part of '../shell_runtime_model.dart';

/// Public language facts and service lifecycle facade.
mixin ShellRuntimeLanguageFacade on ShellRuntimeFacadeHost {
  bool get styioServiceSubscriptionAvailable =>
      _languageController.subscriptionAvailable;
  bool get styioServiceSubscriptionListening =>
      _languageController.subscriptionListening;
  StyioServiceDaemonRestartDispatchResult?
  get lastStyioServiceDaemonRestartDispatch =>
      _languageController.lastDaemonRestartDispatch;

  HoverPayload? get projectHoverAtSelection =>
      _projectLanguageContextController.projectHoverAtSelection;
  HoverPayload? get mergedHoverAtSelection =>
      _projectLanguageContextController.mergedHoverAtSelection;
  List<CompletionItem> get projectCompletionsAtSelection =>
      _projectLanguageContextController.projectCompletionsAtSelection;
  List<CompletionItem> get mergedCompletionsAtSelection =>
      _projectLanguageContextController.mergedCompletionsAtSelection;

  Future<Map<String, Object?>> collectProjectLanguageContext() =>
      _projectLanguageContextController.collect();

  Future<void> startStyioServiceDocumentSubscription() =>
      _languageController.startDocumentSubscription();

  Future<StyioServiceSubscriptionEvent?> refreshStyioServiceSubscriptionNow() =>
      _languageController.refreshSubscriptionNow();

  Future<StyioServiceSubscriptionEvent?>
  cancelStyioServiceDocumentSubscription() =>
      _languageController.cancelDocumentSubscription();

  Future<StyioServiceDaemonRestartDispatchResult?>
  dispatchStyioServiceDaemonRestart({
    int failedAttempt = 0,
    StyioServiceDaemonRestartReason reason =
        StyioServiceDaemonRestartReason.manual,
    StyioServiceDaemonRestartPolicy policy =
        const StyioServiceDaemonRestartPolicy(),
    StyioServiceDaemonRestartHandler? restart,
    StyioServiceDaemonProcessSupervisor? processSupervisor,
  }) => _languageController.dispatchDaemonRestart(
    failedAttempt: failedAttempt,
    reason: reason,
    policy: policy,
    restart: restart,
    processSupervisor: processSupervisor,
  );
}
