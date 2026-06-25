import 'dart:async';
import 'dart:io';

import '../host_platform_io.dart';
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
    final os = localOperatingSystem(operatingSystem);
    final osRelease = await readHostOsRelease(
      operatingSystem: operatingSystem,
      osReleaseReader: osReleaseReader,
    );
    final architecture =
        (await readHostArchitecture(
          operatingSystem: operatingSystem,
          architectureReader: architectureReader,
          environment: env,
        )) ??
        'unknown';
    final distributionId = osRelease['ID']?.toLowerCase() ?? 'unknown';
    final distributionName = osRelease['PRETTY_NAME'] ?? distributionId;
    final preferredShellPath = env['SHELL'];
    final availableShells = await _detectAvailableShells(
      preferredShellPath,
      os,
      env,
    );
    final defaultShellPath = preferredShellPath?.isNotEmpty == true
        ? preferredShellPath
        : availableShells.isEmpty
        ? null
        : availableShells.first.path;
    final scriptExtension =
        availableShells.isNotEmpty &&
            availableShells.first.path == defaultShellPath &&
            availableShells.first.family == ShellFamily.powershell
        ? '.ps1'
        : os == 'windows'
        ? '.cmd'
        : '.sh';

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
      scriptExtension: scriptExtension,
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
        scriptExtension: scriptExtension,
        source: 'prober',
        detectedAt: detectedAt,
      ),
    );
  }

  Future<List<ShellExecutableFact>> _detectAvailableShells(
    String? defaultShellPath,
    String operatingSystem,
    Map<String, String> environment,
  ) async {
    final candidates = operatingSystem == 'windows'
        ? _windowsShellCandidates(defaultShellPath, environment)
        : <String>[
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
      if (path.isEmpty || !seen.add(path.toLowerCase())) {
        continue;
      }
      final resolvedPath = await _resolveExecutable(path, operatingSystem, environment);
      if (resolvedPath == null) {
        continue;
      }
      shells.add(
        ShellExecutableFact(
          path: resolvedPath,
          family: _familyForPath(resolvedPath),
          isDefault: resolvedPath == defaultShellPath,
        ),
      );
    }
    return shells;
  }

  List<String> _windowsShellCandidates(
    String? defaultShellPath,
    Map<String, String> environment,
  ) {
    final systemRoot = environment['SystemRoot'] ?? environment['WINDIR'];
    return <String>[
      if (defaultShellPath != null && defaultShellPath.isNotEmpty)
        defaultShellPath,
      if (systemRoot != null)
        '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      r'C:\Program Files\PowerShell\7\pwsh.exe',
      'pwsh.exe',
      'powershell.exe',
      if (environment['ComSpec']?.isNotEmpty == true) environment['ComSpec']!,
      if (systemRoot != null) '$systemRoot\\System32\\cmd.exe',
      'cmd.exe',
    ];
  }

  Future<String?> _resolveExecutable(
    String path,
    String operatingSystem,
    Map<String, String> environment,
  ) async {
    final checker = executableExists;
    if (checker != null) {
      return await checker(path) ? path : null;
    }
    if (await File(path).exists()) {
      return path;
    }
    if (operatingSystem != 'windows' || _isQualifiedPath(path)) {
      return null;
    }
    for (final candidate in _pathSearchCandidates(path, environment)) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  bool _isQualifiedPath(String path) {
    return path.contains('/') ||
        path.contains(r'\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(path);
  }

  Iterable<String> _pathSearchCandidates(
    String executableName,
    Map<String, String> environment,
  ) sync* {
    final pathValue = environment['Path'] ?? environment['PATH'] ?? '';
    final extensions = <String>[
      '',
      ...((environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD')
          .split(';')
          .where((value) => value.isNotEmpty)),
    ];
    final hasExtension = RegExp(r'\.[A-Za-z0-9]+$').hasMatch(executableName);
    for (final directory in pathValue.split(';')) {
      if (directory.isEmpty) {
        continue;
      }
      if (hasExtension) {
        yield '$directory\\$executableName';
      } else {
        for (final extension in extensions) {
          yield '$directory\\$executableName$extension';
        }
      }
    }
  }

  ShellFamily _familyForPath(String path) {
    final name = path.split(RegExp(r'[\\/]')).last.toLowerCase();
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
    if (name.contains('powershell') || name == 'pwsh' || name == 'pwsh.exe') {
      return ShellFamily.powershell;
    }
    if (name == 'cmd.exe' || name == 'cmd') {
      return ShellFamily.cmd;
    }
    return ShellFamily.unknown;
  }

}
