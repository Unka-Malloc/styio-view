/// Revision-bound diagnostic gate and capability gap models for
/// the Styio language service integration.
///
/// Key invariants:
/// - Diagnostics are bound to a document revision.
/// - Stale diagnostics (from a previous revision) are rejected.
/// - Missing upstream capabilities return structured blocked reasons.
/// - Capability gaps never cause crashes or fake results.
library;

import '../contract/language_contract.dart';

// ── Revision-Bound Diagnostic ─────────────────────────────────────

/// A diagnostic that is bound to a specific document revision.
/// If the document revision changes, the diagnostic is stale.
class RevisionBoundDiagnostic {
  const RevisionBoundDiagnostic({
    required this.diagnostic,
    required this.documentId,
    required this.revision,
    required this.source,
    this.confidence = DiagnosticConfidence.authoritative,
    this.schemaVersion = 1,
    this.extensions = const <String, Object?>{},
  });

  final Diagnostic diagnostic;
  final String documentId;
  final int revision;
  final DiagnosticSource source;
  final DiagnosticConfidence confidence;
  final int schemaVersion;
  final Map<String, Object?> extensions;

  static const Set<String> _knownKeys = <String>{
    'schemaVersion',
    'diagnostic',
    'documentId',
    'revision',
    'source',
    'confidence',
  };

  /// Whether this diagnostic applies to the given document revision.
  bool isStaleForRevision(int currentRevision) => revision != currentRevision;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'diagnostic': <String, Object?>{
          'severity': diagnostic.severity.name,
          'code': diagnostic.code,
          'message': diagnostic.message,
          'range': <String, int>{
            'start': diagnostic.range.start,
            'end': diagnostic.range.end,
          },
        },
        'documentId': documentId,
        'revision': revision,
        'source': source.name,
        'confidence': confidence.name,
        ...extensions,
      };

  factory RevisionBoundDiagnostic.fromJson(Map<String, Object?> json) {
    final diagMap =
        Map<String, Object?>.from(json['diagnostic'] as Map? ?? const {});
    final rangeMap =
        Map<String, int>.from(diagMap['range'] as Map? ?? const {});
    return RevisionBoundDiagnostic(
      diagnostic: Diagnostic(
        severity: _parseSeverity(diagMap['severity'] as String?),
        code: diagMap['code'] as String? ?? '',
        message: diagMap['message'] as String? ?? '',
        range: SourceRange(
          start: rangeMap['start'] ?? 0,
          end: rangeMap['end'] ?? 0,
        ),
      ),
      documentId: json['documentId'] as String? ?? '',
      revision: json['revision'] as int? ?? -1,
      source: _parseSource(json['source'] as String?),
      confidence: _parseConfidence(json['confidence'] as String?),
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      extensions: _collectUnknown(json),
    );
  }

  static DiagnosticSeverity _parseSeverity(String? raw) {
    return DiagnosticSeverity.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => DiagnosticSeverity.error,
    );
  }

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return {
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
  }
}

// ── Diagnostic Source ─────────────────────────────────────────────

/// Where a diagnostic originated — determines its authority.
enum DiagnosticSource {
  /// From the Styio compiler (authoritative).
  compiler,

  /// From a hosted StyioService (authoritative, possibly cached).
  styioService,

  /// From Vityo's local heuristics (best-effort, not authoritative).
  localHeuristic,

  /// From a linter or third-party tool.
  externalTool,

  /// Unknown source — should be treated as lowest confidence.
  unknown,
}

/// Confidence level of a diagnostic.
enum DiagnosticConfidence {
  /// Compiler-verified truth.
  authoritative,

  /// High confidence but not compiler-verified (e.g. StyioService).
  high,

  /// Medium confidence (e.g., local heuristic with good signal).
  medium,

  /// Low confidence — may be a false positive.
  low,

  /// Unknown — treat as informational only.
  unknown,
}

DiagnosticSource _parseSource(String? value) {
  for (final source in DiagnosticSource.values) {
    if (source.name == value) return source;
  }
  return DiagnosticSource.unknown;
}

DiagnosticConfidence _parseConfidence(String? value) {
  for (final confidence in DiagnosticConfidence.values) {
    if (confidence.name == value) return confidence;
  }
  return DiagnosticConfidence.unknown;
}

// ── Stale Result Gate ─────────────────────────────────────────────

/// Filters diagnostics to only those applicable to the current document revision.
class DiagnosticRevisionGate {
  const DiagnosticRevisionGate();

  /// Returns only diagnostics whose revision matches [currentRevision].
  /// Diagnostics from a different revision are stale and rejected.
  List<RevisionBoundDiagnostic> filterCurrent(
    Iterable<RevisionBoundDiagnostic> diagnostics,
    int currentRevision,
  ) {
    return diagnostics
        .where((d) => !d.isStaleForRevision(currentRevision))
        .toList(growable: false);
  }

  /// Returns diagnostics rejected because they are stale.
  List<RevisionBoundDiagnostic> staleDiagnostics(
    Iterable<RevisionBoundDiagnostic> diagnostics,
    int currentRevision,
  ) {
    return diagnostics
        .where((d) => d.isStaleForRevision(currentRevision))
        .toList(growable: false);
  }
}

// ── Capability Gap Models ─────────────────────────────────────────

/// Describes why a language capability is unavailable.
enum CapabilityGapReason {
  /// Upstream Styio or Pafio has not yet published the required contract.
  upstreamBlocked,

