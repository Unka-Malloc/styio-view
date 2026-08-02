import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/owner_adapters/pafio_metadata_adapter.dart';
import 'package:vityo_app/owner_adapters/styio_compiler_adapter.dart';
import 'package:vityo_app/src/ide/workspace/workspace_change_set.dart';
import 'package:vityo_app/src/ide/workspace/workspace_revision_service.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';

const _scenario = 'trusted-desktop-styio-loop';
const _productMarker = 'VITYO_PRODUCT_REPORT ';
const _contractMarker = 'VITYO_PRODUCT_CONTRACT_REPORT ';
const _package = 'vityo/product-gate';
const _packageId = 'workspace:vityo/product-gate@0.1.0';
const _binTarget = 'product-gate';
const _testTarget = 'product-gate-test';
const _beforeToken = 'vityo-before-edit';
const _observationToken = 'vityo-observed-r1';
const _runtimeEventsFile = 'runtime-events.jsonl';
const _ownerStreamLimit = 262144;
const _diagnosticLimit = 128;
const _runtimeEventLimit = 256;
const _artifactReferenceLimit = 64;
const _projectedStringLimit = 512;
const _ownerTimeout = Duration(seconds: 120);
const _terminationGrace = Duration(seconds: 5);

final _windowsDrivePath = RegExp(r'^[A-Za-z]:[\\/]');
final _windowsDriveRelativePath = RegExp(r'^[A-Za-z]:');

typedef _CommandRunner = Future<_CommandResult> Function(_OwnerCommand command);

void main() {
  test('missing selected Styio is blocked distinctly', () async {
    final result = await _classifyBoundary(
      _ControlledRunner(const <_CommandResult>[
        _CommandResult.spawnFailure(),
      ]).call,
    );
    expect(result, ('blocked', 'styio_missing'));
    _emitContract(
      caseName: 'missing-styio',
      outcome: result.$1,
      category: result.$2,
    );
  });

  test('incompatible selected Styio contract is blocked distinctly', () async {
    final incompatible = <_CommandResult>[
      const _CommandResult(exitCode: 2),
      _CommandResult(stdoutBytes: utf8.encode('{not-json')),
      _CommandResult.json(<String, Object?>{
        ..._compatibleMachineInfo(),
        'tool': 'not-styio',
      }),
      _CommandResult.json(<String, Object?>{
        ..._compatibleMachineInfo(),
        'supported_contract_versions': <String, Object?>{
          'compile_plan': <int>[2],
          'runtime_events': <int>[1],
        },
      }),
      _CommandResult.json(<String, Object?>{
        ..._compatibleMachineInfo(),
        'feature_flags': <String, Object?>{
          'compile_plan_consumer': true,
          'runtime_event_stream': false,
        },
      }),
    ];
    for (final probe in incompatible) {
      final result = await _classifyBoundary(
        _ControlledRunner(<_CommandResult>[probe]).call,
      );
      expect(result, ('blocked', 'styio_machine_contract_incompatible'));
    }
    _emitContract(
      caseName: 'incompatible-machine-contract',
      outcome: 'blocked',
      category: 'styio_machine_contract_incompatible',
    );
  });

  test('compiler execution failure is failed distinctly', () async {
    final result = await _classifyBoundary(
      _ControlledRunner(<_CommandResult>[
        _CommandResult.json(_compatibleMachineInfo()),
        const _CommandResult(timedOut: true),
      ]).call,
      workflow: const _OwnerCommand('<pafio>', <String>[
        '--json',
        'check',
      ], '.'),
    );
    expect(result, ('failed', 'compiler_execution_failed'));
    _emitContract(
      caseName: 'compiler-execution-failure',
      outcome: result.$1,
      category: result.$2,
    );
  });

  test('current absolute owner paths stay canonically contained', () async {
    final root = await Directory.systemTemp.createTemp('vityo_owner_contract_');
    try {
      final workspaceDirectory = Directory(
        '${root.path}${Platform.pathSeparator}workspace',
      );
      final buildDirectory = Directory(
        '${workspaceDirectory.path}${Platform.pathSeparator}build',
      );
      final artifactDirectory = Directory(
        '${buildDirectory.path}${Platform.pathSeparator}artifacts',
      );
      final diagnosticDirectory = Directory(
        '${buildDirectory.path}${Platform.pathSeparator}diag',
      );
      await artifactDirectory.create(recursive: true);
      await diagnosticDirectory.create(recursive: true);
      final workspace = await workspaceDirectory.resolveSymbolicLinks();
      final buildRoot = await buildDirectory.resolveSymbolicLinks();
      final artifactDir = await artifactDirectory.resolveSymbolicLinks();
      final diagDir = await diagnosticDirectory.resolveSymbolicLinks();
      final eventsPath =
          '$buildRoot${Platform.pathSeparator}$_runtimeEventsFile';
      await File(
        '$buildRoot${Platform.pathSeparator}receipt.json',
      ).writeAsString(
        jsonEncode(
          _currentReceipt(
            command: 'check',
            workspace: workspace,
            buildRoot: buildRoot,
            artifactDir: artifactDir,
            diagDir: diagDir,
            eventsPath: eventsPath,
          ),
        ),
      );
      await File(
        '$diagDir${Platform.pathSeparator}diagnostics.jsonl',
      ).writeAsString('');
      await File(eventsPath).writeAsString(
        '${jsonEncode(<String, Object?>{
          'schema_version': 1,
          'session_id': 'check-session',
          'sequence': 1,
          'timestamp': '2026-01-01T00:00:00Z',
          'eventKind': 'compile.started',
          'origin': 'styio.compile-plan',
          'payload': <String, Object?>{'intent': 'check'},
        })}\n',
      );

      final session = await _validateWorkflow(
        _currentWorkflowEnvelope(
          command: 'check',
          buildRoot: buildRoot,
          artifactDir: artifactDir,
          diagDir: diagDir,
        ),
        command: 'check',
        workspaceRoot: workspace,
      );
      expect(session, 'check-session');
    } finally {
      await root.delete(recursive: true);
    }
  });

  final enabled = _enabled(Platform.environment['VITYO_PRODUCT_GATE']);
  test(
    'real edit check test run and observation share one saved revision',
    () async {
      final report = await _runRealScenario(
        workspacePath: _requiredEnvironment('VITYO_PRODUCT_WORKSPACE_ROOT'),
        manifestPath: _requiredEnvironment('VITYO_PRODUCT_MANIFEST_PATH'),
        pafioBinary: _requiredEnvironment('VITYO_PAFIO_BIN'),
        styioBinary: _requiredEnvironment('VITYO_STYIO_BIN'),
        runner: _runBoundedCommand,
      );
      stdout.writeln('$_productMarker${jsonEncode(report)}');
    },
    skip: enabled ? false : 'requires VITYO_PRODUCT_GATE=1',
  );
}

