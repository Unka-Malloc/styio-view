import 'dart:async';

import 'debug_adapter_protocol.dart';
import 'debug_adapter_session.dart';

abstract class DapByteTransport {
  Stream<List<int>> get incomingBytes;

  Future<void> send(List<int> bytes);

  Future<void> close();
}

class DapSessionTransportBridge {
  DapSessionTransportBridge({
    required this.transport,
    DapSessionController? session,
  }) : session = session ?? DapSessionController();

  final DapByteTransport transport;
  final DapSessionController session;
  final List<int> _inboundBuffer = <int>[];
  final StreamController<DapSessionSnapshot> _snapshotEvents =
      StreamController<DapSessionSnapshot>.broadcast();
  StreamSubscription<List<int>>? _subscription;

  DapSessionSnapshot get snapshot => session.snapshot;
  Stream<DapSessionSnapshot> get snapshotEvents => _snapshotEvents.stream;

  void attach() {
    _subscription ??= transport.incomingBytes.listen(_acceptBytes);
  }

  Future<void> sendRequest(DapRequest request) async {
    await transport.send(session.encodeRequest(request));
    _emitSnapshot();
  }

  Future<void> sendLaunchPlan(DapLaunchRequestPlan plan) async {
    for (final request in plan.requests) {
      await sendRequest(request);
    }
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await transport.close();
    await _snapshotEvents.close();
  }

  void _acceptBytes(List<int> bytes) {
    _inboundBuffer.addAll(bytes);
    while (_inboundBuffer.isNotEmpty) {
      final frame = session.acceptFrameBytes(_inboundBuffer);
      if (frame == null) {
        return;
      }
      _inboundBuffer.removeRange(0, frame.consumedBytes);
      _emitSnapshot();
    }
  }

  void _emitSnapshot() {
    if (!_snapshotEvents.isClosed) {
      _snapshotEvents.add(snapshot);
    }
  }
}
