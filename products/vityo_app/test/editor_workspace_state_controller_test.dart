import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/interaction/document_resource_binding.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/editor_workspace_state_controller.dart';

void main() {
  test('document cache evicts oldest unprotected document', () {
    final controller = EditorWorkspaceStateController(documentCacheLimit: 2);

    controller.cacheDocument(
      'a',
      _document('a'),
      activeDocumentPath: 'a',
      openFilePaths: const <String>[],
    );
    controller.markDirty('a');
    controller.cacheDocument(
      'b',
      _document('b'),
      activeDocumentPath: 'b',
      openFilePaths: const <String>[],
    );
    controller.cacheDocument(
      'c',
      _document('c'),
      activeDocumentPath: 'c',
      openFilePaths: const <String>[],
    );

    expect(controller.cachedDocumentPaths, <String>['a', 'c']);
    expect(controller.document('b'), isNull);
    expect(controller.isDirty('a'), isTrue);
  });

  test('binding snapshots own dirty-state transitions', () {
    final controller = EditorWorkspaceStateController(documentCacheLimit: 2);

    controller.syncDirtyState(
      'main.styio',
      const DocumentResourceBindingSnapshot(
        state: DocumentResourceBindingState.boundDirty,
      ),
    );
    expect(controller.isDirty('main.styio'), isTrue);

    controller.syncDirtyState(
      'main.styio',
      const DocumentResourceBindingSnapshot(
        state: DocumentResourceBindingState.boundClean,
      ),
    );
    expect(controller.isDirty('main.styio'), isFalse);
  });
}

DocumentState _document(String id) =>
    DocumentState(documentId: id, text: '$id\n', revision: 1);
