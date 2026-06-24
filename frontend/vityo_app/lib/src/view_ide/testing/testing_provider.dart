import '../foundation/foundation.dart';
import '../debugger/debug_launch_contract.dart';
import '../runtime/runtime.dart';

enum TestRunStatus { passed, failed, skipped, error, notRun }

extension TestRunStatusWire on TestRunStatus {
  String get wireValue {
    return switch (this) {
      TestRunStatus.passed => 'passed',
      TestRunStatus.failed => 'failed',
      TestRunStatus.skipped => 'skipped',
      TestRunStatus.error => 'error',
      TestRunStatus.notRun => 'not-run',
    };
  }
}

TestRunStatus testRunStatusFromWireValue(String? value) {
  return switch (value) {
    'passed' => TestRunStatus.passed,
    'failed' => TestRunStatus.failed,
    'skipped' => TestRunStatus.skipped,
    'error' => TestRunStatus.error,
    'not-run' => TestRunStatus.notRun,
    _ => TestRunStatus.notRun,
  };
}

class TestRunRequest {
  const TestRunRequest({
    required this.workspaceRoot,
    this.targetId = '',
    this.filter = '',
    this.debug = false,
  });

  final String workspaceRoot;
  final String targetId;
  final String filter;
  final bool debug;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceRoot': workspaceRoot,
      if (targetId.isNotEmpty) 'targetId': targetId,
      if (filter.isNotEmpty) 'filter': filter,
      'debug': debug,
    };
  }
}

class TestDiscoveryRequest {
  const TestDiscoveryRequest({
    required this.workspaceRoot,
    this.targetId = '',
    this.filter = '',
  });

  final String workspaceRoot;
  final String targetId;
  final String filter;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceRoot': workspaceRoot,
      if (targetId.isNotEmpty) 'targetId': targetId,
      if (filter.isNotEmpty) 'filter': filter,
    };
  }
}

class TestRunConfiguration {
  const TestRunConfiguration({
    required this.id,
    required this.label,
    required this.workspaceRoot,
    this.providerId = '',
    this.targetId = '',
    this.filter = '',
    this.debug = false,
    this.metadata = const <String, Object?>{},
  });

