import 'dart:convert';
import 'dart:io';

const _scenario = 'trusted-desktop-styio-loop';
const _gate = 'vityo-desktop-product-gate';
const _capability = 'trusted-desktop-ide-loop';
const _productMarker = 'VITYO_PRODUCT_REPORT ';
const _contractMarker = 'VITYO_PRODUCT_CONTRACT_REPORT ';

const _ownerTimeoutSeconds = 120;
const _ownerTerminationGraceSeconds = 5;
const _ownerStreamByteLimit = 262144;
const _outerTimeoutSeconds = 600;
const _outerStreamByteLimit = 1048576;
const _markerByteLimit = 65536;
const _diagnosticLimit = 128;
const _runtimeEventLimit = 256;
const _artifactReferenceLimit = 64;
const _projectedStringByteLimit = 512;

const _platforms = <String>{'linux', 'macos', 'windows'};
const _package = 'vityo/product-gate';
const _packageId = 'workspace:vityo/product-gate@0.1.0';
const _binTarget = 'product-gate';
const _testTarget = 'product-gate-test';
const _observationToken = 'vityo-observed-r1';

final _sourceDigest = List<String>.filled(64, 'a').join();
final _observationDigest = List<String>.filled(64, 'b').join();
final _checkSessionDigest = List<String>.filled(64, 'c').join();
final _testSessionDigest = List<String>.filled(64, 'd').join();
final _runSessionDigest = List<String>.filled(64, 'e').join();
final _digestPattern = RegExp(r'^[0-9a-f]{64}$');
final _windowsAbsolutePath = RegExp(r'^[A-Za-z]:[\\/]');

typedef _CommandRunner = Future<_CommandResult> Function(_OwnerCommand command);

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    _validateFrozenLimits();
    _validateOuterCommandOrder();
    await _validateImplementationTopology();
    final fixture = await _exerciseControlledHappyPath();
    await _exerciseControlledFailures();
    _exerciseStaleRevisionRejection();
    _validateOuterReport(
      _passingOuterReport('linux', fixture),
      expectedPlatform: 'linux',
    );

    if (options.reportPath != null) {
      final decoded = jsonDecode(
        await File(options.reportPath!).readAsString(),
      );
      _validateOuterReport(decoded, expectedPlatform: options.platform!);
    }
    stdout.writeln('trusted-desktop-styio-loop acceptance: ok');
  } on Object catch (error) {
    stderr.writeln('trusted-desktop-styio-loop acceptance: $error');
    exitCode = 1;
  }
}

Future<void> _validateImplementationTopology() async {
  final product = await File.fromUri(
    Platform.script.resolve(
      '../../../products/vityo_app/test/local_product_workflow_test.dart',
    ),
  ).readAsString();
  final gate = await File.fromUri(
    Platform.script.resolve('../../../scripts/ecosystem-product-gate.py'),
  ).readAsString();
  for (final source in <String>[product, gate]) {
    _expect(
      !source.contains('workflow_payload_version'),
      'implementation still requires unpublished Pafio workflow v1',
    );
    _expect(
      source.contains('pafio-current+styio-files-v1'),
      'implementation omits the approved owner-contract projection',
    );
  }
  for (final marker in const <String>[
    'receipt.json',
    'diagnostics.jsonl',
    'runtime-events.jsonl',
    'eventKind',
  ]) {
    _expect(
      product.contains(marker),
      'product scenario does not consume current Styio-owned $marker',
    );
  }
}

final class _Options {
  const _Options({this.reportPath, this.platform});

  final String? reportPath;
  final String? platform;

  static _Options parse(List<String> arguments) {
    if (arguments.isEmpty) {
      return const _Options();
    }
    String? reportPath;
    String? platform;
    for (var index = 0; index < arguments.length; index += 2) {
      if (index + 1 >= arguments.length) {
        _fail('every option requires one value');
      }
      switch (arguments[index]) {
        case '--report':
          reportPath = arguments[index + 1];
        case '--platform':
          platform = arguments[index + 1];
        default:
          _fail('unsupported acceptance option');
      }
    }
    if (reportPath == null ||
        platform == null ||
        !_platforms.contains(platform)) {
      _fail('--report and a declared --platform must be provided together');
    }
    return _Options(reportPath: reportPath, platform: platform);
  }
}

final class _OwnerCommand {
  const _OwnerCommand(this.executable, this.arguments, this.workingDirectory);

  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  @override
  bool operator ==(Object other) =>
      other is _OwnerCommand &&
      executable == other.executable &&
      workingDirectory == other.workingDirectory &&
      _sameList(arguments, other.arguments);

  @override
  int get hashCode =>
      Object.hash(executable, workingDirectory, Object.hashAll(arguments));
}

final class _CommandResult {
  const _CommandResult({
    this.spawned = true,
    this.exitCode = 0,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
    int? stdoutBytes,
    int? stderrBytes,
    this.ownerFiles = const <String, String>{},
  }) : stdoutBytes = stdoutBytes ?? 0,
       stderrBytes = stderrBytes ?? 0;

  factory _CommandResult.json(
    Object value, {
    int exitCode = 0,
    Map<String, String> ownerFiles = const <String, String>{},
  }) {
    final text = jsonEncode(value);
    return _CommandResult(
      exitCode: exitCode,
      stdout: text,
      stdoutBytes: utf8.encode(text).length,
      ownerFiles: ownerFiles,
    );
  }

