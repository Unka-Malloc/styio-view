import 'dart:collection';

import '../language/diagnostic_fact.dart';
import '../workbench/capability_snapshot.dart';
import '../workbench/ide_fact_provider.dart';
import 'developer_operation_adapter.dart';
import 'execution_receipt.dart';

final class DeveloperOperationUnavailable implements Exception {
  const DeveloperOperationUnavailable(this.kind);

  final DeveloperOperationKind kind;
}

final class DuplicateDeveloperOperation implements Exception {
  const DuplicateDeveloperOperation(this.kind);

  final DeveloperOperationKind kind;
}

/// Revision-bound projection over IDE-owned developer adapters.
///
/// Adapters retain ownership of compiler, process, source-control, terminal,
/// toolchain, and package semantics. This service only validates revision
/// authority, normalizes receipts, and retains a bounded fact history.
final class DeveloperLoopService implements IdeFactProvider {
  DeveloperLoopService({
    required this.currentWorkspaceRevision,
    required Iterable<DeveloperOperationAdapter> adapters,
    this.maxReceipts = 64,
    this.maxOutputCodeUnits = 4096,
  }) : _adapters = List<DeveloperOperationAdapter?>.filled(
         DeveloperOperationKind.values.length,
         null,
       ) {
    if (maxReceipts <= 0) {
      throw ArgumentError.value(maxReceipts, 'maxReceipts', 'must be positive');
    }
    if (maxOutputCodeUnits < 0) {
      throw ArgumentError.value(
        maxOutputCodeUnits,
        'maxOutputCodeUnits',
        'must not be negative',
      );
    }
    for (final adapter in adapters) {
      final index = adapter.kind.index;
      if (_adapters[index] != null) {
        throw DuplicateDeveloperOperation(adapter.kind);
      }
      if (adapter.capabilities.isEmpty) {
        throw ArgumentError.value(
          adapter.kind,
          'adapters',
          'each adapter must expose at least one capability',
        );
      }
      _adapters[index] = adapter;
      for (final capability in adapter.capabilities) {
        final previous = _capabilities[capability.id];
        if (previous != null && previous != capability) {
          throw ArgumentError.value(
            capability.id,
            'adapters',
            'capability id is declared with conflicting facts',
          );
        }
        _capabilities[capability.id] = capability;
      }
    }
  }

  final int Function() currentWorkspaceRevision;
  final int maxReceipts;
  final int maxOutputCodeUnits;
  final List<DeveloperOperationAdapter?> _adapters;
  final Map<String, IdeCapabilityFact> _capabilities =
      <String, IdeCapabilityFact>{};
  final ListQueue<ExecutionReceipt> _receipts = ListQueue<ExecutionReceipt>();
  final Set<String> _activeOperationIds = <String>{};
  final LinkedHashMap<int, RevisionedDiagnosticFacts> _diagnosticsByRevision =
      LinkedHashMap<int, RevisionedDiagnosticFacts>();

  CapabilitySnapshot get capabilitySnapshot => CapabilitySnapshot(
    schemaVersion: 1,
    workspaceRevision: currentWorkspaceRevision(),
    capabilities: _capabilities,
  );

