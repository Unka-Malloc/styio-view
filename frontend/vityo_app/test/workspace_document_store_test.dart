import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vityo_app/src/app/state/workspace_document_store.dart';
import 'package:vityo_app/src/editor/document_state.dart';

void main() {
  test('shared preferences store persists saved documents', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesWorkspaceDocumentStore(preferences);

    const document = DocumentState(
      documentId: 'main.styio',
      text: 'fn main() {\n  emit 42\n}\n',
      revision: 3,
    );

    await store.saveDocument(document);
    final loaded = await store.loadDocument(document.documentId);

    expect(loaded.text, document.text);
    expect(loaded.revision, document.revision);
  });
}
