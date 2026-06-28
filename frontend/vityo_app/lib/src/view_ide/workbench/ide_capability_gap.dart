/// Capability gap model — structured blocked reasons for missing IDE capabilities.
/// Pure Dart, no Flutter imports. Used by both view_ide and view_render.
library;

import 'ide_capability.dart';

// ── Capability Gap ────────────────────────────────────────────────

/// A single capability gap with structured reason and resolution hint.
class IdeCapabilityGap {
  const IdeCapabilityGap({
    required this.capabilityId,
    required this.reason,
    this.detail = '',
    this.resolutionHint = '',
    this.upstreamContract,
    this.affectedCommandIds = const <String>[],
    this.affectedSurfaces = const <String>[],
  });

  final String capabilityId;
  final IdeCapabilityAvailability reason;
  final String detail;
  final String resolutionHint;
  final String? upstreamContract;
  final List<String> affectedCommandIds;
  final List<String> affectedSurfaces;

  String get displayMessage {
    final buffer = StringBuffer('`$capabilityId`: ');
    switch (reason) {
      case IdeCapabilityAvailability.blockedByUpstreamContract:
        buffer.write('blocked by upstream ');
        buffer.write(upstreamContract ?? 'contract');
        break;
      case IdeCapabilityAvailability.blockedByPlatform:
        buffer.write('not supported on this platform');
        break;
      case IdeCapabilityAvailability.notMounted:
        buffer.write('module not mounted');
        break;
      case IdeCapabilityAvailability.planned:
        buffer.write('planned, not yet implemented');
        break;
      case IdeCapabilityAvailability.previewOnly:
        buffer.write('preview only');
        break;
      case IdeCapabilityAvailability.available:
        buffer.write('available');
        break;
    }
    if (detail.isNotEmpty) {
      buffer.write(' — ');
      buffer.write(detail);
    }
    return buffer.toString();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'capabilityId': capabilityId,
        'reason': reason.name,
        'detail': detail,
        'resolutionHint': resolutionHint,
        'upstreamContract': upstreamContract,
        'affectedCommandIds': affectedCommandIds,
        'affectedSurfaces': affectedSurfaces,
        'displayMessage': displayMessage,
      };
}

// ── Gap Report ────────────────────────────────────────────────────

/// Aggregated capability gap report for a workspace/platform context.
class IdeCapabilityGapReport {
  const IdeCapabilityGapReport({
    this.gaps = const <IdeCapabilityGap>[],
    this.platformTarget = '',
    this.generatedAtIso8601 = '',
  });

  final List<IdeCapabilityGap> gaps;
  final String platformTarget;
  final String generatedAtIso8601;

  bool get hasBlockers =>
      gaps.any((g) => g.reason == IdeCapabilityAvailability.blockedByUpstreamContract);

  bool get hasGaps => gaps.isNotEmpty;

  List<IdeCapabilityGap> get upstreamBlocked =>
      gaps
          .where(
            (g) =>
                g.reason == IdeCapabilityAvailability.blockedByUpstreamContract,
          )
          .toList(growable: false);

  List<IdeCapabilityGap> get platformBlocked =>
      gaps
          .where(
            (g) => g.reason == IdeCapabilityAvailability.blockedByPlatform,
          )
          .toList(growable: false);

  /// Human-readable summary for display in capability/readiness surface.
  String get summary {
    if (gaps.isEmpty) return 'All IDE capabilities available on $platformTarget.';
    final buffer = StringBuffer();
    buffer.writeln('IDE capability status for $platformTarget:');
    for (final gap in gaps) {
      buffer.writeln('  ${gap.displayMessage}');
    }
    return buffer.toString();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'gaps': gaps.map((g) => g.toJson()).toList(growable: false),
        'platformTarget': platformTarget,
        'generatedAtIso8601': generatedAtIso8601,
        'hasBlockers': hasBlockers,
        'hasGaps': hasGaps,
      };
}
