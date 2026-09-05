import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'observable_delta_decoder.dart';
import 'observable_delta_model.dart';
import 'observable_snapshot_cache.dart';
import 'observable_snapshot_decoder.dart';
import 'observable_snapshot_model.dart';

class ObservableRetainedIdentity {
  const ObservableRetainedIdentity({
    required this.snapshotId,
    this.parentSnapshotId,
  });

  final String snapshotId;
  final String? parentSnapshotId;
}

class ObservableDeltaIntakeInput {
  const ObservableDeltaIntakeInput({
    required this.childBytes,
    required this.childSnapshotId,
    this.deltaBytes,
    this.headBytes,
    this.headSnapshotId,
    this.retained = const <ObservableRetainedIdentity>[],
  });

  final List<int> childBytes;
  final String childSnapshotId;
  final List<int>? deltaBytes;
  final List<int>? headBytes;
  final String? headSnapshotId;
  final List<ObservableRetainedIdentity> retained;
}

class ObservableDeltaIntakeResult {
  const ObservableDeltaIntakeResult._({
    required this.accepted,
    this.usedDelta = false,
    this.child,
    this.delta,
    this.childIdentity,
    this.reconstructedBytes,
    this.reason,
    this.subcode,
    this.detail,
  });

  factory ObservableDeltaIntakeResult.accepted({
    required ObservableSnapshot child,
    required SnapshotIdentity childIdentity,
    ObservableDeltaEnvelope? delta,
    List<int>? reconstructedBytes,
    required bool usedDelta,
  }) {
    return ObservableDeltaIntakeResult._(
      accepted: true,
      usedDelta: usedDelta,
      child: child,
      delta: delta,
      childIdentity: childIdentity,
      reconstructedBytes: reconstructedBytes,
    );
  }

  factory ObservableDeltaIntakeResult.rejected({
    required ObservableReasonCode reason,
    ObservableDeltaSubcode? subcode,
    required String detail,
  }) {
    return ObservableDeltaIntakeResult._(
      accepted: false,
      reason: reason,
      subcode: subcode,
      detail: detail,
    );
  }

  final bool accepted;
  final bool usedDelta;
  final ObservableSnapshot? child;
  final ObservableDeltaEnvelope? delta;
  final SnapshotIdentity? childIdentity;
  final List<int>? reconstructedBytes;
  final ObservableReasonCode? reason;
  final ObservableDeltaSubcode? subcode;
  final String? detail;
}

Future<ObservableDeltaIntakeResult> computeObservableDeltaIntake(
  ObservableDeltaIntakeInput input,
) {
  return compute(intakeObservableDelta, input);
}

