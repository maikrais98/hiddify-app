import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';

String generateControlSecret() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

CallOptions controlCallOptions(String secret) => CallOptions(metadata: {'authorization': 'Bearer $secret'});

// Trust only the exact certificate returned over FFI/Flutter's native channel.
// Platform PKI verification may reject this deterministic pinned certificate,
// so the fallback compares exact DER bytes instead of bypassing validation.
ChannelCredentials pinnedControlCredentials(List<int> certificate) => _PinnedControlCredentials(certificate);

class _PinnedControlCredentials extends ChannelCredentials {
  final SecurityContext _context;

  _PinnedControlCredentials(List<int> certificate)
    // Keep this explicit: OS roots must never satisfy the loopback pin.
    // ignore: avoid_redundant_argument_values
    : _context = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(certificate)
        ..setAlpnProtocols(const ['grpc-exp', 'h2'], false),
      super.secure(onBadCertificate: (peer, _) => _sameBytes(peer.der, _pemCertificateDer(certificate)));

  @override
  SecurityContext get securityContext => _context;
}

Uint8List _pemCertificateDer(List<int> certificate) {
  final pem = utf8.decode(certificate);
  final encoded = pem
      .replaceAll('-----BEGIN CERTIFICATE-----', '')
      .replaceAll('-----END CERTIFICATE-----', '')
      .replaceAll(RegExp(r'\s'), '');
  return base64Decode(encoded);
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
