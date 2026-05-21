// ignore_for_file: use_super_parameters

import '../platform_context/platform_context.dart';
import 'pty_adapter.dart';
import 'pty_facts.dart';
import 'pty_manager.dart';
import 'pty_prober.dart';
import 'pty_prober_stub.dart';

Future<PtyManager> createPlatformPtyManager({
  PtyProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  if (platformContext != null) {
    return UnsupportedPtyManager(facts: platformContext.pty);
  }
  final facts = await (prober ?? const UnsupportedPtyProber()).probe();
  return UnsupportedPtyManager(facts: facts);
}

class LocalPtyManager extends UnsupportedPtyManager {
  LocalPtyManager({
    required PtyFacts facts,
    PtyAdapter? adapter,
    PtyNativeOperationBackendRegistry? nativeOperations,
  }) : super(facts: facts);

  factory LocalPtyManager.linuxDebianArmForTest({
    String scriptUtilityPath = '/usr/bin/script',
    PtyNativeOperationBackendRegistry? nativeOperations,
  }) {
    return LocalPtyManager(
      facts: PtyFacts.linuxDebianArm(scriptUtilityPath: scriptUtilityPath),
      nativeOperations: nativeOperations,
    );
  }
}
