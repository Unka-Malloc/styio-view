import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test(
    'Styio workspace diagnostics provider collects project diagnostics',
    () async {
      final source = File(
        'test/fixtures/workspace_diagnostics/duplicate_import.true.styio',
      ).readAsStringSync();
      const provider = StyioWorkspaceDiagnosticsProvider();

      final snapshot = await provider.collect(
        WorkspaceDiagnosticsRequest(
          documentIds: const <String>['main.styio'],
          activeDocumentId: 'main.styio',
          documents: <DocumentState>[
            DocumentState(documentId: 'main.styio', text: source, revision: 1),
          ],
        ),
      );

      expect(snapshot.providerId, 'styio-language');
      expect(snapshot.totalCount, greaterThan(0));
      expect(
        snapshot.diagnostics.map((entry) => entry.documentId),
        contains('main.styio'),
      );
      expect(
        snapshot.diagnostics.map((entry) => entry.diagnostic.code),
        contains('duplicate-import'),
      );
      expect(snapshot.message, contains('problem'));
    },
  );

  test('Styio workspace diagnostics provider reports empty request', () async {
    final snapshot = await const StyioWorkspaceDiagnosticsProvider().collect(
      const WorkspaceDiagnosticsRequest(documentIds: <String>[]),
    );

    expect(snapshot.totalCount, 0);
    expect(snapshot.message, contains('No documents'));
  });

  test(
    'Styio workspace diagnostics provider attaches quick fix stream facts',
    () async {
      const provider = StyioWorkspaceDiagnosticsProvider();

      final snapshot = await provider.collect(
        const WorkspaceDiagnosticsRequest(
          documentIds: <String>['broken.styio'],
          activeDocumentId: 'broken.styio',
          documents: <DocumentState>[
            DocumentState(
              documentId: 'broken.styio',
              text: '#main := () => {\n  value := 1\n',
              revision: 1,
            ),
          ],
        ),
      );
      final diagnostic = snapshot.diagnostics.singleWhere(
        (entry) => entry.diagnostic.code == 'local.unclosed-delimiter',
      );

      expect(diagnostic.hasQuickFixes, isTrue);
      expect(diagnostic.quickFixes.single.label, startsWith('Insert matching'));
      expect(
        snapshot.streamSnapshot.quickFixReadyCount,
        greaterThanOrEqualTo(1),
      );
      expect(
        snapshot.streamSnapshot.sourceKindCounts['styio-project'],
        snapshot.totalCount,
      );
    },
  );
}
