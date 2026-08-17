import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

import 'buffer_sync/buffer_outbox.dart';
import 'connection/connection_state.dart';
import 'projection/service_snapshot.dart';
import 'transport/transport.dart';

export 'buffer_sync/buffer_outbox.dart';
export 'connection/connection_state.dart';
export 'platform/client_factory_stub.dart'
    if (dart.library.ui) 'platform/client_factory.dart';
export 'platform/platform_policy_stub.dart'
    if (dart.library.ui) 'platform/platform_policy.dart';
export 'projection/service_snapshot.dart';
export 'service_launcher_stub.dart'
    if (dart.library.ui) 'service_launcher.dart';
export 'transport/socket_transport.dart';
export 'transport/transport.dart';

final class VityodClient {
  VityodClient({
    required VityodTransport transport,
    required this.clientInstanceId,
    BufferDeltaOutbox? outbox,
    DateTime Function()? clock,
  }) : _transport = transport,
       outbox = outbox ?? BufferDeltaOutbox(),
       _clock = clock ?? DateTime.now {
    _controlSubscription = _transport.incomingControl.listen(_acceptControl);
  }

  final VityodTransport _transport;
  final DateTime Function() _clock;
  final String clientInstanceId;
  final BufferDeltaOutbox outbox;
  final StreamController<VityodConnectionState> _states =
      StreamController<VityodConnectionState>.broadcast(sync: true);
  late final StreamSubscription<Uint8List> _controlSubscription;
  VityodConnectionState _state = const VityodConnectionState.disconnected();
  VityodServiceSnapshot? _snapshot;
  int _requestSequence = 0;
  Future<void>? _fullResync;
  final Map<String, Completer<VityodControlEnvelope>> _pendingRequests =
      <String, Completer<VityodControlEnvelope>>{};

  VityodConnectionState get state => _state;
  VityodServiceSnapshot? get snapshot => _snapshot;
  Stream<VityodConnectionState> get states => _states.stream;
  Stream<VityodBinaryFrame> get binaryFrames => _transport.incomingBinary;

  Future<void> connect() async {
    _setState(
      VityodConnectionState(
        phase: _state.phase == VityodConnectionPhase.disconnected
            ? VityodConnectionPhase.connecting
            : VityodConnectionPhase.reconnecting,
        lastEventCursor: _state.lastEventCursor,
      ),
    );
    try {
      final daemonInstanceId = await _transport.connect();
      _setState(
        VityodConnectionState(
          phase: VityodConnectionPhase.connected,
          daemonInstanceId: daemonInstanceId,
          lastEventCursor: _state.lastEventCursor,
        ),
      );
      final negotiation = await request(
        method: 'handshake.negotiate',
        idempotencyKey: 'handshake-$daemonInstanceId-$clientInstanceId',
        params: const <String, Object?>{
          'minimumProtocolVersion': vityodProtocolVersion,
          'maximumProtocolVersion': vityodProtocolVersion,
          'requiredCapabilities': <String>[
            'event.resume',
            'workspace.snapshot',
          ],
        },
        capabilities: vityodCoreCapabilities,
      );
      _validateNegotiation(negotiation);
      await dispatch(
        method: 'event.resume',
        idempotencyKey: 'resume-$daemonInstanceId-${_state.lastEventCursor}',
        params: <String, Object?>{'afterCursor': _state.lastEventCursor},
        capabilities: vityodCoreCapabilities,
      );
    } catch (_) {
      await _transport.close();
      _setState(
        VityodConnectionState(
          phase: VityodConnectionPhase.disconnected,
          reasonCode: 'connect_failed',
          lastEventCursor: _state.lastEventCursor,
        ),
      );
      rethrow;
    }
  }

  Future<void> dispatch({
    required String method,
    required String idempotencyKey,
    String? workspaceId,
    int? workspaceRevision,
    Map<String, Object?> params = const <String, Object?>{},
    List<String> capabilities = const <String>[],
    Duration deadline = const Duration(seconds: 30),
  }) async {
    if (!_state.canDispatch) throw StateError('vityod client is not connected');
    final envelope = _createEnvelope(
      method: method,
      idempotencyKey: idempotencyKey,
      workspaceId: workspaceId,
      workspaceRevision: workspaceRevision,
      params: params,
      capabilities: capabilities,
      deadline: deadline,
    );
    await _transport.sendControl(VityodControlCodec.encode(envelope));
  }

