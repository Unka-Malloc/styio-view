import 'dart:convert';

import 'debug_launch_contract.dart';

class DapContentFrame {
  const DapContentFrame({required this.message, required this.consumedBytes});

  final Map<String, Object?> message;
  final int consumedBytes;
}

class DapContentFrameCodec {
  const DapContentFrameCodec();

  static final List<int> _headerTerminator = utf8.encode('\r\n\r\n');

  List<int> encode(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode(message));
    final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');
    return <int>[...header, ...body];
  }

  DapContentFrame? decodeFirst(List<int> bytes) {
    final headerEnd = _indexOfSequence(bytes, _headerTerminator);
    if (headerEnd < 0) {
      return null;
    }
    final headerText = ascii.decode(bytes.sublist(0, headerEnd));
    final contentLength = _contentLengthFromHeader(headerText);
    final bodyStart = headerEnd + _headerTerminator.length;
    final bodyEnd = bodyStart + contentLength;
    if (bytes.length < bodyEnd) {
      return null;
    }
    final bodyText = utf8.decode(bytes.sublist(bodyStart, bodyEnd));
    final decoded = jsonDecode(bodyText);
    if (decoded is! Map) {
      throw const FormatException('DAP frame body must be a JSON object.');
    }
    return DapContentFrame(
      message: decoded.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
      consumedBytes: bodyEnd,
    );
  }

  int _contentLengthFromHeader(String headerText) {
    for (final line in headerText.split('\r\n')) {
      final separatorIndex = line.indexOf(':');
      if (separatorIndex < 0) {
        continue;
      }
      final name = line.substring(0, separatorIndex).trim().toLowerCase();
      if (name != 'content-length') {
        continue;
      }
      final value = int.tryParse(line.substring(separatorIndex + 1).trim());
      if (value == null || value < 0) {
        throw FormatException('Invalid DAP Content-Length: $line');
      }
      return value;
    }
    throw const FormatException('Missing DAP Content-Length header.');
  }
}

class DapRequest {
  const DapRequest({
    required this.seq,
    required this.command,
    this.arguments = const <String, Object?>{},
  });

  final int seq;
  final String command;
  final Map<String, Object?> arguments;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'seq': seq,
      'type': 'request',
      'command': command,
      if (arguments.isNotEmpty) 'arguments': arguments,
    };
  }
}

class DapProtocolRequestFactory {
  const DapProtocolRequestFactory();

  DapRequest initialize({
    required int seq,
    String clientId = 'vityo',
    String clientName = 'Vityo IDE',
    String locale = 'en-US',
  }) {
    return DapRequest(
      seq: seq,
      command: 'initialize',
      arguments: <String, Object?>{
        'clientID': clientId,
        'clientName': clientName,
        'adapterID': 'vityo-debug',
        'locale': locale,
        'linesStartAt1': true,
        'columnsStartAt1': true,
        'pathFormat': 'path',
        'supportsVariableType': true,
        'supportsVariablePaging': true,
        'supportsRunInTerminalRequest': true,
      },
    );
  }

  DapRequest launch({
    required int seq,
    required DebugLaunchConfiguration launch,
  }) {
    if (!launch.ready || launch.programPath == null) {
      throw StateError(
        'Cannot build DAP launch request before launch is ready.',
      );
    }
    return DapRequest(
      seq: seq,
      command: 'launch',
      arguments: <String, Object?>{
        'program': launch.programPath,
        'cwd': launch.cwd,
        'args': launch.arguments,
        'env': launch.environment,
        'stopOnEntry': launch.stopOnEntry,
      },
    );
  }

  DapRequest setBreakpoints({
    required int seq,
    required String sourcePath,
    required Iterable<DebugLaunchBreakpoint> breakpoints,
  }) {
    return DapRequest(
      seq: seq,
      command: 'setBreakpoints',
      arguments: <String, Object?>{
        'source': <String, Object?>{'path': sourcePath},
        'breakpoints': breakpoints
            .where((breakpoint) => breakpoint.enabled)
            .map((breakpoint) => <String, Object?>{'line': breakpoint.line + 1})
            .toList(growable: false),
        'sourceModified': false,
      },
    );
  }

