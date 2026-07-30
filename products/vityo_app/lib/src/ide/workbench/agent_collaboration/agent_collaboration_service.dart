import 'dart:async';

import '../../agent_client/agent_client.dart';
import '../../workspace/workspace_change_set.dart';
import '../../workspace/workspace_transaction_service.dart';
import 'collaboration_store.dart';

/// Binds versioned Agent Client sessions to the immutable Workbench
/// projection.
///
/// The IDE owns only client lifecycle, projection, permission presentation,
/// and workspace transactions. Prompt scheduling, model selection, and durable
/// Agent history stay inside the Agent runtime behind the protocol.
final class AgentCollaborationService implements AgentWorkbenchCommandPort {
  factory AgentCollaborationService({
    required AgentClientRegistry registry,
    required WorkspaceTransactionService transactions,
    required Uri workspaceRoot,
    int maxTimelineEntriesPerSession = 128,
  }) {
    final commands = _DeferredCommandPort();
    final service = AgentCollaborationService._(
      registry: registry,
      workspaceRoot: workspaceRoot,
      store: AgentCollaborationStore(
        commands: commands,
        transactions: transactions,
        maxTimelineEntriesPerSession: maxTimelineEntriesPerSession,
      ),
    );
    commands.bind(service);
    return service;
  }

  AgentCollaborationService._({
    required AgentClientRegistry registry,
    required Uri workspaceRoot,
    required this.store,
  }) : _registry = registry,
       _workspaceRoot = workspaceRoot {
    _permissions = _registry.permissionRequests.listen(
      _handlePermissionRequest,
      onError: (Object _) {},
    );
  }

  final AgentClientRegistry _registry;
  final Uri _workspaceRoot;
  final AgentCollaborationStore store;
  final Map<String, _SessionBinding> _bindings = <String, _SessionBinding>{};
  late final StreamSubscription<AgentPermissionRequest> _permissions;
  bool _closed = false;

  CollaborationProjection get projection => store.projection;

  Stream<CollaborationProjection> get changes => store.changes;

  /// Opens one supervised Agent session and registers its projection.
  Future<CollaborationSessionProjection> openSession(String agentId) async {
    _ensureOpen();
    final session = await _registry.newSession(
      agentId: agentId,
      cwd: _workspaceRoot,
    );
    await _bind(session);
    return store.projection.session(session.id);
  }

  @override
  Future<void> steer(String sessionId, String prompt) async {
    final binding = _requireBinding(sessionId);
    binding.lastPrompt = prompt;
    await _prompt(binding, prompt);
  }

  @override
  Future<void> cancel(String sessionId) async {
    await _requireBinding(sessionId).session.cancel();
  }

  @override
  Future<void> retry(String sessionId) async {
    final binding = _requireBinding(sessionId);
    final prompt = binding.lastPrompt;
    if (prompt == null) {
      throw const CollaborationFailure(
        'nothing_to_retry',
        'Session has no prior prompt to replay',
      );
    }
    await _prompt(binding, prompt);
  }

  @override
  Future<void> reconnect(String sessionId) async {
    final binding = _requireBinding(sessionId);
    await binding.updates.cancel();
    final session = await _registry.reconnectSession(
      agentId: binding.agentId,
      sessionId: sessionId,
      cwd: _workspaceRoot,
    );
    await _bind(session, lastPrompt: binding.lastPrompt);
  }

  @override
  Future<void> resolvePermission({
    required String sessionId,
    required String permissionId,
    required AgentPermissionDecision decision,
  }) async {
    _requireBinding(sessionId);
    await _registry.resolvePermission(permissionId, decision);
  }

  Future<AgentChangeReviewProjection> proposeChange({
    required String sessionId,
    required WorkspaceChangeSet changeSet,
  }) => store.proposeChange(sessionId: sessionId, changeSet: changeSet);

  Future<AgentChangeReviewProjection> resolveChange({
    required String sessionId,
    required String changeSetId,
    required AgentChangeReviewDecision decision,
  }) => store.resolveChange(
    sessionId: sessionId,
    changeSetId: changeSetId,
    decision: decision,
  );

  Future<List<AgentShutdownReceipt>> close() async {
    if (_closed) {
      return const <AgentShutdownReceipt>[];
    }
    _closed = true;
    await _permissions.cancel();
    for (final binding in _bindings.values) {
      await binding.updates.cancel();
    }
    _bindings.clear();
    final receipts = await _registry.close();
    await store.close();
    return receipts;
  }

  Future<void> _bind(AgentClientSession session, {String? lastPrompt}) async {
    final binding = _SessionBinding(
      agentId: session.agentId,
      session: session,
      updates: session.updates.listen(
        (_) => unawaited(_project(session)),
        onError: (Object _) {},
      ),
    )..lastPrompt = lastPrompt;
    _bindings[session.id] = binding;
    await _project(session);
  }

  Future<void> _prompt(_SessionBinding binding, String prompt) async {
    try {
      await binding.session.prompt(prompt);
    } on AgentClientFailure catch (failure) {
      throw CollaborationFailure(failure.code, failure.message);
    } finally {
      await _project(binding.session);
    }
  }

  Future<void> _project(AgentClientSession session) async {
    if (_closed) {
      return;
    }
    try {
      await store.apply(session.snapshot);
    } on CollaborationFailure {
      // A stale or replayed snapshot never invalidates the live projection.
    }
  }

  void _handlePermissionRequest(AgentPermissionRequest request) {
    if (_closed || !_bindings.containsKey(request.sessionId)) {
      return;
    }
    unawaited(
      store.addPermission(request).catchError(
        (Object _) => store.projection,
      ),
    );
  }

  _SessionBinding _requireBinding(String sessionId) {
    final binding = _bindings[sessionId];
    if (binding == null) {
      throw CollaborationFailure(
        'unknown_session',
        'Session $sessionId is not available',
      );
    }
    return binding;
  }

  void _ensureOpen() {
    if (_closed) {
      throw const CollaborationFailure(
        'collaboration_closed',
        'Agent collaboration service is closed',
      );
    }
  }
}

final class _SessionBinding {
  _SessionBinding({
    required this.agentId,
    required this.session,
    required this.updates,
  });

  final String agentId;
  final AgentClientSession session;
  final StreamSubscription<AgentSessionUpdate> updates;
  String? lastPrompt;
}

/// Breaks the construction cycle between the store and its command owner.
final class _DeferredCommandPort implements AgentWorkbenchCommandPort {
  AgentWorkbenchCommandPort? _target;

  void bind(AgentWorkbenchCommandPort target) => _target = target;

  AgentWorkbenchCommandPort get _port {
    final target = _target;
    if (target == null) {
      throw const CollaborationFailure(
        'collaboration_unbound',
        'Agent collaboration commands are not bound yet',
      );
    }
    return target;
  }

  @override
  Future<void> steer(String sessionId, String prompt) =>
      _port.steer(sessionId, prompt);

  @override
  Future<void> cancel(String sessionId) => _port.cancel(sessionId);

  @override
  Future<void> retry(String sessionId) => _port.retry(sessionId);

  @override
  Future<void> reconnect(String sessionId) => _port.reconnect(sessionId);

  @override
  Future<void> resolvePermission({
    required String sessionId,
    required String permissionId,
    required AgentPermissionDecision decision,
  }) => _port.resolvePermission(
    sessionId: sessionId,
    permissionId: permissionId,
    decision: decision,
  );
}
