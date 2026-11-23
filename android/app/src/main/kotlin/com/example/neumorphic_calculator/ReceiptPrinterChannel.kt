package com.ragheb.neumorphic_calculator

import android.Manifest
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.CharBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

internal class ReceiptPrinterChannel(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "keycap_calc/receipt_printer")
    private val io = Executors.newSingleThreadExecutor()
    private val usbManager get() = activity.getSystemService(Context.USB_SERVICE) as UsbManager
    private val usbPermissionAction = "${activity.packageName}.RECEIPT_USB_PERMISSION"
    private var bluetoothRequest: PermissionRequest? = null
    private var usbReceiver: BroadcastReceiver? = null
    private var usbResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "encode" -> reply(result) {
                encode(call.argument<String>("text").orEmpty(), call.argument<String>("encoding"))
            }
            "devices" -> when (call.argument<String>("connection")) {
                "bluetooth" -> withBluetoothPermission(result) {
                    reply(result) {
                        bluetooth().bondedDevices
                            .filter { it.type != BluetoothDevice.DEVICE_TYPE_LE }
                            .map { mapOf("address" to it.address, "name" to (it.name ?: it.address)) }
                            .sortedBy { it["name"] }
                    }
                }
                "usb" -> reply(result) {
                    usbPorts().map { mapOf("address" to it.address, "name" to it.name) }
                }
                else -> result.error("unavailable", null, null)
            }
            "send" -> {
                val address = call.argument<String>("address")
                val data = call.argument<ByteArray>("data")
                if (address.isNullOrEmpty() || data == null || data.isEmpty()) {
                    result.error("unavailable", null, null)
                    return
                }
                when (call.argument<String>("connection")) {
                    "bluetooth" -> withBluetoothPermission(result) {
                        onWorker(result) { sendBluetooth(address, data) }
                    }
                    "usb" -> sendUsbWithPermission(address, data, result)
                    else -> result.error("unavailable", null, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun encode(text: String, encoding: String?): ByteArray? {
        val charset = when (encoding) {
            "gbk" -> charset("GBK")
            "big5" -> charset("Big5")
            else -> throw PrinterError("encoding")
        }
        return try {
            val buffer = charset.newEncoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .encode(CharBuffer.wrap(text))
            val bytes = ByteArray(buffer.remaining()).also { buffer.get(it) }
            bytes.takeIf { it.toString(charset) == text }
        } catch (_: CharacterCodingException) {
            null
        }
    }

    private fun withBluetoothPermission(result: MethodChannel.Result, action: () -> Unit) {
        if (Build.VERSION.SDK_INT >= 31 &&
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            if (bluetoothRequest != null) {
                result.error("busy", null, null)
                return
            }
            bluetoothRequest = PermissionRequest(result, action)
            try {
                activity.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), BLUETOOTH_REQUEST)
            } catch (_: Exception) {
                bluetoothRequest = null
                result.error("permission", null, null)
            }
        } else {
            action()
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grants: IntArray) {
        if (requestCode != BLUETOOTH_REQUEST) return
        val request = bluetoothRequest ?: return
        bluetoothRequest = null
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            request.action()
        } else {
            request.result.error("permission", null, null)
        }
    }

    private fun bluetooth(): BluetoothAdapter {
        val adapter = (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        if (adapter == null || !adapter.isEnabled) throw PrinterError("bluetooth")
        return adapter
    }

    private fun sendBluetooth(address: String, data: ByteArray) {
        val device = bluetooth().bondedDevices.firstOrNull { it.address == address }
            ?: throw PrinterError("unavailable")
        val socket = device.createRfcommSocketToServiceRecord(SERIAL_PORT)
        val timer = Executors.newSingleThreadScheduledExecutor()
        val timeout = timer.schedule({ runCatching { socket.close() } }, 22, TimeUnit.SECONDS)
        try {
            try {
                socket.connect()
            } catch (_: Exception) {
                throw PrinterError("unavailable")
            }
            try {
                socket.outputStream.write(data)
                socket.outputStream.flush()
            } catch (_: Exception) {
                throw PrinterError("uncertain")
            }
        } finally {
            timeout.cancel(false)
            timer.shutdownNow()
            runCatching { socket.close() }
        }
    }

    private fun usbPorts(): List<UsbPort> {
        return usbManager.deviceList.values.mapNotNull { device ->
            val ports = (0 until device.interfaceCount).mapNotNull interfacePort@{ index ->
                val intf = device.getInterface(index)
                val endpoint = (0 until intf.endpointCount)
                    .map(intf::getEndpoint)
                    .firstOrNull {
                        it.type == UsbConstants.USB_ENDPOINT_XFER_BULK && it.direction == UsbConstants.USB_DIR_OUT
                    } ?: return@interfacePort null
                UsbPort(device, intf, endpoint)
            }
            ports.firstOrNull { it.intf.interfaceClass == UsbConstants.USB_CLASS_PRINTER }
                ?: ports.firstOrNull {
                    it.intf.interfaceClass == UsbConstants.USB_CLASS_VENDOR_SPEC &&
                        PRINTER_NAME.containsMatchIn(it.name)
                }
        }.sortedBy { it.name }
    }

    private fun sendUsbWithPermission(address: String, data: ByteArray, result: MethodChannel.Result) {
        val ports = usbPorts()
        val port = ports.firstOrNull { it.address == address }
            ?: ports.filter { it.model == address.substringBefore('/') }.singleOrNull()
        if (port == null) {
            result.error("unavailable", null, null)
            return
        }
        if (usbManager.hasPermission(port.device)) {
            onWorker(result) { sendUsb(port, data) }
            return
        }
        if (usbReceiver != null) {
            result.error("busy", null, null)
            return
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != usbPermissionAction) return
                clearUsbRequest()
                if (!usbManager.hasPermission(port.device)) {
                    result.error("permission", null, null)
                } else {
                    onWorker(result) { sendUsb(port, data) }
                }
            }
        }
        try {
            val filter = IntentFilter(usbPermissionAction)
            if (Build.VERSION.SDK_INT >= 33) {
                activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                activity.registerReceiver(receiver, filter)
            }
            usbReceiver = receiver
            usbResult = result
            val intent = Intent(usbPermissionAction).setPackage(activity.packageName)
            val pending = PendingIntent.getBroadcast(
                activity, 0, intent, PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE,
            )
            usbManager.requestPermission(port.device, pending)
        } catch (_: Exception) {
            clearUsbRequest()
            result.error("permission", null, null)
        }
    }

    private fun clearUsbRequest() {
        usbReceiver?.let(activity::unregisterReceiver)
        usbReceiver = null
        usbResult = null
    }

    private fun sendUsb(port: UsbPort, data: ByteArray) {
        val connection = usbManager.openDevice(port.device) ?: throw PrinterError("unavailable")
        try {
            if (!connection.claimInterface(port.intf, true)) throw PrinterError("unavailable")
            try {
                var offset = 0
                val due = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
                while (offset < data.size) {
                    val remaining = TimeUnit.NANOSECONDS.toMillis(due - System.nanoTime())
                    if (remaining <= 0L) throw PrinterError("uncertain")
                    val written = connection.bulkTransfer(
                        port.endpoint, data, offset, minOf(4096, data.size - offset),
                        minOf(4000L, remaining).toInt().coerceAtLeast(1),
                    )
                    if (written <= 0) throw PrinterError("uncertain")
                    offset += written
                }
            } catch (_: Exception) {
                throw PrinterError("uncertain")
            } finally {
                connection.releaseInterface(port.intf)
            }
        } finally {
            connection.close()
        }
    }

    private fun onWorker(result: MethodChannel.Result, transfer: () -> Unit) {
        io.execute {
            reply(result) {
                transfer()
                null
            }
        }
    }

    private fun reply(result: MethodChannel.Result, action: () -> Any?) {
        try {
            result.success(action())
        } catch (error: PrinterError) {
            result.error(error.code, null, null)
        } catch (_: SecurityException) {
            result.error("permission", null, null)
        } catch (_: Exception) {
            result.error("unavailable", null, null)
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        bluetoothRequest?.result?.error("unavailable", null, null)
        bluetoothRequest = null
        usbResult?.error("unavailable", null, null)
        clearUsbRequest()
        io.shutdown()
    }

    private class PrinterError(val code: String) : RuntimeException(code)
    private data class PermissionRequest(val result: MethodChannel.Result, val action: () -> Unit)
    private data class UsbPort(val device: UsbDevice, val intf: UsbInterface, val endpoint: UsbEndpoint) {
        val model = "%04X:%04X".format(device.vendorId, device.productId)
        val address = "$model${device.deviceName}"
        val name = listOfNotNull(device.manufacturerName, device.productName)
            .map { it.substringBefore('\u0000').trim() }
            .filter { it.isNotEmpty() }
            .distinct().joinToString(" ").ifBlank { "USB $model" }
    }

    private companion object {
        const val BLUETOOTH_REQUEST = 6817
        val SERIAL_PORT: UUID = UUID.fromString("00001101-0000-1000-8000-00805f9b34fb")
        val PRINTER_NAME = Regex("printer|thermal|pos|sprt|sprinter|epson|gainscha|佳博|打印|思普瑞特|爱普生", RegexOption.IGNORE_CASE)
    }
}
