import 'dart:convert';

import 'observable_delta_model.dart';

ObservableDeltaDecodeResult decodeObservableDeltaJson(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (error) {
    return ObservableDeltaDecodeResult.invalid(
      ObservableDeltaDecodeFailure(
        reason: ObservableReasonCodeWire.malformedDelta,
        subcode: ObservableDeltaSubcode.missingField,
        detail: 'delta is not valid JSON: ${error.message}',
      ),
    );
  }
  if (decoded is! Map) {
    return const ObservableDeltaDecodeResult.invalid(
      ObservableDeltaDecodeFailure(
        reason: ObservableReasonCodeWire.malformedDelta,
        subcode: ObservableDeltaSubcode.missingField,
        detail: 'delta must be an object',
      ),
    );
  }
  return decodeObservableDeltaMap(
    decoded.map(
      (key, value) => MapEntry<String, Object?>(key.toString(), value),
    ),
  );
}

ObservableDeltaDecodeResult decodeObservableDeltaBytes(List<int> bytes) {
  return decodeObservableDeltaJson(utf8.decode(bytes));
}

class ObservableReasonCodeWire {
  static const String malformedDelta = 'malformed-delta';
  static const String unsupportedDelta = 'unsupported-delta';
}

ObservableDeltaDecodeResult decodeObservableDeltaMap(Map<String, Object?> root) {
  final contract = _stringField(root, 'contract');
  if (contract == null) {
    return _missing('contract');
  }
  if (contract != kObservableDeltaContract) {
    return const ObservableDeltaDecodeResult.invalid(
      ObservableDeltaDecodeFailure(
        reason: ObservableReasonCodeWire.malformedDelta,
        subcode: ObservableDeltaSubcode.unsupportedContract,
        detail: 'unsupported delta contract',
      ),
    );
  }

  final schemaValue = root['schema_version'];
  if (schemaValue is! Map) {
    return _missing('schema_version');
  }
  final schema = _asStringKeyed(schemaValue);
  final major = _intField(schema, 'major');
  final minor = _intField(schema, 'minor');
  if (major == null || minor == null) {
    return _missing('schema_version.major/minor');
  }
  if (major != kObservableDeltaSchemaMajor) {
    return const ObservableDeltaDecodeResult.invalid(
      ObservableDeltaDecodeFailure(
        reason: ObservableReasonCodeWire.unsupportedDelta,
        subcode: ObservableDeltaSubcode.majorIncompatible,
        detail: 'delta schema major is not 0',
      ),
    );
  }

  final stability = _stringField(root, 'stability');
  if (stability == null) {
    return _missing('stability');
  }
  if (stability != kObservableDeltaStability) {
    return const ObservableDeltaDecodeResult.invalid(
      ObservableDeltaDecodeFailure(
        reason: ObservableReasonCodeWire.malformedDelta,
        subcode: ObservableDeltaSubcode.unsupportedContract,
        detail: 'unsupported delta stability',
      ),
    );
  }

  final parentId = _stringField(root, 'parent_snapshot_id');
  final targetId = _stringField(root, 'target_snapshot_id');
  if (parentId == null) {
    return _missing('parent_snapshot_id');
  }
  if (targetId == null) {
    return _missing('target_snapshot_id');
  }
  if (!isObservableSnapshotIdentity(parentId) ||
      !isObservableSnapshotIdentity(targetId)) {
    return const ObservableDeltaDecodeResult.invalid(
      ObservableDeltaDecodeFailure(
        reason: ObservableReasonCodeWire.malformedDelta,
        subcode: ObservableDeltaSubcode.malformedIdentity,
        detail: 'delta snapshot identities are malformed',
      ),
    );
  }

  final requiredCaps = _stringList(root['required_capabilities']);
  final optionalCaps = _stringList(root['optional_capabilities']);
  if (requiredCaps == null) {
    return _missing('required_capabilities');
  }
  if (optionalCaps == null) {
    return _missing('optional_capabilities');
  }
  final closed = kObservableDeltaClosedCapabilities.toSet();
  for (final capability in requiredCaps) {
    if (!closed.contains(capability)) {
      return ObservableDeltaDecodeResult.invalid(
        ObservableDeltaDecodeFailure(
          reason: ObservableReasonCodeWire.unsupportedDelta,
          subcode: ObservableDeltaSubcode.unknownRequiredCapability,
          detail: 'unknown required capability $capability',
        ),
      );
    }
  }

  final operationsValue = root['operations'];
  if (operationsValue is! List) {
    return _missing('operations');
  }
  final operations = <ObservableDeltaOperation>[];
  for (final item in operationsValue) {
    if (item is! Map) {
      return _missing('operations[]');
    }
    final map = _asStringKeyed(item);
    final decoded = _decodeOperation(map);
    if (decoded.failure != null) {
      return ObservableDeltaDecodeResult.invalid(decoded.failure!);
    }
    operations.add(decoded.operation!);
  }

  const known = <String>{
    'contract',
    'schema_version',
    'stability',
    'parent_snapshot_id',
    'target_snapshot_id',
    'required_capabilities',
    'optional_capabilities',
    'operations',
  };

  return ObservableDeltaDecodeResult.ok(
    ObservableDeltaEnvelope(
      contract: contract,
      schemaMajor: major,
      schemaMinor: minor,
      stability: stability,
      parentSnapshotId: parentId,
      targetSnapshotId: targetId,
      requiredCapabilities: List<String>.unmodifiable(requiredCaps),
      optionalCapabilities: List<String>.unmodifiable(optionalCaps),
      operations: List<ObservableDeltaOperation>.unmodifiable(operations),
      extensions: _extensions(root, known),
    ),
  );
}

