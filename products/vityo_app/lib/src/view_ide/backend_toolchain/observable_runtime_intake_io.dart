import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/observable_topology/observable_runtime_correlation.dart';
import '../services/observable_topology/observable_runtime_decoder.dart';
import '../services/observable_topology/observable_runtime_model.dart';
import '../services/observable_topology/observable_snapshot_model.dart';

ObservableRuntimeIntake createObservableRuntimeIntake() {
  return const IoObservableRuntimeIntake();
}

class IoObservableRuntimeIntake implements ObservableRuntimeIntake {
  const IoObservableRuntimeIntake();

  @override
  Future<RuntimeIntakeResult> ingest(RuntimeIntakeRequest request) {
    return compute(ingestRuntimeArtifactIsolate, request);
  }
}

Future<RuntimeIntakeResult> ingestRuntimeArtifactIsolate(
  RuntimeIntakeRequest request,
) async {
  final file = File(request.artifactPath);
  if (!await file.exists()) {
    return const RuntimeIntakeResult.rejected(
      reason: ObservableReasonCode.noRuntimeArtifact,
      detail: 'Runtime-events artifact was not found.',
    );
  }
  final folder = RuntimeOverlayFolder(
    headSnapshotId: request.headSnapshotId,
    headSiteIds: request.headSiteIds,
    capacities: request.capacities,
  );
  var seenCapability = false;
  var firstNonEmpty = true;
  await for (final line
      in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) {
      continue;
    }
    final decoded = decodeRuntimeRecord(line);
    final rejection = decoded.rejection;
    if (rejection != null && rejection.streamLevel) {
      return RuntimeIntakeResult.rejected(
        reason: ObservableReasonCode.invalidRuntimeStream,
        streamSubcode: rejection.streamSubcode,
        detail: rejection.streamSubcode?.wireValue ?? rejection.detail,
      );
    }
    if (decoded.record is RuntimeDecodedCapability) {
      if (seenCapability) {
        return const RuntimeIntakeResult.rejected(
          reason: ObservableReasonCode.invalidRuntimeStream,
          streamSubcode: RuntimeStreamSubcode.duplicateCapabilityRecord,
          detail: 'duplicate-capability-record',
        );
      }
      if (!firstNonEmpty) {
        return const RuntimeIntakeResult.rejected(
          reason: ObservableReasonCode.invalidRuntimeStream,
          streamSubcode: RuntimeStreamSubcode.capabilityRecordNotFirst,
          detail: 'capability-record-not-first',
        );
      }
      seenCapability = true;
      firstNonEmpty = false;
      folder.ingest(decoded.record!);
      continue;
    }
    firstNonEmpty = false;
    if (!seenCapability) {
      continue;
    }
    if (rejection != null) {
      // Record-level degradations are counted, never accumulated: memory stays
      // bounded by the fold's fixed capacities even for a corrupt artifact.
      folder.noteRecordRejection();
      continue;
    }
    folder.ingest(decoded.record!);
  }
  if (!seenCapability) {
    return const RuntimeIntakeResult.rejected(
      reason: ObservableReasonCode.invalidRuntimeStream,
      streamSubcode: RuntimeStreamSubcode.missingCapabilityRecord,
      detail: 'missing-capability-record',
    );
  }
  return RuntimeIntakeResult.ok(folder.finish());
}
