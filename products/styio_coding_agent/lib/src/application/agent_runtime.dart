library;

import 'agent_session_service.dart';

final class AgentRuntime {
  AgentRuntime({required AgentSessionService sessionService})
    : _sessionService = sessionService;

  final AgentSessionService _sessionService;

  Future<AgentRunReceipt> run(AgentRunRequest request) =>
      _sessionService.run(request);

  bool cancel(String sessionId) => _sessionService.cancel(sessionId);

  AgentSessionState? stateOf(String sessionId) =>
      _sessionService.stateOf(sessionId);

  void dispose() => _sessionService.dispose();
}
