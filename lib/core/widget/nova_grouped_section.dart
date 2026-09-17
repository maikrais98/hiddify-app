import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';

class NovaGroupedSection extends StatelessWidget {
  const NovaGroupedSection({
    super.key,
    required this.children,
    this.title,
    this.footer,
    this.padding = const EdgeInsets.symmetric(horizontal: NovaSpacing.lg),
  });

  final String? title;
  final String? footer;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final nova = NovaThemeData.of(context);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(NovaSpacing.xs, 0, NovaSpacing.xs, NovaSpacing.sm),
              child: Text(
                title!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: nova.secondaryText,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(NovaRadii.large),
            child: Material(
              color: nova.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    children[index],
                    if (index != children.length - 1) Divider(height: 1, indent: 56, color: nova.separator),
                  ],
                ],
              ),
            ),
          ),
          if (footer != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(NovaSpacing.xs, NovaSpacing.sm, NovaSpacing.xs, 0),
              child: Text(footer!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: nova.tertiaryText)),
            ),
          ],
        ],
      ),
    );
  }
}

class NovaSettingsRow extends StatelessWidget {
  const NovaSettingsRow({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.value,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final nova = NovaThemeData.of(context);
    final foreground = destructive ? NovaColors.signalBad : nova.primaryText;
    return ListTile(
      minTileHeight: NovaAccessibilityTokens.minimumTapTarget,
      leading: Icon(icon, color: destructive ? NovaColors.signalBad : nova.secondaryText),
      title: Text(title, style: TextStyle(color: foreground)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(color: nova.secondaryText)),
      trailing:
          trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value != null)
                Flexible(
                  child: Text(
                    value!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: nova.secondaryText),
                  ),
                ),
              if (onTap != null) ...[
                const SizedBox(width: NovaSpacing.xs),
                Icon(Icons.chevron_right_rounded, color: nova.tertiaryText),
              ],
            ],
          ),
      onTap: onTap,
    );
  }
}
