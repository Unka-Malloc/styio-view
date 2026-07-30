library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../cancellation.dart';
import '../policy/execution_hooks.dart';
import '../policy/permission_grant_store.dart';
import '../policy/policy_evaluator.dart';
import 'tool_catalog.dart';

final class ToolCall {
  const ToolCall({
    required this.callId,
    required this.toolId,
    required this.catalogVersion,
    required this.arguments,
    this.idempotencyKey,
  });

  final String callId;
  final String toolId;
  final String catalogVersion;
  final Map<String, Object?> arguments;
  final String? idempotencyKey;
}

abstract interface class SecretVault {
  Future<String?> resolve(String secretId, {required String audience});
}

final class ToolExecutionContext {
  ToolExecutionContext({
    required this.sessionId,
    required this.observedAt,
    required this.cancellation,
    required List<ToolRoot> roots,
    required ExecutionPolicy policy,
    required this.grants,
    required this.pathResolver,
    this.secretVault,
    this.deadline,
  }) : roots = List<ToolRoot>.unmodifiable(roots),
       policy = ExecutionPolicy.snapshot(policy);

  final String sessionId;
  final DateTime observedAt;
  final DateTime? deadline;
  final AgentCancellationToken cancellation;
  final List<ToolRoot> roots;
  final ExecutionPolicy policy;
  final PermissionGrantStore grants;
  final Future<String> Function(String uri) pathResolver;
  final SecretVault? secretVault;
}

enum ToolFailureCode {
  schemaInvalid,
  toolRemoved,
  policyDenied,
  permissionDenied,
  cancelled,
  timeout,
  resultInvalid,
  resultTooLarge,
  hookRejected,
  adapterUnavailable,
  idempotencyConflict,
  capacityExceeded,
}

enum ToolEffectState { none, uncertain, committed }

final class ToolFailure {
  const ToolFailure({required this.code, required this.message});

  final ToolFailureCode code;
  final String message;
}

final class ToolExecutionReceipt {
  ToolExecutionReceipt({
    required this.callId,
    required this.toolId,
    required this.catalogVersion,
    required this.effectId,
    required Map<String, Object?> output,
    required this.outputBytes,
    required this.untrustedEvidence,
    required this.reused,
    required this.effectState,
    this.failure,
  }) : output = ToolJson.freezeMap(output);

  final String callId;
  final String toolId;
  final String catalogVersion;
  final String effectId;
  final Map<String, Object?> output;
  final int outputBytes;
  final bool untrustedEvidence;
  final bool reused;
  final ToolEffectState effectState;
  final ToolFailure? failure;

  bool get succeeded => failure == null;

  ToolExecutionReceipt asReused() => ToolExecutionReceipt(
    callId: callId,
    toolId: toolId,
    catalogVersion: catalogVersion,
    effectId: effectId,
    output: output,
    outputBytes: outputBytes,
    untrustedEvidence: untrustedEvidence,
    reused: true,
    effectState: effectState,
    failure: failure,
  );

  @override
  String toString() =>
      'ToolExecutionReceipt(callId: $callId, toolId: $toolId, '
      'effectId: $effectId, succeeded: $succeeded, reused: $reused, '
      'effectState: ${effectState.name}, outputBytes: $outputBytes)';
}

final class ToolExecutor {
  ToolExecutor({
    required ToolCatalog Function() catalogProvider,
    required Map<String, ToolAdapter> adapters,
    required PolicyEvaluator policyEvaluator,
    required List<ExecutionHook> hooks,
    required this.maxReceiptEntries,
  }) : _catalogProvider = catalogProvider,
       _adapters = Map<String, ToolAdapter>.unmodifiable(adapters),
       _policyEvaluator = policyEvaluator,
       _hooks = List<ExecutionHook>.unmodifiable(hooks) {
    if (maxReceiptEntries <= 0) {
      throw ArgumentError.value(maxReceiptEntries, 'maxReceiptEntries');
    }
  }

