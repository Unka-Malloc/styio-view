library;

import 'dart:async';
import 'dart:convert';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';

import 'agent_session_endpoint.dart';

final class StdioAgentServerTransport implements AgentServerTransport {
  StdioAgentServerTransport({
    required Stream<List<int>> input,
    required FutureOr<void> Function(String line) writeLine,
    FutureOr<void> Function()? flush,
    this.maxMessageBytes = vityoAgentProtocolMaxMessageBytes,
  }) : _input = input,
       _writeLine = writeLine,
       _flush = flush {
    if (maxMessageBytes <= 0) {
      throw ArgumentError('maxMessageBytes must be positive.');
    }
  }

  final Stream<List<int>> _input;
  final FutureOr<void> Function(String line) _writeLine;
  final FutureOr<void> Function()? _flush;
  final int maxMessageBytes;
  Future<void> _writeLane = Future<void>.value();
  var _closed = false;

  @override
  Stream<JsonRpcMessage> get incoming => _boundedLines(
    _input,
    maxMessageBytes,
  ).map((line) => JsonRpcCodec.decode(line, maxMessageBytes: maxMessageBytes));

  @override
  Future<void> send(JsonRpcMessage message) {
    if (_closed) return Future<void>.error(StateError('transport is closed'));
    final operation = _writeLane.then((_) async {
      await _writeLine(
        JsonRpcCodec.encode(message, maxMessageBytes: maxMessageBytes),
      );
      await _flush?.call();
    });
    _writeLane = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _writeLane;
    await _flush?.call();
  }
}

Stream<String> _boundedLines(
  Stream<List<int>> input,
  int maxMessageBytes,
) async* {
  var bytes = <int>[];
  await for (final chunk in input) {
    for (final byte in chunk) {
      if (byte == 0x0a) {
        if (bytes.length > maxMessageBytes) {
          throw const AgentProtocolException(
            'message_too_large',
            'protocol frame exceeds its configured bound',
          );
        }
        if (bytes.isNotEmpty && bytes.last == 0x0d) {
          bytes.removeLast();
        }
        if (bytes.isNotEmpty) {
          try {
            yield utf8.decode(bytes);
          } on FormatException {
            throw const AgentProtocolException(
              'malformed_message',
              'protocol frame is not valid UTF-8',
            );
          }
        }
        bytes = <int>[];
      } else {
        bytes.add(byte);
        if (bytes.length > maxMessageBytes) {
          throw const AgentProtocolException(
            'message_too_large',
            'protocol frame exceeds its configured bound',
          );
        }
      }
    }
  }
  if (bytes.isNotEmpty) {
    throw const AgentProtocolException(
      'malformed_message',
      'protocol stream ended with an incomplete frame',
    );
  }
}
