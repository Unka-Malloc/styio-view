import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/hosted_control_plane.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/backend_toolchain/pafio_cli_support.dart';
import 'package:vityo_app/src/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

import 'fake_pafio_cli.dart';

void main() {
  setUp(() {
    debugOverrideHostedEnvironment(const <String, String>{});
  });

  tearDown(() {
    debugOverrideHostedEnvironment(null);
  });

  test('project graph exposes source confidence for every standard field', () {
    final scratch = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/scratch',
      activeFilePath: '/workspace/scratch/main.styio',
      title: 'Scratch',
      notes: const <String>[],
    );

    expect(
      scratch.fieldSourceConfidence.keys,
      containsAll(ProjectGraphSnapshot.sourceConfidenceFieldNames),
    );
    expect(
      scratch.sourceConfidenceFor('manifestPath'),
      ProjectGraphFieldSourceConfidence.capabilityGap,
    );
    expect(
      scratch.sourceConfidenceFor('editorFiles'),
      ProjectGraphFieldSourceConfidence.inferred,
    );
    expect(
      scratch.fieldSourceConfidenceWireValues['manifestPath'],
      'capability-gap',
    );

    final graph = _projectGraphFor('/workspace/project');
    expect(
      graph.sourceConfidenceFor('packages'),
      ProjectGraphFieldSourceConfidence.machinePayload,
    );
  });

  test(
    'toolchain management adapter executes published pafio tool use',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_toolchain_manager_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '[package]\nname = "demo/app"\nversion = "0.1.0"\n',
        );
      await writeFakePafioCli(
        workspaceRoot: tempRoot,
        pythonSource: '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['--json', 'tool', 'use', '--version', '0.0.5', '--channel', 'stable']:
    print(json.dumps({
        'command': 'tool use',
        'message': 'activated managed styio compiler: /workspace/.pafio/tools/styio/current/bin/styio',
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
      expect(result.schemaVersion, ToolchainCommandResult.currentSchemaVersion);
      expect(result.toJson()['schemaVersion'], 1);
      expect(result.toJson()['status'], 'succeeded');
      expect(result.command, 'tool use');
      expect(result.payload?['compiler_version'], '0.0.5');
      expect(
        result.statusMessage,
        contains('activated managed styio compiler'),
      );
    },
  );

  test('pafio cli support parses payloads and process failures', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_pafio_support_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final scratch = ProjectGraphSnapshot.scratch(
      workspaceRoot: tempRoot.path,
      activeFilePath: '${tempRoot.path}${Platform.pathSeparator}main.styio',
      title: 'Scratch',
      notes: const <String>[],
    );
    final graph = _projectGraphFor(tempRoot.path);

    expect(pafioManifestArgs(scratch), isEmpty);
    expect(pafioManifestArgs(graph), <String>[
      '--manifest-path',
      graph.manifestPath!,
    ]);
    expect(parseJsonObjectPayload(''), isNull);
    expect(parseJsonObjectPayload('plain text'), isNull);
    expect(parseJsonObjectPayload('{broken'), isNull);
    expect(parseJsonObjectPayload('[1]'), isNull);
    expect(parseJsonObjectPayload('{"message":"ok"}')?['message'], 'ok');

    final pafioBinary = File(
      '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
    );
    pafioBinary.createSync(recursive: true);
    pafioBinary.writeAsStringSync('not executable');

    final result = await runLocalPafioCommand<_PafioTestResult>(
      projectGraph: graph,
      command: 'tool use',
      args: const <String>['--json', 'tool', 'use'],
      factory: _pafioTestResult,
    );

    expect(result.outcome, LocalPafioCommandOutcome.failed);
    expect(result.statusMessage, contains('Failed to execute pafio'));
    expect(result.stdout, isEmpty);
    expect(result.stderr, isEmpty);
  });

  test('toolchain management adapter covers local command outcomes', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_lifecycle_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('[package]\nname = "demo/app"\nversion = "0.1.0"\n');
    await writeFakePafioCli(
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
    expect(clearBlocked.statusMessage, contains('requires a resolved pafio'));

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
    expect(result.statusMessage, contains('requires a resolved pafio manifest'));
  });
}

class _PafioTestResult {
  const _PafioTestResult({
    required this.outcome,
    required this.command,
    required this.statusMessage,
    required this.stdout,
    required this.stderr,
    this.payload,
    this.errorPayload,
  });

  final LocalPafioCommandOutcome outcome;
  final String command;
  final String statusMessage;
  final String stdout;
  final String stderr;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? errorPayload;
}

_PafioTestResult _pafioTestResult({
  required LocalPafioCommandOutcome outcome,
  required String command,
  required String statusMessage,
  required String stdout,
  required String stderr,
  Map<String, dynamic>? payload,
  Map<String, dynamic>? errorPayload,
}) {
  return _PafioTestResult(
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
  final manifestPath = '$workspaceRoot${Platform.pathSeparator}pafio.toml';
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
