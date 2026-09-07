import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/hosted_control_plane.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/pafio_cli_discovery.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/runtime_event_adapter.dart';
import 'package:vityo_app/src/view_ide/language/language_contract.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'backend_provider_test_support.dart';

void main() {
  setUpAll(startBackendProviderTestServices);
  tearDownAll(stopBackendProviderTestServices);

  test('execution receipt decoder fails closed on unknown schema', () {
    expect(
      ExecutionReceiptSnapshot.decode(const <String, Object?>{
        'schema_version': 2,
        'intent': 'run',
        'executed': true,
      }, fallbackSessionId: 'session'),
      isNull,
    );
  });

  test(
    'execution adapter prefers published pafio workflow payloads and preserves JSON program output',
    () async {
      final tempRoot = await _createTempRoot('vityo_execution_payload_test_');
      final sourceFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('>_("demo")\n');

      File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[build]
implicit-std = true

[[bin]]
name = "demo"
path = "src/main.styio"
''');

      await _writePafioExecutable(
        File(
          '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
        ),
        '''#!/usr/bin/env python3
import json, os, sys

def write_runtime(session, events, command='run'):
    build = os.path.join(os.getcwd(), '.pafio', 'build', session)
    os.makedirs(build, exist_ok=True)
    events_path = os.path.join(build, 'runtime-events.jsonl')
    with open(events_path, 'w', encoding='utf-8') as fh:
        for event in events:
            fh.write(json.dumps(event) + '\\n')
    with open(os.path.join(build, 'receipt.json'), 'w', encoding='utf-8') as fh:
        json.dump({
            'schema_version': 1,
            'intent': command,
            'session_id': session,
            'executed': True,
            'outputs': {'runtime_events_path': events_path},
        }, fh)
    return build

def cap():
    return {
        'contract': 'styio.observable.runtime-events',
        'schema_version': 2,
        'record_kind': 'session.capability',
        'event_kind': 'session.capability',
        'mode': 'detailed',
        'snapshot_schema': 1,
        'snapshot_id': 's1_0123456789abcdef0123456789abcdef',
        'execution_id': 'x2_0000000000000001',
        'privacy_profile': 'strict',
        'producer_lanes': 1,
        'lane_capacity': 256,
        'priority_reserved': 32,
        'drain_batch': 64,
        'sampling': {'numerator': 1, 'denominator': 16, 'seed': 0},
        'clock_unit': 'ns',
        'supported_capabilities': ['task-lifecycle', 'loss-accounting', 'strict-privacy'],
        'active_capabilities': ['task-lifecycle', 'loss-accounting', 'strict-privacy'],
        'unavailable_capabilities': [],
    }

def ev(kind, eid, ns=0, **extra):
    row = {
        'contract': 'styio.observable.runtime-events',
        'schema_version': 2,
        'record_kind': 'event',
        'event_kind': kind,
        'family': 'session',
        'priority': 'lifecycle',
        'correlation_status': 'runtime_only',
        'role': 'runtime_only',
        'snapshot_id': None,
        'site_id': None,
        'instance_id': None,
        'event_id': eid,
        'monotonic_ns': ns,
        'causes': [],
        'wait': None,
    }
    row.update(extra)
    return row

if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)

if '--json' in sys.argv and 'run' in sys.argv:
    if '--package' not in sys.argv or sys.argv[sys.argv.index('--package') + 1] != 'demo/app':
        raise SystemExit(65)
    if '--bin' not in sys.argv or sys.argv[sys.argv.index('--bin') + 1] != 'demo':
        raise SystemExit(66)
    build = write_runtime('runtime-session-1', [
        cap(),
        ev('compile.started', 'r2_0000000000000001', 0, intent='run'),
        ev('run.finished', 'r2_0000000000000002', 1000, success=True),
    ])
    print(json.dumps({
        'command': 'run',
        'mode': 'execute',
        'workflow_payload_version': 1,
        'message': 'completed compiler run via payload',
        'stdout': '{"message":"user-log"}\\n{"a":1}\\npafio-run-ok\\n',
        'stderr': '',
        'diagnostics': [],
        'runtime_session_id': 'runtime-session-1',
        'plan': {'build_root': build},
        'receipt': {
            'schema_version': 1,
            'intent': 'run',
            'session_id': 'runtime-session-1',
            'executed': True,
        },
    }))
    raise SystemExit(0)

raise SystemExit(64)
''',
      );

      final adapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.macos,
        projectGraph: _projectGraph(
          workspaceRoot: tempRoot.path,
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
          targets: <ProjectTargetDescriptor>[
            ProjectTargetDescriptor(
              id: 'demo/app:bin:demo',
              packageName: 'demo/app',
              kind: ProjectTargetKind.bin,
              name: 'demo',
              filePath: sourceFile.path,
            ),
          ],
          packages: <ProjectPackageSnapshot>[
            _packageSnapshot(
              packageName: 'demo/app',
              rootPath: tempRoot.path,
              manifestPath:
                  '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
              targets: <ProjectTargetDescriptor>[
                ProjectTargetDescriptor(
                  id: 'demo/app:bin:demo',
                  packageName: 'demo/app',
                  kind: ProjectTargetKind.bin,
                  name: 'demo',
                  filePath: sourceFile.path,
                ),
              ],
            ),
          ],
          activeCompiler: _compilerSnapshot('/toolchains/styio/bin/styio'),
        ),
      );

      addTearDown(() => clearRuntimeEventsForSession('runtime-session-1'));
      final session = await adapter.runActiveDocument(
        platformTarget: PlatformTarget.macos,
        projectGraph: _projectGraph(
          workspaceRoot: tempRoot.path,
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
          targets: <ProjectTargetDescriptor>[
            ProjectTargetDescriptor(
              id: 'demo/app:bin:demo',
              packageName: 'demo/app',
              kind: ProjectTargetKind.bin,
              name: 'demo',
              filePath: sourceFile.path,
            ),
          ],
          packages: <ProjectPackageSnapshot>[
            _packageSnapshot(
              packageName: 'demo/app',
              rootPath: tempRoot.path,
              manifestPath:
                  '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
              targets: <ProjectTargetDescriptor>[
                ProjectTargetDescriptor(
                  id: 'demo/app:bin:demo',
                  packageName: 'demo/app',
                  kind: ProjectTargetKind.bin,
                  name: 'demo',
                  filePath: sourceFile.path,
                ),
              ],
            ),
          ],
          activeCompiler: _compilerSnapshot('/toolchains/styio/bin/styio'),
        ),
        document: const DocumentState(
          documentId: 'demo',
          text: '>_("demo")\n',
          revision: 1,
        ),
        activeFilePath: sourceFile.path,
      );

      expect(session.status, ExecutionSessionStatus.succeeded);
      expect(session.receipt?.schemaVersion, 1);
      expect(session.receipt?.intent, 'run');
      expect(session.receipt?.executed, isTrue);
      expect(session.sessionId, 'runtime-session-1');
      expect(
        session.statusMessage,
        contains('completed compiler run via payload'),
      );
      expect(
        session.stdoutEvents.map((event) => event.message),
        containsAll(<String>[
          '{"message":"user-log"}',
          '{"a":1}',
          'pafio-run-ok',
        ]),
      );
      expect(session.stderrEvents, isEmpty);
      expect(session.diagnostics, isEmpty);
      final runtimeAdapter = createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      );
      final runtimeEvents = await runtimeAdapter
          .sessionEvents(session.sessionId)
          .toList();
      expect(runtimeEvents.map((event) => event.eventKind), <String>[
        'session.capability',
        'compile.started',
        'run.finished',
      ]);
      expect(runtimeEvents.last.payload['success'], isTrue);
      expect(runtimeEvents.last.schemaVersion, 2);
      expect(runtimeEvents.last.origin, 'styio.observable.runtime-events');
    },
  );

  test(
    'execution adapter falls back to package build for non-entry project files',
    () async {
      final tempRoot = await _createTempRoot('vityo_execution_non_entry_test_');
      final helperFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}helper.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('// helper fixture\n');
      final mainFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('>_("demo")\n');
      final libFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}lib.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('// lib fixture\n');

      File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[build]
implicit-std = true

[lib]
path = "src/lib.styio"

[[bin]]
name = "demo"
path = "src/main.styio"
''');

      await _writePafioExecutable(
        File(
          '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
        ),
        '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)

if '--json' in sys.argv and 'build' in sys.argv:
    if '--package' not in sys.argv or sys.argv[sys.argv.index('--package') + 1] != 'demo/app':
        raise SystemExit(65)
    if '--bin' in sys.argv or '--lib' in sys.argv or '--test' in sys.argv:
        raise SystemExit(66)
    print(json.dumps({
        'command': 'build',
        'mode': 'execute',
        'workflow_payload_version': 1,
        'message': 'completed compiler build via payload',
        'stdout': '',
        'stderr': '',
        'diagnostics': [],
        'receipt': {
            'schema_version': 1,
            'intent': 'build',
            'executed': False,
        },
    }))
    raise SystemExit(0)

if 'run' in sys.argv:
    raise SystemExit(67)

raise SystemExit(64)
''',
      );

      final projectGraph = _projectGraph(
        workspaceRoot: tempRoot.path,
        manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
        targets: <ProjectTargetDescriptor>[
          ProjectTargetDescriptor(
            id: 'demo/app:lib:demo',
            packageName: 'demo/app',
            kind: ProjectTargetKind.lib,
            name: 'demo',
            filePath: libFile.path,
          ),
          ProjectTargetDescriptor(
            id: 'demo/app:bin:demo',
            packageName: 'demo/app',
            kind: ProjectTargetKind.bin,
            name: 'demo',
            filePath: mainFile.path,
          ),
        ],
        packages: <ProjectPackageSnapshot>[
          _packageSnapshot(
            packageName: 'demo/app',
            rootPath: tempRoot.path,
            manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
            targets: <ProjectTargetDescriptor>[
              ProjectTargetDescriptor(
                id: 'demo/app:lib:demo',
                packageName: 'demo/app',
                kind: ProjectTargetKind.lib,
                name: 'demo',
                filePath: libFile.path,
              ),
              ProjectTargetDescriptor(
                id: 'demo/app:bin:demo',
                packageName: 'demo/app',
                kind: ProjectTargetKind.bin,
                name: 'demo',
                filePath: mainFile.path,
              ),
            ],
          ),
        ],
        activeCompiler: _compilerSnapshot('/toolchains/styio/bin/styio'),
      );
      final adapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
      );

      final session = await adapter.runActiveDocument(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
        document: const DocumentState(
          documentId: 'helper',
          text: '# helper := 2\n',
          revision: 2,
        ),
        activeFilePath: helperFile.path,
      );

      expect(session.status, ExecutionSessionStatus.succeeded);
      expect(session.kind, 'build');
      expect(
        session.statusMessage,
        contains('completed compiler build via payload'),
      );
      expect(session.diagnostics, isEmpty);
    },
  );

  test('execution adapter surfaces structured pafio failure payloads', () async {
    final tempRoot = await _createTempRoot(
      'vityo_execution_failure_payload_test_',
    );
    final sourceFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('>_("demo")\n');

    File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[build]
implicit-std = true

[[bin]]
name = "demo"
path = "src/main.styio"
''');

    await _writePafioExecutable(
      File(
        '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
      ),
      '''#!/usr/bin/env python3
import json, os, sys

def write_runtime(session, events, command='run'):
    build = os.path.join(os.getcwd(), '.pafio', 'build', session)
    os.makedirs(build, exist_ok=True)
    events_path = os.path.join(build, 'runtime-events.jsonl')
    with open(events_path, 'w', encoding='utf-8') as fh:
        for event in events:
            fh.write(json.dumps(event) + '\\n')
    with open(os.path.join(build, 'receipt.json'), 'w', encoding='utf-8') as fh:
        json.dump({
            'schema_version': 1,
            'intent': command,
            'session_id': session,
            'executed': False,
            'outputs': {'runtime_events_path': events_path},
        }, fh)
    return build

def cap():
    return {
        'contract': 'styio.observable.runtime-events',
        'schema_version': 2,
        'record_kind': 'session.capability',
        'event_kind': 'session.capability',
        'mode': 'detailed',
        'snapshot_schema': 1,
        'snapshot_id': 's1_0123456789abcdef0123456789abcdef',
        'execution_id': 'x2_0000000000000001',
        'privacy_profile': 'strict',
        'producer_lanes': 1,
        'lane_capacity': 256,
        'priority_reserved': 32,
        'drain_batch': 64,
        'sampling': {'numerator': 1, 'denominator': 16, 'seed': 0},
        'clock_unit': 'ns',
        'supported_capabilities': ['task-lifecycle', 'loss-accounting', 'strict-privacy'],
        'active_capabilities': ['task-lifecycle', 'loss-accounting', 'strict-privacy'],
        'unavailable_capabilities': [],
    }

def ev(kind, eid, ns=0, **extra):
    row = {
        'contract': 'styio.observable.runtime-events',
        'schema_version': 2,
        'record_kind': 'event',
        'event_kind': kind,
        'family': 'session',
        'priority': 'lifecycle',
        'correlation_status': 'runtime_only',
        'role': 'runtime_only',
        'snapshot_id': None,
        'site_id': None,
        'instance_id': None,
        'event_id': eid,
        'monotonic_ns': ns,
        'causes': [],
        'wait': None,
    }
    row.update(extra)
    return row

if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)

if '--json' in sys.argv and 'run' in sys.argv:
    build = write_runtime('runtime-session-failure', [
        cap(),
        ev('compile.started', 'r2_0000000000000001', 0, intent='run'),
        ev('compile.failed', 'r2_0000000000000002', 1000, intent='run', executed=False),
    ])
    sys.stderr.write(json.dumps({
        'category': 'CompilerError',
        'code': 23,
        'message': 'compile-plan failed through payload',
        'command': 'run',
        'runtime_session_id': 'runtime-session-failure',
        'plan': {'build_root': build},
        'diagnostics': [{
            'category': 'SyntaxError',
            'code': 'STYIO_SYN',
            'subcode': 'missing-token',
            'message': 'missing token',
            'file': ${jsonEncode(sourceFile.path)},
            'offset': 2,
            'length': 4,
        }],
    }) + '\\n')
    raise SystemExit(23)

raise SystemExit(64)
''',
    );

    final projectGraph = _projectGraph(
      workspaceRoot: tempRoot.path,
      manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
      targets: <ProjectTargetDescriptor>[
        ProjectTargetDescriptor(
          id: 'demo/app:bin:demo',
          packageName: 'demo/app',
          kind: ProjectTargetKind.bin,
          name: 'demo',
          filePath: sourceFile.path,
        ),
      ],
      packages: <ProjectPackageSnapshot>[
        _packageSnapshot(
          packageName: 'demo/app',
          rootPath: tempRoot.path,
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
          targets: <ProjectTargetDescriptor>[
            ProjectTargetDescriptor(
              id: 'demo/app:bin:demo',
              packageName: 'demo/app',
              kind: ProjectTargetKind.bin,
              name: 'demo',
              filePath: sourceFile.path,
            ),
          ],
        ),
      ],
      activeCompiler: _compilerSnapshot('/toolchains/styio/bin/styio'),
    );
    final adapter = await createExecutionAdapter(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
    );

    addTearDown(() => clearRuntimeEventsForSession('runtime-session-failure'));
    final session = await adapter.runActiveDocument(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
      document: const DocumentState(
        documentId: 'demo',
        text: '>_("demo")\n',
        revision: 1,
      ),
      activeFilePath: sourceFile.path,
    );

    expect(session.status, ExecutionSessionStatus.failed);
    expect(session.sessionId, 'runtime-session-failure');
    expect(
      session.statusMessage,
      contains('compile-plan failed through payload'),
    );
    expect(session.diagnostics, isNotEmpty);
    expect(session.diagnostics.first.code, 'STYIO_SYN:missing-token');
    expect(session.diagnostics.first.message, 'missing token');
    expect(session.diagnostics.first.range.start, 2);
    expect(session.diagnostics.first.range.end, 6);
    final runtimeAdapter = createRuntimeEventAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final runtimeEvents = await runtimeAdapter
        .sessionEvents(session.sessionId)
        .toList();
    expect(runtimeEvents.map((event) => event.eventKind), <String>[
      'session.capability',
      'compile.started',
      'compile.failed',
    ]);
  });

  test(
    'single-file execution uses an overlay snapshot and leaves real files untouched',
    () async {
      final tempRoot = await _createTempRoot(
        'vityo_execution_scratch_path_test_',
      );
      final sourceFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}scratch${Platform.pathSeparator}main.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('>_("before")\n');
      final siblingFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}scratch${Platform.pathSeparator}sibling.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('// sibling before\n');
      File('${tempRoot.path}${Platform.pathSeparator}styio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('dict_impl = "rbmap"\n');

      final fakeStyio = await _writeExecutable(
        File('${tempRoot.path}${Platform.pathSeparator}fake-styio'),
        '''#!/usr/bin/env python3
import json, os, sys

real_path = ${jsonEncode(sourceFile.path)}
sibling_path = ${jsonEncode(siblingFile.path)}

def has_expected_config(path: str) -> bool:
    current = os.path.dirname(path)
    while True:
        for name in ('styio.toml', '.styio.toml'):
            candidate = os.path.join(current, name)
            if os.path.exists(candidate):
                return 'dict_impl = "rbmap"' in open(candidate, 'r', encoding='utf-8').read()
        parent = os.path.dirname(current)
        if parent == current:
            return False
        current = parent

if len(sys.argv) >= 4 and sys.argv[1] == '--file' and sys.argv[3] == '--error-format=jsonl':
    run_path = sys.argv[2]
    overlay_sibling_path = os.path.join(os.path.dirname(run_path), 'sibling.styio')
    with open(overlay_sibling_path, 'w', encoding='utf-8') as overlay_sibling:
        overlay_sibling.write('// sibling after\\n')
    if (run_path != real_path and
        open(real_path, 'r', encoding='utf-8').read() == '>_("before")\\n' and
        open(run_path, 'r', encoding='utf-8').read() == '>_("after")\\n' and
        open(sibling_path, 'r', encoding='utf-8').read() == '// sibling before\\n' and
        open(overlay_sibling_path, 'r', encoding='utf-8').read() == '// sibling after\\n' and
        has_expected_config(run_path)):
        print(json.dumps({'executed_path': run_path}))
        raise SystemExit(0)

sys.stderr.write(json.dumps({
    'category': 'SyntaxError',
    'code': 'WRONG_FILE',
    'message': sys.argv[2] if len(sys.argv) > 2 else 'missing file',
}) + '\\n')
raise SystemExit(65)
''',
      );

      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: tempRoot.path,
        activeFilePath: sourceFile.path,
        title: 'Scratch Project',
        notes: const <String>[],
        activeCompiler: _compilerSnapshot(
          fakeStyio.path,
          contracts: const <String, List<int>>{
            'machine_info': <int>[1],
          },
        ),
      );
      final adapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
      );

      final session = await adapter.runActiveDocument(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
        document: const DocumentState(
          documentId: 'scratch',
          text: '>_("after")\n',
          revision: 2,
        ),
        activeFilePath: sourceFile.path,
      );

      expect(
        session.status,
        ExecutionSessionStatus.succeeded,
        reason: session.statusMessage,
      );
      expect(
        session.stdoutEvents.map((event) => event.message),
        contains(
          predicate((String message) => message.contains('executed_path')),
        ),
      );
      expect(sourceFile.readAsStringSync(), '>_("before")\n');
      expect(siblingFile.readAsStringSync(), '// sibling before\n');
    },
  );

  test(
    'execution overlay omits symlink entries that escape the workspace',
    () async {
      final tempRoot = await _createTempRoot(
        'vityo_execution_symlink_escape_test_',
      );
      final outsideRoot = await Directory.systemTemp.createTemp(
        'vityo_execution_outside_',
      );
      addTearDown(() => outsideRoot.delete(recursive: true));

      final sourceFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}scratch${Platform.pathSeparator}main.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('>_("before")\n');
      final outsideFile = File(
        '${outsideRoot.path}${Platform.pathSeparator}outside.txt',
      )..writeAsStringSync('outside before\n');
      final escapeLink = Link(
        '${tempRoot.path}${Platform.pathSeparator}scratch${Platform.pathSeparator}escape.txt',
      );
      try {
        await escapeLink.create(outsideFile.path);
      } on FileSystemException {
        return;
      }

      File('${tempRoot.path}${Platform.pathSeparator}styio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('dict_impl = "rbmap"\n');

      final fakeStyio = await _writeExecutable(
        File('${tempRoot.path}${Platform.pathSeparator}fake-styio'),
        '''#!/usr/bin/env python3
import json, os, sys

real_path = ${jsonEncode(sourceFile.path)}
outside_path = ${jsonEncode(outsideFile.path)}

if len(sys.argv) >= 4 and sys.argv[1] == '--file' and sys.argv[3] == '--error-format=jsonl':
    run_path = sys.argv[2]
    overlay_escape_path = os.path.join(os.path.dirname(run_path), 'escape.txt')
    if os.path.lexists(overlay_escape_path):
        with open(overlay_escape_path, 'w', encoding='utf-8') as escape_file:
            escape_file.write('outside after\\n')
    if (run_path != real_path and
        not os.path.lexists(overlay_escape_path) and
        open(outside_path, 'r', encoding='utf-8').read() == 'outside before\\n'):
        print(json.dumps({'escape_link_omitted': True}))
        raise SystemExit(0)

sys.stderr.write(json.dumps({
    'category': 'SyntaxError',
    'code': 'ESCAPE_LINK_PRESENT',
    'message': 'overlay symlink escape was present',
}) + '\\n')
raise SystemExit(65)
''',
      );

      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: tempRoot.path,
        activeFilePath: sourceFile.path,
        title: 'Scratch Project',
        notes: const <String>[],
        activeCompiler: _compilerSnapshot(
          fakeStyio.path,
          contracts: const <String, List<int>>{
            'machine_info': <int>[1],
          },
        ),
      );
      final adapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
      );

      final session = await adapter.runActiveDocument(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
        document: const DocumentState(
          documentId: 'scratch',
          text: '>_("after")\n',
          revision: 2,
        ),
        activeFilePath: sourceFile.path,
      );

      expect(
        session.status,
        ExecutionSessionStatus.succeeded,
        reason: session.statusMessage,
      );
      expect(outsideFile.readAsStringSync(), 'outside before\n');
      expect(escapeLink.targetSync(), outsideFile.path);
    },
  );

  test(
    'project execution blocks changed active files that resolve outside the workspace',
    () async {
      final tempRoot = await _createTempRoot(
        'vityo_execution_project_symlink_escape_test_',
      );
      final outsideRoot = await Directory.systemTemp.createTemp(
        'vityo_execution_project_outside_',
      );
      addTearDown(() => outsideRoot.delete(recursive: true));

      final mainFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('>_("main")\n');
      final outsideFile = File(
        '${outsideRoot.path}${Platform.pathSeparator}outside.styio',
      )..writeAsStringSync('>_("outside before")\n');
      final escapeLink = Link(
        '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}escape.styio',
      );
      try {
        await escapeLink.create(outsideFile.path);
      } on FileSystemException {
        return;
      }

      File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[build]
implicit-std = true

[[bin]]
name = "demo"
path = "src/main.styio"
''');

      await _writePafioExecutable(
        File(
          '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
        ),
        '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)

raise SystemExit(66)
''',
      );

      final projectGraph = _projectGraph(
        workspaceRoot: tempRoot.path,
        manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
        targets: <ProjectTargetDescriptor>[
          ProjectTargetDescriptor(
            id: 'demo/app:bin:demo',
            packageName: 'demo/app',
            kind: ProjectTargetKind.bin,
            name: 'demo',
            filePath: mainFile.path,
          ),
        ],
        packages: <ProjectPackageSnapshot>[
          _packageSnapshot(
            packageName: 'demo/app',
            rootPath: tempRoot.path,
            manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
            targets: <ProjectTargetDescriptor>[
              ProjectTargetDescriptor(
                id: 'demo/app:bin:demo',
                packageName: 'demo/app',
                kind: ProjectTargetKind.bin,
                name: 'demo',
                filePath: mainFile.path,
              ),
            ],
          ),
        ],
        activeCompiler: _compilerSnapshot('/toolchains/styio/bin/styio'),
      );
      final adapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
      );

      final session = await adapter.runActiveDocument(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
        document: const DocumentState(
          documentId: 'escape',
          text: '>_("outside after")\n',
          revision: 2,
        ),
        activeFilePath: escapeLink.path,
      );

      expect(session.status, ExecutionSessionStatus.blocked);
      expect(session.sessionId, 'execution-overlay-blocked');
      expect(
        session.statusMessage,
        contains('resolves outside workspace root'),
      );
      expect(outsideFile.readAsStringSync(), '>_("outside before")\n');
    },
  );

  test('cross-file CLI diagnostics stay out of active-file ranges', () async {
    final tempRoot = await _createTempRoot(
      'vityo_execution_cross_file_diag_test_',
    );
    final sourceFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}scratch${Platform.pathSeparator}main.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('>_("main")\n');
    final helperFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}scratch${Platform.pathSeparator}helper.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('// helper fixture\n');

    final fakeStyio = await _writeExecutable(
      File('${tempRoot.path}${Platform.pathSeparator}fake-styio'),
      '''#!/usr/bin/env python3
import json, sys

if len(sys.argv) >= 4 and sys.argv[1] == '--file' and sys.argv[3] == '--error-format=jsonl':
    sys.stderr.write(json.dumps({
        'category': 'SyntaxError',
        'code': 'HELPER',
        'message': 'helper failed',
        'file': ${jsonEncode(helperFile.path)},
        'offset': 1,
        'length': 3,
    }) + '\\n')
    raise SystemExit(65)

raise SystemExit(64)
''',
    );

    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: tempRoot.path,
      activeFilePath: sourceFile.path,
      title: 'Scratch Project',
      notes: const <String>[],
      activeCompiler: _compilerSnapshot(
        fakeStyio.path,
        contracts: const <String, List<int>>{
          'machine_info': <int>[1],
        },
      ),
    );
    final adapter = await createExecutionAdapter(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
    );

    final session = await adapter.runActiveDocument(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
      document: const DocumentState(
        documentId: 'scratch',
        text: '>_("main")\n',
        revision: 1,
      ),
      activeFilePath: sourceFile.path,
    );

    expect(session.status, ExecutionSessionStatus.failed);
    expect(session.diagnostics, isEmpty);
    expect(
      session.stderrEvents.map((event) => event.message),
      contains('${helperFile.path}: helper failed'),
    );
  });

  test(
    'execution adapter exposes blocked platform and compiler branches',
    () async {
      final tempRoot = await _createTempRoot('vityo_execution_blocked_test_');
      final sourceFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}scratch${Platform.pathSeparator}main.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('>_("demo")\n');

      debugOverrideHostedEnvironment(const <String, String>{
        'VITYO_HOSTED_URL': 'http://127.0.0.1:1/api/styio-hosted/v1',
        'VITYO_HOSTED_TOKEN': 'test-hosted-token',
        'VITYO_HOSTED_WORKSPACE_ROOT': '/workspace/hosted',
      });
      final hostedAdapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.ios,
        projectGraph: ProjectGraphSnapshot.scratch(
          workspaceRoot: tempRoot.path,
          activeFilePath: sourceFile.path,
          title: 'Scratch Project',
          notes: const <String>[],
        ),
      );
      addTearDown(() => debugOverrideHostedEnvironment(null));
      expect(
        hostedAdapter.capabilitySnapshot.execution.level,
        AdapterCapabilityLevel.available,
      );
      final missingHostedWorkspace = await hostedAdapter.runActiveDocument(
        platformTarget: PlatformTarget.ios,
        projectGraph: ProjectGraphSnapshot.scratch(
          workspaceRoot: tempRoot.path,
          activeFilePath: sourceFile.path,
          title: 'Scratch Project',
          notes: const <String>[],
        ),
        document: const DocumentState(
          documentId: 'scratch',
          text: '>_("demo")\n',
          revision: 1,
        ),
        activeFilePath: sourceFile.path,
      );
      expect(missingHostedWorkspace.status, ExecutionSessionStatus.blocked);
      expect(missingHostedWorkspace.sessionId, 'missing-hosted-workspace');

      debugOverrideHostedEnvironment(null);
      final missingCompilerGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: tempRoot.path,
        activeFilePath: sourceFile.path,
        title: 'Scratch Project',
        notes: const <String>[],
      );
      final missingCompilerAdapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.macos,
        projectGraph: missingCompilerGraph,
      );
      expect(
        missingCompilerAdapter.capabilitySnapshot.execution.level,
        AdapterCapabilityLevel.unavailable,
      );
      final missingCompiler = await missingCompilerAdapter.runActiveDocument(
        platformTarget: PlatformTarget.macos,
        projectGraph: missingCompilerGraph,
        document: const DocumentState(
          documentId: 'scratch',
          text: '>_("demo")\n',
          revision: 1,
        ),
        activeFilePath: sourceFile.path,
      );
      expect(missingCompiler.status, ExecutionSessionStatus.blocked);
      expect(missingCompiler.sessionId, 'missing-styio-binary');

      final fakeStyio = await _writeExecutable(
        File('${tempRoot.path}${Platform.pathSeparator}fake-styio'),
        '''#!/usr/bin/env python3
raise SystemExit(64)
''',
      );
      final iosGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: tempRoot.path,
        activeFilePath: sourceFile.path,
        title: 'Scratch Project',
        notes: const <String>[],
        activeCompiler: _compilerSnapshot(fakeStyio.path),
      );
      final iosAdapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.ios,
        projectGraph: iosGraph,
      );
      expect(
        iosAdapter.capabilitySnapshot.execution.level,
        AdapterCapabilityLevel.unavailable,
      );
      final iosSession = await iosAdapter.runActiveDocument(
        platformTarget: PlatformTarget.ios,
        projectGraph: iosGraph,
        document: const DocumentState(
          documentId: 'scratch',
          text: '>_("demo")\n',
          revision: 1,
        ),
        activeFilePath: sourceFile.path,
      );
      expect(iosSession.sessionId, 'ios-cloud-only');

      final manifestPath =
          '${tempRoot.path}${Platform.pathSeparator}pafio.toml';
      File(manifestPath).writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[[bin]]