  DapRequest configurationDone({required int seq}) {
    return DapRequest(seq: seq, command: 'configurationDone');
  }

  DapRequest threads({required int seq}) {
    return DapRequest(seq: seq, command: 'threads');
  }

  DapRequest stackTrace({required int seq, required int threadId}) {
    return DapRequest(
      seq: seq,
      command: 'stackTrace',
      arguments: <String, Object?>{'threadId': threadId},
    );
  }

  DapRequest scopes({required int seq, required int frameId}) {
    return DapRequest(
      seq: seq,
      command: 'scopes',
      arguments: <String, Object?>{'frameId': frameId},
    );
  }

  DapRequest variables({required int seq, required int variablesReference}) {
    return DapRequest(
      seq: seq,
      command: 'variables',
      arguments: <String, Object?>{'variablesReference': variablesReference},
    );
  }

  DapRequest continueThread({required int seq, required int threadId}) {
    return DapRequest(
      seq: seq,
      command: 'continue',
      arguments: <String, Object?>{'threadId': threadId},
    );
  }

  DapRequest next({required int seq, required int threadId}) {
    return DapRequest(
      seq: seq,
      command: 'next',
      arguments: <String, Object?>{'threadId': threadId},
    );
  }

  DapRequest disconnect({required int seq, bool terminateDebuggee = true}) {
    return DapRequest(
      seq: seq,
      command: 'disconnect',
      arguments: <String, Object?>{'terminateDebuggee': terminateDebuggee},
    );
  }

  DapRequest terminate({required int seq, bool restart = false}) {
    return DapRequest(
      seq: seq,
      command: 'terminate',
      arguments: <String, Object?>{'restart': restart},
    );
  }
}

class DapLaunchRequestPlan {
  const DapLaunchRequestPlan({required this.requests});

  factory DapLaunchRequestPlan.fromLaunchConfiguration({
    required DebugLaunchConfiguration launch,
    int initialSeq = 1,
    DapProtocolRequestFactory requestFactory =
        const DapProtocolRequestFactory(),
  }) {
    if (!launch.ready) {
      throw StateError('Cannot build DAP request plan before launch is ready.');
    }
    var seq = initialSeq;
    final requests = <DapRequest>[
      requestFactory.initialize(seq: seq++),
      for (final entry in _breakpointsByPath(launch.breakpoints).entries)
        requestFactory.setBreakpoints(
          seq: seq++,
          sourcePath: entry.key,
          breakpoints: entry.value,
        ),
      requestFactory.launch(seq: seq++, launch: launch),
      requestFactory.configurationDone(seq: seq++),
    ];
    return DapLaunchRequestPlan(
      requests: List<DapRequest>.unmodifiable(requests),
    );
  }

  final List<DapRequest> requests;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestCount': requests.length,
      'requests': requests
          .map((request) => request.toJson())
          .toList(growable: false),
    };
  }
}

Map<String, List<DebugLaunchBreakpoint>> _breakpointsByPath(
  Iterable<DebugLaunchBreakpoint> breakpoints,
) {
  final grouped = <String, List<DebugLaunchBreakpoint>>{};
  for (final breakpoint in breakpoints) {
    if (!breakpoint.enabled) {
      continue;
    }
    grouped
        .putIfAbsent(breakpoint.filePath, () => <DebugLaunchBreakpoint>[])
        .add(breakpoint);
  }
  return grouped;
}

int _indexOfSequence(List<int> bytes, List<int> sequence) {
  if (sequence.isEmpty || bytes.length < sequence.length) {
    return -1;
  }
  for (var index = 0; index <= bytes.length - sequence.length; index += 1) {
    var matched = true;
    for (var offset = 0; offset < sequence.length; offset += 1) {
      if (bytes[index + offset] != sequence[offset]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return index;
    }
  }
  return -1;
}
