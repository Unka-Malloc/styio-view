import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/source_control/source_control.dart';

void main() {
  testWidgets('source control surface renders dirty documents and actions', (
    tester,
  ) async {
    String? openedDocumentId;
    String? previewedDocumentId;
    List<String>? stagedPaths;
    List<String>? unstagedPaths;
    SourceControlBranchSwitchPlan? switchedBranchPlan;
    SourceControlDiffConfirmationPlan? confirmedDiffPlan;
    var saveAllCount = 0;
    var refreshCount = 0;
    var openCommitCount = 0;
    const diffSnapshot = SourceControlDiffSnapshot(
      providerKind: SourceControlProviderKind.git,
      path: 'src/main.styio',
      unifiedDiff: 'diff --git a/src/main.styio b/src/main.styio\n+value\n',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceControlSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            workspaceFileCount: 3,
            changedDocumentIds: const <String>[
              'src/main.styio',
              'src/lib.styio',
            ],
            status: const GitPorcelainStatusParser().parse('''
## ai-dev...origin/ai-dev
 M src/main.styio
R  src/old.styio -> src/new.styio
'''),
            diffPreview: diffSnapshot,
            diffWindowBinding: const SourceControlDiffWindowBinding(
              snapshot: diffSnapshot,
              lineLimit: 2,
            ),
            commitDraft: const SourceControlCommitDraft(
              workspaceId: 'demo',
              message: 'Add source control UI',
              selectedPaths: <String>['src/main.styio'],
            ),
            commitDialogState: SourceControlCommitDialogState.fromDraft(
              open: true,
              draft: const SourceControlCommitDraft(
                workspaceId: 'demo',
                message: 'Add source control UI',
                selectedPaths: <String>['src/main.styio'],
              ),
            ),
            branchSnapshot: const SourceControlBranchSnapshot(
              providerKind: SourceControlProviderKind.git,
              currentBranch: 'ai-dev',
              branches: <String>['main', 'ai-dev', 'feature/scm'],
            ),
            historySnapshot: const SourceControlHistorySnapshot(
              providerKind: SourceControlProviderKind.git,
              entries: <SourceControlHistoryEntry>[
                SourceControlHistoryEntry(
                  revision: 'abcdef123',
                  shortRevision: 'abcdef1',
                  summary: 'Add source control UI',
                  author: 'Vityo Bot',
                  authoredAt: '2026-05-20',
                ),
                SourceControlHistoryEntry(
                  revision: '123456789',
                  shortRevision: '1234567',
                  summary: 'Wire branch picker',
                ),
              ],
            ),
            adapterRegistry: SourceControlProviderAdapterRegistry(
              adapters: <SourceControlProviderAdapterDescriptor>[
                SourceControlProviderAdapterDescriptor.git(),
                const SourceControlProviderAdapterDescriptor(
                  id: 'acme-scm',
                  label: 'Acme SCM',
                  providerKind: SourceControlProviderKind.custom,
                  capabilities: <SourceControlProviderCapability>[
                    SourceControlProviderCapability.status,
                    SourceControlProviderCapability.diff,
                  ],
                ),
              ],
            ),
            onOpenFile: (documentId) async {
              openedDocumentId = documentId;
            },
            onSaveAll: () async {
              saveAllCount += 1;
            },
            onRefresh: () async {
              refreshCount += 1;
            },
            onPreviewDiff: (documentId) async {
              previewedDocumentId = documentId;
            },
            onStagePaths: (paths) async {
              stagedPaths = paths;
            },
            onUnstagePaths: (paths) async {
              unstagedPaths = paths;
            },
            onSwitchBranch: (plan) async {
              switchedBranchPlan = plan;
            },
            onOpenCommit: () async {
              openCommitCount += 1;
            },
            onConfirmDiffAction: (plan) async {
              confirmedDiffPlan = plan;
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('source-control-surface')),
      findsOneWidget,
    );
    expect(find.text('Source Control'), findsOneWidget);
    expect(find.text('workspace-files 3'), findsOneWidget);
    expect(find.text('changed 2'), findsOneWidget);
    expect(find.text('provider git'), findsOneWidget);
    expect(find.text('branch ai-dev'), findsOneWidget);
    expect(find.text('branches 3'), findsOneWidget);
    expect(find.text('history 2'), findsOneWidget);
    expect(find.text('providers 2'), findsOneWidget);
    expect(find.text('draft ready'), findsOneWidget);
    expect(find.text('commit-dialog ready'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('source-control-commit-draft-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('source-control-branch-picker-summary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('source-control-history-summary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('source-control-provider-adapter-summary')),
      findsOneWidget,
    );
    expect(find.text('Add source control UI'), findsWidgets);
    expect(find.text('dialog ready'), findsOneWidget);
    expect(find.text('current ai-dev'), findsOneWidget);
    expect(find.text('feature/scm'), findsOneWidget);
    expect(find.text('abcdef1 · Add source control UI'), findsOneWidget);
    expect(find.text('1234567 · Wire branch picker'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('source-control-history-entry-abcdef1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('source-control-history-entry-abcdef1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('revision abcdef123'), findsOneWidget);
    expect(find.text('author Vityo Bot'), findsOneWidget);
    expect(find.text('authored 2026-05-20'), findsOneWidget);
    expect(find.text('Git: status, diff, actions, branches'), findsOneWidget);
    expect(find.text('Acme SCM: status, diff'), findsOneWidget);
    expect(find.text('git 2'), findsOneWidget);
    expect(find.text('staged 1'), findsOneWidget);
    expect(find.text('unstaged 1'), findsOneWidget);
    expect(find.text('src/new.styio'), findsOneWidget);
    expect(find.text('src/main.styio'), findsWidgets);
    expect(find.text('src/lib.styio'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('source-control-diff-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('source-control-diff-review-summary')),
      findsOneWidget,
    );
    expect(find.text('Diff Preview'), findsOneWidget);
    expect(find.text('hunks 0'), findsOneWidget);
    expect(find.text('+1 -0'), findsWidgets);
    expect(find.text('virtual-window 0-2/3'), findsOneWidget);
    expect(find.text('has next window'), findsOneWidget);
    expect(find.textContaining('+value'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('source-control-diff-confirmation')),
      findsOneWidget,
    );
    expect(find.text('stage risk index-write'), findsOneWidget);
    expect(find.text('discard requires confirmation'), findsOneWidget);

    Future<void> tapVisible(String key) async {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
    }

    await tapVisible('source-control-save-all');
    await tapVisible('source-control-refresh');
    await tapVisible('source-control-stage-all');
    await tapVisible('source-control-unstage-all');
    await tapVisible('source-control-open-commit');
    await tapVisible('source-control-switch-branch-feature/scm');

    await tapVisible('source-control-git-change-src/new.styio');
    expect(openedDocumentId, 'src/new.styio');

    await tapVisible('source-control-preview-diff-src/main.styio');
    await tapVisible('source-control-confirm-diff-stage');
    expect(confirmedDiffPlan?.kind, SourceControlActionKind.stage);
    expect(confirmedDiffPlan?.path, 'src/main.styio');
    await tapVisible('source-control-confirm-diff-discard');
    expect(confirmedDiffPlan?.kind, SourceControlActionKind.discard);
    await tapVisible('source-control-change-src/main.styio');

    expect(openedDocumentId, 'src/main.styio');
    expect(previewedDocumentId, 'src/main.styio');
    expect(stagedPaths, <String>['src/main.styio']);
    expect(unstagedPaths, <String>['src/new.styio']);
    expect(switchedBranchPlan?.summary, 'switch ai-dev -> feature/scm');
    expect(saveAllCount, 1);
    expect(refreshCount, 1);
    expect(openCommitCount, 1);
  });

  testWidgets('source control surface renders unavailable provider state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceControlSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            workspaceFileCount: 3,
            changedDocumentIds: const <String>[],
            status: const SourceControlStatusSnapshot(
              providerKind: SourceControlProviderKind.git,
              available: false,
              changes: <SourceControlFileChange>[],
              message: 'Git status failed with exit code 128.',
            ),
          ),
        ),
      ),
    );

    expect(find.text('provider git'), findsOneWidget);
    expect(find.text('provider unavailable'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('source-control-provider-message')),
      findsOneWidget,
    );
    expect(find.text('Git status failed with exit code 128.'), findsOneWidget);
  });
}
