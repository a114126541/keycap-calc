# Keycap Calc

English · [简体中文](README.zh-CN.md)

Keycap Calc is an Android calculator built with Flutter. It has portrait and landscape layouts, themes inspired by physical calculators, and settings for key style and corner radius.

## Screenshots

The screenshots show **Ivory Desk** with the **3D Keycap** style and a **25 dp** corner radius.

### Landscape

<img src="screenshots/keycap-calc-ivory-3d-landscape.png" alt="Keycap Calc in landscape with the Ivory Desk theme and 3D keycaps" width="820">

### Portrait

<img src="screenshots/keycap-calc-ivory-3d-portrait.png" alt="Keycap Calc in portrait with the Ivory Desk theme and 3D keycaps" width="330">

## Features

- **Four columns in portrait and five in landscape.** Rotating the screen keeps the current expression.
- **Light, dark, and system modes.** Themes inspired by physical calculators have their own key colors and LCD-style displays.
- **Five key styles** include Original, Flat, 2.5D Keycap, 3D Keycap, and Frosted Glass. Set the corner radius and font separately.
- **Live results**, parentheses, percentages, and calculation history. Tap Backspace to delete one character or hold it to clear the expression.

## Run locally

The build has been tested with Flutter 3.32.8, JDK 17, and Android SDK Platform 35. Connect an Android device or start an emulator, then run these commands.

```bash
git clone https://github.com/a114126541/keycap-calc.git
cd keycap-calc
flutter pub get
flutter run
```

Use `flutter test` to run the test suite. `flutter build apk --release` saves the APK in `build/app/outputs/flutter-apk/`.

To install Keycap Calc alongside the original app, build a preview APK with a separate application ID.

```bash
ORG_GRADLE_PROJECT_calculatorPreview=true flutter build apk --release --target-platform android-arm64
```

## License and credits

gospursgo maintains Keycap Calc. The app is based on Neumorphic Calculator by Mohammed Ragheb. [Maintainer](https://github.com/a114126541) · [Upstream project](https://github.com/mllrr96/Neumorphic-Calculator)

The repository includes the original copyright notice, **Copyright (c) 2024 Mohammed Ragheb**, and the full MIT License. [LICENSE](LICENSE)
