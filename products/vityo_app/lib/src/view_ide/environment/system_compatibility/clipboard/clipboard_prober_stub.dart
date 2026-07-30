import 'dart:async';

import 'clipboard_facts.dart';
import 'clipboard_prober.dart';

class UnsupportedClipboardProber implements ClipboardProber {
  const UnsupportedClipboardProber();
  @override
  Future<ClipboardFacts> probe() async => ClipboardFacts(
    targetId: 'unsupported',
    operatingSystem: 'unknown',
    distributionId: 'unknown',
    architecture: 'unknown',
    providerKind: ClipboardProviderKind.unsupported,
    supportsText: false,
    supportsSystemClipboard: false,
    supportsMemoryFallback: false,
    detectedAt: DateTime.now().toUtc(),
  );
}

class LocalClipboardProber extends UnsupportedClipboardProber {
  const LocalClipboardProber({
    String targetId = 'local',
    String? operatingSystem,
    Map<String, String>? environment,
    Future<String?> Function()? architectureReader,
    Future<Map<String, String>> Function()? osReleaseReader,
    DateTime Function()? clock,
  });
}
