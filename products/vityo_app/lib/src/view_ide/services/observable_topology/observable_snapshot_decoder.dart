import 'dart:convert';

import 'observable_snapshot_model.dart';

ObservableDecodeResult decodeObservableSnapshotJson(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (error) {
    return ObservableDecodeResult.invalid(
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.missingField,
        detail: 'snapshot is not valid JSON: ${error.message}',
      ),
    );
  }
  if (decoded is! Map) {
    return const ObservableDecodeResult.invalid(
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.missingField,
        detail: 'snapshot must be an object',
      ),
    );
  }
  return decodeObservableSnapshotMap(
    decoded.map(
      (key, value) => MapEntry<String, Object?>(key.toString(), value),
    ),
  );
}

ObservableDecodeResult decodeObservableSnapshotBytes(List<int> bytes) {
  return decodeObservableSnapshotJson(utf8.decode(bytes));
}

ObservableDecodeResult decodeObservableSnapshotMap(Map<String, Object?> root) {
  final contract = _stringField(root, 'contract');
  if (contract == null) {
    return _missing('contract');
  }
  if (contract != kObservableStaticSnapshotContract) {
    return ObservableDecodeResult.invalid(
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.unsupportedContract,
        detail: 'unsupported contract $contract',
      ),
    );
  }

  final schemaVersion = _intField(root, 'schema_version');
  if (schemaVersion == null) {
    return _missing('schema_version');
  }
  if (schemaVersion != kObservableStaticSnapshotSchemaVersion) {
    return ObservableDecodeResult.invalid(
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.unsupportedSchemaVersion,
        detail: 'unsupported snapshot schema_version $schemaVersion',
      ),
    );
  }

  final stability = _stringField(root, 'stability');
  if (stability == null) {
    return _missing('stability');
  }
  if (stability != kObservableStaticSnapshotStability) {
    return ObservableDecodeResult.invalid(
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.unsupportedContract,
        detail: 'unsupported snapshot stability $stability',
      ),
    );
  }

  final producerValue = root['producer'];
  if (producerValue is! Map) {
    return _missing('producer');
  }
  final producerMap = _asStringKeyed(producerValue);
  final producerName = _stringField(producerMap, 'name');
  final producerVersion = _stringField(producerMap, 'version');
  if (producerName == null || producerVersion == null) {
    return _missing('producer.name/version');
  }

  final capabilitiesValue = root['capabilities'];
  if (capabilitiesValue is! List) {
    return _missing('capabilities');
  }
  final capabilities = <String>[];
  for (final item in capabilitiesValue) {
    if (item is! String) {
      return _missing('capabilities[]');
    }
    capabilities.add(item);
  }
  final advertised = capabilities.toSet();
  for (final required in kObservableRequiredCapabilities) {
    if (!advertised.contains(required)) {
      return ObservableDecodeResult.invalid(
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.missingCapability,
          detail: 'snapshot is missing required capability $required',
        ),
      );
    }
  }

  final unitValue = root['compilation_unit'];
  if (unitValue is! Map) {
    return _missing('compilation_unit');
  }
  final unitMap = _asStringKeyed(unitValue);
  final packageName = _stringField(unitMap, 'package_name');
  final manifestPath = _stringField(unitMap, 'manifest_path');
  final entryPath = _stringField(unitMap, 'entry_path');
  if (packageName == null || manifestPath == null || entryPath == null) {
    return _missing('compilation_unit fields');
  }

  final completenessRaw = _stringField(root, 'completeness');
  if (completenessRaw == null) {
    return _missing('completeness');
  }
  final completeness = ObservableCompletenessX.fromWire(completenessRaw);
  if (completeness == null) {
    return ObservableDecodeResult.invalid(
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.unsupportedCompleteness,
        detail: 'unsupported snapshot completeness $completenessRaw',
      ),
    );
  }

  if (!root.containsKey('root')) {
    return _missing('root');
  }
  final rootValue = root['root'];
  final String? rootId;
  if (rootValue == null) {
    rootId = null;
  } else if (rootValue is String && rootValue.isNotEmpty) {
    rootId = rootValue;
  } else {
    return const ObservableDecodeResult.invalid(
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.danglingReference,
        detail: 'snapshot root does not resolve',
      ),
    );
  }

  final nodesResult = _decodeNodes(root['nodes']);
  if (nodesResult.failure != null) {
    return ObservableDecodeResult.invalid(nodesResult.failure!);
  }
  final edgesResult = _decodeEdges(root['edges']);
  if (edgesResult.failure != null) {
    return ObservableDecodeResult.invalid(edgesResult.failure!);
  }
  final factsResult = _decodeFacts(root['facts']);
  if (factsResult.failure != null) {
    return ObservableDecodeResult.invalid(factsResult.failure!);
  }
  final anchorsResult = _decodeAnchors(root['anchors']);
  if (anchorsResult.failure != null) {
    return ObservableDecodeResult.invalid(anchorsResult.failure!);
  }
  final evidenceResult = _decodeEvidence(root['evidence']);
  if (evidenceResult.failure != null) {
    return ObservableDecodeResult.invalid(evidenceResult.failure!);
  }

  final nodes = nodesResult.items;
  final edges = edgesResult.items;
  final facts = factsResult.items;
  final anchors = anchorsResult.items;
  final evidence = evidenceResult.items;

  final ids = <String>{};
  ObservableDecodeFailure? duplicate(String id) {
    if (!ids.add(id)) {
      return ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.duplicateId,
        detail: 'duplicate id $id',
      );
    }
    return null;
  }

  for (final node in nodes) {
    final failure = duplicate(node.id);
    if (failure != null) {
      return ObservableDecodeResult.invalid(failure);
    }
  }
  for (final edge in edges) {
    final failure = duplicate(edge.id);
    if (failure != null) {
      return ObservableDecodeResult.invalid(failure);
    }
  }
  for (final fact in facts) {
    final failure = duplicate(fact.id);
    if (failure != null) {
      return ObservableDecodeResult.invalid(failure);
    }
  }
  for (final anchor in anchors) {
    final failure = duplicate(anchor.ref);
    if (failure != null) {
      return ObservableDecodeResult.invalid(failure);
    }
  }
  for (final record in evidence) {
    final failure = duplicate(record.ref);
    if (failure != null) {
      return ObservableDecodeResult.invalid(failure);
    }
  }

  final nodeIds = nodes.map((node) => node.id).toSet();
  final edgeIds = edges.map((edge) => edge.id).toSet();
  final factIds = facts.map((fact) => fact.id).toSet();
  final evidenceSubjects = <String>{...nodeIds, ...edgeIds, ...factIds};
  final anchorRefs = anchors.map((anchor) => anchor.ref).toSet();
  final evidenceRefs = evidence.map((record) => record.ref).toSet();

  if (completeness == ObservableCompleteness.provenScalarNoop) {
    if (rootId != null ||
        nodes.isNotEmpty ||
        edges.isNotEmpty ||
        facts.isNotEmpty ||
        anchors.isNotEmpty) {
      return const ObservableDecodeResult.invalid(
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.unsupportedCompleteness,
          detail:
              'complete/proven-scalar-noop requires a null root and empty topology collections',
        ),
      );
    }
  } else if (rootId == null || !nodeIds.contains(rootId)) {
    return const ObservableDecodeResult.invalid(
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.danglingReference,
        detail: 'snapshot root does not resolve',
      ),
    );
  }

  for (final node in nodes) {
    if (!evidenceRefs.contains(node.evidence)) {
      return _dangling('node evidence ${node.evidence}');
    }
    for (final ref in node.anchors) {
      if (!anchorRefs.contains(ref)) {
        return _dangling('node anchor $ref');
      }
    }
  }
  for (final edge in edges) {
    if (!nodeIds.contains(edge.from) || !nodeIds.contains(edge.to)) {
      return _dangling('edge endpoint');
    }
    if (!evidenceRefs.contains(edge.evidence)) {
      return _dangling('edge evidence ${edge.evidence}');
    }
  }
  for (final fact in facts) {
    if (!nodeIds.contains(fact.subject)) {
      return _dangling('fact subject ${fact.subject}');
    }
    if (!evidenceRefs.contains(fact.evidence)) {
      return _dangling('fact evidence ${fact.evidence}');
    }
  }
  for (final record in evidence) {
    for (final subject in record.subjects) {
      if (!evidenceSubjects.contains(subject)) {
        return _dangling('evidence subject $subject');
      }
    }
    for (final prerequisite in record.prerequisites) {
      if (!evidenceRefs.contains(prerequisite)) {
        return _dangling('evidence prerequisite $prerequisite');
      }
    }
    for (final ref in record.anchors) {
      if (!anchorRefs.contains(ref)) {
        return _dangling('evidence anchor $ref');
      }
    }
  }

  final cycle = _evidenceCycle(evidence);
  if (cycle != null) {
    return ObservableDecodeResult.invalid(cycle);
  }

  const knownRoot = <String>{
    'contract',
    'schema_version',
    'stability',
    'producer',
    'capabilities',
    'compilation_unit',
    'completeness',
    'root',
    'nodes',
    'edges',
    'facts',
    'anchors',
    'evidence',
  };

  return ObservableDecodeResult.ok(
    ObservableSnapshot(
      contract: contract,
      schemaVersion: schemaVersion,
      stability: stability,
      producer: ObservableProducer(name: producerName, version: producerVersion),
      capabilities: List<String>.unmodifiable(capabilities),
      compilationUnit: ObservableCompilationUnit(
        packageName: packageName,
        manifestPath: manifestPath,
        entryPath: entryPath,
      ),
      completeness: completeness,
      root: rootId,
      nodes: List<ObservableNodeRecord>.unmodifiable(nodes),
      edges: List<ObservableEdgeRecord>.unmodifiable(edges),
      facts: List<ObservableFactRecord>.unmodifiable(facts),
      anchors: List<ObservableAnchorRecord>.unmodifiable(anchors),
      evidence: List<ObservableEvidenceRecord>.unmodifiable(evidence),
      extensions: _extensions(root, knownRoot),
    ),
  );
}

