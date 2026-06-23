import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'project_graph_contract.dart';

enum HandoffOwner { styio, spio }

extension HandoffOwnerX on HandoffOwner {
  String get label {
    switch (this) {
      case HandoffOwner.styio:
        return 'styio';
      case HandoffOwner.spio:
        return 'spio';
    }
  }
}

class RequiredHandoff {
  const RequiredHandoff({
    required this.owner,
    required this.title,
    required this.detail,
    required this.docPath,
    this.blocking = false,
  });

  final HandoffOwner owner;
  final String title;
  final String detail;
  final String docPath;
  final bool blocking;
}

List<RequiredHandoff> summarizeRequiredHandoffs({
  required PlatformTarget platformTarget,
  required ProjectGraphSnapshot projectGraph,
  required List<AdapterCapabilitySnapshot> adapterCapabilities,
}) {
  final handoffs = <RequiredHandoff>[];

  if (!_hasAvailableEndpoint(
    adapterCapabilities,
    (snapshot) => snapshot.languageService,
  )) {
    handoffs.add(
      const RequiredHandoff(
        owner: HandoffOwner.styio,
        title: 'Publish language-service machine contract',
        detail:
            'Editor semantics still run on mock layers because published token, semantic, completion, formatting, hover, and quick-fix payloads are not fully available.',
        docPath: 'docs/for-styio/Styio-Language-Service-Adapter-Contract.md',
        blocking: true,
      ),
    );
  }

  final projectNeedsLiveExecution =
      !projectGraph.isScratch &&
      platformTarget != PlatformTarget.ios &&
      platformTarget != PlatformTarget.web &&
      !projectGraph.compilePlanConsumerAdvertised;
  if (projectNeedsLiveExecution) {
    handoffs.add(
      const RequiredHandoff(
        owner: HandoffOwner.styio,
        title: 'Publish compile-plan consumer and live execution contract',
        detail:
            'Project build/run/test remains preview-only until styio accepts published compile-plan input and returns machine-readable compile/run results.',
        docPath: 'docs/for-styio/Styio-Compile-Run-Contract.md',
        blocking: true,
      ),
    );
  }

  if (!_hasAvailableEndpoint(
    adapterCapabilities,
    (snapshot) => snapshot.runtimeEvents,
  )) {
    handoffs.add(
      const RequiredHandoff(
        owner: HandoffOwner.styio,
        title: 'Publish runtime event stream',
        detail:
            'Runtime surface falls back to placeholders unless adapter capabilities include stable ordered runtime event envelopes.',
        docPath: 'docs/for-styio/Styio-Compile-Run-Contract.md',
      ),
    );
  }

  if (projectGraph.hasProjectGraphPayloadFailure) {
    handoffs.add(
      RequiredHandoff(
        owner: HandoffOwner.spio,
        title: 'Repair published project graph payload',
        detail:
            'spio already advertises a project graph contract, but Vityo could not consume it cleanly. ${projectGraph.projectGraphPayloadFailure!.detail}',
        docPath: 'docs/for-spio/Spio-Project-Graph-Contract.md',
        blocking: true,
      ),
    );
  } else if (!_hasAvailableEndpoint(
    adapterCapabilities,
    (snapshot) => snapshot.projectGraph,
  )) {
    handoffs.add(
      const RequiredHandoff(
        owner: HandoffOwner.spio,
        title: 'Publish project graph success payload',
        detail:
            'Workspace members, packages, targets, and toolchain state are still inferred from canonical files because spio has not published a dedicated project graph payload.',
        docPath: 'docs/for-spio/Spio-Project-Graph-Contract.md',
        blocking: true,
      ),
    );
  }

  if (!projectGraph.hasProjectGraphPayloadFailure &&
      (projectGraph.lockState == ProjectLockState.unknown ||
          projectGraph.vendorState == ProjectVendorState.unknown)) {
    handoffs.add(
      const RequiredHandoff(
        owner: HandoffOwner.spio,
        title: 'Publish lock and vendor freshness state',
        detail:
            'The shell can see canonical files, but freshness and workflow completion state still need stable success payloads from spio.',
        docPath: 'docs/for-spio/Spio-Workflow-Success-Payloads.md',
      ),
    );
  }

  if (projectGraph.hasToolchainStatePayloadFailure) {
    handoffs.add(
      RequiredHandoff(
        owner: HandoffOwner.spio,
        title: 'Repair published toolchain and registry state',
        detail:
            'spio already advertises toolchain_state, but Vityo could not consume the published payload cleanly. ${projectGraph.toolchainStatePayloadFailure!.detail}',
        docPath: 'docs/for-spio/Spio-Toolchain-And-Registry-State.md',
      ),
    );
  } else if (!projectGraph.hasToolchainEnvironment) {
    handoffs.add(
      const RequiredHandoff(
        owner: HandoffOwner.spio,
        title: 'Publish toolchain and registry state',
        detail:
            'Toolchain resolution, managed installs, and registry readiness need a machine-readable spio contract instead of filesystem inference.',
        docPath: 'docs/for-spio/Spio-Toolchain-And-Registry-State.md',
      ),
    );
  }

  if (!projectGraph.hasSourceState &&
      projectGraph.hasManifest &&
      !projectGraph.hasProjectGraphPayloadFailure) {
    handoffs.add(
      const RequiredHandoff(
        owner: HandoffOwner.spio,
        title: 'Publish dependency source and cache state',
        detail:
            'Vendored snapshots, git caches, and registry cache roots still need a machine-readable spio contract instead of filesystem inference.',
        docPath: 'docs/for-spio/Spio-Toolchain-And-Registry-State.md',
      ),
    );
  }

  return handoffs;
}

bool _hasAvailableEndpoint(
  List<AdapterCapabilitySnapshot> snapshots,
  AdapterEndpointCapability Function(AdapterCapabilitySnapshot snapshot) select,
) {
  return snapshots.any(
    (snapshot) => select(snapshot).level == AdapterCapabilityLevel.available,
  );
}
