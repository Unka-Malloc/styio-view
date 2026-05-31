import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace rename previews and applies edits across project files', () async {
    const runtimeText = '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''';
    const mainText = '''
@import { lib/runtime }
value = blend(1.0, 2.0)
''';
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/runtime.styio': DocumentState(
          documentId: 'lib/runtime.styio',
          text: runtimeText,
          revision: 0,
        ),
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: mainText,
          revision: 0,
        ),
        'README.md': DocumentState(
          documentId: 'README.md',
          text: 'blend should not be renamed\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceRenameService(documentStore: store);
    final query = WorkspaceRenameQuery(
      targetFilePath: 'main.styio',
      targetOffset: mainText.indexOf('blend'),
      newName: 'mix',
    );

    final preview = await service.previewRename(
      filePaths: const <String>[
        'main.styio',
        'lib/runtime.styio',
        'README.md',
      ],
      query: query,
    );

    expect(preview.status, WorkspaceRenameStatus.ready);
    expect(preview.canApply, isTrue);
    expect(preview.filesSearched, 2);
    expect(preview.oldName, 'blend');
    expect(preview.newName, 'mix');
    expect(preview.editCount, 2);
    expect(preview.matchedFileCount, 2);
    expect(
      preview.edits.map((edit) => edit.filePath),
      isNot(contains('README.md')),
    );

    final apply = await service.applyRename(
      filePaths: const <String>['main.styio', 'lib/runtime.styio', 'README.md'],
      query: query,
    );

    expect(apply.applied, isTrue);
    expect(apply.documentsChanged, 2);
    expect(apply.editsApplied, 2);
    expect(
      (await store.loadDocument('lib/runtime.styio')).text,
      contains('fn mix'),
    );
    expect((await store.loadDocument('main.styio')).text, contains('mix(1.0'));
    expect(
      (await store.loadDocument('README.md')).text,
      contains('blend should not be renamed'),
    );
  });

  test('workspace rename reports invalid names and visible conflicts', () async {
    const runtimeText = '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}

fn mix(left: f64, right: f64): f64 {
  emit left + right
}
''';
    const mainText = '''
@import { lib/runtime }
value = blend(1.0, 2.0)
''';
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/runtime.styio': DocumentState(
          documentId: 'lib/runtime.styio',
          text: runtimeText,
          revision: 0,
        ),
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: mainText,
          revision: 0,
        ),
      },
    );
    final service = WorkspaceRenameService(documentStore: store);

    final invalid = await service.previewRename(
      filePaths: const <String>['main.styio', 'lib/runtime.styio'],
      query: WorkspaceRenameQuery(
        targetFilePath: 'main.styio',
        targetOffset: mainText.indexOf('blend'),
        newName: '1bad',
      ),
    );
    final conflict = await service.previewRename(
      filePaths: const <String>['main.styio', 'lib/runtime.styio'],
      query: WorkspaceRenameQuery(
        targetFilePath: 'main.styio',
        targetOffset: mainText.indexOf('blend'),
        newName: 'mix',
      ),
    );

    expect(invalid.status, WorkspaceRenameStatus.conflict);
    expect(invalid.canApply, isFalse);
    expect(invalid.message, contains('not a valid'));
    expect(conflict.status, WorkspaceRenameStatus.conflict);
    expect(conflict.message, contains('conflicts'));
  });

  test('workspace rename uses unsaved overlay documents', () async {
    const savedText = '''
fn saved(left: f64, right: f64): f64 {
  emit left + right
}
''';
    const unsavedText = '''
fn unsaved(left: f64, right: f64): f64 {
  emit left + right
}
value = unsaved(1.0, 2.0)
''';
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: savedText,
          revision: 0,
        ),
      },
    );
    final service = WorkspaceRenameService(documentStore: store);

    final preview = await service.previewRename(
      filePaths: const <String>['main.styio'],
      overlayDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: unsavedText,
          revision: 1,
        ),
      },
      query: WorkspaceRenameQuery(
        targetFilePath: 'main.styio',
        targetOffset: unsavedText.indexOf('unsaved('),
        newName: 'live',
      ),
    );

    expect(preview.status, WorkspaceRenameStatus.ready);
    expect(preview.oldName, 'unsaved');
    expect(preview.editCount, 2);
  });
}
