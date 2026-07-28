/// IDE capability registry — registers, queries, and derives capability state.
/// Pure Dart, no Flutter imports. Consumed by view_render for display.
library;

import 'ide_capability.dart';
import '../platform/platform_target.dart';

// ── Registry ──────────────────────────────────────────────────────

class IdeCapabilityRegistry {
  IdeCapabilityRegistry({Iterable<IdeCapabilityDescriptor> descriptors = const []}) {
    for (final descriptor in descriptors) {
      register(descriptor);
    }
  }

  final Map<String, IdeCapabilityDescriptor> _byId = {};
  final Map<IdeCapabilityDomain, List<IdeCapabilityDescriptor>> _byDomain = {};

  List<IdeCapabilityDescriptor> get all =>
      List<IdeCapabilityDescriptor>.unmodifiable(_byId.values);

  bool contains(String capabilityId) => _byId.containsKey(capabilityId);

  IdeCapabilityDescriptor? lookup(String capabilityId) => _byId[capabilityId];

  void register(IdeCapabilityDescriptor descriptor) {
    _byId[descriptor.capabilityId] = descriptor;
    _byDomain.putIfAbsent(descriptor.domain, () => []).add(descriptor);
  }

  /// All capabilities in a domain.
  List<IdeCapabilityDescriptor> domain(IdeCapabilityDomain domain) =>
      List<IdeCapabilityDescriptor>.unmodifiable(
        _byDomain[domain] ?? const <IdeCapabilityDescriptor>[],
      );

  /// Only available capabilities.
  List<IdeCapabilityDescriptor> get available =>
      all.where((c) => c.isAvailable).toList(growable: false);

  /// Only usable (available or preview-only) capabilities.
  List<IdeCapabilityDescriptor> get usable =>
      all.where((c) => c.isUsable).toList(growable: false);

  /// Capabilities blocked for any reason.
  List<IdeCapabilityDescriptor> get blocked =>
      all.where((c) => c.isBlocked).toList(growable: false);

  /// Capabilities blocked specifically by upstream contract.
  List<IdeCapabilityDescriptor> get upstreamBlocked => all
      .where(
        (c) => c.availability == IdeCapabilityAvailability.blockedByUpstreamContract,
      )
      .toList(growable: false);

  /// Capabilities blocked by platform.
  List<IdeCapabilityDescriptor> get platformBlocked => all
      .where(
        (c) => c.availability == IdeCapabilityAvailability.blockedByPlatform,
      )
      .toList(growable: false);

  /// Aggregated capability snapshot for display.
  IdeCapabilitySnapshot toSnapshot() {
    return IdeCapabilitySnapshot(
      totalCount: _byId.length,
      availableCount: available.length,
      previewCount: all
          .where(
            (c) => c.availability == IdeCapabilityAvailability.previewOnly,
          )
          .length,
      blockedCount: blocked.length,
      byDomain: {
        for (final d in IdeCapabilityDomain.values)
          d.wireValue: (CapabilityDomainSummary(
            domain: d,
            total: domain(d).length,
            available: domain(d)
                .where((c) => c.isAvailable)
                .length,
            blocked: domain(d).where((c) => c.isBlocked).length,
          )).toJson(),
      },
      generatedAtIso8601: DateTime.now().toUtc().toIso8601String(),
    );
  }
}

// ── Snapshot ──────────────────────────────────────────────────────

class CapabilityDomainSummary {
  const CapabilityDomainSummary({
    required this.domain,
    this.total = 0,
    this.available = 0,
    this.blocked = 0,
  });

  final IdeCapabilityDomain domain;
  final int total;
  final int available;
  final int blocked;

  Map<String, Object?> toJson() => <String, Object?>{
        'domain': domain.wireValue,
        'label': domain.label,
        'total': total,
        'available': available,
        'blocked': blocked,
      };
}

class IdeCapabilitySnapshot {
  const IdeCapabilitySnapshot({
    this.totalCount = 0,
    this.availableCount = 0,
    this.previewCount = 0,
    this.blockedCount = 0,
    this.byDomain = const <String, Map<String, Object?>>{},
    this.generatedAtIso8601 = '',
  });

  final int totalCount;
  final int availableCount;
  final int previewCount;
  final int blockedCount;
  final Map<String, Map<String, Object?>> byDomain;
  final String generatedAtIso8601;

  double get readinessRatio =>
      totalCount > 0 ? availableCount / totalCount : 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'totalCount': totalCount,
        'availableCount': availableCount,
        'previewCount': previewCount,
        'blockedCount': blockedCount,
        'readinessRatio': readinessRatio,
        'byDomain': byDomain,
        'generatedAtIso8601': generatedAtIso8601,
      };
}

// ── Platform-aware Derivation ─────────────────────────────────────

/// Derives capability availability for a specific platform target.
/// iOS and Web may have more blocked capabilities than Desktop.
class PlatformCapabilityFilter {
  const PlatformCapabilityFilter();

  /// Returns capabilities that should be hidden on [platformTarget]
  /// because the platform doesn't support them.
  Set<String> hiddenCapabilitiesFor(PlatformTarget platformTarget) {
    switch (platformTarget) {
      case PlatformTarget.ios:
        return {
          'execution.local',
          'execution.localCompiler',
          'sourceControl.localGit',
        };
      case PlatformTarget.web:
        return {
          'execution.local',
          'execution.localCompiler',
          'sourceControl.localGit',
        };
      case PlatformTarget.android:
        return {
          'sourceControl.localGit',
        };
      case PlatformTarget.windows:
      case PlatformTarget.linux:
      case PlatformTarget.macos:
      case PlatformTarget.unknown:
        return {};
    }
  }

  /// Filters a descriptor list for display on [platformTarget].
  List<IdeCapabilityDescriptor> filterForPlatform(
    Iterable<IdeCapabilityDescriptor> descriptors,
    PlatformTarget platformTarget,
  ) {
    final hidden = hiddenCapabilitiesFor(platformTarget);
    return descriptors
        .where((d) => !hidden.contains(d.capabilityId))
        .toList(growable: false);
  }
}
