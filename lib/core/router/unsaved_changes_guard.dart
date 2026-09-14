import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef UnsavedChangesHandler = Future<bool> Function();

final unsavedChangesGuardProvider = Provider<UnsavedChangesGuard>((ref) => UnsavedChangesGuard());

class UnsavedChangesGuard {
  final _registrations = <Object, UnsavedChangesHandler>{};
  Future<bool>? _pendingRequest;

  VoidCallback register(UnsavedChangesHandler handler) {
    final registration = Object();
    _registrations[registration] = handler;
    return () => _registrations.remove(registration);
  }

  Future<bool> canLeave() {
    final pendingRequest = _pendingRequest;
    if (pendingRequest != null) return pendingRequest;

    final request = _canLeave().whenComplete(() => _pendingRequest = null);
    _pendingRequest = request;
    return request;
  }

  Future<bool> _canLeave() async {
    for (final handler in _registrations.values.toList().reversed) {
      if (!await handler()) return false;
    }
    return true;
  }
}
