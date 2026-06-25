import 'dart:async';
import 'dart:io';

String localOperatingSystem([String? override]) {
  return (override ?? Platform.operatingSystem).toLowerCase();
}

String hostPrettyName(String operatingSystem) {
  return switch (operatingSystem) {
    'windows' => 'Windows',
    'macos' => 'macOS',
    'ios' => 'iOS',
    'android' => 'Android',
    'linux' => 'Linux',
    _ => operatingSystem,
  };
}

Future<String?> readHostArchitecture({
  String? operatingSystem,
  Future<String?> Function()? architectureReader,
  Map<String, String>? environment,
}) async {
  final reader = architectureReader;
  if (reader != null) {
    return reader();
  }

  final os = localOperatingSystem(operatingSystem);
  final env = environment ?? Platform.environment;
  if (os == 'windows') {
    return _windowsArchitecture(env);
  }

  try {
    final result = await Process.run(
      'uname',
      const <String>['-m'],
    ).timeout(const Duration(milliseconds: 500));
    if (result.exitCode == 0) {
      return result.stdout.toString().trim().toLowerCase();
    }
  } on Object {
    return _fallbackArchitecture(env);
  }
  return _fallbackArchitecture(env);
}

Future<Map<String, String>> readHostOsRelease({
  String? operatingSystem,
  Future<Map<String, String>> Function()? osReleaseReader,
}) async {
  final reader = osReleaseReader;
  if (reader != null) {
    return reader();
  }

  final os = localOperatingSystem(operatingSystem);
  if (os != 'linux') {
    return <String, String>{'ID': os, 'PRETTY_NAME': hostPrettyName(os)};
  }

  final file = File('/etc/os-release');
  if (!await file.exists()) {
    return const <String, String>{};
  }
  try {
    return parseOsRelease(await file.readAsString());
  } on Object {
    return const <String, String>{};
  }
}

Map<String, String> parseOsRelease(String text) {
  final result = <String, String>{};
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
      continue;
    }
    final separator = line.indexOf('=');
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    result[key] = stripOsReleaseQuotes(value);
  }
  return result;
}

String stripOsReleaseQuotes(String value) {
  if (value.length >= 2) {
    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}

String windowsCompatibleArchitecture(String architecture) {
  final normalized = architecture.trim().toLowerCase();
  return switch (normalized) {
    'amd64' || 'x64' || 'x86_64' => 'x64',
    'arm64' || 'aarch64' => 'arm64',
    'x86' || 'i386' || 'i686' => 'x86',
    _ => normalized,
  };
}

String windowsCompatibilityTarget(String architecture) {
  final arch = windowsCompatibleArchitecture(architecture);
  if (arch.isEmpty || arch == 'unknown') {
    return 'windows-generic';
  }
  return 'windows-$arch';
}

String? _windowsArchitecture(Map<String, String> environment) {
  return _normalizeWindowsArchitecture(
        environment['PROCESSOR_ARCHITEW6432'],
      ) ??
      _normalizeWindowsArchitecture(environment['PROCESSOR_ARCHITECTURE']) ??
      _fallbackArchitecture(environment);
}

String? _fallbackArchitecture(Map<String, String> environment) {
  return _normalizeWindowsArchitecture(environment['MSYSTEM_CARCH']) ??
      _normalizeWindowsArchitecture(environment['HOSTTYPE']);
}

String? _normalizeWindowsArchitecture(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return windowsCompatibleArchitecture(value);
}
