import 'dart:async';
import 'dart:typed_data';

import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

abstract interface class VityodTransport {
  Stream<Uint8List> get incomingControl;

  Stream<VityodBinaryFrame> get incomingBinary;

  Future<String> connect();

  Future<void> sendControl(Uint8List payload);

  Future<void> sendBinary(VityodBinaryFrame frame);

  Future<void> close();

  Future<void> dispose();
}

final class MemoryVityodTransport implements VityodTransport {
  MemoryVityodTransport({
    this.instanceId = 'memory-vityod',
    this.automaticallyNegotiate = true,
  });

  final String instanceId;
  final bool automaticallyNegotiate;
  final List<Uint8List> sent = <Uint8List>[];
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<VityodBinaryFrame> _incomingBinary =
      StreamController<VityodBinaryFrame>.broadcast(sync: true);
  bool _connected = false;

  @override
  Stream<Uint8List> get incomingControl => _incoming.stream;

  @override
  Stream<VityodBinaryFrame> get incomingBinary => _incomingBinary.stream;

  @override
  Future<String> connect() async {
    _connected = true;
    return instanceId;
  }

  @override
  Future<void> sendControl(Uint8List payload) async {
    if (!_connected) throw StateError('transport is disconnected');
    sent.add(Uint8List.fromList(payload));
    if (automaticallyNegotiate) {
      final request = VityodControlCodec.decode(payload);
      if (request.method == 'handshake.negotiate') {
        receiveControl(
          VityodControlCodec.encode(
            VityodControlEnvelope(
              method: 'handshake.negotiate.result',
              requestId: request.requestId,
              clientInstanceId: instanceId,
              idempotencyKey: request.idempotencyKey,
              deadlineUnixMillis: request.deadlineUnixMillis,
              params: const <String, Object?>{
                'selectedProtocolVersion': vityodProtocolVersion,
                'capabilities': vityodCoreCapabilities,
              },
              capabilities: vityodCoreCapabilities,
            ),
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    _connected = false;
  }

  @override
  Future<void> sendBinary(VityodBinaryFrame frame) async {
    if (!_connected) throw StateError('transport is disconnected');
    _incomingBinary.add(frame);
  }

  void receiveControl(Uint8List payload) => _incoming.add(payload);

  @override
  Future<void> dispose() async {
    await close();
    await _incoming.close();
    await _incomingBinary.close();
  }
}