  final ToolCatalog Function() _catalogProvider;
  final Map<String, ToolAdapter> _adapters;
  final PolicyEvaluator _policyEvaluator;
  final List<ExecutionHook> _hooks;
  final int maxReceiptEntries;
  final LinkedHashMap<String, _StoredReceipt> _receipts =
      LinkedHashMap<String, _StoredReceipt>();
  final Map<String, _InflightExecution> _inflight =
      <String, _InflightExecution>{};
  int _activeExecutions = 0;

  int get receiptEntryCount => _receipts.length;

  Future<ToolExecutionReceipt> execute(
    ToolCall call,
    ToolExecutionContext context,
  ) {
    final idempotency = call.idempotencyKey?.trim();
    if (idempotency == null || idempotency.isEmpty) {
      if (_activeExecutions >= maxReceiptEntries) {
        return Future<ToolExecutionReceipt>.value(_capacityFailure(call));
      }
      return _startFresh(call, context);
    }
    final key = '${context.sessionId}\u0000${call.toolId}\u0000$idempotency';
    final fingerprint = _fingerprint(call);
    final stored = _receipts.remove(key);
    if (stored != null) {
      _receipts[key] = stored;
      if (stored.fingerprint != fingerprint) {
        return Future<ToolExecutionReceipt>.value(
          _failure(
            call,
            ToolFailureCode.idempotencyConflict,
            'Idempotency key was reused for a different call.',
          ),
        );
      }
      return Future<ToolExecutionReceipt>.value(stored.receipt.asReused());
    }
    final running = _inflight[key];
    if (running != null) {
      if (running.fingerprint != fingerprint) {
        return Future<ToolExecutionReceipt>.value(
          _failure(
            call,
            ToolFailureCode.idempotencyConflict,
            'Idempotency key conflicts with an active call.',
          ),
        );
      }
      return running.future.then((receipt) => receipt.asReused());
    }
    if (_activeExecutions >= maxReceiptEntries) {
      return Future<ToolExecutionReceipt>.value(_capacityFailure(call));
    }
    final future = _startFresh(call, context);
    _inflight[key] = _InflightExecution(fingerprint, future);
    return future.then(
      (receipt) {
        _inflight.remove(key);
        if (receipt.effectState != ToolEffectState.none) {
          _receipts[key] = _StoredReceipt(fingerprint, receipt);
          while (_receipts.length > maxReceiptEntries) {
            _receipts.remove(_receipts.keys.first);
          }
        }
        return receipt;
      },
      onError: (Object error, StackTrace stackTrace) {
        _inflight.remove(key);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  Future<ToolExecutionReceipt> _startFresh(
    ToolCall call,
    ToolExecutionContext context,
  ) {
    _activeExecutions += 1;
    return _executeFresh(
      call,
      context,
      _effectId(call, context),
    ).whenComplete(() => _activeExecutions -= 1);
  }

  Future<ToolExecutionReceipt> _executeFresh(
    ToolCall call,
    ToolExecutionContext context,
    String effectId,
  ) async {
    if (context.cancellation.isCancelled) {
      return _failure(
        call,
        ToolFailureCode.cancelled,
        'Tool execution was cancelled.',
        effectId: effectId,
      );
    }
    if (_deadlineReached(context.deadline)) {
      return _failure(
        call,
        ToolFailureCode.timeout,
        'Tool execution deadline was reached.',
        effectId: effectId,
      );
    }
    final catalog = _catalogProvider();
    if (catalog.version != call.catalogVersion) {
      return _failure(
        call,
        ToolFailureCode.toolRemoved,
        'Tool catalog version is no longer current.',
        effectId: effectId,
      );
    }
    final descriptor = catalog.find(call.toolId);
    if (descriptor == null) {
      return _failure(
        call,
        ToolFailureCode.toolRemoved,
        'Tool is no longer available.',
        effectId: effectId,
      );
    }
    var arguments = Map<String, Object?>.of(call.arguments);
    if (!ToolSchema.accepts(descriptor.inputSchema, arguments)) {
      return _failure(
        call,
        ToolFailureCode.schemaInvalid,
        'Tool arguments do not match the frozen schema.',
        effectId: effectId,
      );
    }
    try {
      for (final hook in _hooks) {
        arguments = Map<String, Object?>.of(
          await _bounded(hook.before(descriptor, arguments), context),
        );
      }
    } on ToolHookRejection {
      return _failure(
        call,
        ToolFailureCode.hookRejected,
        'Pre-execution hook rejected the call.',
        effectId: effectId,
      );
    } on _ExecutionAbort catch (error) {
      return _abortFailure(call, error, effectId);
    } on Object {
      return _failure(
        call,
        ToolFailureCode.hookRejected,
        'Pre-execution hook failed closed.',
        effectId: effectId,
      );
    }
    if (!ToolSchema.accepts(descriptor.inputSchema, arguments)) {
      return _failure(
        call,
        ToolFailureCode.schemaInvalid,
        'Hook-transformed arguments do not match the schema.',
        effectId: effectId,
      );
    }

    final requestedPath = descriptor.pathArgument == null
        ? null
        : arguments[descriptor.pathArgument];
    String? resolvedPath;
    if (requestedPath != null) {
      if (requestedPath is! String) {
        return _failure(
          call,
          ToolFailureCode.schemaInvalid,
          'Tool path argument must be a string.',
          effectId: effectId,
        );
      }
      try {
        resolvedPath = await _bounded(
          context.pathResolver(requestedPath),
          context,
        );
      } on _ExecutionAbort catch (error) {
        return _abortFailure(call, error, effectId);
      } on Object {
        return _failure(
          call,
          ToolFailureCode.policyDenied,
          'Tool path could not be resolved safely.',
          effectId: effectId,
        );
      }
    }

    final secretReferences = <String, _SecretReference>{};
    var secretAudienceValid = true;
    for (final entry in descriptor.secretArguments.entries) {
      final raw = arguments[entry.key];
      final reference = raw is String ? _SecretReference.tryParse(raw) : null;
      if (reference == null || reference.audience != entry.value) {
        secretAudienceValid = false;
      } else {
        secretReferences[entry.key] = reference;
      }
    }
    final rawCredentialDetected =
        _containsRawCredential(arguments, descriptor.secretArguments.keys) ||
        descriptor.secretArguments.keys.any(
          (key) => !secretReferences.containsKey(key),
        );
    final networkHost = descriptor.networkHostArgument == null
        ? null
        : arguments[descriptor.networkHostArgument];
    final decision = _policyEvaluator.evaluate(
      effect: ToolEffect(
        toolId: descriptor.id,
        risk: descriptor.risk,
        requestedPath: requestedPath is String ? requestedPath : null,
        resolvedPath: resolvedPath,
        networkHost: networkHost is String ? networkHost : null,
        rawCredentialDetected: rawCredentialDetected,
        secretAudienceValid: secretAudienceValid,
      ),
      policy: context.policy,
      roots: context.roots,
      grants: context.grants,
      sessionId: context.sessionId,
    );
    if (!decision.allowed) {
      return _failure(
        call,
        decision.code == PolicyDecisionCode.permissionDenied
            ? ToolFailureCode.permissionDenied
            : ToolFailureCode.policyDenied,
        'Tool effect was denied by the current execution policy.',
        effectId: effectId,
      );
    }

    final secretValues = <String>{};
    for (final entry in secretReferences.entries) {
      final vault = context.secretVault;
      String? value;
      try {
        value = vault == null
            ? null
            : await _bounded(
                vault.resolve(entry.value.id, audience: entry.value.audience),
                context,
              );
      } on _ExecutionAbort catch (error) {
        return _abortFailure(call, error, effectId);
      } on Object {
        value = null;
      }
      if (value == null) {
        return _failure(
          call,
          ToolFailureCode.policyDenied,
          'Secret reference could not be resolved for its audience.',
          effectId: effectId,
        );
      }
      arguments[entry.key] = value;
      secretValues.add(value);
    }

    final adapter = _adapters[descriptor.id];
    if (adapter == null) {
      return _failure(
        call,
        ToolFailureCode.adapterUnavailable,
        'Tool adapter is unavailable.',
        effectId: effectId,
      );
    }
    Map<String, Object?> output;
    try {
      output = Map<String, Object?>.of(
        await _bounded(
          adapter.execute(descriptor, arguments, context.cancellation),
          context,
        ),
      );
    } on _ExecutionAbort catch (error) {
      return _abortFailure(
        call,
        error,
        effectId,
        effectState: ToolEffectState.uncertain,
      );
    } on ToolAdapterFailure {
      return _failure(
        call,
        ToolFailureCode.adapterUnavailable,
        'Tool adapter failed.',
        effectId: effectId,
        effectState: ToolEffectState.uncertain,
      );
    } on Object {
      return _failure(
        call,
        ToolFailureCode.adapterUnavailable,
        'Tool adapter failed closed.',
        effectId: effectId,
        effectState: ToolEffectState.uncertain,
      );
    }

    try {
      for (final hook in _hooks) {
        output = Map<String, Object?>.of(
          await _bounded(hook.after(descriptor, output), context),
        );
      }
    } on ToolHookRejection {
      return _failure(
        call,
        ToolFailureCode.hookRejected,
        'Post-execution hook rejected the result.',
        effectId: effectId,
        effectState: ToolEffectState.committed,
      );
    } on _ExecutionAbort catch (error) {
      return _abortFailure(
        call,
        error,
        effectId,
        effectState: ToolEffectState.committed,
      );
    } on Object {
      return _failure(
        call,
        ToolFailureCode.hookRejected,
        'Post-execution hook failed closed.',
        effectId: effectId,
        effectState: ToolEffectState.committed,
      );
    }
    if (!ToolSchema.accepts(descriptor.outputSchema, output)) {
      return _failure(
        call,
        ToolFailureCode.resultInvalid,
        'Tool result does not match the output schema.',
        effectId: effectId,
        effectState: ToolEffectState.committed,
      );
    }
    final rawBytes = ToolSchema.encodedBytes(output);
    final resultLimit =
        descriptor.maxResultBytes < context.policy.maxResultBytes
        ? descriptor.maxResultBytes
        : context.policy.maxResultBytes;
    if (rawBytes > resultLimit) {
      return _failure(
        call,
        ToolFailureCode.resultTooLarge,
        'Tool result exceeds its byte bound.',
        effectId: effectId,
        effectState: ToolEffectState.committed,
      );
    }
    final redacted = Map<String, Object?>.from(
      _redact(output, secretValues) as Map,
    );
    return ToolExecutionReceipt(
      callId: call.callId,
      toolId: call.toolId,
      catalogVersion: call.catalogVersion,
      effectId: effectId,
      output: redacted,
      outputBytes: ToolSchema.encodedBytes(redacted),
      untrustedEvidence: true,
      reused: false,
      effectState: ToolEffectState.committed,
    );
  }

  Future<T> _bounded<T>(
    Future<T> operation,
    ToolExecutionContext context,
  ) async {
    if (context.cancellation.isCancelled) {
      throw const _ExecutionAbort(ToolFailureCode.cancelled);
    }
    final deadline = context.deadline;
    if (_deadlineReached(deadline)) {
      throw const _ExecutionAbort(ToolFailureCode.timeout);
    }
    final abort = Completer<T>();
    final subscription = context.cancellation.cancellations.listen((_) {
      if (!abort.isCompleted) {
        abort.completeError(const _ExecutionAbort(ToolFailureCode.cancelled));
      }
    });
    Timer? timer;
    if (deadline != null) {
      timer = Timer(deadline.difference(DateTime.now()), () {
        if (!abort.isCompleted) {
          abort.completeError(const _ExecutionAbort(ToolFailureCode.timeout));
        }
      });
    }
    try {
      return await Future.any<T>(<Future<T>>[operation, abort.future]);
    } finally {
      timer?.cancel();
      await subscription.cancel();
    }
  }

  static bool _deadlineReached(DateTime? deadline) =>
      deadline != null && !DateTime.now().isBefore(deadline);

  static bool _containsRawCredential(
    Object? value,
    Iterable<String> declaredSecretKeys,
  ) {
    final secretKeys = declaredSecretKeys.toSet();
    bool scan(Object? item, {String? key}) {
      if (item is Map) {
        for (final entry in item.entries) {
          final name = entry.key.toString();
          if (scan(entry.value, key: name)) return true;
        }
        return false;
      }
      if (item is Iterable) {
        return item.any((element) => scan(element, key: key));
      }
      if (item is! String) return false;
      if (item.startsWith('secret://')) return false;
      final normalizedKey = key?.toLowerCase() ?? '';
      return secretKeys.contains(key) ||
          normalizedKey.contains('token') ||
          normalizedKey.contains('password') ||
          normalizedKey.contains('secret') ||
          normalizedKey.contains('credential') ||
          item.toLowerCase().startsWith('bearer ');
    }

    return scan(value);
  }

  static Object? _redact(
    Object? value,
    Set<String> secretValues, {
    String? key,
  }) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _redact(
            entry.value,
            secretValues,
            key: entry.key.toString(),
          ),
      };
    }
    if (value is Iterable) {
      return value
          .map((item) => _redact(item, secretValues, key: key))
          .toList(growable: false);
    }
    final normalizedKey = key?.toLowerCase() ?? '';
    if (normalizedKey.contains('token') ||
        normalizedKey.contains('password') ||
        normalizedKey.contains('secret') ||
        normalizedKey.contains('credential') ||
        (value is String &&
            secretValues.any(
              (secret) => secret.isNotEmpty && value.contains(secret),
            ))) {
      return '[redacted]';
    }
    return value;
  }

