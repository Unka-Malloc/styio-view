import 'dart:typed_data';

import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

import 'transport.dart';

final class SocketVityodTransport implements VityodTransport {
  SocketVityodTransport({required this.endpointPath});

  final String endpointPath;

  @override
  Stream<Uint8List> get incomingControl => const Stream<Uint8List>.empty();

  @override
  Stream<VityodBinaryFrame> get incomingBinary =>
      const Stream<VityodBinaryFrame>.empty();

  @override
  Future<String> connect() async => throw UnsupportedError(
    'Native vityod endpoints are unavailable on this platform.',
  );

  @override
  Future<void> sendControl(Uint8List payload) async => throw UnsupportedError(
    'Native vityod endpoints are unavailable on this platform.',
  );

  @override
  Future<void> sendBinary(VityodBinaryFrame frame) async =>
      throw UnsupportedError(
        'Native vityod endpoints are unavailable on this platform.',
      );

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {}
}
