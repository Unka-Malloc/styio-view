import '../language/language_contract.dart';
import 'execution_adapter.dart';

class HostedExecutionDecodeResult {
  const HostedExecutionDecodeResult({
    required this.session,
    required this.runtimeEvents,
  });

  final ExecutionSession session;
  final List<RuntimeEventEnvelope> runtimeEvents;
}

HostedExecutionDecodeResult executionSessionFromHostedResponse({
  required Map<String, dynamic> response,
  required String workflowKind,
  required String successMessage,
  required String documentText,
  required String activeFilePath,
}) {
  final payload =
      (response['payload'] ?? response['error_payload'])
          as Map<String, dynamic>?;
  final sessionId =
      _stringValue(payload?['session_id']) ??
      DateTime.now().microsecondsSinceEpoch.toString();
  final runtimeEvents = _runtimeEventsFromPayload(
    payload?['runtime_events'],
    sessionId: sessionId,
  );
  final diagnostics = <Diagnostic>[];
  final stderrEvents = <ExecutionLogEvent>[];
  final payloadDiagnostics = payload?['diagnostics'];
  if (payloadDiagnostics is List) {
    for (final entry in payloadDiagnostics.whereType<Map<String, dynamic>>()) {
      final decoded = _parseDiagnosticRecord(
        entry,
        activeFilePath: activeFilePath,
      );
      if (decoded.diagnostic != null) {
        diagnostics.add(decoded.diagnostic!);
      }
      if (decoded.logMessage != null) {
        stderrEvents.add(ExecutionLogEvent(message: decoded.logMessage!));
      }
    }
  }

  final stdoutText =
      _stringValue(payload?['stdout']) ??
      _stringValue(response['stdout']) ??
      '';
  final stderrText =
      _stringValue(payload?['stderr']) ??
      _stringValue(response['stderr']) ??
      '';
  final status = (response['returncode'] as int? ?? 1) == 0
      ? ExecutionSessionStatus.succeeded
      : ExecutionSessionStatus.failed;

  return HostedExecutionDecodeResult(
    session: ExecutionSession(
      sessionId: sessionId,
      kind: workflowKind,
      status: status,
      statusMessage:
          response['message'] as String? ??
          payload?['message'] as String? ??
          (status == ExecutionSessionStatus.succeeded
              ? successMessage
              : '$workflowKind failed through the hosted control plane.'),
      diagnostics: diagnostics,
      stdoutEvents: _logEventsFromText(stdoutText),
      stderrEvents: <ExecutionLogEvent>[
        ...stderrEvents,
        ..._logEventsFromText(stderrText),
      ],
      unitRange: SourceRange(start: 0, end: documentText.length),
    ),
    runtimeEvents: runtimeEvents,
  );
}

List<RuntimeEventEnvelope> _runtimeEventsFromPayload(
  Object? raw, {
  required String sessionId,
}) {
  final events = <RuntimeEventEnvelope>[];
  if (raw is! List) {
    return events;
  }
  for (final event in raw.whereType<Map<String, dynamic>>()) {
    final timestamp =
        DateTime.tryParse(event['timestamp'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final payload = <String, Object?>{};
    final rawPayload = event['payload'];
    if (rawPayload is Map) {
      for (final entry in rawPayload.entries) {
        if (entry.key is String) {
          payload[entry.key as String] = entry.value;
        }
      }
    }
    events.add(
      RuntimeEventEnvelope(
        schemaVersion:
            event['schemaVersion'] as int? ??
            event['schema_version'] as int? ??
            1,
        sessionId:
            event['sessionId'] as String? ??
            event['session_id'] as String? ??
            sessionId,
        sequence: event['sequence'] as int? ?? 0,
        timestamp: timestamp,
        eventKind:
            event['eventKind'] as String? ??
            event['event_kind'] as String? ??
            'runtime.unknown',
        origin: event['origin'] as String? ?? 'styio.hosted',
        payload: payload,
      ),
    );
  }
  return events;
}

List<ExecutionLogEvent> _logEventsFromText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const <ExecutionLogEvent>[];
  }
  return trimmed
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => ExecutionLogEvent(message: line))
      .toList(growable: false);
}

class _ParsedDiagnosticRecord {
  const _ParsedDiagnosticRecord({this.diagnostic, this.logMessage});

  final Diagnostic? diagnostic;
  final String? logMessage;
}

_ParsedDiagnosticRecord _parseDiagnosticRecord(
  Map<String, dynamic> decoded, {
  required String activeFilePath,
}) {
  final message = _diagnosticMessage(decoded);
  if (message == null || message.isEmpty) {
    return const _ParsedDiagnosticRecord();
  }

  final category = _stringValue(decoded['category']);
  final severityLabel = _stringValue(decoded['severity']);
  final filePath = _normalizedDiagnosticFilePath(
    decoded,
    activeFilePath: activeFilePath,
  );
  final range = _diagnosticRangeFromPayload(
    decoded,
    activeFilePath: activeFilePath,
    normalizedFilePath: filePath,
  );
  final code = _diagnosticCode(decoded, category: category);
  final displayMessage = filePath == null || filePath == activeFilePath
      ? message
      : '$filePath: $message';
  if (filePath != null &&
      filePath.isNotEmpty &&
      activeFilePath.isNotEmpty &&
      filePath != activeFilePath) {
    return _ParsedDiagnosticRecord(logMessage: displayMessage);
  }
  return _ParsedDiagnosticRecord(
    diagnostic: Diagnostic(
      severity: severityLabel == null || severityLabel.isEmpty
          ? _severityFromCategory(category ?? 'diagnostic')
          : _severityFromCategory(severityLabel),
      code: code,
      message: displayMessage,
      range: range ?? const SourceRange(start: 0, end: 0),
    ),
  );
}