  Future<ExecutionReceipt> execute({
    required String operationId,
    required DeveloperOperationKind kind,
    required int expectedWorkspaceRevision,
    DeveloperOperationCancellation? cancellation,
  }) async {
    if (operationId.trim().isEmpty) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'must not be empty',
      );
    }
    _requireRevision(expectedWorkspaceRevision);
    final adapter = _adapters[kind.index];
    if (adapter == null) {
      throw DeveloperOperationUnavailable(kind);
    }
    if (!_activeOperationIds.add(operationId)) {
      throw StateError('Operation id is already active.');
    }

    final startedAt = DateTime.now().toUtc();
    DeveloperOperationResult result;
    try {
      final primary = adapter.capabilities.first;
      if (primary.state == IdeCapabilityState.blocked) {
        result = DeveloperOperationResult(
          status: ExecutionReceiptStatus.blocked,
          provenance: primary.provenance,
          message: primary.message,
        );
      } else if (primary.state == IdeCapabilityState.degraded) {
        result = DeveloperOperationResult(
          status: ExecutionReceiptStatus.degraded,
          provenance: primary.provenance,
          message: primary.message,
        );
      } else {
        result = await adapter.execute(
          DeveloperOperationContext(
            operationId: operationId,
            workspaceRevision: expectedWorkspaceRevision,
            cancellation: cancellation ?? DeveloperOperationCancellation(),
          ),
        );
      }
    } finally {
      _activeOperationIds.remove(operationId);
    }
    final completedAt = DateTime.now().toUtc();
    final receipt = ExecutionReceipt(
      operationId: operationId,
      kind: kind,
      status: result.status,
      workspaceRevision: expectedWorkspaceRevision,
      capabilityIds: adapter.capabilities
          .map((capability) => capability.id)
          .toList(growable: false),
      provenance: result.provenance,
      message: result.message,
      startedAt: startedAt,
      completedAt: completedAt,
      exitCode: result.exitCode,
      output: result.output.bounded(maxOutputCodeUnits),
      errorOutput: result.errorOutput.bounded(maxOutputCodeUnits),
    );
    _receipts.addLast(receipt);
    while (_receipts.length > maxReceipts) {
      _receipts.removeFirst();
    }
    final diagnostics = result.diagnostics;
    if (diagnostics != null) {
      _diagnosticsByRevision[expectedWorkspaceRevision] =
          RevisionedDiagnosticFacts(
            workspaceRevision: expectedWorkspaceRevision,
            state: diagnostics.state,
            provenance: diagnostics.provenance,
            message: diagnostics.message,
            diagnostics: diagnostics.diagnostics,
          );
      while (_diagnosticsByRevision.length > 8) {
        _diagnosticsByRevision.remove(_diagnosticsByRevision.keys.first);
      }
    }
    return receipt;
  }

  @override
  Future<RevisionedIdeFacts> read(
    IdeFactQuery query,
    int expectedWorkspaceRevision,
  ) async {
    _requireRevision(expectedWorkspaceRevision);
    if (query.capabilityIds.length > 64 ||
        query.capabilityIds.any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(
        query.capabilityIds,
        'query.capabilityIds',
        'must contain at most 64 non-empty ids',
      );
    }
    final requested = query.capabilityIds.toSet();
    for (final id in requested) {
      if (!_capabilities.containsKey(id)) {
        throw UnknownIdeCapability(id);
      }
    }
    final capabilities = requested.isEmpty
        ? Map<String, IdeCapabilityFact>.of(_capabilities)
        : <String, IdeCapabilityFact>{
            for (final id in requested) id: _capabilities[id]!,
          };
    final receipts = _receipts.where((receipt) {
      if (receipt.workspaceRevision != expectedWorkspaceRevision) {
        return false;
      }
      return requested.isEmpty || receipt.capabilityIds.any(requested.contains);
    });
    return RevisionedIdeFacts(
      workspaceRevision: expectedWorkspaceRevision,
      capabilities: CapabilitySnapshot(
        schemaVersion: 1,
        workspaceRevision: expectedWorkspaceRevision,
        capabilities: capabilities,
      ),
      diagnostics:
          _diagnosticsByRevision[expectedWorkspaceRevision] ??
          RevisionedDiagnosticFacts(
            workspaceRevision: expectedWorkspaceRevision,
            state: IdeCapabilityState.blocked,
            provenance: 'vityo',
            message:
                'No structured diagnostics are available for this revision.',
            diagnostics: const <IdeDiagnosticFact>[],
          ),
      receipts: receipts,
    );
  }

  void _requireRevision(int expected) {
    final current = currentWorkspaceRevision();
    if (expected != current) {
      throw StaleIdeFactRevision(expected: expected, current: current);
    }
  }
}
