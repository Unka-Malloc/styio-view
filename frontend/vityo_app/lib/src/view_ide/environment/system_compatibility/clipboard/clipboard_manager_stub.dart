// ignore_for_file: use_super_parameters

import '../platform_context/platform_context.dart';
import 'clipboard_adapter.dart';
import 'clipboard_facts.dart';
import 'clipboard_manager.dart';
import 'clipboard_prober.dart';
import 'clipboard_prober_stub.dart';

Future<ClipboardManager> createPlatformClipboardManager({
  ClipboardProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  if (platformContext != null) {
    return UnsupportedClipboardManager(facts: platformContext.clipboard);
  }
  final facts = await (prober ?? const UnsupportedClipboardProber()).probe();
  return UnsupportedClipboardManager(facts: facts);
}

class LocalClipboardManager extends UnsupportedClipboardManager {
  LocalClipboardManager({
    required ClipboardFacts facts,
    ClipboardAdapter? adapter,
  }) : super(facts: facts);

  factory LocalClipboardManager.linuxDebianArmForTest() {
    return LocalClipboardManager(facts: ClipboardFacts.linuxDebianArm());
  }
}
