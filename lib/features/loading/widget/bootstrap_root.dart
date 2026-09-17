import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hiddify/features/loading/widget/matrix_loading_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef AppInitializer = Future<ProviderContainer> Function();
typedef InitializedAppBuilder = Widget Function(ProviderContainer container);

class BootstrapRoot extends StatefulWidget {
  const BootstrapRoot({
    required this.initialize,
    this.minimumDuration = const Duration(seconds: 1),
    this.appBuilder,
    this.onFirstFrame,
    super.key,
  });

  final AppInitializer initialize;
  final Duration minimumDuration;
  final InitializedAppBuilder? appBuilder;
  final VoidCallback? onFirstFrame;

  @override
  State<BootstrapRoot> createState() => _BootstrapRootState();
}

class _BootstrapRootState extends State<BootstrapRoot> {
  late Future<ProviderContainer> _initialization;
  ProviderContainer? _container;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.onFirstFrame case final onFirstFrame?) {
        onFirstFrame();
      } else if (!kIsWeb) {
        FlutterNativeSplash.remove();
      }
    });
  }

  Future<ProviderContainer> _initialize() async {
    await Future<void>.delayed(Duration.zero);
    final initialization = widget.initialize();
    await Future.wait<void>([initialization.then((_) {}), Future<void>.delayed(widget.minimumDuration)]);
    final container = await initialization;
    if (!mounted) {
      container.dispose();
      return container;
    }
    _container = container;
    return container;
  }

  void _retry() {
    final completer = Completer<ProviderContainer>();
    setState(() {
      _initialization = completer.future;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      completer.complete(_initialize());
    });
  }

  @override
  void dispose() {
    _container?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProviderContainer>(
      future: _initialization,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.hasData) {
          child = KeyedSubtree(
            key: const ValueKey('initialized-app'),
            child: widget.appBuilder?.call(snapshot.requireData) ?? const SizedBox.shrink(),
          );
        } else {
          child = MaterialApp(
            key: const ValueKey('loading-app'),
            debugShowCheckedModeBanner: false,
            theme: ThemeData(brightness: Brightness.dark, colorSchemeSeed: const Color(0xFFB40D3A)),
            home: MatrixLoadingScreen(
              error: snapshot.hasError ? snapshot.error : null,
              onRetry: snapshot.hasError ? _retry : null,
            ),
          );
        }

        return AnimatedSwitcher(duration: const Duration(milliseconds: 260), child: child);
      },
    );
  }
}