ObservableDeltaApplyResult applyObservableDelta(
  List<int> parentBytes,
  ObservableDeltaEnvelope delta,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(parentBytes));
  } on FormatException catch (error) {
    return ObservableDeltaApplyResult.rejected(
      ObservableDeltaApplyRejection(
        reason: 'malformed-delta',
        subcode: ObservableDeltaSubcode.missingField,
        detail: 'parent snapshot is not valid JSON: ${error.message}',
      ),
    );
  }
  if (decoded is! Map) {
    return const ObservableDeltaApplyResult.rejected(
      ObservableDeltaApplyRejection(
        reason: 'malformed-delta',
        subcode: ObservableDeltaSubcode.missingField,
        detail: 'parent snapshot must be an object',
      ),
    );
  }
  final tree = <String, Object?>{
    for (final entry in decoded.entries) entry.key.toString(): entry.value,
  };
  final parentNodeIds = _idsIn(tree['nodes'], 'id');
  for (final operation in delta.operations) {
    final rejection = _applyOperation(tree, operation, parentNodeIds);
    if (rejection != null) {
      return ObservableDeltaApplyResult.rejected(rejection);
    }
  }
  final canonical = _canonicalize(tree);
  final encoded = utf8.encode('${json.encode(canonical)}\n');
  return ObservableDeltaApplyResult.ok(encoded);
}

  ObservableDeltaIntakeResult intakeObservableDelta(
  ObservableDeltaIntakeInput input,
) {
  final deltaBytes = input.deltaBytes;
  // Identical child bytes are a no-op decided by the caller, which holds the
  // current head identity; the intake always decodes and verifies.
  if (deltaBytes == null || deltaBytes.isEmpty) {
    return _decodeChildOnly(input);
  }

  final decodedDelta = decodeObservableDeltaBytes(deltaBytes);
  if (!decodedDelta.isOk) {
    final failure = decodedDelta.failure!;
    return ObservableDeltaIntakeResult.rejected(
      reason: failure.reason == ObservableReasonCodeWire.unsupportedDelta
          ? ObservableReasonCode.unsupportedDelta
          : ObservableReasonCode.malformedDelta,
      subcode: failure.subcode,
      detail: failure.detail,
    );
  }
  final delta = decodedDelta.envelope!;
  final classified = _classify(delta, input);
  if (classified != null) {
    return classified;
  }
  if (input.headBytes == null) {
    return ObservableDeltaIntakeResult.rejected(
      reason: ObservableReasonCode.wrongParent,
      subcode: ObservableDeltaSubcode.noParent,
      detail: 'no retained parent bytes',
    );
  }
  final applied = applyObservableDelta(input.headBytes!, delta);
  if (!applied.isOk) {
    return ObservableDeltaIntakeResult.rejected(
      reason: ObservableReasonCode.malformedDelta,
      subcode: applied.rejection!.subcode,
      detail: applied.rejection!.detail,
    );
  }
  final reconstructed = applied.bytes!;
  final reconstructedId = observableSnapshotId(reconstructed);
  if (reconstructedId != delta.targetSnapshotId) {
    return ObservableDeltaIntakeResult.rejected(
      reason: ObservableReasonCode.invalidDelta,
      subcode: ObservableDeltaSubcode.targetMismatch,
      detail: 'reconstructed identity does not match target_snapshot_id',
    );
  }
  if (!_bytesEqual(reconstructed, input.childBytes)) {
    return ObservableDeltaIntakeResult.rejected(
      reason: ObservableReasonCode.invalidDelta,
      subcode: ObservableDeltaSubcode.reconstructionMismatch,
      detail: 'reconstructed bytes do not match the published child',
    );
  }
  final child = decodeObservableSnapshotBytes(input.childBytes);
  if (!child.isOk) {
    return ObservableDeltaIntakeResult.rejected(
      reason: ObservableReasonCode.invalidSnapshot,
      detail: child.failure!.detail,
    );
  }
  return ObservableDeltaIntakeResult.accepted(
    child: child.snapshot!,
    childIdentity: SnapshotIdentity.fromSnapshot(
      snapshot: child.snapshot!,
      snapshotId: input.childSnapshotId,
    ),
    delta: delta,
    reconstructedBytes: reconstructed,
    usedDelta: true,
  );
}

ObservableDeltaIntakeResult _decodeChildOnly(ObservableDeltaIntakeInput input) {
  final decoded = decodeObservableSnapshotBytes(input.childBytes);
  if (!decoded.isOk) {
    return ObservableDeltaIntakeResult.rejected(
      reason: ObservableReasonCode.invalidSnapshot,
      detail: decoded.failure!.detail,
    );
  }
  return ObservableDeltaIntakeResult.accepted(
    child: decoded.snapshot!,
    childIdentity: SnapshotIdentity.fromSnapshot(
      snapshot: decoded.snapshot!,
      snapshotId: input.childSnapshotId,
    ),
    usedDelta: false,
  );
}

ObservableDeltaIntakeResult? _classify(
  ObservableDeltaEnvelope delta,
  ObservableDeltaIntakeInput input,
) {
  final head = input.headSnapshotId;
  if (head != null && delta.parentSnapshotId == head) {
    return null;
  }
  final ids = <String>{
    for (final item in input.retained) item.snapshotId,
  };
  String? predecessor;
  if (input.retained.isNotEmpty) {
    predecessor = input.retained.last.parentSnapshotId;
  }
  if (head != null &&
      delta.targetSnapshotId == head &&
      predecessor != null &&
      delta.parentSnapshotId == predecessor) {
    return ObservableDeltaIntakeResult.rejected(
      reason: ObservableReasonCode.duplicateDelta,
      detail: 'delta target is the retained head',
    );
  }
  if (head != null &&
      ids.contains(delta.targetSnapshotId) &&
      delta.targetSnapshotId != head) {
    return ObservableDeltaIntakeResult.rejected(
      reason: ObservableReasonCode.outOfOrderDelta,
      detail: 'delta target is a retained ancestor',
    );
  }
  if (head != null &&
      ids.contains(delta.parentSnapshotId) &&
      delta.parentSnapshotId != head) {
    return ObservableDeltaIntakeResult.rejected(
      reason: ObservableReasonCode.staleDelta,
      detail: 'delta parent is a superseded ancestor',
    );
  }
  return ObservableDeltaIntakeResult.rejected(
    reason: ObservableReasonCode.wrongParent,
    detail: 'delta parent is not the retained head',
  );
}

