import 'dart:async';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';

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
        maxSessions: registry.policy.maxSessions,
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
      onError: (Object _) {
        _recordFailure(
          const CollaborationFailure(
            'permission_stream_failed',
            'Agent permission stream failed',
          ),
        );
      },
      onDone: () {
        if (!_closed) {
          _recordFailure(
            const CollaborationFailure(
              'permission_stream_closed',
              'Agent permission stream closed unexpectedly',
            ),
          );
        }
      },
    );
  }

  final AgentClientRegistry _registry;
  final Uri _workspaceRoot;
  final AgentCollaborationStore store;
  final Map<String, _SessionBinding> _bindings = <String, _SessionBinding>{};
  final StreamController<CollaborationFailure> _failures =
      StreamController<CollaborationFailure>.broadcast(sync: true);
  late final StreamSubscription<AgentPermissionRequest> _permissions;
  bool _closed = false;

  CollaborationProjection get projection => store.projection;

  Stream<CollaborationProjection> get changes => store.changes;

  Stream<CollaborationFailure> get failures => _failures.stream;

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
    final formerPrompt = binding.lastPrompt;
    binding.lastPrompt = prompt;
    try {
      await _prompt(binding, prompt);
    } on CollaborationFailure catch (failure) {
      if (failure.code == 'invalid_prompt' ||
          failure.code == 'message_too_large') {
        binding.lastPrompt = formerPrompt;
      }
      rethrow;
    }
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
    final bindings = _bindings.values.toList(growable: false);
    await Future.wait<void>(
      bindings.map((binding) => binding.updates.cancel()),
      eagerError: false,
    );
    await Future.wait<void>(
      bindings
          .map((binding) => binding.projectionOperation)
          .whereType<Future<void>>(),
      eagerError: false,
    );
    _bindings.clear();
    final permissionCancellation = _permissions.cancel();
    try {
      return await _registry.close();
    } finally {
      await permissionCancellation;
      await store.close();
      await _failures.close();
    }
  }

  Future<void> _bind(AgentClientSession session, {String? lastPrompt}) async {
    final former = _bindings.remove(session.id);
    if (former != null) {
      await former.updates.cancel();
      await former.projectionOperation;
    }
    late final _SessionBinding binding;
    binding = _SessionBinding(
      agentId: session.agentId,
      session: session,
      updates: session.updates.listen(
        (_) => _scheduleProjection(binding),
        onError: (Object _) {
          _recordFailure(
            CollaborationFailure(
              'session_stream_failed',
              'Agent session ${session.id} update stream failed',
            ),
          );
        },
      ),
    )..lastPrompt = lastPrompt;
    _bindings[session.id] = binding;
    await _project(session);
  }

  void _scheduleProjection(_SessionBinding binding) {
    if (_closed || !identical(_bindings[binding.session.id], binding)) {
      return;
    }
    binding.projectionPending = true;
    if (binding.projectionOperation != null) {
      return;
    }
    final operation = _drainProjection(binding);
    binding.projectionOperation = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(binding.projectionOperation, operation)) {
          binding.projectionOperation = null;
        }
      }),
    );
  }

  Future<void> _drainProjection(_SessionBinding binding) async {
    while (binding.projectionPending &&
        !_closed &&
        identical(_bindings[binding.session.id], binding)) {
      binding.projectionPending = false;
      await _projectSafely(binding.session);
    }
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
      final snapshot = session.snapshot;
      await store.apply(snapshot);
      for (final update in snapshot.updates) {
        if (update.kind != VityoCapability.workspaceChangeProposal) {
          continue;
        }
        final proposal = VityoWorkspaceChangeProposal.fromNotificationParams(
          update.payload,
        );
        await store.proposeChange(
          sessionId: session.id,
          changeSet: WorkspaceChangeSet(
            id: proposal.id,
            baseWorkspaceRevision: proposal.baseWorkspaceRevision,
            resources: proposal.resources.map(
              (resource) => WorkspaceResourceChange(
                resourceId: resource.resourceId,
                baseDocumentRevision: resource.baseDocumentRevision,
                edits: resource.edits.map(
                  (edit) => WorkspaceTextChange(
                    start: edit.start,
                    end: edit.end,
                    replacement: edit.replacement,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    } on CollaborationFailure catch (failure) {
      if (failure.code != 'stale_snapshot') {
        rethrow;
      }
    } on AgentProtocolException catch (failure) {
      throw CollaborationFailure(failure.code, failure.message);
    }
  }

  Future<void> _projectSafely(AgentClientSession session) async {
    try {
      await _project(session);
    } on CollaborationFailure catch (failure) {
      _recordFailure(failure);
    } on Object {
      _recordFailure(
        CollaborationFailure(
          'projection_failed',
          'Agent session ${session.id} projection failed',
        ),
      );
    }
  }

  void _handlePermissionRequest(AgentPermissionRequest request) {
    if (_closed || !_bindings.containsKey(request.sessionId)) {
      return;
    }
    unawaited(_addPermissionSafely(request));
  }

  Future<void> _addPermissionSafely(AgentPermissionRequest request) async {
    try {
      await store.addPermission(request);
    } on CollaborationFailure catch (failure) {
      _recordFailure(failure);
    } on Object {
      _recordFailure(
        const CollaborationFailure(
          'permission_projection_failed',
          'Agent permission could not be projected',
        ),
      );
    }
  }

  void _recordFailure(CollaborationFailure failure) {
    if (!_failures.isClosed) {
      _failures.add(failure);
    }
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
  bool projectionPending = false;
  Future<void>? projectionOperation;
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
