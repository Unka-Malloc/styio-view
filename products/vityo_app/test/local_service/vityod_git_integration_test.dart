import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/local_service/vityod_source_control_command_runner.dart';
import 'package:vityo_app/src/ide/workspace/source_control_status.dart';

import '../support/vityod_test_harness.dart';

void main() {
  test('Git status, diff, and actions use typed vityod contracts', () async {
    final root = await Directory.systemTemp.createTemp('vityod-git-test-');
    final harness = await VityodTestHarness.start(clientId: 'git-test');
    addTearDown(() async {
      await harness.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    await _git(root, const <String>['init']);
    await _git(root, const <String>['config', 'user.name', 'Vityo Test']);
    await _git(root, const <String>[
      'config',
      'user.email',
      'vityo-test@example.invalid',
    ]);
    final source = File('${root.path}${Platform.pathSeparator}main.styio');
    await source.writeAsString('before\n');
    await _git(root, const <String>['add', '--', 'main.styio']);
    await _git(root, const <String>['commit', '-m', 'initial']);
    await source.writeAsString('after\n');

    final opened = await harness.client.request(
      method: 'workspace.open',
      idempotencyKey: 'git-workspace-open',
      workspaceId: 'git-workspace',
      params: <String, Object?>{'rootPath': root.path},
    );
    expect(opened.method, 'workspace.open.result');
    final runner = VityodSourceControlCommandRunner(
      client: harness.client,
      workspaceId: 'git-workspace',
    ).call;
    final status = await GitPorcelainStatusProvider(
      runner: runner,
    ).status(workspaceRoot: root.path);
    expect(status.available, isTrue);
    expect(status.changes.single.path, 'main.styio');
    expect(
      status.changes.single.unstagedStatus,
      SourceControlFileStatus.modified,
    );

    final diff = await GitSourceControlDiffProvider(
      runner: runner,
    ).diff(workspaceRoot: root.path, path: 'main.styio');
    expect(diff.available, isTrue);
    expect(diff.unifiedDiff, contains('+after'));

    final action = await GitSourceControlActionProvider(runner: runner)
        .runAction(
          workspaceRoot: root.path,
          request: const SourceControlActionRequest(
            kind: SourceControlActionKind.stage,
            paths: <String>['main.styio'],
          ),
        );
    expect(action.applied, isTrue);
    final staged = await GitPorcelainStatusProvider(
      runner: runner,
    ).status(workspaceRoot: root.path);
    expect(
      staged.changes.single.stagedStatus,
      SourceControlFileStatus.modified,
    );
  });
}

Future<void> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError('Git fixture command failed with ${result.exitCode}.');
  }
}
