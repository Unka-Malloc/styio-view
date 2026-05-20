import 'extension_activator.dart';
import 'extension_manifest_contract.dart';

enum ExtensionLifecycleStatus {
  registered,
  activated,
  blocked,
  deactivated,
  failed,
}

extension ExtensionLifecycleStatusX on ExtensionLifecycleStatus {
  String get wireValue => switch (this) {
    ExtensionLifecycleStatus.registered => 'registered',
    ExtensionLifecycleStatus.activated => 'activated',
    ExtensionLifecycleStatus.blocked => 'blocked',
    ExtensionLifecycleStatus.deactivated => 'deactivated',
    ExtensionLifecycleStatus.failed => 'failed',
  };
}

class ExtensionLifecycleRecord {
  const ExtensionLifecycleRecord({
    required this.extensionId,
    required this.status,
    required this.event,
    required this.message,
    required this.updatedAt,
  });

  final String extensionId;
  final ExtensionLifecycleStatus status;
  final String event;
  final String message;
  final DateTime updatedAt;

  bool get active => status == ExtensionLifecycleStatus.activated;
  bool get blocked => status == ExtensionLifecycleStatus.blocked;

  ExtensionLifecycleRecord copyWith({
    ExtensionLifecycleStatus? status,
    String? event,
    String? message,
    DateTime? updatedAt,
  }) {
    return ExtensionLifecycleRecord(
      extensionId: extensionId,
      status: status ?? this.status,
      event: event ?? this.event,
      message: message ?? this.message,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'status': status.wireValue,
      'event': event,
      'message': message,
      'updatedAt': updatedAt.toIso8601String(),
      'active': active,
      'blocked': blocked,
    };
  }
}

class ExtensionLifecycleSnapshot {
  const ExtensionLifecycleSnapshot({required this.records});

  final List<ExtensionLifecycleRecord> records;

  List<String> get activatedExtensionIds {
    return records
        .where((record) => record.active)
        .map((record) => record.extensionId)
        .toList(growable: false);
  }

  List<String> get blockedExtensionIds {
    return records
        .where((record) => record.blocked)
        .map((record) => record.extensionId)
        .toList(growable: false);
  }

  ExtensionLifecycleRecord? lookup(String extensionId) {
    for (final record in records) {
      if (record.extensionId == extensionId) {
        return record;
      }
    }
    return null;
  }

  ExtensionLifecycleSnapshot replace(ExtensionLifecycleRecord nextRecord) {
    final nextRecords = records
        .map(
          (record) => record.extensionId == nextRecord.extensionId
              ? nextRecord
              : record,
        )
        .toList(growable: false);
    return ExtensionLifecycleSnapshot(records: nextRecords);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'recordCount': records.length,
      'activatedExtensionIds': activatedExtensionIds,
      'blockedExtensionIds': blockedExtensionIds,
      'records': records
          .map((record) => record.toJson())
          .toList(growable: false),
    };
  }
}

class ExtensionLifecycleController {
  const ExtensionLifecycleController({this.clock});

  final DateTime Function()? clock;

  ExtensionLifecycleSnapshot registeredSnapshot(
    ExtensionManifestRegistry registry,
  ) {
    final timestamp = _now();
    return ExtensionLifecycleSnapshot(
      records: registry
          .list()
          .map(
            (manifest) => ExtensionLifecycleRecord(
              extensionId: manifest.extensionId,
              status: ExtensionLifecycleStatus.registered,
              event: 'register',
              message: 'Extension ${manifest.extensionId} is registered.',
              updatedAt: timestamp,
            ),
          )
          .toList(growable: false),
    );
  }

  ExtensionLifecycleSnapshot applyActivation({
    required ExtensionManifestRegistry registry,
    required ExtensionActivationSession session,
    ExtensionLifecycleSnapshot? previous,
  }) {
    var snapshot = previous ?? registeredSnapshot(registry);
    for (final decision in session.decisions) {
      final previousRecord = snapshot.lookup(decision.extensionId);
      if (previousRecord == null) {
        continue;
      }
      snapshot = snapshot.replace(
        previousRecord.copyWith(
          status: decision.activated
              ? ExtensionLifecycleStatus.activated
              : ExtensionLifecycleStatus.blocked,
          event: decision.event,
          message: decision.message,
          updatedAt: session.activatedAt,
        ),
      );
    }
    return snapshot;
  }

  ExtensionLifecycleSnapshot deactivate({
    required ExtensionLifecycleSnapshot snapshot,
    required String extensionId,
    required String reason,
  }) {
    final record = snapshot.lookup(extensionId);
    if (record == null) {
      return snapshot;
    }
    return snapshot.replace(
      record.copyWith(
        status: ExtensionLifecycleStatus.deactivated,
        event: 'deactivate',
        message: reason,
        updatedAt: _now(),
      ),
    );
  }

  DateTime _now() => (clock ?? DateTime.now)().toUtc();
}
