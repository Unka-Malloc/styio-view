/// IDE capability domain model — pure Dart, no Flutter imports.
///
/// Expresses every IDE capability domain, its maturity level, availability
/// status, owner boundary, related commands, and target surface.
/// This is the single source of truth for capability state; view_render
/// consumes this model but never infers capability state from UI context.
library;

import '../commands/app_commands.dart';

// ── Capability Domain ─────────────────────────────────────────────

/// The top-level IDE capability domains.
enum IdeCapabilityDomain {
  workbench,
  editorEngine,
  languageIntelligence,
  projectModel,
  runDebugRuntime,
  agentWorkflow,
  moduleSystem,
  sourceControl,
  settingsKeymapProfile,
  securityTrust,
  crossPlatformHostedWorkspace,
  performanceAccessibility,
}

extension IdeCapabilityDomainX on IdeCapabilityDomain {
  String get label {
    switch (this) {
      case IdeCapabilityDomain.workbench:
        return 'Workbench';
      case IdeCapabilityDomain.editorEngine:
        return 'Editor Engine';
      case IdeCapabilityDomain.languageIntelligence:
        return 'Language Intelligence';
      case IdeCapabilityDomain.projectModel:
        return 'Project Model';
      case IdeCapabilityDomain.runDebugRuntime:
        return 'Run / Debug / Runtime';
      case IdeCapabilityDomain.agentWorkflow:
        return 'Agent Workflow';
      case IdeCapabilityDomain.moduleSystem:
        return 'Module System';
      case IdeCapabilityDomain.sourceControl:
        return 'Source Control';
      case IdeCapabilityDomain.settingsKeymapProfile:
        return 'Settings / Profile';
      case IdeCapabilityDomain.securityTrust:
        return 'Security / Trust';
      case IdeCapabilityDomain.crossPlatformHostedWorkspace:
        return 'Cross-Platform / Hosted';
      case IdeCapabilityDomain.performanceAccessibility:
        return 'Performance / Accessibility';
    }
  }

  String get wireValue => name;
}

// ── Capability Maturity ───────────────────────────────────────────

/// Vityo's own capability maturity levels.
/// Never expressed as "like VSCode" or "like JetBrains".
enum IdeCapabilityMaturity {
  /// Placeholder exists; no product behavior.
  l0Stub,

  /// Repo-local model exists with unit tests.
  l1LocalModel,

  /// Consumes a Vityo-owned adapter contract.
  l2ContractBacked,

  /// Wired into product shell with end-to-end workflow.
  l3ProductWorkflow,

  /// Verified on all target platforms.
  l4CrossPlatformReliable,

  /// Exploits Styio language properties uniquely.
  l5StyioNativeDifferentiated,
}

extension IdeCapabilityMaturityX on IdeCapabilityMaturity {
  String get label {
    switch (this) {
      case IdeCapabilityMaturity.l0Stub:
        return 'L0 — Stub';
      case IdeCapabilityMaturity.l1LocalModel:
        return 'L1 — Local Model';
      case IdeCapabilityMaturity.l2ContractBacked:
        return 'L2 — Contract-backed';
      case IdeCapabilityMaturity.l3ProductWorkflow:
        return 'L3 — Product Workflow';
      case IdeCapabilityMaturity.l4CrossPlatformReliable:
        return 'L4 — Cross-platform';
      case IdeCapabilityMaturity.l5StyioNativeDifferentiated:
        return 'L5 — Styio-native';
    }
  }
}

// ── Capability Availability ───────────────────────────────────────

/// Whether an IDE capability is currently available.
enum IdeCapabilityAvailability {
  /// Fully available and tested.
  available,

  /// Available but with limited scope or known issues.
  previewOnly,

  /// Blocked because upstream Styio/Spio hasn't published the contract.
  blockedByUpstreamContract,

  /// Blocked because the current platform doesn't support it.
  blockedByPlatform,

  /// The required module is not mounted.
  notMounted,

  /// On the roadmap but not yet implemented.
  planned,
}

extension IdeCapabilityAvailabilityX on IdeCapabilityAvailability {
  bool get isAvailable => this == IdeCapabilityAvailability.available;
  bool get isUsable =>
      this == IdeCapabilityAvailability.available ||
      this == IdeCapabilityAvailability.previewOnly;
  bool get isBlocked =>
      this == IdeCapabilityAvailability.blockedByUpstreamContract ||
      this == IdeCapabilityAvailability.blockedByPlatform ||
      this == IdeCapabilityAvailability.notMounted;
}

// ── Capability Descriptor ─────────────────────────────────────────

/// Describes a single IDE capability within a domain.
class IdeCapabilityDescriptor {
  const IdeCapabilityDescriptor({
    required this.capabilityId,
    required this.domain,
    required this.label,
    required this.description,
    this.maturity = IdeCapabilityMaturity.l1LocalModel,
    this.availability = IdeCapabilityAvailability.planned,
    this.blockedReason = '',
    this.ownerBoundary = '',
    this.relatedCommandIds = const <AppCommandId>[],
    this.requiredCapabilities = const <String>[],
    this.upstreamContract,
  });

  /// Stable capability identifier, e.g. 'language.diagnostics'.
  final String capabilityId;

  /// The domain this capability belongs to.
  final IdeCapabilityDomain domain;

  /// Human-readable label.
  final String label;

  /// One-line description.
  final String description;

  /// Current maturity level.
  final IdeCapabilityMaturity maturity;

  /// Current availability status.
  final IdeCapabilityAvailability availability;

  /// If blocked, the structured reason.
  final String blockedReason;

  /// The Vityo owner boundary (e.g., 'LanguageServiceAdapter').
  final String ownerBoundary;

  /// Command IDs that exercise this capability.
  final List<AppCommandId> relatedCommandIds;

  /// Other capability IDs this one depends on.
  final List<String> requiredCapabilities;

  /// If upstream-blocked, the name of the upstream contract needed.
  final String? upstreamContract;

  bool get isAvailable => availability.isAvailable;
  bool get isUsable => availability.isUsable;
  bool get isBlocked => availability.isBlocked;

  Map<String, Object?> toJson() => <String, Object?>{
        'capabilityId': capabilityId,
        'domain': domain.wireValue,
        'label': label,
        'description': description,
        'maturity': maturity.name,
        'availability': availability.name,
        'blockedReason': blockedReason,
        'ownerBoundary': ownerBoundary,
        'relatedCommandIds':
            relatedCommandIds.map((c) => c.name).toList(growable: false),
        'requiredCapabilities': requiredCapabilities,
        'upstreamContract': upstreamContract,
        'isAvailable': isAvailable,
        'isUsable': isUsable,
        'isBlocked': isBlocked,
      };
}
