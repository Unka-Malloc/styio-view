import 'dart:async';

import '../language/diagnostic_fact.dart';
import '../workbench/capability_snapshot.dart';
import 'execution_receipt.dart';

final class DeveloperOperationCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

final class DeveloperOperationContext {
  const DeveloperOperationContext({
    required this.operationId,
    required this.workspaceRevision,
    required this.cancellation,
  });

  final String operationId;
  final int workspaceRevision;
  final DeveloperOperationCancellation cancellation;
}

final class DeveloperOperationResult {
  const DeveloperOperationResult({
    required this.status,
    required this.provenance,
    required this.message,
    this.exitCode,
    this.output = BoundedText.empty,
    this.errorOutput = BoundedText.empty,
    this.diagnostics,
  });

  const DeveloperOperationResult.succeeded({
    required String provenance,
    required String message,
    int? exitCode = 0,
    BoundedText output = BoundedText.empty,
    BoundedText errorOutput = BoundedText.empty,
    DeveloperDiagnosticBatch? diagnostics,
  }) : this(
         status: ExecutionReceiptStatus.succeeded,
         provenance: provenance,
         message: message,
         exitCode: exitCode,
         output: output,
         errorOutput: errorOutput,
         diagnostics: diagnostics,
       );

  final ExecutionReceiptStatus status;
  final String provenance;
  final String message;
  final int? exitCode;
  final BoundedText output;
  final BoundedText errorOutput;
  final DeveloperDiagnosticBatch? diagnostics;
}

abstract interface class DeveloperOperationAdapter {
  DeveloperOperationKind get kind;

  List<IdeCapabilityFact> get capabilities;

  Future<DeveloperOperationResult> execute(DeveloperOperationContext context);
}

final class UnavailableDeveloperOperationAdapter
    implements DeveloperOperationAdapter {
  UnavailableDeveloperOperationAdapter({
    required this.kind,
    required IdeCapabilityFact capability,
  }) : capabilities = List<IdeCapabilityFact>.unmodifiable(<IdeCapabilityFact>[
         capability,
       ]),
       assert(capability.state != IdeCapabilityState.available);

  @override
  final DeveloperOperationKind kind;

  @override
  final List<IdeCapabilityFact> capabilities;

  @override
  Future<DeveloperOperationResult> execute(
    DeveloperOperationContext context,
  ) async {
    final capability = capabilities.single;
    return DeveloperOperationResult(
      status: switch (capability.state) {
        IdeCapabilityState.degraded => ExecutionReceiptStatus.degraded,
        IdeCapabilityState.blocked => ExecutionReceiptStatus.blocked,
        IdeCapabilityState.available => ExecutionReceiptStatus.failed,
      },
      provenance: capability.provenance,
      message: capability.message,
    );
  }
}
