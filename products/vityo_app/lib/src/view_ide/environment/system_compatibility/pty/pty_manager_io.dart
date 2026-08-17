import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

import '../../../../ide/local_service/vityod_client.dart';
import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context.dart';
import 'pty_adapter.dart';
import 'pty_facts.dart';
import 'pty_manager.dart';
import 'pty_prober.dart';
import 'pty_prober_io.dart';

var _globalTerminalSequence = 0;

Future<PtyManager> createPlatformPtyManager({
  PtyProber? prober,
  PlatformContextSnapshot? platformContext,
  VityodClient? vityodClient,
}) async {
  final adapter = platformContext == null
      ? null
      : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.pty ?? await (prober ?? const LocalPtyProber()).probe();
  if (vityodClient == null) return UnsupportedPtyManager(facts: facts);
  return LocalPtyManager(
    facts: facts,
    client: vityodClient,
    adapter: adapter?.ptyAdapter,
  );
}

class LocalPtyManager implements PtyManager {
  LocalPtyManager({
    required this.facts,
    required VityodClient client,
    PtyAdapter? adapter,
  }) : _client = client,
       _adapter = adapter ?? PtyAdapter(facts),
       compatibility = (adapter ?? PtyAdapter(facts)).adapt();

  factory LocalPtyManager.linuxDebianArmForTest({
    required VityodClient client,
  }) => LocalPtyManager(facts: PtyFacts.linuxDebianArm(), client: client);

  final VityodClient _client;
  final PtyAdapter _adapter;

  @override
  final PtyFacts facts;

  @override
  final PtyCompatibility compatibility;

  @override
  PtyOperationFailure? failureForSession(
    PtySession session, {
    String operation = 'pty.start',
    String? recoveryHint,
  }) => const PtyFailureClassifier(
    sourceManager: 'VityodPtyManager',
  ).classifySession(session, operation: operation, recoveryHint: recoveryHint);

  @override
  PtyOperationFailure? failureForResize(
    PtyResizeResult result, {
    String operation = 'pty.resize',
    String target = 'pty',
    String? recoveryHint,
  }) => const PtyFailureClassifier(sourceManager: 'VityodPtyManager')
      .classifyResize(
        result,
        operation: operation,
        target: target,
        recoveryHint: recoveryHint,
      );

  @override
  Future<PtySession> start(PtySessionRequest request) async {
    final plan = _adapter.plan(request);
    if (!plan.supported) {
      return UnsupportedPtySession(
        request: request,
        message: plan.unsupportedMessage ?? 'PTY sessions are unavailable.',
      );
    }
    if (!_client.state.canDispatch) {
      return FailedPtySession(
        request: request,
        error: StateError('The local service is disconnected.'),
      );
    }
    final terminalId =
        'terminal-${_client.clientInstanceId}-${++_globalTerminalSequence}';
    try {
      final response = await _client.request(
        method: 'pty.start',
        idempotencyKey: 'pty-start-$terminalId',
        params: <String, Object?>{
          'terminalId': terminalId,
          'executable': plan.backendExecutablePath,
          'arguments': plan.backendArguments,
          'workingDirectory': plan.workingDirectory,
          'environment': plan.environment,
          'rows': request.rows,
          'cols': request.cols,
        },
        capabilities: const <String>['pty.start'],
      );
      _throwIfError(response);
      final streamId = response.params['streamId'];
      if (streamId is! int || streamId <= 0) {
        throw const VityodProtocolException(
          'invalid_stream_id',
          'The daemon returned an invalid PTY stream identifier.',
        );
      }
      final session = VityodPtySession(
        id: terminalId,
        streamId: streamId,
        client: _client,
      );
      await session.startReading();
      return session;
    } on Object catch (error) {
      return FailedPtySession(request: request, error: error);
    }
  }
}

final class VityodPtySession implements PtySession {
  VityodPtySession({
    required this.id,
    required this.streamId,
    required VityodClient client,
  }) : _client = client {
    _output = _bytes.stream.transform(utf8.decoder);
  }

  static const _creditBytes = 256 * 1024;

  final VityodClient _client;
  final int streamId;
  final StreamController<List<int>> _bytes =
      StreamController<List<int>>.broadcast(sync: true);
  final Completer<int?> _exitCode = Completer<int?>();
  late final Stream<String> _output;
  StreamSubscription<VityodBinaryFrame>? _subscription;
  PtySessionState _state = PtySessionState.starting;
  var _inputSequence = 0;
  var _creditSequence = 0;
  Timer? _creditTimer;

  @override
  final String id;

  @override
  PtySessionState get state => _state;

  @override
  Stream<String> get output => _output;

  @override
  Future<int?> get exitCode => _exitCode.future;

  Future<void> startReading() async {
    _subscription = _client.binaryFrames
        .where(
          (frame) =>
              frame.kind == VityodFrameKind.pty && frame.streamId == streamId,
        )
        .listen(_acceptOutput, onError: _fail);
    _state = PtySessionState.running;
    await _grantCredit();
  }

