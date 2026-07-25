import 'package:flutter/foundation.dart';

import '../../agent/agent.dart';

/// Owns bounded agent-facing IDE context independently from shell composition.
final class AgentController extends ChangeNotifier {
  AgentController({this.maxCommandResultRecords = 12})
    : assert(maxCommandResultRecords > 0);

  final int maxCommandResultRecords;
  final List<AgentCommandResultContext> _commandResults =
      <AgentCommandResultContext>[];

  AgentWorkspaceSearchResultContext? _lastWorkspaceSearch;
  AgentWorkspaceSymbolSearchResultContext? _lastWorkspaceSymbolSearch;
  AgentCommandResultContext? _lastCommandResult;
  AgentPromptProfileManifest _providerProfileManifest =
      const AgentPromptProfileManifest();

  AgentWorkspaceSearchResultContext? get lastWorkspaceSearch =>
      _lastWorkspaceSearch;
  AgentWorkspaceSymbolSearchResultContext? get lastWorkspaceSymbolSearch =>
      _lastWorkspaceSymbolSearch;
  AgentCommandResultContext? get lastCommandResult => _lastCommandResult;
  List<AgentCommandResultContext> get recentCommandResults =>
      List<AgentCommandResultContext>.unmodifiable(_commandResults);
  AgentPromptProfileManifest get providerProfileManifest =>
      _providerProfileManifest;

  void replaceProviderProfileManifest(AgentPromptProfileManifest manifest) {
    _providerProfileManifest = manifest;
    notifyListeners();
  }

  void recordCommandResult(AgentCommandResultContext result) {
    _lastCommandResult = result;
    _commandResults.insert(0, result);
    if (_commandResults.length > maxCommandResultRecords) {
      _commandResults.removeRange(
        maxCommandResultRecords,
        _commandResults.length,
      );
    }
    notifyListeners();
  }

  void replaceWorkspaceSearch({
    required AgentWorkspaceSearchResultContext text,
    required AgentWorkspaceSymbolSearchResultContext symbols,
  }) {
    _lastWorkspaceSearch = text;
    _lastWorkspaceSymbolSearch = symbols;
    notifyListeners();
  }
}
