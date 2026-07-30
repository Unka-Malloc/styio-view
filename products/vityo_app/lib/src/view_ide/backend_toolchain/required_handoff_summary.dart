import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'project_graph_contract.dart';

enum HandoffOwner { styio, pafio }

extension HandoffOwnerX on HandoffOwner {
  String get label {
    switch (this) {
      case HandoffOwner.styio:
        return 'styio';
      case HandoffOwner.pafio:
        return 'pafio';
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
        owner: HandoffOwner.pafio,
        title: 'Repair Pafio metadata v1 payload',
        detail:
            'Vityo could not consume pafio metadata --json cleanly. ${projectGraph.projectGraphPayloadFailure!.detail}',
        docPath: 'docs/external/for-pafio/Pafio-Metadata-Contract.md',
        blocking: true,
      ),
    );
  } else if (!_hasAvailableEndpoint(
    adapterCapabilities,
    (snapshot) => snapshot.projectGraph,
  )) {
    handoffs.add(
      const RequiredHandoff(
        owner: HandoffOwner.pafio,
        title: 'Publish metadata v1',
        detail:
            'Workspace members, packages, dependencies, and targets require the public Pafio metadata v1 payload.',
        docPath: 'docs/external/for-pafio/Pafio-Metadata-Contract.md',
        blocking: true,
      ),
    );
  }

  if (!projectGraph.hasProjectGraphPayloadFailure &&
      (projectGraph.lockState == ProjectLockState.unknown ||
          projectGraph.vendorState == ProjectVendorState.unknown)) {
    handoffs.add(
      const RequiredHandoff(
        owner: HandoffOwner.pafio,
        title: 'Publish precise lock and vendor state',
        detail:
            'Metadata v1 exposes lock and vendor presence; workflow completion continues through stable Pafio workflow JSON.',
        docPath: 'docs/external/for-pafio/Pafio-Workflow-Success-Payloads.md',
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
