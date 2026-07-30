import '../system_compatibility/file_system/file_system_manager.dart';
import 'configuration_store.dart';
import 'credential_data_store.dart';

enum EnvironmentVariableOverlayScope {
  user,
  workspace,
  profile,
  task,
  debug,
  toolchain,
  extension,
}

extension EnvironmentVariableOverlayScopeX on EnvironmentVariableOverlayScope {
  String get wireValue => switch (this) {
    EnvironmentVariableOverlayScope.user => 'user',
    EnvironmentVariableOverlayScope.workspace => 'workspace',
    EnvironmentVariableOverlayScope.profile => 'profile',
    EnvironmentVariableOverlayScope.task => 'task',
    EnvironmentVariableOverlayScope.debug => 'debug',
    EnvironmentVariableOverlayScope.toolchain => 'toolchain',
    EnvironmentVariableOverlayScope.extension => 'extension',
  };
}

EnvironmentVariableOverlayScope environmentVariableOverlayScopeFromWireValue(
  String? value,
) {
  return switch (value) {
    'workspace' => EnvironmentVariableOverlayScope.workspace,
    'profile' => EnvironmentVariableOverlayScope.profile,
    'task' => EnvironmentVariableOverlayScope.task,
    'debug' => EnvironmentVariableOverlayScope.debug,
    'toolchain' => EnvironmentVariableOverlayScope.toolchain,
    'extension' => EnvironmentVariableOverlayScope.extension,
    _ => EnvironmentVariableOverlayScope.user,
  };
}

class EnvironmentVariableOverlay {
  const EnvironmentVariableOverlay({
    required this.id,
    required this.scope,
    required this.target,
    this.workspaceId,
    this.variables = const <String, String?>{},
    this.pathPrepend = const <String>[],
    this.pathAppend = const <String>[],
    this.envFiles = const <String>[],
    this.credentialReferences = const <CredentialReference>[],
  });

  final String id;
  final EnvironmentVariableOverlayScope scope;
  final String target;
  final String? workspaceId;
  final Map<String, String?> variables;
  final List<String> pathPrepend;
  final List<String> pathAppend;
  final List<String> envFiles;
  final List<CredentialReference> credentialReferences;

  factory EnvironmentVariableOverlay.fromJson(
    Map<String, Object?> json, {
    List<CredentialReference> credentialReferences =
        const <CredentialReference>[],
  }) {
    return EnvironmentVariableOverlay(
      id: json['id'] as String? ?? 'default',
      scope: environmentVariableOverlayScopeFromWireValue(
        json['scope'] as String?,
      ),
      target: json['target'] as String? ?? 'process',
      workspaceId: json['workspaceId'] as String?,
      variables: _nullableStringMapFromJson(json['variables']),
      pathPrepend: _stringListFromJson(json['pathPrepend']),
      pathAppend: _stringListFromJson(json['pathAppend']),
      envFiles: _stringListFromJson(json['envFiles']),
      credentialReferences: credentialReferences,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': 1,
      'id': id,
      'scope': scope.wireValue,
      'target': target,
      if (workspaceId != null) 'workspaceId': workspaceId,
      'variables': variables,
      'pathPrepend': pathPrepend,
      'pathAppend': pathAppend,
      'envFiles': envFiles,
      'credentialReferenceIds': credentialReferences
          .map((reference) => reference.key.stableId)
          .toList(growable: false),
    };
  }

  Map<String, Object?> toRedactedJson({
    EnvironmentVariableRedactionPolicy redactionPolicy =
        const EnvironmentVariableRedactionPolicy(),
  }) {
    return <String, Object?>{
      ...toJson(),
      'variables': redactionPolicy.redactNullableVariables(variables),
    };
  }
}

class EnvironmentVariableConfigurationStore {
  const EnvironmentVariableConfigurationStore({
    required ConfigurationStore configurationStore,
  }) : _configurationStore = configurationStore;

  final ConfigurationStore _configurationStore;

  Future<void> save(EnvironmentVariableOverlay overlay) {
    return _configurationStore.write(
      ConfigurationSettingRecord(
        key: _key(overlay),
        value: overlay.toJson(),
        credentialReferences: overlay.credentialReferences,
      ),
    );
  }

  Future<EnvironmentVariableOverlay?> load({
    required String id,
    required EnvironmentVariableOverlayScope scope,
    required String target,
    String? workspaceId,
  }) async {
    final record = await _configurationStore.read(
      _keyParts(
        id: id,
        scope: scope,
        target: target,
        workspaceId: workspaceId,
      ),
    );
    return record == null
        ? null
        : EnvironmentVariableOverlay.fromJson(
            record.value,
            credentialReferences: record.credentialReferences,
          );
  }

  Future<bool> delete({
    required String id,
    required EnvironmentVariableOverlayScope scope,
    required String target,
    String? workspaceId,
  }) {
    return _configurationStore.delete(
      _keyParts(
        id: id,
        scope: scope,
        target: target,
        workspaceId: workspaceId,
      ),
    );
  }

  ConfigurationSettingKey _key(EnvironmentVariableOverlay overlay) {
    return _keyParts(
      id: overlay.id,
      scope: overlay.scope,
      target: overlay.target,
      workspaceId: overlay.workspaceId,
    );
  }

  ConfigurationSettingKey _keyParts({
    required String id,
    required EnvironmentVariableOverlayScope scope,
    required String target,
    String? workspaceId,
  }) {
    return ConfigurationSettingKey(
      namespace: 'environment-variable',
      name: '${scope.wireValue}.$target.$id',
      workspaceId: workspaceId,
    );
  }
}

class ParsedEnvironmentVariableFile {
  const ParsedEnvironmentVariableFile({
    required this.sourcePath,
    required this.variables,
  });

