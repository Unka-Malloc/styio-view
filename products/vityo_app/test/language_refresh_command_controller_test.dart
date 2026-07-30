import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/language_refresh_command_controller.dart';

void main() {
  test('missing refresh callback fails closed', () async {
    final logs = <String>[];
    final controller = LanguageRefreshCommandController(
      refreshAvailable: () => false,
      refresh: () async => throw StateError('must not run'),
      status: LanguageServiceStatusSurface.unavailable,
      log: logs.add,
    );

    final applied = await controller.execute();

    expect(applied, isFalse);
    expect(logs.single, contains('skipped'));
  });

  test('successful refresh logs current language facts', () async {
    var refreshCount = 0;
    final logs = <String>[];
    final controller = LanguageRefreshCommandController(
      refreshAvailable: () => true,
      refresh: () async => refreshCount += 1,
      status: () => const LanguageServiceStatusSurface(
        runtimeState: 'active',
        severity: LanguageServiceStatusSeverity.ready,
        title: 'ready',
        message: 'ready',
        usableCapabilityCount: 2,
        freshCapabilityCount: 1,
        primaryCapabilityStates: <String, String>{'diagnostics': 'available'},
        capabilities: <LanguageServiceCapabilityStatusItem>[],
        parserEngine: 'styio',
        grammarVersion: 'pinned',
      ),
      log: logs.add,
    );

    final applied = await controller.execute();

    expect(applied, isTrue);
    expect(refreshCount, 1);
    expect(logs.single, contains('usable=2'));
  });

  test('refresh exception is contained', () async {
    final logs = <String>[];
    final controller = LanguageRefreshCommandController(
      refreshAvailable: () => true,
      refresh: () async => throw StateError('offline'),
      status: LanguageServiceStatusSurface.unavailable,
      log: logs.add,
    );

    final applied = await controller.execute();

    expect(applied, isFalse);
    expect(logs.single, contains('offline'));
  });
}
