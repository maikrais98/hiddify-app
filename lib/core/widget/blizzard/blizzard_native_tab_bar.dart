import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BlizzardNativeTabBar extends StatefulWidget {
  const BlizzardNativeTabBar({
    super.key,
    required this.titles,
    required this.selectedIndex,
    required this.tint,
    required this.onDestinationSelected,
  });

  final List<String> titles;
  final int selectedIndex;
  final Color tint;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<BlizzardNativeTabBar> createState() => _BlizzardNativeTabBarState();
}

class _BlizzardNativeTabBarState extends State<BlizzardNativeTabBar> {
  MethodChannel? _channel;
  Map<String, Object>? _lastSentState;
  bool _disposed = false;

  Map<String, Object> get _state => {
    'titles': List<String>.of(widget.titles),
    'selectedIndex': widget.selectedIndex,
    'tint': widget.tint.toARGB32(),
    'dark': Theme.of(context).brightness == Brightness.dark,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sendStateIfChanged();
  }

  @override
  void didUpdateWidget(BlizzardNativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sendStateIfChanged();
  }

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: 'app.blizzard/native-tab-bar',
      creationParams: _state,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }

  void _onPlatformViewCreated(int viewId) {
    if (_disposed) return;
    _channel?.setMethodCallHandler(null);
    final channel = MethodChannel('app.blizzard/native-tab-bar/$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleNativeCall);
    _lastSentState = null;
    _sendStateIfChanged();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (_disposed || !mounted || call.method != 'select') return;
    final arguments = call.arguments;
    if (arguments is! Map) return;
    final index = arguments['index'];
    if (index is! int || index < 0 || index >= widget.titles.length) return;
    if (_disposed || !mounted) return;
    widget.onDestinationSelected(index);
  }

  void _sendStateIfChanged() {
    final channel = _channel;
    if (_disposed || channel == null) return;
    final state = _state;
    if (_sameState(state, _lastSentState)) return;
    _lastSentState = state;
    unawaited(_invokeUpdate(channel, state));
  }

  Future<void> _invokeUpdate(MethodChannel channel, Map<String, Object> state) async {
    try {
      await channel.invokeMethod<void>('update', state);
    } on MissingPluginException {
      // A platform view can disappear while its final state is in flight.
    }
  }

  bool _sameState(Map<String, Object> state, Map<String, Object>? previous) {
    if (previous == null) return false;
    return state['selectedIndex'] == previous['selectedIndex'] &&
        state['tint'] == previous['tint'] &&
        state['dark'] == previous['dark'] &&
        listEquals(state['titles']! as List<String>, previous['titles']! as List<String>);
  }

  @override
  void dispose() {
    _disposed = true;
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }
}
