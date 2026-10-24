import 'dart:async';
import 'dart:convert';

import 'package:hiddify/core/observability/better_stack_log_printer.dart';
import 'package:hiddify/core/observability/telemetry_delivery_status.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_journal.dart';

typedef NativeDiagnosticRead = Future<Object?> Function();

/// Non-destructive bridge reads; remote progress belongs to the durable outbox.
final class NativeDiagnosticImporter {
  NativeDiagnosticImporter({required this.journal, required NativeDiagnosticRead read}) : _read = read;
  final SafeDiagnosticJournal journal;
  final NativeDiagnosticRead _read;
  final Map<String, ({String generation, int sequence, int dropped})> _local = {};
  final Map<String, Map<int, SafeDiagnosticEvent>> _localEvents = {};
  BetterStackLogPrinter? _remote;
  StreamSubscription<TelemetryDeliveryStatus>? _deliverySubscription;
  Future<void> Function()? _onBaselinePersisted;
  List<({String source, String generation, int sequence})>? _baseline;
  bool _baselineSaved = false;
  Future<bool> Function(String)? _persistBaseline;

  Future<String> captureBaseline() async {
    final sources = _parse(await _read());
    if (sources.length != 2 || sources.any((source) => source.storageFailed)) {
      throw StateError('native baseline unavailable');
    }
    return _encodeBaseline([
      for (final source in sources) (source: source.source, generation: source.generation, sequence: source.last),
    ]);
  }

  static bool isValidBaseline(Object? value) {
    if (value is! String) return false;
    try {
      _decodeBaseline(value);
      return true;
    } on Object {
      return false;
    }
  }

  static String _encodeBaseline(List<({String source, String generation, int sequence})> sources) => jsonEncode({
    'version': 1,
    'sources': [
      for (final source in sources)
        {'source': source.source, 'generation': source.generation, 'sequence': source.sequence},
    ],
  });

  static List<({String source, String generation, int sequence})> _decodeBaseline(String value) {
    final raw = jsonDecode(value);
    if (raw is! Map ||
        !_keys(raw, {'version', 'sources'}) ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['sources'] is! List ||
        (raw['sources'] as List).length != 2) {
      throw const FormatException('invalid native baseline');
    }
    final result = <({String source, String generation, int sequence})>[];
    final seen = <String>{};
    for (final item in raw['sources'] as List) {
      if (item is! Map || !_keys(item, {'source', 'generation', 'sequence'})) {
        throw const FormatException('invalid native baseline');
      }
      final source = item['source'];
      final generation = item['generation'];
      final sequence = item['sequence'];
      if (source is! String ||
          !{'runner', 'extension'}.contains(source) ||
          !seen.add(source) ||
          generation is! String ||
          !RegExp(r'^[0-9a-f]{16}$').hasMatch(generation) ||
          !_counter(sequence)) {
        throw const FormatException('invalid native baseline');
      }
      result.add((source: source, generation: generation, sequence: sequence as int));
    }
    return result;
  }

  Future<void> _pending = Future.value();
  bool _disposed = false;
  bool readFailed = false;
  bool sourceStorageFailed = false;
  bool deliveryFailed = false;
  bool baselinePending = false;
  int droppedCount = 0;
  bool historyGap = false;
  final StreamController<void> _changes = StreamController.broadcast();
  Stream<void> get changes => _changes.stream;

  Future<void> attachRemote(
    BetterStackLogPrinter remote, {
    bool baseline = false,
    String? persistedBaseline,
    Future<bool> Function(String)? persistBaseline,
    Future<void> Function()? onBaselinePersisted,
  }) {
    final frozen = persistedBaseline == null ? null : _decodeBaseline(persistedBaseline);
    detachRemote();
    _remote = remote;
    _deliverySubscription = remote.deliveryStatuses.listen((status) {
      if (_remote == remote && status.state == TelemetryDeliveryState.accepted) unawaited(refresh());
    });
    baselinePending = baseline;
    _baseline = frozen;
    _baselineSaved = persistedBaseline != null;
    _persistBaseline = persistBaseline;
    _onBaselinePersisted = onBaselinePersisted;
    return refresh();
  }

  void detachRemote() {
    unawaited(_deliverySubscription?.cancel());
    _deliverySubscription = null;
    _remote = null;
    _baseline = null;
    _baselineSaved = false;
    _persistBaseline = null;
    baselinePending = false;
    _onBaselinePersisted = null;
  }

  void dispose() {
    _disposed = true;
    detachRemote();
    unawaited(_changes.close());
  }

  Future<void> refresh() {
    final operation = _pending.then((_) => _refresh());
    _pending = operation;
    return operation;
  }