  Future<VityodControlEnvelope> request({
    required String method,
    required String idempotencyKey,
    String? workspaceId,
    int? workspaceRevision,
    Map<String, Object?> params = const <String, Object?>{},
    List<String> capabilities = const <String>[],
    Duration deadline = const Duration(seconds: 30),
  }) => _requestEnvelope(
    method: method,
    idempotencyKey: idempotencyKey,
    workspaceId: workspaceId,
    workspaceRevision: workspaceRevision,
    params: params,
    capabilities: capabilities,
    deadline: deadline,
    allowResync: false,
  );

  Future<VityodControlEnvelope> _requestEnvelope({
    required String method,
    required String idempotencyKey,
    required String? workspaceId,
    required int? workspaceRevision,
    required Map<String, Object?> params,
    required List<String> capabilities,
    required Duration deadline,
    required bool allowResync,
  }) async {
    if (!_state.canDispatch &&
        !(allowResync &&
            _state.phase == VityodConnectionPhase.resyncRequired)) {
      throw StateError('vityod client is not connected');
    }
    final envelope = _createEnvelope(
      method: method,
      idempotencyKey: idempotencyKey,
      workspaceId: workspaceId,
      workspaceRevision: workspaceRevision,
      params: params,
      capabilities: capabilities,
      deadline: deadline,
    );
    final requestId = envelope.requestId!;
    final completer = Completer<VityodControlEnvelope>();
    _pendingRequests[requestId] = completer;
    try {
      await _transport.sendControl(VityodControlCodec.encode(envelope));
      return await completer.future.timeout(deadline);
    } finally {
      _pendingRequests.remove(requestId);
    }
  }

  Future<void> sendBinary(VityodBinaryFrame frame) {
    if (!_state.canDispatch) {
      throw StateError('vityod client is not connected');
    }
    return _transport.sendBinary(frame);
  }

  void acceptSnapshot(VityodServiceSnapshot snapshot) {
    if (snapshot.eventCursor < _state.lastEventCursor) {
      throw StateError('service snapshot cursor moved backwards');
    }
    _snapshot = snapshot;
    _setState(
      VityodConnectionState(
        phase: VityodConnectionPhase.connected,
        daemonInstanceId: _state.daemonInstanceId,
        lastEventCursor: snapshot.eventCursor,
      ),
    );
  }

  void requireResync(String reasonCode) {
    _setState(
      VityodConnectionState(
        phase: VityodConnectionPhase.resyncRequired,
        daemonInstanceId: _state.daemonInstanceId,
        reasonCode: reasonCode,
        lastEventCursor: _state.lastEventCursor,
      ),
    );
  }

  Future<void> close() async {
    await _transport.close();
    final pending = _pendingRequests.values.toList(growable: false);
    _pendingRequests.clear();
    for (final request in pending) {
      if (!request.isCompleted) {
        request.completeError(StateError('vityod client disconnected'));
      }
    }
    _setState(
      VityodConnectionState(
        phase: VityodConnectionPhase.disconnected,
        lastEventCursor: _state.lastEventCursor,
      ),
    );
  }

  Future<void> dispose() async {
    await close();
    await _controlSubscription.cancel();
    await _transport.dispose();
    await _states.close();
  }

  void _acceptControl(Uint8List payload) {
    final envelope = VityodControlCodec.decode(payload);
    final requestId = envelope.requestId;
    final pending = requestId == null ? null : _pendingRequests[requestId];
    if (pending != null && !pending.isCompleted) pending.complete(envelope);
    if (envelope.method == 'event.resume.error') {
      final code = envelope.params['errorCode'];
      requireResync(code is String ? code : 'event_resume_failed');
      if (envelope.params['context'] case final Map<Object?, Object?> context) {
        if (context['resyncMode'] == 'full_snapshot') {
          _fullResync ??= _requestFullSnapshot().whenComplete(() {
            _fullResync = null;
          });
        }
      }
      return;
    }
    if (envelope.method == 'snapshot.get.result') {
      _acceptServiceSnapshot(envelope.params, full: true);
      return;
    }
    if (envelope.method != 'event.resume.result') return;
    _acceptServiceSnapshot(envelope.params, full: false);
  }

