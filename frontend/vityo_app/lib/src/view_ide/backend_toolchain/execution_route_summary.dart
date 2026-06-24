import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'project_graph_contract.dart';

class ExecutionRouteSummary {
  const ExecutionRouteSummary({
    required this.title,
    required this.body,
    required this.primaryAdapterKind,
    required this.previewOnly,
    required this.jitRoute,
  });

  final String title;
  final String body;
  final AdapterKind primaryAdapterKind;
  final bool previewOnly;
  final JitRouteSummary jitRoute;
}

class JitRouteSummary {
  const JitRouteSummary({
    required this.title,
    required this.body,
    required this.primaryAdapterKind,
    required this.blocked,
  });

  final String title;
  final String body;
  final AdapterKind primaryAdapterKind;
  final bool blocked;
}

class ExecutionRouteGate {
  const ExecutionRouteGate({
    required this.summary,
    required this.allowed,
    required this.blockedReason,
  });

  final ExecutionRouteSummary summary;
  final bool allowed;
  final String? blockedReason;
}

enum ExecutionRouteIntent { workflow, jit }

enum BackendExecutionRouteKind { localCli, ffi, hosted, blocked }

extension BackendExecutionRouteKindX on BackendExecutionRouteKind {
  String get wireValue {
    return switch (this) {
      BackendExecutionRouteKind.localCli => 'local-cli',
      BackendExecutionRouteKind.ffi => 'ffi',
      BackendExecutionRouteKind.hosted => 'hosted',
      BackendExecutionRouteKind.blocked => 'blocked',
    };
  }
}

class BackendExecutionRouteSelection {
  const BackendExecutionRouteSelection({
    required this.routeKind,
    required this.intent,
    required this.adapterKind,
    required this.allowed,
    required this.previewOnly,
    required this.title,
    required this.detail,
    this.blockedReason,
  });

  final BackendExecutionRouteKind routeKind;
  final ExecutionRouteIntent intent;
  final AdapterKind adapterKind;
  final bool allowed;
  final bool previewOnly;
  final String title;
  final String detail;
  final String? blockedReason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'routeKind': routeKind.wireValue,
      'intent': intent.name,
      'adapterKind': adapterKind.wireValue,
      'allowed': allowed,
      'previewOnly': previewOnly,
      'title': title,
      'detail': detail,
      if (blockedReason != null) 'blockedReason': blockedReason,
    };
  }
}

BackendExecutionRouteSelection selectBackendExecutionRoute({
  required PlatformTarget platformTarget,
  required ProjectGraphSnapshot projectGraph,
  required List<AdapterCapabilitySnapshot> adapterCapabilities,
  ExecutionRouteIntent routeIntent = ExecutionRouteIntent.workflow,
}) {
  final gate = evaluateExecutionRouteGate(
    platformTarget: platformTarget,
    projectGraph: projectGraph,
    adapterCapabilities: adapterCapabilities,
    routeIntent: routeIntent,
  );
  return BackendExecutionRouteSelection(
    routeKind: gate.allowed
        ? _routeKindForAdapter(gate.summary.primaryAdapterKind)
        : BackendExecutionRouteKind.blocked,
    intent: routeIntent,
    adapterKind: gate.summary.primaryAdapterKind,
    allowed: gate.allowed,
    previewOnly: gate.summary.previewOnly,
    title: gate.summary.title,
    detail: gate.summary.body,
    blockedReason: gate.blockedReason,
  );
}

ExecutionRouteGate evaluateExecutionRouteGate({
  required PlatformTarget platformTarget,
  required ProjectGraphSnapshot projectGraph,
  required List<AdapterCapabilitySnapshot> adapterCapabilities,
  ExecutionRouteIntent routeIntent = ExecutionRouteIntent.workflow,
}) {
  final summary = summarizeExecutionRoute(
    platformTarget: platformTarget,
    projectGraph: projectGraph,
    adapterCapabilities: adapterCapabilities,
    routeIntent: routeIntent,
  );
  if (!summary.previewOnly) {
    return ExecutionRouteGate(
      summary: summary,
      allowed: true,
      blockedReason: null,
    );
  }
  return ExecutionRouteGate(
    summary: summary,
    allowed: false,
    blockedReason: '${summary.title}. ${summary.body}',
  );
}

BackendExecutionRouteKind _routeKindForAdapter(AdapterKind adapterKind) {
  return switch (adapterKind) {
    AdapterKind.cli => BackendExecutionRouteKind.localCli,
    AdapterKind.ffi => BackendExecutionRouteKind.ffi,
    AdapterKind.cloud => BackendExecutionRouteKind.hosted,
  };
}

