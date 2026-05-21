import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test(
    'source control provider adapter registry resolves non-git adapters',
    () {
      final registry = SourceControlProviderAdapterRegistry(
        adapters: <SourceControlProviderAdapterDescriptor>[
          SourceControlProviderAdapterDescriptor.git(),
          const SourceControlProviderAdapterDescriptor(
            id: 'perforce',
            label: 'Perforce',
            providerKind: SourceControlProviderKind.custom,
            capabilities: <SourceControlProviderCapability>[
              SourceControlProviderCapability.status,
              SourceControlProviderCapability.diff,
              SourceControlProviderCapability.history,
            ],
            metadata: <String, Object?>{'vendor': 'p4'},
          ),
        ],
      );

      final customDiff = registry.resolve(
        capability: SourceControlProviderCapability.diff,
        providerKind: SourceControlProviderKind.custom,
      );
      final customBranchAction = registry.resolve(
        capability: SourceControlProviderCapability.branchActions,
        providerKind: SourceControlProviderKind.custom,
      );
      final gitBranchAction = registry.resolve(
        capability: SourceControlProviderCapability.branchActions,
        providerKind: SourceControlProviderKind.git,
      );

      expect(customDiff?.id, 'perforce');
      expect(
        customDiff?.supports(SourceControlProviderCapability.history),
        isTrue,
      );
      expect(customBranchAction, isNull);
      expect(gitBranchAction?.id, 'git');
      expect(registry.manifest()['adapterCount'], 2);
      expect(
        (customDiff!.toJson()['capabilities']! as List<Object?>),
        contains('diff'),
      );
    },
  );

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
    'git diff provider requests file diff through injected runner',
    () async {
      SourceControlCommandRequest? capturedRequest;
      final provider = GitSourceControlDiffProvider(
        runner: (request) async {
          capturedRequest = request;
          return const SourceControlCommandResult(
            exitCode: 0,
            stdout: '''
diff --git a/lib/main.styio b/lib/main.styio
@@ -1 +1 @@
-old
+new
''',
          );
        },
      );

      final snapshot = await provider.diff(
        workspaceRoot: '/workspace/vityo',
        path: 'lib/main.styio',
      );

      expect(capturedRequest?.executable, 'git');
      expect(capturedRequest?.arguments, <String>[
        'diff',
        '--',
        'lib/main.styio',
      ]);
      expect(capturedRequest?.workingDirectory, '/workspace/vityo');
      expect(snapshot.available, isTrue);
      expect(snapshot.path, 'lib/main.styio');
      expect(snapshot.unifiedDiff, contains('+new'));
      expect(snapshot.reviewSummary.hunkCount, 1);
      expect(snapshot.reviewSummary.additionCount, 1);
      expect(snapshot.reviewSummary.deletionCount, 1);
      expect(snapshot.window(startLine: 1, lineLimit: 2).lines, <String>[
        '@@ -1 +1 @@',
        '-old',
      ]);
      expect(snapshot.window(startLine: 1, lineLimit: 2).hasNext, isTrue);
      expect(snapshot.toJson()['diffTruncated'], isFalse);
      expect(snapshot.toJson()['reviewSummary'], isA<Map<String, Object?>>());
      expect(snapshot.toJson()['defaultWindow'], isA<Map<String, Object?>>());
    },
  );

  test('source control diff window binding paginates visible diff content', () {
    final snapshot = SourceControlDiffSnapshot(
      providerKind: SourceControlProviderKind.git,
      path: 'src/main.styio',
      unifiedDiff: List<String>.generate(
        5,
        (index) => 'line-$index',
      ).join('\n'),
    );
    final binding = SourceControlDiffWindowBinding(
      snapshot: snapshot,
      lineLimit: 2,
    );
    final next = binding.nextWindow();
    final previous = next.previousWindow();
    final json = binding.toJson();

    expect(binding.window.lines, <String>['line-0', 'line-1']);
    expect(binding.window.hasNext, isTrue);
    expect(binding.visibleText, 'line-0\nline-1');
    expect(next.window.startLine, 2);
    expect(next.window.lines, <String>['line-2', 'line-3']);
    expect(previous.window.startLine, 0);
    expect(json['providerKind'], 'git');
    expect((json['window']! as Map<String, Object?>)['lineCount'], 2);
  });

  test('source control diff confirmation plan wraps reviewed diff actions', () {
    const snapshot = SourceControlDiffSnapshot(
      providerKind: SourceControlProviderKind.git,
      path: 'src/main.styio',
      unifiedDiff: 'diff --git a/src/main.styio b/src/main.styio\n+new\n',
    );
    final stagePlan = SourceControlDiffConfirmationPlan.fromDiff(
      snapshot: snapshot,
      kind: SourceControlActionKind.stage,
    );
    final discardPlan = SourceControlDiffConfirmationPlan.fromDiff(
      snapshot: snapshot,
      kind: SourceControlActionKind.discard,
    );
    final blockedPlan = SourceControlDiffConfirmationPlan.fromDiff(
      snapshot: const SourceControlDiffSnapshot(
        providerKind: SourceControlProviderKind.git,
        path: 'src/empty.styio',
      ),
      kind: SourceControlActionKind.stage,
    );

    expect(stagePlan.canRun, isTrue);
    expect(stagePlan.toActionRequest().paths, <String>['src/main.styio']);
    expect(stagePlan.reviewSummary.additionCount, 1);
    expect(discardPlan.risk, SourceControlActionRisk.destructive);
    expect(discardPlan.requiresConfirmation, isTrue);
    expect(blockedPlan.canRun, isFalse);
    expect(blockedPlan.blockedReason, contains('reviewed diff content'));
    expect(stagePlan.toJson()['summary'], contains('reviewed diff'));
  });

  test(
    'git action provider stages and commits through injected runner',
    () async {
      final requests = <SourceControlCommandRequest>[];
      final provider = GitSourceControlActionProvider(
        runner: (request) async {
          requests.add(request);
          return const SourceControlCommandResult(exitCode: 0, stdout: 'ok\n');
        },
      );

      final stage = await provider.runAction(
        workspaceRoot: '/workspace/vityo',
        request: const SourceControlActionRequest(
          kind: SourceControlActionKind.stage,
          paths: <String>[' src/main.styio ', ''],
        ),
      );
      final commit = await provider.runAction(
        workspaceRoot: '/workspace/vityo',
        request: const SourceControlActionRequest(
          kind: SourceControlActionKind.commit,
          message: ' checkpoint ',
        ),
      );

      expect(stage.applied, isTrue);
      expect(stage.paths, <String>['src/main.styio']);
      expect(requests.first.arguments, <String>['add', '--', 'src/main.styio']);
      expect(commit.applied, isTrue);
      expect(requests.last.arguments, <String>['commit', '-m', 'checkpoint']);
      expect(requests.last.workingDirectory, '/workspace/vityo');
    },
  );

  test('git action provider rejects unsafe incomplete requests', () async {
    var invoked = false;
    final provider = GitSourceControlActionProvider(
      runner: (_) async {
        invoked = true;
        return const SourceControlCommandResult(exitCode: 0);
      },
    );

    final stage = await provider.runAction(
      workspaceRoot: '/workspace/vityo',
      request: const SourceControlActionRequest(
        kind: SourceControlActionKind.stage,
      ),
    );
    final commit = await provider.runAction(
      workspaceRoot: '/workspace/vityo',
      request: const SourceControlActionRequest(
        kind: SourceControlActionKind.commit,
      ),
    );

    expect(stage.applied, isFalse);
    expect(stage.message, contains('no paths'));
    expect(commit.applied, isFalse);
    expect(commit.message, contains('commit message is required'));
    expect(invoked, isFalse);
  });

  test('source control action plan classifies risky actions', () {
    final discard = SourceControlActionPlan.fromRequest(
      const SourceControlActionRequest(
        kind: SourceControlActionKind.discard,
        paths: <String>[' src/main.styio '],
      ),
    );
    final commit = SourceControlActionPlan.fromRequest(
      const SourceControlActionRequest(kind: SourceControlActionKind.commit),
    );

    expect(discard.normalizedPaths, <String>['src/main.styio']);
    expect(discard.risk, SourceControlActionRisk.destructive);
    expect(discard.requiresConfirmation, isTrue);
    expect(discard.canRun, isTrue);
    expect(discard.toJson()['risk'], 'destructive');
    expect(commit.canRun, isFalse);
    expect(commit.blockedReason, contains('commit message'));
  });

  test('git branch provider loads current branch and branch list', () async {
    final requests = <SourceControlCommandRequest>[];
    final provider = GitSourceControlBranchProvider(
      runner: (request) async {
        requests.add(request);
        if (requests.length == 1) {
          return const SourceControlCommandResult(
            exitCode: 0,
            stdout: 'ai-dev\n',
          );
        }
        return const SourceControlCommandResult(
          exitCode: 0,
          stdout: 'main\nai-dev\nfeature/scm\n',
        );
      },
    );

    final snapshot = await provider.branches(workspaceRoot: '/workspace/vityo');

    expect(requests.first.arguments, <String>['branch', '--show-current']);
    expect(
      requests.last.arguments,
      GitSourceControlBranchProvider.branchArguments,
    );
    expect(snapshot.available, isTrue);
    expect(snapshot.currentBranch, 'ai-dev');
    expect(snapshot.branches, <String>['main', 'ai-dev', 'feature/scm']);
    expect(snapshot.toJson()['branchCount'], 3);
  });

  test('git branch action provider switches planned branches', () async {
    SourceControlCommandRequest? capturedRequest;
    final provider = GitSourceControlBranchActionProvider(
      runner: (request) async {
        capturedRequest = request;
        return const SourceControlCommandResult(
          exitCode: 0,
          stdout: 'Switched to branch feature/scm\n',
        );
      },
    );
    const snapshot = SourceControlBranchSnapshot(
      providerKind: SourceControlProviderKind.git,
      currentBranch: 'ai-dev',
      branches: <String>['main', 'ai-dev', 'feature/scm'],
    );

    final plan = SourceControlBranchSwitchPlan.fromSnapshot(
      snapshot: snapshot,
      targetBranch: 'feature/scm',
    );
    final blocked = SourceControlBranchSwitchPlan.fromSnapshot(
      snapshot: snapshot,
      targetBranch: 'missing',
    );
    final result = await provider.switchBranch(
      workspaceRoot: '/workspace/vityo',
      plan: plan,
    );

    expect(plan.canRun, isTrue);
    expect(plan.summary, 'switch ai-dev -> feature/scm');
    expect(plan.toJson()['targetBranch'], 'feature/scm');
    expect(blocked.canRun, isFalse);
    expect(blocked.blockedReason, contains('not in the branch list'));
    expect(result.applied, isTrue);
    expect(result.targetBranch, 'feature/scm');
    expect(capturedRequest?.arguments, <String>['switch', 'feature/scm']);
    expect(result.toJson()['applied'], isTrue);
  });

  test('git history provider parses log entries', () async {
    SourceControlCommandRequest? capturedRequest;
    final provider = GitSourceControlHistoryProvider(
      runner: (request) async {
        capturedRequest = request;
        return const SourceControlCommandResult(
          exitCode: 0,
          stdout:
              'abc123def\u001fabcd123\u001fUnka\u001f2026-05-20T10:00:00+08:00\u001fAdd SCM provider\n',
        );
      },
    );

    final snapshot = await provider.history(
      workspaceRoot: '/workspace/vityo',
      limit: 10,
    );

    expect(
      capturedRequest?.arguments,
      GitSourceControlHistoryProvider.historyArgumentsFor(10),
    );
    expect(snapshot.available, isTrue);
    expect(snapshot.entries.single.revision, 'abc123def');
    expect(snapshot.entries.single.shortRevision, 'abcd123');
    expect(snapshot.entries.single.author, 'Unka');
    expect(snapshot.entries.single.summary, 'Add SCM provider');
    expect(snapshot.toJson()['entryCount'], 1);
  });

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
      diffProvider: const StaticSourceControlDiffProvider(
        SourceControlDiffSnapshot(
          providerKind: SourceControlProviderKind.git,
          path: 'src/main.styio',
          unifiedDiff: 'diff --git a/src/main.styio b/src/main.styio\n',
        ),
      ),
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

    final diff = await controller.previewDiff('src/main.styio');

    expect(controller.diffPreview, same(diff));
    expect(controller.hasDiffPreview, isTrue);
    expect(diff.unifiedDiff, contains('diff --git'));
    expect(notifications, 2);

    controller.clear();

    expect(controller.snapshot, isNull);
    expect(controller.diffPreview, isNull);
    expect(notifications, 3);
  });

  test('source control status controller records action results', () async {
    final controller = SourceControlStatusController(
      provider: const StaticSourceControlStatusProvider(
        SourceControlStatusSnapshot(
          providerKind: SourceControlProviderKind.git,
          changes: <SourceControlFileChange>[],
        ),
      ),
      actionProvider: _FakeSourceControlActionProvider(),
      workspaceRoot: '/workspace/vityo',
    );
    addTearDown(controller.dispose);

    final result = await controller.runAction(
      const SourceControlActionRequest(
        kind: SourceControlActionKind.stage,
        paths: <String>['src/main.styio'],
      ),
    );

    expect(result.applied, isTrue);
    expect(result.kind, SourceControlActionKind.stage);
    expect(result.paths, <String>['src/main.styio']);
    expect(controller.lastActionResult, same(result));
    expect(result.toJson()['kind'], 'stage');
  });

  test('source control controller exposes agent context snapshot', () async {
    final controller = SourceControlStatusController(
      provider: const StaticSourceControlStatusProvider(
        SourceControlStatusSnapshot(
          providerKind: SourceControlProviderKind.git,
          branchName: 'ai-dev',
          changes: <SourceControlFileChange>[
            SourceControlFileChange(
              path: 'src/staged.styio',
              stagedStatus: SourceControlFileStatus.added,
            ),
            SourceControlFileChange(
              path: 'src/main.styio',
              unstagedStatus: SourceControlFileStatus.modified,
            ),
            SourceControlFileChange(
              path: 'src/conflict.styio',
              unstagedStatus: SourceControlFileStatus.conflicted,
            ),
          ],
        ),
      ),
      diffProvider: const StaticSourceControlDiffProvider(
        SourceControlDiffSnapshot(
          providerKind: SourceControlProviderKind.git,
          path: 'src/main.styio',
          unifiedDiff: '''
diff --git a/src/main.styio b/src/main.styio
@@ -1 +1 @@
-old
+new
''',
        ),
      ),
      workspaceRoot: '/workspace/vityo',
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    await controller.previewDiff('src/main.styio');
    controller.planAction(
      const SourceControlActionRequest(
        kind: SourceControlActionKind.discard,
        paths: <String>['src/main.styio'],
      ),
    );

    final context = controller.agentContextSnapshot;
    final json = context.toJson();
    final diffReview = json['diffReview']! as Map<String, Object?>;
    final pendingActionPlan =
        json['pendingActionPlan']! as Map<String, Object?>;
    final mergeWorkflowPlan =
        json['mergeWorkflowPlan']! as Map<String, Object?>;

    expect(context.loaded, isTrue);
    expect(context.providerKind, 'git');
    expect(context.branchName, 'ai-dev');
    expect(context.stagedPaths, <String>['src/staged.styio']);
    expect(context.unstagedPaths, <String>[
      'src/main.styio',
      'src/conflict.styio',
    ]);
    expect(context.conflictedPaths, <String>['src/conflict.styio']);
    expect(context.requiresHumanConfirmation, isTrue);
    expect(context.mergeWorkflowPlan?.conflictCount, 1);
    expect(context.mergeWorkflowPlan?.canOpenMergeWorkflow, isTrue);
    expect(json['workspaceRoot'], '/workspace/vityo');
    expect(json['changeCount'], 3);
    expect(mergeWorkflowPlan['conflictedPaths'], <String>[
      'src/conflict.styio',
    ]);
    expect(mergeWorkflowPlan['requiresHumanConfirmation'], isTrue);
    expect(diffReview['additionCount'], 1);
    expect(diffReview['deletionCount'], 1);
    expect((json['diffWindow']! as Map<String, Object?>)['lineCount'], 5);
    expect(pendingActionPlan['risk'], 'destructive');
  });

  test('source control merge workflow plan exposes conflict resolutions', () {
    const snapshot = SourceControlStatusSnapshot(
      providerKind: SourceControlProviderKind.git,
      branchName: 'ai-dev',
      changes: <SourceControlFileChange>[
        SourceControlFileChange(
          path: 'src/conflict.styio',
          unstagedStatus: SourceControlFileStatus.conflicted,
        ),
        SourceControlFileChange(
          path: 'src/main.styio',
          unstagedStatus: SourceControlFileStatus.modified,
        ),
      ],
    );

    final plan = SourceControlMergeWorkflowPlan.fromStatus(snapshot);
    final resolution = plan.conflictPlans.single;

    expect(plan.conflictCount, 1);
    expect(plan.conflictedPaths, <String>['src/conflict.styio']);
    expect(plan.canOpenMergeWorkflow, isTrue);
    expect(plan.requiresHumanConfirmation, isTrue);
    expect(resolution.canResolve, isTrue);
    expect(
      resolution.resolutionKinds,
      contains(SourceControlConflictResolutionKind.openMergeEditor),
    );
    expect(plan.toJson()['conflictCount'], 1);
  });

  test(
    'source control conflict resolution registry executes provider operations',
    () async {
      const snapshot = SourceControlStatusSnapshot(
        providerKind: SourceControlProviderKind.git,
        branchName: 'ai-dev',
        changes: <SourceControlFileChange>[
          SourceControlFileChange(
            path: 'src/conflict.styio',
            unstagedStatus: SourceControlFileStatus.conflicted,
          ),
        ],
      );
      final workflowPlan = SourceControlMergeWorkflowPlan.fromStatus(snapshot);
      final request = SourceControlConflictResolutionRequest.fromPlan(
        workflowPlan: workflowPlan,
        conflictPlan: workflowPlan.conflictPlans.single,
        kind: SourceControlConflictResolutionKind.acceptCurrent,
      );
      final provider = _RecordingSourceControlConflictResolutionProvider();
      final registry = SourceControlConflictResolutionProviderRegistry(
        providers: <SourceControlConflictResolutionProvider>[provider],
      );

      final result = await registry.resolve(request);
      final missing = await SourceControlConflictResolutionProviderRegistry()
          .resolve(request);

      expect(request.canRun, isTrue);
      expect(result.accepted, isTrue);
      expect(result.path, 'src/conflict.styio');
      expect(
        provider.requests.single.kind,
        SourceControlConflictResolutionKind.acceptCurrent,
      );
      expect(missing.accepted, isFalse);
      expect(missing.toJson()['message'], contains('No source control'));
      expect(registry.toJson()['providerCount'], 1);
    },
  );

  test('source control status controller confirms planned action', () async {
    final controller = SourceControlStatusController(
      provider: const StaticSourceControlStatusProvider(
        SourceControlStatusSnapshot(
          providerKind: SourceControlProviderKind.git,
          changes: <SourceControlFileChange>[],
        ),
      ),
      actionProvider: _FakeSourceControlActionProvider(),
      workspaceRoot: '/workspace/vityo',
    );
    addTearDown(controller.dispose);

    final plan = controller.planAction(
      const SourceControlActionRequest(
        kind: SourceControlActionKind.discard,
        paths: <String>['src/main.styio'],
      ),
    );
    final result = await controller.confirmPendingAction();

    expect(plan.requiresConfirmation, isTrue);
    expect(result.applied, isTrue);
    expect(result.kind, SourceControlActionKind.discard);
    expect(controller.pendingActionPlan, isNull);
    expect(controller.lastActionResult, same(result));
  });

  test('source control status controller records hunk action result', () async {
    const diff = SourceControlDiffSnapshot(
      providerKind: SourceControlProviderKind.git,
      path: 'src/main.styio',
      unifiedDiff: '''
diff --git a/src/main.styio b/src/main.styio
--- a/src/main.styio
+++ b/src/main.styio
@@ -1,1 +1,1 @@
-old
+new
''',
    );
    final controller = SourceControlStatusController(
      provider: const StaticSourceControlStatusProvider(
        SourceControlStatusSnapshot(
          providerKind: SourceControlProviderKind.git,
          changes: <SourceControlFileChange>[],
        ),
      ),
      partialPatchProvider: const _FakeSourceControlPartialPatchProvider(),
      workspaceRoot: '/workspace/vityo',
    );
    addTearDown(controller.dispose);
    final plan = SourceControlDiffHunkActionPlan.fromDiff(
      snapshot: diff,
      kind: SourceControlActionKind.stage,
      selectedHunkIndexes: const <int>[0],
    );

    final result = await controller.runHunkAction(plan);

    expect(result.applied, isTrue);
    expect(result.kind, SourceControlActionKind.stage);
    expect(result.selectedHunkIndexes, <int>[0]);
    expect(controller.lastPartialPatchResult, same(result));
  });

  test(
    'source control status controller persists hunk selection confirmations',
    () async {
      const diff = SourceControlDiffSnapshot(
        providerKind: SourceControlProviderKind.git,
        path: 'src/main.styio',
        unifiedDiff: '''
diff --git a/src/main.styio b/src/main.styio
--- a/src/main.styio
+++ b/src/main.styio
@@ -1,1 +1,1 @@
-old
+new
@@ -8,1 +8,1 @@
-before
+after
''',
      );
      final controller = SourceControlStatusController(
        provider: const StaticSourceControlStatusProvider(
          SourceControlStatusSnapshot(
            providerKind: SourceControlProviderKind.git,
            changes: <SourceControlFileChange>[],
          ),
        ),
        diffProvider: const StaticSourceControlDiffProvider(diff),
        partialPatchProvider: const _FakeSourceControlPartialPatchProvider(),
        workspaceRoot: '/workspace/vityo',
      );
      addTearDown(controller.dispose);

      await controller.previewDiff('src/main.styio');
      final selection = controller.toggleHunkSelection(0);
      final plan = controller.planSelectedHunkAction(
        SourceControlActionKind.discard,
      );
      final pendingJson = controller.agentContextSnapshot.toJson();

      expect(selection?.selectedHunkIndexes, <int>[0]);
      expect(plan?.requiresConfirmation, isTrue);
      expect(controller.pendingHunkDiscardConfirmation?.readyForDialog, isTrue);
      expect(pendingJson['requiresHumanConfirmation'], isTrue);
      expect(
        (pendingJson['hunkSelectionState']!
            as Map<String, Object?>)['selectedHunkIndexes'],
        <int>[0],
      );
      expect(
        (pendingJson['pendingHunkDiscardConfirmation']!
            as Map<String, Object?>)['confirmed'],
        isFalse,
      );

      final result = await controller.confirmPendingHunkDiscard();
      final confirmedJson = controller.agentContextSnapshot.toJson();

      expect(result.applied, isTrue);
      expect(result.selectedHunkIndexes, <int>[0]);
      expect(controller.pendingHunkDiscardConfirmation, isNull);
      expect(controller.hunkSelectionState?.hasSelection, isFalse);
      expect(
        (confirmedJson['lastPartialPatchResult']!
            as Map<String, Object?>)['applied'],
        isTrue,
      );
    },
  );

  test(
    'source control status controller restores diff session state',
    () async {
      const diff = SourceControlDiffSnapshot(
        providerKind: SourceControlProviderKind.git,
        path: 'src/main.styio',
        unifiedDiff: '''
diff --git a/src/main.styio b/src/main.styio
--- a/src/main.styio
+++ b/src/main.styio
@@ -1,1 +1,1 @@
-old
+new
@@ -8,1 +8,1 @@
-before
+after
''',
      );
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_source_control_controller_diff_session_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final dataStore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final store = SourceControlDiffSessionStore.fromDataStore(
        dataStore: dataStore,
      );
      final controller = SourceControlStatusController(
        provider: const StaticSourceControlStatusProvider(
          SourceControlStatusSnapshot(
            providerKind: SourceControlProviderKind.git,
            changes: <SourceControlFileChange>[],
          ),
        ),
        diffProvider: const StaticSourceControlDiffProvider(diff),
        diffSessionStore: store,
        workspaceRoot: '/workspace/vityo',
      );
      addTearDown(controller.dispose);

      await controller.previewDiff('src/main.styio');
      controller.toggleHunkSelection(1);
      await controller.persistDiffSession();

      final restoredController = SourceControlStatusController(
        provider: const StaticSourceControlStatusProvider(
          SourceControlStatusSnapshot(
            providerKind: SourceControlProviderKind.git,
            changes: <SourceControlFileChange>[],
          ),
        ),
        diffProvider: const StaticSourceControlDiffProvider(diff),
        diffSessionStore: store,
        workspaceRoot: '/workspace/vityo',
      );
      addTearDown(restoredController.dispose);

      final restoredSession = await restoredController.restoreDiffSession();
      await restoredController.previewDiff('src/main.styio');

      expect(restoredSession.selectedHunkIndexes, <int>[1]);
      expect(restoredController.diffSessionState?.path, 'src/main.styio');
      expect(restoredController.hunkSelectionState?.selectedHunkIndexes, <int>[
        1,
      ]);
    },
  );

  test(
    'source control controller caches branch and history planning facts',
    () async {
      final controller = SourceControlStatusController(
        provider: const StaticSourceControlStatusProvider(
          SourceControlStatusSnapshot(
            providerKind: SourceControlProviderKind.git,
            branchName: 'ai-dev',
            changes: <SourceControlFileChange>[],
          ),
        ),
        branchProvider: const StaticSourceControlBranchProvider(
          SourceControlBranchSnapshot(
            providerKind: SourceControlProviderKind.git,
            currentBranch: 'ai-dev',
            branches: <String>['main', 'ai-dev', 'feature/scm'],
          ),
        ),
        historyProvider: const StaticSourceControlHistoryProvider(
          SourceControlHistorySnapshot(
            providerKind: SourceControlProviderKind.git,
            entries: <SourceControlHistoryEntry>[
              SourceControlHistoryEntry(
                revision: 'abcdef123',
                shortRevision: 'abcdef1',
                summary: 'Add branch facts',
              ),
            ],
          ),
        ),
        workspaceRoot: '/workspace/vityo',
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      final branches = await controller.refreshBranches();
      final plan = controller.planBranchSwitch('feature/scm');
      final history = await controller.refreshHistory(limit: 5);
      final contextJson = controller.agentContextSnapshot.toJson();

      expect(branches.currentBranch, 'ai-dev');
      expect(branches.branches, contains('feature/scm'));
      expect(plan.canRun, isTrue);
      expect(controller.pendingBranchSwitchPlan, same(plan));
      expect(history.entries.single.shortRevision, 'abcdef1');
      expect(
        (contextJson['branches']! as Map<String, Object?>)['branchCount'],
        3,
      );
      expect(
        (contextJson['pendingBranchSwitchPlan']!
            as Map<String, Object?>)['targetBranch'],
        'feature/scm',
      );
      expect(
        (contextJson['history']! as Map<String, Object?>)['entryCount'],
        1,
      );
    },
  );

  test(
    'source control status controller reports missing action provider',
    () async {
      final controller = SourceControlStatusController(
        provider: const StaticSourceControlStatusProvider(
          SourceControlStatusSnapshot(
            providerKind: SourceControlProviderKind.git,
            changes: <SourceControlFileChange>[],
          ),
        ),
        workspaceRoot: '/workspace/vityo',
      );
      addTearDown(controller.dispose);

      final result = await controller.runAction(
        const SourceControlActionRequest(
          kind: SourceControlActionKind.commit,
          message: 'checkpoint',
        ),
      );

      expect(result.applied, isFalse);
      expect(result.message, contains('no action provider'));
      expect(controller.lastActionResult, same(result));
    },
  );
}

class _FakeSourceControlActionProvider extends SourceControlActionProvider {
  @override
  SourceControlProviderKind get providerKind => SourceControlProviderKind.git;

  @override
  Future<SourceControlActionResult> runAction({
    required String workspaceRoot,
    required SourceControlActionRequest request,
  }) async {
    return SourceControlActionResult(
      kind: request.kind,
      applied: true,
      paths: request.paths,
      message: workspaceRoot,
    );
  }
}

class _FakeSourceControlPartialPatchProvider
    extends SourceControlPartialPatchProvider {
  const _FakeSourceControlPartialPatchProvider();

  @override
  SourceControlProviderKind get providerKind => SourceControlProviderKind.git;

  @override
  Future<SourceControlPartialPatchResult> runHunkAction({
    required String workspaceRoot,
    required SourceControlDiffHunkActionPlan plan,
  }) async {
    return SourceControlPartialPatchResult(
      kind: plan.kind,
      path: plan.path,
      selectedHunkIndexes: plan.selectedHunkIndexes,
      applied: true,
      message: workspaceRoot,
    );
  }
}

class _RecordingSourceControlConflictResolutionProvider
    extends SourceControlConflictResolutionProvider {
  final List<SourceControlConflictResolutionRequest> requests =
      <SourceControlConflictResolutionRequest>[];

  @override
  SourceControlProviderKind get providerKind => SourceControlProviderKind.git;

  @override
  bool supports(SourceControlConflictResolutionRequest request) {
    return request.providerKind == providerKind && request.canRun;
  }

  @override
  Future<SourceControlConflictResolutionResult> resolve(
    SourceControlConflictResolutionRequest request,
  ) async {
    requests.add(request);
    return SourceControlConflictResolutionResult.accepted(
      path: request.path,
      kind: request.kind,
      message: 'Resolved ${request.path}.',
    );
  }
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
