import 'dart:async';
import 'dart:io';

import 'shell_facts.dart';
import 'shell_prober.dart';

class LocalShellProber implements ShellProber {
  const LocalShellProber({
    this.targetId = 'local',
    this.operatingSystem,
    this.environment,
    this.architectureReader,
    this.osReleaseReader,
    this.executableExists,
    this.clock,
  });

  final String targetId;
  final String? operatingSystem;
  final Map<String, String>? environment;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final Future<bool> Function(String path)? executableExists;
  final DateTime Function()? clock;

  @override
  Future<ShellFacts> probe() async {
    final detectedAt = (clock ?? DateTime.now)().toUtc();
    final env = environment ?? Platform.environment;
    final os = (operatingSystem ?? Platform.operatingSystem).toLowerCase();
    final osRelease = await _readOsRelease();
    final architecture = (await _readArchitecture()) ?? 'unknown';
    final distributionId = osRelease['ID']?.toLowerCase() ?? 'unknown';
    final distributionName = osRelease['PRETTY_NAME'] ?? distributionId;
    final defaultShellPath = env['SHELL'];
    final availableShells = await _detectAvailableShells(defaultShellPath);

    return ShellFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: distributionId,
      distributionName: distributionName,
      architecture: architecture,
      providerKind: ShellProviderKind.local,
      availableShells: availableShells,
      defaultShellPath: defaultShellPath,
      supportsPty: os == 'linux' || os == 'macos',
      supportsLoginShell: os == 'linux' || os == 'macos',
      supportsInteractiveShell: availableShells.isNotEmpty,
      scriptExtension: os == 'windows' ? '.cmd' : '.sh',
      detectedAt: detectedAt,
      entries: ShellFacts.buildEntries(
        targetId: targetId,
        operatingSystem: os,
        distributionId: distributionId,
        distributionName: distributionName,
        architecture: architecture,
        providerKind: ShellProviderKind.local,
        availableShells: availableShells,
        defaultShellPath: defaultShellPath,
        supportsPty: os == 'linux' || os == 'macos',
        supportsLoginShell: os == 'linux' || os == 'macos',
        supportsInteractiveShell: availableShells.isNotEmpty,
        scriptExtension: os == 'windows' ? '.cmd' : '.sh',
        source: 'prober',
        detectedAt: detectedAt,
      ),
    );
  }

  Future<List<ShellExecutableFact>> _detectAvailableShells(
    String? defaultShellPath,
  ) async {
    final candidates = <String>[
      if (defaultShellPath != null && defaultShellPath.isNotEmpty)
        defaultShellPath,
      '/bin/bash',
      '/usr/bin/bash',
      '/bin/sh',
      '/usr/bin/sh',
      '/bin/zsh',
      '/usr/bin/zsh',
      '/usr/bin/fish',
    ];
    final seen = <String>{};
    final shells = <ShellExecutableFact>[];
    for (final path in candidates) {
      if (!seen.add(path)) {
        continue;
      }
      if (!await _exists(path)) {
        continue;
      }
      shells.add(
        ShellExecutableFact(
          path: path,
          family: _familyForPath(path),
          isDefault: path == defaultShellPath,
        ),
      );
    }
    return shells;
  }

  Future<bool> _exists(String path) async {
    final checker = executableExists;
    if (checker != null) {
      return checker(path);
    }
    return File(path).exists();
  }

  ShellFamily _familyForPath(String path) {
    final name = path.split('/').last.toLowerCase();
    if (name.contains('bash')) {
      return ShellFamily.bash;
    }
    if (name == 'sh' || name.endsWith('dash')) {
      return ShellFamily.sh;
    }
    if (name.contains('zsh')) {
      return ShellFamily.zsh;
    }
    if (name.contains('fish')) {
      return ShellFamily.fish;
    }
    if (name.contains('powershell') || name == 'pwsh') {
      return ShellFamily.powershell;
    }
    if (name == 'cmd.exe' || name == 'cmd') {
      return ShellFamily.cmd;
    }
    return ShellFamily.unknown;
  }

  Future<String?> _readArchitecture() async {
    final reader = architectureReader;
    if (reader != null) {
      return reader();
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
      return null;
    }
    return null;
  }

  Future<Map<String, String>> _readOsRelease() async {
    final reader = osReleaseReader;
    if (reader != null) {
      return reader();
    }
    final file = File('/etc/os-release');
    if (!await file.exists()) {
      return const <String, String>{};
    }
    try {
      return _parseOsRelease(await file.readAsString());
    } on Object {
      return const <String, String>{};
    }
  }

  Map<String, String> _parseOsRelease(String text) {
    final result = <String, String>{};
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
        continue;
      }
      final separator = line.indexOf('=');
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      result[key] = _stripQuotes(value);
    }
    return result;
  }

  String _stripQuotes(String value) {
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return value.substring(1, value.length - 1);
      }
    }
    return value;
  }
}
