import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

import 'transport.dart';
import 'windows_named_pipe.dart';

final class SocketVityodTransport implements VityodTransport {
  SocketVityodTransport({required this.endpointPath});

  final String endpointPath;
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<VityodBinaryFrame> _incomingBinary =
      StreamController<VityodBinaryFrame>.broadcast(sync: true);
  final List<int> _buffer = <int>[];
  Socket? _socket;
  WindowsNamedPipeConnection? _windowsPipe;
  StreamSubscription<Uint8List>? _subscription;
  int _sequence = 0;
  Future<void> _writeTail = Future<void>.value();

  @override
  Stream<Uint8List> get incomingControl => _incoming.stream;

  @override
  Stream<VityodBinaryFrame> get incomingBinary => _incomingBinary.stream;

  @override
  Future<String> connect() async {
    if (_socket != null || _windowsPipe != null) {
      throw StateError('transport is already connected');
    }
    if (Platform.isWindows) {
      final pipe = await WindowsNamedPipeConnection.connect(endpointPath);
      _windowsPipe = pipe;
      _subscription = pipe.incoming.listen(
        _acceptBytes,
        onError: _incoming.addError,
        onDone: () {
          _windowsPipe = null;
        },
        cancelOnError: false,
      );
      return 'vityod-local-service';
    }
    final socket = await Socket.connect(
      InternetAddress(endpointPath, type: InternetAddressType.unix),
      0,
    );
    _socket = socket;
    _subscription = socket.listen(
      _acceptBytes,
      onError: _incoming.addError,
      onDone: () {
        _socket = null;
      },
      cancelOnError: false,
    );
    return 'vityod-local-service';
  }

  @override
  Future<void> sendControl(Uint8List payload) {
    final header = VityodFrameHeader(
      kind: VityodFrameKind.control,
      streamId: 0,
      sequence: ++_sequence,
      payloadLength: payload.length,
    );
    return _enqueueFrame(header, payload);
  }

  @override
  Future<void> sendBinary(VityodBinaryFrame frame) {
    final header = VityodFrameHeader(
      kind: frame.kind,
      streamId: frame.streamId,
      sequence: frame.sequence,
      payloadLength: frame.payload.length,
      flags: frame.flags,
    );
    return _enqueueFrame(header, frame.payload);
  }

  Future<void> _enqueueFrame(VityodFrameHeader header, Uint8List payload) {
    final operation = _writeTail.then((_) async {
      final pipe = _windowsPipe;
      if (pipe != null) {
        final bytes = Uint8List(vityodFrameHeaderBytes + payload.length);
        bytes.setAll(0, header.encode());
        bytes.setAll(vityodFrameHeaderBytes, payload);
        await pipe.write(bytes);
        return;
      }
      final socket = _socket;
      if (socket == null) throw StateError('transport is disconnected');
      socket.add(header.encode());
      socket.add(payload);
      await socket.flush();
    });
    _writeTail = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  void _acceptBytes(Uint8List bytes) {
    _buffer.addAll(bytes);
    while (_buffer.length >= vityodFrameHeaderBytes) {
      final header = VityodFrameHeader.decode(
        _buffer.sublist(0, vityodFrameHeaderBytes),
      );
      final frameLength = vityodFrameHeaderBytes + header.payloadLength;
      if (_buffer.length < frameLength) return;
      final payload = Uint8List.fromList(
        _buffer.sublist(vityodFrameHeaderBytes, frameLength),
      );
      _buffer.removeRange(0, frameLength);
      if (header.kind == VityodFrameKind.control) {
        _incoming.add(payload);
      } else {
        _incomingBinary.add(
          VityodBinaryFrame(
            kind: header.kind,
            streamId: header.streamId,
            sequence: header.sequence,
            payload: payload,
            flags: header.flags,
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    await _writeTail;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final socket = _socket;
    _socket = null;
    await socket?.close();
    final pipe = _windowsPipe;
    _windowsPipe = null;
    await pipe?.close();
    _buffer.clear();
  }

  @override
  Future<void> dispose() async {
    await close();
    await _incoming.close();
    await _incomingBinary.close();
  }
}
