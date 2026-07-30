import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';

void main() {
  test('matches compiler diagnostic snapshot fixtures', () {
    final fixtureDirectory = Directory('test/fixtures/styio_diagnostics');
    final fixtures =
        fixtureDirectory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList(growable: false)
          ..sort((left, right) => left.path.compareTo(right.path));

    expect(fixtures, isNotEmpty);
    for (final fixture in fixtures) {
      final decoded = jsonDecode(fixture.readAsStringSync());
      final cases = decoded['cases'] as List<dynamic>;
      for (final entry in cases.cast<Map<String, dynamic>>()) {
        final name = entry['name'] as String;
        final source = entry['source'] as String;
        final expected = _normalizeSnapshotEntries(
          (entry['diagnostics'] as List<dynamic>).cast<Map<String, dynamic>>(),
        );
        final actual = _compilerDiagnosticSnapshot(source);

        expect(actual, equals(expected), reason: '${fixture.path}: $name');
      }
    }
  });
}

List<Map<String, String>> _compilerDiagnosticSnapshot(String source) {
  const highlighter = StyioSyntaxHighlighter();
  const diagnostics = StyioCompilerDiagnostics();
  final tokens = highlighter.tokenize(source);

  return _normalizeSnapshotEntries(
    diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) {
          final descriptor = StyioDiagnosticCatalog.descriptorFor(
            diagnostic.code,
          );
          return <String, String>{
            'code': diagnostic.code,
            'severity': diagnostic.severity.name,
            'phase': descriptor?.phase.name ?? 'unknown',
          };
        })
        .toList(growable: false),
  );
}

List<Map<String, String>> _normalizeSnapshotEntries(
  List<Map<String, dynamic>> entries,
) {
  final normalized = entries
      .map((entry) {
        return <String, String>{
          'code': entry['code'] as String,
          'severity': entry['severity'] as String,
          'phase': entry['phase'] as String,
        };
      })
      .toList(growable: false);

  normalized.sort((left, right) {
    final code = left['code']!.compareTo(right['code']!);
    if (code != 0) {
      return code;
    }
    final severity = left['severity']!.compareTo(right['severity']!);
    if (severity != 0) {
      return severity;
    }
    return left['phase']!.compareTo(right['phase']!);
  });
  return normalized;
}
