import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('git porcelain status parser records branch and file states', () {
    final snapshot = const GitPorcelainStatusParser().parse('''
## feature/scm...origin/feature/scm
 M lib/main.styio
A  lib/new.styio
R  lib/old.styio -> lib/renamed.styio
?? notes/todo.md
''');

    expect(snapshot.providerKind, SourceControlProviderKind.git);
    expect(snapshot.branchName, 'feature/scm');
    expect(snapshot.clean, isFalse);
    expect(snapshot.changes.map((change) => change.path), <String>[
      'lib/main.styio',
      'lib/new.styio',
      'lib/renamed.styio',
      'notes/todo.md',
    ]);
    expect(
      snapshot.changes.first.unstagedStatus,
      SourceControlFileStatus.modified,
    );
    expect(snapshot.changes[1].stagedStatus, SourceControlFileStatus.added);
    expect(snapshot.changes[2].originalPath, 'lib/old.styio');
    expect(snapshot.changes[2].stagedStatus, SourceControlFileStatus.renamed);
    expect(
      snapshot.changes.last.stagedStatus,
      SourceControlFileStatus.untracked,
    );
  });

  test(
    'git status provider requests porcelain status through injected runner',
    () async {
      SourceControlCommandRequest? capturedRequest;
      final provider = GitPorcelainStatusProvider(
        runner: (request) async {
          capturedRequest = request;
          return const SourceControlCommandResult(
            exitCode: 0,
            stdout: '''
## ai-dev...origin/ai-dev
 M lib/main.styio
''',
          );
        },
      );

      final snapshot = await provider.status(workspaceRoot: '/workspace/vityo');

      expect(capturedRequest?.executable, 'git');
      expect(
        capturedRequest?.arguments,
        GitPorcelainStatusProvider.statusArguments,
      );
      expect(capturedRequest?.workingDirectory, '/workspace/vityo');
      expect(snapshot.available, isTrue);
      expect(snapshot.branchName, 'ai-dev');
      expect(snapshot.changes.single.path, 'lib/main.styio');
    },
  );

  test(
    'git status provider reports unavailable status on command failure',
    () async {
      final provider = GitPorcelainStatusProvider(
        runner: (_) async {
          return const SourceControlCommandResult(
            exitCode: 128,
            stderr: 'fatal: not a git repository',
          );
        },
      );

      final snapshot = await provider.status(workspaceRoot: '/workspace/vityo');

      expect(snapshot.providerKind, SourceControlProviderKind.git);
      expect(snapshot.available, isFalse);
      expect(snapshot.clean, isTrue);
      expect(snapshot.message, contains('fatal: not a git repository'));
    },
  );

  test('source control status snapshot serializes provider facts', () {
    final snapshot = const GitPorcelainStatusParser().parse('''
## main...origin/main
 M src/main.styio
?? src/new.styio
''');
    final json = snapshot.toJson();
    final changes = json['changes']! as List<Object?>;

    expect(json['providerKind'], 'git');
    expect(json['branchName'], 'main');
    expect(json['changeCount'], 2);
    expect(
      (changes.first! as Map<String, Object?>)['unstagedStatus'],
      'modified',
    );
  });

  test('source control status controller caches provider snapshot', () async {
    const snapshot = SourceControlStatusSnapshot(
      providerKind: SourceControlProviderKind.git,
      branchName: 'ai-dev',
      changes: <SourceControlFileChange>[
        SourceControlFileChange(
          path: 'src/main.styio',
          unstagedStatus: SourceControlFileStatus.modified,
        ),
      ],
    );
    final controller = SourceControlStatusController(
      provider: const StaticSourceControlStatusProvider(snapshot),
      workspaceRoot: '/workspace/vityo',
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() {
      notifications++;
    });

    final result = await controller.refresh();

    expect(result, same(snapshot));
    expect(controller.snapshot, same(snapshot));
    expect(notifications, 1);

    controller.clear();

    expect(controller.snapshot, isNull);
    expect(notifications, 2);
  });
}
