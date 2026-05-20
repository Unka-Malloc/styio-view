import 'extension_activator.dart';
import 'extension_manifest_contract.dart';

enum ExtensionLifecycleHookKind { activate, deactivate }

extension ExtensionLifecycleHookKindX on ExtensionLifecycleHookKind {
  String get wireValue => switch (this) {
    ExtensionLifecycleHookKind.activate => 'activate',
    ExtensionLifecycleHookKind.deactivate => 'deactivate',
  };
}

class ExtensionLifecycleHook {
  const ExtensionLifecycleHook({
    required this.extensionId,
    required this.kind,
    required this.command,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.metadata = const <String, Object?>{},
  });

  factory ExtensionLifecycleHook.fromJson({
    required String extensionId,
    required Map<String, Object?> json,
  }) {
    return ExtensionLifecycleHook(
      extensionId: extensionId,
      kind: _hookKindFromWire(json['kind'] as String?),
      command: json['command'] as String? ?? '',
      arguments: _stringList(json['arguments']),
      environment: _stringMap(json['environment']),
      metadata: _objectMap(json['metadata']),
    );
  }

  final String extensionId;
  final ExtensionLifecycleHookKind kind;
  final String command;
  final List<String> arguments;
  final Map<String, String> environment;
  final Map<String, Object?> metadata;

  bool get runnable =>
      extensionId.trim().isNotEmpty && command.trim().isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'kind': kind.wireValue,
      'command': command,
      'arguments': arguments,
      'environment': environment,
      'runnable': runnable,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionLifecycleHookCatalog {
  const ExtensionLifecycleHookCatalog({required this.hooks});

  factory ExtensionLifecycleHookCatalog.fromRegistry(
    ExtensionManifestRegistry registry,
  ) {
    return ExtensionLifecycleHookCatalog(
      hooks: registry
          .list()
          .expand((manifest) => _hooksFromManifest(manifest))
          .where((hook) => hook.runnable)
          .toList(growable: false),
    );
  }

  final List<ExtensionLifecycleHook> hooks;

  List<ExtensionLifecycleHook> hooksFor({
    required String extensionId,
    required ExtensionLifecycleHookKind kind,
  }) {
    return hooks
        .where((hook) => hook.extensionId == extensionId && hook.kind == kind)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-lifecycle-hooks.v1',
      'hookCount': hooks.length,
      'hooks': hooks.map((hook) => hook.toJson()).toList(growable: false),
    };
  }
}

class ExtensionLifecycleHookResult {
  const ExtensionLifecycleHookResult({
    required this.hook,
    required this.succeeded,
    required this.message,
    required this.completedAt,
    this.exitCode,
  });

  final ExtensionLifecycleHook hook;
  final bool succeeded;
  final String message;
  final DateTime completedAt;
  final int? exitCode;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'hook': hook.toJson(),
      'succeeded': succeeded,
      'message': message,
      'completedAt': completedAt.toIso8601String(),
      if (exitCode != null) 'exitCode': exitCode,
    };
  }
}

typedef ExtensionLifecycleHookExecutor =
    Future<ExtensionLifecycleHookResult> Function(ExtensionLifecycleHook hook);

class ExtensionLifecycleHookRunner {
  const ExtensionLifecycleHookRunner({
    required this.catalog,
    required this.executor,
  });

  final ExtensionLifecycleHookCatalog catalog;
  final ExtensionLifecycleHookExecutor executor;

  Future<List<ExtensionLifecycleHookResult>> runActivationHooks(
    ExtensionActivationSession session,
  ) async {
    final results = <ExtensionLifecycleHookResult>[];
    for (final extensionId in session.activatedExtensionIds) {
      for (final hook in catalog.hooksFor(
        extensionId: extensionId,
        kind: ExtensionLifecycleHookKind.activate,
      )) {
        results.add(await executor(hook));
      }
    }
    return results;
  }

  Future<List<ExtensionLifecycleHookResult>> runDeactivationHooks({
    required String extensionId,
  }) async {
    final results = <ExtensionLifecycleHookResult>[];
    for (final hook in catalog.hooksFor(
      extensionId: extensionId,
      kind: ExtensionLifecycleHookKind.deactivate,
    )) {
      results.add(await executor(hook));
    }
    return results;
  }
}

Iterable<ExtensionLifecycleHook> _hooksFromManifest(
  ExtensionManifest manifest,
) {
  final rawHooks = manifest.metadata['lifecycleHooks'];
  if (rawHooks is! List) {
    return const <ExtensionLifecycleHook>[];
  }
  return rawHooks.whereType<Map>().map(
    (hook) => ExtensionLifecycleHook.fromJson(
      extensionId: manifest.extensionId,
      json: hook.map((key, value) => MapEntry(key.toString(), value)),
    ),
  );
}

ExtensionLifecycleHookKind _hookKindFromWire(String? value) {
  return switch (value) {
    'deactivate' => ExtensionLifecycleHookKind.deactivate,
    _ => ExtensionLifecycleHookKind.activate,
  };
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .where((item) => item.trim().isNotEmpty)
      .map((item) => item.trim())
      .toList(growable: false);
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  return value.map((key, value) => MapEntry(key.toString(), value.toString()));
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}
