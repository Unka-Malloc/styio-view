import '../system_compatibility/shell/shell_facts.dart';

class ShellConfiguration {
  const ShellConfiguration({
    required this.defaultProfileId,
    required this.profiles,
    this.environmentOverlay = const <String, String>{},
    this.loginShell = false,
    this.interactive = false,
    this.timeout = const Duration(seconds: 30),
  });

  factory ShellConfiguration.fromFacts(ShellFacts facts) {
    final defaultShell = facts.defaultShell;
    final profiles = facts.availableShells
        .map(
          (shell) => ShellProfileConfiguration(
            id: shell.isDefault ? 'default' : shell.family.wireValue,
            executablePath: shell.path,
            family: shell.family,
          ),
        )
        .toList(growable: false);
    if (profiles.isEmpty || defaultShell == null) {
      return const ShellConfiguration(
        defaultProfileId: 'unsupported',
        profiles: <ShellProfileConfiguration>[],
      );
    }
    return ShellConfiguration(
      defaultProfileId: profiles
          .firstWhere(
            (profile) => profile.executablePath == defaultShell.path,
            orElse: () => profiles.first,
          )
          .id,
      profiles: profiles,
      loginShell: false,
      interactive: false,
    );
  }

  final String defaultProfileId;
  final List<ShellProfileConfiguration> profiles;
  final Map<String, String> environmentOverlay;
  final bool loginShell;
  final bool interactive;
  final Duration timeout;

  factory ShellConfiguration.fromJson(Map<String, Object?> json) {
    final profiles = json['profiles'];
    final environmentOverlay = json['environmentOverlay'];
    return ShellConfiguration(
      defaultProfileId: json['defaultProfileId'] as String? ?? 'default',
      profiles: profiles is List
          ? profiles
              .map(_shellProfileConfigurationFromJson)
              .whereType<ShellProfileConfiguration>()
              .toList(growable: false)
          : const <ShellProfileConfiguration>[],
      environmentOverlay: _stringMapFromJson(environmentOverlay),
      loginShell: json['loginShell'] as bool? ?? false,
      interactive: json['interactive'] as bool? ?? false,
      timeout: Duration(
        milliseconds: json['timeoutMs'] as int? ?? 30000,
      ),
    );
  }

  ShellProfileConfiguration? get defaultProfile {
    for (final profile in profiles) {
      if (profile.id == defaultProfileId) {
        return profile;
      }
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  ShellConfiguration copyWith({
    String? defaultProfileId,
    List<ShellProfileConfiguration>? profiles,
    Map<String, String>? environmentOverlay,
    bool? loginShell,
    bool? interactive,
    Duration? timeout,
  }) {
    return ShellConfiguration(
      defaultProfileId: defaultProfileId ?? this.defaultProfileId,
      profiles: profiles ?? this.profiles,
      environmentOverlay: environmentOverlay ?? this.environmentOverlay,
      loginShell: loginShell ?? this.loginShell,
      interactive: interactive ?? this.interactive,
      timeout: timeout ?? this.timeout,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': 1,
      'defaultProfileId': defaultProfileId,
      'profiles': profiles
          .map((profile) => profile.toJson())
          .toList(growable: false),
      'environmentOverlay': environmentOverlay,
      'loginShell': loginShell,
      'interactive': interactive,
      'timeoutMs': timeout.inMilliseconds,
    };
  }
}

class ShellProfileConfiguration {
  const ShellProfileConfiguration({
    required this.id,
    required this.executablePath,
    required this.family,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
  });

  final String id;
  final String executablePath;
  final ShellFamily family;
  final List<String> arguments;
  final Map<String, String> environment;

  factory ShellProfileConfiguration.fromJson(Map<String, Object?> json) {
    final arguments = json['arguments'];
    return ShellProfileConfiguration(
      id: json['id'] as String? ?? 'default',
      executablePath: json['executablePath'] as String? ?? '',
      family: shellFamilyFromWireValue(json['family'] as String?),
      arguments: arguments is List
          ? arguments.map((value) => value.toString()).toList(growable: false)
          : const <String>[],
      environment: _stringMapFromJson(json['environment']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'executablePath': executablePath,
      'family': family.wireValue,
      'arguments': arguments,
      'environment': environment,
    };
  }
}

ShellFamily shellFamilyFromWireValue(String? value) {
  return switch (value) {
    'bash' => ShellFamily.bash,
    'sh' => ShellFamily.sh,
    'zsh' => ShellFamily.zsh,
    'fish' => ShellFamily.fish,
    'powershell' => ShellFamily.powershell,
    'cmd' => ShellFamily.cmd,
    _ => ShellFamily.unknown,
  };
}

ShellProfileConfiguration? _shellProfileConfigurationFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return ShellProfileConfiguration.fromJson(value);
  }
  if (value is Map) {
    return ShellProfileConfiguration.fromJson(
      value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
  }
  return null;
}

Map<String, String> _stringMapFromJson(Object? value) {
  if (value is Map<String, String>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, value) => MapEntry<String, String>(
        key.toString(),
        value.toString(),
      ),
    );
  }
  return const <String, String>{};
}
