import 'package:flutter/foundation.dart';

import '../../backend_toolchain/backend_toolchain.dart';

/// Owns dependency fetch/vendor execution and the latest command result.
final class DependencySourceController extends ChangeNotifier {
  DependencySourceController({
    required this.adapter,
    required this.projectGraph,
    required this.refreshProjectGraph,
    required this.log,
  });

  final DependencySourceAdapter adapter;
  final ProjectGraphSnapshot Function() projectGraph;
  final Future<void> Function({String? reason}) refreshProjectGraph;
  final void Function(String message) log;

  DependencySourceCommandResult? _lastCommand;

  DependencySourceCommandResult? get lastCommand => _lastCommand;

  Future<DependencySourceCommandResult> fetchDependencies({
    bool locked = false,
    bool offline = false,
  }) async {
    final result = await adapter.fetchDependencies(
      projectGraph: projectGraph(),
      locked: locked,
      offline: offline,
    );
    return _complete(result, refreshReason: 'fetch completed');
  }

  Future<DependencySourceCommandResult> vendorDependencies({
    String? outputPath,
    bool locked = false,
    bool offline = false,
  }) async {
    final result = await adapter.vendorDependencies(
      projectGraph: projectGraph(),
      outputPath: outputPath,
      locked: locked,
      offline: offline,
    );
    return _complete(result, refreshReason: 'vendor completed');
  }

  Future<DependencySourceCommandResult> _complete(
    DependencySourceCommandResult result, {
    required String refreshReason,
  }) async {
    _lastCommand = result;
    log('${result.command} ${result.status.name}: ${result.statusMessage}');
    if (result.payload case final payload?) {
      final packages = payload['packages'];
      final vendorRoot = payload['vendor_root'] as String?;
      final metadataPath = payload['metadata_path'] as String?;
      if (packages is num) {
        log('${result.command} packages: ${packages.toInt()}');
      }
      if (vendorRoot != null && vendorRoot.isNotEmpty) {
        log('vendor root: $vendorRoot');
      }
      if (metadataPath != null && metadataPath.isNotEmpty) {
        log('vendor metadata: $metadataPath');
      }
    }
    if (result.succeeded) {
      await refreshProjectGraph(reason: refreshReason);
    } else {
      notifyListeners();
    }
    return result;
  }
}