ObservableDeltaApplyRejection? _applyOperation(
  Map<String, Object?> tree,
  ObservableDeltaOperation operation,
  Set<String> parentNodeIds,
) {
  if (operation.category == ObservableDeltaCategory.metadata) {
    return _applyMetadata(tree, operation);
  }
  if (operation.op == ObservableDeltaOp.add &&
      operation.category == ObservableDeltaCategory.lineage) {
    final record = operation.record;
    final prior = record == null ? null : record['prior'];
    if (prior is List) {
      for (final item in prior) {
        if (item is! String || !parentNodeIds.contains(item)) {
          return const ObservableDeltaApplyRejection(
            reason: 'malformed-delta',
            subcode: ObservableDeltaSubcode.lineagePriorUnresolved,
            detail: 'lineage prior does not resolve in the parent',
          );
        }
      }
    }
  }
  final key = operation.category.wireValue;
  var list = tree[key];
  if (list == null) {
    if (operation.op == ObservableDeltaOp.add &&
        operation.category.isAdditiveArray) {
      list = <Object?>[];
      tree[key] = list;
    } else if (operation.op != ObservableDeltaOp.add) {
      return const ObservableDeltaApplyRejection(
        reason: 'malformed-delta',
        subcode: ObservableDeltaSubcode.missingRecord,
        detail: 'category array is missing',
      );
    } else {
      list = <Object?>[];
      tree[key] = list;
    }
  }
  if (list is! List) {
    return const ObservableDeltaApplyRejection(
      reason: 'malformed-delta',
      subcode: ObservableDeltaSubcode.missingRecord,
      detail: 'category is not an array',
    );
  }
  final identityField = operation.category.identityField;
  final index = _indexOf(list, identityField, operation.key);
  switch (operation.op) {
    case ObservableDeltaOp.add:
      final record = operation.record;
      if (record == null) {
        return const ObservableDeltaApplyRejection(
          reason: 'malformed-delta',
          subcode: ObservableDeltaSubcode.missingField,
          detail: 'add is missing record',
        );
      }
      final recordId = record[identityField];
      if (recordId != operation.key) {
        return const ObservableDeltaApplyRejection(
          reason: 'malformed-delta',
          subcode: ObservableDeltaSubcode.keyMismatch,
          detail: 'add record identity does not match key',
        );
      }
      if (index != -1) {
        return const ObservableDeltaApplyRejection(
          reason: 'malformed-delta',
          subcode: ObservableDeltaSubcode.duplicateKey,
          detail: 'add record already exists',
        );
      }
      _insertSorted(list, identityField, Map<String, Object?>.from(record));
    case ObservableDeltaOp.remove:
      if (index == -1) {
        return const ObservableDeltaApplyRejection(
          reason: 'malformed-delta',
          subcode: ObservableDeltaSubcode.missingRecord,
          detail: 'remove record does not exist',
        );
      }
      list.removeAt(index);
      if (list.isEmpty && operation.category.isAdditiveArray) {
        tree.remove(key);
      }
    case ObservableDeltaOp.replaceFields:
      if (index == -1) {
        return const ObservableDeltaApplyRejection(
          reason: 'malformed-delta',
          subcode: ObservableDeltaSubcode.missingRecord,
          detail: 'replace_fields record does not exist',
        );
      }
      final current = list[index];
      if (current is! Map) {
        return const ObservableDeltaApplyRejection(
          reason: 'malformed-delta',
          subcode: ObservableDeltaSubcode.missingRecord,
          detail: 'replace_fields record is not an object',
        );
      }
      final record = <String, Object?>{
        for (final entry in current.entries) entry.key.toString(): entry.value,
      };
      for (final field in operation.fields) {
        if (!_jsonEquals(record[field.name], field.before)) {
          return ObservableDeltaApplyRejection(
            reason: 'malformed-delta',
            subcode: ObservableDeltaSubcode.beforeMismatch,
            detail: 'field before-value mismatch: ${field.name}',
          );
        }
        record[field.name] = field.after;
      }
      list[index] = record;
  }
  return null;
}

