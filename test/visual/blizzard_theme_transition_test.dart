import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';

void main() => registerBlizzardThemeTransitions();

void registerBlizzardThemeTransitions() {
  testWidgets('actual Material typography transitions both ways without losing field draft', (tester) async {
    final base = AppTheme(AppThemeMode.dark, 'Roboto').darkTheme(null);
    final scoped = BlizzardTheme.from(base);
    final enabled = ValueNotifier(false);
    final draft = TextEditingController(text: 'Unchanged draft');
    final focus = FocusNode();
    await tester.pumpWidget(MaterialApp(
      theme: base,
      home: ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (context, active, child) => Theme(
          data: active ? scoped : base,
          child: Material(child: Column(children: [
            const ListTile(title: Text('Theme transition'), subtitle: Text('Same content')),
            TextField(controller: draft, focusNode: focus),
            TextButton(onPressed: () {}, child: const Text('Same action')),
          ])),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    for (final active in [true, false, true]) {
      enabled.value = active;
      await tester.pump();
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      expect(editor.controller, same(draft));
      expect(editor.focusNode, same(focus));
      expect(editor.controller.text, 'Unchanged draft');
      expect(editor.focusNode.hasFocus, true);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    enabled.dispose();
    draft.dispose();
    focus.dispose();
  });
}