  static String _fingerprint(ToolCall call) => sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'tool': call.toolId,
            'catalog': call.catalogVersion,
            'arguments': _canonical(call.arguments),
          }),
        ),
      )
      .toString();

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonical(value[key]),
      };
    }
    if (value is Iterable) {
      return value.map(_canonical).toList(growable: false);
    }
    return value;
  }

  static String _effectId(ToolCall call, ToolExecutionContext context) {
    final material =
        '${context.sessionId}\u0000${call.toolId}\u0000'
        '${call.idempotencyKey ?? call.callId}';
    return sha256.convert(utf8.encode(material)).toString();
  }

  static ToolExecutionReceipt _abortFailure(
    ToolCall call,
    _ExecutionAbort abort,
    String effectId, {
    ToolEffectState effectState = ToolEffectState.none,
  }) => _failure(
    call,
    abort.code,
    abort.code == ToolFailureCode.cancelled
        ? 'Tool execution was cancelled.'
        : 'Tool execution deadline was reached.',
    effectId: effectId,
    effectState: effectState,
  );

  static ToolExecutionReceipt _failure(
    ToolCall call,
    ToolFailureCode code,
    String message, {
    String? effectId,
    ToolEffectState effectState = ToolEffectState.none,
  }) => ToolExecutionReceipt(
    callId: call.callId,
    toolId: call.toolId,
    catalogVersion: call.catalogVersion,
    effectId: effectId ?? sha256.convert(utf8.encode(call.callId)).toString(),
    output: const <String, Object?>{},
    outputBytes: 0,
    untrustedEvidence: false,
    reused: false,
    effectState: effectState,
    failure: ToolFailure(code: code, message: message),
  );

  static ToolExecutionReceipt _capacityFailure(ToolCall call) => _failure(
    call,
    ToolFailureCode.capacityExceeded,
    'Tool execution concurrency bound was reached.',
  );
}

final class _SecretReference {
  const _SecretReference({required this.id, required this.audience});

  final String id;
  final String audience;

  static _SecretReference? tryParse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'secret') return null;
    final id = uri.host.isNotEmpty
        ? uri.host
        : uri.pathSegments.firstOrNull ?? '';
    final audience = uri.queryParameters['audience'] ?? '';
    if (id.isEmpty || audience.isEmpty) return null;
    return _SecretReference(id: id, audience: audience);
  }
}

final class _ExecutionAbort implements Exception {
  const _ExecutionAbort(this.code);

  final ToolFailureCode code;
}

final class _StoredReceipt {
  const _StoredReceipt(this.fingerprint, this.receipt);

  final String fingerprint;
  final ToolExecutionReceipt receipt;
}

final class _InflightExecution {
  const _InflightExecution(this.fingerprint, this.future);

  final String fingerprint;
  final Future<ToolExecutionReceipt> future;
}
