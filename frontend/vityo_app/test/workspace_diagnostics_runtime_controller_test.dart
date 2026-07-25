import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/workspace_diagnostics_runtime_controller.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('refresh fails closed when no diagnostics provider is wired', () async {
    final logs = <String>[];
    final controller = WorkspaceDiagnosticsRuntimeController(
      controller: null,
      activeDocument: () => _document('src/main.styio'),
      workspaceDocuments: () => <DocumentState>[],
      openFilePaths: () => <String>['src/main.styio'],
      log: logs.add,
    );
    addTearDown(controller.dispose);

    final snapshot = await controller.refresh();

    expect(controller.available, isFalse);
    expect(snapshot.providerId, 'unavailable');
    expect(snapshot.diagnostics, isEmpty);
    expect(snapshot.message, contains('no provider is configured'));
    expect(logs.single, snapshot.message);
  });

  test('refresh sends authoritative open and cached document facts', () async {
    final provider = _CapturingDiagnosticsProvider();
    final diagnostics = WorkspaceDiagnosticsController(provider: provider);
    addTearDown(diagnostics.dispose);
    final active = _document('src/main.styio');
    final cached = _document('src/helper.styio');
    final controller = WorkspaceDiagnosticsRuntimeController(
      controller: diagnostics,
      activeDocument: () => active,
      workspaceDocuments: () => <DocumentState>[active, cached],
      openFilePaths: () => <String>[active.documentId, cached.documentId],
      log: (_) {},
    );
    addTearDown(controller.dispose);

    final snapshot = await controller.refresh();
    final request = provider.lastRequest;

    expect(controller.available, isTrue);
    expect(snapshot.providerId, provider.providerId);
    expect(controller.snapshot, same(snapshot));
    expect(request?.activeDocumentId, active.documentId);
    expect(request?.documentIds, <String>[
      active.documentId,
      cached.documentId,
    ]);
    expect(request?.documents.map((document) => document.documentId), <String>[
      active.documentId,
      cached.documentId,
    ]);
  });
}

DocumentState _document(String path) =>
    DocumentState(documentId: path, text: '$path\n', revision: 1);

final class _CapturingDiagnosticsProvider
    implements WorkspaceDiagnosticsProvider {
  @override
  String get providerId => 'capturing';

  WorkspaceDiagnosticsRequest? lastRequest;

  @override
  Future<WorkspaceDiagnosticsSnapshot> collect(
    WorkspaceDiagnosticsRequest request,
  ) async {
    lastRequest = request;
    return const WorkspaceDiagnosticsSnapshot(
      providerId: 'capturing',
      diagnostics: <WorkspaceDiagnostic>[],
    );
  }
}
