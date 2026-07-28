import '../platform/platform_target.dart';
import 'dependency_source_adapter.dart';
import 'deployment_adapter.dart';
import 'execution_adapter.dart';
import 'project_graph_adapter.dart';
import 'project_graph_contract.dart';
import 'runtime_event_adapter.dart';
import 'toolchain_management_adapter.dart';

abstract interface class BackendProvider {
  String get id;

  Set<PlatformTarget> get supportedPlatforms;

  int get priority;

  Future<ProjectGraphAdapter> createProjectGraphAdapter();

  Future<ExecutionAdapter> createExecutionAdapter(
    ProjectGraphSnapshot projectGraph,
  );

  RuntimeEventAdapter createRuntimeEventAdapter();

  Future<DependencySourceAdapter> createDependencySourceAdapter();

  Future<DeploymentAdapter> createDeploymentAdapter();

  Future<ToolchainManagementAdapter> createToolchainManagementAdapter();
}

class BackendProviderRegistry {
  BackendProviderRegistry({Iterable<BackendProvider> providers = const []}) {
    for (final provider in providers) {
      register(provider);
    }
  }

  final Map<String, BackendProvider> _providersById =
      <String, BackendProvider>{};

  List<BackendProvider> get providers =>
      List<BackendProvider>.unmodifiable(_providersById.values);

  void register(BackendProvider provider) {
    final id = provider.id.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        provider.id,
        'provider.id',
        'must not be empty',
      );
    }
    if (_providersById.containsKey(id)) {
      throw StateError('Backend provider "$id" is already registered.');
    }
    if (provider.supportedPlatforms.isEmpty) {
      throw ArgumentError.value(
        provider.supportedPlatforms,
        'provider.supportedPlatforms',
        'must not be empty',
      );
    }
    _providersById[id] = provider;
  }

  BackendProvider resolve(PlatformTarget platformTarget) {
    final candidates =
        _providersById.values
            .where(
              (provider) =>
                  provider.supportedPlatforms.contains(platformTarget),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final byPriority = right.priority.compareTo(left.priority);
            return byPriority != 0 ? byPriority : left.id.compareTo(right.id);
          });
    if (candidates.isEmpty) {
      throw StateError(
        'No backend provider is registered for ${platformTarget.wireValue}.',
      );
    }
    if (candidates.length > 1 &&
        candidates[0].priority == candidates[1].priority) {
      final conflictingIds = candidates
          .where((candidate) => candidate.priority == candidates[0].priority)
          .map((candidate) => candidate.id)
          .join(', ');
      throw StateError(
        'Backend providers have equal priority for '
        '${platformTarget.wireValue}: $conflictingIds.',
      );
    }
    return candidates.first;
  }
}