class _OpDecode {
  const _OpDecode(this.operation, [this.failure]);

  final ObservableDeltaOperation? operation;
  final ObservableDeltaDecodeFailure? failure;
}

_OpDecode _decodeOperation(Map<String, Object?> map) {
  final opRaw = _stringField(map, 'op');
  final categoryRaw = _stringField(map, 'category');
  final key = _stringField(map, 'key');
  if (opRaw == null) {
    return const _OpDecode(
      null,
      ObservableDeltaDecodeFailure(
        reason: ObservableReasonCodeWire.malformedDelta,
        subcode: ObservableDeltaSubcode.missingField,
        detail: 'operation is missing op',
      ),
    );
  }
  if (categoryRaw == null) {
    return const _OpDecode(
      null,
      ObservableDeltaDecodeFailure(
        reason: ObservableReasonCodeWire.malformedDelta,
        subcode: ObservableDeltaSubcode.missingField,
        detail: 'operation is missing category',
      ),
    );
  }
  if (key == null) {
    return const _OpDecode(
      null,
      ObservableDeltaDecodeFailure(
        reason: ObservableReasonCodeWire.malformedDelta,
        subcode: ObservableDeltaSubcode.missingField,
        detail: 'operation is missing key',
      ),
    );
  }
  final op = ObservableDeltaOpX.fromWire(opRaw);
  if (op == null) {
    return const _OpDecode(
      null,
      ObservableDeltaDecodeFailure(
        reason: ObservableReasonCodeWire.malformedDelta,
        subcode: ObservableDeltaSubcode.unknownOp,
        detail: 'unknown delta op',
      ),
    );
  }
  final category = ObservableDeltaCategoryX.fromWire(categoryRaw);
  if (category == null) {
    return const _OpDecode(
      null,
      ObservableDeltaDecodeFailure(
        reason: ObservableReasonCodeWire.malformedDelta,
        subcode: ObservableDeltaSubcode.unknownCategory,
        detail: 'unknown delta category',
      ),
    );
  }
  Map<String, Object?>? record;
  var fields = const <ObservableFieldReplacement>[];
  if (op == ObservableDeltaOp.add) {
    final recordValue = map['record'];
    if (recordValue is! Map) {
      return const _OpDecode(
        null,
        ObservableDeltaDecodeFailure(
          reason: ObservableReasonCodeWire.malformedDelta,
          subcode: ObservableDeltaSubcode.missingField,
          detail: 'add operation is missing record',
        ),
      );
    }
    record = _asStringKeyed(recordValue);
  } else if (op == ObservableDeltaOp.replaceFields) {
    final fieldsValue = map['fields'];
    if (fieldsValue is! List) {
      return const _OpDecode(
        null,
        ObservableDeltaDecodeFailure(
          reason: ObservableReasonCodeWire.malformedDelta,
          subcode: ObservableDeltaSubcode.missingField,
          detail: 'replace_fields is missing fields',
        ),
      );
    }
    final parsed = <ObservableFieldReplacement>[];
    for (final field in fieldsValue) {
      if (field is! Map) {
        return const _OpDecode(
          null,
          ObservableDeltaDecodeFailure(
            reason: ObservableReasonCodeWire.malformedDelta,
            subcode: ObservableDeltaSubcode.missingField,
            detail: 'field replacement is invalid',
          ),
        );
      }
      final fieldMap = _asStringKeyed(field);
      final name = _stringField(fieldMap, 'name');
      if (name == null || !fieldMap.containsKey('before') || !fieldMap.containsKey('after')) {
        return const _OpDecode(
          null,
          ObservableDeltaDecodeFailure(
            reason: ObservableReasonCodeWire.malformedDelta,
            subcode: ObservableDeltaSubcode.missingField,
            detail: 'field replacement is missing required fields',
          ),
        );
      }
      parsed.add(
        ObservableFieldReplacement(
          name: name,
          before: fieldMap['before'],
          after: fieldMap['after'],
        ),
      );
    }
    fields = List<ObservableFieldReplacement>.unmodifiable(parsed);
  }
  return _OpDecode(
    ObservableDeltaOperation(
      op: op,
      category: category,
      key: key,
      record: record == null
          ? null
          : Map<String, Object?>.unmodifiable(record),
      fields: fields,
    ),
  );
}

ObservableDeltaDecodeResult _missing(String field) {
  return ObservableDeltaDecodeResult.invalid(
    ObservableDeltaDecodeFailure(
      reason: ObservableReasonCodeWire.malformedDelta,
      subcode: ObservableDeltaSubcode.missingField,
      detail: 'missing field $field',
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
