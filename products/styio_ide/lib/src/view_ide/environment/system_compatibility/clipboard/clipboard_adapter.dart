import 'clipboard_facts.dart';

class ClipboardAdapter {
  const ClipboardAdapter(this.facts);
  final ClipboardFacts facts;
  ClipboardCompatibility adapt() => ClipboardCompatibility(
    targetId: facts.targetId,
    compatibilityTarget: facts.compatibilityTarget,
    supportsText: facts.supportsText,
    supportsSystemClipboard: facts.supportsSystemClipboard,
    supportsMemoryFallback: facts.supportsMemoryFallback,
  );
}

class ClipboardCompatibility {
  const ClipboardCompatibility({required this.targetId, required this.compatibilityTarget, required this.supportsText, required this.supportsSystemClipboard, required this.supportsMemoryFallback});
  final String targetId;
  final String compatibilityTarget;
  final bool supportsText;
  final bool supportsSystemClipboard;
  final bool supportsMemoryFallback;
  bool get isLinuxDebianArm => compatibilityTarget == 'linux-debian-arm';
}
