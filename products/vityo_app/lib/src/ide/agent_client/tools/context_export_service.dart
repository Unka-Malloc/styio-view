import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../mcp/workspace_root_registry.dart';
import '../../workbench/ide_fact_provider.dart';
import 'ide_tool_catalog.dart';
import 'tool_security_policy.dart';

final class ContextQuery {
  const ContextQuery({
    required this.expectedWorkspaceRevision,
    this.capabilityIds = const <String>[],
    this.cursor,
  });

  final int expectedWorkspaceRevision;
  final List<String> capabilityIds;
  final String? cursor;
}

final class ContextBudget {
  const ContextBudget({
    required this.maxItems,
    required this.maxUtf8Bytes,
    required this.maxCodeUnitsPerItem,
  });

  final int maxItems;
  final int maxUtf8Bytes;
  final int maxCodeUnitsPerItem;

  void validate() {
    if (maxItems <= 0 ||
        maxItems > 256 ||
        maxUtf8Bytes <= 0 ||
        maxUtf8Bytes > 1024 * 1024 ||
        maxCodeUnitsPerItem <= 0 ||
        maxCodeUnitsPerItem > 256 * 1024) {
      throw ArgumentError('context budget is outside supported bounds');
    }
  }
}

final class ContextEvidenceItem {
  ContextEvidenceItem({
    required this.id,
    required this.kind,
    required Map<String, Object?> content,
    required this.provenance,
    required this.sensitivity,
    required this.digest,
    required this.truncated,
    required this.omittedCodeUnits,
  }) : content = UnmodifiableMapView(content);

  final String id;
  final String kind;
  final Map<String, Object?> content;
  final String provenance;
  final ContextSensitivity sensitivity;
  final String digest;
  final bool truncated;
  final int omittedCodeUnits;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'content': content,
    'provenance': provenance,
    'sensitivity': sensitivity.name,
    'digest': digest,
    'truncated': truncated,
    'omittedCodeUnits': omittedCodeUnits,
  };
}

final class ContextEvidencePage {
  ContextEvidencePage({
    required this.schemaVersion,
    required this.workspaceRevision,
    required this.provenance,
    required Iterable<ContextEvidenceItem> items,
    required this.nextCursor,
    required this.truncated,
    required this.omittedItemCount,
    required this.omittedUtf8Bytes,
  }) : items = UnmodifiableListView<ContextEvidenceItem>(
         List<ContextEvidenceItem>.of(items),
       );

  final int schemaVersion;
  final int workspaceRevision;
  final String provenance;
  final List<ContextEvidenceItem> items;
  final String? nextCursor;
  final bool truncated;
  final int omittedItemCount;
  final int omittedUtf8Bytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'workspaceRevision': workspaceRevision,
    'provenance': provenance,
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'nextCursor': nextCursor,
    'truncated': truncated,
    'omittedItemCount': omittedItemCount,
    'omittedUtf8Bytes': omittedUtf8Bytes,
  };
}

abstract interface class ContextExportService {
  Future<ContextEvidencePage> read(ContextQuery query, ContextBudget budget);
}

final class RevisionedIdeContextExportService implements ContextExportService {
  const RevisionedIdeContextExportService({
    required IdeFactProvider provider,
    required int Function() currentWorkspaceRevision,
    required McpPayloadSanitizer sanitizer,
  }) : _provider = provider,
       _currentWorkspaceRevision = currentWorkspaceRevision,
       _sanitizer = sanitizer;

  final IdeFactProvider _provider;
  final int Function() _currentWorkspaceRevision;
  final McpPayloadSanitizer _sanitizer;

