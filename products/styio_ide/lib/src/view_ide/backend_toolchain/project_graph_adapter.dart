import 'adapter_contracts.dart';
import 'project_graph_contract.dart';

abstract class ProjectGraphAdapter {
  AdapterCapabilitySnapshot get capabilitySnapshot;

  Future<ProjectGraphSnapshot> loadProjectGraph();
}