  final String sourcePath;
  final Map<String, String?> variables;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sourcePath': sourcePath,
      'variables': variables,
    };
  }

  Map<String, Object?> toRedactedJson({
    EnvironmentVariableRedactionPolicy redactionPolicy =
        const EnvironmentVariableRedactionPolicy(),
  }) {
    return <String, Object?>{
      'sourcePath': sourcePath,
      'variables': redactionPolicy.redactNullableVariables(variables),
    };
  }
}

class EnvironmentVariableFileParser {
  const EnvironmentVariableFileParser();

  ParsedEnvironmentVariableFile parse({
    required String sourcePath,
    required String text,
  }) {
    final variables = <String, String?>{};
    final lines = text.split(RegExp(r'\r?\n'));
    for (var index = 0; index < lines.length; index += 1) {
      var line = lines[index].trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      if (line.startsWith('export ')) {
        line = line.substring('export '.length).trimLeft();
      }
      final separator = line.indexOf('=');
      if (separator <= 0) {
        throw FormatException(
          'Invalid environment variable assignment on line ${index + 1}.',
          line,
        );
      }
      final key = line.substring(0, separator).trim();
      if (!_isValidEnvironmentVariableName(key)) {
        throw FormatException(
          'Invalid environment variable name on line ${index + 1}.',
          key,
        );
      }
      variables[key] = _parseEnvironmentVariableValue(
        line.substring(separator + 1).trim(),
      );
    }
    return ParsedEnvironmentVariableFile(
      sourcePath: sourcePath,
      variables: Map<String, String?>.unmodifiable(variables),
    );
  }
}

class EnvironmentVariableFileLoader {
  const EnvironmentVariableFileLoader({
    required FileSystemManager fileSystemManager,
    EnvironmentVariableFileParser parser = const EnvironmentVariableFileParser(),
  }) : _fileSystemManager = fileSystemManager,
       _parser = parser;

  final FileSystemManager _fileSystemManager;
  final EnvironmentVariableFileParser _parser;

  Future<ParsedEnvironmentVariableFile> load(String path) async {
    return _parser.parse(
      sourcePath: path,
      text: await _fileSystemManager.readText(path),
    );
  }

  Future<List<ParsedEnvironmentVariableFile>> loadAll(
    Iterable<String> paths,
  ) {
    return Future.wait(paths.map(load));
  }
}

class EnvironmentVariableRedactionPolicy {
  const EnvironmentVariableRedactionPolicy({
    this.redactedValue = '<redacted>',
    this.sensitiveNameFragments = const <String>{
      'secret',
      'token',
      'password',
      'apikey',
      '_key',
      'privatekey',
      'private_key',
      'credential',
    },
  });

  final String redactedValue;
  final Set<String> sensitiveNameFragments;

  bool shouldRedact(String name) {
    final normalized = name.toLowerCase();
    return sensitiveNameFragments.any(normalized.contains);
  }

  Map<String, String> redactEnvironment(Map<String, String> environment) {
    return environment.map(
      (key, value) => MapEntry<String, String>(
        key,
        shouldRedact(key) ? redactedValue : value,
      ),
    );
  }

  Map<String, String?> redactNullableVariables(
    Map<String, String?> variables,
  ) {
    return variables.map(
      (key, value) => MapEntry<String, String?>(
        key,
        value == null
            ? null
            : shouldRedact(key)
                ? redactedValue
                : value,
      ),
    );
  }
}

class EnvironmentVariableResolver {
  const EnvironmentVariableResolver({this.pathVariableName = 'PATH'});

  final String pathVariableName;

  Map<String, String> resolve({
    Map<String, String> inherited = const <String, String>{},
    Iterable<Map<String, String?>> envFileVariables =
        const <Map<String, String?>>[],
    Iterable<EnvironmentVariableOverlay> overlays =
        const <EnvironmentVariableOverlay>[],
    Map<String, String> runtimeOverrides = const <String, String>{},
    String pathSeparator = ':',
  }) {
    final result = Map<String, String>.of(inherited);
    for (final envFile in envFileVariables) {
      _mergeVariables(result, envFile);
    }
    for (final overlay in overlays) {
      _mergePath(result, overlay, pathSeparator);
      _mergeVariables(result, overlay.variables);
    }
    result.addAll(runtimeOverrides);
    return result;
  }

  void _mergeVariables(
    Map<String, String> result,
    Map<String, String?> variables,
  ) {
    for (final entry in variables.entries) {
      final value = entry.value;
      if (value == null) {
        result.remove(entry.key);
      } else {
        result[entry.key] = value;
      }
    }
  }

  void _mergePath(
    Map<String, String> result,
    EnvironmentVariableOverlay overlay,
    String pathSeparator,
  ) {
    if (overlay.pathPrepend.isEmpty && overlay.pathAppend.isEmpty) {
      return;
    }
    final current = result[pathVariableName];
    final segments = <String>[
      ...overlay.pathPrepend,
      if (current != null && current.isNotEmpty) current,
      ...overlay.pathAppend,
    ];
    result[pathVariableName] = segments.join(pathSeparator);
  }
}

List<String> _stringListFromJson(Object? value) {
  if (value is List) {
    return value.map((entry) => entry.toString()).toList(growable: false);
  }
  return const <String>[];
}

Map<String, String?> _nullableStringMapFromJson(Object? value) {
  if (value is Map) {
    return value.map(
      (key, value) => MapEntry<String, String?>(
        key.toString(),
        value?.toString(),
      ),
    );
  }
  return const <String, String?>{};
}

bool _isValidEnvironmentVariableName(String name) {
  return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name);
}

String _parseEnvironmentVariableValue(String value) {
  if (value.length >= 2) {
    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}
