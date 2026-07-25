import 'package:flutter/foundation.dart';

import '../../editor/editor.dart';
import '../../runtime/runtime.dart';
import '../../workspace/workspace.dart';

/// Owns workspace-diagnostics availability, requests, and producer control.
final class WorkspaceDiagnosticsRuntimeController extends ChangeNotifier {
  WorkspaceDiagnosticsRuntimeController({
    required this.controller,
    required this.activeDocument,
    required this.workspaceDocuments,
    required this.openFilePaths,
    required this.log,
  });

  final WorkspaceDiagnosticsController? controller;
  final DocumentState Function() activeDocument;
  final List<DocumentState> Function() workspaceDocuments;
  final List<String> Function() openFilePaths;
  final void Function(String message) log;

  bool get available => controller != null;
  WorkspaceDiagnosticsSnapshot? get snapshot => controller?.snapshot;
  List<WorkspaceDiagnosticsProducerLifecycleSnapshot> get producerLifecycles =>
      controller?.diagnosticsProducerLifecycles ??
      const <WorkspaceDiagnosticsProducerLifecycleSnapshot>[];

  Future<WorkspaceDiagnosticsProducerLifecycleSnapshot?> cancelProducer(
    WorkspaceDiagnosticsProducerLifecycleSnapshot snapshot,
  ) async {
    final diagnosticsController = controller;
    if (diagnosticsController == null) {
      log(
        'Workspace diagnostics producer cancel unavailable: no controller is wired.',
      );
      return null;
    }
    final result = await diagnosticsController.cancelDiagnosticsProducer(
      snapshot,
    );
    if (result == null) {
      log(
        'Workspace diagnostics producer ${snapshot.providerId} cancel unavailable: no lifecycle plan is registered.',
      );
      return null;
    }
    log(
      'Workspace diagnostics producer ${snapshot.providerId} cancel ${result.status.wireValue}: ${result.message}',
    );
    notifyListeners();
    return result;
  }

  Future<WorkspaceDiagnosticsSnapshot> refresh() async {
    final diagnosticsController = controller;
    final result = diagnosticsController == null
        ? const WorkspaceDiagnosticsSnapshot(
            providerId: 'unavailable',
            diagnostics: <WorkspaceDiagnostic>[],
            message:
                'Workspace diagnostics refresh skipped: no provider is configured.',
          )
        : await diagnosticsController.refresh(_createRequest());
    log(refreshMessage(result));
    notifyListeners();
    return result;
  }

  String refreshMessage(WorkspaceDiagnosticsSnapshot snapshot) {
    if (snapshot.message.isNotEmpty && snapshot.providerId == 'unavailable') {
      return snapshot.message;
    }
    return 'Workspace diagnostics refreshed: ${snapshot.totalCount} problem(s).';
  }

  WorkspaceDiagnosticsRequest _createRequest() {
    final active = activeDocument();
    final documentsById = <String, DocumentState>{
      active.documentId: active,
      for (final document in workspaceDocuments())
        document.documentId: document,
    };
    final documentIds = <String>{
      ...openFilePaths(),
      active.documentId,
    }.toList(growable: false);
    return WorkspaceDiagnosticsRequest(
      documentIds: documentIds,
      activeDocumentId: active.documentId,
      documents: documentsById.values.toList(growable: false),
    );
  }
}
