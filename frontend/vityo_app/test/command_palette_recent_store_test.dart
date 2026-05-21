import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('command palette recent store persists ranking input', () async {
    final store = CommandPaletteRecentCommandStore.fromDataStore(
      dataStore: await _createDataStore(),
    );

    await store.recordCommand(
      workspaceId: 'demo',
      commandId: AppCommandId.save,
      updatedAt: DateTime.utc(2026, 5, 20, 8),
    );
    await store.recordCommand(
      workspaceId: 'demo',
      commandId: AppCommandId.renameSymbol,
      updatedAt: DateTime.utc(2026, 5, 20, 9),
    );
    await store.recordCommand(
      workspaceId: 'demo',
      commandId: AppCommandId.save,
      updatedAt: DateTime.utc(2026, 5, 20, 10),
    );

    final history = await store.readHistory(workspaceId: 'demo');
    final entries = const CommandPaletteModel(
      commands: <AppCommandDescriptor>[
        AppCommandDescriptor(
          id: AppCommandId.renameSymbol,
          label: 'Rename Symbol',
          shortcutHint: 'Route',
          description: 'Rename symbol.',
        ),
        AppCommandDescriptor(
          id: AppCommandId.save,
          label: 'Save',
          shortcutHint: 'Cmd/Ctrl+S',
          description: 'Save file.',
        ),
      ],
    ).entriesFor(history.toQueryState());

    expect(history.commandIds, <AppCommandId>[
      AppCommandId.save,
      AppCommandId.renameSymbol,
    ]);
    expect(history.toJson()['count'], 2);
    expect(entries.first.command.id, AppCommandId.save);
    expect(entries.first.recentRank, 0);
    expect(await store.clearHistory(workspaceId: 'demo'), isTrue);
    expect((await store.readHistory(workspaceId: 'demo')).commandIds, isEmpty);
  });

  test('command palette preferences store persists display policy', () async {
    final store = CommandPaletteDisplayPreferencesStore.fromDataStore(
      dataStore: await _createDataStore(),
    );

    await store.savePreferences(
      const CommandPaletteDisplayPreferences(
        workspaceId: 'demo',
        defaultCategory: AppCommandCategory.navigation,
        showCategoryFilters: false,
        showRecentCommands: false,
      ).copyWith(updatedAt: DateTime.utc(2026, 5, 20, 11)),
    );

    final restored = await store.readPreferences(workspaceId: 'demo');
    final queryState = restored.toQueryState(
      query: 'search',
      recentCommandIds: const <AppCommandId>[AppCommandId.save],
    );

    expect(restored.defaultCategory, AppCommandCategory.navigation);
    expect(restored.showCategoryFilters, isFalse);
    expect(restored.showRecentCommands, isFalse);
    expect(restored.toJson()['defaultCategory'], 'navigation');
    expect(queryState.category, AppCommandCategory.navigation);
    expect(queryState.recentCommandIds, isEmpty);
    expect(await store.clearPreferences(workspaceId: 'demo'), isTrue);
    expect(
      (await store.readPreferences(workspaceId: 'demo')).showCategoryFilters,
      isTrue,
    );
  });

  test('command keybinding profile store persists overrides', () async {
    final store = CommandKeybindingProfileStore.fromDataStore(
      dataStore: await _createDataStore(),
    );
    final profile = CommandKeybindingProfile(
      workspaceId: 'demo',
      overrides: <AppCommandId, CommandKeybindingOverride>{
        AppCommandId.run: const CommandKeybindingOverride(
          commandId: AppCommandId.run,
          shortcuts: <AppCommandShortcutSpec>[
            AppCommandShortcutSpec('keyS', meta: true),
          ],
        ),
      },
      updatedAt: DateTime.utc(2026, 5, 20, 12),
    );

    await store.saveProfile(profile);

    final restored = await store.readProfile(workspaceId: 'demo');
    final run = StyioCommandRegistry.descriptorFor(AppCommandId.run);

    expect(restored.hasOverrideFor(AppCommandId.run), isTrue);
    expect(restored.effectiveShortcutsFor(run).single.key, 'keyS');
    expect(restored.effectiveShortcutsFor(run).single.meta, isTrue);
    expect(restored.toJson()['overrides'], hasLength(1));
    expect(await store.clearProfile(workspaceId: 'demo'), isTrue);
    expect((await store.readProfile(workspaceId: 'demo')).overrides, isEmpty);
  });

  test('command keybinding parser and conflict review classify overrides', () {
    final shortcut = parseCommandShortcutExpression('ctrl+shift+keyK');
    expect(shortcut, isNotNull);
    expect(shortcut!.control, isTrue);
    expect(shortcut.shift, isTrue);
    expect(shortcut.key, 'keyK');
    expect(commandShortcutSignature(shortcut), 'ctrl+shift+keyK');
    expect(commandShortcutDisplayLabel(shortcut), 'Ctrl+Shift+keyK');

    final profile = CommandKeybindingProfile(
      workspaceId: 'demo',
      overrides: <AppCommandId, CommandKeybindingOverride>{
        AppCommandId.save: const CommandKeybindingOverride(
          commandId: AppCommandId.save,
          shortcuts: <AppCommandShortcutSpec>[
            AppCommandShortcutSpec('keyK', control: true),
          ],
        ),
        AppCommandId.renameSymbol: const CommandKeybindingOverride(
          commandId: AppCommandId.renameSymbol,
          shortcuts: <AppCommandShortcutSpec>[
            AppCommandShortcutSpec('keyK', control: true),
          ],
        ),
      },
    );
    final review = CommandKeybindingResolver.reviewConflicts(
      profile: profile,
      descriptors: const <AppCommandDescriptor>[
        AppCommandDescriptor(
          id: AppCommandId.save,
          label: 'Save',
          shortcutHint: 'Cmd/Ctrl+S',
          description: 'Save file.',
        ),
        AppCommandDescriptor(
          id: AppCommandId.renameSymbol,
          label: 'Rename Symbol',
          shortcutHint: 'Route',
          description: 'Rename symbol.',
        ),
      ],
    );

    expect(review.hasConflicts, isTrue);
    expect(review.conflicts.single.signature, 'ctrl+keyK');
    expect(review.conflicts.single.commandIds, <AppCommandId>[
      AppCommandId.save,
      AppCommandId.renameSymbol,
    ]);
  });

  test('command shortcut capture policy blocks reserved shortcuts', () {
    const policy = CommandShortcutCapturePolicy();
    final browserPolicy = CommandShortcutCapturePolicy.forPlatform(
      PlatformTarget.web,
    );
    final macosPolicy = CommandShortcutCapturePolicy.forPlatform(
      PlatformTarget.macos,
    );

    final reserved = policy.evaluate(
      const AppCommandShortcutSpec('tab', control: true),
    );
    final browserRefresh = browserPolicy.evaluate(
      const AppCommandShortcutSpec('keyR', control: true),
    );
    final macosQuit = macosPolicy.evaluate(
      const AppCommandShortcutSpec('keyQ', meta: true),
    );
    final hinted = policy.evaluate(const AppCommandShortcutSpec('keyK'));
    final allowed = policy.evaluate(
      const AppCommandShortcutSpec('keyK', control: true, shift: true),
    );

    expect(reserved.allowed, isFalse);
    expect(reserved.decision, CommandShortcutCaptureDecision.reserved);
    expect(reserved.message, contains('reserved'));
    expect(browserRefresh.allowed, isFalse);
    expect(browserRefresh.message, contains('web-browser'));
    expect(macosQuit.allowed, isFalse);
    expect(macosQuit.message, contains('macos-desktop'));
    expect(hinted.allowed, isTrue);
    expect(hinted.decision, CommandShortcutCaptureDecision.needsModifierHint);
    expect(hinted.accessibilityHint, contains('text input'));
    expect(allowed.allowed, isTrue);
    expect(allowed.toJson()['decision'], 'allowed');
    expect(browserPolicy.hostPolicy.toJson()['kind'], 'web-browser');
  });
}

Future<FoundationDataStore> _createDataStore() async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'vityo_command_palette_recent_test_',
  );
  addTearDown(() => tempRoot.delete(recursive: true));
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: tempRoot.path,
      homePath: tempRoot.path,
    ),
  );
  return FoundationDataStore(
    resourceCoordinator: FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    ),
    fileSystemManager: fileSystemManager,
  );
}