class _ListDecode<T> {
  const _ListDecode(this.items, [this.failure]);

  final List<T> items;
  final ObservableDecodeFailure? failure;
}

_ListDecode<ObservableNodeRecord> _decodeNodes(Object? value) {
  if (value is! List) {
    return const _ListDecode<ObservableNodeRecord>(
      <ObservableNodeRecord>[],
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.missingField,
        detail: 'missing field nodes',
      ),
    );
  }
  const known = <String>{'id', 'kind', 'role', 'anchors', 'evidence'};
  final items = <ObservableNodeRecord>[];
  for (final item in value) {
    if (item is! Map) {
      return const _ListDecode<ObservableNodeRecord>(
        <ObservableNodeRecord>[],
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.missingField,
          detail: 'node record is invalid',
        ),
      );
    }
    final map = _asStringKeyed(item);
    final id = _stringField(map, 'id');
    final kind = _stringField(map, 'kind');
    final role = _stringField(map, 'role');
    final evidence = _stringField(map, 'evidence');
    final anchorsValue = map['anchors'];
    if (id == null ||
        kind == null ||
        role == null ||
        evidence == null ||
        anchorsValue is! List) {
      return const _ListDecode<ObservableNodeRecord>(
        <ObservableNodeRecord>[],
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.missingField,
          detail: 'node record is missing required fields',
        ),
      );
    }
    final anchors = <String>[];
    for (final ref in anchorsValue) {
      if (ref is! String) {
        return const _ListDecode<ObservableNodeRecord>(
          <ObservableNodeRecord>[],
          ObservableDecodeFailure(
            subcode: ObservableInvalidSubcode.missingField,
            detail: 'node anchors must be strings',
          ),
        );
      }
      anchors.add(ref);
    }
    items.add(
      ObservableNodeRecord(
        id: id,
        kind: ObservableNodeKindX.fromWire(kind),
        rawKind: kind,
        role: role,
        anchors: List<String>.unmodifiable(anchors),
        evidence: evidence,
        extensions: _extensions(map, known),
      ),
    );
  }
  return _ListDecode<ObservableNodeRecord>(items);
}

