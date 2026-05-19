import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/app/state/workspace_document_store_io.dart';
import 'package:vityo_app/src/editor/document_state.dart';

void main() {
  test('filesystem store persists source and revision sidecar', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_store_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    final store = FileSystemWorkspaceDocumentStore(tempRoot);
    const document = DocumentState(
      documentId: 'cloud/main.styio',
      text: 'fn main() {\n  emit session\n}\n',
      revision: 7,
    );

    await store.saveDocument(document);
    final loaded = await store.loadDocument(document.documentId);

    expect(loaded.text, document.text);
    expect(loaded.revision, document.revision);
    expect(
      File(
        '${tempRoot.path}${Platform.pathSeparator}cloud${Platform.pathSeparator}main.styio',
      ).existsSync(),
      isTrue,
    );
    expect(
      store.filePathForDocumentId(document.documentId),
      '${tempRoot.path}${Platform.pathSeparator}cloud${Platform.pathSeparator}main.styio',
    );
  });

  test(
    'filesystem store reads and writes absolute project files directly',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_store_abs_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final absoluteFile = File(
        '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
      )..createSync(recursive: true);
      absoluteFile.writeAsStringSync('fn main() {\n  emit seed\n}\n');

      final store = FileSystemWorkspaceDocumentStore(tempRoot);

      final loaded = await store.loadDocument(absoluteFile.path);
      expect(loaded.text, 'fn main() {\n  emit seed\n}\n');

      final updated = DocumentState(
        documentId: loaded.documentId,
        text: 'fn main() {\n  emit updated\n}\n',
        revision: 3,
      );

      await store.saveDocument(updated);

      expect(absoluteFile.readAsStringSync(), updated.text);
      expect(store.filePathForDocumentId(absoluteFile.path), absoluteFile.path);
    },
  );

  test('filesystem store rejects escaping relative document ids', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_store_escape_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    final store = FileSystemWorkspaceDocumentStore(tempRoot);

    expect(
      () => store.filePathForDocumentId('../secret.styio'),
      throwsArgumentError,
    );
    await expectLater(
      store.loadDocument('..\\secret.styio'),
      throwsArgumentError,
    );
    await expectLater(
      store.saveDocument(
        const DocumentState(
          documentId: '../secret.styio',
          text: 'secret\n',
          revision: 1,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('filesystem store watches document text and revision changes', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_store_watch_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    final store = FileSystemWorkspaceDocumentStore(tempRoot);
    const initial = DocumentState(
      documentId: 'watched/main.styio',
      text: 'value := 1\n',
      revision: 1,
    );
    final updated = initial.replaceRange(
      start: initial.text.indexOf('1'),
      end: initial.text.indexOf('1') + 1,
      replacement: '2',
    );

    await store.saveDocument(initial);
    final observed = store
        .watchDocument(initial.documentId)
        .firstWhere(
          (document) =>
              document.text == updated.text &&
              document.revision == updated.revision,
        )
        .timeout(const Duration(seconds: 3));

    await Future<void>.delayed(const Duration(milliseconds: 50));
    await store.saveDocument(updated);

    final watched = await observed;

    expect(watched.documentId, updated.documentId);
    expect(watched.text, updated.text);
    expect(watched.revision, updated.revision);
  });
}