  void _acceptOutput(VityodBinaryFrame frame) {
    var outputBytes = frame.payload;
    int? reportedExitCode;
    if ((frame.flags & 4) != 0) {
      if (frame.payload.length < 4) {
        _fail(
          StateError('vityod returned invalid PTY exit metadata.'),
          StackTrace.current,
        );
        return;
      }
      reportedExitCode = ByteData.sublistView(
        frame.payload,
        0,
        4,
      ).getUint32(0, Endian.big);
      outputBytes = Uint8List.sublistView(frame.payload, 4);
    }
    if (outputBytes.isNotEmpty && !_bytes.isClosed) {
      _bytes.add(outputBytes);
    }
    if ((frame.flags & 1) != 0 && !_bytes.isClosed) {
      _bytes.add(
        utf8.encode('\n[vityod: earlier terminal output was truncated]\n'),
      );
    }
    if ((frame.flags & 2) != 0) {
      _state = PtySessionState.exited;
      if (!_exitCode.isCompleted) _exitCode.complete(reportedExitCode);
      unawaited(_finish());
      return;
    }
    _creditTimer?.cancel();
    _creditTimer = Timer(const Duration(milliseconds: 50), () {
      unawaited(_grantCredit());
    });
  }

  Future<void> _grantCredit() {
    if (_state != PtySessionState.running) return Future<void>.value();
    final payload = ByteData(4)..setUint32(0, _creditBytes, Endian.big);
    return _client.sendBinary(
      VityodBinaryFrame(
        kind: VityodFrameKind.credit,
        streamId: streamId,
        sequence: ++_creditSequence,
        payload: payload.buffer.asUint8List(),
      ),
    );
  }

  @override
  Future<void> write(String input) {
    if (_state != PtySessionState.running) {
      throw StateError('PTY session is not running.');
    }
    return _client.sendBinary(
      VityodBinaryFrame(
        kind: VityodFrameKind.pty,
        streamId: streamId,
        sequence: ++_inputSequence,
        payload: utf8.encode(input),
      ),
    );
  }

  @override
  Future<PtyResizeResult> resize({required int rows, required int cols}) async {
    try {
      final response = await _client.request(
        method: 'pty.resize',
        idempotencyKey:
            'pty-resize-$id-$rows-$cols-${DateTime.now().microsecondsSinceEpoch}',
        params: <String, Object?>{
          'streamId': streamId,
          'rows': rows,
          'cols': cols,
        },
      );
      _throwIfError(response);
      return PtyResizeResult(
        status: PtyResizeStatus.applied,
        rows: rows,
        cols: cols,
      );
    } on Object catch (error) {
      return PtyResizeResult(
        status: PtyResizeStatus.failed,
        rows: rows,
        cols: cols,
        message: 'vityod PTY resize failed: $error',
      );
    }
  }

  @override
  Future<PtySignalResult> sendSignal(PtySignal signal) async {
    try {
      if (signal == PtySignal.eof) {
        await write('\u0004');
      } else {
        await close(force: signal == PtySignal.kill);
      }
      return PtySignalResult(signal: signal, status: PtySignalStatus.sent);
    } on Object catch (error) {
      return PtySignalResult(
        signal: signal,
        status: PtySignalStatus.failed,
        message: 'vityod PTY signal failed: $error',
      );
    }
  }

  @override
  Future<int?> close({bool force = false}) async {
    if (_state == PtySessionState.closed || _state == PtySessionState.exited) {
      return _exitCode.future;
    }
    _state = PtySessionState.closed;
    int? exitCode;
    try {
      final response = await _client.request(
        method: 'pty.close',
        idempotencyKey: 'pty-close-$id',
        params: <String, Object?>{'streamId': streamId, 'force': force},
      );
      _throwIfError(response);
      final responseExitCode = response.params['exitCode'];
      if (responseExitCode is int) exitCode = responseExitCode;
    } finally {
      if (!_exitCode.isCompleted) _exitCode.complete(exitCode);
      await _finish();
    }
    return _exitCode.future;
  }

  void _fail(Object error, StackTrace stackTrace) {
    _state = PtySessionState.failed;
    if (!_bytes.isClosed) _bytes.addError(error, stackTrace);
    if (!_exitCode.isCompleted) _exitCode.complete(null);
    unawaited(_finish());
  }

  Future<void> _finish() async {
    _creditTimer?.cancel();
    _creditTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    if (!_bytes.isClosed) await _bytes.close();
  }
}

class FailedPtySession implements PtySession {
  FailedPtySession({required this.request, required this.error});

  final PtySessionRequest request;
  final Object error;

  @override
  String get id => 'failed-pty';
  @override
  PtySessionState get state => PtySessionState.failed;
  @override
  Stream<String> get output => Stream<String>.value(error.toString());
  @override
  Future<int?> get exitCode async => null;
  @override
  Future<void> write(String input) async {}
  @override
  Future<PtyResizeResult> resize({required int rows, required int cols}) async {
    return PtyResizeResult(
      status: PtyResizeStatus.failed,
      rows: rows,
      cols: cols,
      message: error.toString(),
    );
  }

  @override
  Future<PtySignalResult> sendSignal(PtySignal signal) async {
    return PtySignalResult(
      signal: signal,
      status: PtySignalStatus.failed,
      message: error.toString(),
    );
  }

  @override
  Future<int?> close({bool force = false}) async => null;
}

void _throwIfError(VityodControlEnvelope response) {
  if (!response.method.endsWith('.error')) return;
  final code = response.params['errorCode'];
  throw VityodProtocolException(
    code is String ? code : 'service_error',
    'The local service rejected the PTY operation.',
  );
}
