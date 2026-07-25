import 'dart:async';

import '../../agent/agent.dart';
import '../../commands/commands.dart';
import 'agent_controller.dart';
import 'debug_controller.dart';

/// Owns agent-facing debugger command routing and typed result projection.
final class AgentDebugCommandController {
  const AgentDebugCommandController({
    required this.agentController,
    required this.toggleBreakpoint,
    required this.start,
    required this.stop,
    required this.resume,
    required this.stepOver,
    required this.selectThread,
    required this.selectStackFrame,
    required this.debugStatus,
    required this.blockWhenDirty,
    required this.log,
  });

  final AgentController agentController;
  final FutureOr<DebugCommandResult> Function() toggleBreakpoint;
  final FutureOr<DebugCommandResult> Function() start;
  final FutureOr<DebugCommandResult> Function() stop;
  final FutureOr<DebugCommandResult> Function() resume;
  final FutureOr<DebugCommandResult> Function() stepOver;
  final FutureOr<DebugCommandResult> Function(String id) selectThread;
  final FutureOr<DebugCommandResult> Function(String id) selectStackFrame;
  final String Function() debugStatus;
  final bool Function(AgentIdeCommandSuggestion suggestion) blockWhenDirty;
  final void Function(String message) log;

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) async {
    if (suggestion.commandId == 'startDebugging' &&
        blockWhenDirty(suggestion)) {
      return false;
    }
    return switch (suggestion.commandId) {
      'toggleBreakpoint' => _run(suggestion, toggleBreakpoint),
      'startDebugging' => _run(suggestion, start),
      'stopDebugging' => _run(suggestion, stop),
      'continueDebugging' => _run(suggestion, resume),
      'stepOver' => _run(suggestion, stepOver),
      'selectDebugThread' => _select(
        suggestion,
        AppCommandId.selectDebugThread,
        selectThread,
        'threadId',
      ),
      'selectDebugStackFrame' => _select(
        suggestion,
        AppCommandId.selectDebugStackFrame,
        selectStackFrame,
        'frameId',
      ),
      _ => throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported agent debug command.',
      ),
    };
  }

  Future<bool> _run(
    AgentIdeCommandSuggestion suggestion,
    FutureOr<DebugCommandResult> Function() action,
  ) async {
    final result = await Future<DebugCommandResult>.value(action());
    _record(
      suggestion,
      applied: result.applied,
      message: result.message,
      metadata: <String, Object?>{'debugStatus': debugStatus()},
    );
    return result.applied;
  }

  Future<bool> _select(
    AgentIdeCommandSuggestion suggestion,
    AppCommandId commandId,
    FutureOr<DebugCommandResult> Function(String id) action,
    String metadataKey,
  ) async {
    final input = suggestion.input?.trim() ?? '';
    if (input.isEmpty) {
      final descriptor = StyioCommandRegistry.descriptorFor(commandId);
      final message =
          'Agent command ${suggestion.commandId} skipped: missing input.';
      _record(
        suggestion,
        applied: false,
        message: message,
        metadata: <String, Object?>{
          'reason': 'missing-input',
          'requiredInput': descriptor.inputLabel,
          'inputLabel': descriptor.inputLabel,
          'inputContract': descriptor.inputContract,
          'inputExamples': descriptor.inputExamples,
        },
      );
      log(message);
      return false;
    }
    final result = await Future<DebugCommandResult>.value(action(input));
    _record(
      suggestion,
      applied: result.applied,
      message: result.message,
      metadata: <String, Object?>{metadataKey: input},
    );
    return result.applied;
  }

  void _record(
    AgentIdeCommandSuggestion suggestion, {
    required bool applied,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final effectiveMetadata = <String, Object?>{...metadata};
    final prerequisite = suggestion.prerequisiteForCommandId;
    if (prerequisite != null && prerequisite.isNotEmpty) {
      effectiveMetadata['completedRequiredCommandFor'] = prerequisite;
    }
    agentController.recordCommandResult(
      AgentCommandResultContext(
        commandId: suggestion.commandId,
        input: suggestion.input,
        applied: applied,
        message: message,
        metadata: effectiveMetadata,
        completedAt: DateTime.now().toUtc(),
      ),
    );
  }
}