  /// The capability is designed but not implemented in Vityo.
  implementationNeeded,

  /// A provider exists but returned an error or empty result.
  providerError,

  /// The project index is not ready; caller should retry in smart mode.
  indexUnavailable,

  /// The provider exceeded the latency budget and returned a partial result.
  timeout,

  /// A newer document revision cancelled this request.
  cancelled,

  /// The current platform does not support this capability.
  platformUnsupported,

  /// The capability requires toolchain that is not installed.
  toolchainMissing,

  /// The capability is intentionally disabled by policy.
  policyDisabled,

  /// Unknown reason.
  unknown,
}

/// Structured blocked reason for a missing language capability.
class LanguageCapabilityGap {
  const LanguageCapabilityGap({
    required this.capabilityId,
    required this.reason,
    this.detail = '',
    this.resolution = '',
    this.upstreamContract,
  });

  final String capabilityId;
  final CapabilityGapReason reason;
  final String detail;
  final String resolution;

  /// If upstream-blocked, the name of the required contract.
  final String? upstreamContract;

  String get blockedMessage {
    final buffer = StringBuffer('`$capabilityId` is unavailable');
    switch (reason) {
      case CapabilityGapReason.upstreamBlocked:
        buffer.write(': blocked on upstream ');
        buffer.write(upstreamContract ?? 'contract');
        break;
      case CapabilityGapReason.implementationNeeded:
        buffer.write(': implementation pending');
        break;
      case CapabilityGapReason.providerError:
        buffer.write(': provider error');
        break;
      case CapabilityGapReason.indexUnavailable:
        buffer.write(': index unavailable');
        break;
      case CapabilityGapReason.timeout:
        buffer.write(': timed out');
        break;
      case CapabilityGapReason.cancelled:
        buffer.write(': cancelled by newer revision');
        break;
      case CapabilityGapReason.platformUnsupported:
        buffer.write(': not supported on this platform');
        break;
      case CapabilityGapReason.toolchainMissing:
        buffer.write(': toolchain not installed');
        break;
      case CapabilityGapReason.policyDisabled:
        buffer.write(': disabled by policy');
        break;
      case CapabilityGapReason.unknown:
        buffer.write(': reason unknown');
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
        'resolution': resolution,
        'upstreamContract': upstreamContract,
        'blockedMessage': blockedMessage,
      };
}

/// Snapshot of all language capability gaps for a document or workspace.
class LanguageCapabilityGapSnapshot {
  const LanguageCapabilityGapSnapshot({
    this.gaps = const <LanguageCapabilityGap>[],
    this.generatedAtIso8601 = '',
  });

  final List<LanguageCapabilityGap> gaps;
  final String generatedAtIso8601;

  bool get hasGaps => gaps.isNotEmpty;

  /// Gaps that are upstream-blocked (need Styio/Pafio contract).
  List<LanguageCapabilityGap> get upstreamBlocked => gaps
      .where((g) => g.reason == CapabilityGapReason.upstreamBlocked)
      .toList(growable: false);

  /// Gaps that Vityo can close itself.
  List<LanguageCapabilityGap> get vityoActionable => gaps
      .where((g) =>
          g.reason == CapabilityGapReason.implementationNeeded ||
          g.reason == CapabilityGapReason.providerError)
      .toList(growable: false);

  /// Check if a specific capability is blocked.
  bool isBlocked(String capabilityId) =>
      gaps.any((g) => g.capabilityId == capabilityId);

  /// Get the blocked reason for a specific capability, or null if available.
  LanguageCapabilityGap? gapFor(String capabilityId) {
    for (final gap in gaps) {
      if (gap.capabilityId == capabilityId) {
        return gap;
      }
    }
    return null;
  }

  /// Human-readable summary of all blocked capabilities.
  String get summary {
    if (gaps.isEmpty) return 'All language capabilities available.';
    return gaps.map((g) => g.blockedMessage).join('\n');
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'gaps': gaps.map((g) => g.toJson()).toList(growable: false),
        'generatedAtIso8601': generatedAtIso8601,
        'hasGaps': hasGaps,
      };
}

// ── Code Action Application Result ────────────────────────────────

/// Result of applying a code action / quick fix.
enum CodeActionApplicationStatus {
  applied,
  previewedOnly,
  rejectedStaleDiagnostic,
  rejectedCapabilityGap,
  rejectedInvalidRange,
  failed,
}

class CodeActionApplicationResult {
  const CodeActionApplicationResult({
    required this.status,
    required this.actionLabel,
    this.appliedEditCount = 0,
    this.transactionId = '',
    this.errorMessage = '',
    this.blockedReason = '',
  });

  final CodeActionApplicationStatus status;
  final String actionLabel;
  final int appliedEditCount;
  final String transactionId;
  final String errorMessage;
  final String blockedReason;

  bool get isApplied =>
      status == CodeActionApplicationStatus.applied;
  bool get isPreviewed =>
      status == CodeActionApplicationStatus.previewedOnly;
  bool get isBlocked =>
      status == CodeActionApplicationStatus.rejectedStaleDiagnostic ||
      status == CodeActionApplicationStatus.rejectedCapabilityGap;

  Map<String, Object?> toJson() => <String, Object?>{
        'status': status.name,
        'actionLabel': actionLabel,
        'appliedEditCount': appliedEditCount,
        'transactionId': transactionId,
        'errorMessage': errorMessage,
        'blockedReason': blockedReason,
      };
}
