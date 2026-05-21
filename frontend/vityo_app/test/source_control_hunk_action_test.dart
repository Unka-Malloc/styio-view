import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/workspace/source_control_status.dart';
import 'package:vityo_app/src/view_render/platform/viewport_profile.dart';
import 'package:vityo_app/src/view_render/source_control/source_control_surface.dart';

const _diff = '''
diff --git a/src/main.styio b/src/main.styio
--- a/src/main.styio
+++ b/src/main.styio
@@ -1,3 +1,4 @@
 #main := () => {
-  old
+  new
+  extra
 }
@@ -10,2 +11,2 @@
-#old := 1
+#next := 1
''';

void main() {
  test('source control diff parses hunks and builds hunk action plans', () {
    const snapshot = SourceControlDiffSnapshot(
      providerKind: SourceControlProviderKind.git,
      path: 'src/main.styio',
      unifiedDiff: _diff,
    );

    final hunks = snapshot.hunks;
    final plan = SourceControlDiffHunkActionPlan.fromDiff(
      snapshot: snapshot,
      kind: SourceControlActionKind.discard,
      selectedHunkIndexes: const <int>[1],
    );

    expect(hunks, hasLength(2));
    expect(hunks.first.additionCount, 2);
    expect(hunks.first.deletionCount, 1);
    expect(hunks.first.summary, contains('hunk 1'));
    expect(plan.canSelect, isTrue);
    expect(plan.requiresConfirmation, isTrue);
    expect(plan.selectedHunkIndexes, <int>[1]);
    expect(plan.summary, contains('discard 1 hunk'));
    expect(plan.selectedPatch, contains('@@ -10,2 +11,2 @@'));
    expect(plan.selectedPatch, isNot(contains('extra')));
    expect(plan.toJson()['selectedPatchLineCount'], greaterThan(0));
  });

  test('source control hunk selection state confirms destructive discard', () {
    const snapshot = SourceControlDiffSnapshot(
      providerKind: SourceControlProviderKind.git,
      path: 'src/main.styio',
      unifiedDiff: _diff,
    );

    final selection = SourceControlHunkSelectionState.fromDiff(
      snapshot: snapshot,
    ).toggle(0).toggle(1);
    final plan = selection.toActionPlan(kind: SourceControlActionKind.discard);
    final pendingConfirmation =
        SourceControlHunkDiscardConfirmationPlan.fromSelection(selection);
    final confirmed = SourceControlHunkDiscardConfirmationPlan.fromActionPlan(
      plan,
      confirmed: true,
    );

    expect(selection.selectedHunkIndexes, <int>[0, 1]);
    expect(selection.allSelected, isTrue);
    expect(selection.toJson()['selectedHunkCount'], 2);
    expect(plan.requiresConfirmation, isTrue);
    expect(plan.selectedPatch, contains('@@ -1,3 +1,4 @@'));
    expect(plan.selectedPatch, contains('@@ -10,2 +11,2 @@'));
    expect(pendingConfirmation.readyForDialog, isTrue);
    expect(pendingConfirmation.canRun, isFalse);
    expect(confirmed.canRun, isTrue);
    expect(confirmed.confirmLabel, 'Discard 2 hunk(s)');
    expect(confirmed.toJson()['requiresConfirmation'], isTrue);
  });

  test(
    'git partial patch provider executes selected hunk through stdin',
    () async {
      const snapshot = SourceControlDiffSnapshot(
        providerKind: SourceControlProviderKind.git,
        path: 'src/main.styio',
        unifiedDiff: _diff,
      );
      final plan = SourceControlDiffHunkActionPlan.fromDiff(
        snapshot: snapshot,
        kind: SourceControlActionKind.discard,
        selectedHunkIndexes: const <int>[1],
      );
      SourceControlCommandRequest? commandRequest;
      final provider = GitSourceControlPartialPatchProvider(
        commandRunner: (request) async {
          commandRequest = request;
          return const SourceControlCommandResult(exitCode: 0);
        },
      );

      final result = await provider.runHunkAction(
        workspaceRoot: '/workspace/vityo',
        plan: plan,
      );

      expect(result.applied, isTrue);
      expect(result.kind, SourceControlActionKind.discard);
      expect(result.selectedHunkIndexes, <int>[1]);
      expect(commandRequest?.executable, 'git');
      expect(commandRequest?.workingDirectory, '/workspace/vityo');
      expect(commandRequest?.arguments, <String>[
        'apply',
        '--reverse',
        '--whitespace=nowarn',
        '-',
      ]);
      expect(commandRequest?.standardInput, contains('@@ -10,2 +11,2 @@'));
      expect(commandRequest?.standardInput, isNot(contains('extra')));
      expect(result.toJson()['command'], 'git');
    },
  );

  testWidgets('source control surface emits hunk action selection plans', (
    tester,
  ) async {
    const snapshot = SourceControlDiffSnapshot(
      providerKind: SourceControlProviderKind.git,
      path: 'src/main.styio',
      unifiedDiff: _diff,
    );
    SourceControlDiffHunkActionPlan? selectedPlan;
    var discardConfirmed = false;
    final pendingDiscard =
        SourceControlHunkDiscardConfirmationPlan.fromActionPlan(
          SourceControlDiffHunkActionPlan.fromDiff(
            snapshot: snapshot,
            kind: SourceControlActionKind.discard,
            selectedHunkIndexes: const <int>[1],
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceControlSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 900,
            ),
            workspaceFileCount: 1,
            changedDocumentIds: const <String>['src/main.styio'],
            diffPreview: snapshot,
            lastHunkActionResult: const SourceControlPartialPatchResult(
              kind: SourceControlActionKind.discard,
              path: 'src/main.styio',
              selectedHunkIndexes: <int>[1],
              applied: true,
              message: 'Applied discard to 1 selected hunk(s).',
              command: 'git',
              arguments: <String>['apply', '--reverse', '-'],
              exitCode: 0,
            ),
            pendingHunkDiscardConfirmation: pendingDiscard,
            onSelectHunkAction: (plan) async {
              selectedPlan = plan;
            },
            onConfirmHunkDiscard: () async {
              discardConfirmed = true;
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('source-control-hunk-action-selection')),
      findsOneWidget,
    );
    expect(find.textContaining('hunk 1 · +2 -1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('source-control-hunk-action-result')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('source-control-hunk-discard-confirmation')),
      findsOneWidget,
    );
    expect(find.text('hunk action applied'), findsOneWidget);
    expect(find.text('Applied discard to 1 selected hunk(s).'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('source-control-hunk-discard-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('source-control-hunk-discard-1')),
    );
    await tester.pump();

    expect(selectedPlan?.kind, SourceControlActionKind.discard);
    expect(selectedPlan?.selectedHunkIndexes, <int>[1]);
    expect(selectedPlan?.canSelect, isTrue);

    await tester.ensureVisible(
      find.byKey(const ValueKey('source-control-review-hunk-discard')),
    );
    await tester.tap(
      find.byKey(const ValueKey('source-control-review-hunk-discard')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('source-control-hunk-discard-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('source-control-confirm-hunk-discard')),
    );
    await tester.pumpAndSettle();
    expect(discardConfirmed, isTrue);
  });
}