  Future<void> _requestFullSnapshot() async {
    try {
      final response = await _requestEnvelope(
        method: 'snapshot.get',
        idempotencyKey: 'full-resync-${_state.daemonInstanceId}',
        workspaceId: null,
        workspaceRevision: null,
        params: const <String, Object?>{},
        capabilities: vityodCoreCapabilities,
        deadline: const Duration(seconds: 30),
        allowResync: true,
      );
      if (response.method != 'snapshot.get.result') {
        final code = response.params['errorCode'];
        requireResync(code is String ? code : 'full_snapshot_failed');
      }
    } on VityodProtocolException catch (error) {
      requireResync(error.code);
    } on TimeoutException {
      requireResync('full_snapshot_timeout');
    } on StateError {
      requireResync('full_snapshot_transport_failed');
    } on Object {
      requireResync('full_snapshot_failed');
    }
  }

  void _acceptServiceSnapshot(
    Map<String, Object?> params, {
    required bool full,
  }) {
    try {
      final events = _serviceEvents(
        params,
        afterCursor: full ? 0 : _state.lastEventCursor,
      );
      final digest = params['eventDigest'];
      final eventCursor = _requiredNonNegativeInt(params, 'eventCursor');
      final expectedCursor = full
          ? eventCursor
          : events.isEmpty
          ? _state.lastEventCursor
          : events.last.cursor;
      if (eventCursor != expectedCursor ||
          digest is! String ||
          digest != _orderedEventDigest(events)) {
        requireResync('event_digest_mismatch');
        return;
      }
      acceptSnapshot(
        VityodServiceSnapshot(
          eventCursor: eventCursor,
          workspaceRevision: _requiredNonNegativeInt(
            params,
            'workspaceRevision',
          ),
          capabilities: _stringSet(params, 'capabilities'),
          activeTerminalIds: _stringList(params, 'activeTerminalIds'),
          activeTaskIds: _stringList(params, 'activeTaskIds'),
          activeAgentSessionIds: _stringList(params, 'activeAgentSessionIds'),
          dirtyBuffers: _dirtyBuffers(params),
          events: events,
          eventDigest: digest,
        ),
      );
    } on VityodProtocolException catch (error) {
      requireResync(error.code);
    }
  }

  void _validateNegotiation(VityodControlEnvelope response) {
    if (response.method != 'handshake.negotiate.result') {
      final code = response.params['errorCode'];
      throw VityodProtocolException(
        code is String ? code : 'handshake_failed',
        'The local service rejected protocol negotiation.',
      );
    }
    final selected = response.params['selectedProtocolVersion'];
    if (selected != vityodProtocolVersion) {
      throw VityodProtocolException(
        'unsupported_protocol_version',
        'The local service selected protocol version $selected.',
      );
    }
    final selectedCapabilities = _stringSet(response.params, 'capabilities');
    const required = <String>{'event.resume', 'workspace.snapshot'};
    if (!selectedCapabilities.containsAll(required)) {
      throw const VityodProtocolException(
        'required_capability_unsupported',
        'The local service does not provide the required reconnect capabilities.',
      );
    }
  }

  void _setState(VityodConnectionState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  VityodControlEnvelope _createEnvelope({
    required String method,
    required String idempotencyKey,
    required String? workspaceId,
    required int? workspaceRevision,
    required Map<String, Object?> params,
    required List<String> capabilities,
    required Duration deadline,
  }) {
    return VityodControlEnvelope(
      method: method,
      requestId: 'request-${++_requestSequence}',
      clientInstanceId: clientInstanceId,
      idempotencyKey: idempotencyKey,
      workspaceId: workspaceId,
      workspaceRevision: workspaceRevision,
      deadlineUnixMillis: _clock().add(deadline).millisecondsSinceEpoch,
      params: params,
      capabilities: capabilities,
    );
  }
}

int _requiredNonNegativeInt(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is int && value >= 0) return value;
  throw VityodProtocolException(
    'invalid_service_snapshot',
    '$key must be a non-negative integer',
  );
}

List<String> _stringList(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is List && value.every((item) => item is String)) {
    return List<String>.unmodifiable(value.cast<String>());
  }
  throw VityodProtocolException(
    'invalid_service_snapshot',
    '$key must contain only strings',
  );
}

