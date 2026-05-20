import '../backend_toolchain/hosted_control_plane.dart';
import '../backend_toolchain/project_graph_contract.dart';
import '../platform/platform_target.dart';
import 'hosted_workspace_lifecycle.dart';

enum HostedBackendRetryActionExecutionStatus {
  completed,
  blocked,
  unsupported,
  failed,
}

extension HostedBackendRetryActionExecutionStatusX
    on HostedBackendRetryActionExecutionStatus {
  String get label {
    return switch (this) {
      HostedBackendRetryActionExecutionStatus.completed => 'completed',
      HostedBackendRetryActionExecutionStatus.blocked => 'blocked',
      HostedBackendRetryActionExecutionStatus.unsupported => 'unsupported',
      HostedBackendRetryActionExecutionStatus.failed => 'failed',
    };
  }
}

class HostedBackendRetryActionExecutionResult {
  const HostedBackendRetryActionExecutionResult({
    required this.actionId,
    required this.kind,
    required this.status,
    required this.message,
    this.response,
  });

  final String actionId;
  final HostedBackendRetryActionKind kind;
  final HostedBackendRetryActionExecutionStatus status;
  final String message;
  final Map<String, dynamic>? response;

  bool get successful =>
      status == HostedBackendRetryActionExecutionStatus.completed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'actionId': actionId,
      'kind': kind.label,
      'status': status.label,
      'successful': successful,
      'message': message,
      if (response != null) 'response': response,
    };
  }
}

abstract class HostedBackendRetryTransport {
  Future<Map<String, dynamic>> retryConnect({required String workspaceId});

  Future<Map<String, dynamic>> refreshWorkspace({required String workspaceId});

  Future<Map<String, dynamic>> reopenWorkspace({required String workspaceId});

  Future<Map<String, dynamic>> exportCoreFiles({required String workspaceId});
}

class HostedControlPlaneRetryTransport implements HostedBackendRetryTransport {
  const HostedControlPlaneRetryTransport({
    required this.hostedClient,
    required this.platformTarget,
  });

  final HostedControlPlaneClient hostedClient;
  final PlatformTarget platformTarget;

  @override
  Future<Map<String, dynamic>> retryConnect({required String workspaceId}) {
    return hostedClient.projectGraph(workspaceId: workspaceId);
  }

  @override
  Future<Map<String, dynamic>> refreshWorkspace({required String workspaceId}) {
    return hostedClient.projectGraph(workspaceId: workspaceId);
  }

  @override
  Future<Map<String, dynamic>> reopenWorkspace({
    required String workspaceId,
  }) async {
    return <String, dynamic>{
      'returncode': 78,
      'status': 'unsupported',
      'message':
          'TODO: hosted control plane reopen endpoint is not published yet for $workspaceId on ${platformTarget.label}.',
    };
  }

  @override
  Future<Map<String, dynamic>> exportCoreFiles({
    required String workspaceId,
  }) async {
    return <String, dynamic>{
      'returncode': 78,
      'status': 'unsupported',
      'message':
          'TODO: hosted control plane core-file export endpoint is not published yet for $workspaceId on ${platformTarget.label}.',
    };
  }
}

class HostedBackendRetryActionExecutor {
  const HostedBackendRetryActionExecutor({required this.transport});

  final HostedBackendRetryTransport transport;

  Future<HostedBackendRetryActionExecutionResult> execute({
    required HostedBackendRetryAction action,
    required HostedWorkspaceRecordSnapshot workspace,
  }) async {
    if (!action.enabled) {
      return HostedBackendRetryActionExecutionResult(
        actionId: action.id,
        kind: action.kind,
        status: HostedBackendRetryActionExecutionStatus.blocked,
        message: action.message ?? 'Hosted backend retry action is disabled.',
      );
    }

    try {
      final response = await _executeAction(action, workspace);
      return HostedBackendRetryActionExecutionResult(
        actionId: action.id,
        kind: action.kind,
        status: _statusFromResponse(response),
        message: _messageFromResponse(response, fallback: action.message),
        response: response,
      );
    } catch (error) {
      return HostedBackendRetryActionExecutionResult(
        actionId: action.id,
        kind: action.kind,
        status: HostedBackendRetryActionExecutionStatus.failed,
        message: 'Hosted backend retry action failed: $error',
      );
    }
  }

  Future<Map<String, dynamic>> _executeAction(
    HostedBackendRetryAction action,
    HostedWorkspaceRecordSnapshot workspace,
  ) {
    return switch (action.kind) {
      HostedBackendRetryActionKind.retryConnect => transport.retryConnect(
        workspaceId: workspace.workspaceId,
      ),
      HostedBackendRetryActionKind.refreshWorkspace =>
        transport.refreshWorkspace(workspaceId: workspace.workspaceId),
      HostedBackendRetryActionKind.reopenWorkspace => transport.reopenWorkspace(
        workspaceId: workspace.workspaceId,
      ),
      HostedBackendRetryActionKind.exportCoreFiles => transport.exportCoreFiles(
        workspaceId: workspace.workspaceId,
      ),
      HostedBackendRetryActionKind.openSettings => Future.value(
        <String, dynamic>{
          'returncode': 0,
          'message': 'Open hosted backend settings.',
          'payload': <String, Object?>{
            'settingsRoute': 'hosted-backend',
            'workspaceId': workspace.workspaceId,
          },
        },
      ),
    };
  }

  HostedBackendRetryActionExecutionStatus _statusFromResponse(
    Map<String, dynamic> response,
  ) {
    if (response['status'] == 'unsupported') {
      return HostedBackendRetryActionExecutionStatus.unsupported;
    }
    final returnCode = response['returncode'];
    if (returnCode == null || returnCode == 0) {
      return HostedBackendRetryActionExecutionStatus.completed;
    }
    return HostedBackendRetryActionExecutionStatus.failed;
  }

  String _messageFromResponse(
    Map<String, dynamic> response, {
    String? fallback,
  }) {
    final message = response['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }
    return fallback ?? 'Hosted backend retry action completed.';
  }
}
