import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

extension RefLifeCycle<T> on Ref<T> {
  void disposeDelay(Duration duration) {
    final link = keepAlive();
    Timer? timer;
    var disposed = false;

    onCancel(() {
      if (disposed) return;
      timer?.cancel();
      timer = Timer(duration, link.close);
    });

    onDispose(() {
      disposed = true;
      timer?.cancel();
    });

    onResume(() {
      timer?.cancel();
    });
  }
}
