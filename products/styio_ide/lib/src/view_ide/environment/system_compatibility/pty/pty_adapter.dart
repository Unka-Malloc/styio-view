import 'pty_facts.dart';
import 'pty_manager.dart';

class PtyAdapter {
  const PtyAdapter(this.facts);

  final PtyFacts facts;

  PtyCompatibility adapt() => PtyCompatibility(
    targetId: facts.targetId,
    compatibilityTarget: facts.compatibilityTarget,
    providerKind: facts.providerKind,
    supportsPty: facts.supportsPty,
    supportsResize: facts.supportsResize,
    supportsRawMode: facts.supportsRawMode,
    supportsSignals: facts.supportsSignals,
    supportsProcessGroup: facts.supportsProcessGroup,
  );

  PtyExecutionPlan plan(PtySessionRequest request) {
    final compatibility = adapt();
    if (!compatibility.supportsPty ||
        (compatibility.providerKind != PtyProviderKind.posixPty &&
            compatibility.providerKind != PtyProviderKind.conPty)) {
      return PtyExecutionPlan.unsupported(
        request: request,
        message: 'Native PTY allocation is not available on ${facts.targetId}.',
      );
    }
    return PtyExecutionPlan(
      request: request,
      providerKind: compatibility.providerKind,
      backendExecutablePath: request.executablePath,
      backendArguments: request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      supported: true,
    );
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
  });

  final String targetId;
  final String compatibilityTarget;
  final PtyProviderKind providerKind;
  final bool supportsPty;
  final bool supportsResize;
  final bool supportsRawMode;
  final bool supportsSignals;
  final bool supportsProcessGroup;

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
  }) => PtyExecutionPlan(
    request: request,
    providerKind: PtyProviderKind.unsupported,
    backendExecutablePath: '',
    backendArguments: const <String>[],
    workingDirectory: request.workingDirectory,
    environment: const <String, String>{},
    supported: false,
    unsupportedMessage: message,
  );

  final PtySessionRequest request;
  final PtyProviderKind providerKind;
  final String backendExecutablePath;
  final List<String> backendArguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final bool supported;
  final String? unsupportedMessage;
}