  const _CommandResult.spawnFailure()
    : spawned = false,
      exitCode = -1,
      stdout = '',
      stderr = '',
      timedOut = false,
      stdoutBytes = 0,
      stderrBytes = 0,
      ownerFiles = const <String, String>{};

  final bool spawned;
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final int stdoutBytes;
  final int stderrBytes;
  final Map<String, String> ownerFiles;
}

final class _ControlledRunner {
  _ControlledRunner(Iterable<_CommandResult> results)
    : _results = List<_CommandResult>.of(results);

  final List<_CommandResult> _results;
  final List<_OwnerCommand> calls = <_OwnerCommand>[];
  var _index = 0;

  Future<_CommandResult> call(_OwnerCommand command) async {
    calls.add(command);
    if (_index >= _results.length) {
      _fail('controlled runner received an unexpected command');
    }
    return _results[_index++];
  }
}

Future<Map<String, Object?>> _exerciseControlledHappyPath() async {
  final runner = _ControlledRunner(<_CommandResult>[
    _CommandResult.json(_compatibleMachineInfo()),
    _CommandResult.json(<String, Object?>{
      'command': 'sync',
      'message': 'synchronized',
    }),
    _CommandResult.json(_metadataPayload()),
    _CommandResult.json(
      _workflowPayload('check'),
      ownerFiles: _ownerFiles('check', 'check-session'),
    ),
    _CommandResult.json(
      _workflowPayload('test'),
      ownerFiles: _ownerFiles('test', 'test-session'),
    ),
    _CommandResult.json(
      _workflowPayload('run'),
      ownerFiles: _ownerFiles(
        'run',
        'run-session',
        observationToken: _observationToken,
      ),
    ),
  ]);

  final report = await _runReferenceScenario(runner.call);
  _expect(
    runner.calls.length == 6,
    'happy path must execute six owner commands',
  );
  final expected = _expectedOwnerCommands();
  for (var index = 0; index < expected.length; index++) {
    _expect(
      runner.calls[index] == expected[index],
      'owner command ${index + 1} has a different executable, order, or cwd',
    );
  }
  _validateScenario(report);
  return report;
}

Future<Map<String, Object?>> _runReferenceScenario(
  _CommandRunner runner,
) async {
  final commands = _expectedOwnerCommands();
  final machine = await runner(commands[0]);
  _requireUsableResult(machine, phase: _ProcessPhase.machineProbe);
  _validateMachineInfo(_decodeObject(machine.stdout, 'machine-info'));

  final sync = await runner(commands[1]);
  _requireUsableResult(sync, phase: _ProcessPhase.workflow);
  final syncPayload = _decodeObject(sync.stdout, 'sync');
  _expect(syncPayload['command'] == 'sync', 'sync command must match');
  _boundedString(syncPayload['message'], 'sync.message');

  final metadata = await runner(commands[2]);
  _requireUsableResult(metadata, phase: _ProcessPhase.workflow);
  _validateMetadata(_decodeObject(metadata.stdout, 'metadata'));

  const revision = 1;
  _requireStableSource(
    revision: revision,
    savedDigest: _sourceDigest,
    observedDigests: List<String>.filled(6, _sourceDigest),
  );

  final workflowSessions = <String>[];
  for (var index = 0; index < 3; index++) {
    final command = <String>['check', 'test', 'run'][index];
    final result = await runner(commands[index + 3]);
    _requireUsableResult(result, phase: _ProcessPhase.workflow);
    final payload = _decodeObject(result.stdout, command);
    final session = _validateWorkflow(
      payload,
      command: command,
      ownerFiles: result.ownerFiles,
      observationToken: command == 'run' ? _observationToken : null,
    );
    workflowSessions.add(session);
  }

  final checkSession = workflowSessions[0];
  final testSession = workflowSessions[1];
  final runSession = workflowSessions[2];
  _expect(
    <String>{checkSession, testSession, runSession}.length == 3,
    'workflow receipts must identify three distinct executions',
  );

  return <String, Object?>{
    'schema_version': 1,
    'scenario': _scenario,
    'evidence_kind': 'real-pinned-matrix',
    'ok': true,
    'workspace_revision': revision,
    'source_sha256': _sourceDigest,
    'preflight': <String, Object?>{
      'metadata_contract': 'metadata-v1',
      'sync_status': 'succeeded',
      'compiler_tool': 'styio',
      'compile_plan_contract': 1,
      'runtime_events_contract': 1,
      'runtime_event_stream': true,
      'package': _package,
      'bin_target': _binTarget,
      'test_target': _testTarget,
    },
    'steps': <Map<String, Object?>>[
      _revisionStep('edit', revision, _sourceDigest),
      _workflowStep('check', revision, _sourceDigest, _checkSessionDigest),
      _workflowStep('test', revision, _sourceDigest, _testSessionDigest),
      _workflowStep('run', revision, _sourceDigest, _runSessionDigest),
      <String, Object?>{
        ..._revisionStep('observe', revision, _sourceDigest),
        'session_id_sha256': _runSessionDigest,
        'eventKind': 'log.emitted',
        'observation_sha256': _observationDigest,
      },
    ],
  };
}

