import '../configuration/environment_variable_configuration.dart';

enum WorkspaceTrustState { trusted, restricted }

enum ApprovalPolicy {
  readOnly,
  workspaceWrite,
  trustedFullAccess,
}

enum NetworkPolicy { denied, workspaceEndpointsOnly, allowed }

enum ExecutionSandboxFailureCode {
  none,
  untrustedWorkspace,
  approvalRequired,
  commandRejected,
  cwdOutsideWorkspace,
  pathTraversal,
  symlinkEscape,
  envRejected,
  timeoutInvalid,
  outputLimitInvalid,
  networkBlocked,
}

class ExecutionSandboxFailure {
  const ExecutionSandboxFailure({
    required this.code,
    required this.message,
    this.recoveryAction = '',
    this.developerDetail = '',
    this.correlationId = '',
  });

  final ExecutionSandboxFailureCode code;
  final String message;
  final String recoveryAction;
  final String developerDetail;
  final String correlationId;
}

class ExecutionSandboxDecision {
  const ExecutionSandboxDecision.allowed({
    required this.normalizedCwd,
    required this.redactedEnvironment,
    required this.effectiveTimeout,
  })  : failure = null,
        isAllowed = true;

  const ExecutionSandboxDecision.blocked(this.failure)
      : normalizedCwd = '',
        redactedEnvironment = const <String, String>{},
        effectiveTimeout = Duration.zero,
        isAllowed = false;

  final bool isAllowed;
  final String normalizedCwd;
  final Map<String, String> redactedEnvironment;
  final Duration effectiveTimeout;
  final ExecutionSandboxFailure? failure;
}

class ExecutionSandboxPolicy {
  const ExecutionSandboxPolicy({
    required this.workspaceRoot,
    this.trustState = WorkspaceTrustState.restricted,
    this.approvalPolicy = ApprovalPolicy.readOnly,
    this.networkPolicy = NetworkPolicy.denied,
    this.redactionPolicy = const EnvironmentVariableRedactionPolicy(),
    this.allowedEnvironmentKeys = const <String>{},
    this.allowedCwdPrefixes = const <String>[],
    this.knownSymlinkPaths = const <String>{},
    this.timeout = const Duration(seconds: 30),
    this.maxStdoutBytes = 65536,
    this.maxStderrBytes = 65536,
  });

  final String workspaceRoot;
  final WorkspaceTrustState trustState;
  final ApprovalPolicy approvalPolicy;
  final NetworkPolicy networkPolicy;
  final EnvironmentVariableRedactionPolicy redactionPolicy;
  final Set<String> allowedEnvironmentKeys;
  final List<String> allowedCwdPrefixes;
  final Set<String> knownSymlinkPaths;
  final Duration timeout;
  final int maxStdoutBytes;
  final int maxStderrBytes;
}

class ExecutionSandboxRequest {
  const ExecutionSandboxRequest({
    required this.executable,
    this.arguments = const <String>[],
    this.cwd = '.',
    this.environment = const <String, String>{},
    this.requiresWorkspaceWrite = false,
    this.requiresNetwork = false,
    this.timeout,
    this.correlationId = '',
  });

  final String executable;
  final List<String> arguments;
  final String cwd;
  final Map<String, String> environment;
  final bool requiresWorkspaceWrite;
  final bool requiresNetwork;
  final Duration? timeout;
  final String correlationId;
}

class ExecutionSandbox {
  const ExecutionSandbox({required this.policy});

  final ExecutionSandboxPolicy policy;

