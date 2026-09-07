import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/local_service/vityod_lsp_gateway.dart';

import '../support/vityod_test_harness.dart';

void main() {
  test('LSP byte process is owned by vityod', () async {
    final executable = File('/bin/cat');
    if (!await executable.exists()) return;
    final harness = await VityodTestHarness.start(clientId: 'lsp-test');
    addTearDown(harness.close);
    final session = await VityodLspGateway(client: harness.client).start(
      executable: executable.path,
      workingDirectory: Directory.systemTemp.path,
    );

    await session.write(const <int>[1, 2, 3, 4]);
    VityodLspPoll? output;
    for (var attempt = 0; attempt < 100; attempt += 1) {
      final polled = await session.poll();
      if (polled.stdout.isNotEmpty) {
        output = polled;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(output?.stdout, const <int>[1, 2, 3, 4]);
    expect(output?.overflowed, isFalse);
    await session.stop();
  });
}
