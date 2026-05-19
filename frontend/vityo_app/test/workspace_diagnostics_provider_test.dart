import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace diagnostics snapshot groups and counts diagnostics', () {
    const snapshot = WorkspaceDiagnosticsSnapshot(
      providerId: 'language',
      diagnostics: <WorkspaceDiagnostic>[
        WorkspaceDiagnostic(
          documentId: 'main.styio',
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'syntax-error',
            message: 'Unexpected token.',
            range: SourceRange(start: 0, end: 1),
          ),
        ),
        WorkspaceDiagnostic(
          documentId: 'lib/math.styio',
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'unused-binding',
            message: 'Binding is unused.',
            range: SourceRange(start: 3, end: 8),
          ),
        ),
      ],
    );

    final json = snapshot.toJson();

    expect(snapshot.totalCount, 2);
    expect(snapshot.hasErrors, isTrue);
    expect(snapshot.documentIds, <String>['lib/math.styio', 'main.styio']);
    expect(snapshot.severityCounts['error'], 1);
    expect(snapshot.severityCounts['warning'], 1);
    expect(snapshot.diagnosticsFor('main.styio'), hasLength(1));
    expect(json['diagnostics'], isNotEmpty);
  });

  test('workspace diagnostics provider registry resolves active provider', () {
    final snapshot = const WorkspaceDiagnosticsSnapshot(
      providerId: 'high',
      diagnostics: <WorkspaceDiagnostic>[],
    );
    final registry = WorkspaceDiagnosticsProviderRegistry()
      ..register(
        WorkspaceDiagnosticsProviderRegistration(
          id: 'low',
          provider: StaticWorkspaceDiagnosticsProvider(
            providerId: 'low',
            snapshot: snapshot,
          ),
          priority: 1,
          state: FoundationRegistryEntryState.active,
        ),
      )
      ..register(
        WorkspaceDiagnosticsProviderRegistration(
          id: 'high',
          provider: StaticWorkspaceDiagnosticsProvider(
            providerId: 'high',
            snapshot: snapshot,
          ),
          priority: 10,
          state: FoundationRegistryEntryState.active,
          metadata: const <String, Object?>{'source': 'styio-service'},
        ),
      );

    final resolved = registry.resolve();
    final manifest = registry.manifest().toJson();
    final entries = manifest['entries']! as List<Object?>;

    expect(resolved?.id, 'high');
    expect(registry.provider(), same(resolved?.value));
    expect(entries, hasLength(2));
    expect(
      ((entries.first! as Map<String, Object?>)['metadata']!
          as Map<String, Object?>)['providerContract'],
      'workspace-diagnostics-provider',
    );
  });

  test(
    'static workspace diagnostics provider returns configured snapshot',
    () async {
      const snapshot = WorkspaceDiagnosticsSnapshot(
        providerId: 'static',
        diagnostics: <WorkspaceDiagnostic>[
          WorkspaceDiagnostic(
            documentId: 'main.styio',
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.hint,
              code: 'style',
              message: 'Prefer explicit name.',
              range: SourceRange(start: 0, end: 1),
            ),
          ),
        ],
      );
      const provider = StaticWorkspaceDiagnosticsProvider(
        providerId: 'static',
        snapshot: snapshot,
      );

      final result = await provider.collect(
        const WorkspaceDiagnosticsRequest(
          documentIds: <String>['main.styio'],
          activeDocumentId: 'main.styio',
        ),
      );

      expect(result.providerId, 'static');
      expect(result.totalCount, 1);
      expect(result.diagnostics.single.diagnostic.code, 'style');
    },
  );
}
