import 'clipboard_adapter.dart';
import 'clipboard_facts.dart';

enum ClipboardOperationStatus { succeeded, blocked }

enum ClipboardFailureKind {
  unsupported,
  blocked,
  unknownFailure,
}

class ClipboardOperationFailure {
  const ClipboardOperationFailure({
    required this.kind,
    required this.operation,
    required this.sourceManager,
    required this.message,
    this.recoveryHint,
  });

  final ClipboardFailureKind kind;
  final String operation;
  final String sourceManager;
  final String message;
  final String? recoveryHint;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'operation': operation,
      'sourceManager': sourceManager,
      'message': message,
      if (recoveryHint != null) 'recoveryHint': recoveryHint,
    };
  }
}

class ClipboardOperationResult {
  const ClipboardOperationResult({required this.status, this.text, this.message});
  final ClipboardOperationStatus status;
  final String? text;
  final String? message;
  bool get succeeded => status == ClipboardOperationStatus.succeeded;
}

class ClipboardFailureClassifier {
  const ClipboardFailureClassifier({required this.sourceManager});

  final String sourceManager;

  ClipboardOperationFailure? classify(
    ClipboardOperationResult result, {
    required String operation,
    String? recoveryHint,
  }) {
    if (result.succeeded) {
      return null;
    }
    return ClipboardOperationFailure(
      kind: result.status == ClipboardOperationStatus.blocked
          ? ClipboardFailureKind.blocked
          : ClipboardFailureKind.unknownFailure,
      operation: operation,
      sourceManager: sourceManager,
      message: result.message ?? 'Clipboard operation failed.',
      recoveryHint: recoveryHint,
    );
  }
}

abstract class ClipboardManager {
  ClipboardFacts get facts;
  ClipboardCompatibility get compatibility;
  Future<ClipboardOperationResult> writeText(String text);
  Future<ClipboardOperationResult> readText();
  ClipboardOperationFailure? failureFor(
    ClipboardOperationResult result, {
    required String operation,
    String? recoveryHint,
  });
}

class UnsupportedClipboardManager implements ClipboardManager {
  UnsupportedClipboardManager({required this.facts}) : compatibility = ClipboardAdapter(facts).adapt();
  @override
  final ClipboardFacts facts;
  @override
  final ClipboardCompatibility compatibility;
  @override
  Future<ClipboardOperationResult> writeText(String text) async => const ClipboardOperationResult(status: ClipboardOperationStatus.blocked, message: 'Clipboard is not available.');
  @override
  Future<ClipboardOperationResult> readText() async => const ClipboardOperationResult(status: ClipboardOperationStatus.blocked, message: 'Clipboard is not available.');
  @override
  ClipboardOperationFailure? failureFor(
    ClipboardOperationResult result, {
    required String operation,
    String? recoveryHint,
  }) {
    return const ClipboardFailureClassifier(
      sourceManager: 'UnsupportedClipboardManager',
    ).classify(
      result,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }
}
