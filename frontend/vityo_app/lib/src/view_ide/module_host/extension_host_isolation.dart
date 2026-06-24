import 'extension_activator.dart';
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

enum ExtensionHostSupervisorStatus {
  planned,
  starting,
  running,
  blocked,
  failed,
  stopped,
}

extension ExtensionHostSupervisorStatusX on ExtensionHostSupervisorStatus {
  String get wireValue => switch (this) {
    ExtensionHostSupervisorStatus.planned => 'planned',
    ExtensionHostSupervisorStatus.starting => 'starting',
    ExtensionHostSupervisorStatus.running => 'running',
    ExtensionHostSupervisorStatus.blocked => 'blocked',
    ExtensionHostSupervisorStatus.failed => 'failed',
    ExtensionHostSupervisorStatus.stopped => 'stopped',
  };
}

enum ExtensionHostSupervisorAction {
  none,
  runInProcess,
  spawnLocalProcess,
  spawnWebWorker,
  connectRemoteService,
}

extension ExtensionHostSupervisorActionX on ExtensionHostSupervisorAction {
  String get wireValue => switch (this) {
    ExtensionHostSupervisorAction.none => 'none',
    ExtensionHostSupervisorAction.runInProcess => 'run-in-process',
    ExtensionHostSupervisorAction.spawnLocalProcess => 'spawn-local-process',
    ExtensionHostSupervisorAction.spawnWebWorker => 'spawn-web-worker',
    ExtensionHostSupervisorAction.connectRemoteService =>
      'connect-remote-service',
  };
}

class ExtensionHostSupervisorRecord {
  const ExtensionHostSupervisorRecord({
    required this.extensionId,
    required this.plan,
    required this.status,
    required this.action,
    required this.message,
    required this.updatedAt,
  });

  final String extensionId;
  final ExtensionHostExecutionPlan plan;
  final ExtensionHostSupervisorStatus status;
  final ExtensionHostSupervisorAction action;
  final String message;
  final DateTime updatedAt;

  bool get active {
    return status == ExtensionHostSupervisorStatus.starting ||
        status == ExtensionHostSupervisorStatus.running;
  }

  bool get blocked => status == ExtensionHostSupervisorStatus.blocked;
  bool get failed => status == ExtensionHostSupervisorStatus.failed;

  ExtensionHostSupervisorRecord copyWith({
    ExtensionHostExecutionPlan? plan,
    ExtensionHostSupervisorStatus? status,
    ExtensionHostSupervisorAction? action,
    String? message,
    DateTime? updatedAt,
  }) {
    return ExtensionHostSupervisorRecord(
      extensionId: extensionId,
      plan: plan ?? this.plan,
      status: status ?? this.status,
      action: action ?? this.action,
      message: message ?? this.message,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'plan': plan.toJson(),
      'status': status.wireValue,
      'action': action.wireValue,
      'message': message,
      'updatedAt': updatedAt.toIso8601String(),
      'active': active,
      'blocked': blocked,
      'failed': failed,
    };
  }
}

class ExtensionHostSupervisorTelemetryEvent {
  const ExtensionHostSupervisorTelemetryEvent({
    required this.extensionId,
    required this.mode,
    required this.status,
    required this.action,
    required this.message,
    required this.timestamp,
  });

  factory ExtensionHostSupervisorTelemetryEvent.fromRecord(
    ExtensionHostSupervisorRecord record,
  ) {
    return ExtensionHostSupervisorTelemetryEvent(
      extensionId: record.extensionId,
      mode: record.plan.mode,
      status: record.status,
      action: record.action,
      message: record.message,
      timestamp: record.updatedAt,
    );
  }

  final String extensionId;
  final ExtensionHostIsolationMode mode;
  final ExtensionHostSupervisorStatus status;
  final ExtensionHostSupervisorAction action;
  final String message;
  final DateTime timestamp;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'mode': mode.wireValue,
      'status': status.wireValue,
      'action': action.wireValue,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class ExtensionHostSupervisorSnapshot {
  const ExtensionHostSupervisorSnapshot({required this.records});

  final List<ExtensionHostSupervisorRecord> records;

  List<String> get startingExtensionIds {
    return records
        .where(
          (record) => record.status == ExtensionHostSupervisorStatus.starting,
        )
        .map((record) => record.extensionId)
        .toList(growable: false);
  }

  List<String> get runningExtensionIds {
    return records
        .where(
          (record) => record.status == ExtensionHostSupervisorStatus.running,
        )
        .map((record) => record.extensionId)
        .toList(growable: false);
  }

  List<String> get blockedExtensionIds {
    return records
        .where((record) => record.blocked)
        .map((record) => record.extensionId)
        .toList(growable: false);
  }

  List<String> get failedExtensionIds {
    return records
        .where((record) => record.failed)
        .map((record) => record.extensionId)
        .toList(growable: false);
  }

  List<ExtensionHostSupervisorTelemetryEvent> get telemetryEvents {
    return records
        .map(ExtensionHostSupervisorTelemetryEvent.fromRecord)
        .toList(growable: false);
  }

  ExtensionHostSupervisorRecord? lookup(String extensionId) {
    for (final record in records) {
      if (record.extensionId == extensionId) {
        return record;
      }
    }
    return null;
  }

  ExtensionHostSupervisorSnapshot replace(
    ExtensionHostSupervisorRecord nextRecord,
  ) {
    return ExtensionHostSupervisorSnapshot(
      records: records
          .map(
            (record) => record.extensionId == nextRecord.extensionId
                ? nextRecord
                : record,
          )
          .toList(growable: false),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'recordCount': records.length,
      'startingExtensionIds': startingExtensionIds,
      'runningExtensionIds': runningExtensionIds,
      'blockedExtensionIds': blockedExtensionIds,
      'failedExtensionIds': failedExtensionIds,
      'records': records
          .map((record) => record.toJson())
          .toList(growable: false),
      'telemetryEvents': telemetryEvents
          .map((event) => event.toJson())
          .toList(growable: false),
    };
  }
}

class ExtensionHostSupervisor {
  const ExtensionHostSupervisor({
    this.planner = const ExtensionHostIsolationPlanner(),
    this.clock,
  });

