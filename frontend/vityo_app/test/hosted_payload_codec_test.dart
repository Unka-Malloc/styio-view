import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/hosted_payload_codec.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';

void main() {
  test('hosted workspace payload accepts public enum label spellings', () {
    final record = hostedWorkspaceRecordFromPayload(<String, dynamic>{
      'workspaceId': 'demo-workspace',
      'schemaVersion': '1',
      'ownerRef': 'Vityo',
      'status': HostedWorkspaceStatus.pendingDeletion.label,
      'entryUrl': 'https://hosted.example/workspaces/demo-workspace',
      'createdAt': '2026-04-21T00:00:00Z',
      'lastActiveAt': '2026-04-21T00:05:00Z',
      'retentionDays': 14,
      'exportState': HostedWorkspaceExportState.notRequested.label,
    });

    expect(record.status, HostedWorkspaceStatus.pendingDeletion);
    expect(record.exportState, HostedWorkspaceExportState.notRequested);
    expect(record.retentionDays, 14);
  });
}