  Future<void> _refresh() async {
    if (_disposed) return;
    try {
      final sources = _parse(await _read());
      if (_disposed) return;
      readFailed = false;
      sourceStorageFailed = sources.any((source) => source.storageFailed);
      droppedCount = sources.fold(0, (count, source) => count + source.dropped);
      final remote = _remote;
      for (final source in sources) {
        final durable = remote?.importedSourceCursor(source.source);
        final local = _local[source.source];
        final generation = durable?.generation ?? local?.generation;
        final sequence = durable?.sequence ?? local?.sequence ?? 0;
        if ((generation != null && generation != source.generation) ||
            (source.events.isNotEmpty && source.events.first.sequence > sequence + 1)) {
          historyGap = true;
        }
      }
      final callback = _onBaselinePersisted;
      if (remote != null && baselinePending) {
        if (sourceStorageFailed || sources.length != 2) {
          deliveryFailed = true;
          _importLocal(sources);
          return;
        }
        // Freeze the first valid enable snapshot. A failed save must not move
        // the baseline forward and silently skip subsequently observed events.
        _baseline ??= [
          for (final source in sources) (source: source.source, generation: source.generation, sequence: source.last),
        ];
        if (!_baselineSaved) {
          final save = _persistBaseline;
          if (save != null && !await save(_encodeBaseline(_baseline!))) {
            deliveryFailed = true;
            _importLocal(sources);
            return;
          }
          if (_remote != remote || _disposed) return;
          _baselineSaved = true;
        }
        for (final source in _baseline!) {
          final outcome = await remote.baselineImportedSource(
            source: source.source,
            generation: source.generation,
            sourceSequence: source.sequence,
          );
          if (_remote != remote || _disposed) return;
          if (!_committed(outcome)) {
            deliveryFailed = true;
            _importLocal(sources);
            return;
          }
        }
        if (callback != null) await callback();
        if (_remote != remote || _disposed) return;
        baselinePending = false;
        _baseline = null;
      }
      deliveryFailed = false;
      for (final source in sources) {
        for (final record in source.events) {
          final localEvent = _importOne(source, record);
          if (remote != null && _remote == remote && !baselinePending) {
            final outcome = await remote.addImportedDiagnostic(
              localEvent,
              source: source.source,
              generation: source.generation,
              sourceSequence: record.sequence,
            );
            if (_remote != remote || _disposed) return;
            if (!_committed(outcome)) {
              deliveryFailed = true;
              // Do not skip later source records past a failed handoff.
              _importLocal(sources);
              return;
            }
          }
        }
      }
    } on Object {
      // Bridge/persistence faults never affect connection or analytics actions.
      readFailed = true;
    } finally {
      if (!_disposed) _changes.add(null);
    }
  }

  static bool _committed(DiagnosticEnqueueResult result) =>
      result == DiagnosticEnqueueResult.persisted || result == DiagnosticEnqueueResult.alreadyPersisted;

  void _importLocal(List<_Source> sources) {
    for (final source in sources) {
      for (final event in source.events) {
        _importOne(source, event);
      }
    }
  }

  SafeDiagnosticEvent _importOne(_Source source, SafeDiagnosticEvent event) {
    final previous = _local[source.source];
    if (previous?.generation != source.generation) _localEvents.remove(source.source);
    final remembered = _localEvents.putIfAbsent(source.source, () => {});
    final cached = remembered[event.sequence];
    if (cached != null) return cached;
    final imported = journal.importNative(event);
    remembered[event.sequence] = imported;
    if (remembered.length > SafeDiagnosticJournal.maxCapacity) remembered.remove(remembered.keys.first);
    _local[source.source] = (generation: source.generation, sequence: event.sequence, dropped: source.dropped);
    return imported;
  }

  static List<_Source> _parse(Object? raw) {
    if (raw is! Map ||
        !_keys(raw, {'version', 'sources'}) ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['sources'] is! List ||
        (raw['sources'] as List).length > 2) {
      throw const FormatException('invalid native snapshot');
    }
    // Only primitive closed values are serialized here; reject malformed values
    // before any event can be added to the local or remote journal.
    final result = <_Source>[];
    final seen = <String>{};
    for (final item in raw['sources'] as List) {
      if (item is! Map ||
          !_keys(item, {
            'source',
            'generation',
            'first_sequence',
            'last_sequence',
            'dropped_count',
            'storage_failed',
            'records',
          })) {
        throw const FormatException('invalid native source');
      }
      final source = item['source'];
      final generation = item['generation'];
      final first = item['first_sequence'];
      final last = item['last_sequence'];
      final dropped = item['dropped_count'];
      final storage = item['storage_failed'];
      final records = item['records'];
      if ((source != 'runner' && source != 'extension') ||
          source is! String ||
          !seen.add(source) ||
          generation is! String ||
          !RegExp(r'^[0-9a-f]{16}$').hasMatch(generation) ||
          first is! int ||
          last is! int ||
          dropped is! int ||
          !_counter(first) ||
          !_counter(last) ||
          !_counter(dropped) ||
          storage is! bool ||
          records is! List ||
          records.length > 128 ||
          first > last ||
          (records.isEmpty ? first != 0 : first == 0)) {
        throw const FormatException('invalid native source value');
      }
      final events = <SafeDiagnosticEvent>[];
      var previous = first - 1;
      for (final record in records) {
        if (record is! Map || !_keys(record, {'source_sequence', 'event'}) || record['event'] is! Map) {
          throw const FormatException('invalid native record');
        }
        final event = SafeDiagnosticEvent.fromJson(Map<String, Object?>.from(record['event'] as Map));
        if (record['source_sequence'] != event.sequence ||
            event.sequence != previous + 1 ||
            event.operation != DiagnosticOperation.native ||
            event.operationId != 0) {
          throw const FormatException('invalid native sequence');
        }
        previous = event.sequence;
        events.add(event);
      }
      if (events.isNotEmpty && events.last.sequence != last) throw const FormatException('invalid native tail');
      if (utf8.encode(jsonEncode(item)).length > SafeDiagnosticJournal.maxEncodedBytes + 1024) {
        throw const FormatException('oversized native source');
      }
      result.add(_Source(source, generation, last, dropped, storage, events));
    }
    return result;
  }

  static bool _keys(Map raw, Set<String> keys) => raw.length == keys.length && raw.keys.every(keys.contains);
  static bool _counter(Object? value) => value is int && value >= 0 && value <= SafeDiagnosticEvent.maxCounter;
}

final class _Source {
  const _Source(this.source, this.generation, this.last, this.dropped, this.storageFailed, this.events);
  final String source;
  final String generation;
  final int last;
  final int dropped;
  final bool storageFailed;
  final List<SafeDiagnosticEvent> events;
}
