import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../ide/editor/editor.dart';
import '../../language/service/service.dart';
import '../../runtime/runtime.dart';

/// Owns the StyioService document subscription and daemon restart lifecycle.
final class LanguageController extends ChangeNotifier {
  LanguageController({
    required this.subscriptionController,
    required this.processSupervisor,
    required this.refreshLanguageService,
    required this.activeDocument,
    required this.activeDocumentPath,
    required this.workspaceRoot,
    required this.log,
    required this.recordSemanticRuntimeEvent,
  }) {
    _eventSubscription = subscriptionController?.events.listen(_handleEvent);
  }

  final StyioServiceSubscriptionController? subscriptionController;
  final StyioServiceDaemonProcessSupervisor? processSupervisor;
  final Future<void> Function()? refreshLanguageService;
  final DocumentState Function() activeDocument;
  final String Function() activeDocumentPath;
  final String Function() workspaceRoot;
  final void Function(String message) log;
  final Future<void> Function(RuntimeOutputEvent event)
  recordSemanticRuntimeEvent;

  StreamController<DocumentState>? _documents;
  StreamSubscription<StyioServiceSubscriptionEvent>? _eventSubscription;
  StyioServiceDaemonRestartDispatchResult? _lastDaemonRestartDispatch;

  bool get subscriptionAvailable => subscriptionController != null;
  bool get subscriptionListening => subscriptionController?.listening ?? false;
  bool get refreshAvailable => refreshLanguageService != null;
  StyioServiceDaemonRestartDispatchResult? get lastDaemonRestartDispatch =>
      _lastDaemonRestartDispatch;

  Future<void> refresh() async {
    await refreshLanguageService?.call();
  }

  Future<void> startDocumentSubscription() async {
    final controller = subscriptionController;
    if (controller == null) {
      log(
        'StyioService document subscription unavailable: no controller is wired.',
      );
      return;
    }
    await _documents?.close();
    final documents = StreamController<DocumentState>.broadcast(sync: true);
    _documents = documents;
    controller.bindDocumentStream(
      documents.stream,
      filePathForDocument: _documentPath,
      workingDirectoryForDocument: (_) => workspaceRoot(),
    );
    documents.add(activeDocument());
    log('StyioService document subscription started from shell.');
    notifyListeners();
  }

  Future<StyioServiceSubscriptionEvent?> refreshSubscriptionNow() {
    final controller = subscriptionController;
    if (controller == null) {
      log(
        'StyioService document subscription refresh unavailable: no controller is wired.',
      );
      return Future<StyioServiceSubscriptionEvent?>.value();
    }
    final document = activeDocument();
    return controller.refresh(
      document,
      filePath: _documentPath(document),
      workingDirectory: workspaceRoot(),
    );
  }

  Future<StyioServiceSubscriptionEvent?> cancelDocumentSubscription() async {
    final controller = subscriptionController;
    if (controller == null) {
      log(
        'StyioService document subscription cancel unavailable: no controller is wired.',
      );
      return null;
    }
    await _documents?.close();
    _documents = null;
    final event = await controller.cancel(
      message: 'StyioService document subscription cancelled from shell.',
    );
    notifyListeners();
    return event;
  }

  Future<StyioServiceDaemonRestartDispatchResult?> dispatchDaemonRestart({
    int failedAttempt = 0,
    StyioServiceDaemonRestartReason reason =
        StyioServiceDaemonRestartReason.manual,
    StyioServiceDaemonRestartPolicy policy =
        const StyioServiceDaemonRestartPolicy(),
    StyioServiceDaemonRestartHandler? restart,
    StyioServiceDaemonProcessSupervisor? processSupervisor,
  }) async {
    final controller = subscriptionController;
    if (controller == null) {
      log('StyioService daemon restart unavailable: no controller is wired.');
      return null;
    }
    final effectiveSupervisor = processSupervisor ?? this.processSupervisor;
    final supervisorControls = effectiveSupervisor == null
        ? null
        : StyioServiceDaemonSupervisorControls(
            controller: controller,
            processSupervisor: effectiveSupervisor,
          );
    final restartHandler =
        restart ??
        supervisorControls?.restartHandler ??
        (refreshLanguageService == null ? null : _restartFromRefresh);
    final result = await controller.dispatchDaemonRestart(
      failedAttempt: failedAttempt,
      reason: reason,
      policy: policy,
      restart: restartHandler,
    );
    _lastDaemonRestartDispatch = result;
    log(result.message);
    notifyListeners();
    return result;
  }

  void publishDocument(DocumentState document) {
    final documents = _documents;
    if (documents != null && !documents.isClosed) {
      documents.add(document);
    }
  }

  Future<StyioServiceDaemonLifecycleSnapshot> _restartFromRefresh(
    StyioServiceDaemonRestartPlan plan,
  ) async {
    final refresh = refreshLanguageService;
    if (refresh == null) {
      return StyioServiceDaemonLifecycleSnapshot(
        state: plan.lifecycle.state,
        providerId: plan.providerId,
        message:
            'StyioService daemon restart skipped: no language service refresh callback is configured.',
      );
    }
    await refresh();
    return StyioServiceDaemonLifecycleSnapshot(
      state: StyioServiceDaemonLifecycleState.active,
      providerId: plan.providerId,
      message:
          'StyioService daemon restart dispatched through the language service refresh callback.',
    );
  }

  String? _documentPath(DocumentState document) {
    final documentId = document.documentId.trim();
    if (documentId.isNotEmpty) {
      return documentId;
    }
    final path = activeDocumentPath().trim();
    return path.isEmpty ? null : path;
  }

  void _handleEvent(StyioServiceSubscriptionEvent event) {
    log(event.message);
    for (final runtimeEvent in event.semanticPanelEvents()) {
      unawaited(recordSemanticRuntimeEvent(runtimeEvent));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    unawaited(_documents?.close());
    _documents = null;
    super.dispose();
  }
}