  final ExtensionHostIsolationPlanner planner;
  final DateTime Function()? clock;

  ExtensionHostSupervisorSnapshot planRegistry(
    ExtensionManifestRegistry registry,
  ) {
    final timestamp = _now();
    return ExtensionHostSupervisorSnapshot(
      records: planner
          .planRegistry(registry)
          .map((plan) {
            return ExtensionHostSupervisorRecord(
              extensionId: plan.extensionId,
              plan: plan,
              status: plan.executable
                  ? ExtensionHostSupervisorStatus.planned
                  : ExtensionHostSupervisorStatus.blocked,
              action: _actionFor(plan.mode),
              message: plan.reason,
              updatedAt: timestamp,
            );
          })
          .toList(growable: false),
    );
  }

  ExtensionHostSupervisorSnapshot applyActivation({
    required ExtensionManifestRegistry registry,
    required ExtensionActivationSession session,
    ExtensionHostSupervisorSnapshot? previous,
  }) {
    var snapshot = previous ?? planRegistry(registry);
    for (final decision in session.decisions) {
      final record = snapshot.lookup(decision.extensionId);
      if (record == null) {
        continue;
      }
      if (!decision.activated) {
        snapshot = snapshot.replace(
          record.copyWith(
            status: ExtensionHostSupervisorStatus.blocked,
            action: ExtensionHostSupervisorAction.none,
            message: decision.message,
            updatedAt: session.activatedAt,
          ),
        );
        continue;
      }
      if (!record.plan.executable) {
        snapshot = snapshot.replace(
          record.copyWith(
            status: ExtensionHostSupervisorStatus.blocked,
            action: ExtensionHostSupervisorAction.none,
            message: record.plan.reason,
            updatedAt: session.activatedAt,
          ),
        );
        continue;
      }
      snapshot = snapshot.replace(
        record.copyWith(
          status: ExtensionHostSupervisorStatus.starting,
          action: _actionFor(record.plan.mode),
          message:
              'Extension ${record.extensionId} activation requested host '
              '${record.plan.mode.wireValue}.',
          updatedAt: session.activatedAt,
        ),
      );
    }
    return snapshot;
  }

  ExtensionHostSupervisorSnapshot markRunning({
    required ExtensionHostSupervisorSnapshot snapshot,
    required String extensionId,
    String message = 'Extension host is running.',
  }) {
    final record = snapshot.lookup(extensionId);
    if (record == null || !record.plan.executable) {
      return snapshot;
    }
    return snapshot.replace(
      record.copyWith(
        status: ExtensionHostSupervisorStatus.running,
        action: _actionFor(record.plan.mode),
        message: message,
        updatedAt: _now(),
      ),
    );
  }

  ExtensionHostSupervisorSnapshot markFailed({
    required ExtensionHostSupervisorSnapshot snapshot,
    required String extensionId,
    required String reason,
  }) {
    final record = snapshot.lookup(extensionId);
    if (record == null) {
      return snapshot;
    }
    return snapshot.replace(
      record.copyWith(
        status: ExtensionHostSupervisorStatus.failed,
        action: ExtensionHostSupervisorAction.none,
        message: reason,
        updatedAt: _now(),
      ),
    );
  }

  ExtensionHostSupervisorSnapshot stop({
    required ExtensionHostSupervisorSnapshot snapshot,
    required String extensionId,
    required String reason,
  }) {
    final record = snapshot.lookup(extensionId);
    if (record == null) {
      return snapshot;
    }
    return snapshot.replace(
      record.copyWith(
        status: ExtensionHostSupervisorStatus.stopped,
        action: ExtensionHostSupervisorAction.none,
        message: reason,
        updatedAt: _now(),
      ),
    );
  }

  DateTime _now() => (clock ?? DateTime.now)().toUtc();
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

ExtensionHostSupervisorAction _actionFor(ExtensionHostIsolationMode mode) {
  return switch (mode) {
    ExtensionHostIsolationMode.inProcess =>
      ExtensionHostSupervisorAction.runInProcess,
    ExtensionHostIsolationMode.localProcess =>
      ExtensionHostSupervisorAction.spawnLocalProcess,
    ExtensionHostIsolationMode.webWorker =>
      ExtensionHostSupervisorAction.spawnWebWorker,
    ExtensionHostIsolationMode.remoteService =>
      ExtensionHostSupervisorAction.connectRemoteService,
    ExtensionHostIsolationMode.blocked => ExtensionHostSupervisorAction.none,
  };
}