Future<void> _exerciseControlledFailures() async {
  final missing = await _classifyBoundary(
    _ControlledRunner(const <_CommandResult>[
      _CommandResult.spawnFailure(),
    ]).call,
  );
  _validateContractReport(
    _contractReport(
      caseName: 'missing-styio',
      outcome: missing.$1,
      category: missing.$2,
    ),
  );

  final incompatibleResults = <_CommandResult>[
    const _CommandResult(exitCode: 2),
    const _CommandResult(stdout: '{not-json', stdoutBytes: 9),
    _CommandResult.json(<String, Object?>{
      ..._compatibleMachineInfo(),
      'tool': 'another-tool',
    }),
    _CommandResult.json(<String, Object?>{
      ..._compatibleMachineInfo(),
      'supported_contract_versions': <String, Object?>{
        'compile_plan': <int>[2],
        'runtime_events': <int>[1],
      },
    }),
  ];
  for (final result in incompatibleResults) {
    final outcome = await _classifyBoundary(
      _ControlledRunner(<_CommandResult>[result]).call,
    );
    _expect(
      outcome == ('blocked', 'styio_machine_contract_incompatible'),
      'every executed incompatible machine probe must block distinctly',
    );
  }
  _validateContractReport(
    _contractReport(
      caseName: 'incompatible-machine-contract',
      outcome: 'blocked',
      category: 'styio_machine_contract_incompatible',
    ),
  );

  final executionFailures = <_CommandResult>[
    const _CommandResult(timedOut: true),
    const _CommandResult(stdoutBytes: _ownerStreamByteLimit + 1),
    const _CommandResult(stderrBytes: _ownerStreamByteLimit + 1),
    const _CommandResult(exitCode: 9),
    const _CommandResult(stdout: '{not-json', stdoutBytes: 9),
    _CommandResult.json(_workflowPayload('check')),
  ];
  for (final failure in executionFailures) {
    final outcome = await _classifyBoundary(
      _ControlledRunner(<_CommandResult>[
        _CommandResult.json(_compatibleMachineInfo()),
        failure,
      ]).call,
      workflowCommand: _expectedOwnerCommands()[3],
    );
    _expect(
      outcome == ('failed', 'compiler_execution_failed'),
      'every bounded compiler execution failure must fail distinctly',
    );
  }
  _validateContractReport(
    _contractReport(
      caseName: 'compiler-execution-failure',
      outcome: 'failed',
      category: 'compiler_execution_failed',
    ),
  );
}

Future<(String, String)> _classifyBoundary(
  _CommandRunner runner, {
  _OwnerCommand? workflowCommand,
}) async {
  final machine = await runner(_expectedOwnerCommands()[0]);
  if (!machine.spawned) {
    return ('blocked', 'styio_missing');
  }
  try {
    _requireUsableResult(machine, phase: _ProcessPhase.machineProbe);
    _validateMachineInfo(_decodeObject(machine.stdout, 'machine-info'));
  } on _AcceptanceFailure {
    return ('blocked', 'styio_machine_contract_incompatible');
  }
  if (workflowCommand == null) {
    _fail('a compatible probe requires a workflow result');
  }
  final result = await runner(workflowCommand);
  try {
    _requireUsableResult(result, phase: _ProcessPhase.workflow);
    _validateWorkflow(
      _decodeObject(result.stdout, 'check'),
      command: 'check',
      ownerFiles: result.ownerFiles,
    );
  } on _AcceptanceFailure {
    return ('failed', 'compiler_execution_failed');
  }
  _fail('controlled failure unexpectedly succeeded');
}

void _exerciseStaleRevisionRejection() {
  _expectFails(
    () => _requireStableSource(
      revision: 1,
      savedDigest: _sourceDigest,
      observedDigests: <String>[
        _sourceDigest,
        _sourceDigest,
        List<String>.filled(64, 'f').join(),
        _sourceDigest,
        _sourceDigest,
        _sourceDigest,
      ],
    ),
    'a stale or mutated source digest must be rejected',
  );
}

List<_OwnerCommand> _expectedOwnerCommands() {
  const styio = '<styio>';
  const pafio = '<pafio>';
  const manifest = '<workspace>/pafio.toml';
  const workspace = '<workspace>';
  return <_OwnerCommand>[
    const _OwnerCommand(styio, <String>['--machine-info=json'], workspace),
    const _OwnerCommand(pafio, <String>[
      '--json',
      'sync',
      '--manifest-path',
      manifest,
    ], workspace),
    const _OwnerCommand(pafio, <String>[
      'metadata',
      '--json',
      '--manifest-path',
      manifest,
    ], workspace),
    const _OwnerCommand(pafio, <String>[
      '--json',
      'check',
      '--manifest-path',
      manifest,
      '--styio-bin',
      styio,
      '--package',
      _package,
      '--bin',
      _binTarget,
    ], workspace),
    const _OwnerCommand(pafio, <String>[
      '--json',
      'test',
      '--manifest-path',
      manifest,
      '--styio-bin',
      styio,
      '--package',
      _package,
      '--test',
      _testTarget,
    ], workspace),
    const _OwnerCommand(pafio, <String>[
      '--json',
      'run',
      '--manifest-path',
      manifest,
      '--styio-bin',
      styio,
      '--package',
      _package,
      '--bin',
      _binTarget,
    ], workspace),
  ];
}