ExecutionRouteSummary summarizeExecutionRoute({
  required PlatformTarget platformTarget,
  required ProjectGraphSnapshot projectGraph,
  required List<AdapterCapabilitySnapshot> adapterCapabilities,
  ExecutionRouteIntent routeIntent = ExecutionRouteIntent.workflow,
}) {
  final cli = _capabilityFor(adapterCapabilities, AdapterKind.cli);
  final ffi = _capabilityFor(adapterCapabilities, AdapterKind.ffi);
  final cloud = _capabilityFor(adapterCapabilities, AdapterKind.cloud);
  final jitRoute = summarizeJitRoute(
    platformTarget: platformTarget,
    projectGraph: projectGraph,
    adapterCapabilities: adapterCapabilities,
  );

  if (routeIntent == ExecutionRouteIntent.jit) {
    return ExecutionRouteSummary(
      title: jitRoute.title,
      body: jitRoute.body,
      primaryAdapterKind: jitRoute.primaryAdapterKind,
      previewOnly: jitRoute.blocked,
      jitRoute: jitRoute,
    );
  }

  if (platformTarget == PlatformTarget.ios) {
    return ExecutionRouteSummary(
      title: 'Cloud-only by policy',
      body: cloud.execution.isAvailable
          ? 'iOS keeps compile/run in the Cloud Adapter path, and the hosted control plane is live for project execution.'
          : 'iOS keeps compile/run in the Cloud Adapter path. Local CLI and FFI execution stay disabled even when a compiler is installed elsewhere.',
      primaryAdapterKind: AdapterKind.cloud,
      previewOnly: !cloud.execution.isAvailable,
      jitRoute: jitRoute,
    );
  }

  if (platformTarget == PlatformTarget.web || projectGraph.isHosted) {
    return ExecutionRouteSummary(
      title: 'Hosted project route',
      body: cloud.projectGraph.isAvailable && cloud.execution.isAvailable
          ? 'Hosted workspaces use Cloud Adapter project graph and execution routes. Local binaries are not part of the hosted path.'
          : 'Hosted workspaces reserve the Cloud Adapter route, but the hosted control plane has not published a live project workflow yet.',
      primaryAdapterKind: AdapterKind.cloud,
      previewOnly:
          !(cloud.projectGraph.isAvailable && cloud.execution.isAvailable),
      jitRoute: jitRoute,
    );
  }

  if (projectGraph.isScratch) {
    if (cli.execution.level != AdapterCapabilityLevel.unavailable &&
        projectGraph.hasActiveCompiler) {
      return ExecutionRouteSummary(
        title: 'Scratch single-file route',
        body:
            'The active buffer can run through published styio CLI single-file entry. Diagnostics return over the jsonl machine path.',
        primaryAdapterKind: AdapterKind.cli,
        previewOnly: false,
        jitRoute: jitRoute,
      );
    }

    if (ffi.execution.level != AdapterCapabilityLevel.unavailable) {
      return ExecutionRouteSummary(
        title: 'Scratch route reserved for FFI',
        body:
            'No local CLI compiler was resolved, but the shell still reserves the same scratch route for a future FFI Adapter.',
        primaryAdapterKind: AdapterKind.ffi,
        previewOnly: true,
        jitRoute: jitRoute,
      );
    }

    return ExecutionRouteSummary(
      title: 'Scratch route blocked',
      body:
          'No local compiler route is available yet. Install styio or point VITYO_STYIO_BIN to a published CLI binary.',
      primaryAdapterKind: AdapterKind.cli,
      previewOnly: true,
      jitRoute: jitRoute,
    );
  }

  if (projectGraph.compilePlanConsumerAdvertised &&
      cli.execution.level != AdapterCapabilityLevel.unavailable) {
    return ExecutionRouteSummary(
      title: 'Project route live through spio',
      body:
          'The active compiler advertises compile-plan support, so project build/run/test can execute through spio with a live published handoff.',
      primaryAdapterKind: AdapterKind.cli,
      previewOnly: false,
      jitRoute: jitRoute,
    );
  }

  if (projectGraph.compilePlanConsumerAdvertised) {
    return ExecutionRouteSummary(
      title: 'Project route blocked by adapter',
      body:
          'The active compiler advertises compile-plan support, but no CLI execution adapter is available for the current route snapshot.',
      primaryAdapterKind: AdapterKind.cli,
      previewOnly: true,
      jitRoute: jitRoute,
    );
  }

  if (platformTarget == PlatformTarget.android &&
      cloud.execution.level != AdapterCapabilityLevel.unavailable) {
    return ExecutionRouteSummary(
      title: cloud.execution.isAvailable
          ? 'Project route live with cloud fallback'
          : 'Project route preview-only',
      body: cloud.execution.isAvailable
          ? 'Android keeps local-first intent, while the hosted control plane remains available as a live fallback route.'
          : 'Android keeps local-first intent, but current project execution still blocks until the active compiler advertises compile-plan support. Cloud remains the fallback route.',
      primaryAdapterKind: AdapterKind.cli,
      previewOnly: !cloud.execution.isAvailable,
      jitRoute: jitRoute,
    );
  }

  return ExecutionRouteSummary(
    title: 'Project route preview-only',
    body:
        'The shell can inspect spio projects today, but build/run/test stays blocked until the active compiler advertises compile-plan support.',
    primaryAdapterKind: AdapterKind.cli,
    previewOnly: true,
    jitRoute: jitRoute,
  );
}

