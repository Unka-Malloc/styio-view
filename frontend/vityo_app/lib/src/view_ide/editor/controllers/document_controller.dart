import '../document/document_state.dart';
import 'editor_owned_controller.dart';

class DocumentController extends EditorOwnedController {
  DocumentController(DocumentState initialDocument)
    : _document = initialDocument;

  DocumentState _document;

  DocumentState get document => _document;

  void loadDocument(DocumentState document) {
    ensureNotDisposed();
    _document = document;
    notifyControllerListeners();
  }

  void replaceDocument(DocumentState document) {
    loadDocument(document);
  }

  void replaceRange({
    required int start,
    required int end,
    required String replacement,
  }) {
    ensureNotDisposed();
    _document = _document.replaceRange(
      start: start,
      end: end,
      replacement: replacement,
    );
    notifyControllerListeners();
  }

  static DocumentState seedDocumentForPath(String path) {
    final samples = <String, String>{
      'main.styio': '''
fn main() {
  let stream = source |> normalize -> sink
  emit stream
}
''',
      'render_flow.styio': '''
pipeline renderFlow

let commitFlow = source |> normalize |> shade -> commit

fn commitFrame(frame) {
  state paint_ready
  when frame.ready -> state submitted
  emit frame.commit
}
''',
      'runtime_graph.styio': '''
fn bootRuntime() {
  spawn worker_a
  spawn worker_b
  sync worker_a -> worker_b
}
''',
      'cloud/main.styio': '''
fn main() {
  let session = remote_source |> hydrate -> cloud_sink
  emit session
}
''',
      'cloud/runtime_surface.styio': '''
fn inspectCloudSession() {
  state awaiting_container
  when container.ready -> state connected
}
''',
    };

    final normalizedPath = path.replaceAll('\\', '/');
    final basename = normalizedPath.split('/').last;
    final cloudPath = normalizedPath.contains('/cloud/');
    final lookupOrder = <String>[
      normalizedPath,
      if (cloudPath) 'cloud/$basename',
      basename,
    ];

    String? sample;
    for (final candidate in lookupOrder) {
      sample = samples[candidate];
      if (sample != null) {
        break;
      }
    }

    return DocumentState(
      documentId: path,
      text: sample ?? '// empty document\n',
      revision: 0,
    );
  }
}