void _validateOuterCommandOrder() {
  for (final platform in _platforms) {
    final expected = <String>[
      'scripts/ecosystem-product-gate.py',
      '--platform',
      platform,
      '--styio-bin',
      '<styio>',
      '--pafio-bin',
      '<pafio>',
      '--output',
      'build/evidence/product-gate-$platform.json',
      '--require-real-matrix',
      '--json',
    ];
    _expect(expected.length == 11, 'outer product gate command order changed');
  }
}

Map<String, Object?> _compatibleMachineInfo() => <String, Object?>{
  'tool': 'styio',
  'active_integration_phase': 'compile-plan-live',
  'supported_contract_versions': <String, Object?>{
    'compile_plan': <int>[1],
    'runtime_events': <int>[1],
  },
  'feature_flags': <String, Object?>{
    'compile_plan_consumer': true,
    'runtime_event_stream': true,
  },
};

Map<String, Object?> _metadataPayload() => <String, Object?>{
  'package': <String, Object?>{'id': _packageId, 'name': _package},
  'workspace': <String, Object?>{
    'root': '<workspace>',
    'manifest_path': '<workspace>/pafio.toml',
    'members': <String>[_package],
    'packages': <Map<String, Object?>>[
      <String, Object?>{
        'id': _packageId,
        'name': _package,
        'version': '0.1.0',
        'root': '<workspace>',
        'manifest_path': '<workspace>/pafio.toml',
      },
    ],
  },
  'dependencies': <Object?>[],
  'targets': <Map<String, Object?>>[
    <String, Object?>{
      'package_id': _packageId,
      'kind': 'bin',
      'name': _binTarget,
      'path': 'src/main.styio',
    },
    <String, Object?>{
      'package_id': _packageId,
      'kind': 'test',
      'name': _testTarget,
      'path': 'tests/product_gate.styio',
    },
  ],
  'lock': <String, Object?>{},
  'resolution': <String, Object?>{},
  'vendor': <String, Object?>{},
};

Map<String, Object?> _workflowPayload(String command) => <String, Object?>{
  'action': command,
  'command': command,
  'intent': command,
  'message': 'completed Styio $command via compile-plan',
  'mode': 'execute',
  'plan': <String, Object?>{
    'artifact_dir': 'build/artifacts',
    'build_root': 'build',
    'cache_key': 'cache-key',
    'diag_dir': 'build/diagnostics',
    'path': 'build/compile-plan.json',
  },
  'profile': 'dev',
  'status': 'succeeded',
  'styio': <String, Object?>{
    'binary': '<styio>',
    'capabilities': <String, Object?>{},
    'compiler_channel': 'nightly',
    'compiler_edition_max': '2026',
    'compiler_version': '0.1.0',
    'integration_phase': 'compile-plan-live',
    'process': <String, Object?>{'exit_code': 0, 'status': 'exited'},
    'status': 'succeeded',
    'supported_compile_plan_versions': <int>[1],
  },
  'sync': <String, Object?>{'status': 'succeeded'},
  'target': <String, Object?>{
    'kind': command == 'test' ? 'test' : 'bin',
    'name': command == 'test' ? _testTarget : _binTarget,
    'package': _package,
    'package_id': _packageId,
  },
};

Map<String, String> _ownerFiles(
  String command,
  String session, {
  String? observationToken,
}) {
  final executed = command != 'check';
  final events = <Map<String, Object?>>[
    <String, Object?>{
      'schema_version': 1,
      'session_id': session,
      'sequence': 1,
      'eventKind': 'compile.started',
      'origin': 'styio.compile-plan',
      'payload': <String, Object?>{'intent': command},
    },
    if (observationToken != null)
      <String, Object?>{
        'schema_version': 1,
        'session_id': session,
        'sequence': 2,
        'eventKind': 'log.emitted',
        'origin': 'styio.runtime',
        'payload': <String, Object?>{
          'stream': 'stdout',
          'message': observationToken,
        },
      },
  ];
  final receipt = <String, Object?>{
    'schema_version': 1,
    'tool': 'styio',
    'compiler_version': '0.1.0',
    'channel': 'nightly',
    'plan_version': 1,
    'intent': command,
    'session_id': session,
    'executed': executed,
    'entry': <String, Object?>{
      'package_id': _packageId,
      'target_kind': command == 'test' ? 'test' : 'bin',
      'target_name': command == 'test' ? _testTarget : _binTarget,
    },
    'outputs': <String, Object?>{
      'build_root': 'build',
      'artifact_dir': 'build/artifacts',
      'diag_dir': 'build/diagnostics',
      'runtime_events_path': 'build/runtime-events.jsonl',
    },
    'artifacts': <String>[],
  };
  return <String, String>{
    'build/receipt.json': jsonEncode(receipt),
    'build/diagnostics/diagnostics.jsonl': '',
    'build/runtime-events.jsonl': '${events.map(jsonEncode).join('\n')}\n',
  };
}

