import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/language_fixture_confidence_matrix.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';

void main() {
  test('language fixture confidence matrix classifies parser outcomes', () async {
    const builder = LanguageFixtureConfidenceMatrixBuilder();
    final matrix = await builder.build(
      fixturePaths: const <String>[
        'valid.true.styio',
        'stale-valid.true.styio',
        'invalid.false.styio',
        'mislabeled.false.styio',
        'unmarked.styio',
      ],
      validate: (path) {
        return switch (path) {
          'valid.true.styio' => LanguageFixtureActualResult.pass,
          'stale-valid.true.styio' => LanguageFixtureActualResult.fail,
          'invalid.false.styio' => LanguageFixtureActualResult.fail,
          'mislabeled.false.styio' => LanguageFixtureActualResult.pass,
          _ => LanguageFixtureActualResult.pass,
        };
      },
    );

    expect(
      matrix.entries.map((entry) => entry.matrixClass),
      <LanguageFixtureConfidenceClass>[
        LanguageFixtureConfidenceClass.truePositive,
        LanguageFixtureConfidenceClass.falseNegative,
        LanguageFixtureConfidenceClass.trueNegative,
        LanguageFixtureConfidenceClass.falsePositive,
        LanguageFixtureConfidenceClass.unlabeled,
      ],
    );
    expect(matrix.gatePassed, isFalse);
    expect(matrix.failures, hasLength(3));
    expect(matrix.toJson()['gatePassed'], isFalse);
    expect(
      matrix.summary,
      containsPair(LanguageFixtureConfidenceClass.falseNegative.name, 1),
    );
  });

  test('language fixture confidence matrix passes matching expectations', () async {
    final matrix = await const LanguageFixtureConfidenceMatrixBuilder().build(
      fixturePaths: const <String>[
        'valid.true.styio',
        'invalid.false.styio',
      ],
      validate: (path) => path.endsWith('.true.styio')
          ? LanguageFixtureActualResult.pass
          : LanguageFixtureActualResult.fail,
    );

    expect(matrix.gatePassed, isTrue);
    expect(matrix.failures, isEmpty);
  });

  test('styio service fixture validator maps connector diagnostics to matrix', () async {
    final validator = StyioServiceFixtureValidator(
      connector: _FixtureConnector(),
      textLoader: (path) => path,
    );
    final matrix = await const LanguageFixtureConfidenceMatrixBuilder().build(
      fixturePaths: const <String>[
        'valid.true.styio',
        'invalid.false.styio',
      ],
      validate: validator.validate,
    );

    expect(matrix.gatePassed, isTrue);
    expect(
      matrix.entries.map((entry) => entry.matrixClass),
      <LanguageFixtureConfidenceClass>[
        LanguageFixtureConfidenceClass.truePositive,
        LanguageFixtureConfidenceClass.trueNegative,
      ],
    );
  });

  test('language fixture gate runner scans styio files through file system manager', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'vityo-language-fixtures-',
    );
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    try {
      final root = tempDirectory.path;
      final nested = fileSystemManager.joinPath(<String>[root, 'nested']);
      final valid = fileSystemManager.joinPath(<String>[
        root,
        'valid.true.styio',
      ]);
      final invalid = fileSystemManager.joinPath(<String>[
        nested,
        'invalid.false.styio',
      ]);
      final ignored = fileSystemManager.joinPath(<String>[root, 'notes.txt']);

      await fileSystemManager.createDirectory(nested);
      await fileSystemManager.writeText(valid, 'valid fixture');
      await fileSystemManager.writeText(invalid, 'invalid fixture');
      await fileSystemManager.writeText(ignored, 'not a styio fixture');

      final runner = LanguageFixtureGateRunner(
        collector: LanguageFixtureFileCollector(
          fileSystemManager: fileSystemManager,
        ),
        validate: (path) => path.endsWith('.true.styio')
            ? LanguageFixtureActualResult.pass
            : LanguageFixtureActualResult.fail,
      );

      final matrix = await runner.run(roots: <String>[root]);
      final expectedPaths = <String>[valid, invalid]..sort();

      expect(
        matrix.entries.map((entry) => entry.path),
        expectedPaths,
      );
      expect(matrix.gatePassed, isTrue);
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('language fixture file-system text loader reads through manager', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'vityo-language-fixture-loader-',
    );
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    try {
      final fixture = fileSystemManager.joinPath(<String>[
        tempDirectory.path,
        'valid.true.styio',
      ]);
      await fileSystemManager.writeText(fixture, 'fixture source');

      final loader = LanguageFixtureFileSystemTextLoader(
        fileSystemManager: fileSystemManager,
      );

      expect(await loader.load(fixture), 'fixture source');
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('styio service fixture gate composes file system and connector', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'vityo-styio-service-fixture-gate-',
    );
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    try {
      final valid = fileSystemManager.joinPath(<String>[
        tempDirectory.path,
        'valid.true.styio',
      ]);
      final invalid = fileSystemManager.joinPath(<String>[
        tempDirectory.path,
        'invalid.false.styio',
      ]);
      await fileSystemManager.writeText(valid, '#valid := () => {}');
      await fileSystemManager.writeText(invalid, '#invalid := () => {');

      final gate = StyioServiceFixtureGate(
        fileSystemManager: fileSystemManager,
        connector: _FixtureConnector(),
      );
      final matrix = await gate.run(roots: <String>[tempDirectory.path]);

      expect(matrix.gatePassed, isTrue);
      expect(
        matrix.entries.map((entry) => entry.matrixClass),
        <LanguageFixtureConfidenceClass>[
          LanguageFixtureConfidenceClass.trueNegative,
          LanguageFixtureConfidenceClass.truePositive,
        ],
      );
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  });
}

class _FixtureConnector implements StyioServiceConnector {
  @override
  Future<StyioServiceResponse> analyzeDocument(StyioServiceDocument document) async {
    if (document.documentId.endsWith('.false.styio')) {
      return StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: document.documentId,
        revision: document.revision,
        diagnostics: const <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.error,
            code: 'styio.syntax',
            message: 'invalid fixture',
            range: SourceRange(start: 0, end: 1),
          ),
        ],
      );
    }
    return StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: document.documentId,
      revision: document.revision,
    );
  }
}
