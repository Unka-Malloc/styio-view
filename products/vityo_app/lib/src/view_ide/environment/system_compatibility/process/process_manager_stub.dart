// ignore_for_file: use_super_parameters

import '../platform_context/platform_context.dart';
import 'process_adapter.dart';
import 'process_facts.dart';
import 'process_manager.dart';
import 'process_prober.dart';
import 'process_prober_stub.dart';

Future<ProcessManager> createPlatformProcessManager({
  ProcessProber? prober,
  PlatformContextSnapshot? platformContext,
  Object? vityodClient,
}) async {
  if (platformContext != null) {
    return UnsupportedProcessManager(facts: platformContext.process);
  }
  final facts = await (prober ?? const UnsupportedProcessProber()).probe();
  return UnsupportedProcessManager(facts: facts);
}

class LocalProcessManager extends UnsupportedProcessManager {
  LocalProcessManager({
    required ProcessFacts facts,
    Object? client,
    ProcessAdapter? adapter,
  }) : super(facts: facts);

  factory LocalProcessManager.linuxDebianArmForTest({Object? client}) {
    return LocalProcessManager(
      facts: ProcessFacts.linuxDebianArm(),
      client: client,
    );
  }
}