final class _OwnerCommand {
  const _OwnerCommand(this.executable, this.arguments, this.workingDirectory);

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}

final class _CommandResult {
  const _CommandResult({
    this.exitCode = 0,
    this.stdoutBytes = const <int>[],
    this.stderrBytes = const <int>[],
    this.timedOut = false,
    this.outputExceeded = false,
  }) : spawned = true;

  factory _CommandResult.json(Object value, {int exitCode = 0}) {
    return _CommandResult(
      exitCode: exitCode,
      stdoutBytes: utf8.encode(jsonEncode(value)),
    );
  }

  const _CommandResult.spawnFailure()
    : spawned = false,
      exitCode = -1,
      stdoutBytes = const <int>[],
      stderrBytes = const <int>[],
      timedOut = false,
      outputExceeded = false;

  final bool spawned;
  final int exitCode;
  final List<int> stdoutBytes;
  final List<int> stderrBytes;
  final bool timedOut;
  final bool outputExceeded;

  String get stdoutText => utf8.decode(stdoutBytes);
}

final class _ControlledRunner {
  _ControlledRunner(Iterable<_CommandResult> results)
    : _results = List<_CommandResult>.of(results);

  final List<_CommandResult> _results;
  var _index = 0;

  Future<_CommandResult> call(_OwnerCommand command) async {
    if (_index >= _results.length) {
      throw StateError('controlled runner received an unexpected command');
    }
    return _results[_index++];
  }
}

