import '../execution/execution_receipt.dart';
import '../workbench/capability_snapshot.dart';
import 'diagnostic_fact.dart';

abstract interface class DeveloperDiagnosticDecoder {
  DeveloperDiagnosticBatch decode({
    required BoundedText output,
    required BoundedText errorOutput,
    required int exitCode,
  });
}

/// Decodes Dart analyzer's machine format without interpreting compiler
/// semantics. Paths outside the workspace are reduced to opaque resource ids.
final class DartAnalyzeMachineDiagnosticDecoder
    implements DeveloperDiagnosticDecoder {
  DartAnalyzeMachineDiagnosticDecoder({required String workspaceRoot})
    : _workspaceRoot = _normalizePath(workspaceRoot);

  final String _workspaceRoot;

  @override
  DeveloperDiagnosticBatch decode({
    required BoundedText output,
    required BoundedText errorOutput,
    required int exitCode,
  }) {
    if (output.truncated || errorOutput.truncated) {
      return DeveloperDiagnosticBatch(
        state: IdeCapabilityState.degraded,
        provenance: 'dart-analyze-machine',
        message: 'Analyzer output was truncated; diagnostics are incomplete.',
        diagnostics: const <IdeDiagnosticFact>[],
      );
    }
    final diagnostics = <IdeDiagnosticFact>[];
    var undecodable = false;
    for (final line in output.text.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) {
        continue;
      }
      final fields = _splitMachineLine(line);
      if (fields.length != 8) {
        undecodable = true;
        continue;
      }
      final severity = _severity(fields[0]);
      final lineNumber = int.tryParse(fields[4]);
      final column = int.tryParse(fields[5]);
      final length = int.tryParse(fields[6]);
      if (severity == null ||
          lineNumber == null ||
          column == null ||
          length == null) {
        undecodable = true;
        continue;
      }
      diagnostics.add(
        IdeDiagnosticFact(
          resourceId: _resourceId(fields[3]),
          severity: severity,
          code: fields[2],
          message: fields[7],
          line: lineNumber,
          column: column,
          length: length,
          provenance: 'dart-analyze-machine',
        ),
      );
    }
    if (undecodable || exitCode != 0) {
      return DeveloperDiagnosticBatch(
        state: IdeCapabilityState.degraded,
        provenance: 'dart-analyze-machine',
        message: exitCode != 0
            ? 'Analyzer reported failure; diagnostics may be incomplete.'
            : 'Analyzer emitted an unrecognized machine-format record.',
        diagnostics: diagnostics,
      );
    }
    return DeveloperDiagnosticBatch(
      state: IdeCapabilityState.available,
      provenance: 'dart-analyze-machine',
      message: 'Analyzer diagnostics are complete for this revision.',
      diagnostics: diagnostics,
    );
  }

  String _resourceId(String path) {
    final normalized = _normalizePath(path);
    final rootPrefix = _workspaceRoot.endsWith('/')
        ? _workspaceRoot
        : '$_workspaceRoot/';
    if (normalized.toLowerCase().startsWith(rootPrefix.toLowerCase())) {
      return normalized.substring(rootPrefix.length);
    }
    return 'external/${normalized.split('/').last}';
  }
}

IdeDiagnosticSeverity? _severity(String value) => switch (value) {
  'ERROR' => IdeDiagnosticSeverity.error,
  'WARNING' => IdeDiagnosticSeverity.warning,
  'INFO' => IdeDiagnosticSeverity.information,
  _ => null,
};

String _normalizePath(String value) => value.replaceAll('\\', '/');

List<String> _splitMachineLine(String line) {
  final fields = <String>[];
  final current = StringBuffer();
  for (var index = 0; index < line.length; index += 1) {
    final character = line[index];
    if (character == r'\' && index + 1 < line.length) {
      final next = line[index + 1];
      if (next == '|' || next == r'\') {
        current.write(next);
        index += 1;
      } else {
        current.write(character);
      }
    } else if (character == '|') {
      fields.add(current.toString());
      current.clear();
    } else {
      current.write(character);
    }
  }
  fields.add(current.toString());
  return fields;
}
