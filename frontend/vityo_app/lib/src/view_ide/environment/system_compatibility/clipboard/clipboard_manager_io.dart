import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context.dart';
import 'clipboard_adapter.dart';
import 'clipboard_facts.dart';
import 'clipboard_manager.dart';
import 'clipboard_prober.dart';
import 'clipboard_prober_io.dart';

Future<ClipboardManager> createPlatformClipboardManager({
  ClipboardProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  final adapter = platformContext == null ? null : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.clipboard ?? await (prober ?? const LocalClipboardProber()).probe();
  return LocalClipboardManager(facts: facts, adapter: adapter?.clipboardAdapter);
}

class LocalClipboardManager implements ClipboardManager {
  LocalClipboardManager({required this.facts, ClipboardAdapter? adapter}) : compatibility = (adapter ?? ClipboardAdapter(facts)).adapt();
  factory LocalClipboardManager.linuxDebianArmForTest() => LocalClipboardManager(facts: ClipboardFacts.linuxDebianArm());
  @override
  final ClipboardFacts facts;
  @override
  final ClipboardCompatibility compatibility;
  String _memoryText = '';
  @override
  ClipboardOperationFailure? failureFor(
    ClipboardOperationResult result, {
    required String operation,
    String? recoveryHint,
  }) {
    return const ClipboardFailureClassifier(
      sourceManager: 'LocalClipboardManager',
    ).classify(
      result,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }

  @override
  Future<ClipboardOperationResult> writeText(String text) async {
    if (!compatibility.supportsText || !compatibility.supportsMemoryFallback) return const ClipboardOperationResult(status: ClipboardOperationStatus.blocked, message: 'Text clipboard is not available.');
    _memoryText = text;
    return ClipboardOperationResult(status: ClipboardOperationStatus.succeeded, text: text);
  }
  @override
  Future<ClipboardOperationResult> readText() async {
    if (!compatibility.supportsText || !compatibility.supportsMemoryFallback) return const ClipboardOperationResult(status: ClipboardOperationStatus.blocked, message: 'Text clipboard is not available.');
    return ClipboardOperationResult(status: ClipboardOperationStatus.succeeded, text: _memoryText);
  }
}
