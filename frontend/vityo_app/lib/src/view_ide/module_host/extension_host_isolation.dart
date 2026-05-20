import 'extension_manifest_contract.dart';

enum ExtensionHostIsolationMode {
  inProcess,
  localProcess,
  webWorker,
  remoteService,
  blocked,
}

extension ExtensionHostIsolationModeX on ExtensionHostIsolationMode {
  String get wireValue => switch (this) {
    ExtensionHostIsolationMode.inProcess => 'in-process',
    ExtensionHostIsolationMode.localProcess => 'local-process',
    ExtensionHostIsolationMode.webWorker => 'web-worker',
    ExtensionHostIsolationMode.remoteService => 'remote-service',
    ExtensionHostIsolationMode.blocked => 'blocked',
  };
}

class ExtensionHostIsolationPolicy {
  const ExtensionHostIsolationPolicy({
    this.allowUntrusted = false,
    this.allowInProcessCore = true,
    this.allowLocalProcess = true,
    this.allowWebWorker = true,
    this.allowRemoteService = true,
  });

  final bool allowUntrusted;
  final bool allowInProcessCore;
  final bool allowLocalProcess;
  final bool allowWebWorker;
  final bool allowRemoteService;

  ExtensionHostExecutionPlan planFor(ExtensionManifest manifest) {
    if (!manifest.trustedByDefault && !allowUntrusted) {
      return ExtensionHostExecutionPlan.blocked(
        extensionId: manifest.extensionId,
        reason: 'Extension is blocked until user trust is granted.',
      );
    }
    final requested = _requestedIsolationMode(manifest);
    final allowed = _allowed(requested, manifest);
    if (!allowed) {
      return ExtensionHostExecutionPlan.blocked(
        extensionId: manifest.extensionId,
        reason:
            'Extension ${manifest.extensionId} requested disallowed isolation mode ${requested.wireValue}.',
        requestedMode: requested,
      );
    }
    return ExtensionHostExecutionPlan(
      extensionId: manifest.extensionId,
      mode: requested,
      requestedMode: requested,
      reason:
          'Extension ${manifest.extensionId} can run in ${requested.wireValue}.',
    );
  }

  bool _allowed(ExtensionHostIsolationMode mode, ExtensionManifest manifest) {
    return switch (mode) {
      ExtensionHostIsolationMode.inProcess =>
        allowInProcessCore && manifest.trustedByDefault,
      ExtensionHostIsolationMode.localProcess => allowLocalProcess,
      ExtensionHostIsolationMode.webWorker => allowWebWorker,
      ExtensionHostIsolationMode.remoteService => allowRemoteService,
      ExtensionHostIsolationMode.blocked => false,
    };
  }
}

class ExtensionHostExecutionPlan {
  const ExtensionHostExecutionPlan({
    required this.extensionId,
    required this.mode,
    required this.requestedMode,
    required this.reason,
  });

  factory ExtensionHostExecutionPlan.blocked({
    required String extensionId,
    required String reason,
    ExtensionHostIsolationMode requestedMode =
        ExtensionHostIsolationMode.blocked,
  }) {
    return ExtensionHostExecutionPlan(
      extensionId: extensionId,
      mode: ExtensionHostIsolationMode.blocked,
      requestedMode: requestedMode,
      reason: reason,
    );
  }

  final String extensionId;
  final ExtensionHostIsolationMode mode;
  final ExtensionHostIsolationMode requestedMode;
  final String reason;

  bool get executable => mode != ExtensionHostIsolationMode.blocked;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'mode': mode.wireValue,
      'requestedMode': requestedMode.wireValue,
      'reason': reason,
      'executable': executable,
    };
  }
}

class ExtensionHostIsolationPlanner {
  const ExtensionHostIsolationPlanner({
    this.policy = const ExtensionHostIsolationPolicy(),
  });

  final ExtensionHostIsolationPolicy policy;

  List<ExtensionHostExecutionPlan> planRegistry(
    ExtensionManifestRegistry registry,
  ) {
    return registry.list().map(policy.planFor).toList(growable: false);
  }
}

ExtensionHostIsolationMode _requestedIsolationMode(ExtensionManifest manifest) {
  final raw = manifest.metadata['isolationMode'];
  return switch (raw) {
    'in-process' => ExtensionHostIsolationMode.inProcess,
    'web-worker' => ExtensionHostIsolationMode.webWorker,
    'remote-service' => ExtensionHostIsolationMode.remoteService,
    'blocked' => ExtensionHostIsolationMode.blocked,
    _ =>
      manifest.trustedByDefault
          ? ExtensionHostIsolationMode.localProcess
          : ExtensionHostIsolationMode.remoteService,
  };
}
