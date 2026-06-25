import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/hosted_control_plane.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/backend_toolchain/spio_cli_support.dart';
import 'package:vityo_app/src/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

import 'fake_spio_cli.dart';

void main() {
  setUp(() {
    debugOverrideHostedEnvironment(const <String, String>{});
  });

  tearDown(() {
    debugOverrideHostedEnvironment(null);
  });

  test('toolchain management adapter executes published spio tool use', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_manager_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('[package]\nname = "demo/app"\nversion = "0.1.0"\n');
    await writeFakeSpioCli(
      workspaceRoot: tempRoot,
      pythonSource: '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['--json', 'tool', 'use', '--version', '0.0.5', '--channel', 'stable']:
    print(json.dumps({
        'command': 'tool use',
        'message': 'activated managed styio compiler: /workspace/.spio/tools/styio/current/bin/styio',
        'compiler_version': '0.0.5',
        'channel': 'stable',
    }))
    raise SystemExit(0)

raise SystemExit(64)
''',
    );

    final adapter = await createToolchainManagementAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final result = await adapter.useManagedCompiler(
      projectGraph: _projectGraphFor(tempRoot.path),
      compilerVersion: '0.0.5',
      channel: 'stable',
    );

    expect(result.succeeded, isTrue);
    expect(result.command, 'tool use');
    expect(result.payload?['compiler_version'], '0.0.5');
    expect(result.statusMessage, contains('activated managed styio compiler'));
  });

  test('spio cli support parses payloads and process failures', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_spio_support_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final scratch = ProjectGraphSnapshot.scratch(
      workspaceRoot: tempRoot.path,
      activeFilePath: '${tempRoot.path}${Platform.pathSeparator}main.styio',
      title: 'Scratch',
      notes: const <String>[],
    );
    final graph = _projectGraphFor(tempRoot.path);

    expect(spioManifestArgs(scratch), isEmpty);
    expect(spioManifestArgs(graph), <String>[
      '--manifest-path',
      graph.manifestPath!,
    ]);
    expect(parseJsonObjectPayload(''), isNull);
    expect(parseJsonObjectPayload('plain text'), isNull);
    expect(parseJsonObjectPayload('{broken'), isNull);
    expect(parseJsonObjectPayload('[1]'), isNull);
    expect(parseJsonObjectPayload('{"message":"ok"}')?['message'], 'ok');

    final spioBinary = File(
      '${tempRoot.path}${Platform.pathSeparator}.spio${Platform.pathSeparator}bin${Platform.pathSeparator}spio',
    );
    spioBinary.createSync(recursive: true);
    spioBinary.writeAsStringSync('not executable');

    final result = await runLocalSpioCommand<_SpioTestResult>(
      projectGraph: graph,
      command: 'tool use',
      args: const <String>['--json', 'tool', 'use'],
      factory: _spioTestResult,
    );

    expect(result.outcome, LocalSpioCommandOutcome.failed);
    expect(result.statusMessage, contains('Failed to execute spio'));
    expect(result.stdout, isEmpty);
    expect(result.stderr, isEmpty);
  });

  test('toolchain management adapter covers local command outcomes', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_lifecycle_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('[package]\nname = "demo/app"\nversion = "0.1.0"\n');
    await writeFakeSpioCli(
      workspaceRoot: tempRoot,
      pythonSource: '''#!/usr/bin/env python3
import json, sys

args = sys.argv[1:]

if args[:3] == ['--json', 'tool', 'install'] and '--styio-bin' in args:
    print(json.dumps({
        'message': 'installed managed compiler',
        'styio_bin': args[args.index('--styio-bin') + 1],
    }))
    raise SystemExit(0)

if args[:3] == ['--json', 'tool', 'use'] and '--version' in args:
    print(json.dumps({
        'message': 'activated managed compiler',
        'compiler_version': args[args.index('--version') + 1],
        'channel': args[args.index('--channel') + 1] if '--channel' in args else 'none',
    }))
    raise SystemExit(0)

if args[:3] == ['--json', 'tool', 'pin'] and '--clear' in args:
    print(json.dumps({'message': 'cleared project pin'}))
    raise SystemExit(0)

if args[:3] == ['--json', 'tool', 'pin']:
    print(json.dumps({'message': 'pin failed', 'code': 'bad-pin'}), file=sys.stderr)
    raise SystemExit(2)

print('unsupported invocation', file=sys.stderr)
raise SystemExit(64)
''',
    );

    final graph = _projectGraphFor(tempRoot.path);
    final adapter = await createToolchainManagementAdapter(
      platformTarget: PlatformTarget.macos,
    );

    final installResult = await adapter.installManagedCompiler(
      projectGraph: graph,
      styioBinaryPath: '/opt/styio/bin/styio',
    );
    expect(installResult.succeeded, isTrue);
    expect(installResult.payload?['styio_bin'], '/opt/styio/bin/styio');

    final useResult = await adapter.useManagedCompiler(
      projectGraph: graph,
      compilerVersion: '0.0.6',
      channel: '',
    );
    expect(useResult.succeeded, isTrue);
    expect(useResult.payload?['channel'], 'none');

    final pinResult = await adapter.pinManagedCompiler(
      projectGraph: graph,
      compilerVersion: '0.0.7',
    );
    expect(pinResult.status, ToolchainCommandStatus.failed);
    expect(pinResult.errorPayload?['code'], 'bad-pin');

    final clearResult = await adapter.clearPinnedCompiler(projectGraph: graph);
    expect(clearResult.succeeded, isTrue);
    expect(clearResult.statusMessage, 'cleared project pin');

    final scratch = ProjectGraphSnapshot.scratch(
      workspaceRoot: tempRoot.path,
      activeFilePath: '${tempRoot.path}${Platform.pathSeparator}main.styio',
      title: 'Scratch',
      notes: const <String>[],
    );
    final clearBlocked = await adapter.clearPinnedCompiler(
      projectGraph: scratch,
    );
    expect(clearBlocked.status, ToolchainCommandStatus.blocked);
    expect(clearBlocked.statusMessage, contains('requires a resolved spio'));

    final webAdapter = await createToolchainManagementAdapter(
      platformTarget: PlatformTarget.web,
    );
    final webBlocked = await webAdapter.installManagedCompiler(
      projectGraph: graph,
      styioBinaryPath: '/opt/styio/bin/styio',
    );
    expect(webBlocked.status, ToolchainCommandStatus.blocked);
    expect(webBlocked.statusMessage, contains('Web'));
  });

  test('toolchain pin blocks when no manifest is resolved', () async {
    final adapter = await createToolchainManagementAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final result = await adapter.pinManagedCompiler(
      projectGraph: ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/scratch',
        activeFilePath: '/workspace/scratch/main.styio',
        title: 'Scratch',
        notes: const <String>[],
      ),
      compilerVersion: '0.0.5',
      channel: 'stable',
    );

    expect(result.status, ToolchainCommandStatus.blocked);
    expect(result.statusMessage, contains('requires a resolved spio manifest'));
  });
}

class _SpioTestResult {
  const _SpioTestResult({
    required this.outcome,
    required this.command,
    required this.statusMessage,
    required this.stdout,
    required this.stderr,
    this.payload,
    this.errorPayload,
  });

  final LocalSpioCommandOutcome outcome;
  final String command;
  final String statusMessage;
  final String stdout;
  final String stderr;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? errorPayload;
}

_SpioTestResult _spioTestResult({
  required LocalSpioCommandOutcome outcome,
  required String command,
  required String statusMessage,
  required String stdout,
  required String stderr,
  Map<String, dynamic>? payload,
  Map<String, dynamic>? errorPayload,
}) {
  return _SpioTestResult(
    outcome: outcome,
    command: command,
    statusMessage: statusMessage,
    stdout: stdout,
    stderr: stderr,
    payload: payload,
    errorPayload: errorPayload,
  );
}

ProjectGraphSnapshot _projectGraphFor(String workspaceRoot) {
  final manifestPath = '$workspaceRoot${Platform.pathSeparator}spio.toml';
  return ProjectGraphSnapshot(
    id: manifestPath,
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: workspaceRoot,
    workspaceMembers: const <String>[],
    manifestPath: manifestPath,
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: <String>[
      '$workspaceRoot${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
    ],
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.unavailable,
      detail: 'No toolchain resolved for this test fixture.',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.missing,
    notes: const <String>[],
  );
}