Future<_CommandResult> _runBoundedCommand(_OwnerCommand command) async {
  final Process process;
  try {
    process = await Process.start(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory,
      runInShell: false,
    );
  } on ProcessException {
    return const _CommandResult.spawnFailure();
  }

  final stdoutBytes = <int>[];
  final stderrBytes = <int>[];
  var outputExceeded = false;
  final drains = <Future<void>>[
    _drainBounded(process.stdout, stdoutBytes, () => outputExceeded = true),
    _drainBounded(process.stderr, stderrBytes, () => outputExceeded = true),
  ];
  final stopwatch = Stopwatch()..start();
  final exitCode = Completer<int>();
  unawaited(process.exitCode.then(exitCode.complete));
  var timedOut = false;
  while (!exitCode.isCompleted) {
    if (outputExceeded) {
      await _terminate(process);
      break;
    }
    if (stopwatch.elapsed >= _ownerTimeout) {
      timedOut = true;
      await _terminate(process);
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  final code = await process.exitCode;
  await Future.wait(drains);
  return _CommandResult(
    exitCode: code,
    stdoutBytes: List<int>.unmodifiable(stdoutBytes),
    stderrBytes: List<int>.unmodifiable(stderrBytes),
    timedOut: timedOut,
    outputExceeded: outputExceeded,
  );
}

Future<void> _drainBounded(
  Stream<List<int>> stream,
  List<int> target,
  void Function() exceeded,
) async {
  await for (final chunk in stream) {
    final remaining = _ownerStreamLimit + 1 - target.length;
    if (remaining > 0) {
      target.addAll(chunk.take(remaining));
    }
    if (target.length > _ownerStreamLimit || chunk.length > remaining) {
      exceeded();
    }
  }
}

Future<void> _terminate(Process process) async {
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(_terminationGrace);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  }
}

Future<(String, String)> _classifyBoundary(
  _CommandRunner runner, {
  _OwnerCommand? workflow,
}) async {
  final machine = await runner(
    const _OwnerCommand('<styio>', <String>['--machine-info=json'], '.'),
  );
  if (!machine.spawned) {
    return ('blocked', 'styio_missing');
  }
  try {
    _requireSuccessful(machine);
    _decodeCompatibleMachine(machine.stdoutText, '<styio>');
  } on Object {
    return ('blocked', 'styio_machine_contract_incompatible');
  }
  if (workflow == null) {
    throw StateError('compatible probe requires a workflow failure result');
  }
  final result = await runner(workflow);
  try {
    _requireSuccessful(result);
    await _validateWorkflow(
      _jsonObject(result.stdoutText, 'check workflow'),
      command: 'check',
      workspaceRoot: Directory.current.path,
      requireContainedPaths: false,
    );
  } on Object {
    return ('failed', 'compiler_execution_failed');
  }
  throw StateError('controlled compiler execution unexpectedly succeeded');
}

Future<Map<String, Object?>> _runRealScenario({
  required String workspacePath,
  required String manifestPath,
  required String pafioBinary,
  required String styioBinary,
  required _CommandRunner runner,
}) async {
  final workspace = await Directory(workspacePath).resolveSymbolicLinks();
  final manifest = await File(manifestPath).resolveSymbolicLinks();
  _requireContained(workspace, manifest);

  final machineResult = await runner(
    _OwnerCommand(styioBinary, const <String>[
      '--machine-info=json',
    ], workspace),
  );
  if (!machineResult.spawned) {
    throw StateError('styio_missing');
  }
  _requireSuccessful(machineResult);
  final compiler = _decodeCompatibleMachine(
    machineResult.stdoutText,
    styioBinary,
  );

  final syncResult = await runner(
    _OwnerCommand(pafioBinary, <String>[
      '--json',
      'sync',
      '--manifest-path',
      manifest,
    ], workspace),
  );
  _requireSuccessful(syncResult);
  final sync = _jsonObject(syncResult.stdoutText, 'sync');
  if (sync['command'] != 'sync') {
    throw StateError('sync returned a different command');
  }
  _boundedString(sync['message'], 'sync.message');

  final metadataResult = await runner(
    _OwnerCommand(pafioBinary, <String>[
      'metadata',
      '--json',
      '--manifest-path',
      manifest,
    ], workspace),
  );
  _requireSuccessful(metadataResult);
  final metadata = _jsonObject(metadataResult.stdoutText, 'metadata');
  PafioMetadataAdapter.decode(metadataResult.stdoutText);
  _requireSelectedTargets(metadata);

  final unresolvedSourceFile = File(
    '${Directory(workspace).path}${Platform.pathSeparator}src'
    '${Platform.pathSeparator}main.styio',
  );
  final sourcePath = await unresolvedSourceFile.resolveSymbolicLinks();
  _requireContained(workspace, sourcePath);
  final sourceFile = File(sourcePath);
  final initialBytes = await sourceFile.readAsBytes();
  final initialText = utf8.decode(initialBytes);
  final tokenStart = initialText.indexOf(_beforeToken);
  if (tokenStart < 0) {
    throw StateError('product fixture does not contain the edit token');
  }

  final revisions = InMemoryWorkspaceRevisionService(
    initialDocuments: <String, String>{'src/main.styio': initialText},
  );
  final transactions = RevisionedWorkspaceTransactionService(revisions);
  final before = revisions.snapshot();
  final preview = await transactions.preview(
    WorkspaceChangeSet(
      id: 'trusted-desktop-product-edit',
      baseWorkspaceRevision: before.workspaceRevision,
      resources: <WorkspaceResourceChange>[
        WorkspaceResourceChange(
          resourceId: 'src/main.styio',
          baseDocumentRevision: before.document('src/main.styio').revision,
          edits: <WorkspaceTextChange>[
            WorkspaceTextChange(
              start: tokenStart,
              end: tokenStart + _beforeToken.length,
              replacement: _observationToken,
            ),
          ],
        ),
      ],
    ),
  );
  if (preview.outcome != WorkspaceTransactionOutcome.ready) {
    throw StateError('Vityo edit preview was not ready');
  }
  final receipt = await transactions.commit(preview.id);
  if (receipt.outcome != WorkspaceTransactionOutcome.committed ||
      receipt.workspaceRevision <= 0) {
    throw StateError('Vityo edit did not commit');
  }
  final savedText = revisions.snapshot().document('src/main.styio').text;
  if (savedText.contains('\r')) {
    throw StateError('committed product source is not LF-normalized');
  }
  final savedBytes = utf8.encode(savedText);
  await sourceFile.writeAsBytes(savedBytes, flush: true);
  final sourceDigest = sha256.convert(savedBytes).toString();

  final workflowReports = <Map<String, Object?>>[];
  final sessions = <String>[];
  for (final command in const <String>['check', 'test', 'run']) {
    await _requireSavedDigest(sourceFile, sourceDigest);
    final selector = command == 'test'
        ? const <String>['--test', _testTarget]
        : const <String>['--bin', _binTarget];
    final result = await runner(
      _OwnerCommand(pafioBinary, <String>[
        '--json',
        command,
        '--manifest-path',
        manifest,
        '--styio-bin',
        styioBinary,
        '--package',
        _package,
        ...selector,
      ], workspace),
    );
    _requireSuccessful(result);
    final payload = _jsonObject(result.stdoutText, '$command workflow');
    final session = await _validateWorkflow(
      payload,
      command: command,
      workspaceRoot: workspace,
      observationToken: command == 'run' ? _observationToken : null,
    );
    sessions.add(session);
    workflowReports.add(<String, Object?>{
      'name': command,
      'status': 'succeeded',
      'workspace_revision': receipt.workspaceRevision,
      'source_sha256': sourceDigest,
      'owner_contract': 'pafio-current+styio-files-v1',
      'session_id_sha256': sha256.convert(utf8.encode(session)).toString(),
    });
    await _requireSavedDigest(sourceFile, sourceDigest);
  }
  if (sessions.toSet().length != 3) {
    throw StateError('workflow sessions must identify distinct executions');
  }
  final runSessionDigest = sha256.convert(utf8.encode(sessions[2])).toString();
  final observationDigest = sha256
      .convert(utf8.encode(_observationToken))
      .toString();

  Map<String, Object?> revisionStep(String name) => <String, Object?>{
    'name': name,
    'status': 'succeeded',
    'workspace_revision': receipt.workspaceRevision,
    'source_sha256': sourceDigest,
  };

  return <String, Object?>{
    'schema_version': 1,
    'scenario': _scenario,
    'evidence_kind': 'real-pinned-matrix',
    'ok': true,
    'workspace_revision': receipt.workspaceRevision,
    'source_sha256': sourceDigest,
    'preflight': <String, Object?>{
      'metadata_contract': 'metadata-v1',
      'sync_status': 'succeeded',
      'compiler_tool': compiler.tool,
      'compile_plan_contract': 1,
      'runtime_events_contract': 1,
      'runtime_event_stream': true,
      'package': _package,
      'bin_target': _binTarget,
      'test_target': _testTarget,
    },
    'steps': <Map<String, Object?>>[
      revisionStep('edit'),
      ...workflowReports,
      <String, Object?>{
        ...revisionStep('observe'),
        'session_id_sha256': runSessionDigest,
        'eventKind': 'log.emitted',
        'observation_sha256': observationDigest,
      },
    ],
  };
}

CompilerHandshakeSnapshot _decodeCompatibleMachine(
  String payload,
  String styioBinary,
) {
  final raw = _jsonObject(payload, 'styio machine-info');
  final contracts = _object(
    raw['supported_contract_versions'],
    'styio supported contracts',
  );
  final flags = _object(raw['feature_flags'], 'styio feature flags');
  if (raw['tool'] != 'styio' ||
      raw['active_integration_phase'] is! String ||
      (raw['active_integration_phase'] as String).trim().isEmpty ||
      !_list(contracts['compile_plan'], 'compile-plan contracts').contains(1) ||
      !_list(
        contracts['runtime_events'],
        'runtime-event contracts',
      ).contains(1) ||
      flags['compile_plan_consumer'] != true ||
      flags['runtime_event_stream'] != true) {
    throw StateError('styio_machine_contract_incompatible');
  }
  final compiler = StyioCompilerAdapter.decode(
    payload,
    binaryPath: styioBinary,
  );
  if (compiler.tool != 'styio' ||
      compiler.integrationPhase.trim().isEmpty ||
      !(compiler.supportedContractVersions['compile_plan'] ?? const <int>[])
          .contains(1) ||
      !(compiler.supportedContractVersions['runtime_events'] ?? const <int>[])
          .contains(1) ||
      compiler.featureFlags['compile_plan_consumer'] != true ||
      compiler.featureFlags['runtime_event_stream'] != true) {
    throw StateError('styio_machine_contract_incompatible');
  }
  return compiler;
}

void _requireSelectedTargets(Map<String, Object?> metadata) {
  final selectedPackage = _object(metadata['package'], 'metadata.package');
  final packageId = _boundedString(
    selectedPackage['id'],
    'metadata.package.id',
  );
  if (selectedPackage['name'] != _package) {
    throw StateError('metadata returned a different selected package');
  }
  final workspace = _object(metadata['workspace'], 'metadata.workspace');
  final packages = _list(workspace['packages'], 'metadata.workspace.packages');
  if (!packages.any((item) {
    final package = _object(item, 'metadata package');
    return package['id'] == packageId && package['name'] == _package;
  })) {
    throw StateError('metadata omitted the selected package');
  }
  final targets = _list(metadata['targets'], 'metadata.targets');
  final selectors = <String>{
    for (final item in targets)
      '${_object(item, 'metadata target')['package_id']}:'
          '${_object(item, 'metadata target')['kind']}:'
          '${_object(item, 'metadata target')['name']}',
  };
  if (!selectors.contains('$packageId:bin:$_binTarget') ||
      !selectors.contains('$packageId:test:$_testTarget')) {
    throw StateError('metadata omitted a selected product target');
  }
}

Future<String> _validateWorkflow(
  Map<String, Object?> payload, {
  required String command,
  required String workspaceRoot,
  String? observationToken,
  bool requireContainedPaths = true,
}) async {
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
  if (payload['action'] != command ||
      payload['command'] != command ||
      payload['intent'] != command ||
      payload['mode'] != 'execute' ||
      payload['status'] != 'succeeded') {
    throw StateError('$command did not return the current success envelope');
  }
  _boundedString(payload['message'], '$command.message');
  _boundedString(payload['profile'], '$command.profile');
  final styio = _object(payload['styio'], '$command.styio');
  final sync = _object(payload['sync'], '$command.sync');
  final process = _object(styio['process'], '$command.styio.process');
  if (styio['status'] != 'succeeded' ||
      sync['status'] != 'succeeded' ||
      process['status'] != 'exited' ||
      process['exit_code'] != 0) {
    throw StateError('$command Styio process did not succeed');
  }
  final expectedKind = command == 'test' ? 'test' : 'bin';
  final expectedName = command == 'test' ? _testTarget : _binTarget;
  final target = _object(payload['target'], '$command.target');
  if (target['package'] != _package ||
      target['package_id'] != _packageId ||
      target['kind'] != expectedKind ||
      target['name'] != expectedName) {
    throw StateError('$command target does not match the selected target');
  }

  if (!requireContainedPaths) {
    throw StateError('$command owner files are unavailable');
  }
  final workspace = await Directory(workspaceRoot).resolveSymbolicLinks();
  final plan = _object(payload['plan'], '$command.plan');
  final buildRoot = await _resolveOwnerDirectory(
    workspace,
    _boundedOwnerPath(plan['build_root'], '$command.plan.build_root'),
  );
  final artifactDir = await _resolveOwnerDirectory(
    workspace,
    _boundedOwnerPath(plan['artifact_dir'], '$command.plan.artifact_dir'),
  );
  final diagDir = await _resolveOwnerDirectory(
    workspace,
    _boundedOwnerPath(plan['diag_dir'], '$command.plan.diag_dir'),
  );

  final receiptText = await _readOwnerFile(
    _ownerPath(buildRoot, 'receipt.json'),
    containedRoot: buildRoot,
    name: '$command receipt',
  );
  final receipt = _jsonObject(receiptText, '$command.receipt');
  _closedKeys(receipt, const <String>{
    'schema_version',
    'tool',
    'compiler_version',
    'channel',
    'plan_version',
    'intent',
    'session_id',
    'executed',
    'wall_time_ms',
    'generated_at',
    'dict_impl',
    'entry',
    'outputs',
    'artifacts',
  }, '$command receipt');
  if (receipt['schema_version'] != 1 ||
      receipt['tool'] != 'styio' ||
      receipt['plan_version'] != 1 ||
      receipt['intent'] != command ||
      receipt['executed'] != (command != 'check')) {
    throw StateError('$command receipt does not match current Styio semantics');
  }
  _boundedString(receipt['compiler_version'], '$command.compiler_version');
  _boundedString(receipt['channel'], '$command.channel');
  _boundedString(receipt['generated_at'], '$command.generated_at');
  final wallTime = receipt['wall_time_ms'];
  if (wallTime is! int || wallTime < 0) {
    throw StateError('$command receipt wall time is invalid');
  }
  final dictImpl = _object(receipt['dict_impl'], '$command.receipt.dict_impl');
  _closedKeys(dictImpl, const <String>{'selected'}, '$command dict_impl');
  _boundedString(dictImpl['selected'], '$command.dict_impl.selected');
  final session = _boundedString(receipt['session_id'], '$command.session_id');
  final entry = _object(receipt['entry'], '$command.receipt.entry');
  _closedKeys(entry, const <String>{
    'package_id',
    'target_kind',
    'target_name',
    'file',
  }, '$command receipt entry');
  if (entry['package_id'] != _packageId ||
      entry['target_kind'] != expectedKind ||
      entry['target_name'] != expectedName) {
    throw StateError('$command receipt target is stale');
  }
  _boundedOwnerPath(entry['file'], '$command receipt entry file');
  final outputs = _object(receipt['outputs'], '$command.receipt.outputs');
  _closedKeys(outputs, const <String>{
    'build_root',
    'artifact_dir',
    'diag_dir',
    'runtime_events_path',
  }, '$command receipt outputs');
  final receiptBuildRoot = await _resolveOwnerDirectory(
    workspace,
    _boundedOwnerPath(outputs['build_root'], '$command.outputs.build_root'),
  );
  final receiptArtifactDir = await _resolveOwnerDirectory(
    workspace,
    _boundedOwnerPath(outputs['artifact_dir'], '$command.outputs.artifact_dir'),
  );
  final receiptDiagDir = await _resolveOwnerDirectory(
    workspace,
    _boundedOwnerPath(outputs['diag_dir'], '$command.outputs.diag_dir'),
  );
  if (receiptBuildRoot != buildRoot ||
      receiptArtifactDir != artifactDir ||
      receiptDiagDir != diagDir) {
    throw StateError('$command receipt outputs are stale');
  }
  final artifacts = _list(receipt['artifacts'], '$command artifacts');
  if (artifacts.length > _artifactReferenceLimit) {
    throw StateError('$command artifacts exceed their limit');
  }
  for (final artifact in artifacts) {
    final path = _boundedOwnerPath(artifact, '$command artifact');
    final resolved = await File(
      _ownerPath(workspace, path),
    ).resolveSymbolicLinks();
    _requireContained(artifactDir, resolved);
  }

  final diagnosticText = await _readOwnerFile(
    _ownerPath(diagDir, 'diagnostics.jsonl'),
    containedRoot: diagDir,
    name: '$command diagnostics',
  );
  final diagnostics = _jsonLines(
    diagnosticText,
    '$command diagnostic',
    _diagnosticLimit,
  );
  for (final diagnostic in diagnostics) {
    if (diagnostic.containsKey('schema_version') &&
        diagnostic['schema_version'] != 1) {
      throw StateError('$command diagnostic schema is unsupported');
    }
  }

  final eventsPath = _boundedOwnerPath(
    outputs['runtime_events_path'],
    '$command.runtime_events_path',
  );
  if (eventsPath.split(RegExp(r'[\\/]')).last != _runtimeEventsFile) {
    throw StateError('$command runtime events path has an unknown schema');
  }
  final eventFile = await File(
    _ownerPath(workspace, eventsPath),
  ).resolveSymbolicLinks();
  _requireContained(buildRoot, eventFile);
  final eventText = await _readOwnerFile(
    eventFile,
    containedRoot: buildRoot,
    name: '$command runtime events',
  );
  final events = _jsonLines(
    eventText,
    '$command runtime event',
    _runtimeEventLimit,
  );
  var sequence = 0;
  var observed = false;
  for (final event in events) {
    _closedKeys(event, const <String>{
      'schema_version',
      'session_id',
      'sequence',
      'timestamp',
      'eventKind',
      'origin',
      'payload',
    }, '$command runtime event');
    final nextSequence = event['sequence'];
    if (event['schema_version'] != 1 ||
        event['session_id'] != session ||
        nextSequence is! int ||
        nextSequence <= sequence) {
      throw StateError('$command runtime event is stale or invalid');
    }
    sequence = nextSequence;
    _boundedString(event['timestamp'], '$command event timestamp');
    final kind = _boundedString(event['eventKind'], '$command eventKind');
    _boundedString(event['origin'], '$command event origin');
    final eventPayload = _object(event['payload'], '$command event payload');
    if (utf8.encode(jsonEncode(eventPayload)).length > _ownerStreamLimit) {
      throw StateError('$command runtime event payload exceeds its limit');
    }
    if (observationToken != null && kind == 'log.emitted') {
      final message = eventPayload['message'];
      if (message is String && message.contains(observationToken)) {
        observed = true;
      }
    }
  }
  if (observationToken != null && !observed) {
    throw StateError(
      'run observation is missing from its same-session log event',
    );
  }
  return session;
}

Future<String> _resolveOwnerDirectory(String workspace, String path) async {
  final resolved = await Directory(
    _ownerPath(workspace, path),
  ).resolveSymbolicLinks();
  _requireContained(workspace, resolved);
  return resolved;
}

Future<String> _readOwnerFile(
  String path, {
  required String containedRoot,
  required String name,
}) async {
  final resolved = await File(path).resolveSymbolicLinks();
  _requireContained(containedRoot, resolved);
  final file = File(resolved);
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file || stat.size > _ownerStreamLimit) {
    throw StateError('$name is missing or exceeds its owner-output limit');
  }
  final bytes = <int>[];
  await for (final chunk in file.openRead()) {
    final remaining = _ownerStreamLimit + 1 - bytes.length;
    if (remaining > 0) {
      bytes.addAll(chunk.take(remaining));
    }
    if (bytes.length > _ownerStreamLimit || chunk.length > remaining) {
      throw StateError('$name exceeds its owner-output limit');
    }
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw StateError('$name is not valid UTF-8');
  }
}