_ListDecode<ObservableEdgeRecord> _decodeEdges(Object? value) {
  if (value is! List) {
    return const _ListDecode<ObservableEdgeRecord>(
      <ObservableEdgeRecord>[],
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.missingField,
        detail: 'missing field edges',
      ),
    );
  }
  const known = <String>{'id', 'kind', 'from', 'to', 'evidence'};
  final items = <ObservableEdgeRecord>[];
  for (final item in value) {
    if (item is! Map) {
      return const _ListDecode<ObservableEdgeRecord>(
        <ObservableEdgeRecord>[],
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.missingField,
          detail: 'edge record is invalid',
        ),
      );
    }
    final map = _asStringKeyed(item);
    final id = _stringField(map, 'id');
    final kind = _stringField(map, 'kind');
    final from = _stringField(map, 'from');
    final to = _stringField(map, 'to');
    final evidence = _stringField(map, 'evidence');
    if (id == null ||
        kind == null ||
        from == null ||
        to == null ||
        evidence == null) {
      return const _ListDecode<ObservableEdgeRecord>(
        <ObservableEdgeRecord>[],
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.missingField,
          detail: 'edge record is missing required fields',
        ),
      );
    }
    items.add(
      ObservableEdgeRecord(
        id: id,
        kind: ObservableEdgeKindX.fromWire(kind),
        rawKind: kind,
        from: from,
        to: to,
        evidence: evidence,
        extensions: _extensions(map, known),
      ),
    );
  }
  return _ListDecode<ObservableEdgeRecord>(items);
}

