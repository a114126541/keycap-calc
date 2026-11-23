import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.value,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? subtitle;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        minLeadingWidth: 24,
        minTileHeight: 54,
        minVerticalPadding: 10,
        leading: Icon(icon, size: 22),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value case final current?) ...[
              ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: constraints.maxWidth * .4),
                child: Text(
                  current,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(LucideIcons.chevronRight, size: 18),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
