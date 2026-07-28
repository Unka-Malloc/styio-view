import 'dart:collection';

import '../execution/execution_receipt.dart';
import '../language/diagnostic_fact.dart';
import 'capability_snapshot.dart';

final class IdeFactQuery {
  const IdeFactQuery({this.capabilityIds = const <String>[]});

  static const all = IdeFactQuery();

  final List<String> capabilityIds;
}

final class RevisionedIdeFacts {
  RevisionedIdeFacts({
    required this.workspaceRevision,
    required this.capabilities,
    required this.diagnostics,
    required Iterable<ExecutionReceipt> receipts,
  }) : receipts = UnmodifiableListView(List<ExecutionReceipt>.of(receipts));

  final int workspaceRevision;
  final CapabilitySnapshot capabilities;
  final RevisionedDiagnosticFacts diagnostics;
  final List<ExecutionReceipt> receipts;

  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceRevision': workspaceRevision,
    'capabilities': capabilities.toJson(),
    'diagnostics': diagnostics.toJson(),
    'receipts': receipts
        .map((receipt) => receipt.toJson())
        .toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is RevisionedIdeFacts &&
      workspaceRevision == other.workspaceRevision &&
      capabilities == other.capabilities &&
      diagnostics == other.diagnostics &&
      _receiptListsEqual(receipts, other.receipts);

  @override
  int get hashCode => Object.hash(
    workspaceRevision,
    capabilities,
    diagnostics,
    Object.hashAll(receipts),
  );
}

abstract interface class IdeFactProvider {
  Future<RevisionedIdeFacts> read(
    IdeFactQuery query,
    int expectedWorkspaceRevision,
  );
}

final class StaleIdeFactRevision implements Exception {
  const StaleIdeFactRevision({required this.expected, required this.current});

  final int expected;
  final int current;
}

final class UnknownIdeCapability implements Exception {
  const UnknownIdeCapability(this.capabilityId);

  final String capabilityId;
}

bool _receiptListsEqual(
  List<ExecutionReceipt> left,
  List<ExecutionReceipt> right,
) {
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