_ListDecode<ObservableFactRecord> _decodeFacts(Object? value) {
  if (value is! List) {
    return const _ListDecode<ObservableFactRecord>(
      <ObservableFactRecord>[],
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.missingField,
        detail: 'missing field facts',
      ),
    );
  }
  const known = <String>{'id', 'subject', 'predicate', 'value', 'evidence'};
  final items = <ObservableFactRecord>[];
  for (final item in value) {
    if (item is! Map) {
      return const _ListDecode<ObservableFactRecord>(
        <ObservableFactRecord>[],
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.missingField,
          detail: 'fact record is invalid',
        ),
      );
    }
    final map = _asStringKeyed(item);
    final id = _stringField(map, 'id');
    final subject = _stringField(map, 'subject');
    final predicate = _stringField(map, 'predicate');
    final evidence = _stringField(map, 'evidence');
    if (id == null ||
        subject == null ||
        predicate == null ||
        evidence == null ||
        !map.containsKey('value')) {
      return const _ListDecode<ObservableFactRecord>(
        <ObservableFactRecord>[],
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.missingField,
          detail: 'fact record is missing required fields',
        ),
      );
    }
    items.add(
      ObservableFactRecord(
        id: id,
        subject: subject,
        predicate: predicate,
        canonicalValue: _canonicalFactValue(map['value']),
        evidence: evidence,
        extensions: _extensions(map, known),
      ),
    );
  }
  return _ListDecode<ObservableFactRecord>(items);
}

_ListDecode<ObservableAnchorRecord> _decodeAnchors(Object? value) {
  if (value is! List) {
    return const _ListDecode<ObservableAnchorRecord>(
      <ObservableAnchorRecord>[],
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.missingField,
        detail: 'missing field anchors',
      ),
    );
  }
  const known = <String>{'ref', 'path', 'precision'};
  final items = <ObservableAnchorRecord>[];
  for (final item in value) {
    if (item is! Map) {
      return const _ListDecode<ObservableAnchorRecord>(
        <ObservableAnchorRecord>[],
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.missingField,
          detail: 'anchor record is invalid',
        ),
      );
    }
    final map = _asStringKeyed(item);
    final ref = _stringField(map, 'ref');
    final path = _stringField(map, 'path');
    final precision = _stringField(map, 'precision');
    if (ref == null || path == null || precision == null) {
      return const _ListDecode<ObservableAnchorRecord>(
        <ObservableAnchorRecord>[],
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.missingField,
          detail: 'anchor record is missing required fields',
        ),
      );
    }
    items.add(
      ObservableAnchorRecord(
        ref: ref,
        path: path,
        precision: precision,
        extensions: _extensions(map, known),
      ),
    );
  }
  return _ListDecode<ObservableAnchorRecord>(items);
}

