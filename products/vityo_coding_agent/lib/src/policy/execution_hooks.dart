library;

import '../tools/tool_catalog.dart';

final class ToolHookRejection implements Exception {
  const ToolHookRejection(this.message);

  final String message;
}

abstract interface class ExecutionHook {
  Future<Map<String, Object?>> before(
    ToolDescriptor descriptor,
    Map<String, Object?> arguments,
  );

  Future<Map<String, Object?>> after(
    ToolDescriptor descriptor,
    Map<String, Object?> output,
  );
}