name = "demo"
path = "scratch/main.styio"
''');
      final target = ProjectTargetDescriptor(
        id: 'demo/app:bin:demo',
        packageName: 'demo/app',
        kind: ProjectTargetKind.bin,
        name: 'demo',
        filePath: sourceFile.path,
      );
      final blockedCompilePlanGraph = _projectGraph(
        workspaceRoot: tempRoot.path,
        manifestPath: manifestPath,
        targets: <ProjectTargetDescriptor>[target],
        packages: <ProjectPackageSnapshot>[
          _packageSnapshot(
            packageName: 'demo/app',
            rootPath: tempRoot.path,
            manifestPath: manifestPath,
            targets: <ProjectTargetDescriptor>[target],
          ),
        ],
        activeCompiler: _compilerSnapshot(
          fakeStyio.path,
          contracts: const <String, List<int>>{
            'machine_info': <int>[1],
          },
        ),
      );
      final blockedCompilePlanAdapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.macos,
        projectGraph: blockedCompilePlanGraph,
      );
      expect(
        blockedCompilePlanAdapter.capabilitySnapshot.execution.level,
        AdapterCapabilityLevel.partial,
      );
      final blockedCompilePlan = await blockedCompilePlanAdapter
          .runActiveDocument(
            platformTarget: PlatformTarget.macos,
            projectGraph: blockedCompilePlanGraph,
            document: const DocumentState(
              documentId: 'scratch',
              text: '>_("demo")\n',
              revision: 1,
            ),
            activeFilePath: sourceFile.path,
          );
      expect(blockedCompilePlan.sessionId, 'compile-plan-preview-only');

      debugOverridePafioExecutableCandidates(const <String>[]);
      addTearDown(() => debugOverridePafioExecutableCandidates(null));
      final missingPafioGraph = _projectGraph(
        workspaceRoot: tempRoot.path,
        manifestPath: manifestPath,
        targets: <ProjectTargetDescriptor>[target],
        packages: <ProjectPackageSnapshot>[
          _packageSnapshot(
            packageName: 'demo/app',
            rootPath: tempRoot.path,
            manifestPath: manifestPath,
            targets: <ProjectTargetDescriptor>[target],
          ),
        ],
        activeCompiler: _compilerSnapshot(fakeStyio.path),
      );
      final missingPafioAdapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.macos,
        projectGraph: missingPafioGraph,
      );
      final missingPafio = await missingPafioAdapter.runActiveDocument(
        platformTarget: PlatformTarget.macos,
        projectGraph: missingPafioGraph,
        document: const DocumentState(
          documentId: 'scratch',
          text: '>_("demo")\n',
          revision: 1,
        ),
        activeFilePath: sourceFile.path,
      );
      expect(missingPafio.status, ExecutionSessionStatus.blocked);
      expect(missingPafio.sessionId, 'missing-pafio-binary');
    },
  );

  test(
    'single-file execution writes relative documents to temporary inputs',
    () async {
      final tempRoot = await _createTempRoot('vityo_execution_relative_test_');
      final fakeStyio = await _writeExecutable(
        File('${tempRoot.path}${Platform.pathSeparator}fake-styio'),
        '''#!/usr/bin/env python3
