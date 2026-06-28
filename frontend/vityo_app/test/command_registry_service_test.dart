import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/workbench/workbench.dart';
import 'package:vityo_app/src/view_render/commands/commands.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  test(
    'command registry contribution exposes metadata and enablement gates',
    () {
      const descriptor = AppCommandDescriptor(
        id: AppCommandId.run,
        label: 'Run Active Target',
        shortcutHint: 'Ctrl+Enter',
        description: 'Run the active target through the managed toolchain.',
        shortcuts: <AppCommandShortcutSpec>[
          AppCommandShortcutSpec('enter', control: true),
        ],
        enablement: <ContextKeyExpression>[
          ContextKeyExpression.equals(
            key: 'workbench.hasActiveEditor',
            value: true,
          ),
          ContextKeyExpression.equals(
            key: 'editor.activeLanguageId',
            value: 'styio',
          ),
          ContextKeyExpression.equals(
            key: 'workspace.isTrusted',
            value: true,
          ),
          ContextKeyExpression.equals(
            key: 'workspace.indexReady',
            value: true,
          ),
        ],
        permissionRequirement:
            AppCommandPermissionRequirement.toolchainManaged,
      );
      final registry = IdeCommandRegistry(descriptors: const [descriptor]);
      final contextKeys = ContextKeyService()
        ..setActiveEditor(
          editorId: 'src/main.styio',
          languageId: 'styio',
          hasSelection: true,
        )
        ..setWorkspaceTrust(true)
        ..setWorkspaceIndexReady(true);

      expect(
        registry.descriptorFor(AppCommandId.run).enabledIn(contextKeys),
        isTrue,
      );

      contextKeys.setWorkspaceIndexReady(false);

      expect(
        registry.descriptorFor(AppCommandId.run).enabledIn(contextKeys),
        isFalse,
      );

      final json = descriptor.toContributionJson();
      final telemetry =
          json['telemetryClassification']! as Map<String, Object?>;
      final keybindings = json['keybindings']! as List<Object?>;
      final enablement = json['enablement']! as List<Object?>;

      expect(json['id'], 'run');
      expect(json['title'], 'Run Active Target');
      expect(json['category'], 'execution');
      expect(json['permissionRequirement'], 'toolchain-managed');
      expect(keybindings.single, <String, Object?>{
        'key': 'enter',
        'control': true,
        'meta': false,
        'alt': false,
        'shift': false,
      });
      expect(enablement, hasLength(4));
      expect(
        enablement,
        contains(
          equals(<String, Object?>{
            'operator': 'equals',
            'key': 'workspace.indexReady',
            'value': true,
          }),
        ),
      );
      expect(telemetry['sideEffect'], 'toolchain-execution');
      expect(telemetry['targetSurface'], 'bottom-panel');
      expect(telemetry['permissionRequirement'], 'toolchain-managed');
    },
  );

  test('context key service tracks workbench readiness facts', () {
    final contextKeys = ContextKeyService();

    expect(contextKeys.valueFor(WorkbenchContextKeys.hasActiveEditor), isFalse);
    expect(contextKeys.valueFor(WorkbenchContextKeys.activeLanguageId), '');
    expect(
      contextKeys.valueFor(WorkbenchContextKeys.workspaceTrusted),
      isFalse,
    );
    expect(
      contextKeys.valueFor(WorkbenchContextKeys.workspaceIndexReady),
      isFalse,
    );

    contextKeys
      ..setActiveEditor(
        editorId: 'src/main.styio',
        languageId: 'styio',
        hasSelection: true,
      )
      ..setWorkspaceTrust(true)
      ..setWorkspaceIndexReady(true);

    expect(contextKeys.valueFor(WorkbenchContextKeys.hasActiveEditor), isTrue);
    expect(
      contextKeys.valueFor(WorkbenchContextKeys.activeEditorId),
      'src/main.styio',
    );
    expect(contextKeys.valueFor(WorkbenchContextKeys.activeLanguageId), 'styio');
    expect(contextKeys.valueFor(WorkbenchContextKeys.workspaceTrusted), isTrue);
    expect(
      contextKeys.valueFor(WorkbenchContextKeys.editorHasSelection),
      isTrue,
    );
    expect(
      contextKeys.valueFor(WorkbenchContextKeys.workspaceIndexReady),
      isTrue,
    );
    expect(
      contextKeys.snapshot(),
      containsPair('workbench.activeEditorId', 'src/main.styio'),
    );

    contextKeys.clearActiveEditor();

    expect(contextKeys.valueFor(WorkbenchContextKeys.hasActiveEditor), isFalse);
    expect(contextKeys.valueFor(WorkbenchContextKeys.activeEditorId), '');
    expect(contextKeys.valueFor(WorkbenchContextKeys.activeLanguageId), '');
    expect(
      contextKeys.valueFor(WorkbenchContextKeys.editorHasSelection),
      isFalse,
    );
  });

  test('keybinding overrides round-trip and retain conflict metadata', () {
    final parsed = parseCommandShortcutExpression('alt+arrowLeft');
    expect(parsed, isNotNull);
    expect(commandShortcutSignature(parsed!), 'alt+arrowLeft');
    expect(commandShortcutDisplayLabel(parsed), 'Alt+arrowLeft');

    final profile = CommandKeybindingProfile(workspaceId: 'demo')
        .replaceOverride(
          const CommandKeybindingOverride(
            commandId: AppCommandId.save,
            shortcuts: <AppCommandShortcutSpec>[
              AppCommandShortcutSpec('arrowLeft', alt: true),
            ],
          ),
          updatedAt: DateTime.utc(2026, 6, 25, 1),
        )
        .replaceOverride(
          const CommandKeybindingOverride(
            commandId: AppCommandId.renameSymbol,
            shortcuts: <AppCommandShortcutSpec>[
              AppCommandShortcutSpec('arrowLeft', alt: true),
            ],
          ),
          updatedAt: DateTime.utc(2026, 6, 25, 2),
        );
    final restored = CommandKeybindingProfile.fromJson(profile.toJson());
    const descriptors = <AppCommandDescriptor>[
      AppCommandDescriptor(
        id: AppCommandId.save,
        label: 'Save',
        shortcutHint: 'Cmd/Ctrl+S',
        description: 'Persist the active document.',
      ),
      AppCommandDescriptor(
        id: AppCommandId.renameSymbol,
        label: 'Rename Symbol',
        shortcutHint: 'Route',
        description: 'Rename the selected symbol.',
      ),
    ];
    final review = CommandKeybindingResolver.reviewConflicts(
      profile: restored,
      descriptors: descriptors,
    );
    final effectiveSaveShortcut =
        CommandKeybindingResolver.effectiveShortcutsFor(
      descriptor: descriptors.first,
      profile: restored,
    ).single;
    final exported = restored.toJson();
    final overrides = exported['overrides']! as List<Object?>;
    final firstShortcut =
        (overrides.first! as Map<String, Object?>)['shortcuts']!
            as List<Object?>;

    expect(restored.workspaceId, 'demo');
    expect(restored.hasOverrideFor(AppCommandId.save), isTrue);
    expect(effectiveSaveShortcut.alt, isTrue);
    expect(review.hasConflicts, isTrue);
    expect(review.conflicts.single.signature, 'alt+arrowLeft');
    expect(review.conflicts.single.shortcutLabel, 'Alt+arrowLeft');
    expect(review.conflicts.single.commandIds, <AppCommandId>[
      AppCommandId.save,
      AppCommandId.renameSymbol,
    ]);
    expect(
      review.conflicts.single.commandPreviews.map(
        (preview) => preview.sourceLabel,
      ),
      <String>['override', 'override'],
    );
    expect(firstShortcut.single, containsPair('alt', true));
  });

  testWidgets('command palette surface only dispatches command ids', (
    tester,
  ) async {
    final registry = IdeCommandRegistry(
      descriptors: const <AppCommandDescriptor>[
        AppCommandDescriptor(
          id: AppCommandId.save,
          label: 'Save',
          shortcutHint: 'Cmd/Ctrl+S',
          description: 'Persist the active document.',
        ),
      ],
    );
    AppCommandId? dispatchedCommandId;
    var dispatchCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPaletteSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            commands: registry.commands,
            onExecuteCommand: (commandId) async {
              dispatchedCommandId = commandId;
              dispatchCount += 1;
            },
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('command-palette-query-input')),
      'save',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(dispatchedCommandId, AppCommandId.save);
    expect(dispatchCount, 1);
    expect(registry.contains(AppCommandId.save), isTrue);
    expect(registry.commands.single.label, 'Save');
  });
}
