import 'dart:collection';

import '../agent_client/tools/ide_tool_catalog.dart';

final class McpExtensionContribution {
  McpExtensionContribution({
    required this.id,
    required Iterable<IdeToolAdapter> tools,
  }) : tools = UnmodifiableListView<IdeToolAdapter>(
         List<IdeToolAdapter>.of(tools),
       ) {
    if (!id.startsWith('styio.')) {
      throw ArgumentError.value(
        id,
        'id',
        'extension contribution ids must use the styio. namespace',
      );
    }
    if (this.tools.isEmpty ||
        this.tools.any((tool) => !tool.descriptor.name.startsWith('styio.'))) {
      throw ArgumentError(
        'extension tools must be non-empty and use the styio. namespace',
      );
    }
  }

  final String id;
  final List<IdeToolAdapter> tools;
}

final class McpExtensionRegistry {
  McpExtensionRegistry(this._catalog);

  final IdeToolCatalog _catalog;
  final Map<String, McpExtensionContribution> _contributions =
      <String, McpExtensionContribution>{};

  void register(McpExtensionContribution contribution) {
    if (_contributions.containsKey(contribution.id)) {
      throw ArgumentError.value(
        contribution.id,
        'contribution',
        'extension contribution is already registered',
      );
    }
    _catalog.registerAll(contribution.tools);
    _contributions[contribution.id] = contribution;
  }

  void unregister(String id) {
    final contribution = _contributions.remove(id);
    if (contribution == null) {
      return;
    }
    _catalog.unregisterAll(
      contribution.tools.map((tool) => tool.descriptor.name),
    );
  }
}
