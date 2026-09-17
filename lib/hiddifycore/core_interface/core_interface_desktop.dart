import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/gen/hiddify_core_generated_bindings.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/core_interface/local_control_credentials.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello_service.pbgrpc.dart';
import 'package:hiddify/utils/custom_loggers.dart';

import 'package:loggy/loggy.dart';

import 'package:path/path.dart' as p;

final _logger = Loggy('HiddifyCoreFFI');
typedef StopFunc = Pointer<Utf8> Function();
typedef StopFuncDart = Pointer<Utf8> Function();

class CoreInterfaceDesktop extends CoreInterface with InfraLogger {
  static final HiddifyCoreNativeLibrary _box = _gen();

  static HiddifyCoreNativeLibrary _gen() {
    String fullPath = "";
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      fullPath = "hiddify-core";
    }
    if (Platform.isWindows) {
      fullPath = p.join(fullPath, "hiddify-core.dll");
    } else if (Platform.isMacOS) {
      fullPath = p.join(fullPath, "hiddify-core.dylib");
    } else {
      fullPath = p.join(fullPath, "hiddify-core.so");
    }

    _logger.debug('hiddify-core native libs path: "$fullPath"');
    final lib = DynamicLibrary.open(fullPath);
    // final stopFunc = lib.lookup<NativeFunction<StopFunc>>('stop').asFunction<StopFunc>();
    // final errPtr2 = stopFunc();
    // final err = errPtr2.cast<Utf8>().toDartString();

    return HiddifyCoreNativeLibrary(lib);
  }

  Future<bool> isMusl() async {
    try {
      final result = await Process.run('ldd', ['--version']);
      return result.stdout.toString().toLowerCase().contains('musl');
    } catch (_) {
      return false;
    }
  }

  final port = 17078;
  static final String secret = generateControlSecret();

  @override
  Future<String> setup(Directories directories, bool debug, int mode) async {
    final errPtr = _box.setup(
      directories.baseDir.path.toNativeUtf8().cast(),
      directories.workingDir.path.toNativeUtf8().cast(),
      directories.tempDir.path.toNativeUtf8().cast(),
      SetupMode.GRPC_NORMAL_INSECURE.value,
      "127.0.0.1:$port".toNativeUtf8().cast(),
      secret.toNativeUtf8().cast(),
      0,
      debug ? 1 : 0,
    );
    final err = errPtr.cast<Utf8>().toDartString();

    if (err.isNotEmpty) {
      return err;
    }

    final certificate = _box.GetServerPublicKey().cast<Utf8>().toDartString();
    final channel = ClientChannel(
      '127.0.0.1',
      port: port,
      options: ChannelOptions(credentials: pinnedControlCredentials(utf8.encode(certificate))),
    );
    final options = controlCallOptions(secret);
    await HelloClient(channel, options: options).sayHello(
      HelloRequest(name: "app"),
      options: CallOptions(timeout: const Duration(seconds: 5)),
    );
    bgClient = fgClient = CoreClient(channel, options: options);

    return "";
  }

  @override
  Future<bool> restart(String path, String name) async {
    return false;
  }

  @override
  Future<bool> stop() async {
    return false;
  }
}
