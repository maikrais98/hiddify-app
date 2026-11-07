import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';
Future<void> main()=>integrationDriver(responseDataCallback:(data)async{
  final plates=(data!['plates'] as Map).cast<String,List<dynamic>>();
  for(final e in plates.entries){
    await File('/workspace/user/Documents/KVN/design-assets/luma-v01/current-runtime-2026-10-25/luma-aurora-${e.key}.png').writeAsBytes(e.value.cast<int>());
  }
});