ObservableDeltaApplyRejection? _applyMetadata(
  Map<String, Object?> tree,
  ObservableDeltaOperation operation,
) {
  if (operation.op != ObservableDeltaOp.replaceFields ||
      operation.key != kObservableMetadataSnapshotKey) {
    return const ObservableDeltaApplyRejection(
      reason: 'malformed-delta',
      subcode: ObservableDeltaSubcode.unknownMetadataField,
      detail: 'metadata accepts replace_fields on snapshot only',
    );
  }
  for (final field in operation.fields) {
    if (!kObservableMetadataFieldNames.contains(field.name)) {
      return ObservableDeltaApplyRejection(
        reason: 'malformed-delta',
        subcode: ObservableDeltaSubcode.unknownMetadataField,
        detail: 'unknown metadata field ${field.name}',
      );
    }
    final current = _metadataValue(tree, field.name);
    if (!_jsonEquals(current, field.before)) {
      return ObservableDeltaApplyRejection(
        reason: 'malformed-delta',
        subcode: ObservableDeltaSubcode.beforeMismatch,
        detail: 'field before-value mismatch: ${field.name}',
      );
    }
    _setMetadataValue(tree, field.name, field.after);
  }
  return null;
}

Object? _metadataValue(Map<String, Object?> tree, String name) {
  final producer = tree['producer'];
  final unit = tree['compilation_unit'];
  return switch (name) {
    'completeness' => tree['completeness'],
    'producer_name' => producer is Map ? producer['name'] : null,
    'producer_version' => producer is Map ? producer['version'] : null,
    'root' => tree['root'],
    'capabilities' => tree['capabilities'],
    'package_name' => unit is Map ? unit['package_name'] : null,
    'manifest_path' => unit is Map ? unit['manifest_path'] : null,
    'entry_path' => unit is Map ? unit['entry_path'] : null,
    _ => null,
  };
}

void _setMetadataValue(Map<String, Object?> tree, String name, Object? after) {
  switch (name) {
    case 'completeness':
      tree['completeness'] = after;
    case 'producer_name':
      final producer = _ensureMap(tree, 'producer');
      producer['name'] = after;
    case 'producer_version':
      final producer = _ensureMap(tree, 'producer');
      producer['version'] = after;
    case 'root':
      tree['root'] = after;
    case 'capabilities':
      tree['capabilities'] = after;
    case 'package_name':
      _ensureMap(tree, 'compilation_unit')['package_name'] = after;
    case 'manifest_path':
      _ensureMap(tree, 'compilation_unit')['manifest_path'] = after;
    case 'entry_path':
      _ensureMap(tree, 'compilation_unit')['entry_path'] = after;
  }
}

Map<String, Object?> _ensureMap(Map<String, Object?> tree, String key) {
  final current = tree[key];
  if (current is Map) {
    final mapped = <String, Object?>{
      for (final entry in current.entries) entry.key.toString(): entry.value,
    };
    tree[key] = mapped;
    return mapped;
  }
  final created = <String, Object?>{};
  tree[key] = created;
  return created;
}

int _indexOf(List<Object?> list, String field, String key) {
  var low = 0;
  var high = list.length - 1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final item = list[mid];
    final identity = item is Map ? item[field]?.toString() ?? '' : '';
    final compare = identity.compareTo(key);
    if (compare == 0) {
      return mid;
    }
    if (compare < 0) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}

void _insertSorted(
  List<Object?> list,
  String field,
  Map<String, Object?> record,
) {
  final key = record[field]?.toString() ?? '';
  var low = 0;
  var high = list.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    final item = list[mid];
    final identity = item is Map ? item[field]?.toString() ?? '' : '';
    if (identity.compareTo(key) < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  list.insert(low, record);
}

Set<String> _idsIn(Object? value, String field) {
  final ids = <String>{};
  if (value is! List) {
    return ids;
  }
  for (final item in value) {
    if (item is Map) {
      final id = item[field];
      if (id is String) {
        ids.add(id);
      }
    }
  }
  return ids;
}

Map<String, Object?> _canonicalize(Map<String, Object?> tree) {
  final out = <String, Object?>{};
  for (final key in kObservableSnapshotCanonicalKeys) {
    if (!tree.containsKey(key)) {
      continue;
    }
    final value = tree[key];
    if ((key == 'diagnostics' || key == 'lineage') &&
        value is List &&
        value.isEmpty) {
      continue;
    }
    if (key == 'parent_snapshot_id' &&
        (value == null || (value is String && value.isEmpty))) {
      continue;
    }
    out[key] = value;
  }
  for (final entry in tree.entries) {
    if (out.containsKey(entry.key)) {
      continue;
    }
    if (kObservableSnapshotCanonicalKeys.contains(entry.key)) {
      continue;
    }
    out[entry.key] = entry.value;
  }
  return out;
}

bool _jsonEquals(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == right) {
    return true;
  }
  if (left is num && right is num) {
    return left == right;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      if (!_jsonEquals(left[i], right[i])) {
        return false;
      }
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_jsonEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  return false;
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}