List<Map<String, Object?>> _jsonLines(String text, String name, int limit) {
  final lines = text
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  if (lines.length > limit) {
    throw StateError('$name count exceeds its limit');
  }
  return <Map<String, Object?>>[
    for (final line in lines) _jsonObject(line, name),
  ];
}

void _requireSuccessful(_CommandResult result) {
  if (!result.spawned ||
      result.timedOut ||
      result.outputExceeded ||
      result.stdoutBytes.length > _ownerStreamLimit ||
      result.stderrBytes.length > _ownerStreamLimit ||
      result.exitCode != 0) {
    throw StateError('owner command failed its process boundary');
  }
}

Future<void> _requireSavedDigest(File source, String expected) async {
  final actual = sha256.convert(await source.readAsBytes()).toString();
  if (actual != expected) {
    throw StateError('saved source changed during the workflow sequence');
  }
}

void _requireContained(String root, String target) {
  final separator = Platform.pathSeparator;
  final normalizedRoot = Platform.isWindows ? root.toLowerCase() : root;
  final normalizedTarget = Platform.isWindows ? target.toLowerCase() : target;
  if (normalizedTarget != normalizedRoot &&
      !normalizedTarget.startsWith('$normalizedRoot$separator')) {
    throw StateError('owner path escapes the isolated workspace');
  }
}

