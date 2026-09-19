import 'dart:async';

import 'package:hiddify/hiddifycore/core_interface/native_tunnel_failure.dart';
import 'package:hiddify/singbox/model/core_status.dart';

Stream<CoreStatus> routeNativeStatusEvents(
  Stream<dynamic> events, {
  required String? Function() activeOperationId,
  required void Function(NativeTunnelFailure failure) onFailure,
}) => events.transform(
  StreamTransformer<dynamic, CoreStatus>.fromHandlers(
    handleData: (event, sink) {
      final failure = NativeTunnelFailure.fromEvent(event);
      if (failure != null) {
        if (!failure.belongsTo(activeOperationId())) return;
        onFailure(failure);
        sink.add(CoreStatus.stopped(alert: CoreAlert.startFailed, message: failure.safeMessage));
        return;
      }
      sink.add(CoreStatus.fromEvent(event));
    },
  ),
);
