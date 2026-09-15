import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

String formatStatsValue(
  AsyncValue<SystemInfo> state,
  String Function(SystemInfo stats) format, {
  String placeholder = '—',
}) {
  if (state.isLoading || state.hasError) return placeholder;
  if (state case AsyncData(:final value)) return format(value);
  return placeholder;
}

String? statsStateLabel(AsyncValue<SystemInfo> state, {required String loading, required String unavailable}) {
  if (state.isLoading) return loading;
  if (state.hasError) return unavailable;
  return null;
}
