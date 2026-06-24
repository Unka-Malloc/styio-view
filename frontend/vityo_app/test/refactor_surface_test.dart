import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_event_bridge.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/refactor/refactor.dart';

void main() {
  testWidgets('refactor surface renders commands and semantic safety events', (
    tester,
  ) async {
    AppCommandId? executedCommandId;
    final viewModel = SemanticSnapshotPanelViewModel.fromState(
      SemanticSnapshotPanelEventState.empty(
        SemanticSnapshotPanelEventTarget.refactor,
      ).record(
        SemanticSnapshotPanelEvent(
          target: SemanticSnapshotPanelEventTarget.refactor,
          kind: SemanticSnapshotTelemetryEventKind.renameSafety,
          documentId: 'src/main.styio',
          message: 'Rename may conflict.',
          payload: const <String, Object?>{
            'safe': false,
            'newName': 'nextName',
          },
          timestamp: DateTime.utc(2026, 5, 20, 16),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RefactorSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            semanticSnapshotPanelViewModel: viewModel,
            refactorCommands: const <AppCommandDescriptor>[
              AppCommandDescriptor(
                id: AppCommandId.renameSymbol,
                label: 'Rename Symbol',
                shortcutHint: 'F2',
                description: 'Rename the selected symbol.',
                requiresInput: true,
                inputLabel: 'New symbol name',
              ),
              AppCommandDescriptor(
                id: AppCommandId.safeDelete,
                label: 'Safe Delete',
                shortcutHint: 'Route',
                description: 'Delete only when references are safe.',
              ),
            ],
            onExecuteCommand: (commandId) async {
              executedCommandId = commandId;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('refactor-surface')), findsOneWidget);
    expect(find.text('Refactor'), findsOneWidget);
    expect(find.text('commands 2'), findsOneWidget);
    expect(find.text('events 1'), findsOneWidget);
    expect(find.text('rename-safety 1'), findsWidgets);
    expect(find.text('Rename Symbol'), findsOneWidget);
    expect(find.text('input New symbol name'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('refactor-semantic-snapshot-panel')),
      findsOneWidget,
    );
    expect(find.text('Semantic Refactor'), findsOneWidget);
    expect(find.text('Rename to nextName'), findsOneWidget);
    expect(
      find.textContaining('src/main.styio · rename-safety'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('refactor-command-safeDelete')));
    await tester.pump();

    expect(executedCommandId, AppCommandId.safeDelete);
  });
}
