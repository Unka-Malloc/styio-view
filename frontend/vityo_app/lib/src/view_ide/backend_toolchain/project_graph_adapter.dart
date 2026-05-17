import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'project_graph_adapter_web.dart'
    if (dart.library.io) 'project_graph_adapter_io.dart'
    as platform_adapter;
import 'project_graph_contract.dart';

abstract class ProjectGraphAdapter {
  AdapterCapabilitySnapshot get capabilitySnapshot;

  Future<ProjectGraphSnapshot> loadProjectGraph();
}

Future<ProjectGraphAdapter> createProjectGraphAdapter({
  required PlatformTarget platformTarget,
}) {
  return platform_adapter.createPlatformProjectGraphAdapter(
    platformTarget: platformTarget,
  );
}
