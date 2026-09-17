import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'nova_pen_frame_registry.dart';

void main() {
  test('registry covers every numbered frame in the live Pen document', () {
    expect(novaPenFrameFixtures, hasLength(40));
    expect(novaPenFrameFixtures.map((frame) => frame.id).toSet(), hasLength(40));
    expect(
      novaPenFrameFixtures.map((frame) => frame.id).toSet(),
      equals({
        '01',
        '02',
        '02a',
        '02b',
        '02c',
        '02d',
        '02e',
        '02f',
        '03',
        '04',
        '04a',
        '04b',
        '05',
        '06',
        '07',
        '08',
        '09',
        '10',
        '11',
        '12',
        '13',
        '14',
        '15',
        '16',
        '17',
        '18',
        '19a',
        '19b',
        '19c',
        '20',
        '21',
        '22',
        '23',
        '24',
        '25',
        '35',
        '36',
        '37',
        '38',
        '39',
      }),
    );
  });

  test('registry uses the canonical 393x852 mobile viewport and production seams', () {
    for (final frame in novaPenFrameFixtures) {
      expect(frame.viewport.width, 393, reason: frame.id);
      expect(frame.viewport.height, 852, reason: frame.id);
      expect(frame.productionTarget, isNotEmpty, reason: frame.id);
      expect(frame.russianName, isNotEmpty, reason: frame.id);
      expect(frame.evidence.scenario, isNotEmpty, reason: frame.id);
    }
  });

  test('every frame points to executable production-widget evidence', () {
    for (final frame in novaPenFrameFixtures) {
      final evidence = frame.evidence;
      final file = File(evidence.testPath);
      expect(file.existsSync(), isTrue, reason: '${frame.id}: missing ${evidence.testPath}');
      final source = file.readAsStringSync();
      expect(source, contains('testWidgets('), reason: '${frame.id}: evidence must mount a widget');
      expect(
        source,
        contains(evidence.productionSymbol),
        reason: '${frame.id}: ${evidence.productionSymbol} is not exercised by ${evidence.testPath}',
      );
      expect(
        evidence.kind,
        anyOf(
          NovaPenEvidenceKind.productionPage,
          NovaPenEvidenceKind.productionComponent,
          NovaPenEvidenceKind.productionBehavior,
          NovaPenEvidenceKind.constructorSmoke,
        ),
        reason: frame.id,
      );
    }
  });

  test('constructor-only evidence remains explicit and cannot be mistaken for rendered coverage', () {
    expect(
      novaPenFrameFixtures
          .where((frame) => frame.evidence.kind == NovaPenEvidenceKind.constructorSmoke)
          .map((frame) => frame.id)
          .toSet(),
      equals({'12'}),
    );
  });

  test('registry excludes exploratory Pen frames', () {
    final names = novaPenFrameFixtures.map((frame) => frame.russianName).join(' ');
    expect(names, isNot(contains('Design System')));
    expect(names, isNot(contains('Coverage Review')));
    expect(names, isNot(contains('Concept')));
  });
}