  @override
  Future<ContextEvidencePage> read(
    ContextQuery query,
    ContextBudget budget,
  ) async {
    budget.validate();
    final currentRevision = _currentWorkspaceRevision();
    if (query.expectedWorkspaceRevision != currentRevision) {
      throw StaleIdeFactRevision(
        expected: query.expectedWorkspaceRevision,
        current: currentRevision,
      );
    }
    final facts = await _provider.read(
      IdeFactQuery(capabilityIds: query.capabilityIds),
      query.expectedWorkspaceRevision,
    );
    final candidates = _candidates(facts);
    final start = _decodeCursor(query.cursor, facts.workspaceRevision);
    if (start > candidates.length) {
      throw const IdeToolFailure(
        'invalid_cursor',
        'context cursor is outside the current evidence set',
      );
    }

    final selected = <ContextEvidenceItem>[];
    final seen = <String>{};
    var usedBytes = 0;
    var nextIndex = start;
    var oversizedItemCount = 0;
    var oversizedUtf8Bytes = 0;
    while (nextIndex < candidates.length && selected.length < budget.maxItems) {
      final candidate = candidates[nextIndex];
      final item = _toItem(candidate, budget.maxCodeUnitsPerItem);
      if (!seen.add(item.digest)) {
        nextIndex += 1;
        continue;
      }
      final encodedBytes = utf8.encode(jsonEncode(item.toJson())).length;
      if (encodedBytes > budget.maxUtf8Bytes) {
        nextIndex += 1;
        oversizedItemCount += 1;
        oversizedUtf8Bytes += _sanitizedContentUtf8Bytes(candidate);
        continue;
      }
      if (usedBytes + encodedBytes > budget.maxUtf8Bytes) {
        break;
      }
      nextIndex += 1;
      selected.add(item);
      usedBytes += encodedBytes;
    }
    final omitted = candidates.skip(nextIndex).toList(growable: false);
    final omittedBytes =
        oversizedUtf8Bytes +
        omitted.fold<int>(
          0,
          (total, candidate) => total + _sanitizedContentUtf8Bytes(candidate),
        );
    final truncated = oversizedItemCount > 0 || nextIndex < candidates.length;
    return ContextEvidencePage(
      schemaVersion: 1,
      workspaceRevision: facts.workspaceRevision,
      provenance: 'vityo-facts',
      items: selected,
      nextCursor: truncated
          ? _encodeCursor(facts.workspaceRevision, nextIndex)
          : null,
      truncated: truncated,
      omittedItemCount: oversizedItemCount + candidates.length - nextIndex,
      omittedUtf8Bytes: omittedBytes,
    );
  }

  int _sanitizedContentUtf8Bytes(_ContextCandidate candidate) =>
      utf8.encode(jsonEncode(_sanitizer.sanitize(candidate.content))).length;

  List<_ContextCandidate> _candidates(RevisionedIdeFacts facts) {
    final candidates = <_ContextCandidate>[
      for (final entry in facts.capabilities.capabilities.entries)
        _ContextCandidate(
          id: 'capability:${entry.key}',
          kind: 'capability',
          content: entry.value.toJson(),
          provenance: entry.value.provenance,
          sensitivity: ContextSensitivity.internal,
        ),
      _ContextCandidate(
        id: 'diagnostics:${facts.workspaceRevision}',
        kind: 'diagnostics',
        content: facts.diagnostics.toJson(),
        provenance: facts.diagnostics.provenance,
        sensitivity: ContextSensitivity.internal,
      ),
      for (final receipt in facts.receipts)
        _ContextCandidate(
          id: 'receipt:${receipt.operationId}',
          kind: 'execution_receipt',
          content: receipt.toJson(),
          provenance: receipt.provenance,
          sensitivity: ContextSensitivity.internal,
        ),
    ];
    candidates.sort((left, right) => left.id.compareTo(right.id));
    return candidates;
  }

  ContextEvidenceItem _toItem(_ContextCandidate candidate, int maxCodeUnits) {
    final sanitized = _sanitizer.sanitize(candidate.content);
    final canonical = _canonicalJson(sanitized);
    var encoded = jsonEncode(canonical);
    var truncated = false;
    var omitted = 0;
    Map<String, Object?> content;
    if (encoded.length > maxCodeUnits) {
      final end = _safeCodeUnitEnd(encoded, maxCodeUnits);
      omitted = encoded.length - end;
      encoded = encoded.substring(0, end);
      truncated = true;
      content = <String, Object?>{'jsonFragment': encoded};
    } else {
      content = Map<String, Object?>.from(canonical as Map<String, Object?>);
    }
    return ContextEvidenceItem(
      id: candidate.id,
      kind: candidate.kind,
      content: content,
      provenance: candidate.provenance,
      sensitivity: candidate.sensitivity,
      digest: sha256.convert(utf8.encode(jsonEncode(canonical))).toString(),
      truncated: truncated,
      omittedCodeUnits: omitted,
    );
  }
}

final class ContextReadToolAdapter implements IdeToolAdapter {
  const ContextReadToolAdapter(this._context);

  final ContextExportService _context;

