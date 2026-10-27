import 'package:flutter/material.dart';
import 'package:hiddify/features/account_lab/account_lab_page.dart';
import 'package:hiddify/features/account_lab/account_protocol.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Dedicated first-device test: no core, telemetry or VPN startup from main.dart.
void main() {
  if (!labEnabled) throw StateError('Explicit debug account lab configuration required');
  runApp(const ProviderScope(child: MaterialApp(debugShowCheckedModeBanner: false, home: AccountLabPage())));
}