  factory TestRunConfiguration.fromJson(Map<String, Object?> json) {
    final metadata = json['metadata'];
    return TestRunConfiguration(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      workspaceRoot: json['workspaceRoot'] as String? ?? '',
      providerId: json['providerId'] as String? ?? '',
      targetId: json['targetId'] as String? ?? '',
      filter: json['filter'] as String? ?? '',
      debug: json['debug'] as bool? ?? false,
      metadata: metadata is Map
          ? metadata.map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            )
          : const <String, Object?>{},
    );
  }

  final String id;
  final String label;
  final String workspaceRoot;
  final String providerId;
  final String targetId;
  final String filter;
  final bool debug;
  final Map<String, Object?> metadata;

  bool get ready => id.trim().isNotEmpty && workspaceRoot.trim().isNotEmpty;

  TestRunConfiguration copyWith({
    String? id,
    String? label,
    String? workspaceRoot,
    String? providerId,
    String? targetId,
    String? filter,
    bool? debug,
    Map<String, Object?>? metadata,
  }) {
    return TestRunConfiguration(
      id: id ?? this.id,
      label: label ?? this.label,
      workspaceRoot: workspaceRoot ?? this.workspaceRoot,
      providerId: providerId ?? this.providerId,
      targetId: targetId ?? this.targetId,
      filter: filter ?? this.filter,
      debug: debug ?? this.debug,
      metadata: metadata ?? this.metadata,
    );
  }

  TestRunRequest toRunRequest() {
    return TestRunRequest(
      workspaceRoot: workspaceRoot.trim(),
      targetId: targetId.trim(),
      filter: filter.trim(),
      debug: debug,
    );
  }

  TestDiscoveryRequest toDiscoveryRequest() {
    return TestDiscoveryRequest(
      workspaceRoot: workspaceRoot.trim(),
      targetId: targetId.trim(),
      filter: filter.trim(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'workspaceRoot': workspaceRoot,
      if (providerId.isNotEmpty) 'providerId': providerId,
      if (targetId.isNotEmpty) 'targetId': targetId,
      if (filter.isNotEmpty) 'filter': filter,
      'debug': debug,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

enum TestNodeKind { suite, test }

extension TestNodeKindWire on TestNodeKind {
  String get wireValue {
    return switch (this) {
      TestNodeKind.suite => 'suite',
      TestNodeKind.test => 'test',
    };
  }
}

class TestNode {
  const TestNode({
    required this.id,
    required this.label,
    required this.kind,
    this.uri = '',
    this.children = const <TestNode>[],
  });

  final String id;
  final String label;
  final TestNodeKind kind;
  final String uri;
  final List<TestNode> children;

  int get testCount {
    if (kind == TestNodeKind.test) {
      return 1;
    }
    return children.fold<int>(0, (total, child) => total + child.testCount);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'kind': kind.wireValue,
      if (uri.isNotEmpty) 'uri': uri,
      if (children.isNotEmpty)
        'children': children
            .map((child) => child.toJson())
            .toList(growable: false),
      'testCount': testCount,
    };
  }
}

class TestDiscoveryResult {
  const TestDiscoveryResult({
    required this.providerId,
    required this.roots,
    this.message = '',
  });

  final String providerId;
  final List<TestNode> roots;
  final String message;

  int get testCount {
    return roots.fold<int>(0, (total, root) => total + root.testCount);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'testCount': testCount,
      if (message.isNotEmpty) 'message': message,
      'roots': roots.map((root) => root.toJson()).toList(growable: false),
    };
  }
}

class TestCaseResult {
  const TestCaseResult({
    required this.name,
    required this.status,
    this.id = '',
    this.durationMs,
    this.message = '',
  });

  final String id;
  final String name;
  final TestRunStatus status;
  final int? durationMs;
  final String message;

  factory TestCaseResult.fromJson(Map<String, Object?> json) {
    return TestCaseResult(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      status: testRunStatusFromWireValue(json['status'] as String?),
      durationMs: json['durationMs'] as int?,
      message: json['message'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (id.isNotEmpty) 'id': id,
      'name': name,
      'status': status.wireValue,
      if (durationMs != null) 'durationMs': durationMs,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

class TestRunResult {
  const TestRunResult({
    required this.providerId,
    required this.status,
    required this.message,
    this.runner = '',
    this.totalCount = 0,
    this.passedCount = 0,
    this.failedCount = 0,
    this.skippedCount = 0,
    this.cases = const <TestCaseResult>[],
    this.metadata = const <String, Object?>{},
  });

  final String providerId;
  final String runner;
  final TestRunStatus status;
  final String message;
  final int totalCount;
  final int passedCount;
  final int failedCount;
  final int skippedCount;
  final List<TestCaseResult> cases;
  final Map<String, Object?> metadata;

  factory TestRunResult.fromJson(Map<String, Object?> json) {
    final cases = json['cases'];
    final metadata = json['metadata'];
    return TestRunResult(
      providerId: json['providerId'] as String? ?? '',
      runner: json['runner'] as String? ?? '',
      status: testRunStatusFromWireValue(json['status'] as String?),
      message: json['message'] as String? ?? '',
      totalCount: json['totalCount'] as int? ?? 0,
      passedCount: json['passedCount'] as int? ?? 0,
      failedCount: json['failedCount'] as int? ?? 0,
      skippedCount: json['skippedCount'] as int? ?? 0,
      cases: cases is List
          ? cases
                .whereType<Map>()
                .map(
                  (testCase) => TestCaseResult.fromJson(
                    testCase.map(
                      (key, value) =>
                          MapEntry<String, Object?>(key.toString(), value),
                    ),
                  ),
                )
                .toList(growable: false)
          : const <TestCaseResult>[],
      metadata: metadata is Map
          ? metadata.map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            )
          : const <String, Object?>{},
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      if (runner.isNotEmpty) 'runner': runner,
      'status': status.wireValue,
      'message': message,
      'totalCount': totalCount,
      'passedCount': passedCount,
      'failedCount': failedCount,
      'skippedCount': skippedCount,
      if (cases.isNotEmpty)
        'cases': cases
            .map((testCase) => testCase.toJson())
            .toList(growable: false),
      if (failedTests.isNotEmpty) 'failedTests': failedTests,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  List<Map<String, Object?>> get failedTests {
    return cases
        .where((testCase) => testCase.status == TestRunStatus.failed)
        .map((testCase) => testCase.toJson())
        .toList(growable: false);
  }

  String get outputChannelId => 'test.$providerId';

  RuntimeOutputStreamSubscriptionPlan outputSubscriptionPlan({
    String taskId = '',
    RuntimeOutputRetentionPolicy retentionPolicy =
        const RuntimeOutputRetentionPolicy.workspaceHistory(),
  }) {
    return RuntimeOutputStreamSubscriptionPlan.forManager(
      taskId: taskId.isEmpty ? outputChannelId : taskId,
      managerId: 'testing-session',
      routeKind: outputRouteKind,
      channelIds: <String>[outputChannelId],
      kinds: const <RuntimeOutputChannelKind>[
        RuntimeOutputChannelKind.runtimeEvents,
      ],
      status: RuntimeOutputSubscriptionStatus.active,
      retentionPolicy: retentionPolicy,
      metadata: <String, Object?>{
        'providerId': providerId,
        if (runner.isNotEmpty) 'runner': runner,
        'testStatus': status.wireValue,
      },
    );
  }

  RuntimeOutputEvent outputEvent({required DateTime timestamp}) {
    return RuntimeOutputEvent(
      channelId: outputChannelId,
      label: runner.isEmpty ? 'Test Run' : 'Test Run $runner',
      kind: RuntimeOutputChannelKind.runtimeEvents,
      message: message,
      timestamp: timestamp,
      metadata: <String, Object?>{
        'providerId': providerId,
        if (runner.isNotEmpty) 'runner': runner,
        'status': status.wireValue,
        'totalCount': totalCount,
        'passedCount': passedCount,
        'failedCount': failedCount,
        'skippedCount': skippedCount,
      },
    );
  }

  String get outputRouteKind => 'test-run';
}

class FailedTestRerunPlanner {
  const FailedTestRerunPlanner();

  TestRunConfiguration? plan({
    required TestRunResult? lastRun,
    required String workspaceRoot,
    bool debug = false,
  }) {
    final failedCases =
        lastRun?.cases
            .where((testCase) => testCase.status == TestRunStatus.failed)
            .toList(growable: false) ??
        const <TestCaseResult>[];
    if (failedCases.isEmpty) {
      return null;
    }
    final filter = failedCases
        .map((testCase) => testCase.id.isNotEmpty ? testCase.id : testCase.name)
        .where((name) => name.trim().isNotEmpty)
        .map(RegExp.escape)
        .join('|');
    return TestRunConfiguration(
      id: 'rerun-failed',
      label: debug ? 'Debug Failed Tests' : 'Rerun Failed Tests',
      workspaceRoot: workspaceRoot,
      providerId: lastRun?.providerId ?? '',
      filter: filter,
      debug: debug,
      metadata: <String, Object?>{
        'failedCount': failedCases.length,
        'sourceRunProviderId': lastRun?.providerId,
        ..._debugLaunchMetadataFrom(
          lastRun?.metadata ?? const <String, Object?>{},
        ),
      },
    );
  }
}

class TestDebugLaunchRoutePlanner {
  const TestDebugLaunchRoutePlanner();

  DebugLaunchRoutePlan plan(TestRunConfiguration configuration) {
    final debugConfiguration = configuration.debug
        ? configuration
        : configuration.copyWith(debug: true);
    final debuggerExecutablePath =
        _metadataString(
          debugConfiguration.metadata,
          'debuggerExecutablePath',
        ) ??
        _metadataString(
          debugConfiguration.metadata,
          'debugAdapterExecutablePath',
        );
    final programPath = _resolveMetadataPath(
      _metadataString(debugConfiguration.metadata, 'programPath') ??
          _metadataString(debugConfiguration.metadata, 'testProgramPath'),
      debugConfiguration.workspaceRoot,
    );
    final adapterProtocol =
        _metadataString(debugConfiguration.metadata, 'adapterProtocol') ??
        'dap';
    final missingExecutable =
        debuggerExecutablePath == null || debuggerExecutablePath.trim().isEmpty;
    final missingProgram = programPath == null || programPath.trim().isEmpty;
    final launch = DebugLaunchConfiguration(
      readiness: missingExecutable || missingProgram
          ? DebugLaunchReadiness.missingProgram
          : DebugLaunchReadiness.ready,
      reason: missingExecutable
          ? 'Test debug launch blocked: debuggerExecutablePath is missing.'
          : missingProgram
          ? 'Test debug launch blocked: programPath is missing.'
          : 'Test debug launch route is ready.',
      debuggerId:
          _metadataString(debugConfiguration.metadata, 'debuggerId') ??
          'test-debug.${debugConfiguration.providerId}',
      debuggerLabel:
          _metadataString(debugConfiguration.metadata, 'debuggerLabel') ??
          'Test Debug Adapter',
      debuggerExecutablePath: debuggerExecutablePath ?? '',
      debuggerArguments:
          _metadataStringList(
            debugConfiguration.metadata,
            'debuggerArguments',
          ) ??
          _metadataStringList(
            debugConfiguration.metadata,
            'debugAdapterArguments',
          ) ??
          _metadataStringList(
            debugConfiguration.metadata,
            'adapterArguments',
          ) ??
          const <String>[],
      adapterProtocol: adapterProtocol,
      programPath: programPath,
      cwd:
          _resolveMetadataPath(
            _metadataString(debugConfiguration.metadata, 'cwd'),
            debugConfiguration.workspaceRoot,
          ) ??
          debugConfiguration.workspaceRoot,
      arguments: <String>[
        ...?_metadataStringList(debugConfiguration.metadata, 'arguments'),
        ...?_metadataStringList(debugConfiguration.metadata, 'args'),
        if (debugConfiguration.filter.trim().isNotEmpty)
          '--test-filter=${debugConfiguration.filter.trim()}',
      ],
      environment: _metadataStringMap(
        debugConfiguration.metadata,
        'environment',
      ),
    );
    return launch.toRoutePlan(
      profileId: debugConfiguration.id.isEmpty
          ? 'test-debug'
          : 'test-debug.${debugConfiguration.id}',
      taskId: debugConfiguration.id.isEmpty
          ? 'debug.test'
          : 'debug.test.${debugConfiguration.id}',
      label: debugConfiguration.label,
    );
  }
}

Map<String, Object?> _debugLaunchMetadataFrom(Map<String, Object?> metadata) {
  const keys = <String>{
    'debuggerId',
    'debuggerLabel',
    'debuggerExecutablePath',
    'debugAdapterExecutablePath',
    'debuggerArguments',
    'debugAdapterArguments',
    'adapterArguments',
    'adapterProtocol',
    'programPath',
    'testProgramPath',
    'cwd',
    'arguments',
    'args',
    'environment',
  };
  return <String, Object?>{
    for (final entry in metadata.entries)
      if (keys.contains(entry.key)) entry.key: entry.value,
  };
}

String? _resolveMetadataPath(String? path, String workspaceRoot) {
  if (path == null) {
    return null;
  }
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.startsWith('/') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed) ||
      workspaceRoot.trim().isEmpty) {
    return trimmed;
  }
  final normalizedRoot = workspaceRoot.endsWith('/')
      ? workspaceRoot.substring(0, workspaceRoot.length - 1)
      : workspaceRoot;
  return '$normalizedRoot/$trimmed';
}

String? _metadataString(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String>? _metadataStringList(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : <String>[trimmed];
  }
  if (value is! Iterable<Object?>) {
    return null;
  }
  final entries = value
      .whereType<String>()
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
  return entries.isEmpty ? null : entries;
}

Map<String, String> _metadataStringMap(
  Map<String, Object?> metadata,
  String key,
) {
  final value = metadata[key];
  if (value is! Map<Object?, Object?>) {
    return const <String, String>{};
  }
  return <String, String>{
    for (final entry in value.entries)
      if (entry.key is String && entry.value is String)
        (entry.key! as String): (entry.value! as String),
  };
}

abstract class TestRunProvider {
  const TestRunProvider();

  String get providerId;

  Future<TestRunResult> run(TestRunRequest request);
}

abstract class TestDiscoveryProvider {
  const TestDiscoveryProvider();

  String get providerId;

  Future<TestDiscoveryResult> discover(TestDiscoveryRequest request);
}

class StaticTestRunProvider extends TestRunProvider {
  const StaticTestRunProvider({required this.providerId, required this.result});

  @override
  final String providerId;
  final TestRunResult result;

  @override
  Future<TestRunResult> run(TestRunRequest request) async {
    return result;
  }
}

class StaticTestDiscoveryProvider extends TestDiscoveryProvider {
  const StaticTestDiscoveryProvider({
    required this.providerId,
    required this.result,
  });

  @override
  final String providerId;
  final TestDiscoveryResult result;

  @override
  Future<TestDiscoveryResult> discover(TestDiscoveryRequest request) async {
    return result;
  }
}

class TestingProviderRegistration {
  const TestingProviderRegistration({
    required this.id,
    required this.provider,
    this.priority = 0,
    this.state = FoundationRegistryEntryState.registered,
    this.metadata = const <String, Object?>{},
    this.todo = '',
  });

  final String id;
  final TestRunProvider provider;
  final int priority;
  final FoundationRegistryEntryState state;
  final Map<String, Object?> metadata;
  final String todo;
}

class TestingProviderRegistry {
  TestingProviderRegistry({
    FoundationProviderRegistry<TestRunProvider>? registry,
  }) : _registry = registry ?? FoundationProviderRegistry<TestRunProvider>();

  static const String owner = 'interaction.testing';
  static const String runCapability = 'testing.run';
  static const String discoverCapability = 'testing.discover';

  final FoundationProviderRegistry<TestRunProvider> _registry;

  void register(TestingProviderRegistration registration) {
    _registry.register(
      FoundationProviderRegistration<TestRunProvider>(
        id: registration.id,
        owner: owner,
        provider: registration.provider,
        layer: 'interaction',
        priority: registration.priority,
        state: registration.state,
        capabilities: const <String>[runCapability],
        metadata: <String, Object?>{
          ...registration.metadata,
          'providerContract': 'test-run-provider',
        },
        todo: registration.todo,
      ),
    );
  }

  FoundationRegistryEntry<TestRunProvider>? resolve({bool activeOnly = true}) {
    return _registry.resolve(
      capability: runCapability,
      owner: owner,
      activeOnly: activeOnly,
    );
  }

  TestRunProvider? provider({bool activeOnly = true}) {
    return resolve(activeOnly: activeOnly)?.value;
  }

  FoundationRegistryManifest manifest({FoundationRegistryEntryState? state}) {
    return _registry.manifest(owner: owner, state: state);
  }
}

class TestingDiscoveryProviderRegistration {
  const TestingDiscoveryProviderRegistration({
    required this.id,
    required this.provider,
    this.priority = 0,
    this.state = FoundationRegistryEntryState.registered,
    this.metadata = const <String, Object?>{},
    this.todo = '',
  });

  final String id;
  final TestDiscoveryProvider provider;
  final int priority;
  final FoundationRegistryEntryState state;
  final Map<String, Object?> metadata;
  final String todo;
}

class TestingDiscoveryProviderRegistry {
  TestingDiscoveryProviderRegistry({
    FoundationProviderRegistry<TestDiscoveryProvider>? registry,
  }) : _registry =
           registry ?? FoundationProviderRegistry<TestDiscoveryProvider>();

  static const String owner = TestingProviderRegistry.owner;
  static const String discoverCapability =
      TestingProviderRegistry.discoverCapability;

  final FoundationProviderRegistry<TestDiscoveryProvider> _registry;

  void register(TestingDiscoveryProviderRegistration registration) {
    _registry.register(
      FoundationProviderRegistration<TestDiscoveryProvider>(
        id: registration.id,
        owner: owner,
        provider: registration.provider,
        layer: 'interaction',
        priority: registration.priority,
        state: registration.state,
        capabilities: const <String>[discoverCapability],
        metadata: <String, Object?>{
          ...registration.metadata,
          'providerContract': 'test-discovery-provider',
        },
        todo: registration.todo,
      ),
    );
  }

  FoundationRegistryEntry<TestDiscoveryProvider>? resolve({
    bool activeOnly = true,
  }) {
    return _registry.resolve(
      capability: discoverCapability,
      owner: owner,
      activeOnly: activeOnly,
    );
  }

  TestDiscoveryProvider? provider({bool activeOnly = true}) {
    return resolve(activeOnly: activeOnly)?.value;
  }

  FoundationRegistryManifest manifest({FoundationRegistryEntryState? state}) {
    return _registry.manifest(owner: owner, state: state);
  }
}

class TestingProviderCatalog {
  TestingProviderCatalog({
    TestingProviderRegistry? runRegistry,
    TestingDiscoveryProviderRegistry? discoveryRegistry,
  }) : runRegistry = runRegistry ?? TestingProviderRegistry(),
       discoveryRegistry =
           discoveryRegistry ?? TestingDiscoveryProviderRegistry();

  final TestingProviderRegistry runRegistry;
  final TestingDiscoveryProviderRegistry discoveryRegistry;

  void registerRunProvider(TestingProviderRegistration registration) {
    runRegistry.register(registration);
  }

  void registerDiscoveryProvider(
    TestingDiscoveryProviderRegistration registration,
  ) {
    discoveryRegistry.register(registration);
  }

  TestRunProvider? runProvider({bool activeOnly = true}) {
    return runRegistry.provider(activeOnly: activeOnly);
  }

  TestDiscoveryProvider? discoveryProvider({bool activeOnly = true}) {
    return discoveryRegistry.provider(activeOnly: activeOnly);
  }

  Map<String, Object?> manifest({FoundationRegistryEntryState? state}) {
    return <String, Object?>{
      'owner': TestingProviderRegistry.owner,
      'run': runRegistry.manifest(state: state).toJson(),
      'discovery': discoveryRegistry.manifest(state: state).toJson(),
    };
  }
}

class CTestOutputParser {
  const CTestOutputParser();

  TestRunResult parse({
    required String providerId,
    required int exitCode,
    required String stdout,
    String stderr = '',
  }) {
    final summary = _summaryPattern.firstMatch(stdout);
    final failedCases = _failedCases(stdout);
    final totalCount = int.tryParse(summary?.group(3) ?? '') ?? 0;
    final failedCount =
        int.tryParse(summary?.group(2) ?? '') ??
        (exitCode == 0 ? 0 : failedCases.length);
    final passedCount = totalCount > 0 ? totalCount - failedCount : 0;
    final status = exitCode == 0 && failedCount == 0
        ? TestRunStatus.passed
        : TestRunStatus.failed;
    final message = status == TestRunStatus.passed
        ? 'CTest completed successfully.'
        : stderr.trim().isNotEmpty
        ? stderr.trim()
        : 'CTest reported $failedCount failed test(s).';

    return TestRunResult(
      providerId: providerId,
      runner: 'ctest',
      status: status,
      message: message,
      totalCount: totalCount,
      passedCount: passedCount,
      failedCount: failedCount,
      cases: List<TestCaseResult>.unmodifiable(failedCases),
      metadata: <String, Object?>{'exitCode': exitCode},
    );
  }

  static final RegExp _summaryPattern = RegExp(
    r'(\d+)% tests passed,\s+(\d+) tests failed out of\s+(\d+)',
  );

  static final RegExp _failedTestPattern = RegExp(
    r'^\s*\d+\s+-\s+(.+?)\s+\((.+)\)\s*$',
    multiLine: true,
  );

  List<TestCaseResult> _failedCases(String output) {
    return _failedTestPattern
        .allMatches(output)
        .map(
          (match) => TestCaseResult(
            name: match.group(1)?.trim() ?? 'unknown',
            status: TestRunStatus.failed,
            message: match.group(2)?.trim() ?? 'failed',
          ),
        )
        .toList(growable: false);
  }
}

/// Lightweight health state for a testing provider contribution.
///
/// This mirrors the provider/registry model used by mature IDEs: provider
/// discovery stays decoupled from execution, while the UI/runtime can still
/// surface whether a provider is active and which retry action is safe.
class TestingProviderHealthRecord {
  const TestingProviderHealthRecord({
    required this.surface,
    required this.id,
    required this.state,
    required this.active,
    this.providerContract = '',
    this.todo = '',
    this.metadata = const <String, Object?>{},
  });

  final String surface;
  final String id;
  final String state;
  final bool active;
  final String providerContract;
  final String todo;
  final Map<String, Object?> metadata;

  bool get hasTodo => todo.trim().startsWith('TODO:');

  String get label => '$surface:$id';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'surface': surface,
      'id': id,
      'state': state,
      'active': active,
      if (providerContract.isNotEmpty) 'providerContract': providerContract,
      if (todo.isNotEmpty) 'todo': todo,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class TestingProviderRetryAction {
  const TestingProviderRetryAction({
    required this.id,
    required this.surface,
    required this.providerId,
    required this.label,
    required this.enabled,
    required this.reason,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String surface;
  final String providerId;
  final String label;
  final bool enabled;
  final String reason;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'surface': surface,
      'providerId': providerId,
      'label': label,
      'enabled': enabled,
      'reason': reason,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class TestingProviderHealthSnapshot {
  const TestingProviderHealthSnapshot({
    required this.records,
    required this.retryActions,
  });

  factory TestingProviderHealthSnapshot.fromManifest(
    Map<String, Object?> manifest,
  ) {
    final records = <TestingProviderHealthRecord>[
      ..._recordsFromManifestSection(
        surface: 'discovery',
        section: manifest['discovery'],
      ),
      ..._recordsFromManifestSection(surface: 'run', section: manifest['run']),
    ];
    return TestingProviderHealthSnapshot(
      records: records,
      retryActions: _retryActionsFromRecords(records),
    );
  }

  final List<TestingProviderHealthRecord> records;
  final List<TestingProviderRetryAction> retryActions;

  bool get hasActiveDiscoveryProvider =>
      records.any((record) => record.surface == 'discovery' && record.active);

  bool get hasActiveRunProvider =>
      records.any((record) => record.surface == 'run' && record.active);

  bool get ready => hasActiveDiscoveryProvider && hasActiveRunProvider;

  String get summary {
    final activeDiscovery = hasActiveDiscoveryProvider ? 'ready' : 'missing';
    final activeRun = hasActiveRunProvider ? 'ready' : 'missing';
    return 'Testing providers: discovery $activeDiscovery, run $activeRun.';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'summary': summary,
      'records': records.map((record) => record.toJson()).toList(),
      'retryActions': retryActions.map((action) => action.toJson()).toList(),
    };
  }
}

class TestingProviderRetryPlan {
  const TestingProviderRetryPlan({
    required this.ready,
    required this.message,
    required this.actions,
  });

  factory TestingProviderRetryPlan.fromHealth(
    TestingProviderHealthSnapshot snapshot,
  ) {
    final enabledActions = snapshot.retryActions
        .where((action) => action.enabled)
        .toList(growable: false);
    return TestingProviderRetryPlan(
      ready: enabledActions.isNotEmpty,
      message: enabledActions.isEmpty
          ? '${snapshot.summary} TODO: register an active testing provider before retrying.'
          : '${snapshot.summary} ${enabledActions.length} retry action${enabledActions.length == 1 ? '' : 's'} available.',
      actions: snapshot.retryActions,
    );
  }

  final bool ready;
  final String message;
  final List<TestingProviderRetryAction> actions;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'message': message,
      'actions': actions.map((action) => action.toJson()).toList(),
    };
  }
}

extension TestingProviderCatalogHealth on TestingProviderCatalog {
  TestingProviderHealthSnapshot healthSnapshot() {
    return TestingProviderHealthSnapshot.fromManifest(manifest());
  }

  TestingProviderRetryPlan retryPlan() {
    return TestingProviderRetryPlan.fromHealth(healthSnapshot());
  }
}

List<TestingProviderHealthRecord> _recordsFromManifestSection({
  required String surface,
  required Object? section,
}) {
  if (section is! Map<Object?, Object?>) {
    return const <TestingProviderHealthRecord>[];
  }
  final rawEntries = section['entries'];
  if (rawEntries is! Iterable<Object?>) {
    return const <TestingProviderHealthRecord>[];
  }
  return rawEntries
      .whereType<Map<Object?, Object?>>()
      .map((entry) {
        final metadata = _stringObjectMap(entry['metadata']);
        final state = (entry['state'] as String? ?? '').trim();
        final id = (entry['id'] as String? ?? '').trim();
        return TestingProviderHealthRecord(
          surface: surface,
          id: id,
          state: state,
          active: state == 'active',
          providerContract: (metadata['providerContract'] as String? ?? '')
              .trim(),
          todo: (entry['todo'] as String? ?? '').trim(),
          metadata: metadata,
        );
      })
      .toList(growable: false);
}

List<TestingProviderRetryAction> _retryActionsFromRecords(
  List<TestingProviderHealthRecord> records,
) {
  final actions = <TestingProviderRetryAction>[];
  for (final surface in const <String>['discovery', 'run']) {
    final surfaceRecords = records
        .where((record) => record.surface == surface)
        .toList(growable: false);
    final activeRecords = surfaceRecords
        .where((record) => record.active)
        .toList(growable: false);
    if (activeRecords.isEmpty) {
      actions.add(
        TestingProviderRetryAction(
          id: 'testing.$surface.configure-provider',
          surface: surface,
          providerId: 'unavailable',
          label: 'Configure $surface test provider',
          enabled: false,
          reason:
              'No active $surface test provider is registered. TODO: register Styio, CTest, or custom testing adapters.',
        ),
      );
      continue;
    }
    for (final record in activeRecords) {
      actions.add(
        TestingProviderRetryAction(
          id: 'testing.$surface.retry.${record.id}',
          surface: surface,
          providerId: record.id,
          label: 'Retry $surface with ${record.id}',
          enabled: true,
          reason: 'Active $surface provider ${record.id} can be retried.',
          metadata: <String, Object?>{
            if (record.providerContract.isNotEmpty)
              'providerContract': record.providerContract,
            if (record.hasTodo) 'todo': record.todo,
          },
        ),
      );
    }
  }
  return actions;
}

Map<String, Object?> _stringObjectMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return const <String, Object?>{};
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}