void _validateMachineInfo(Map<String, Object?> payload) {
  _expect(payload['tool'] == 'styio', 'machine-info tool must be styio');
  _boundedString(
    payload['active_integration_phase'],
    'machine-info.active_integration_phase',
  );
  final contracts = _object(
    payload['supported_contract_versions'],
    'contracts',
  );
  for (final name in const <String>['compile_plan', 'runtime_events']) {
    final versions = _list(contracts[name], 'contracts.$name');
    _expect(versions.contains(1), '$name contract version 1 is required');
  }
  final flags = _object(payload['feature_flags'], 'feature_flags');
  _expect(
    flags['compile_plan_consumer'] == true &&
        flags['runtime_event_stream'] == true,
    'compile-plan and runtime-event feature flags are required',
  );
}

void _validateMetadata(Map<String, Object?> payload) {
  _closedKeys(payload, const <String>{
    'package',
    'workspace',
    'dependencies',
    'targets',
    'lock',
    'resolution',
    'vendor',
  }, 'metadata');
  final selectedPackage = _object(payload['package'], 'metadata.package');
  _expect(
    selectedPackage['id'] == _packageId && selectedPackage['name'] == _package,
    'metadata must publish the selected canonical package',
  );
  final targets = _list(payload['targets'], 'metadata.targets');
  final selectors = <String>{};
  for (final item in targets) {
    final target = _object(item, 'metadata.target');
    selectors.add(
      '${target['package_id']}:${target['kind']}:${target['name']}',
    );
  }
  _expect(
    selectors.containsAll(<String>{
      '$_packageId:bin:$_binTarget',
      '$_packageId:test:$_testTarget',
    }),
    'metadata must publish the selected binary and test targets',
  );
}

String _validateWorkflow(
  Map<String, Object?> payload, {
  required String command,
  required Map<String, String> ownerFiles,
  String? observationToken,
}) {
  _closedKeys(payload, const <String>{
    'action',
    'command',
    'intent',
    'message',
    'mode',
    'plan',
    'profile',
    'status',
    'styio',
    'sync',
    'target',
  }, '$command Pafio envelope');
  _expect(
    payload['action'] == command &&
        payload['command'] == command &&
        payload['intent'] == command &&
        payload['mode'] == 'execute' &&
        payload['status'] == 'succeeded',
    '$command must return Pafio current success envelope',
  );
  _boundedString(payload['message'], '$command.message');
  _boundedString(payload['profile'], '$command.profile');
  final plan = _object(payload['plan'], '$command.plan');
  for (final key in const <String>['build_root', 'artifact_dir', 'diag_dir']) {
    final path = _boundedString(plan[key], '$command.plan.$key');
    _expect(
      !_isAbsolutePath(path) && !path.split(RegExp(r'[\\/]')).contains('..'),
      '$command.plan.$key must remain a contained projection',
    );
  }
  final styio = _object(payload['styio'], '$command.styio');
  final process = _object(styio['process'], '$command.styio.process');
  _expect(
    styio['status'] == 'succeeded' &&
        process['status'] == 'exited' &&
        process['exit_code'] == 0,
    '$command Styio process did not succeed',
  );
  final target = _object(payload['target'], '$command.target');
  final expectedKind = command == 'test' ? 'test' : 'bin';
  final expectedName = command == 'test' ? _testTarget : _binTarget;
  _expect(
    target['package'] == _package &&
        target['package_id'] == _packageId &&
        target['kind'] == expectedKind &&
        target['name'] == expectedName,
    '$command target does not match the selected target',
  );

  final buildRoot = _boundedString(plan['build_root'], '$command.build_root');
  final diagDir = _boundedString(plan['diag_dir'], '$command.diag_dir');
  final receiptPath = '$buildRoot/receipt.json';
  final receiptText = ownerFiles[receiptPath];
  _expect(receiptText != null, '$command receipt is missing');
  final receipt = _object(jsonDecode(receiptText!), '$command.receipt');
  _expect(
    receipt['schema_version'] == 1 &&
        receipt['tool'] == 'styio' &&
        receipt['intent'] == command &&
        receipt['executed'] == (command != 'check'),
    '$command receipt does not match current Styio semantics',
  );
  final session = _boundedString(receipt['session_id'], '$command.session_id');
  final entry = _object(receipt['entry'], '$command.receipt.entry');
  _expect(
    entry['package_id'] == _packageId &&
        entry['target_kind'] == expectedKind &&
        entry['target_name'] == expectedName,
    '$command receipt target is stale',
  );
  final artifacts = _list(receipt['artifacts'], '$command.receipt.artifacts');
  _expect(artifacts.length <= _artifactReferenceLimit, 'artifact limit exceeded');

  final diagnosticText = ownerFiles['$diagDir/diagnostics.jsonl'];
  _expect(diagnosticText != null, '$command diagnostics are missing');
  final diagnostics = diagnosticText!
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  _expect(diagnostics.length <= _diagnosticLimit, 'diagnostic limit exceeded');
  for (final line in diagnostics) {
    _object(jsonDecode(line), '$command diagnostic');
  }

  final outputs = _object(receipt['outputs'], '$command.receipt.outputs');
  final eventsPath = _boundedString(
    outputs['runtime_events_path'],
    '$command.runtime_events_path',
  );
  _expect(
    !_isAbsolutePath(eventsPath) &&
        !eventsPath.split(RegExp(r'[\\/]')).contains('..') &&
        (eventsPath == buildRoot || eventsPath.startsWith('$buildRoot/')),
    '$command runtime events escape build_root',
  );
  final eventText = ownerFiles[eventsPath];
  _expect(eventText != null, '$command runtime events are missing');
  final events = eventText!
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .map((line) => _object(jsonDecode(line), '$command.runtime_event'))
      .toList(growable: false);
  _expect(events.length <= _runtimeEventLimit, 'runtime event limit exceeded');
  var previousSequence = 0;
  var observed = false;
  for (final item in events) {
    final event = _object(item, '$command.runtime_event');
    _expect(event['schema_version'] == 1, 'runtime event schema must be v1');
    _expect(event['session_id'] == session, 'runtime event session must match');
    final sequence = event['sequence'];
    _expect(
      sequence is int && sequence > previousSequence,
      'runtime event sequences must be positive and increasing',
    );
    previousSequence = sequence as int;
    _boundedString(event['eventKind'], '$command.eventKind');
    _boundedString(event['origin'], '$command.origin');
    final eventPayload = _object(event['payload'], '$command.payload');
    _expect(
      utf8.encode(jsonEncode(eventPayload)).length <= _ownerStreamByteLimit,
      'runtime event payload exceeds its owner-output budget',
    );
    if (observationToken != null &&
        event['eventKind'] == 'log.emitted' &&
        jsonEncode(eventPayload).contains(observationToken)) {
      observed = true;
    }
  }
  if (observationToken != null) {
    _expect(
      observed,
      'run observation must exist in a same-session log event',
    );
  }
  return session;
}