  ExecutionSandboxDecision evaluate(ExecutionSandboxRequest request) {
    final timeout = request.timeout ?? policy.timeout;
    if (timeout <= Duration.zero) {
      return _blocked(
        ExecutionSandboxFailureCode.timeoutInvalid,
        'Execution timeout must be positive.',
        request,
      );
    }
    if (policy.maxStdoutBytes <= 0 || policy.maxStderrBytes <= 0) {
      return _blocked(
        ExecutionSandboxFailureCode.outputLimitInvalid,
        'Execution output limits must be positive.',
        request,
      );
    }
    if (request.requiresNetwork &&
        policy.networkPolicy == NetworkPolicy.denied) {
      return _blocked(
        ExecutionSandboxFailureCode.networkBlocked,
        'Network access is blocked by the sandbox policy.',
        request,
        recoveryAction: 'Request approval or use a provider with network access.',
      );
    }
    if (policy.trustState == WorkspaceTrustState.restricted &&
        (request.requiresWorkspaceWrite || request.requiresNetwork)) {
      return _blocked(
        ExecutionSandboxFailureCode.untrustedWorkspace,
        'Restricted workspaces cannot auto-run write or network tasks.',
        request,
        recoveryAction: 'Trust the workspace or approve the command manually.',
      );
    }
    if (request.requiresWorkspaceWrite &&
        policy.approvalPolicy == ApprovalPolicy.readOnly) {
      return _blocked(
        ExecutionSandboxFailureCode.approvalRequired,
        'Workspace write execution requires approval.',
        request,
      );
    }
    if (!_isSafeExecutable(request.executable)) {
      return _blocked(
        ExecutionSandboxFailureCode.commandRejected,
        'Executable must be an argv-safe program path or command name.',
        request,
      );
    }
    if (request.arguments.any(_containsNul)) {
      return _blocked(
        ExecutionSandboxFailureCode.commandRejected,
        'Arguments cannot contain NUL bytes.',
        request,
      );
    }

    final normalizedRoot = _normalizePath(policy.workspaceRoot);
    if (_containsTraversal(request.cwd)) {
      return _blocked(
        ExecutionSandboxFailureCode.pathTraversal,
        'Working directory cannot contain path traversal.',
        request,
      );
    }
    final normalizedCwd = _resolvePath(normalizedRoot, request.cwd);
    if (!_isWithin(normalizedCwd, normalizedRoot) ||
        !_isWithinAllowedCwd(normalizedCwd, normalizedRoot)) {
      return _blocked(
        ExecutionSandboxFailureCode.cwdOutsideWorkspace,
        'Working directory must stay inside the workspace.',
        request,
        developerDetail: normalizedCwd,
      );
    }
    if (policy.knownSymlinkPaths.any((path) {
      final normalized = _resolvePath(normalizedRoot, path);
      return normalizedCwd == normalized ||
          normalizedCwd.startsWith('$normalized/');
    })) {
      return _blocked(
        ExecutionSandboxFailureCode.symlinkEscape,
        'Working directory crosses a blocked symlink path.',
        request,
      );
    }

    final rejectedEnv = request.environment.keys
        .where((key) => !policy.allowedEnvironmentKeys.contains(key))
        .toList(growable: false);
    if (rejectedEnv.isNotEmpty) {
      return _blocked(
        ExecutionSandboxFailureCode.envRejected,
        'Environment contains keys outside the allowlist.',
        request,
        developerDetail: rejectedEnv.join(','),
      );
    }

    return ExecutionSandboxDecision.allowed(
      normalizedCwd: normalizedCwd,
      redactedEnvironment: policy.redactionPolicy.redactEnvironment(
        request.environment,
      ),
      effectiveTimeout: timeout,
    );
  }

  ExecutionSandboxDecision _blocked(
    ExecutionSandboxFailureCode code,
    String message,
    ExecutionSandboxRequest request, {
    String recoveryAction = '',
    String developerDetail = '',
  }) {
    return ExecutionSandboxDecision.blocked(
      ExecutionSandboxFailure(
        code: code,
        message: message,
        recoveryAction: recoveryAction,
        developerDetail: developerDetail,
        correlationId: request.correlationId,
      ),
    );
  }

  bool _isWithinAllowedCwd(String cwd, String normalizedRoot) {
    if (policy.allowedCwdPrefixes.isEmpty) {
      return true;
    }
    for (final prefix in policy.allowedCwdPrefixes) {
      final normalizedPrefix = _resolvePath(normalizedRoot, prefix);
      if (_isWithin(cwd, normalizedPrefix)) {
        return true;
      }
    }
    return false;
  }

  static bool _isSafeExecutable(String executable) {
    if (executable.isEmpty || _containsNul(executable)) {
      return false;
    }
    return !RegExp(r'''[\s;&|<>`$]''').hasMatch(executable);
  }

  static bool _containsNul(String value) => value.contains('\u0000');

  static bool _containsTraversal(String path) {
    return path
        .replaceAll('\\', '/')
        .split('/')
        .any((segment) => segment == '..');
  }

  static String _resolvePath(String normalizedRoot, String path) {
    if (path.startsWith('/')) {
      return _normalizePath(path);
    }
    return _normalizePath('$normalizedRoot/$path');
  }

  static String _normalizePath(String path) {
    final raw = path.replaceAll('\\', '/');
    final isAbsolute = raw.startsWith('/');
    final parts = <String>[];
    for (final segment in raw.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (parts.isNotEmpty) {
          parts.removeLast();
        }
        continue;
      }
      parts.add(segment);
    }
    final joined = parts.join('/');
    return isAbsolute ? '/$joined' : joined;
  }

  static bool _isWithin(String child, String parent) {
    if (parent == '/') {
      return child.startsWith('/');
    }
    return child == parent || child.startsWith('$parent/');
  }
}
