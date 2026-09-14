import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/unsaved_changes_guard.dart';
import 'package:hiddify/features/shortcut/shortcut_wrapper.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('close shortcut waits for the active unsaved-changes guard', (tester) async {
    final harness = await _ShortcutHarness.pump(tester);
    harness.container.read(unsavedChangesGuardProvider).register(() async => false);

    Actions.invoke<CloseWindowIntent>(harness.actionContext, CloseWindowIntent());
    await tester.pump();

    expect(harness.windows.hideCount, 0);
  });

  testWidgets('close shortcut proceeds when there are no unsaved changes', (tester) async {
    final harness = await _ShortcutHarness.pump(tester);

    Actions.invoke<CloseWindowIntent>(harness.actionContext, CloseWindowIntent());
    await tester.pump();

    expect(harness.windows.hideCount, 1);
  });
}

class _ShortcutHarness {
  _ShortcutHarness(this.container, this.windows, this.actionContext);

  final ProviderContainer container;
  final _RecordingWindowNotifier windows;
  final BuildContext actionContext;

  static Future<_ShortcutHarness> pump(WidgetTester tester) async {
    final windows = _RecordingWindowNotifier();
    final container = ProviderContainer(overrides: [windowNotifierProvider.overrideWith(() => windows)]);
    addTearDown(container.dispose);
    late BuildContext actionContext;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShortcutWrapper(
          Builder(
            builder: (context) {
              actionContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    return _ShortcutHarness(container, windows, actionContext);
  }
}

class _RecordingWindowNotifier extends WindowNotifier {
  int hideCount = 0;

  @override
  Future<void> build() async {}

  @override
  Future<void> hide() async {
    hideCount++;
  }
}
