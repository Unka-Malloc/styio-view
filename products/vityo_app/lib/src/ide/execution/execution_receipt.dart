enum DeveloperOperationKind {
  save,
  analyze,
  format,
  build,
  test,
  run,
  debug,
  sourceControl,
  terminal,
  toolchain,
  packageManagement,
}

enum ExecutionReceiptStatus { succeeded, degraded, blocked, failed, cancelled }

final class BoundedText {
  const BoundedText({required this.text, required this.omittedCodeUnits});

  factory BoundedText.from(Object? value, {required int maxCodeUnits}) {
    if (maxCodeUnits < 0) {
      throw ArgumentError.value(
        maxCodeUnits,
        'maxCodeUnits',
        'must not be negative',
      );
    }
    final source = value?.toString() ?? '';
    if (source.length <= maxCodeUnits) {
      return BoundedText(text: source, omittedCodeUnits: 0);
    }
    var end = maxCodeUnits;
    if (end > 0) {
      final last = source.codeUnitAt(end - 1);
      if (last >= 0xD800 && last <= 0xDBFF) {
        end -= 1;
      }
    }
    return BoundedText(
      text: source.substring(0, end),
      omittedCodeUnits: source.length - end,
    );
  }

  static const empty = BoundedText(text: '', omittedCodeUnits: 0);

  final String text;
  final int omittedCodeUnits;

  bool get truncated => omittedCodeUnits > 0;

  BoundedText bounded(int maxCodeUnits) {
    if (text.length <= maxCodeUnits) {
      return this;
    }
    final bounded = BoundedText.from(text, maxCodeUnits: maxCodeUnits);
    return BoundedText(
      text: bounded.text,
      omittedCodeUnits: omittedCodeUnits + bounded.omittedCodeUnits,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'truncated': truncated,
    'omittedCodeUnits': omittedCodeUnits,
  };

  @override
  bool operator ==(Object other) =>
      other is BoundedText &&
      text == other.text &&
      omittedCodeUnits == other.omittedCodeUnits;

  @override
  int get hashCode => Object.hash(text, omittedCodeUnits);
}

final class ExecutionReceipt {
  ExecutionReceipt({
    required this.operationId,
    required this.kind,
    required this.status,
    required this.workspaceRevision,
    required List<String> capabilityIds,
    required this.provenance,
    required this.message,
    required this.startedAt,
    required this.completedAt,
    this.exitCode,
    this.output = BoundedText.empty,
    this.errorOutput = BoundedText.empty,
  }) : capabilityIds = List<String>.unmodifiable(capabilityIds) {
    if (operationId.trim().isEmpty) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'must not be empty',
      );
    }
    if (workspaceRevision < 0) {
      throw ArgumentError.value(
        workspaceRevision,
        'workspaceRevision',
        'must not be negative',
      );
    }
    if (this.capabilityIds.isEmpty ||
        this.capabilityIds.any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(
        capabilityIds,
        'capabilityIds',
        'must contain non-empty ids',
      );
    }
    if (provenance.trim().isEmpty || message.trim().isEmpty) {
      throw ArgumentError('Receipt provenance and message must not be empty.');
    }
    if (completedAt.isBefore(startedAt)) {
      throw ArgumentError('Receipt completion precedes its start.');
    }
  }

  final String operationId;
  final DeveloperOperationKind kind;
  final ExecutionReceiptStatus status;
  final int workspaceRevision;
  final List<String> capabilityIds;
  final String provenance;
  final String message;
  final DateTime startedAt;
  final DateTime completedAt;
  final int? exitCode;
  final BoundedText output;
  final BoundedText errorOutput;

  Duration get duration => completedAt.difference(startedAt);

  Map<String, Object?> toJson() => <String, Object?>{
    'operationId': operationId,
    'kind': kind.name,
    'status': status.name,
    'workspaceRevision': workspaceRevision,
    'capabilityIds': capabilityIds,
    'provenance': provenance,
    'message': message,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'completedAt': completedAt.toUtc().toIso8601String(),
    'durationMicros': duration.inMicroseconds,
    'exitCode': exitCode,
    'output': output.toJson(),
    'errorOutput': errorOutput.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ExecutionReceipt &&
      operationId == other.operationId &&
      kind == other.kind &&
      status == other.status &&
      workspaceRevision == other.workspaceRevision &&
      _listEquals(capabilityIds, other.capabilityIds) &&
      provenance == other.provenance &&
      message == other.message &&
      startedAt == other.startedAt &&
      completedAt == other.completedAt &&
      exitCode == other.exitCode &&
      output == other.output &&
      errorOutput == other.errorOutput;

  @override
  int get hashCode => Object.hash(
    operationId,
    kind,
    status,
    workspaceRevision,
    Object.hashAll(capabilityIds),
    provenance,
    message,
    startedAt,
    completedAt,
    exitCode,
    output,
    errorOutput,
  );
}

bool _listEquals(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
