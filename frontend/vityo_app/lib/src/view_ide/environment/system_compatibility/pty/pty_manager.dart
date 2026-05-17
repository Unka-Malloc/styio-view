import 'pty_adapter.dart';
import 'pty_facts.dart';

enum PtySessionState {
  starting,
  running,
  exited,
  closed,
  failed,
  unsupported,
}

enum PtyResizeStatus {
  applied,
  unsupported,
  failed,
}

enum PtyFailureKind {
  unsupported,
  startFailed,
  resizeUnsupported,
  resizeFailed,
  sessionFailed,
  unknownFailure,
}

class PtyOperationFailure {
  const PtyOperationFailure({
    required this.kind,
    required this.operation,
    required this.target,
    required this.sourceManager,
    required this.message,
    this.recoveryHint,
  });

  final PtyFailureKind kind;
  final String operation;
  final String target;
  final String sourceManager;
  final String message;
  final String? recoveryHint;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'operation': operation,
      'target': target,
      'sourceManager': sourceManager,
      'message': message,
      if (recoveryHint != null) 'recoveryHint': recoveryHint,
    };
  }
}

class PtySessionRequest {
  const PtySessionRequest({
    required this.executablePath,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.workingDirectory,
    this.rows = 24,
    this.cols = 80,
  });

  final String executablePath;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
  final int rows;
  final int cols;
}

class PtyResizeResult {
  const PtyResizeResult({
    required this.status,
    required this.rows,
    required this.cols,
    this.message,
  });

  final PtyResizeStatus status;
  final int rows;
  final int cols;
  final String? message;

  bool get applied => status == PtyResizeStatus.applied;
}

class PtyFailureClassifier {
  const PtyFailureClassifier({required this.sourceManager});

  final String sourceManager;

  PtyOperationFailure? classifySession(
    PtySession session, {
    String operation = 'pty.start',
    String? recoveryHint,
  }) {
    return switch (session.state) {
      PtySessionState.unsupported => PtyOperationFailure(
        kind: PtyFailureKind.unsupported,
        operation: operation,
        target: session.id,
        sourceManager: sourceManager,
        message: 'PTY session is unsupported.',
        recoveryHint: recoveryHint,
      ),
      PtySessionState.failed => PtyOperationFailure(
        kind: PtyFailureKind.startFailed,
        operation: operation,
        target: session.id,
        sourceManager: sourceManager,
        message: 'PTY session failed to start or run.',
        recoveryHint: recoveryHint,
      ),
      _ => null,
    };
  }

  PtyOperationFailure? classifyResize(
    PtyResizeResult result, {
    String operation = 'pty.resize',
    String target = 'pty',
    String? recoveryHint,
  }) {
    if (result.applied) {
      return null;
    }
    return PtyOperationFailure(
      kind: result.status == PtyResizeStatus.unsupported
          ? PtyFailureKind.resizeUnsupported
          : PtyFailureKind.resizeFailed,
      operation: operation,
      target: target,
      sourceManager: sourceManager,
      message: result.message ?? 'PTY resize failed.',
      recoveryHint: recoveryHint,
    );
  }
}

abstract class PtySession {
  String get id;

  PtySessionState get state;

  Stream<String> get output;

  Future<void> write(String input);

  Future<PtyResizeResult> resize({required int rows, required int cols});

  Future<int?> close({bool force = false});

  Future<int?> get exitCode;
}

abstract class PtyManager {
  PtyFacts get facts;

  PtyCompatibility get compatibility;

  Future<PtySession> start(PtySessionRequest request);

  PtyOperationFailure? failureForSession(
    PtySession session, {
    String operation = 'pty.start',
    String? recoveryHint,
  });

  PtyOperationFailure? failureForResize(
    PtyResizeResult result, {
    String operation = 'pty.resize',
    String target = 'pty',
    String? recoveryHint,
  });
}

class UnsupportedPtyManager implements PtyManager {
  UnsupportedPtyManager({required this.facts})
    : compatibility = PtyAdapter(facts).adapt();

  @override
  final PtyFacts facts;

  @override
  final PtyCompatibility compatibility;

  @override
  Future<PtySession> start(PtySessionRequest request) async {
    return UnsupportedPtySession(
      request: request,
      message: 'PTY sessions are not available on this platform.',
    );
  }

  @override
  PtyOperationFailure? failureForSession(
    PtySession session, {
    String operation = 'pty.start',
    String? recoveryHint,
  }) {
    return const PtyFailureClassifier(
      sourceManager: 'UnsupportedPtyManager',
    ).classifySession(
      session,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }

  @override
  PtyOperationFailure? failureForResize(
    PtyResizeResult result, {
    String operation = 'pty.resize',
    String target = 'pty',
    String? recoveryHint,
  }) {
    return const PtyFailureClassifier(
      sourceManager: 'UnsupportedPtyManager',
    ).classifyResize(
      result,
      operation: operation,
      target: target,
      recoveryHint: recoveryHint,
    );
  }
}

class UnsupportedPtySession implements PtySession {
  UnsupportedPtySession({required this.request, required this.message});

  final PtySessionRequest request;
  final String message;

  @override
  String get id => 'unsupported-pty';

  @override
  PtySessionState get state => PtySessionState.unsupported;

  @override
  Stream<String> get output => Stream<String>.value(message);

  @override
  Future<int?> get exitCode async => null;

  @override
  Future<void> write(String input) async {}

  @override
  Future<PtyResizeResult> resize({required int rows, required int cols}) async {
    return PtyResizeResult(
      status: PtyResizeStatus.unsupported,
      rows: rows,
      cols: cols,
      message: 'PTY resize is not available.',
    );
  }

  @override
  Future<int?> close({bool force = false}) async {
    return null;
  }
}
