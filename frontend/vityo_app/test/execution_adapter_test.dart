import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/hosted_control_plane.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/backend_toolchain/runtime_event_adapter.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test(
    'execution adapter prefers published spio workflow payloads and preserves JSON program output',
    () async {
      final tempRoot = await _createTempRoot(
        'vityo_execution_payload_test_',
      );
      final sourceFile =
          File(
              '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('>_("demo")\n');

      File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[toolchain]
channel = "stable"
implicit-std = true

[[bin]]
name = "demo"
path = "src/main.styio"
''');

      await _writeExecutable(
        File(
          '${tempRoot.path}${Platform.pathSeparator}.spio${Platform.pathSeparator}bin${Platform.pathSeparator}spio',
        ),
        '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'feature_flags': {'workflow_success_payloads': True},
        'supported_contract_versions': {'workflow_success_payloads': [1]},
    }))
    raise SystemExit(0)

if '--json' in sys.argv and 'run' in sys.argv:
    if '--package' not in sys.argv or sys.argv[sys.argv.index('--package') + 1] != 'demo/app':
        raise SystemExit(65)
    if '--bin' not in sys.argv or sys.argv[sys.argv.index('--bin') + 1] != 'demo':
        raise SystemExit(66)
    print(json.dumps({
        'command': 'run',
        'mode': 'execute',
        'workflow_payload_version': 1,
        'message': 'completed compiler run via payload',
        'stdout': '{"message":"user-log"}\\n{"a":1}\\nspio-run-ok\\n',
        'stderr': '',
        'diagnostics': [],
        'runtime_session_id': 'runtime-session-1',
        'runtime_events': [
            {
                'schema_version': 1,
                'session_id': 'runtime-session-1',
                'sequence': 1,
                'timestamp': '2026-04-17T00:00:00Z',
                'eventKind': 'compile.started',
                'origin': 'styio.compile-plan',
                'payload': {'intent': 'run'},
            },
            {
                'schema_version': 1,
                'session_id': 'runtime-session-1',
                'sequence': 2,
                'timestamp': '2026-04-17T00:00:01Z',
                'eventKind': 'run.finished',
                'origin': 'styio.runtime',
                'payload': {'file': ${jsonEncode(sourceFile.path)}, 'success': True},
            },
        ],
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
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}spio.toml',
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
                  '${tempRoot.path}${Platform.pathSeparator}spio.toml',
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
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}spio.toml',
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
                  '${tempRoot.path}${Platform.pathSeparator}spio.toml',
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
          'spio-run-ok',
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
        'compile.started',
        'run.finished',
      ]);
      expect(runtimeEvents.last.payload['file'], sourceFile.path);
    },
  );

  test(
    'execution adapter falls back to package build for non-entry project files',
    () async {
      final tempRoot = await _createTempRoot(
        'vityo_execution_non_entry_test_',
      );
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

      File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[toolchain]
channel = "stable"
implicit-std = true

[lib]
path = "src/lib.styio"

[[bin]]
name = "demo"
path = "src/main.styio"
''');

      await _writeExecutable(
        File(
          '${tempRoot.path}${Platform.pathSeparator}.spio${Platform.pathSeparator}bin${Platform.pathSeparator}spio',
        ),
        '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'feature_flags': {'workflow_success_payloads': True},
        'supported_contract_versions': {'workflow_success_payloads': [1]},
    }))
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
        manifestPath: '${tempRoot.path}${Platform.pathSeparator}spio.toml',
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
            manifestPath: '${tempRoot.path}${Platform.pathSeparator}spio.toml',
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

  test('execution adapter surfaces structured spio failure payloads', () async {
    final tempRoot = await _createTempRoot(
      'vityo_execution_failure_payload_test_',
    );
    final sourceFile =
        File(
            '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('>_("demo")\n');

    File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[toolchain]
channel = "stable"
implicit-std = true

[[bin]]
name = "demo"
path = "src/main.styio"
''');

    await _writeExecutable(
      File(
        '${tempRoot.path}${Platform.pathSeparator}.spio${Platform.pathSeparator}bin${Platform.pathSeparator}spio',
      ),
      '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'feature_flags': {'workflow_success_payloads': True},
        'supported_contract_versions': {'workflow_success_payloads': [1]},
    }))
    raise SystemExit(0)

if '--json' in sys.argv and 'run' in sys.argv:
    sys.stderr.write(json.dumps({
        'category': 'CompilerError',
        'code': 23,
        'message': 'compile-plan failed through payload',
        'command': 'run',
        'runtime_session_id': 'runtime-session-failure',
        'runtime_events': [
            {
                'schema_version': 1,
                'session_id': 'runtime-session-failure',
                'sequence': 1,
                'timestamp': '2026-04-17T00:00:00Z',
                'eventKind': 'compile.started',
                'origin': 'styio.compile-plan',
                'payload': {'intent': 'run'},
            },
            {
                'schema_version': 1,
                'session_id': 'runtime-session-failure',
                'sequence': 2,
                'timestamp': '2026-04-17T00:00:01Z',
                'eventKind': 'compile.failed',
                'origin': 'styio.compile-plan',
                'payload': {'intent': 'run', 'executed': False},
            },
        ],
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
      manifestPath: '${tempRoot.path}${Platform.pathSeparator}spio.toml',
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
          manifestPath: '${tempRoot.path}${Platform.pathSeparator}spio.toml',
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

      expect(session.status, ExecutionSessionStatus.succeeded);
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

      expect(session.status, ExecutionSessionStatus.succeeded);
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

      File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[toolchain]
channel = "stable"
implicit-std = true

[[bin]]
name = "demo"
path = "src/main.styio"
''');

      await _writeExecutable(
        File(
          '${tempRoot.path}${Platform.pathSeparator}.spio${Platform.pathSeparator}bin${Platform.pathSeparator}spio',
        ),
        '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'feature_flags': {'workflow_success_payloads': True},
        'supported_contract_versions': {'workflow_success_payloads': [1]},
    }))
    raise SystemExit(0)

