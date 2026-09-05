import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/observable_runtime_intake_io.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'observable_fixture_support.dart';

const _snapshot = 's1_0123456789abcdef0123456789abcdef';
const _taskSite = 'n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _awaitSite = 'n1_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IO intake of the canonical fixture is value-equal on repeats', () async {
    final intake = const IoObservableRuntimeIntake();
    final request = RuntimeIntakeRequest(
      artifactPath: observableRuntimeFixturePath('canonical.jsonl'),
      headSnapshotId: _snapshot,
      headSiteIds: const <String>[_taskSite, _awaitSite],
    );
    final first = await intake.ingest(request);
    final second = await intake.ingest(request);
    expect(first.isOk, isTrue);
    expect(second.isOk, isTrue);
    expect(first.overlay, second.overlay);
    expect(first.overlay!.presentation.isComplete, isTrue);
  });

  test('IO intake rejects an invalid capability stream', () async {
    final intake = const IoObservableRuntimeIntake();
    final result = await intake.ingest(
      RuntimeIntakeRequest(
        artifactPath: observableRuntimeVityoFixturePath(
          'missing-capability-record.jsonl',
        ),
        headSnapshotId: _snapshot,
        headSiteIds: const <String>[_taskSite, _awaitSite],
      ),
    );
    expect(result.isOk, isFalse);
    expect(result.reason, ObservableReasonCode.invalidRuntimeStream);
    expect(result.streamSubcode, RuntimeStreamSubcode.missingCapabilityRecord);
  });

  test('IO intake streams a temporary file through the fold', () async {
    final temp = await Directory.systemTemp.createTemp('vityo_runtime_intake_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final file = File('${temp.path}${Platform.pathSeparator}runtime-events.jsonl');
    await file.writeAsString(readObservableRuntimeFixture('canonical.jsonl'));
    final result = await const IoObservableRuntimeIntake().ingest(
      RuntimeIntakeRequest(
        artifactPath: file.path,
        headSnapshotId: _snapshot,
        headSiteIds: const <String>[_taskSite, _awaitSite],
      ),
    );
    expect(result.isOk, isTrue);
    expect(result.overlay!.sites[_taskSite]!.instancesCreated, 1);
    expect(result.overlay!.sites[_awaitSite]!.waits[RuntimeWaitReason.task]!.totalDurationNs, 60);
  });
}
