import 'dart:async';
import 'dart:io';

import 'file_system_facts.dart';
import 'file_system_prober.dart';

class LocalFileSystemProber implements FileSystemProber {
  const LocalFileSystemProber({
    this.targetId = 'local',
    this.operatingSystem,
    this.architectureReader,
    this.osReleaseReader,
    this.clock,
  });

  final String targetId;
  final String? operatingSystem;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final DateTime Function()? clock;

  @override
  Future<FileSystemFacts> probe() async {
    final detectedAt = (clock ?? DateTime.now)().toUtc();
    final os = (operatingSystem ?? Platform.operatingSystem).toLowerCase();
    final osRelease = await _readOsRelease();
    final architecture = (await _readArchitecture()) ?? 'unknown';
    final distributionId = osRelease['ID']?.toLowerCase() ?? 'unknown';
    final distributionName = osRelease['PRETTY_NAME'] ?? distributionId;
    final pathStyle = os == 'windows'
        ? FileSystemPathStyle.windows
        : FileSystemPathStyle.posix;
    final pathSeparator = os == 'windows' ? r'\' : '/';
    final watchSupport = os == 'linux'
        ? FileSystemWatchSupport.directory
        : FileSystemWatchSupport.unknown;
    final caseSensitive = os == 'linux' || os == 'android';
    final supportsSymbolicLinks = os == 'linux' || os == 'macos';
    final supportsAtomicWrite = os == 'linux' || os == 'macos' || os == 'windows';

    return FileSystemFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: distributionId,
      distributionName: distributionName,
      architecture: architecture,
      pathStyle: pathStyle,
      pathSeparator: pathSeparator,
      providerKind: FileSystemProviderKind.local,
      watchSupport: watchSupport,
      caseSensitive: caseSensitive,
      supportsFileUri: true,
      supportsSymbolicLinks: supportsSymbolicLinks,
      supportsAtomicWrite: supportsAtomicWrite,
      detectedAt: detectedAt,
      entries: FileSystemFacts.buildEntries(
        targetId: targetId,
        operatingSystem: os,
        distributionId: distributionId,
        distributionName: distributionName,
        architecture: architecture,
        pathStyle: pathStyle,
        pathSeparator: pathSeparator,
        providerKind: FileSystemProviderKind.local,
        watchSupport: watchSupport,
        caseSensitive: caseSensitive,
        supportsFileUri: true,
        supportsSymbolicLinks: supportsSymbolicLinks,
        supportsAtomicWrite: supportsAtomicWrite,
        source: 'prober',
        detectedAt: detectedAt,
      ),
    );
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