  @override
  IdeToolDescriptor get descriptor => IdeToolDescriptor(
    name: 'ide.context.read',
    title: 'Read IDE facts',
    description: 'Read bounded revision-bound IDE facts.',
    requiredCapabilityId: 'ide.context.read',
    inputSchema: const <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'type': 'object',
      'additionalProperties': false,
      'required': <String>[
        'expectedWorkspaceRevision',
        'maxItems',
        'maxUtf8Bytes',
        'maxCodeUnitsPerItem',
      ],
    },
    outputSchema: const <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'type': 'object',
    },
    risks: const <IdeToolRisk>{IdeToolRisk.readOnly},
    annotations: const <String, Object?>{'readOnlyHint': true},
  );

  @override
  Future<IdeToolResult> invoke(IdeToolInvocation invocation) async {
    final arguments = invocation.arguments;
    final revision = _requiredInt(arguments, 'expectedWorkspaceRevision');
    final page = await _context.read(
      ContextQuery(
        expectedWorkspaceRevision: revision,
        capabilityIds: _optionalStrings(arguments, 'capabilityIds'),
        cursor: arguments['cursor'] as String?,
      ),
      ContextBudget(
        maxItems: _requiredInt(arguments, 'maxItems'),
        maxUtf8Bytes: _requiredInt(arguments, 'maxUtf8Bytes'),
        maxCodeUnitsPerItem: _requiredInt(arguments, 'maxCodeUnitsPerItem'),
      ),
    );
    return IdeToolResult(
      structuredContent: page.toJson(),
      workspaceRevision: page.workspaceRevision,
      provenance: page.provenance,
      sensitivity: ContextSensitivity.internal,
    );
  }
}

final class WorkspaceReadTextToolAdapter implements IdeToolAdapter {
  WorkspaceReadTextToolAdapter({
    required WorkspaceRootRegistry roots,
    required this.maxCodeUnits,
    required McpPayloadSanitizer sanitizer,
  }) : _roots = roots,
       _sanitizer = sanitizer {
    if (maxCodeUnits <= 0 || maxCodeUnits > 256 * 1024) {
      throw ArgumentError.value(
        maxCodeUnits,
        'maxCodeUnits',
        'must be between 1 and 262144',
      );
    }
  }

  final WorkspaceRootRegistry _roots;
  final int maxCodeUnits;
  final McpPayloadSanitizer _sanitizer;

  @override
  IdeToolDescriptor get descriptor => IdeToolDescriptor(
    name: 'ide.workspace.read_text',
    title: 'Read workspace text',
    description: 'Read one text file inside a consented workspace root.',
    requiredCapabilityId: 'ide.workspace.read_text',
    inputSchema: const <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['path'],
    },
    outputSchema: const <String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'type': 'object',
    },
    risks: const <IdeToolRisk>{IdeToolRisk.readOnly},
    requiresWorkspacePath: true,
    annotations: const <String, Object?>{'readOnlyHint': true},
  );

  @override
  Future<IdeToolResult> invoke(IdeToolInvocation invocation) async {
    final path = invocation.arguments['path'];
    if (path is! String || path.isEmpty) {
      throw const IdeToolFailure(
        'schema_validation_failed',
        'path must be a non-empty string',
      );
    }
    final authorization = await _roots.authorize(
      sessionId: invocation.sessionId,
      candidate: path,
    );
    if (!authorization.allowed) {
      throw IdeToolFailure(
        authorization.code,
        'workspace path is not authorized',
      );
    }
    final source = await _readBoundedUtf8File(
      authorization.canonicalPath!,
      maxCodeUnits,
      validateOpenTarget: () async {
        final current = await _roots.authorize(
          sessionId: invocation.sessionId,
          candidate: authorization.canonicalPath!,
        );
        if (!current.allowed ||
            current.rootRevision != authorization.rootRevision ||
            current.rootId != authorization.rootId ||
            current.canonicalPath != authorization.canonicalPath) {
          throw const IdeToolFailure(
            'resource_changed',
            'workspace resource authorization changed while opening the file',
          );
        }
      },
    );
    final sanitized = _sanitizer.sanitize(source.text) as String;
    return IdeToolResult(
      structuredContent: <String, Object?>{
        'text': sanitized,
        'truncated': source.truncated,
        'omittedCodeUnits': source.omittedCodeUnits,
        'omittedCodeUnitsExact': source.omittedCodeUnitsExact,
        'omittedUtf8Bytes': source.omittedUtf8Bytes,
        'rootId': authorization.rootId,
        'rootRevision': authorization.rootRevision,
      },
      workspaceRevision: invocation.expectedWorkspaceRevision ?? 0,
      provenance: 'vityo-workspace-root',
      sensitivity: ContextSensitivity.internal,
    );
  }
}

final class _ContextCandidate {
  const _ContextCandidate({
    required this.id,
    required this.kind,
    required this.content,
    required this.provenance,
    required this.sensitivity,
  });

