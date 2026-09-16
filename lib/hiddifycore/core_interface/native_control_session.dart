import 'package:flutter/services.dart';

final class NativeControlSession {
  const NativeControlSession({required this.generation, required this.controlSecret, required this.certificate});

  final String generation;
  final String controlSecret;
  final Uint8List certificate;

  factory NativeControlSession.fromPlatform(Object? value) {
    if (value case {
      'generation': final String generation,
      'controlSecret': final String controlSecret,
      'certificate': final Uint8List certificate,
    } when generation.isNotEmpty && RegExp(r'^[0-9a-f]{64}$').hasMatch(controlSecret) && certificate.isNotEmpty) {
      return NativeControlSession(generation: generation, controlSecret: controlSecret, certificate: certificate);
    }
    throw StateError('Native control session is unavailable');
  }

  @override
  bool operator ==(Object other) =>
      other is NativeControlSession &&
      generation == other.generation &&
      controlSecret == other.controlSecret &&
      _equalBytes(certificate, other.certificate);

  @override
  int get hashCode => Object.hash(generation, controlSecret, Object.hashAll(certificate));
}

final class NativeControlSessionProvider {
  const NativeControlSessionProvider(this._channel);

  final MethodChannel _channel;

  Future<NativeControlSession> setup(Map<String, Object?> arguments) async {
    final value = await _channel.invokeMethod<Object>('setup', arguments);
    return NativeControlSession.fromPlatform(value);
  }
}

bool _equalBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