JitRouteSummary summarizeJitRoute({
  required PlatformTarget platformTarget,
  required ProjectGraphSnapshot projectGraph,
  required List<AdapterCapabilitySnapshot> adapterCapabilities,
}) {
  final cli = _capabilityFor(adapterCapabilities, AdapterKind.cli);
  final ffi = _capabilityFor(adapterCapabilities, AdapterKind.ffi);
  final cloud = _capabilityFor(adapterCapabilities, AdapterKind.cloud);

  if (platformTarget == PlatformTarget.ios) {
    return const JitRouteSummary(
      title: 'JIT disabled by iOS policy',
      body:
          'iOS does not mount unrestricted local JIT or compiler modules; execution stays cloud-routed.',
      primaryAdapterKind: AdapterKind.cloud,
      blocked: true,
    );
  }

  if (platformTarget == PlatformTarget.web || projectGraph.isHosted) {
    return JitRouteSummary(
      title: cloud.execution.isAvailable
          ? 'JIT unavailable on hosted route'
          : 'JIT blocked with hosted route',
      body:
          'Hosted workspaces consume execution envelopes from the Cloud Adapter and do not expose local JIT modules.',
      primaryAdapterKind: AdapterKind.cloud,
      blocked: true,
    );
  }

  if (ffi.execution.isAvailable) {
    return const JitRouteSummary(
      title: 'JIT route live through FFI',
      body:
          'The project JIT route is owned by the FFI Adapter, so build/run workflow state does not change the JIT transport.',
      primaryAdapterKind: AdapterKind.ffi,
      blocked: false,
    );
  }

  if (projectGraph.jitRouteAdvertised && cli.execution.isAvailable) {
    return const JitRouteSummary(
      title: 'JIT route live through local CLI',
      body:
          'The active compiler advertises a JIT route, so local project execution can expose the JIT lane through the CLI Adapter.',
      primaryAdapterKind: AdapterKind.cli,
      blocked: false,
    );
  }

  if (ffi.execution.isPartial) {
    return const JitRouteSummary(
      title: 'JIT route reserved for FFI',
      body:
          'The shell exposes the JIT route as an FFI capability gap until a published adapter can execute project code.',
      primaryAdapterKind: AdapterKind.ffi,
      blocked: true,
    );
  }

  if (platformTarget == PlatformTarget.android) {
    return JitRouteSummary(
      title: 'Android JIT route pending local compiler support',
      body: cloud.execution.level != AdapterCapabilityLevel.unavailable
          ? 'Android stays local-first for JIT. Cloud execution may run project workflows, but local JIT remains blocked until the active compiler advertises a JIT contract.'
          : 'Android stays local-first for JIT, but no local compiler has advertised a JIT contract yet.',
      primaryAdapterKind: AdapterKind.cli,
      blocked: true,
    );
  }

  if (cli.execution.level != AdapterCapabilityLevel.unavailable) {
    return const JitRouteSummary(
      title: 'JIT route blocked by missing compiler contract',
      body:
          'The local execution adapter is present, but the active compiler has not advertised a JIT contract.',
      primaryAdapterKind: AdapterKind.cli,
      blocked: true,
    );
  }

  return const JitRouteSummary(
    title: 'JIT route blocked',
    body:
        'No local execution adapter is available for a JIT lane. Install styio or publish a local runtime module before enabling JIT.',
    primaryAdapterKind: AdapterKind.cli,
    blocked: true,
  );
}

AdapterCapabilitySnapshot _capabilityFor(
  List<AdapterCapabilitySnapshot> snapshots,
  AdapterKind kind,
) {
  return snapshots.firstWhere(
    (snapshot) => snapshot.adapterKind == kind,
    orElse: () => AdapterCapabilitySnapshot(
      adapterKind: kind,
      languageService: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: 'No adapter capability resolved.',
      ),
      projectGraph: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: 'No adapter capability resolved.',
      ),
      execution: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: 'No adapter capability resolved.',
      ),
      runtimeEvents: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: 'No adapter capability resolved.',
      ),
    ),
  );
}