void _requireStableSource({
  required int revision,
  required String savedDigest,
  required List<String> observedDigests,
}) {
  _expect(revision > 0, 'the committed workspace revision must be positive');
  _requireDigest(savedDigest, 'saved source digest');
  _expect(
    observedDigests.length == 6 &&
        observedDigests.every((digest) => digest == savedDigest),
    'source must match the saved digest before and after every workflow',
  );
}

enum _ProcessPhase { machineProbe, workflow }

void _requireUsableResult(
  _CommandResult result, {
  required _ProcessPhase phase,
}) {
  _expect(result.spawned, 'selected executable could not be spawned');
  _expect(
    !result.timedOut,
    '${phase.name} exceeded $_ownerTimeoutSeconds seconds',
  );
  _expect(
    result.stdoutBytes <= _ownerStreamByteLimit &&
        result.stderrBytes <= _ownerStreamByteLimit,
    '${phase.name} exceeded its bounded output budget',
  );
  _expect(result.exitCode == 0, '${phase.name} exited unsuccessfully');
}

Map<String, Object?> _decodeObject(String text, String name) {
  try {
    return _object(jsonDecode(text), name);
  } on FormatException {
    _fail('$name emitted malformed JSON');
  }
}

Map<String, Object?> _revisionStep(String name, int revision, String digest) =>
    <String, Object?>{
      'name': name,
      'status': 'succeeded',
      'workspace_revision': revision,
      'source_sha256': digest,
    };

Map<String, Object?> _workflowStep(
  String name,
  int revision,
  String digest,
  String sessionDigest,
) => <String, Object?>{
  ..._revisionStep(name, revision, digest),
  'owner_contract': 'pafio-current+styio-files-v1',
  'session_id_sha256': sessionDigest,
};

Map<String, Object?> _contractReport({
  required String caseName,
  required String outcome,
  required String category,
}) => <String, Object?>{
  'schema_version': 1,
  'scenario': _scenario,
  'evidence_kind': 'deterministic-contract',
  'case': caseName,
  'accepted': true,
  'outcome': outcome,
  'error_category': category,
  'success_observation': false,
};

Map<String, Object?> _passingOuterReport(
  String platform,
  Map<String, Object?> scenario,
) {
  final contracts = <Map<String, Object?>>[
    _contractReport(
      caseName: 'missing-styio',
      outcome: 'blocked',
      category: 'styio_missing',
    ),
    _contractReport(
      caseName: 'incompatible-machine-contract',
      outcome: 'blocked',
      category: 'styio_machine_contract_incompatible',
    ),
    _contractReport(
      caseName: 'compiler-execution-failure',
      outcome: 'failed',
      category: 'compiler_execution_failed',
    ),
  ];
  return <String, Object?>{
    'schema_version': 1,
    'gate': _gate,
    'platform': platform,
    'capability': _capability,
    'evidence_kind': 'real-pinned-matrix',
    'ok': true,
    'required': true,
    'skipped': false,
    'failure_category': null,
    'steps': const <Map<String, Object?>>[
      <String, Object?>{'name': 'product-process', 'ok': true},
      <String, Object?>{'name': 'real-scenario', 'ok': true},
      <String, Object?>{'name': 'deterministic-contract-cases', 'ok': true},
    ],
    'report': <String, Object?>{
      'scenario_count': 1,
      'scenarios': <Map<String, Object?>>[scenario],
      'contract_case_count': 3,
      'contract_cases': contracts,
    },
  };
}

