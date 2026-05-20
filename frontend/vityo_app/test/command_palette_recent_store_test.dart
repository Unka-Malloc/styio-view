import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
