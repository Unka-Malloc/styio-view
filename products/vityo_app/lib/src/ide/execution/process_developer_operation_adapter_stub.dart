import '../workbench/capability_snapshot.dart';
import 'developer_operation_adapter.dart';
import 'execution_receipt.dart';

final class ProcessDeveloperOperationAdapter
    implements DeveloperOperationAdapter {
  ProcessDeveloperOperationAdapter({
    required this.kind,
    required Iterable<IdeCapabilityFact> capabilities,
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    int maxOutputCodeUnits = 4096,
    Object? diagnosticDecoder,
  }) : capabilities = List<IdeCapabilityFact>.unmodifiable(capabilities);

  @override
  final DeveloperOperationKind kind;

  @override
  final List<IdeCapabilityFact> capabilities;

  @override
  Future<DeveloperOperationResult> execute(
    DeveloperOperationContext context,
  ) async {
    return const DeveloperOperationResult(
      status: ExecutionReceiptStatus.blocked,
      provenance: 'process-adapter',
      message: 'Process execution is unavailable on this platform.',
    );
  }
}
