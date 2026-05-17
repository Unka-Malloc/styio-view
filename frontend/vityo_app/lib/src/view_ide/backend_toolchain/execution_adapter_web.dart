import '../editor/document_state.dart';
import '../language/language_contract.dart';
import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'execution_adapter.dart';
import 'hosted_control_plane.dart';
import 'hosted_execution_codec.dart';
import 'project_workflow_selection.dart';
import 'project_graph_contract.dart';
import 'runtime_event_adapter.dart';

Future<ExecutionAdapter> createPlatformExecutionAdapter({
  required PlatformTarget platformTarget,
  required ProjectGraphSnapshot projectGraph,
}) async {
  final hostedClient = await createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
  if (hostedClient == null) {
    throw StateError(
      'Web hosted route requires a published hosted control plane.',
    );
  }
  return _HostedExecutionAdapter(
    platformTarget: platformTarget,
    projectGraph: projectGraph,
    hostedClient: hostedClient,
  );
}

class _HostedExecutionAdapter implements ExecutionAdapter {
  _HostedExecutionAdapter({
    required this.platformTarget,
    required this.projectGraph,
    required this.hostedClient,
  });

  final PlatformTarget platformTarget;
  final ProjectGraphSnapshot projectGraph;
  final HostedControlPlaneClient hostedClient;

  @override
  AdapterCapabilitySnapshot
  get capabilitySnapshot => const AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cloud,
    languageService: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.partial,
      detail: 'Hosted language service stays reserved behind the cloud route.',
    ),
    projectGraph: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'Hosted project graph is live through the shared control plane.',
      supportedContractVersions: <int>[1],
    ),
    execution: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'Hosted execution is live through the shared control plane.',
      supportedContractVersions: <int>[1],
    ),
    runtimeEvents: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail:
          'Hosted execution publishes runtime event payloads through the shared control plane.',
      supportedContractVersions: <int>[1],
    ),
  );

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const ExecutionSession(
        sessionId: 'missing-hosted-workspace',
        kind: 'run',
        status: ExecutionSessionStatus.blocked,
        statusMessage:
            'Hosted workspace identity is unavailable for cloud execution.',
        diagnostics: <Diagnostic>[],
        stdoutEvents: <ExecutionLogEvent>[],
        stderrEvents: <ExecutionLogEvent>[],
      );
    }

    final workflow = selectProjectWorkflow(
      projectGraph: projectGraph,
      activeFilePath: activeFilePath,
    );
    try {
      final response = switch (workflow.command) {
        'test' => await hostedClient.testWorkflow(
          workspaceId: workspaceId,
          activeFilePath: activeFilePath,
          documentText: document.text,
          packageName: workflow.packageName,
          targetName: workflow.targetName,
          targetKind: workflow.targetKind,
        ),
        'build' => await hostedClient.buildWorkflow(
          workspaceId: workspaceId,
          activeFilePath: activeFilePath,
          documentText: document.text,
          packageName: workflow.packageName,
          targetName: workflow.targetName,
          targetKind: workflow.targetKind,
        ),
        _ => await hostedClient.runWorkflow(
          workspaceId: workspaceId,
          activeFilePath: activeFilePath,
          documentText: document.text,
          packageName: workflow.packageName,
          targetName: workflow.targetName,
          targetKind: workflow.targetKind,
        ),
      };
      final decoded = executionSessionFromHostedResponse(
        response: response,
        workflowKind: workflow.kind,
        successMessage: workflow.successMessage,
        documentText: document.text,
        activeFilePath: activeFilePath,
      );
      if (decoded.runtimeEvents.isEmpty) {
        clearRuntimeEventsForSession(decoded.session.sessionId);
      } else {
        recordRuntimeEventsForSession(
          decoded.session.sessionId,
          decoded.runtimeEvents,
        );
      }
      return decoded.session;
    } catch (error) {
      return ExecutionSession(
        sessionId: 'hosted-execution-error',
        kind: workflow.kind,
        status: ExecutionSessionStatus.failed,
        statusMessage: 'Hosted execution failed: $error',
        diagnostics: const <Diagnostic>[],
        stdoutEvents: const <ExecutionLogEvent>[],
        stderrEvents: const <ExecutionLogEvent>[],
        unitRange: SourceRange(start: 0, end: document.length),
      );
    }
  }
}