String _ownerPath(String workspaceRoot, String value) {
  if (_isNativeAbsolutePath(value)) {
    return value;
  }
  if (_looksRootedPath(value)) {
    throw StateError('owner path uses a non-native or drive-relative root');
  }
  final normalized = value.replaceAll(RegExp(r'[\\/]'), Platform.pathSeparator);
  return '$workspaceRoot${Platform.pathSeparator}$normalized';
}

String _boundedOwnerPath(Object? value, String name) {
  final path = _boundedString(value, name);
  if (path.contains('\u0000') ||
      _windowsDriveRelativePath.hasMatch(path) &&
          !_windowsDrivePath.hasMatch(path) ||
      path.split(RegExp(r'[\\/]')).contains('..')) {
    throw StateError('$name escapes the isolated workspace');
  }
  return path;
}

bool _isNativeAbsolutePath(String value) {
  if (Platform.isWindows) {
    return _windowsDrivePath.hasMatch(value) ||
        value.startsWith(r'\\') ||
        value.startsWith('//');
  }
  return value.startsWith('/');
}

bool _looksRootedPath(String value) =>
    value.startsWith('/') ||
    value.startsWith('\\') ||
    _windowsDriveRelativePath.hasMatch(value);

Map<String, Object?> _jsonObject(String text, String name) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw StateError('$name emitted malformed JSON');
  }
  return _object(decoded, name);
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map) {
    throw StateError('$name must be an object');
  }
  return <String, Object?>{
    for (final entry in value.entries) '${entry.key}': entry.value,
  };
}

