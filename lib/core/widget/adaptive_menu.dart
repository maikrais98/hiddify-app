import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef AdaptiveMenuBuilder = Widget Function(BuildContext context, void Function() toggleVisibility, Widget? child);

MenuThemeData get blizzardPopupMenuTheme => const MenuThemeData(
  style: MenuStyle(
    backgroundColor: WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
    shadowColor: WidgetStatePropertyAll(Colors.transparent),
    elevation: WidgetStatePropertyAll(0),
    padding: WidgetStatePropertyAll(EdgeInsets.zero),
  ),
);

/// One native material owner for a complete anchored popup. Individual menu
/// items remain ordinary Flutter actions and do not each sample the backdrop.
class BlizzardPopupMenuSurface extends StatelessWidget {
  const BlizzardPopupMenuSurface({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => BlizzardGlass(
    active: true,
    radius: BlizzardRadii.row,
    contentSurface: true,
    child: Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ),
  );
}

class AdaptiveMenuItem<T> {
  AdaptiveMenuItem({required this.title, this.icon, this.onTap, this.isSelected, this.subItems});

  final String title;
  final IconData? icon;
  final T Function()? onTap;
  final bool? isSelected;
  final List<AdaptiveMenuItem>? subItems;

  (String, IconData?, T Function()?, bool?, List<AdaptiveMenuItem>?) _equality() =>
      (title, icon, onTap, isSelected, subItems);

  @override
  bool operator ==(covariant AdaptiveMenuItem other) {
    if (identical(this, other)) return true;
    return other._equality() == _equality();
  }

  @override
  int get hashCode => _equality().hashCode;
}

class AdaptiveMenu extends HookConsumerWidget {
  const AdaptiveMenu({super.key, required this.items, required this.builder, required this.child});

  final Iterable<AdaptiveMenuItem> items;
  final AdaptiveMenuBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    List<Widget> buildMenuItems(Iterable<AdaptiveMenuItem> scopeItems) {
      final menuItems = <Widget>[];
      for (final item in scopeItems) {
        if (item.subItems != null) {
          final subItems = buildMenuItems(item.subItems!);
          menuItems.add(
            SubmenuButton(
              menuChildren: subItems,
              leadingIcon: item.icon != null ? BlizzardSystemSymbol(icon: item.icon!) : null,
              child: Text(item.title),
            ),
          );
        } else {
          menuItems.add(
            MenuItemButton(
              leadingIcon: item.icon != null ? BlizzardSystemSymbol(icon: item.icon!) : null,
              onPressed: item.onTap,
              child: Text(item.title),
            ),
          );
        }
      }
      return menuItems;
    }

    return MenuAnchor(
      builder: (context, controller, child) => builder(context, () {
        if (controller.isOpen) {
          controller.close();
        } else {
          controller.open();
        }
      }, child),
      menuChildren: buildMenuItems(items),
      child: child,
    );
  }
}
