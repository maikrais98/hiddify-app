import 'dart:io';
import 'dart:math';

import 'package:grpc/grpc.dart';

String generateControlSecret() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

CallOptions controlCallOptions(String secret) => CallOptions(metadata: {'authorization': 'Bearer $secret'});

// Trust only the certificate returned over FFI/Flutter's native channel.
// OS roots and onBadCertificate overrides would allow a rogue loopback service.
ChannelCredentials pinnedControlCredentials(List<int> certificate) => _PinnedControlCredentials(certificate);

class _PinnedControlCredentials extends ChannelCredentials {
  // Explicitly pin trust even if the SDK default changes.
  // ignore: avoid_redundant_argument_values
  final SecurityContext _context = SecurityContext(withTrustedRoots: false);

  _PinnedControlCredentials(List<int> certificate) : super.secure() {
    _context.setTrustedCertificatesBytes(certificate);
  }

  @override
  SecurityContext get securityContext => _context;
}
