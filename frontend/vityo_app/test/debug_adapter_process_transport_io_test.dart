import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_process_transport_io.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_protocol.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_session.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_transport.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';

void main() {
  test(
    'DAP process transport connects process stdout and stdin bytes',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_dap_process_transport_',
      );
      addTearDown(() => _deleteDirectoryWithRetry(tempRoot));
      final capture = File('${tempRoot.path}/stdin.bin');
      final adapterScript = File('${tempRoot.path}/fake_dap_adapter.dart');
      await adapterScript.writeAsString(r'''
import 'dart:convert';
import 'dart:io';

void main() async {
  final capturePath = Platform.environment['DAP_CAPTURE_PATH'];
  final body = jsonEncode(<String, Object?>{
    'type': 'event',
    'event': 'stopped',
    'body': <String, Object?>{'reason': 'entry', 'threadId': 1},
  });
  final bodyBytes = utf8.encode(body);
  stdout.add(ascii.encode('Content-Length: ${bodyBytes.length}\r\n\r\n'));
  stdout.add(bodyBytes);
  await stdout.flush();
  stdin.listen((chunk) {
    if (capturePath != null) {
      File(capturePath).writeAsBytesSync(chunk, mode: FileMode.append);
    }
  });
}
''');

      final transport = DapProcessTransport(
        executable: _dartExecutablePath(),
        arguments: <String>[adapterScript.path],
        environment: <String, String>{'DAP_CAPTURE_PATH': capture.path},
      );
      await transport.start();
      final bridge = DapSessionTransportBridge(transport: transport);
      bridge.attach();
      await _pumpUntil(() => bridge.snapshot.status == DapSessionStatus.paused);

      await bridge.sendRequest(const DapRequest(seq: 1, command: 'threads'));
      await _pumpUntil(() => capture.existsSync() && capture.lengthSync() > 0);

      const codec = DapContentFrameCodec();
      final captured = codec.decodeFirst(await capture.readAsBytes());

      expect(transport.started, isTrue);
      expect(bridge.snapshot.status, DapSessionStatus.paused);
      expect(bridge.snapshot.events.single.event, 'stopped');
      expect(captured?.message['command'], 'threads');
      await bridge.close();
    },
  );

  test('startDapProcessTransport passes launch debugger arguments', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_dap_process_args_',
    );
    addTearDown(() => _deleteDirectoryWithRetry(tempRoot));
    final capture = File('${tempRoot.path}/args.txt');
    final program = File('${tempRoot.path}/demo')..writeAsStringSync('');
    final adapterScript = File('${tempRoot.path}/capture_args_adapter.dart');
    await adapterScript.writeAsString(r'''
import 'dart:io';

void main(List<String> args) {
  final capturePath = Platform.environment['DAP_ARG_CAPTURE_PATH'];
  if (capturePath != null) {
    File(capturePath).writeAsStringSync(args.join('\n'));
  }
  stdin.listen((_) {});
}
''');

    final transport = await startDapProcessTransport(
      DebugLaunchConfiguration(
        readiness: DebugLaunchReadiness.ready,
        reason: 'ready',
        debuggerId: 'dart-fake-adapter',
        debuggerLabel: 'Dart Fake Adapter',
        debuggerExecutablePath: _dartExecutablePath(),
        debuggerArguments: <String>[adapterScript.path, '--adapter-mode'],
        adapterProtocol: 'dap',
        programPath: program.path,
        cwd: tempRoot.path,
        environment: <String, String>{'DAP_ARG_CAPTURE_PATH': capture.path},
      ),
    );

    try {
      await _pumpUntil(() => capture.existsSync() && capture.lengthSync() > 0);

      expect(await capture.readAsLines(), <String>['--adapter-mode']);
    } finally {
      await transport.close();
    }
  });
}

Future<void> _pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

String _dartExecutablePath() {
  final resolved = File(Platform.resolvedExecutable);
  for (final candidate in _dartExecutableCandidatesFor(resolved)) {
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }
  final pathEntries = (Platform.environment['PATH'] ?? '')
      .split(';')
      .where((entry) => entry.trim().isNotEmpty);
  for (final entry in pathEntries) {
    for (final candidate in _dartExecutableCandidatesFor(
      File([entry, 'dart'].join(Platform.pathSeparator)),
    )) {
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
  }
  return resolved.path;
}

List<File> _dartExecutableCandidatesFor(File resolved) {
  final resolvedName = resolved.path.split(RegExp(r'[\\/]')).last.toLowerCase();
  final dartExecutableName = Platform.isWindows ? 'dart.exe' : 'dart';
  final separator = Platform.pathSeparator;
  return <File>[
    if (resolvedName == dartExecutableName) resolved,
    if (Platform.isWindows) File('${resolved.path}.exe'),
    File([resolved.parent.path, dartExecutableName].join(separator)),
    File(
      [
        resolved.parent.path,
        'cache',
        'dart-sdk',
        'bin',
        dartExecutableName,
      ].join(separator),
    ),
    File(
      [
        resolved.parent.parent.parent.parent.path,
        'dart-sdk',
        'bin',
        dartExecutableName,
      ].join(separator),
    ),
  ];
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 6; attempt += 1) {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return;
    } on FileSystemException {
      if (attempt == 5) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 50 * (attempt + 1)));
    }
  }
}
