import 'pty_facts.dart';
import 'pty_manager.dart';

class PtyAdapter {
  const PtyAdapter(this.facts);

  final PtyFacts facts;

  PtyCompatibility adapt() {
    return PtyCompatibility(
      targetId: facts.targetId,
      compatibilityTarget: facts.compatibilityTarget,
      providerKind: facts.providerKind,
      supportsPty: facts.supportsPty,
      supportsResize: facts.supportsResize,
      supportsRawMode: facts.supportsRawMode,
      supportsSignals: facts.supportsSignals,
      supportsProcessGroup: facts.supportsProcessGroup,
      scriptUtilityPath: facts.scriptUtilityPath,
    );
  }

  PtyExecutionPlan plan(PtySessionRequest request) {
    final compatibility = adapt();
    if (!compatibility.supportsPty) {
      return PtyExecutionPlan.unsupported(
        request: request,
        message: 'PTY allocation is not available on ${facts.targetId}.',
      );
    }
    if (compatibility.providerKind == PtyProviderKind.scriptUtility) {
      final scriptPath = compatibility.scriptUtilityPath;
      if (scriptPath == null || scriptPath.isEmpty) {
        return PtyExecutionPlan.unsupported(
          request: request,
          message: 'The script utility PTY backend has no executable path.',
        );
      }
      return PtyExecutionPlan(
        request: request,
        providerKind: PtyProviderKind.scriptUtility,
        backendExecutablePath: scriptPath,
        backendArguments: <String>[
          '-qfec',
          _composeCommand(request.executablePath, request.arguments),
          '/dev/null',
        ],
        workingDirectory: request.workingDirectory,
        environment: request.environment,
        supported: true,
      );
    }
    return PtyExecutionPlan.unsupported(
      request: request,
      message:
          'PTY provider ${compatibility.providerKind.wireValue} is not implemented.',
    );
  }

  String _composeCommand(String executablePath, List<String> arguments) {
    return <String>[
      quotePosix(executablePath),
      ...arguments.map(quotePosix),
    ].join(' ');
  }

  String quotePosix(String value) {
    if (value.isEmpty) {
      return "''";
    }
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}

class PtyCompatibility {
  const PtyCompatibility({
    required this.targetId,
    required this.compatibilityTarget,
    required this.providerKind,
    required this.supportsPty,
    required this.supportsResize,
    required this.supportsRawMode,
    required this.supportsSignals,
    required this.supportsProcessGroup,
    this.scriptUtilityPath,
  });

  final String targetId;
  final String compatibilityTarget;
  final PtyProviderKind providerKind;
  final bool supportsPty;
  final bool supportsResize;
  final bool supportsRawMode;
  final bool supportsSignals;
  final bool supportsProcessGroup;
  final String? scriptUtilityPath;

  bool get isLinuxDebianArm => compatibilityTarget == 'linux-debian-arm';
}

class PtyExecutionPlan {
  const PtyExecutionPlan({
    required this.request,
    required this.providerKind,
    required this.backendExecutablePath,
    required this.backendArguments,
    required this.workingDirectory,
    required this.environment,
    required this.supported,
    this.unsupportedMessage,
  });

  factory PtyExecutionPlan.unsupported({
    required PtySessionRequest request,
    required String message,
  }) {
    return PtyExecutionPlan(
      request: request,
      providerKind: PtyProviderKind.unsupported,
      backendExecutablePath: '',
      backendArguments: const <String>[],
      workingDirectory: request.workingDirectory,
      environment: const <String, String>{},
      supported: false,
      unsupportedMessage: message,
    );
  }

  final PtySessionRequest request;
  final PtyProviderKind providerKind;
  final String backendExecutablePath;
  final List<String> backendArguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final bool supported;
  final String? unsupportedMessage;
}