void _closedKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String name,
) {
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    throw StateError('$name schema is not closed');
  }
}

List<Object?> _list(Object? value, String name) {
  if (value is! List) {
    throw StateError('$name must be an array');
  }
  return List<Object?>.from(value);
}

String _boundedString(Object? value, String name) {
  if (value is! String ||
      value.isEmpty ||
      utf8.encode(value).length > _projectedStringLimit) {
    throw StateError('$name is missing or exceeds its limit');
  }
  return value;
}

void _emitContract({
  required String caseName,
  required String outcome,
  required String category,
}) {
  stdout.writeln(
    '$_contractMarker${jsonEncode(<String, Object?>{'schema_version': 1, 'scenario': _scenario, 'evidence_kind': 'deterministic-contract', 'case': caseName, 'accepted': true, 'outcome': outcome, 'error_category': category, 'success_observation': false})}',
  );
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

Map<String, Object?> _currentWorkflowEnvelope({
  required String command,
  required String buildRoot,
  required String artifactDir,
  required String diagDir,
}) => <String, Object?>{
  'action': command,
  'command': command,
  'intent': command,
  'message': 'completed Styio $command via compile-plan',
  'mode': 'execute',
  'plan': <String, Object?>{
    'artifact_dir': artifactDir,
    'build_root': buildRoot,
    'cache_key': 'cache-key',
    'diag_dir': diagDir,
    'path': '$buildRoot${Platform.pathSeparator}plan.json',
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
    'kind': 'bin',
    'name': _binTarget,
    'package': _package,
    'package_id': _packageId,
  },
};

Map<String, Object?> _currentReceipt({
  required String command,
  required String workspace,
  required String buildRoot,
  required String artifactDir,
  required String diagDir,
  required String eventsPath,
}) => <String, Object?>{
  'schema_version': 1,
  'tool': 'styio',
  'compiler_version': '0.1.0',
  'channel': 'nightly',
  'plan_version': 1,
  'intent': command,
  'session_id': 'check-session',
  'executed': false,
  'wall_time_ms': 1,
  'generated_at': '2026-01-01T00:00:00Z',
  'dict_impl': <String, Object?>{'selected': 'hash'},
  'entry': <String, Object?>{
    'package_id': _packageId,
    'target_kind': 'bin',
    'target_name': _binTarget,
    'file':
        '$workspace${Platform.pathSeparator}src'
        '${Platform.pathSeparator}main.styio',
  },
  'outputs': <String, Object?>{
    'build_root': buildRoot,
    'artifact_dir': artifactDir,
    'diag_dir': diagDir,
    'runtime_events_path': eventsPath,
  },
  'artifacts': <String>[],
};

bool _enabled(String? value) => const <String>{
  '1',
  'true',
  'yes',
  'on',
}.contains(value?.trim().toLowerCase());

String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required by the opt-in product gate');
  }
  return value;
}