Set<String> _stringSet(Map<String, Object?> source, String key) =>
    Set<String>.unmodifiable(_stringList(source, key));

List<VityodDirtyBufferSnapshot> _dirtyBuffers(Map<String, Object?> source) {
  final values = source['dirtyBuffers'];
  if (values == null) {
    return const <VityodDirtyBufferSnapshot>[];
  }
  if (values is! List || values.length > 1024) {
    throw const VityodProtocolException(
      'invalid_service_snapshot',
      'dirtyBuffers must be a bounded list',
    );
  }
  final buffers = <VityodDirtyBufferSnapshot>[];
  var totalBytes = 0;
  for (final raw in values) {
    if (raw is! Map) {
      throw const VityodProtocolException(
        'invalid_service_snapshot',
        'dirty buffer entries must be objects',
      );
    }
    final value = Map<String, Object?>.from(raw);
    final documentId = value['documentId'];
    final contents = value['contents'];
    if (documentId is! String || documentId.isEmpty || contents is! String) {
      throw const VityodProtocolException(
        'invalid_service_snapshot',
        'dirty buffer entries are malformed',
      );
    }
    totalBytes += utf8.encode(contents).length;
    if (totalBytes > 8 * 1024 * 1024) {
      throw const VityodProtocolException(
        'invalid_service_snapshot',
        'dirty buffer snapshot exceeds its byte budget',
      );
    }
    buffers.add(
      VityodDirtyBufferSnapshot(
        documentId: documentId,
        revision: _requiredNonNegativeInt(value, 'revision'),
        contents: contents,
      ),
    );
  }
  return List<VityodDirtyBufferSnapshot>.unmodifiable(buffers);
}

List<VityodServiceEvent> _serviceEvents(
  Map<String, Object?> source, {
  required int afterCursor,
}) {
  final values = source['events'];
  if (values is! List) {
    throw const VityodProtocolException(
      'invalid_service_events',
      'events must be a list',
    );
  }
  final events = <VityodServiceEvent>[];
  var expectedCursor = afterCursor + 1;
  for (final raw in values) {
    if (raw is! Map) {
      throw const VityodProtocolException(
        'invalid_service_events',
        'event entries must be objects',
      );
    }
    final value = Map<String, Object?>.from(raw);
    final cursor = _requiredNonNegativeInt(value, 'cursor');
    final workspaceRevision = _requiredNonNegativeInt(
      value,
      'workspaceRevision',
    );
    final kind = value['kind'];
    final encoded = value['payloadBase64'];
    if (cursor != expectedCursor ||
        kind is! String ||
        kind.isEmpty ||
        encoded is! String) {
      throw const VityodProtocolException(
        'invalid_service_events',
        'events must be contiguous and structurally valid',
      );
    }
    late final List<int> payload;
    try {
      payload = base64Decode(encoded);
    } on FormatException {
      throw const VityodProtocolException(
        'invalid_service_events',
        'event payload must be valid base64',
      );
    }
    events.add(
      VityodServiceEvent(
        cursor: cursor,
        kind: kind,
        workspaceRevision: workspaceRevision,
        payload: List<int>.unmodifiable(payload),
      ),
    );
    expectedCursor += 1;
  }
  return List<VityodServiceEvent>.unmodifiable(events);
}

String _orderedEventDigest(List<VityodServiceEvent> events) {
  final mask = BigInt.parse('ffffffffffffffff', radix: 16);
  final prime = BigInt.from(1099511628211);
  var digest = BigInt.parse('cbf29ce484222325', radix: 16);
  void addByte(int byte) {
    digest = ((digest ^ BigInt.from(byte)) * prime) & mask;
  }

  void addUint64(int value) {
    for (var shift = 0; shift < 64; shift += 8) {
      addByte((value >> shift) & 0xff);
    }
  }

  for (final event in events) {
    final kind = utf8.encode(event.kind);
    addUint64(event.cursor);
    addUint64(kind.length);
    for (final byte in kind) {
      addByte(byte);
    }
    addUint64(event.workspaceRevision);
    addUint64(event.payload.length);
    for (final byte in event.payload) {
      addByte(byte);
    }
  }
  return digest.toRadixString(16).padLeft(16, '0');
}
