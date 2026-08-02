import '../../interaction/language_service_status_surface.dart';

/// Owns explicit language-service refresh for IDE commands.
final class LanguageRefreshCommandController {
  const LanguageRefreshCommandController({
    required this.refreshAvailable,
    required this.refresh,
    required this.status,
    required this.log,
  });

  final bool Function() refreshAvailable;
  final Future<void> Function() refresh;
  final LanguageServiceStatusSurface Function() status;
  final void Function(String message) log;

  Future<bool> execute() async {
    if (!refreshAvailable()) {
      log(
        'Language service refresh skipped: no refresh callback is configured.',
      );
      return false;
    }
    try {
      await refresh();
      final currentStatus = status();
      log(
        'Language service refresh requested '
        '(severity=${currentStatus.severity.name}, '
        'usable=${currentStatus.usableCapabilityCount}, '
        'fresh=${currentStatus.freshCapabilityCount}).',
      );
      return true;
    } on Object catch (error) {
      log('Language service refresh failed: $error');
      return false;
    }
  }
}
