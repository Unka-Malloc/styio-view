import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/process/process_adapter.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/process/process_facts.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/process/process_manager.dart';
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
    'process source control runner executes through process manager',
    () async {
      final processManager = _FakeProcessManager(
        const ProcessCommandResult(
          status: ProcessCommandStatus.succeeded,
          executablePath: 'git',
          arguments: <String>['status'],
          exitCode: 0,
          stdout: '## ai-dev\n',
          stderr: '',
          duration: Duration(milliseconds: 12),
        ),
      );
      final runner = ProcessSourceControlCommandRunner(
        processManager: processManager,
        timeout: const Duration(seconds: 3),
      );

      final result = await runner(
        const SourceControlCommandRequest(
          executable: 'git',
          arguments: <String>['status', '--porcelain=v1', '--branch'],
          workingDirectory: '/workspace/vityo',
        ),
      );

      expect(processManager.lastRequest?.executablePath, 'git');
      expect(processManager.lastRequest?.arguments, <String>[
        'status',
        '--porcelain=v1',
        '--branch',
      ]);
      expect(processManager.lastRequest?.workingDirectory, '/workspace/vityo');
      expect(processManager.lastRequest?.timeout, const Duration(seconds: 3));
      expect(result.exitCode, 0);
      expect(result.stdout, '## ai-dev\n');
    },
  );

  test('process source control runner maps blocked process status', () async {
    final processManager = _FakeProcessManager(
      const ProcessCommandResult(
        status: ProcessCommandStatus.blocked,
        executablePath: 'git',
        arguments: <String>['status'],
        exitCode: null,
        stdout: '',
        stderr: '',
        duration: Duration.zero,
        message: 'Process execution is not available.',
      ),
    );

    final result =
        await ProcessSourceControlCommandRunner(
          processManager: processManager,
        ).call(
          const SourceControlCommandRequest(
            executable: 'git',
            arguments: <String>['status'],
            workingDirectory: '/workspace/vityo',
          ),
        );

    expect(result.exitCode, 126);
    expect(result.stderr, 'Process execution is not available.');
  });

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

class _FakeProcessManager implements ProcessManager {
  _FakeProcessManager(this.result)
    : facts = ProcessFacts.linuxDebianArm(),
      compatibility = ProcessAdapter(ProcessFacts.linuxDebianArm()).adapt();

  final ProcessCommandResult result;
  ProcessCommandRequest? lastRequest;

  @override
  final ProcessFacts facts;

  @override
  final ProcessCompatibility compatibility;

  @override
  Future<ProcessCommandResult> run(ProcessCommandRequest request) async {
    lastRequest = request;
    return result;
  }

  @override
  ProcessOperationFailure? failureFor(
    ProcessCommandResult result, {
    String operation = 'process.spawn',
    String? recoveryHint,
  }) {
    return null;
  }
}