String? _diagnosticMessage(Map<String, dynamic> decoded) {
  for (final key in const <String>[
    'message',
    'text',
    'detail',
    'reason',
    'raw',
  ]) {
    final value = _stringValue(decoded[key]);
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String _diagnosticCode(
  Map<String, dynamic> decoded, {
  required String? category,
}) {
  final primary = _stringValue(decoded['code']) ?? category ?? 'diagnostic';
  final subcode = _stringValue(decoded['subcode']);
  if (subcode == null || subcode.isEmpty) {
    return primary;
  }
  return '$primary:$subcode';
}

SourceRange? _diagnosticRangeFromPayload(
  Map<String, dynamic> decoded, {
  required String activeFilePath,
  String? normalizedFilePath,
}) {
  final filePath =
      normalizedFilePath ??
      _normalizedDiagnosticFilePath(decoded, activeFilePath: activeFilePath);
  if (filePath != null &&
      filePath.isNotEmpty &&
      activeFilePath.isNotEmpty &&
      filePath != activeFilePath) {
    return null;
  }

  return _sourceRangeFromObject(decoded['range']) ??
      _sourceRangeFromObject(decoded['span']) ??
      _sourceRangeFromObject(decoded['location']) ??
      _sourceRangeFromOffsetFields(decoded);
}

SourceRange? _sourceRangeFromObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    return null;
  }

  final directRange = _sourceRangeFromOffsetFields(value);
  if (directRange != null) {
    return directRange;
  }

  final start = _offsetFromObject(value['start']);
  final end = _offsetFromObject(value['end']);
  if (start != null && end != null) {
    return _normalizedRange(start, end);
  }

  return null;
}

SourceRange? _sourceRangeFromOffsetFields(Map<String, dynamic> value) {
  final start = _intValue(value['start']) ?? _intValue(value['startOffset']);
  final end = _intValue(value['end']) ?? _intValue(value['endOffset']);
  if (start != null && end != null) {
    return _normalizedRange(start, end);
  }

  final offset = _intValue(value['offset']);
  final length = _intValue(value['length']);
  if (offset != null && length != null) {
    final safeLength = length < 0 ? 0 : length;
    return SourceRange(start: offset, end: offset + safeLength);
  }

  return null;
}

int? _offsetFromObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return _intValue(value['offset']) ??
        _intValue(value['index']) ??
        _intValue(value['position']) ??
        _intValue(value['value']);
  }
  return _intValue(value);
}

SourceRange _normalizedRange(int start, int end) {
  if (end < start) {
    return SourceRange(start: end, end: start);
  }
  return SourceRange(start: start, end: end);
}

String? _normalizedDiagnosticFilePath(
  Map<String, dynamic> decoded, {
  required String activeFilePath,
}) {
  final rawFilePath = _stringValue(decoded['file']);
  if (rawFilePath == null) {
    return null;
  }
  return _normalizeHostedDiagnosticPath(
    rawFilePath,
    activeFilePath: activeFilePath,
  );
}

String _normalizeHostedDiagnosticPath(
  String filePath, {
  required String activeFilePath,
}) {
  if (filePath.isEmpty ||
      activeFilePath.isEmpty ||
      filePath == activeFilePath) {
    return filePath;
  }

  final fileSegments = _pathSegments(filePath);
  final activeSegments = _pathSegments(activeFilePath);
  if (fileSegments.isEmpty || activeSegments.isEmpty) {
    return filePath;
  }

  final workspaceSuffix = _pathSuffixAfterWorkspace(fileSegments);
  if (workspaceSuffix.isNotEmpty &&
      _pathEndsWith(activeSegments, workspaceSuffix)) {
    return activeFilePath;
  }

  final sharedSuffixLength = _sharedTrailingSegmentCount(
    fileSegments,
    activeSegments,
  );
  if (sharedSuffixLength >= 2 ||
      (sharedSuffixLength == 1 &&
          fileSegments.length == 1 &&
          activeSegments.length == 1)) {
    return activeFilePath;
  }

  return filePath;
}

List<String> _pathSegments(String value) {
  final normalized = value.replaceAll('\\', '/');
  return normalized.split('/').where((segment) => segment.isNotEmpty).toList();
}

List<String> _pathSuffixAfterWorkspace(List<String> segments) {
  final workspaceIndex = segments.lastIndexOf('workspace');
  if (workspaceIndex < 0 || workspaceIndex + 1 >= segments.length) {
    return const <String>[];
  }
  return segments.sublist(workspaceIndex + 1);
}

bool _pathEndsWith(List<String> fullPath, List<String> suffix) {
  if (suffix.length > fullPath.length) {
    return false;
  }
  final start = fullPath.length - suffix.length;
  for (var index = 0; index < suffix.length; index += 1) {
    if (fullPath[start + index] != suffix[index]) {
      return false;
    }
  }
  return true;
}

int _sharedTrailingSegmentCount(List<String> left, List<String> right) {
  var count = 0;
  while (count < left.length && count < right.length) {
    if (left[left.length - 1 - count] != right[right.length - 1 - count]) {
      break;
    }
    count += 1;
  }
  return count;
}

String? _stringValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num || value is bool) {
    return '$value';
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

DiagnosticSeverity _severityFromCategory(String category) {
  final normalized = category.toLowerCase();
  if (normalized.contains('runtime') || normalized.contains('type')) {
    return DiagnosticSeverity.error;
  }
  if (normalized.contains('warning')) {
    return DiagnosticSeverity.warning;
  }
  return DiagnosticSeverity.error;
}