  final String id;
  final String kind;
  final Map<String, Object?> content;
  final String provenance;
  final ContextSensitivity sensitivity;
}

Object? _canonicalJson(Object? value) {
  if (value is Map<Object?, Object?>) {
    final keys = value.keys.map((key) => key.toString()).toList(growable: false)
      ..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  if (value is Iterable<Object?>) {
    return value.map(_canonicalJson).toList(growable: false);
  }
  return value;
}

int _decodeCursor(String? cursor, int revision) {
  if (cursor == null) {
    return 0;
  }
  try {
    final decoded =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(cursor))))
            as Map<String, Object?>;
    if (decoded['revision'] != revision ||
        decoded['index'] is! int ||
        (decoded['index'] as int) < 0) {
      throw const FormatException();
    }
    return decoded['index'] as int;
  } on Object {
    throw const IdeToolFailure(
      'invalid_cursor',
      'context cursor is malformed or stale',
    );
  }
}

String _encodeCursor(int revision, int index) => base64Url.encode(
  utf8.encode(
    jsonEncode(<String, Object?>{'revision': revision, 'index': index}),
  ),
);

int _safeCodeUnitEnd(String value, int maximum) {
  var end = maximum < value.length ? maximum : value.length;
  if (end > 0) {
    final last = value.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) {
      end -= 1;
    }
  }
  return end;
}

Future<_BoundedUtf8File> _readBoundedUtf8File(
  String path,
  int maxCodeUnits, {
  required Future<void> Function() validateOpenTarget,
}) async {
  final handle = await File(path).open();
  try {
    await validateOpenTarget();
    final initialLength = await handle.length();
    final byteLimit = maxCodeUnits * 4 + 3;
    final requestedBytes = initialLength < byteLimit
        ? initialLength
        : byteLimit;
    final bytes = await handle.read(requestedBytes);
    final finalLength = await handle.length();
    if (finalLength != initialLength) {
      throw const IdeToolFailure(
        'resource_changed',
        'workspace resource changed while it was being read',
      );
    }
    final complete = bytes.length == initialLength;
    final decoded = _decodeUtf8Prefix(bytes, complete: complete);
    final end = _safeCodeUnitEnd(decoded.text, maxCodeUnits);
    final text = decoded.text.substring(0, end);
    final emittedBytes = utf8.encode(text).length;
    return _BoundedUtf8File(
      text: text,
      truncated: emittedBytes < initialLength,
      omittedCodeUnits: decoded.text.length - end,
      omittedCodeUnitsExact: complete,
      omittedUtf8Bytes: initialLength - emittedBytes,
    );
  } finally {
    await handle.close();
  }
}

_DecodedUtf8Prefix _decodeUtf8Prefix(
  List<int> bytes, {
  required bool complete,
}) {
  if (complete) {
    try {
      return _DecodedUtf8Prefix(utf8.decode(bytes));
    } on FormatException {
      throw const IdeToolFailure(
        'resource_invalid_encoding',
        'workspace resource is not valid UTF-8',
      );
    }
  }
  final maximumTrim = bytes.length < 3 ? bytes.length : 3;
  for (var trim = 0; trim <= maximumTrim; trim += 1) {
    try {
      return _DecodedUtf8Prefix(
        utf8.decode(bytes.sublist(0, bytes.length - trim)),
      );
    } on FormatException {
      // A bounded prefix may end in the middle of one UTF-8 scalar.
    }
  }
  throw const IdeToolFailure(
    'resource_invalid_encoding',
    'workspace resource is not valid UTF-8',
  );
}

final class _DecodedUtf8Prefix {
  const _DecodedUtf8Prefix(this.text);

  final String text;
}

final class _BoundedUtf8File {
  const _BoundedUtf8File({
    required this.text,
    required this.truncated,
    required this.omittedCodeUnits,
    required this.omittedCodeUnitsExact,
    required this.omittedUtf8Bytes,
  });

  final String text;
  final bool truncated;
  final int omittedCodeUnits;
  final bool omittedCodeUnitsExact;
  final int omittedUtf8Bytes;
}

int _requiredInt(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! int) {
    throw IdeToolFailure('schema_validation_failed', '$key must be an integer');
  }
  return value;
}

List<String> _optionalStrings(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value == null) {
    return const <String>[];
  }
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw IdeToolFailure(
      'schema_validation_failed',
      '$key must be a list of strings',
    );
  }
  return List<String>.unmodifiable(value.cast<String>());
}
