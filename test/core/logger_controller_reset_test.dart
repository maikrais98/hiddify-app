import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:loggy/loggy.dart';

void main() {
  test('reset flushes the file printer and allows initialization to retry', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('logger-controller-reset-');
    addTearDown(() async {
      await LoggerController.reset();
      await tempDirectory.delete(recursive: true);
    });

    final firstLog = File('${tempDirectory.path}/first.log');
    LoggerController.init(firstLog.path);
    Loggy('logger-controller-test').info('first attempt');
    await LoggerController.reset();

    expect(await firstLog.readAsString(), contains('first attempt'));

    final retryLog = File('${tempDirectory.path}/retry.log');
    LoggerController.init(retryLog.path);
    Loggy('logger-controller-test').info('retry attempt');
    await LoggerController.reset();

    expect(await retryLog.readAsString(), contains('retry attempt'));
  });
}