raise SystemExit(66)
''',
      );

      final projectGraph = _projectGraph(
        workspaceRoot: tempRoot.path,
        manifestPath: '${tempRoot.path}${Platform.pathSeparator}spio.toml',
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
            manifestPath: '${tempRoot.path}${Platform.pathSeparator}spio.toml',
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

  test('execution adapter exposes blocked platform and compiler branches', () async {
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

    final manifestPath = '${tempRoot.path}${Platform.pathSeparator}spio.toml';
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
    final blockedCompilePlan = await blockedCompilePlanAdapter.runActiveDocument(
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

    final missingSpioGraph = _projectGraph(
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
    final missingSpioAdapter = await createExecutionAdapter(
      platformTarget: PlatformTarget.macos,
      projectGraph: missingSpioGraph,
    );
    final missingSpio = await missingSpioAdapter.runActiveDocument(
      platformTarget: PlatformTarget.macos,
      projectGraph: missingSpioGraph,
      document: const DocumentState(
        documentId: 'scratch',
        text: '>_("demo")\n',
        revision: 1,
      ),
      activeFilePath: sourceFile.path,
    );
    expect(missingSpio.status, ExecutionSessionStatus.blocked);
    expect(missingSpio.sessionId, 'missing-spio-binary');
  });

  test('single-file execution writes relative documents to temporary inputs', () async {
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
        jsonDecode(session.stdoutEvents.single.message) as Map<String, dynamic>;
    expect(payload['basename'], 'main.styio');
    expect(payload['text'], '>_("relative")\n');
    expect(File(payload['path'] as String).existsSync(), isFalse);
  });

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
      final manifestPath = '${tempRoot.path}${Platform.pathSeparator}spio.toml';
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
      await _writeExecutable(
        File(
          '${tempRoot.path}${Platform.pathSeparator}.spio${Platform.pathSeparator}bin${Platform.pathSeparator}spio',
        ),
        '''#!/usr/bin/env python3
