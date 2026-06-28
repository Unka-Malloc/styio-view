import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/diagnostic_revision_gate.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';

void main() {
  group('RevisionBoundDiagnostic', () {
    test('isStaleForRevision returns true when revision differs', () {
      final diag = const RevisionBoundDiagnostic(
        diagnostic: Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'E001',
          message: 'test error',
          range: SourceRange(start: 0, end: 5),
        ),
        documentId: 'test.styio',
        revision: 3,
        source: DiagnosticSource.compiler,
        confidence: DiagnosticConfidence.authoritative,
      );

      expect(diag.isStaleForRevision(3), isFalse);
      expect(diag.isStaleForRevision(4), isTrue);
      expect(diag.isStaleForRevision(2), isTrue);
    });

    test('serializes and deserializes', () {
      final original = const RevisionBoundDiagnostic(
        diagnostic: Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'W001',
          message: 'unused variable',
          range: SourceRange(start: 10, end: 15),
        ),
        documentId: 'lib.styio',
        revision: 5,
        source: DiagnosticSource.styioService,
        confidence: DiagnosticConfidence.high,
      );

      final json = original.toJson();
      final restored = RevisionBoundDiagnostic.fromJson(json);

      expect(restored.documentId, 'lib.styio');
      expect(restored.revision, 5);
      expect(restored.source, DiagnosticSource.styioService);
      expect(restored.diagnostic.severity, DiagnosticSeverity.warning);
      expect(restored.diagnostic.code, 'W001');
      expect(restored.diagnostic.range.start, 10);
      expect(restored.diagnostic.range.end, 15);
    });
  });

  group('DiagnosticRevisionGate', () {
    test('filters stale diagnostics', () {
      const gate = DiagnosticRevisionGate();
      final diagnostics = [
        const RevisionBoundDiagnostic(
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'E001',
            message: 'current',
            range: SourceRange(start: 0, end: 1),
          ),
          documentId: 'a.styio',
          revision: 5,
          source: DiagnosticSource.compiler,
        ),
        const RevisionBoundDiagnostic(
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'E002',
            message: 'stale',
            range: SourceRange(start: 0, end: 1),
          ),
          documentId: 'a.styio',
          revision: 3,
          source: DiagnosticSource.compiler,
        ),
        const RevisionBoundDiagnostic(
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'W001',
            message: 'current',
            range: SourceRange(start: 0, end: 1),
          ),
          documentId: 'b.styio',
          revision: 5,
          source: DiagnosticSource.localHeuristic,
          confidence: DiagnosticConfidence.medium,
        ),
      ];

      final current = gate.filterCurrent(diagnostics, 5);
      expect(current.length, 2);
      expect(current.any((d) => d.diagnostic.message == 'stale'), isFalse);

      final stale = gate.staleDiagnostics(diagnostics, 5);
      expect(stale.length, 1);
      expect(stale.first.diagnostic.message, 'stale');

      // When revision changes, previously current diagnostics become stale
      final afterEdit = gate.filterCurrent(diagnostics, 6);
      expect(afterEdit.length, 0);
    });
  });

  group('LanguageCapabilityGap', () {
    test('blockedMessage is descriptive for each reason', () {
      final upstreamBlocked = const LanguageCapabilityGap(
        capabilityId: 'language.rename',
        reason: CapabilityGapReason.upstreamBlocked,
        upstreamContract: 'LanguageServiceAdapter.renamePlan',
      );
      expect(
        upstreamBlocked.blockedMessage,
        contains('blocked on upstream'),
      );
      expect(upstreamBlocked.blockedMessage, contains('LanguageServiceAdapter'));

      final implNeeded = const LanguageCapabilityGap(
        capabilityId: 'language.inlayHints',
        reason: CapabilityGapReason.implementationNeeded,
        detail: 'Rendering code not yet written',
      );
      expect(implNeeded.blockedMessage, contains('implementation pending'));

      final platformUnsupported = const LanguageCapabilityGap(
        capabilityId: 'execution.local',
        reason: CapabilityGapReason.platformUnsupported,
        detail: 'iOS does not support local compilation',
      );
      expect(
        platformUnsupported.blockedMessage,
        contains('not supported on this platform'),
      );
    });

    test('serializes with blocked message', () {
      final gap = const LanguageCapabilityGap(
        capabilityId: 'language.formatting',
        reason: CapabilityGapReason.upstreamBlocked,
        upstreamContract: 'LanguageServiceAdapter.formattingEdits',
        detail: 'StyioService does not yet expose formatting',
        resolution: 'Implement StyioService formatting endpoint',
      );

      final json = gap.toJson();
      expect(json['capabilityId'], 'language.formatting');
      expect(json['reason'], 'upstreamBlocked');
      expect(json['blockedMessage'], isNotEmpty);
    });
  });

  group('LanguageCapabilityGapSnapshot', () {
    test('isBlocked checks capability availability', () {
      final snapshot = const LanguageCapabilityGapSnapshot(
        gaps: [
          LanguageCapabilityGap(
            capabilityId: 'language.rename',
            reason: CapabilityGapReason.upstreamBlocked,
          ),
          LanguageCapabilityGap(
            capabilityId: 'language.codeActions',
            reason: CapabilityGapReason.upstreamBlocked,
          ),
        ],
      );

      expect(snapshot.isBlocked('language.rename'), isTrue);
      expect(snapshot.isBlocked('language.formatting'), isFalse);
      expect(snapshot.hasGaps, isTrue);
    });

    test('separates upstream-blocked from vityo-actionable', () {
      final snapshot = const LanguageCapabilityGapSnapshot(
        gaps: [
          LanguageCapabilityGap(
            capabilityId: 'language.rename',
            reason: CapabilityGapReason.upstreamBlocked,
          ),
          LanguageCapabilityGap(
            capabilityId: 'ui.themeEditor',
            reason: CapabilityGapReason.implementationNeeded,
          ),
          LanguageCapabilityGap(
            capabilityId: 'language.hover',
            reason: CapabilityGapReason.providerError,
          ),
        ],
      );

      expect(snapshot.upstreamBlocked.length, 1);
      expect(snapshot.vityoActionable.length, 2);
    });

    test('empty snapshot has no gaps', () {
      const snapshot = LanguageCapabilityGapSnapshot();
      expect(snapshot.hasGaps, isFalse);
      expect(snapshot.summary, contains('available'));
    });

    test('summary includes all blocked capabilities', () {
      final snapshot = const LanguageCapabilityGapSnapshot(
        gaps: [
          LanguageCapabilityGap(
            capabilityId: 'a',
            reason: CapabilityGapReason.upstreamBlocked,
          ),
          LanguageCapabilityGap(
            capabilityId: 'b',
            reason: CapabilityGapReason.implementationNeeded,
          ),
        ],
      );

      expect(snapshot.summary, contains('a'));
      expect(snapshot.summary, contains('b'));
    });
  });

  group('Diagnostic confidence', () {
    test('local heuristic diagnostics are marked with lower confidence', () {
      final diag = const RevisionBoundDiagnostic(
        diagnostic: Diagnostic(
          severity: DiagnosticSeverity.hint,
          code: 'H001',
          message: 'Possible improvement',
          range: SourceRange(start: 0, end: 1),
        ),
        documentId: 'test.styio',
        revision: 1,
        source: DiagnosticSource.localHeuristic,
        confidence: DiagnosticConfidence.medium,
      );

      expect(diag.confidence, DiagnosticConfidence.medium);
      expect(diag.source, isNot(DiagnosticSource.compiler));
      // Local heuristics must not claim compiler authority
      expect(diag.confidence, isNot(DiagnosticConfidence.authoritative));
    });

    test('compiler diagnostics have authoritative confidence', () {
      final diag = const RevisionBoundDiagnostic(
        diagnostic: Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'E001',
          message: 'Syntax error',
          range: SourceRange(start: 0, end: 1),
        ),
        documentId: 'test.styio',
        revision: 1,
        source: DiagnosticSource.compiler,
        confidence: DiagnosticConfidence.authoritative,
      );

      expect(diag.confidence, DiagnosticConfidence.authoritative);
    });
  });

  group('CodeActionApplicationResult', () {
    test('applied status reports success', () {
      const result = CodeActionApplicationResult(
        status: CodeActionApplicationStatus.applied,
        actionLabel: 'Fix missing assignment',
        appliedEditCount: 1,
        transactionId: 'txn-1',
      );
      expect(result.isApplied, isTrue);
      expect(result.isBlocked, isFalse);
    });

    test('rejected stale diagnostic status is blocked', () {
      const result = CodeActionApplicationResult(
        status: CodeActionApplicationStatus.rejectedStaleDiagnostic,
        actionLabel: 'Fix typo',
        blockedReason: 'Diagnostic is from revision 3, current is 5',
      );
      expect(result.isBlocked, isTrue);
      expect(result.isApplied, isFalse);
    });

    test('rejected capability gap status is blocked', () {
      const result = CodeActionApplicationResult(
        status: CodeActionApplicationStatus.rejectedCapabilityGap,
        actionLabel: 'Rename symbol',
        blockedReason: 'Capability language.rename is upstream-blocked',
      );
      expect(result.isBlocked, isTrue);
    });
  });

  group('Multiple diagnostics sort stability', () {
    test('same severity diagnostics sort consistently by file, line, column', () {
      final diagnostics = [
        const RevisionBoundDiagnostic(
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'E003',
            message: 'z-error',
            range: SourceRange(start: 100, end: 105),
          ),
          documentId: 'c.styio',
          revision: 1,
          source: DiagnosticSource.compiler,
        ),
        const RevisionBoundDiagnostic(
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'E001',
            message: 'a-error',
            range: SourceRange(start: 0, end: 5),
          ),
          documentId: 'a.styio',
          revision: 1,
          source: DiagnosticSource.compiler,
        ),
        const RevisionBoundDiagnostic(
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'E002',
            message: 'b-error',
            range: SourceRange(start: 50, end: 55),
          ),
          documentId: 'a.styio',
          revision: 1,
          source: DiagnosticSource.compiler,
        ),
        const RevisionBoundDiagnostic(
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'W001',
            message: 'warning',
            range: SourceRange(start: 0, end: 1),
          ),
          documentId: 'a.styio',
          revision: 1,
          source: DiagnosticSource.compiler,
        ),
      ];

      // Sort: error before warning, then by file, then by line
      final sorted = List<RevisionBoundDiagnostic>.from(diagnostics)
        ..sort((a, b) {
          final sevA = a.diagnostic.severity == DiagnosticSeverity.error ? 0 : 1;
          final sevB = b.diagnostic.severity == DiagnosticSeverity.error ? 0 : 1;
          final sevCompare = sevA.compareTo(sevB);
          if (sevCompare != 0) return sevCompare;
          final fileCompare = a.documentId.compareTo(b.documentId);
          if (fileCompare != 0) return fileCompare;
          return a.diagnostic.range.start.compareTo(b.diagnostic.range.start);
        });

      // Errors come first
      expect(sorted[0].diagnostic.severity, DiagnosticSeverity.error);
      expect(sorted[1].diagnostic.severity, DiagnosticSeverity.error);
      expect(sorted[2].diagnostic.severity, DiagnosticSeverity.error);
      expect(sorted[3].diagnostic.severity, DiagnosticSeverity.warning);

      // Within errors: file a.styio first, then by range
      expect(sorted[0].documentId, 'a.styio');
      expect(sorted[0].diagnostic.range.start, 0);
      expect(sorted[1].documentId, 'a.styio');
      expect(sorted[1].diagnostic.range.start, 50);
      expect(sorted[2].documentId, 'c.styio');

      // Sort is stable — run twice
      final sorted2 = List<RevisionBoundDiagnostic>.from(diagnostics)
        ..sort((a, b) {
          final sevA = a.diagnostic.severity == DiagnosticSeverity.error ? 0 : 1;
          final sevB = b.diagnostic.severity == DiagnosticSeverity.error ? 0 : 1;
          final sevCompare = sevA.compareTo(sevB);
          if (sevCompare != 0) return sevCompare;
          final fileCompare = a.documentId.compareTo(b.documentId);
          if (fileCompare != 0) return fileCompare;
          return a.diagnostic.range.start.compareTo(b.diagnostic.range.start);
        });

      for (var i = 0; i < sorted.length; i++) {
        expect(sorted2[i].diagnostic.code, sorted[i].diagnostic.code);
      }
    });
  });
}