import json, os, sys

if len(sys.argv) >= 4 and sys.argv[1] == '--file' and sys.argv[3] == '--error-format=jsonl':
    run_path = sys.argv[2]
    with open(run_path, 'r', encoding='utf-8') as handle:
        text = handle.read()
    print(json.dumps({
        'path': run_path,
        'basename': os.path.basename(run_path),
        'text': text,
    }))
    raise SystemExit(0)

raise SystemExit(64)
''',
      );
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: tempRoot.path,
        activeFilePath: 'scratch/relative.styio',
        title: 'Scratch Project',
        notes: const <String>[],
        activeCompiler: _compilerSnapshot(
          fakeStyio.path,
          contracts: const <String, List<int>>{
            'machine_info': <int>[1],
          },
        ),
      );
      final adapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
      );

      final session = await adapter.runActiveDocument(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
        document: const DocumentState(
          documentId: 'scratch/relative.styio',
          text: '>_("relative")\n',
          revision: 1,
        ),
        activeFilePath: 'scratch/relative.styio',
      );

      expect(session.status, ExecutionSessionStatus.succeeded);
      final payload =
          jsonDecode(session.stdoutEvents.single.message)
              as Map<String, dynamic>;
      expect(payload['basename'], 'main.styio');
      expect(payload['text'], '>_("relative")\n');
      expect(File(payload['path'] as String).existsSync(), isFalse);
    },
  );

  test(
    'project workflow reads artifact diagnostics and runtime events for test and lib targets',
    () async {
      final tempRoot = await _createTempRoot(
        'vityo_execution_artifact_payload_test_',
      );
      final testFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}tests${Platform.pathSeparator}render_test.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('test "render" {}\n');
      final libFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}lib.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('pub fn render() {}\n');
      final manifestPath =
          '${tempRoot.path}${Platform.pathSeparator}pafio.toml';
      File(manifestPath).writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[lib]
path = "src/lib.styio"

[[test]]
name = "render"
path = "tests/render_test.styio"
''');
      await _writePafioExecutable(
        File(
          '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
        ),
        '''#!/usr/bin/env python3
import json, os, sys

if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)

if '--json' in sys.argv and 'test' in sys.argv:
    manifest = sys.argv[sys.argv.index('--manifest-path') + 1]
    root = os.path.dirname(manifest)
    active = os.path.join(root, 'tests', 'render_test.styio')
    artifact_dir = os.path.join(root, 'artifacts')
    os.makedirs(artifact_dir, exist_ok=True)
    diagnostics_path = os.path.join(artifact_dir, 'diagnostics.jsonl')
    with open(diagnostics_path, 'w', encoding='utf-8') as diagnostics:
        diagnostics.write(json.dumps({
            'eventKind': 'diagnostic.emitted',
            'payload': {
                'severity': 'warning',
                'code': 99,
                'message': {'summary': 'range summary', 'detail': 'range detail'},
                'file': active,
                'range': {'start': {'offset': 8}, 'end': {'offset': 4}},
            },
        }) + '\\n')
        diagnostics.write(json.dumps({
            'category': 'RuntimeType',
            'detail': 'negative length',
            'file': active,
            'offset': 7,
            'length': -2,
        }) + '\\n')
        diagnostics.write('not-json\\n')
    build = os.path.join(root, '.pafio', 'build', 'artifact-session')
    os.makedirs(build, exist_ok=True)
    events_path = os.path.join(build, 'runtime-events.jsonl')
    with open(events_path, 'w', encoding='utf-8') as events:
        events.write(json.dumps({
            'contract': 'styio.observable.runtime-events',
            'schema_version': 2,
            'record_kind': 'session.capability',
            'event_kind': 'session.capability',
            'mode': 'detailed',
            'snapshot_schema': 1,
            'snapshot_id': 's1_0123456789abcdef0123456789abcdef',
            'execution_id': 'x2_0000000000000001',
            'privacy_profile': 'strict',
            'producer_lanes': 1,
            'lane_capacity': 256,
            'priority_reserved': 32,
            'drain_batch': 64,
            'sampling': {'numerator': 1, 'denominator': 16, 'seed': 0},
            'clock_unit': 'ns',
            'supported_capabilities': ['task-lifecycle', 'loss-accounting', 'strict-privacy'],
            'active_capabilities': ['task-lifecycle', 'loss-accounting', 'strict-privacy'],
            'unavailable_capabilities': [],
        }) + '\\n')
        events.write(json.dumps({
            'contract': 'styio.observable.runtime-events',
            'schema_version': 2,
            'record_kind': 'event',
            'event_kind': 'compile.finished',
            'family': 'session',
            'priority': 'lifecycle',
            'correlation_status': 'runtime_only',
            'role': 'runtime_only',
            'snapshot_id': None,
            'site_id': None,
            'instance_id': None,
            'event_id': 'r2_0000000000000001',
            'monotonic_ns': 0,
            'causes': [],
            'wait': None,
        }) + '\\n')
    with open(os.path.join(build, 'receipt.json'), 'w', encoding='utf-8') as receipt:
        json.dump({
            'schema_version': 1,
            'intent': 'test',
            'session_id': 'artifact-session',
            'executed': True,
            'outputs': {'runtime_events_path': events_path},
        }, receipt)
    print(json.dumps({
        'workflow_payload_version': 1,
        'message': 'artifact test completed',
        'stdout': 'plain stdout\\n',
        'stderr': json.dumps({
            'category': 'Warning',
            'message': 'stderr diagnostic',
            'file': active,
            'span': {'startOffset': '1', 'endOffset': '3'},
        }) + '\\n',
        'diagnostics_path': 'artifacts/diagnostics.jsonl',
        'plan': {'build_root': build},
        'receipt': {
            'schema_version': 1,
            'intent': 'test',
            'session_id': 'artifact-session',
            'executed': True,
            'phases': ['compile', 'test'],
            'artifacts': ['artifacts/diagnostics.jsonl'],
        },
    }))
    raise SystemExit(0)

if '--json' in sys.argv and 'build' in sys.argv and '--lib' in sys.argv:
    print(json.dumps({
        'workflow_payload_version': 1,
        'message': 'library build completed',
        'stdout': 'lib stdout\\n',
        'stderr': '',
        'diagnostics': [],
        'plan': {'build_root': os.path.join(os.getcwd(), '.pafio', 'build', 'missing')},
    }))
    raise SystemExit(0)

raise SystemExit(64)
''',
      );

      final testTarget = ProjectTargetDescriptor(
        id: 'demo/app:test:render',
        packageName: 'demo/app',
        kind: ProjectTargetKind.test,
        name: 'render',
        filePath: testFile.path,
      );
      final libTarget = ProjectTargetDescriptor(
        id: 'demo/app:lib:demo',
        packageName: 'demo/app',
        kind: ProjectTargetKind.lib,
        name: 'demo',
        filePath: libFile.path,
      );
      final projectGraph = _projectGraph(
        workspaceRoot: tempRoot.path,
        manifestPath: manifestPath,
        targets: <ProjectTargetDescriptor>[testTarget, libTarget],
        packages: <ProjectPackageSnapshot>[
          _packageSnapshot(
            packageName: 'demo/app',
            rootPath: tempRoot.path,
            manifestPath: manifestPath,
            targets: <ProjectTargetDescriptor>[testTarget, libTarget],
          ),
        ],
        activeCompiler: _compilerSnapshot('/toolchains/styio/bin/styio'),
      );
      final adapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
      );

      final testSession = await adapter.runActiveDocument(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
        document: const DocumentState(
          documentId: 'tests/render_test.styio',
          text: 'test "render" { assert false }\n',
          revision: 2,
        ),
        activeFilePath: testFile.path,
      );

      addTearDown(() => clearRuntimeEventsForSession('artifact-session'));
      expect(testSession.status, ExecutionSessionStatus.succeeded);
      expect(testSession.kind, 'test');
      expect(testSession.sessionId, 'artifact-session');
      expect(testSession.stdoutEvents.single.message, 'plain stdout');
      final diagnosticMessages = testSession.diagnostics
          .map((diagnostic) => diagnostic.message)
          .toList(growable: false);
      for (final expectedMessage in <String>[
        'range summary range detail',
        'negative length',
        'stderr diagnostic',
      ]) {
        expect(diagnosticMessages, anyElement(contains(expectedMessage)));
      }
      expect(
        testSession.diagnostics.first.severity,
        DiagnosticSeverity.warning,
      );
      expect(testSession.diagnostics.first.code, '99');
      expect(testSession.diagnostics.first.range.start, 4);
      expect(testSession.diagnostics.first.range.end, 8);
      expect(testSession.diagnostics[1].range.start, 7);
      expect(testSession.diagnostics[1].range.end, 7);

      final runtimeEvents = await createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      ).sessionEvents('artifact-session').toList();
      expect(runtimeEvents, hasLength(2));
      expect(runtimeEvents.first.eventKind, 'session.capability');
      expect(runtimeEvents.last.schemaVersion, 2);
      expect(runtimeEvents.last.sessionId, 'artifact-session');
      expect(runtimeEvents.last.sequence, 2);
      expect(runtimeEvents.last.eventKind, 'compile.finished');
      expect(runtimeEvents.last.origin, 'styio.observable.runtime-events');
      expect(
        runtimeEvents.last.timestamp,
        DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
      );

      final libSession = await adapter.runActiveDocument(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
        document: const DocumentState(
          documentId: 'src/lib.styio',
          text: 'pub fn render() {}\n',
          revision: 1,
        ),
        activeFilePath: libFile.path,
      );
      expect(libSession.status, ExecutionSessionStatus.succeeded);
      expect(libSession.kind, 'build');
      expect(libSession.statusMessage, 'library build completed');
    },
  );

  test('single-file execution parses diagnostic edge payloads as logs', () async {
    final tempRoot = await _createTempRoot(
      'vityo_execution_diagnostic_edges_test_',
    );
    final sourceFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}scratch${Platform.pathSeparator}main.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('price = 1\nresult = price\n');
    final helperFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}scratch${Platform.pathSeparator}helper.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('helper = 1\n');

    final fakeStyio = await _writeExecutable(
      File('${tempRoot.path}${Platform.pathSeparator}fake-styio'),
      '''#!/usr/bin/env python3
import json, sys

if len(sys.argv) >= 4 and sys.argv[1] == '--file' and sys.argv[3] == '--error-format=jsonl':
    print('{broken')
    print(json.dumps({'message': 'structured log without diagnostic marker'}))
    print(json.dumps({
        'type': 'diagnostic',
        'text': {'text': 'typed diagnostic'},
        'severity': 'warning',
        'code': True,
        'location': {'start': {'index': 0}, 'end': {'value': 5}},
    }))
    sys.stderr.write(json.dumps({
        'category': 'RuntimeType',
        'detail': 'runtime category failed',
        'offset': 8.0,
        'length': 3.0,
    }) + '\\n')
    sys.stderr.write(json.dumps({
        'category': 'Warning',
        'message': ${jsonEncode('${helperFile.path}: already decorated')},
        'file': ${jsonEncode(helperFile.path)},
        'span': {'start': {'position': 1}, 'end': {'offset': 4}},
    }) + '\\n')
    raise SystemExit(65)

raise SystemExit(64)
''',
    );

    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: tempRoot.path,
      activeFilePath: sourceFile.path,
      title: 'Scratch Project',
      notes: const <String>[],
      activeCompiler: _compilerSnapshot(
        fakeStyio.path,
        contracts: const <String, List<int>>{
          'machine_info': <int>[1],
        },
      ),
    );
    final adapter = await createExecutionAdapter(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
    );

    final session = await adapter.runActiveDocument(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
      document: const DocumentState(
        documentId: 'scratch',
        text: 'price = 1\nresult = price\n',
        revision: 1,
      ),
      activeFilePath: sourceFile.path,
    );

    expect(session.status, ExecutionSessionStatus.failed);
    expect(session.diagnostics.map((diagnostic) => diagnostic.message), [
      'typed diagnostic',
      'runtime category failed',
    ]);
    expect(session.diagnostics.first.severity, DiagnosticSeverity.warning);
    expect(session.diagnostics.first.code, 'true');
    expect(session.diagnostics.first.range.start, 0);
    expect(session.diagnostics.first.range.end, 5);
    expect(session.diagnostics.last.severity, DiagnosticSeverity.error);
    expect(session.diagnostics.last.range.start, 8);
    expect(session.diagnostics.last.range.end, 11);
    expect(
      session.stdoutEvents.map((event) => event.message),
      containsAll(<String>[
        '{broken',
        '{"message": "structured log without diagnostic marker"}',
      ]),
    );
    expect(
      session.stderrEvents.map((event) => event.message),
      contains('${helperFile.path}: already decorated'),
    );
  });

  test('observed runs append Pafio options and return a contained artifact', () async {
    final tempRoot = await _createTempRoot('vityo_observed_run_test_');
    final sourceFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('>_("demo")\n');
    File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"
[[bin]]
name = "demo"
path = "src/main.styio"
''');
    await _writePafioExecutable(
      File(
        '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
      ),
      '''#!/usr/bin/env python3
import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
argv_path = os.path.join(root, 'argv.json')
with open(argv_path, 'w', encoding='utf-8') as fh:
    json.dump(sys.argv[1:], fh)
def write_runtime(session, events):
    build = os.path.join(os.getcwd(), '.pafio', 'build', session)
    os.makedirs(build, exist_ok=True)
    events_path = os.path.join(build, 'runtime-events.jsonl')
    with open(events_path, 'w', encoding='utf-8') as fh:
        for event in events:
            fh.write(json.dumps(event) + '\\n')
    with open(os.path.join(build, 'receipt.json'), 'w', encoding='utf-8') as fh:
        json.dump({
            'schema_version': 1,
            'intent': 'run',
            'session_id': session,
            'executed': True,
            'outputs': {'runtime_events_path': events_path},
        }, fh)
    return build, events_path
if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)
if '--json' in sys.argv and 'run' in sys.argv:
    build, events_path = write_runtime('observed-session', [{
        'contract': 'styio.observable.runtime-events',
        'schema_version': 2,
        'record_kind': 'session.capability',
        'event_kind': 'session.capability',
        'mode': 'aggregate',
        'snapshot_schema': 1,
        'snapshot_id': 's1_0123456789abcdef0123456789abcdef',
        'execution_id': 'x2_0000000000000001',
        'privacy_profile': 'strict',
        'producer_lanes': 1,
        'lane_capacity': 256,
        'priority_reserved': 32,
        'drain_batch': 64,
        'sampling': {'numerator': 1, 'denominator': 16, 'seed': 0},
        'clock_unit': 'ns',
        'supported_capabilities': ['task-lifecycle', 'loss-accounting', 'strict-privacy'],
        'active_capabilities': ['task-lifecycle', 'loss-accounting', 'strict-privacy'],
        'unavailable_capabilities': [],
    }])
    print(json.dumps({
        'workflow_payload_version': 1,
        'message': 'observed run',
        'stdout': '',
        'stderr': '',
        'diagnostics': [],
        'runtime_session_id': 'observed-session',
        'plan': {'build_root': build},
        'receipt': {'schema_version': 1, 'intent': 'run', 'session_id': 'observed-session', 'executed': True},
    }))
    raise SystemExit(0)
raise SystemExit(64)
''',
    );
    final projectGraph = _projectGraph(
      workspaceRoot: tempRoot.path,
      manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
      targets: <ProjectTargetDescriptor>[
        ProjectTargetDescriptor(
          id: 'demo/app:bin:demo',
          packageName: 'demo/app',
          kind: ProjectTargetKind.bin,
          name: 'demo',
          filePath: sourceFile.path,
        ),
      ],
      packages: <ProjectPackageSnapshot>[
        _packageSnapshot(
          packageName: 'demo/app',
          rootPath: tempRoot.path,
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
          targets: <ProjectTargetDescriptor>[
            ProjectTargetDescriptor(
              id: 'demo/app:bin:demo',
              packageName: 'demo/app',
              kind: ProjectTargetKind.bin,
              name: 'demo',
              filePath: sourceFile.path,
            ),
          ],
        ),
      ],
      activeCompiler: _compilerSnapshot(
        '/toolchains/styio/bin/styio',
        contracts: const <String, List<int>>{
          'machine_info': <int>[1],
          'compile_plan': <int>[1],
          'runtime_events': <int>[2],
        },
      ),
    );
    final adapter = await createExecutionAdapter(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
    );
    expect(adapter, isA<ObservedExecutionAdapter>());
    addTearDown(() => clearRuntimeEventsForSession('observed-session'));
    final run = await (adapter as ObservedExecutionAdapter)
        .runActiveDocumentObserved(
          platformTarget: PlatformTarget.macos,
          projectGraph: projectGraph,
          document: const DocumentState(
            documentId: 'demo',
            text: '>_("demo")\n',
            revision: 1,
          ),
          activeFilePath: sourceFile.path,
          observation: const RuntimeObservationRequest(
            mode: RuntimeObservationMode.aggregate,
          ),
        );
    expect(run.session.status, ExecutionSessionStatus.succeeded);
    expect(run.runtimeEventsPath, isNotNull);
    expect(File(run.runtimeEventsPath!).existsSync(), isTrue);
    expect(
      run.runtimeEventsPath!.endsWith('runtime-events.jsonl'),
      isTrue,
    );
    final argv = jsonDecode(
      File('${tempRoot.path}${Platform.pathSeparator}argv.json').readAsStringSync(),
    ) as List<dynamic>;
    expect(argv, contains('--emit-runtime-observation=2'));
    expect(argv, contains('--runtime-observation-mode'));
    expect(argv, contains('aggregate'));
    expect(argv, contains('--runtime-observation-capability'));
    expect(argv, contains('task-lifecycle'));
    expect(argv, contains('loss-accounting'));
    expect(argv, contains('strict-privacy'));
    expect(argv, isNot(contains('--runtime-observation-lane-capacity')));
    await run.release();

    // The plain run through the same adapter must not gain any observation
    // option: the observed seam never alters the plain command line.
    final plainSession = await adapter.runActiveDocument(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
      document: const DocumentState(
        documentId: 'demo',
        text: '>_("demo")\n',
        revision: 1,
      ),
      activeFilePath: sourceFile.path,
    );
    expect(plainSession.status, ExecutionSessionStatus.succeeded);
    final plainArgv = jsonDecode(
      File('${tempRoot.path}${Platform.pathSeparator}argv.json').readAsStringSync(),
    ) as List<dynamic>;
    expect(
      plainArgv.where((arg) => '$arg'.startsWith('--emit-runtime-observation')),
      isEmpty,
    );
    expect(plainArgv, isNot(contains('--runtime-observation-mode')));
    expect(plainArgv, isNot(contains('--runtime-observation-capability')));
  });

  test('invalid runtime stream records no envelopes', () async {
    final tempRoot = await _createTempRoot('vityo_invalid_stream_test_');
    final sourceFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('>_("demo")\n');
    File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"
[[bin]]
name = "demo"
path = "src/main.styio"
''');
    await _writePafioExecutable(
      File(
        '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
      ),
      '''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)
if '--json' in sys.argv and 'run' in sys.argv:
    build = os.path.join(os.getcwd(), '.pafio', 'build', 'invalid')
    os.makedirs(build, exist_ok=True)
    events_path = os.path.join(build, 'runtime-events.jsonl')
    with open(events_path, 'w', encoding='utf-8') as fh:
        fh.write(json.dumps({'contract': 'styio.other', 'schema_version': 2, 'record_kind': 'session.capability', 'event_kind': 'session.capability', 'mode': 'detailed', 'snapshot_schema': 1, 'snapshot_id': 's1_0123456789abcdef0123456789abcdef', 'execution_id': 'x2_0000000000000001'}) + '\\n')
    with open(os.path.join(build, 'receipt.json'), 'w', encoding='utf-8') as fh:
        json.dump({'schema_version': 1, 'intent': 'run', 'session_id': 'invalid-session', 'executed': True, 'outputs': {'runtime_events_path': events_path}}, fh)
    print(json.dumps({
        'workflow_payload_version': 1,
        'message': 'invalid stream',
        'stdout': '',
        'stderr': '',
        'diagnostics': [],
        'runtime_session_id': 'invalid-session',
        'plan': {'build_root': build},
        'receipt': {'schema_version': 1, 'intent': 'run', 'session_id': 'invalid-session', 'executed': True},
    }))
    raise SystemExit(0)
raise SystemExit(64)
''',
    );
    final projectGraph = _projectGraph(
      workspaceRoot: tempRoot.path,
      manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
      targets: <ProjectTargetDescriptor>[
        ProjectTargetDescriptor(
          id: 'demo/app:bin:demo',
          packageName: 'demo/app',
          kind: ProjectTargetKind.bin,
          name: 'demo',
          filePath: sourceFile.path,
        ),
      ],
      packages: <ProjectPackageSnapshot>[
        _packageSnapshot(
          packageName: 'demo/app',
          rootPath: tempRoot.path,
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
          targets: <ProjectTargetDescriptor>[
            ProjectTargetDescriptor(
              id: 'demo/app:bin:demo',
              packageName: 'demo/app',
              kind: ProjectTargetKind.bin,
              name: 'demo',
              filePath: sourceFile.path,
            ),
          ],
        ),
      ],
      activeCompiler: _compilerSnapshot('/toolchains/styio/bin/styio'),
    );
    final adapter = await createExecutionAdapter(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
    );
    addTearDown(() => clearRuntimeEventsForSession('invalid-session'));
    final session = await adapter.runActiveDocument(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
      document: const DocumentState(
        documentId: 'demo',
        text: '>_("demo")\n',
        revision: 1,
      ),
      activeFilePath: sourceFile.path,
    );
    expect(session.status, ExecutionSessionStatus.succeeded);
    final events = await createRuntimeEventAdapter(
      platformTarget: PlatformTarget.macos,
    ).sessionEvents(session.sessionId).toList();
    expect(events, isEmpty);
  });

  test('plain run records disabled-mode controller events', () async {
    // The producer writes a v2 stream on every compile-plan run; without an
    // observation request the capability record carries mode `disabled` and
    // `snapshot_id: null`. That legal shape must not reject the stream, or
    // existing sessions would lose their controller events.
    final tempRoot = await _createTempRoot('vityo_disabled_mode_intake_test_');
    final sourceFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('>_("demo")\n');
    File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"
[[bin]]
name = "demo"
path = "src/main.styio"
''');
    await _writePafioExecutable(
      File(
        '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
      ),
      '''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)
if '--json' in sys.argv and 'run' in sys.argv:
    build = os.path.join(os.getcwd(), '.pafio', 'build', 'disabled-session')
    os.makedirs(build, exist_ok=True)
    events_path = os.path.join(build, 'runtime-events.jsonl')
    with open(events_path, 'w', encoding='utf-8') as fh:
        fh.write(json.dumps({
            'contract': 'styio.observable.runtime-events',
            'schema_version': 2,
            'record_kind': 'session.capability',
            'event_kind': 'session.capability',
            'mode': 'disabled',
            'snapshot_schema': 1,
            'snapshot_id': None,
            'execution_id': 'x2_0000000000000007',
            'privacy_profile': 'strict',
            'producer_lanes': 0,
            'lane_capacity': 256,
            'priority_reserved': 32,
            'drain_batch': 64,
            'sampling': {'numerator': 1, 'denominator': 16, 'seed': 0},
            'clock_unit': 'ns',
            'supported_capabilities': ['task-lifecycle', 'loss-accounting', 'strict-privacy'],
            'active_capabilities': [],
            'unavailable_capabilities': [],
        }) + '\\n')
        fh.write(json.dumps({
            'contract': 'styio.observable.runtime-events',
            'schema_version': 2,
            'record_kind': 'event',
            'event_kind': 'compile.started',
            'family': 'controller',
            'priority': 'lifecycle',
            'correlation_status': 'runtime_only',
            'role': 'runtime_only',
            'snapshot_id': None,
            'site_id': None,
            'instance_id': None,
            'event_id': 'r2_0000000000000071',
            'monotonic_ns': 10,
            'causes': [],
            'wait': None,
            'intent': 'run',
        }) + '\\n')
        fh.write(json.dumps({
            'contract': 'styio.observable.runtime-events',
            'schema_version': 2,
            'record_kind': 'event',
            'event_kind': 'transition.fired',
            'family': 'controller',
            'priority': 'lifecycle',
            'correlation_status': 'runtime_only',
            'role': 'runtime_only',
            'snapshot_id': None,
            'site_id': None,
            'instance_id': None,
            'event_id': 'r2_0000000000000072',
            'monotonic_ns': 20,
            'causes': [],
            'wait': None,
            'from_phase': 'parsed',
            'to_phase': 'typed',
            'operation': 'sema',
            'intent': 'run',
        }) + '\\n')
        fh.write(json.dumps({
            'contract': 'styio.observable.runtime-events',
            'schema_version': 2,
            'record_kind': 'session.summary',
            'event_kind': 'session.summary',
            'mode': 'disabled',
            'execution_id': 'x2_0000000000000007',
            'completeness': 'partial/disabled',
            'exporter_failed': False,
            'lane_capacity': 256,
            'priority_reserved': 32,
            'producer_lanes': 0,
            'high_water_occupancy': 0,
            'families': {},
        }) + '\\n')
    with open(os.path.join(build, 'receipt.json'), 'w', encoding='utf-8') as fh:
        json.dump({
            'schema_version': 1,
            'intent': 'run',
            'session_id': 'disabled-session',
            'executed': True,
            'outputs': {'runtime_events_path': events_path},
        }, fh)
    print(json.dumps({
        'workflow_payload_version': 1,
        'message': 'plain run',
        'stdout': '',
        'stderr': '',
        'diagnostics': [],
        'runtime_session_id': 'disabled-session',
        'plan': {'build_root': build},
        'receipt': {'schema_version': 1, 'intent': 'run', 'session_id': 'disabled-session', 'executed': True},
    }))
    raise SystemExit(0)
raise SystemExit(64)
''',
    );
    final projectGraph = _projectGraph(
      workspaceRoot: tempRoot.path,
      manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
      targets: <ProjectTargetDescriptor>[
        ProjectTargetDescriptor(
          id: 'demo/app:bin:demo',
          packageName: 'demo/app',
          kind: ProjectTargetKind.bin,
          name: 'demo',
          filePath: sourceFile.path,
        ),
      ],
      packages: <ProjectPackageSnapshot>[
        _packageSnapshot(
          packageName: 'demo/app',
          rootPath: tempRoot.path,
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
          targets: <ProjectTargetDescriptor>[
            ProjectTargetDescriptor(
              id: 'demo/app:bin:demo',
              packageName: 'demo/app',
              kind: ProjectTargetKind.bin,
              name: 'demo',
              filePath: sourceFile.path,
            ),
          ],
        ),
      ],
      activeCompiler: _compilerSnapshot('/toolchains/styio/bin/styio'),
    );
    final adapter = await createExecutionAdapter(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
    );
    addTearDown(() => clearRuntimeEventsForSession('disabled-session'));
    final session = await adapter.runActiveDocument(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
      document: const DocumentState(
        documentId: 'demo',
        text: '>_("demo")\n',
        revision: 1,
      ),
      activeFilePath: sourceFile.path,
    );
    expect(session.status, ExecutionSessionStatus.succeeded);
    final events = await createRuntimeEventAdapter(
      platformTarget: PlatformTarget.macos,
    ).sessionEvents(session.sessionId).toList();
    expect(events.map((event) => event.eventKind), <String>[
      'session.capability',
      'compile.started',
      'transition.fired',
      'session.summary',
    ]);
    expect(events.first.schemaVersion, 2);
    expect(events.first.payload['mode'], 'disabled');
    expect(events.first.payload['snapshot_id'], isNull);
    final transition = events.firstWhere(
      (event) => event.eventKind == 'transition.fired',
    );
    expect(transition.payload['from_phase'], 'parsed');
    expect(transition.payload['to_phase'], 'typed');
  });

  test('missing receipt returns no artifact and no envelopes', () async {
    final tempRoot = await _createTempRoot('vityo_missing_receipt_test_');
    final sourceFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('>_("demo")\n');
    File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"
[[bin]]
name = "demo"
path = "src/main.styio"
''');
    await _writePafioExecutable(
      File(
        '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
      ),
      '''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)
if '--json' in sys.argv and 'run' in sys.argv:
    build = os.path.join(os.getcwd(), '.pafio', 'build', 'missing-receipt')
    os.makedirs(build, exist_ok=True)
    events_path = os.path.join(build, 'runtime-events.jsonl')
    with open(events_path, 'w', encoding='utf-8') as fh:
        fh.write(json.dumps({
            'contract': 'styio.observable.runtime-events',
            'schema_version': 2,
            'record_kind': 'session.capability',
            'event_kind': 'session.capability',
            'mode': 'detailed',
            'snapshot_schema': 1,
            'snapshot_id': 's1_0123456789abcdef0123456789abcdef',
            'execution_id': 'x2_0000000000000001',
        }) + '\\n')
    print(json.dumps({
        'workflow_payload_version': 1,
        'message': 'missing receipt',
        'stdout': '',
        'stderr': '',
        'diagnostics': [],
        'runtime_session_id': 'missing-receipt-session',
        'plan': {'build_root': build},
        'receipt': {'schema_version': 1, 'intent': 'run', 'session_id': 'missing-receipt-session', 'executed': True},
    }))
    raise SystemExit(0)
raise SystemExit(64)
''',
    );
    final projectGraph = _projectGraph(
      workspaceRoot: tempRoot.path,
      manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
      targets: <ProjectTargetDescriptor>[
        ProjectTargetDescriptor(
          id: 'demo/app:bin:demo',
          packageName: 'demo/app',
          kind: ProjectTargetKind.bin,
          name: 'demo',
          filePath: sourceFile.path,
        ),
      ],
      packages: <ProjectPackageSnapshot>[
        _packageSnapshot(
          packageName: 'demo/app',
          rootPath: tempRoot.path,
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
          targets: <ProjectTargetDescriptor>[
            ProjectTargetDescriptor(
              id: 'demo/app:bin:demo',
              packageName: 'demo/app',
              kind: ProjectTargetKind.bin,
              name: 'demo',
              filePath: sourceFile.path,
            ),
          ],
        ),
      ],
      activeCompiler: _compilerSnapshot(
        '/toolchains/styio/bin/styio',
        contracts: const <String, List<int>>{
          'machine_info': <int>[1],
          'compile_plan': <int>[1],
          'runtime_events': <int>[2],
        },
      ),
    );
    final adapter = await createExecutionAdapter(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
    );
    addTearDown(() => clearRuntimeEventsForSession('missing-receipt-session'));
    final run = await (adapter as ObservedExecutionAdapter)
        .runActiveDocumentObserved(
          platformTarget: PlatformTarget.macos,
          projectGraph: projectGraph,
          document: const DocumentState(
            documentId: 'demo',
            text: '>_("demo")\n',
            revision: 1,
          ),
          activeFilePath: sourceFile.path,
          observation: const RuntimeObservationRequest(
            mode: RuntimeObservationMode.aggregate,
          ),
        );
    expect(run.session.status, ExecutionSessionStatus.succeeded);
    expect(run.runtimeEventsPath, isNull);
    final events = await createRuntimeEventAdapter(
      platformTarget: PlatformTarget.macos,
    ).sessionEvents(run.session.sessionId).toList();
    expect(events, isEmpty);
    await run.release();
  });

  test('artifact outside the workspace tree is ignored', () async {
    final tempRoot = await _createTempRoot('vityo_outside_artifact_test_');
    final outsideRoot = Directory(
      '${tempRoot.parent.path}${Platform.pathSeparator}'
      '${tempRoot.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty)}-outside-artifact',
    );
    addTearDown(() async {
      if (await outsideRoot.exists()) {
        await outsideRoot.delete(recursive: true);
      }
    });
    final sourceFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('>_("demo")\n');
    File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"
[[bin]]
name = "demo"
path = "src/main.styio"
''');
    await _writePafioExecutable(
      File(
        '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
      ),
      '''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)
if '--json' in sys.argv and 'run' in sys.argv:
    build = os.path.join(os.getcwd(), '.pafio', 'build', 'outside')
    os.makedirs(build, exist_ok=True)
    sibling = os.path.join(
        os.path.dirname(os.getcwd()), os.path.basename(os.getcwd()) + '-outside-artifact')
    os.makedirs(sibling, exist_ok=True)
    events_path = os.path.join(sibling, 'runtime-events.jsonl')
    with open(events_path, 'w', encoding='utf-8') as fh:
        fh.write(json.dumps({
            'contract': 'styio.observable.runtime-events',
            'schema_version': 2,
            'record_kind': 'session.capability',
            'event_kind': 'session.capability',
            'mode': 'detailed',
            'snapshot_schema': 1,
            'snapshot_id': 's1_0123456789abcdef0123456789abcdef',
            'execution_id': 'x2_0000000000000001',
        }) + '\\n')
    with open(os.path.join(build, 'receipt.json'), 'w', encoding='utf-8') as fh:
        json.dump({
            'schema_version': 1,
            'intent': 'run',
            'session_id': 'outside-artifact-session',
            'executed': True,
            'outputs': {'runtime_events_path': events_path},
        }, fh)
    print(json.dumps({
        'workflow_payload_version': 1,
        'message': 'outside artifact',
        'stdout': '',
        'stderr': '',
        'diagnostics': [],
        'runtime_session_id': 'outside-artifact-session',
        'plan': {'build_root': build},
        'receipt': {'schema_version': 1, 'intent': 'run', 'session_id': 'outside-artifact-session', 'executed': True},
    }))
    raise SystemExit(0)
raise SystemExit(64)
''',
    );
    final projectGraph = _projectGraph(
      workspaceRoot: tempRoot.path,
      manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
      targets: <ProjectTargetDescriptor>[
        ProjectTargetDescriptor(
          id: 'demo/app:bin:demo',
          packageName: 'demo/app',
          kind: ProjectTargetKind.bin,
          name: 'demo',
          filePath: sourceFile.path,
        ),
      ],
      packages: <ProjectPackageSnapshot>[
        _packageSnapshot(
          packageName: 'demo/app',
          rootPath: tempRoot.path,
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
          targets: <ProjectTargetDescriptor>[
            ProjectTargetDescriptor(
              id: 'demo/app:bin:demo',
              packageName: 'demo/app',
              kind: ProjectTargetKind.bin,
              name: 'demo',
              filePath: sourceFile.path,
            ),
          ],
        ),
      ],
      activeCompiler: _compilerSnapshot(
        '/toolchains/styio/bin/styio',
        contracts: const <String, List<int>>{
          'machine_info': <int>[1],
          'compile_plan': <int>[1],
          'runtime_events': <int>[2],
        },
      ),
    );
    final adapter = await createExecutionAdapter(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
    );
    addTearDown(() => clearRuntimeEventsForSession('outside-artifact-session'));
    final run = await (adapter as ObservedExecutionAdapter)
        .runActiveDocumentObserved(
          platformTarget: PlatformTarget.macos,
          projectGraph: projectGraph,
          document: const DocumentState(
            documentId: 'demo',
            text: '>_("demo")\n',
            revision: 1,
          ),
          activeFilePath: sourceFile.path,
          observation: const RuntimeObservationRequest(
            mode: RuntimeObservationMode.aggregate,
          ),
        );
    expect(run.session.status, ExecutionSessionStatus.succeeded);
    expect(run.runtimeEventsPath, isNull);
    final events = await createRuntimeEventAdapter(
      platformTarget: PlatformTarget.macos,
    ).sessionEvents(run.session.sessionId).toList();
    expect(events, isEmpty);
    await run.release();
  });

  test('foreign build root cannot consume same-suffix local receipt', () async {
    final tempRoot = await _createTempRoot('vityo_outside_artifact_test_');
    final foreignRoot = Directory(
      '${tempRoot.parent.path}${Platform.pathSeparator}'
      '${tempRoot.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty)}-foreign',
    );
    addTearDown(() async {
      if (await foreignRoot.exists()) {
        await foreignRoot.delete(recursive: true);
      }
    });
    final sourceFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('>_("demo")\n');
    File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"
[[bin]]
name = "demo"
path = "src/main.styio"
''');
    await _writePafioExecutable(
      File(
        '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
      ),
      '''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)
if '--json' in sys.argv and 'run' in sys.argv:
    suffix = os.path.join('.pafio', 'build', 'shared-session')
    local_build = os.path.join(os.getcwd(), suffix)
    foreign_root = os.path.join(
        os.path.dirname(os.getcwd()), os.path.basename(os.getcwd()) + '-foreign')
    foreign_build = os.path.join(foreign_root, suffix)
    os.makedirs(local_build, exist_ok=True)
    os.makedirs(foreign_build, exist_ok=True)
    events_path = os.path.join(local_build, 'runtime-events.jsonl')
    with open(events_path, 'w', encoding='utf-8') as fh:
        fh.write(json.dumps({
            'contract': 'styio.observable.runtime-events',
            'schema_version': 2,
            'record_kind': 'session.capability',
            'event_kind': 'session.capability',
            'mode': 'detailed',
            'snapshot_schema': 1,
            'snapshot_id': 's1_0123456789abcdef0123456789abcdef',
            'execution_id': 'x2_0000000000000001',
        }) + '\\n')
    with open(os.path.join(local_build, 'receipt.json'), 'w', encoding='utf-8') as fh:
        json.dump({
            'schema_version': 1,
            'intent': 'run',
            'session_id': 'outside-session',
            'executed': True,
            'outputs': {'runtime_events_path': events_path},
        }, fh)
    print(json.dumps({
        'workflow_payload_version': 1,
        'message': 'outside artifact',
        'stdout': '',
        'stderr': '',
        'diagnostics': [],
        'runtime_session_id': 'outside-session',
        'plan': {'build_root': foreign_build},
        'receipt': {'schema_version': 1, 'intent': 'run', 'session_id': 'outside-session', 'executed': True},
    }))
    raise SystemExit(0)
raise SystemExit(64)
''',
    );
    final projectGraph = _projectGraph(
      workspaceRoot: tempRoot.path,
      manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
      targets: <ProjectTargetDescriptor>[
        ProjectTargetDescriptor(
          id: 'demo/app:bin:demo',
          packageName: 'demo/app',
          kind: ProjectTargetKind.bin,
          name: 'demo',
          filePath: sourceFile.path,
        ),
      ],
      packages: <ProjectPackageSnapshot>[
        _packageSnapshot(
          packageName: 'demo/app',
          rootPath: tempRoot.path,
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
          targets: <ProjectTargetDescriptor>[
            ProjectTargetDescriptor(
              id: 'demo/app:bin:demo',
              packageName: 'demo/app',
              kind: ProjectTargetKind.bin,
              name: 'demo',
              filePath: sourceFile.path,
            ),
          ],
        ),
      ],
      activeCompiler: _compilerSnapshot(
        '/toolchains/styio/bin/styio',
        contracts: const <String, List<int>>{
          'machine_info': <int>[1],
          'compile_plan': <int>[1],
          'runtime_events': <int>[2],
        },
      ),
    );
    final adapter = await createExecutionAdapter(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
    );
    addTearDown(() => clearRuntimeEventsForSession('outside-session'));
    final run = await (adapter as ObservedExecutionAdapter)
        .runActiveDocumentObserved(
          platformTarget: PlatformTarget.macos,
          projectGraph: projectGraph,
          document: const DocumentState(
            documentId: 'demo',
            text: '>_("demo")\n',
            revision: 1,
          ),
          activeFilePath: sourceFile.path,
          observation: const RuntimeObservationRequest(
            mode: RuntimeObservationMode.aggregate,
          ),
        );
    expect(run.session.status, ExecutionSessionStatus.succeeded);
    expect(run.runtimeEventsPath, isNull);
    final events = await createRuntimeEventAdapter(
      platformTarget: PlatformTarget.macos,
    ).sessionEvents(run.session.sessionId).toList();
    expect(events, isEmpty);
    await run.release();
  });

  test('observed overlay directory lives until release', () async {
    final tempRoot = await _createTempRoot('vityo_overlay_release_test_');
    final sourceFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('>_("demo")\n');
    File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"
[[bin]]
name = "demo"
path = "src/main.styio"
''');
    await _writePafioExecutable(
      File(
        '${tempRoot.path}${Platform.pathSeparator}.pafio${Platform.pathSeparator}bin${Platform.pathSeparator}pafio',
      ),
      '''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ['--version']:
    print('pafio 1.0.0')
    raise SystemExit(0)
if '--json' in sys.argv and 'run' in sys.argv:
    build = os.path.join(os.getcwd(), '.pafio', 'build', 'overlay-session')
    os.makedirs(build, exist_ok=True)
    events_path = os.path.join(build, 'runtime-events.jsonl')
    with open(events_path, 'w', encoding='utf-8') as fh:
        fh.write(json.dumps({
            'contract': 'styio.observable.runtime-events',
            'schema_version': 2,
            'record_kind': 'session.capability',
            'event_kind': 'session.capability',
            'mode': 'aggregate',
            'snapshot_schema': 1,
            'snapshot_id': 's1_0123456789abcdef0123456789abcdef',
            'execution_id': 'x2_0000000000000001',
            'privacy_profile': 'strict',
            'producer_lanes': 1,
            'lane_capacity': 256,
            'priority_reserved': 32,
            'drain_batch': 64,
            'sampling': {'numerator': 1, 'denominator': 16, 'seed': 0},
            'clock_unit': 'ns',
            'supported_capabilities': ['task-lifecycle', 'loss-accounting', 'strict-privacy'],
            'active_capabilities': ['task-lifecycle', 'loss-accounting', 'strict-privacy'],
            'unavailable_capabilities': [],
        }) + '\\n')
    with open(os.path.join(build, 'receipt.json'), 'w', encoding='utf-8') as fh:
        json.dump({
            'schema_version': 1,
            'intent': 'run',
            'session_id': 'overlay-session',
            'executed': True,
            'outputs': {'runtime_events_path': events_path},
        }, fh)
    print(json.dumps({
        'workflow_payload_version': 1,
        'message': 'overlay run',
        'stdout': '',
        'stderr': '',
        'diagnostics': [],
        'runtime_session_id': 'overlay-session',
        'plan': {'build_root': build},
        'receipt': {'schema_version': 1, 'intent': 'run', 'session_id': 'overlay-session', 'executed': True},
    }))
    raise SystemExit(0)
raise SystemExit(64)
''',
    );
    final projectGraph = _projectGraph(
      workspaceRoot: tempRoot.path,
      manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
      targets: <ProjectTargetDescriptor>[
        ProjectTargetDescriptor(
          id: 'demo/app:bin:demo',
          packageName: 'demo/app',
          kind: ProjectTargetKind.bin,
          name: 'demo',
          filePath: sourceFile.path,
        ),
      ],
      packages: <ProjectPackageSnapshot>[
        _packageSnapshot(
          packageName: 'demo/app',
          rootPath: tempRoot.path,
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}pafio.toml',
          targets: <ProjectTargetDescriptor>[
            ProjectTargetDescriptor(
              id: 'demo/app:bin:demo',
              packageName: 'demo/app',
              kind: ProjectTargetKind.bin,
              name: 'demo',
              filePath: sourceFile.path,
            ),
          ],
        ),
      ],
      activeCompiler: _compilerSnapshot(
        '/toolchains/styio/bin/styio',
        contracts: const <String, List<int>>{
          'machine_info': <int>[1],
          'compile_plan': <int>[1],
          'runtime_events': <int>[2],
        },
      ),
    );
    final adapter = await createExecutionAdapter(
      platformTarget: PlatformTarget.macos,
      projectGraph: projectGraph,
    );
    addTearDown(() => clearRuntimeEventsForSession('overlay-session'));
    final run = await (adapter as ObservedExecutionAdapter)
        .runActiveDocumentObserved(
          platformTarget: PlatformTarget.macos,
          projectGraph: projectGraph,
          document: const DocumentState(
            documentId: 'demo',
            text: '>_("dirty")\n',
            revision: 2,
          ),
          activeFilePath: sourceFile.path,
          observation: const RuntimeObservationRequest(
            mode: RuntimeObservationMode.aggregate,
          ),
        );
    expect(run.session.status, ExecutionSessionStatus.succeeded);
    final workspaceName = tempRoot.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
    );
    final overlayPrefix = 'Vityo-$workspaceName-';
    final overlays = Directory(tempRoot.parent.path)
        .listSync()
        .whereType<Directory>()
        .where(
          (directory) => directory.uri.pathSegments
              .lastWhere((segment) => segment.isNotEmpty)
              .startsWith(overlayPrefix),
        )
        .toList();
    expect(overlays, isNotEmpty);
    final overlay = overlays.single;
    expect(overlay.existsSync(), isTrue);
    await run.release();
    expect(overlay.existsSync(), isFalse);
  });
}

Future<Directory> _createTempRoot(String prefix) async {
  final createdTempRoot = await Directory.systemTemp.createTemp(prefix);
  final tempRoot = Directory(await createdTempRoot.resolveSymbolicLinks());
  addTearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  final previousCurrentDirectory = Directory.current;
  addTearDown(() => Directory.current = previousCurrentDirectory);
  Directory.current = tempRoot;
  return tempRoot;
}

Future<File> _writeExecutable(File file, String contents) async {
  if (Platform.isWindows) {
    final script = File('${file.path}.py');
    await script.create(recursive: true);
    await script.writeAsString(contents);
    final launcher = File('${file.path}.cmd');
    await launcher.writeAsString(
      '@echo off\r\npython "%~dp0${script.uri.pathSegments.last}" %*\r\n',
    );
    return launcher;
  }

  await file.create(recursive: true);
  await file.writeAsString(contents);
  Process.runSync('chmod', <String>['+x', file.path]);
  return file;
}

Future<File> _writePafioExecutable(File file, String contents) async {
  final executable = await _writeExecutable(file, contents);
  debugOverridePafioExecutableCandidates(<String>[executable.path]);
  addTearDown(() => debugOverridePafioExecutableCandidates(null));
  return executable;
}

CompilerHandshakeSnapshot _compilerSnapshot(
  String binaryPath, {
  Map<String, List<int>> contracts = const <String, List<int>>{
    'machine_info': <int>[1],
    'compile_plan': <int>[1],
  },
}) {
  return CompilerHandshakeSnapshot(
    binaryPath: binaryPath,
    tool: 'styio',
    compilerVersion: '0.0.5',
    channel: 'stable',
    variant: 'desktop',
    capabilities: const <String>[
      'machine_info_json',
      'single_file_entry',
      'jsonl_diagnostics',
      'compile_plan_consumer',
    ],
    supportedContractVersions: contracts,
    integrationPhase: 'compile-plan-live',
    featureFlags: const <String, bool>{'compile_plan_consumer': true},
  );
}

ProjectPackageSnapshot _packageSnapshot({
  required String packageName,
  required String rootPath,
  required String manifestPath,
  required List<ProjectTargetDescriptor> targets,
}) {
  return ProjectPackageSnapshot(
    packageName: packageName,
    version: '0.1.0',
    rootPath: rootPath,
    manifestPath: manifestPath,
    targets: targets,
  );
}

ProjectGraphSnapshot _projectGraph({
  required String workspaceRoot,
  required String manifestPath,
  required List<ProjectTargetDescriptor> targets,
  required List<ProjectPackageSnapshot> packages,
  required CompilerHandshakeSnapshot activeCompiler,
}) {
  return ProjectGraphSnapshot(
    id: manifestPath,
    title: packages.isEmpty ? 'demo/app' : packages.first.packageName,
    kind: ProjectKind.package,
    workspaceRoot: workspaceRoot,
    workspaceMembers: const <String>[],
    manifestPath: manifestPath,
    lockfilePath: '$workspaceRoot${Platform.pathSeparator}pafio.lock',
    vendorRoot:
        '$workspaceRoot${Platform.pathSeparator}.pafio${Platform.pathSeparator}vendor',
    packages: packages,
    dependencies: const <ProjectDependencySnapshot>[],
    targets: targets,
    editorFiles: targets
        .map((target) => target.filePath)
        .toList(growable: false),
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.environment,
      detail: 'project pin',
    ),
    lockState: ProjectLockState.missing,
    vendorState: ProjectVendorState.missing,
    activeCompiler: activeCompiler,
    notes: const <String>[],
  );
}