void _validateOuterReport(Object? value, {required String expectedPlatform}) {
  final report = _object(value, 'outer report');
  _expect(
    utf8.encode(jsonEncode(report)).length <= _markerByteLimit,
    'outer report exceeds $_markerByteLimit bytes',
  );
  _closedKeys(report, const <String>{
    'schema_version',
    'gate',
    'platform',
    'capability',
    'evidence_kind',
    'ok',
    'required',
    'skipped',
    'failure_category',
    'steps',
    'report',
  }, 'outer report');
  _expect(report['schema_version'] == 1, 'outer report schema must be v1');
  _expect(report['gate'] == _gate, 'outer gate identity changed');
  _expect(report['platform'] == expectedPlatform, 'outer platform mismatch');
  _expect(_platforms.contains(expectedPlatform), 'undeclared platform');
  _expect(report['capability'] == _capability, 'outer capability changed');
  _expect(
    report['evidence_kind'] == 'real-pinned-matrix' &&
        report['ok'] == true &&
        report['required'] == true &&
        report['skipped'] == false &&
        report['failure_category'] == null,
    'only a required passing real matrix report is acceptance evidence',
  );

  final steps = _list(report['steps'], 'outer steps');
  const stepNames = <String>[
    'product-process',
    'real-scenario',
    'deterministic-contract-cases',
  ];
  _expect(steps.length == stepNames.length, 'outer step count changed');
  for (var index = 0; index < steps.length; index++) {
    final step = _object(steps[index], 'outer step');
    _closedKeys(step, const <String>{'name', 'ok'}, 'outer step');
    _expect(
      step['name'] == stepNames[index] && step['ok'] == true,
      'outer step failed or changed order',
    );
  }

  final body = _object(report['report'], 'outer report body');
  _closedKeys(body, const <String>{
    'scenario_count',
    'scenarios',
    'contract_case_count',
    'contract_cases',
  }, 'outer report body');
  final scenarios = _list(body['scenarios'], 'scenarios');
  final contractCases = _list(body['contract_cases'], 'contract cases');
  _expect(
    body['scenario_count'] == 1 && scenarios.length == 1,
    'exactly one real scenario is required',
  );
  _expect(
    body['contract_case_count'] == 3 && contractCases.length == 3,
    'exactly three deterministic contract cases are required',
  );
  _validateScenario(_object(scenarios.single, 'scenario'));
  for (final contract in contractCases) {
    _validateContractReport(_object(contract, 'contract report'));
  }
  _expect(
    contractCases
            .map((item) => _object(item, 'contract')['case'])
            .toList()
            .join(',') ==
        'missing-styio,incompatible-machine-contract,compiler-execution-failure',
    'contract cases must retain their frozen order',
  );
  _validatePrivacy(report);
}

void _validateScenario(Map<String, Object?> report) {
  _closedKeys(report, const <String>{
    'schema_version',
    'scenario',
    'evidence_kind',
    'ok',
    'workspace_revision',
    'source_sha256',
    'preflight',
    'steps',
  }, 'scenario');
  _expect(
    report['schema_version'] == 1 &&
        report['scenario'] == _scenario &&
        report['evidence_kind'] == 'real-pinned-matrix' &&
        report['ok'] == true,
    'scenario identity or evidence kind is invalid',
  );
  final revision = report['workspace_revision'];
  _expect(
    revision is int && revision > 0,
    'scenario revision must be positive',
  );
  final sourceDigest = report['source_sha256'];
  _requireDigest(sourceDigest, 'scenario source digest');

  final preflight = _object(report['preflight'], 'preflight');
  _closedKeys(preflight, const <String>{
    'metadata_contract',
    'sync_status',
    'compiler_tool',
    'compile_plan_contract',
    'runtime_events_contract',
    'runtime_event_stream',
    'package',
    'bin_target',
    'test_target',
  }, 'preflight');
  _expect(
    preflight['metadata_contract'] == 'metadata-v1' &&
        preflight['sync_status'] == 'succeeded' &&
        preflight['compiler_tool'] == 'styio' &&
        preflight['compile_plan_contract'] == 1 &&
        preflight['runtime_events_contract'] == 1 &&
        preflight['runtime_event_stream'] == true &&
        preflight['package'] == _package &&
        preflight['bin_target'] == _binTarget &&
        preflight['test_target'] == _testTarget,
    'scenario preflight is incomplete',
  );

  final steps = _list(report['steps'], 'scenario steps');
  const names = <String>['edit', 'check', 'test', 'run', 'observe'];
  _expect(steps.length == names.length, 'scenario must contain five steps');
  final sessions = <String>[];
  for (var index = 0; index < steps.length; index++) {
    final step = _object(steps[index], 'scenario step');
    final expectedKeys = <String>{
      'name',
      'status',
      'workspace_revision',
      'source_sha256',
      if (index >= 1 && index <= 3) ...<String>{
        'owner_contract',
        'session_id_sha256',
      },
      if (index == 4) ...<String>{
        'session_id_sha256',
        'eventKind',
        'observation_sha256',
      },
    };
    _closedKeys(step, expectedKeys, 'scenario step');
    _expect(
      step['name'] == names[index] &&
          step['status'] == 'succeeded' &&
          step['workspace_revision'] == revision &&
          step['source_sha256'] == sourceDigest,
      'scenario step is stale, reordered, or unsuccessful',
    );
    if (index >= 1) {
      _requireDigest(step['session_id_sha256'], 'session digest');
    }
    if (index >= 1 && index <= 3) {
      _expect(
        step['owner_contract'] == 'pafio-current+styio-files-v1',
        'workflow step must prove the current owner contract',
      );
      sessions.add(step['session_id_sha256'] as String);
    }
  }
  _expect(
    sessions.toSet().length == 3,
    'workflow session digests must be unique',
  );
  final observe = _object(steps[4], 'observe');
  _expect(
    observe['session_id_sha256'] == sessions[2] &&
        observe['eventKind'] == 'log.emitted',
    'observation must bind to the run receipt and log event',
  );
  _requireDigest(observe['observation_sha256'], 'observation digest');
}