_ListDecode<ObservableEvidenceRecord> _decodeEvidence(Object? value) {
  if (value is! List) {
    return const _ListDecode<ObservableEvidenceRecord>(
      <ObservableEvidenceRecord>[],
      ObservableDecodeFailure(
        subcode: ObservableInvalidSubcode.missingField,
        detail: 'missing field evidence',
      ),
    );
  }
  const known = <String>{
    'ref',
    'producer_rule',
    'rule_version',
    'subjects',
    'prerequisites',
    'anchors',
  };
  final items = <ObservableEvidenceRecord>[];
  for (final item in value) {
    if (item is! Map) {
      return const _ListDecode<ObservableEvidenceRecord>(
        <ObservableEvidenceRecord>[],
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.missingField,
          detail: 'evidence record is invalid',
        ),
      );
    }
    final map = _asStringKeyed(item);
    final ref = _stringField(map, 'ref');
    final producerRule = _stringField(map, 'producer_rule');
    final ruleVersion = _stringField(map, 'rule_version');
    final subjects = _stringList(map['subjects']);
    final prerequisites = _stringList(map['prerequisites']);
    final anchors = _stringList(map['anchors']);
    if (ref == null ||
        producerRule == null ||
        ruleVersion == null ||
        subjects == null ||
        prerequisites == null ||
        anchors == null) {
      return const _ListDecode<ObservableEvidenceRecord>(
        <ObservableEvidenceRecord>[],
        ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.missingField,
          detail: 'evidence record is missing required fields',
        ),
      );
    }
    items.add(
      ObservableEvidenceRecord(
        ref: ref,
        producerRule: producerRule,
        ruleVersion: ruleVersion,
        subjects: List<String>.unmodifiable(subjects),
        prerequisites: List<String>.unmodifiable(prerequisites),
        anchors: List<String>.unmodifiable(anchors),
        extensions: _extensions(map, known),
      ),
    );
  }
  return _ListDecode<ObservableEvidenceRecord>(items);
}

ObservableDecodeFailure? _evidenceCycle(List<ObservableEvidenceRecord> evidence) {
  final index = <String, int>{};
  for (var i = 0; i < evidence.length; i += 1) {
    index[evidence[i].ref] = i;
  }
  final indegree = List<int>.filled(evidence.length, 0);
  final adj = List<List<int>>.generate(evidence.length, (_) => <int>[]);
  for (var i = 0; i < evidence.length; i += 1) {
    for (final prerequisite in evidence[i].prerequisites) {
      final from = index[prerequisite];
      if (from == null) {
        return ObservableDecodeFailure(
          subcode: ObservableInvalidSubcode.danglingReference,
          detail: 'evidence prerequisite $prerequisite does not resolve',
        );
      }
      adj[from].add(i);
      indegree[i] += 1;
    }
  }
  final ready = <int>[];
  for (var i = 0; i < evidence.length; i += 1) {
    if (indegree[i] == 0) {
      ready.add(i);
    }
  }
  var seen = 0;
  for (var cursor = 0; cursor < ready.length; cursor += 1) {
    seen += 1;
    for (final next in adj[ready[cursor]]) {
      indegree[next] -= 1;
      if (indegree[next] == 0) {
        ready.add(next);
      }
    }
  }
  if (seen != evidence.length) {
    return const ObservableDecodeFailure(
      subcode: ObservableInvalidSubcode.evidenceCycle,
      detail: 'evidence graph contains a cycle',
    );
  }
  return null;
}

ObservableDecodeResult _missing(String field) {
  return ObservableDecodeResult.invalid(
    ObservableDecodeFailure(
      subcode: ObservableInvalidSubcode.missingField,
      detail: 'missing field $field',
    ),
  );
}

ObservableDecodeResult _dangling(String detail) {
  return ObservableDecodeResult.invalid(
    ObservableDecodeFailure(
      subcode: ObservableInvalidSubcode.danglingReference,
      detail: detail,
    ),
  );
}

Map<String, Object?> _asStringKeyed(Map value) {
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String? _stringField(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

int? _intField(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

List<String>? _stringList(Object? value) {
  if (value is! List) {
    return null;
  }
  final items = <String>[];
  for (final item in value) {
    if (item is! String) {
      return null;
    }
    items.add(item);
  }
  return items;
}

Map<String, Object?> _extensions(Map<String, Object?> map, Set<String> known) {
  final extras = <String, Object?>{};
  for (final entry in map.entries) {
    if (!known.contains(entry.key)) {
      extras[entry.key] = entry.value;
    }
  }
  if (extras.isEmpty) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(extras);
}

String _canonicalFactValue(Object? value) {
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return jsonEncode(value);
  }
  if (value is List) {
    return jsonEncode(value);
  }
  if (value is Map) {
    return jsonEncode(value);
  }
  return 'null';
}