import json, os, sys

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'supported_contract_versions': {'workflow_success_payloads': [1]},
    }))
    raise SystemExit(0)

if '--json' in sys.argv and 'test' in sys.argv:
    manifest = sys.argv[sys.argv.index('--manifest-path') + 1]
    root = os.path.dirname(manifest)
    active = os.path.join(root, 'tests', 'render_test.styio')
    artifact_dir = os.path.join(root, 'artifacts')
    os.makedirs(artifact_dir, exist_ok=True)
    diagnostics_path = os.path.join(artifact_dir, 'diagnostics.jsonl')
    events_path = os.path.join(artifact_dir, 'events.jsonl')
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
    with open(events_path, 'w', encoding='utf-8') as events:
        events.write('\\n')
        events.write('not-json\\n')
        events.write(json.dumps({
            'schemaVersion': 2,
            'sessionId': 'artifact-session',
            'sequence': '4',
            'timestamp': 'not-a-date',
            'event_kind': 'compile.finished',
            'payload': {'file': active},
        }) + '\\n')
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
        'runtime_events_path': 'artifacts/events.jsonl',
        'receipt': {'sessionId': 'artifact-session'},
    }))
    raise SystemExit(0)

if '--json' in sys.argv and 'build' in sys.argv and '--lib' in sys.argv:
    print(json.dumps({
        'workflow_payload_version': 1,
        'message': 'library build completed',
        'stdout': 'lib stdout\\n',
        'stderr': '',
        'diagnostics': [],
        'runtime_events': [],
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
      expect(testSession.diagnostics.first.severity, DiagnosticSeverity.warning);
      expect(testSession.diagnostics.first.code, '99');
      expect(testSession.diagnostics.first.range.start, 4);
      expect(testSession.diagnostics.first.range.end, 8);
      expect(testSession.diagnostics[1].range.start, 7);
      expect(testSession.diagnostics[1].range.end, 7);

      final runtimeEvents = await createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      ).sessionEvents('artifact-session').toList();
      expect(runtimeEvents, hasLength(1));
      expect(runtimeEvents.single.schemaVersion, 2);
      expect(runtimeEvents.single.sessionId, 'artifact-session');
      expect(runtimeEvents.single.sequence, 1);
      expect(runtimeEvents.single.eventKind, 'compile.finished');
      expect(
        _comparableExistingPath(runtimeEvents.single.payload['file'] as String),
        _comparableExistingPath(testFile.path),
      );
      expect(
        runtimeEvents.single.timestamp,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
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
}

Future<Directory> _createTempRoot(String prefix) async {
  final tempRoot = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() => tempRoot.delete(recursive: true));

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
    await launcher.writeAsString('@echo off\r\npython "%~dp0${script.uri.pathSegments.last}" %*\r\n');
    return launcher;
  }

  await file.create(recursive: true);
  await file.writeAsString(contents);
  Process.runSync('chmod', <String>['+x', file.path]);
  return file;
}

String _comparableExistingPath(String path) {
  String resolved;
  try {
    resolved = File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    resolved = path;
  }
  return Platform.isWindows ? resolved.toLowerCase() : resolved;
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
    lockfilePath: '$workspaceRoot${Platform.pathSeparator}spio.lock',
    toolchainPinPath:
        '$workspaceRoot${Platform.pathSeparator}spio-toolchain.toml',
    vendorRoot:
        '$workspaceRoot${Platform.pathSeparator}.spio${Platform.pathSeparator}vendor',
    buildRoot:
        '$workspaceRoot${Platform.pathSeparator}.spio${Platform.pathSeparator}build',
    packages: packages,
    dependencies: const <ProjectDependencySnapshot>[],
    targets: targets,
    editorFiles: targets
        .map((target) => target.filePath)
        .toList(growable: false),
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'project pin',
    ),
    lockState: ProjectLockState.missing,
    vendorState: ProjectVendorState.missing,
    activeCompiler: activeCompiler,
    notes: const <String>[],
  );
}