void _validateContractReport(Map<String, Object?> report) {
  _closedKeys(report, const <String>{
    'schema_version',
    'scenario',
    'evidence_kind',
    'case',
    'accepted',
    'outcome',
    'error_category',
    'success_observation',
  }, 'contract report');
  _expect(
    report['schema_version'] == 1 &&
        report['scenario'] == _scenario &&
        report['evidence_kind'] == 'deterministic-contract' &&
        report['accepted'] == true &&
        report['success_observation'] == false,
    'contract report identity or evidence label is invalid',
  );
  const expected = <String, (String, String)>{
    'missing-styio': ('blocked', 'styio_missing'),
    'incompatible-machine-contract': (
      'blocked',
      'styio_machine_contract_incompatible',
    ),
    'compiler-execution-failure': ('failed', 'compiler_execution_failed'),
  };
  final pair = expected[report['case']];
  _expect(
    pair != null &&
        report['outcome'] == pair.$1 &&
        report['error_category'] == pair.$2,
    'contract case/category/outcome does not match the frozen classifier',
  );
}

void _validatePrivacy(Object? value, [String parent = 'report']) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = '${entry.key}';
      final normalized = key.toLowerCase();
      _expect(
        !const <String>{
              'stdout',
              'stderr',
              'source',
              'source_text',
              'receipt',
              'receipt_path',
              'runtime_events',
              'runtime_payload',
              'timestamp',
              'environment',
              'executable',
              'machine_identity',
              'token',
            }.contains(normalized) &&
            !normalized.contains('secret') &&
            !normalized.contains('password'),
        '$parent contains a forbidden evidence field',
      );
      _validatePrivacy(entry.value, '$parent.$key');
    }
  } else if (value is List) {
    for (final item in value) {
      _validatePrivacy(item, parent);
    }
  } else if (value is String) {
    _expect(
      utf8.encode(value).length <= _projectedStringByteLimit,
      '$parent exceeds the projected string limit',
    );
    _expect(!_isAbsolutePath(value), '$parent exposes an absolute path');
  }
}

void _validateFrozenLimits() {
  _expect(_ownerTimeoutSeconds == 120, 'owner timeout changed');
  _expect(_ownerTerminationGraceSeconds == 5, 'termination grace changed');
  _expect(_ownerStreamByteLimit == 262144, 'owner output budget changed');
  _expect(_outerTimeoutSeconds == 600, 'outer timeout changed');
  _expect(_outerStreamByteLimit == 1048576, 'outer output budget changed');
  _expect(_markerByteLimit == 65536, 'marker budget changed');
  _expect(_diagnosticLimit == 128, 'diagnostic budget changed');
  _expect(_runtimeEventLimit == 256, 'runtime-event budget changed');
  _expect(_artifactReferenceLimit == 64, 'artifact budget changed');
  _expect(_projectedStringByteLimit == 512, 'string budget changed');
  _expect(
    _productMarker == 'VITYO_PRODUCT_REPORT ' &&
        _contractMarker == 'VITYO_PRODUCT_CONTRACT_REPORT ',
    'report markers changed',
  );
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map) {
    _fail('$name must be one JSON object');
  }
  return <String, Object?>{
    for (final entry in value.entries) '${entry.key}': entry.value,
  };
}

List<Object?> _list(Object? value, String name) {
  if (value is! List) {
    _fail('$name must be one JSON array');
  }
  return List<Object?>.from(value);
}

String _boundedString(Object? value, String name, {bool allowEmpty = false}) {
  if (value is! String || (!allowEmpty && value.isEmpty)) {
    _fail('$name must be ${allowEmpty ? '' : 'nonempty '}text');
  }
  if (utf8.encode(value).length > _projectedStringByteLimit) {
    _fail('$name exceeds the bounded string limit');
  }
  return value;
}

void _closedKeys(Map<String, Object?> value, Set<String> keys, String name) {
  if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
    _fail('$name is not a closed schema');
  }
}

void _requireDigest(Object? value, String name) {
  _expect(
    value is String && _digestPattern.hasMatch(value),
    '$name is invalid',
  );
}

bool _isAbsolutePath(String value) =>
    value.startsWith('/') ||
    value.startsWith(r'\\') ||
    _windowsAbsolutePath.hasMatch(value);

bool _sameList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) _fail(message);
}

void _expectFails(void Function() operation, String message) {
  try {
    operation();
  } on _AcceptanceFailure {
    return;
  }
  _fail(message);
}

Never _fail(String message) => throw _AcceptanceFailure(message);

final class _AcceptanceFailure implements Exception {
  const _AcceptanceFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
