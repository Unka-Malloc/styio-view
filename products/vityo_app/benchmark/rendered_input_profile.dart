/// Rendered editor input profile harness.
///
/// Writes sanitized baseline evidence. Desktop rendered measurement requires a
/// matching host; without one the receipt is marked unsupported/notRun.
library;

import 'dart:io';

import 'package:vityo_app/src/ide/editor/performance/rendered_input_profile_harness.dart';

Future<void> main(List<String> args) async {
  final writeBaseline = args.contains('--write-baseline');
  final harness = EditorRenderedInputProfileHarness();
  final platformFamily = _detectPlatformFamily();
  final receipt = harness.buildUnsupportedReceipt(
    platformFamily: platformFamily,
    failureCode: 'rendered_desktop_profile_not_run',
  );

  stdout.writeln(
    'rendered-editor-input profile status=${receipt.status} '
    'platform=$platformFamily lanes=${receipt.lanes.length}',
  );

  if (writeBaseline) {
    final repoRoot = _repositoryRoot();
    final jsonPath = '$repoRoot/docs/review/performance-baseline.json';
    final markdownPath = '$repoRoot/docs/review/performance-baseline.md';
    harness.writeBaselineFiles(
      receipt: receipt,
      jsonPath: jsonPath,
      markdownPath: markdownPath,
    );
    stdout.writeln('wrote $jsonPath');
    stdout.writeln('wrote $markdownPath');
  }
}

String _detectPlatformFamily() {
  if (Platform.isMacOS) return 'desktop-macos';
  if (Platform.isWindows) return 'desktop-windows';
  if (Platform.isLinux) return 'desktop-linux';
  return 'unsupported';
}

String _repositoryRoot() {
  var current = Directory.current;
  while (!File('${current.path}/products/vityo_app/pubspec.yaml').existsSync()) {
    if (current.parent.path == current.path) {
      return Directory.current.path;
    }
    current = current.parent;
  }
  return current.path;
}
