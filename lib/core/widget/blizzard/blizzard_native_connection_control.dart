import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BlizzardRootRouteVisibility extends InheritedWidget {
  const BlizzardRootRouteVisibility({
    super.key,
    required this.visible,
    this.route,
    this.homeVisible,
    required super.child,
  });

  final bool visible;
  final ModalRoute<dynamic>? route;
  final bool? homeVisible;

  static bool of(BuildContext context) {
    final visibility = context.dependOnInheritedWidgetOfExactType<BlizzardRootRouteVisibility>();
    return (visibility?.visible ?? true) && (visibility?.route?.isCurrent ?? true);
  }

  static bool homeIsVisible(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BlizzardRootRouteVisibility>()?.homeVisible ?? TickerMode.of(context);

  @override
  bool updateShouldNotify(BlizzardRootRouteVisibility oldWidget) =>
      visible != oldWidget.visible || route != oldWidget.route || homeVisible != oldWidget.homeVisible;
}

class BlizzardNativeConnectionControl extends StatefulWidget {
  const BlizzardNativeConnectionControl({
    super.key,
    required this.enabled,
    required this.label,
    required this.connectionState,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final String connectionState;
  final VoidCallback onPressed;

  @override
  State<BlizzardNativeConnectionControl> createState() => _BlizzardNativeConnectionControlState();
}

class _BlizzardNativeConnectionControlState extends State<BlizzardNativeConnectionControl> with WidgetsBindingObserver {
  MethodChannel? _channel;
  Map<String, Object>? _lastSentState;
  late Map<String, Object> _currentState;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _routeVisible = true;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _currentState = {
      'enabled': widget.enabled,
      'visible': _lifecycle == AppLifecycleState.resumed,
      'interactionAllowed': _lifecycle == AppLifecycleState.resumed,
      'label': widget.label,
      'connectionState': widget.connectionState,
    };
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A translucent root popup covers Home without removing its visual lens.
    // Tab/offstage and lifecycle visibility remain independent of interaction.
    _routeVisible = (ModalRoute.of(context)?.isCurrent ?? true) && BlizzardRootRouteVisibility.homeIsVisible(context);
    _refreshState();
  }

  @override
  void didUpdateWidget(BlizzardNativeConnectionControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lifecycle == state || _disposed) return;
    _lifecycle = state;
    _refreshState();
  }

  Map<String, Object> _state() => {
    'enabled': widget.enabled,
    'visible': _routeVisible && _lifecycle == AppLifecycleState.resumed,
    'interactionAllowed':
        _routeVisible && _lifecycle == AppLifecycleState.resumed && BlizzardRootRouteVisibility.of(context),
    'label': widget.label,
    'connectionState': widget.connectionState,
  };

  void _refreshState() {
    _currentState = _state();
    _sendStateIfChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return const SizedBox.shrink();
    return UiKitView(
      viewType: 'app.blizzard/native-connection-control',
      creationParams: Map<String, Object>.of(_currentState),
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }

  void _onPlatformViewCreated(int viewId) {
    if (_disposed) return;
    _channel?.setMethodCallHandler(null);
    final channel = MethodChannel('app.blizzard/native-connection-control/$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleNativeCall);
    _lastSentState = null;
    _sendStateIfChanged();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (_disposed || !mounted || call.method != 'pressed') return;
    if (_currentState['enabled'] != true ||
        _currentState['visible'] != true ||
        _currentState['interactionAllowed'] != true ||
        !_isAvailableNow()) {
      // A UIKit callback may already be queued when a root sheet is pushed,
      // before the inherited route visibility has rebuilt this platform view.
      if (_currentState['interactionAllowed'] == true && !_isAvailableNow()) {
        _currentState = Map<String, Object>.of(_currentState)..['interactionAllowed'] = false;
        _sendStateIfChanged();
      }
      return;
    }
    widget.onPressed();
  }

  bool _isAvailableNow() =>
      _lifecycle == AppLifecycleState.resumed &&
      BlizzardRootRouteVisibility.of(context) &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.of(context);

  void _sendStateIfChanged() {
    final channel = _channel;
    if (_disposed || channel == null || mapEquals(_currentState, _lastSentState)) return;
    final state = Map<String, Object>.of(_currentState);
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

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }
}
