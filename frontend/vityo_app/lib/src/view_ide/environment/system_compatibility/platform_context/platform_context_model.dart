import '../clipboard/clipboard_facts.dart';
import '../file_system/file_system_facts.dart';
import '../local_service/local_service_facts.dart';
import '../network/network_facts.dart';
import '../notification/notification_facts.dart';
import '../process/process_facts.dart';
import '../pty/pty_facts.dart';
import '../resource/resource_facts.dart';
import '../shell/shell_facts.dart';

class PlatformContextSnapshot {
  const PlatformContextSnapshot({
    required this.schemaVersion,
    required this.targetId,
    required this.fileSystem,
    required this.shell,
    required this.process,
    required this.resource,
    required this.network,
    required this.clipboard,
    required this.notification,
    required this.localService,
    required this.pty,
    required this.loadedAt,
    this.refreshedAt,
    this.source = 'runtime',
    this.overrides = const <String, Object?>{},
  });

  factory PlatformContextSnapshot.compose({
    required FileSystemFacts fileSystem,
    required ShellFacts shell,
    ProcessFacts? process,
    ResourceFacts? resource,
    NetworkFacts? network,
    ClipboardFacts? clipboard,
    NotificationFacts? notification,
    LocalServiceFacts? localService,
    PtyFacts? pty,
    String schemaVersion = 'vityo.platform-context.v1',
    String targetId = 'local',
    String source = 'prober',
    DateTime? loadedAt,
    DateTime? refreshedAt,
    Map<String, Object?> overrides = const <String, Object?>{},
  }) {
    final now = DateTime.now().toUtc();
    final normalizedFileSystem = _retargetFileSystemFacts(fileSystem, targetId);
    final normalizedShell = _retargetShellFacts(shell, targetId);
    return PlatformContextSnapshot(
      schemaVersion: schemaVersion,
      targetId: targetId,
      fileSystem: normalizedFileSystem,
      shell: normalizedShell,
      process: process == null
          ? _defaultProcessFacts(normalizedFileSystem)
          : _retargetProcessFacts(process, targetId, normalizedFileSystem),
      resource: resource == null
          ? _defaultResourceFacts(normalizedFileSystem)
          : _retargetResourceFacts(resource, targetId, normalizedFileSystem),
      network: network == null
          ? _defaultNetworkFacts(normalizedFileSystem)
          : _retargetNetworkFacts(network, targetId, normalizedFileSystem),
      clipboard: clipboard == null
          ? _defaultClipboardFacts(normalizedFileSystem)
          : _retargetClipboardFacts(clipboard, targetId, normalizedFileSystem),
      notification: notification == null
          ? _defaultNotificationFacts(normalizedFileSystem)
          : _retargetNotificationFacts(
              notification,
              targetId,
              normalizedFileSystem,
            ),
      localService: localService == null
          ? _defaultLocalServiceFacts(normalizedFileSystem)
          : _retargetLocalServiceFacts(
              localService,
              targetId,
              normalizedFileSystem,
            ),
      pty: pty == null
          ? _defaultPtyFacts(normalizedFileSystem, normalizedShell)
          : _retargetPtyFacts(
              pty,
              targetId,
              normalizedFileSystem,
              normalizedShell,
            ),
      loadedAt: loadedAt ?? now,
      refreshedAt: refreshedAt ?? now,
      source: source,
      overrides: Map<String, Object?>.unmodifiable(overrides),
    );
  }

  factory PlatformContextSnapshot.fromJson(Map<String, Object?> json) {
    final targetId = json['targetId'] as String? ?? 'local';
    final fileSystem = _retargetFileSystemFacts(
      _fileSystemFactsFromJson(_asMap(json['fileSystem'])),
      targetId,
    );
    final shell = _retargetShellFacts(
      _shellFactsFromJson(_asMap(json['shell'])),
      targetId,
    );
    return PlatformContextSnapshot(
      schemaVersion:
          json['schemaVersion'] as String? ?? 'vityo.platform-context.v1',
      targetId: targetId,
      fileSystem: fileSystem,
      shell: shell,
      process: _processFactsFromJson(_asMap(json['process']), fileSystem),
      resource: _resourceFactsFromJson(_asMap(json['resource']), fileSystem),
      network: _networkFactsFromJson(_asMap(json['network']), fileSystem),
      clipboard: _clipboardFactsFromJson(_asMap(json['clipboard']), fileSystem),
      notification: _notificationFactsFromJson(
        _asMap(json['notification']),
        fileSystem,
      ),
      localService: _localServiceFactsFromJson(
        _asMap(json['localService']),
        fileSystem,
      ),
      pty: _ptyFactsFromJson(_asMap(json['pty']), fileSystem, shell),
      loadedAt: _dateTimeFromJson(json['loadedAt']) ?? DateTime.now().toUtc(),
      refreshedAt: _dateTimeFromJson(json['refreshedAt']),
      source: json['source'] as String? ?? 'config',
      overrides: Map<String, Object?>.unmodifiable(_asMap(json['overrides'])),
    );
  }

  final String schemaVersion;
  final String targetId;
  final FileSystemFacts fileSystem;
  final ShellFacts shell;
  final ProcessFacts process;
  final ResourceFacts resource;
  final NetworkFacts network;
  final ClipboardFacts clipboard;
  final NotificationFacts notification;
  final LocalServiceFacts localService;
  final PtyFacts pty;
  final DateTime loadedAt;
  final DateTime? refreshedAt;
  final String source;
  final Map<String, Object?> overrides;

  bool get supportsLinuxDebianArmTarget {
    return fileSystem.supportsLinuxDebianArmTarget &&
        shell.supportsLinuxDebianArmTarget &&
        process.supportsLinuxDebianArmTarget &&
        resource.supportsLinuxDebianArmTarget &&
        network.supportsLinuxDebianArmTarget &&
        clipboard.supportsLinuxDebianArmTarget &&
        notification.supportsLinuxDebianArmTarget &&
        localService.supportsLinuxDebianArmTarget &&
        pty.supportsLinuxDebianArmTarget;
  }

  String get environmentPathListSeparator {
    if (fileSystem.operatingSystem.toLowerCase() == 'windows' ||
        fileSystem.pathStyle == FileSystemPathStyle.windows) {
      return ';';
    }
    return ':';
  }

  PlatformContextSnapshot copyWith({
    String? schemaVersion,
    String? targetId,
    FileSystemFacts? fileSystem,
    ShellFacts? shell,
    ProcessFacts? process,
    ResourceFacts? resource,
    NetworkFacts? network,
    ClipboardFacts? clipboard,
    NotificationFacts? notification,
    LocalServiceFacts? localService,
    PtyFacts? pty,
    DateTime? loadedAt,
    DateTime? refreshedAt,
    String? source,
    Map<String, Object?>? overrides,
  }) {
    final effectiveTargetId = targetId ?? this.targetId;
    final normalizedFileSystem = _retargetFileSystemFacts(
      fileSystem ?? this.fileSystem,
      effectiveTargetId,
    );
    final normalizedShell = _retargetShellFacts(
      shell ?? this.shell,
      effectiveTargetId,
    );
    return PlatformContextSnapshot(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      targetId: effectiveTargetId,
      fileSystem: normalizedFileSystem,
      shell: normalizedShell,
      process: _retargetProcessFacts(
        process ?? this.process,
        effectiveTargetId,
        normalizedFileSystem,
      ),
      resource: _retargetResourceFacts(
        resource ?? this.resource,
        effectiveTargetId,
        normalizedFileSystem,
      ),
      network: _retargetNetworkFacts(
        network ?? this.network,
        effectiveTargetId,
        normalizedFileSystem,
      ),
      clipboard: _retargetClipboardFacts(
        clipboard ?? this.clipboard,
        effectiveTargetId,
        normalizedFileSystem,
      ),
      notification: _retargetNotificationFacts(
        notification ?? this.notification,
        effectiveTargetId,
        normalizedFileSystem,
      ),
      localService: _retargetLocalServiceFacts(
        localService ?? this.localService,
        effectiveTargetId,
        normalizedFileSystem,
      ),
      pty: _retargetPtyFacts(
        pty ?? this.pty,
        effectiveTargetId,
        normalizedFileSystem,
        normalizedShell,
      ),
      loadedAt: loadedAt ?? this.loadedAt,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      source: source ?? this.source,
      overrides: overrides == null
          ? this.overrides
          : Map<String, Object?>.unmodifiable(overrides),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'targetId': targetId,
      'source': source,
      'loadedAt': loadedAt.toIso8601String(),
      if (refreshedAt != null) 'refreshedAt': refreshedAt!.toIso8601String(),
      'fileSystem': fileSystem.toJson(),
      'shell': shell.toJson(),
      'process': process.toJson(),
      'resource': resource.toJson(),
      'network': _networkFactsToJson(network),
      'clipboard': _clipboardFactsToJson(clipboard),
      'notification': _notificationFactsToJson(notification),
      'localService': _localServiceFactsToJson(localService),
      'pty': pty.toJson(),
      'overrides': overrides,
    };
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
    }
    return const <String, Object?>{};
  }

  static DateTime? _dateTimeFromJson(Object? value) {
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  static bool _boolValue(Object? value, bool fallback) {
    return value is bool ? value : fallback;
  }

  static int _intValue(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) {
      return const <String, String>{};
    }
    return Map<String, String>.unmodifiable(
      value.map((key, value) => MapEntry(key.toString(), value.toString())),
    );
  }

  static Map<String, Object?> _withTargetId(
    Map<String, Object?> json,
    String targetId,
  ) {
    return <String, Object?>{...json, 'targetId': targetId};
  }

  static FileSystemFacts _retargetFileSystemFacts(
    FileSystemFacts facts,
    String targetId,
  ) {
    if (facts.targetId == targetId) {
      return facts;
    }
    return _fileSystemFactsFromJson(_withTargetId(facts.toJson(), targetId));
  }

  static ShellFacts _retargetShellFacts(ShellFacts facts, String targetId) {
    if (facts.targetId == targetId) {
      return facts;
    }
    return _shellFactsFromJson(_withTargetId(facts.toJson(), targetId));
  }

  static ProcessFacts _retargetProcessFacts(
    ProcessFacts facts,
    String targetId,
    FileSystemFacts host,
  ) {
    if (facts.targetId == targetId) {
      return facts;
    }
    return _processFactsFromJson(_withTargetId(facts.toJson(), targetId), host);
  }

  static ResourceFacts _retargetResourceFacts(
    ResourceFacts facts,
    String targetId,
    FileSystemFacts host,
  ) {
    if (facts.targetId == targetId) {
      return facts;
    }
    return _resourceFactsFromJson(
      _withTargetId(facts.toJson(), targetId),
      host,
    );
  }

  static NetworkFacts _retargetNetworkFacts(
    NetworkFacts facts,
    String targetId,
    FileSystemFacts host,
  ) {
    if (facts.targetId == targetId) {
      return facts;
    }
    return _networkFactsFromJson(
      _withTargetId(_networkFactsToJson(facts), targetId),
      host,
    );
  }

  static ClipboardFacts _retargetClipboardFacts(
    ClipboardFacts facts,
    String targetId,
    FileSystemFacts host,
  ) {
    if (facts.targetId == targetId) {
      return facts;
    }
    return _clipboardFactsFromJson(
      _withTargetId(_clipboardFactsToJson(facts), targetId),
      host,
    );
  }

  static NotificationFacts _retargetNotificationFacts(
    NotificationFacts facts,
    String targetId,
    FileSystemFacts host,
  ) {
    if (facts.targetId == targetId) {
      return facts;
    }
    return _notificationFactsFromJson(
      _withTargetId(_notificationFactsToJson(facts), targetId),
      host,
    );
  }

  static LocalServiceFacts _retargetLocalServiceFacts(
    LocalServiceFacts facts,
    String targetId,
    FileSystemFacts host,
  ) {
    if (facts.targetId == targetId) {
      return facts;
    }
    return _localServiceFactsFromJson(
      _withTargetId(_localServiceFactsToJson(facts), targetId),
      host,
    );
  }

  static PtyFacts _retargetPtyFacts(
    PtyFacts facts,
    String targetId,
    FileSystemFacts host,
    ShellFacts shell,
  ) {
    if (facts.targetId == targetId) {
      return facts;
    }
    return _ptyFactsFromJson(
      _withTargetId(facts.toJson(), targetId),
      host,
      shell,
    );
  }

  static FileSystemFacts _fileSystemFactsFromJson(Map<String, Object?> json) {
    final targetId = json['targetId'] as String? ?? 'local';
    final operatingSystem = json['operatingSystem'] as String? ?? 'unknown';
    final distributionId = json['distributionId'] as String? ?? 'unknown';
    final distributionName = json['distributionName'] as String? ?? 'Unknown';
    final architecture = json['architecture'] as String? ?? 'unknown';
    final pathStyle = _fileSystemPathStyle(json['pathStyle'] as String?);
    final pathSeparator = json['pathSeparator'] as String? ?? '/';
    final providerKind = _fileSystemProviderKind(
      json['providerKind'] as String?,
    );
    final watchSupport = _fileSystemWatchSupport(
      json['watchSupport'] as String?,
    );
    final caseSensitive = json['caseSensitive'] as bool? ?? true;
    final supportsFileUri = json['supportsFileUri'] as bool? ?? false;
    final supportsSymbolicLinks =
        json['supportsSymbolicLinks'] as bool? ?? false;
    final supportsAtomicWrite = json['supportsAtomicWrite'] as bool? ?? false;
    final detectedAt = _dateTimeFromJson(json['detectedAt']);
    return FileSystemFacts(
      targetId: targetId,
      operatingSystem: operatingSystem,
      distributionId: distributionId,
      distributionName: distributionName,
      architecture: architecture,
      pathStyle: pathStyle,
      pathSeparator: pathSeparator,
      providerKind: providerKind,
      watchSupport: watchSupport,
      caseSensitive: caseSensitive,
      supportsFileUri: supportsFileUri,
      supportsSymbolicLinks: supportsSymbolicLinks,
      supportsAtomicWrite: supportsAtomicWrite,
      detectedAt: detectedAt,
      entries: FileSystemFacts.buildEntries(
        targetId: targetId,
        operatingSystem: operatingSystem,
        distributionId: distributionId,
        distributionName: distributionName,
        architecture: architecture,
        pathStyle: pathStyle,
        pathSeparator: pathSeparator,
        providerKind: providerKind,
        watchSupport: watchSupport,
        caseSensitive: caseSensitive,
        supportsFileUri: supportsFileUri,
        supportsSymbolicLinks: supportsSymbolicLinks,
        supportsAtomicWrite: supportsAtomicWrite,
        source: 'config',
        detectedAt: detectedAt,
      ),
    );
  }

  static ShellFacts _shellFactsFromJson(Map<String, Object?> json) {
    final targetId = json['targetId'] as String? ?? 'local';
    final operatingSystem = json['operatingSystem'] as String? ?? 'unknown';
    final distributionId = json['distributionId'] as String? ?? 'unknown';
    final distributionName = json['distributionName'] as String? ?? 'Unknown';
    final architecture = json['architecture'] as String? ?? 'unknown';
    final providerKind = _shellProviderKind(json['providerKind'] as String?);
    final availableShells = _shellExecutablesFromJson(json['availableShells']);
    final defaultShellPath = json['defaultShellPath'] as String?;
    final supportsPty = json['supportsPty'] as bool? ?? false;
    final supportsLoginShell = json['supportsLoginShell'] as bool? ?? false;
    final supportsInteractiveShell =
        json['supportsInteractiveShell'] as bool? ?? availableShells.isNotEmpty;
    final scriptExtension = json['scriptExtension'] as String? ?? '.sh';
    final detectedAt = _dateTimeFromJson(json['detectedAt']);
    return ShellFacts(
      targetId: targetId,
      operatingSystem: operatingSystem,
      distributionId: distributionId,
      distributionName: distributionName,
      architecture: architecture,
      providerKind: providerKind,
      availableShells: availableShells,
      defaultShellPath: defaultShellPath,
      supportsPty: supportsPty,
      supportsLoginShell: supportsLoginShell,
      supportsInteractiveShell: supportsInteractiveShell,
      scriptExtension: scriptExtension,
      detectedAt: detectedAt,
      entries: ShellFacts.buildEntries(
        targetId: targetId,
        operatingSystem: operatingSystem,
        distributionId: distributionId,
        distributionName: distributionName,
        architecture: architecture,
        providerKind: providerKind,
        availableShells: availableShells,
        defaultShellPath: defaultShellPath,
        supportsPty: supportsPty,
        supportsLoginShell: supportsLoginShell,
        supportsInteractiveShell: supportsInteractiveShell,
        scriptExtension: scriptExtension,
        source: 'config',
        detectedAt: detectedAt,
      ),
    );
  }

  static ProcessFacts _processFactsFromJson(
    Map<String, Object?> json,
    FileSystemFacts host,
  ) {
    if (json.isEmpty) {
      return _defaultProcessFacts(host);
    }
    final detectedAt = _dateTimeFromJson(json['detectedAt']);
    final targetId = json['targetId'] as String? ?? host.targetId;
    final operatingSystem =
        json['operatingSystem'] as String? ?? host.operatingSystem;
    final distributionId =
        json['distributionId'] as String? ?? host.distributionId;
    final distributionName =
        json['distributionName'] as String? ?? host.distributionName;
    final architecture = json['architecture'] as String? ?? host.architecture;
    final providerKind = _processProviderKind(json['providerKind'] as String?);
    final supportsSpawn = _boolValue(json['supportsSpawn'], false);
    final supportsSignals = _boolValue(json['supportsSignals'], false);
    final supportsProcessGroups = _boolValue(
      json['supportsProcessGroups'],
      false,
    );
    final supportsEnvironmentOverlay = _boolValue(
      json['supportsEnvironmentOverlay'],
      false,
    );
    final supportsWorkingDirectory = _boolValue(
      json['supportsWorkingDirectory'],
      false,
    );
    return ProcessFacts(
      targetId: targetId,
      operatingSystem: operatingSystem,
      distributionId: distributionId,
      distributionName: distributionName,
      architecture: architecture,
      providerKind: providerKind,
      supportsSpawn: supportsSpawn,
      supportsSignals: supportsSignals,
      supportsProcessGroups: supportsProcessGroups,
      supportsEnvironmentOverlay: supportsEnvironmentOverlay,
      supportsWorkingDirectory: supportsWorkingDirectory,
      detectedAt: detectedAt,
      entries: ProcessFacts.buildEntries(
        targetId: targetId,
        operatingSystem: operatingSystem,
        distributionId: distributionId,
        distributionName: distributionName,
        architecture: architecture,
        providerKind: providerKind,
        supportsSpawn: supportsSpawn,
        supportsSignals: supportsSignals,
        supportsProcessGroups: supportsProcessGroups,
        supportsEnvironmentOverlay: supportsEnvironmentOverlay,
        supportsWorkingDirectory: supportsWorkingDirectory,
        source: 'config',
        detectedAt: detectedAt,
      ),
    );
  }

  static ResourceFacts _resourceFactsFromJson(
    Map<String, Object?> json,
    FileSystemFacts host,
  ) {
    if (json.isEmpty) {
      return _defaultResourceFacts(host);
    }
    return ResourceFacts(
      targetId: json['targetId'] as String? ?? host.targetId,
      operatingSystem:
          json['operatingSystem'] as String? ?? host.operatingSystem,
      distributionId: json['distributionId'] as String? ?? host.distributionId,
      architecture: json['architecture'] as String? ?? host.architecture,
      providerKind: _resourceProviderKind(json['providerKind'] as String?),
      processorCount: _intValue(json['processorCount'], 1),
      systemTempPath: json['systemTempPath'] as String? ?? '/tmp',
      homePath: json['homePath'] as String?,
      supportsTempDirectory: _boolValue(json['supportsTempDirectory'], false),
      supportsHomeDirectory: _boolValue(json['supportsHomeDirectory'], false),
      supportsStorageProbe: _boolValue(json['supportsStorageProbe'], false),
      detectedAt: _dateTimeFromJson(json['detectedAt']),
    );
  }

  static NetworkFacts _networkFactsFromJson(
    Map<String, Object?> json,
    FileSystemFacts host,
  ) {
    if (json.isEmpty) {
      return _defaultNetworkFacts(host);
    }
    return NetworkFacts(
      targetId: json['targetId'] as String? ?? host.targetId,
      operatingSystem:
          json['operatingSystem'] as String? ?? host.operatingSystem,
      distributionId: json['distributionId'] as String? ?? host.distributionId,
      architecture: json['architecture'] as String? ?? host.architecture,
      providerKind: _networkProviderKind(json['providerKind'] as String?),
      supportsHttpClient: _boolValue(json['supportsHttpClient'], false),
      supportsLoopback: _boolValue(json['supportsLoopback'], false),
      proxyEnvironment: _stringMap(json['proxyEnvironment']),
      detectedAt: _dateTimeFromJson(json['detectedAt']),
    );
  }

  static ClipboardFacts _clipboardFactsFromJson(
    Map<String, Object?> json,
    FileSystemFacts host,
  ) {
    if (json.isEmpty) {
      return _defaultClipboardFacts(host);
    }
    return ClipboardFacts(
      targetId: json['targetId'] as String? ?? host.targetId,
      operatingSystem:
          json['operatingSystem'] as String? ?? host.operatingSystem,
      distributionId: json['distributionId'] as String? ?? host.distributionId,
      architecture: json['architecture'] as String? ?? host.architecture,
      providerKind: _clipboardProviderKind(json['providerKind'] as String?),
      supportsText: _boolValue(json['supportsText'], false),
      supportsSystemClipboard: _boolValue(
        json['supportsSystemClipboard'],
        false,
      ),
      supportsMemoryFallback: _boolValue(json['supportsMemoryFallback'], false),
      detectedAt: _dateTimeFromJson(json['detectedAt']),
    );
  }

  static NotificationFacts _notificationFactsFromJson(
    Map<String, Object?> json,
    FileSystemFacts host,
  ) {
    if (json.isEmpty) {
      return _defaultNotificationFacts(host);
    }
    return NotificationFacts(
      targetId: json['targetId'] as String? ?? host.targetId,
      operatingSystem:
          json['operatingSystem'] as String? ?? host.operatingSystem,
      distributionId: json['distributionId'] as String? ?? host.distributionId,
      architecture: json['architecture'] as String? ?? host.architecture,
      providerKind: _notificationProviderKind(json['providerKind'] as String?),
      supportsDesktopNotifications: _boolValue(
        json['supportsDesktopNotifications'],
        false,
      ),
      supportsInAppFallback: _boolValue(json['supportsInAppFallback'], false),
      detectedAt: _dateTimeFromJson(json['detectedAt']),
    );
  }

  static LocalServiceFacts _localServiceFactsFromJson(
    Map<String, Object?> json,
    FileSystemFacts host,
  ) {
    if (json.isEmpty) {
      return _defaultLocalServiceFacts(host);
    }
    return LocalServiceFacts(
      targetId: json['targetId'] as String? ?? host.targetId,
      operatingSystem:
          json['operatingSystem'] as String? ?? host.operatingSystem,
      distributionId: json['distributionId'] as String? ?? host.distributionId,
      architecture: json['architecture'] as String? ?? host.architecture,
      providerKind: _localServiceProviderKind(json['providerKind'] as String?),
      supportsLoopbackHttpServer: _boolValue(
        json['supportsLoopbackHttpServer'],
        false,
      ),
      supportsEphemeralPort: _boolValue(json['supportsEphemeralPort'], false),
      detectedAt: _dateTimeFromJson(json['detectedAt']),
    );
  }

  static PtyFacts _ptyFactsFromJson(
    Map<String, Object?> json,
    FileSystemFacts host,
    ShellFacts shell,
  ) {
    if (json.isEmpty) {
      return _defaultPtyFacts(host, shell);
    }
    final detectedAt = _dateTimeFromJson(json['detectedAt']);
    final targetId = json['targetId'] as String? ?? host.targetId;
    final operatingSystem =
        json['operatingSystem'] as String? ?? host.operatingSystem;
    final distributionId =
        json['distributionId'] as String? ?? host.distributionId;
    final distributionName =
        json['distributionName'] as String? ?? host.distributionName;
    final architecture = json['architecture'] as String? ?? host.architecture;
    final providerKind = _ptyProviderKind(json['providerKind'] as String?);
    final supportsPty = _boolValue(json['supportsPty'], false);
    final supportsResize = _boolValue(json['supportsResize'], false);
    final supportsRawMode = _boolValue(json['supportsRawMode'], false);
    final supportsSignals = _boolValue(json['supportsSignals'], false);
    final supportsProcessGroup = _boolValue(
      json['supportsProcessGroup'],
      false,
    );
    final supportsConPty = _boolValue(json['supportsConPty'], false);
    final supportsForkPty = _boolValue(json['supportsForkPty'], false);
    final supportsScriptUtility = _boolValue(
      json['supportsScriptUtility'],
      false,
    );
    final scriptUtilityPath = json['scriptUtilityPath'] as String?;
    return PtyFacts(
      targetId: targetId,
      operatingSystem: operatingSystem,
      distributionId: distributionId,
      distributionName: distributionName,
      architecture: architecture,
      providerKind: providerKind,
      supportsPty: supportsPty,
      supportsResize: supportsResize,
      supportsRawMode: supportsRawMode,
      supportsSignals: supportsSignals,
      supportsProcessGroup: supportsProcessGroup,
      supportsConPty: supportsConPty,
      supportsForkPty: supportsForkPty,
      supportsScriptUtility: supportsScriptUtility,
      scriptUtilityPath: scriptUtilityPath,
      detectedAt: detectedAt,
      entries: PtyFacts.buildEntries(
        targetId: targetId,
        operatingSystem: operatingSystem,
        distributionId: distributionId,
        distributionName: distributionName,
        architecture: architecture,
        providerKind: providerKind,
        supportsPty: supportsPty,
        supportsResize: supportsResize,
        supportsRawMode: supportsRawMode,
        supportsSignals: supportsSignals,
        supportsProcessGroup: supportsProcessGroup,
        supportsConPty: supportsConPty,
        supportsForkPty: supportsForkPty,
        supportsScriptUtility: supportsScriptUtility,
        scriptUtilityPath: scriptUtilityPath,
        source: 'config',
        detectedAt: detectedAt,
      ),
    );
  }

  static ProcessFacts _defaultProcessFacts(FileSystemFacts host) {
    if (host.operatingSystem == 'linux') {
      return ProcessFacts.linuxDebianArm(
        targetId: host.targetId,
        architecture: host.architecture,
        detectedAt: host.detectedAt,
      );
    }
    final supportsSpawn =
        host.operatingSystem == 'windows' || host.operatingSystem == 'macos';
    return ProcessFacts(
      targetId: host.targetId,
      operatingSystem: host.operatingSystem,
      distributionId: host.distributionId,
      distributionName: host.distributionName,
      architecture: host.architecture,
      providerKind: ProcessProviderKind.local,
      supportsSpawn: supportsSpawn,
      supportsSignals: host.operatingSystem == 'macos',
      supportsProcessGroups: host.operatingSystem == 'macos',
      supportsEnvironmentOverlay: supportsSpawn,
      supportsWorkingDirectory: supportsSpawn,
      detectedAt: host.detectedAt,
    );
  }

  static ResourceFacts _defaultResourceFacts(FileSystemFacts host) {
    if (host.operatingSystem == 'linux') {
      return ResourceFacts.linuxDebianArm(
        targetId: host.targetId,
        architecture: host.architecture,
        detectedAt: host.detectedAt,
      );
    }
    return ResourceFacts(
      targetId: host.targetId,
      operatingSystem: host.operatingSystem,
      distributionId: host.distributionId,
      architecture: host.architecture,
      providerKind: ResourceProviderKind.local,
      processorCount: 1,
      systemTempPath: host.pathStyle == FileSystemPathStyle.windows
          ? r'C:\Windows\Temp'
          : '/tmp',
      supportsTempDirectory: true,
      supportsHomeDirectory: false,
      supportsStorageProbe: true,
      detectedAt: host.detectedAt,
    );
  }

  static NetworkFacts _defaultNetworkFacts(FileSystemFacts host) {
    if (host.operatingSystem == 'linux') {
      return NetworkFacts.linuxDebianArm(
        targetId: host.targetId,
        architecture: host.architecture,
        detectedAt: host.detectedAt,
      );
    }
    return NetworkFacts(
      targetId: host.targetId,
      operatingSystem: host.operatingSystem,
      distributionId: host.distributionId,
      architecture: host.architecture,
      providerKind: NetworkProviderKind.local,
      supportsHttpClient: true,
      supportsLoopback: true,
      proxyEnvironment: const <String, String>{},
      detectedAt: host.detectedAt,
    );
  }

  static ClipboardFacts _defaultClipboardFacts(FileSystemFacts host) {
    if (host.operatingSystem == 'linux') {
      return ClipboardFacts.linuxDebianArm(
        targetId: host.targetId,
        architecture: host.architecture,
        detectedAt: host.detectedAt,
      );
    }
    final supportsSystemClipboard = host.operatingSystem == 'windows' ||
        host.operatingSystem == 'macos';
    return ClipboardFacts(
      targetId: host.targetId,
      operatingSystem: host.operatingSystem,
      distributionId: host.distributionId,
      architecture: host.architecture,
      providerKind: supportsSystemClipboard
          ? ClipboardProviderKind.system
          : ClipboardProviderKind.memoryFallback,
      supportsText: true,
      supportsSystemClipboard: supportsSystemClipboard,
      supportsMemoryFallback: true,
      detectedAt: host.detectedAt,
    );
  }

  static NotificationFacts _defaultNotificationFacts(FileSystemFacts host) {
    if (host.operatingSystem == 'linux') {
      return NotificationFacts.linuxDebianArm(
        targetId: host.targetId,
        architecture: host.architecture,
        detectedAt: host.detectedAt,
      );
    }
    final supportsDesktopNotifications = host.operatingSystem == 'windows' ||
        host.operatingSystem == 'macos';
    return NotificationFacts(
      targetId: host.targetId,
      operatingSystem: host.operatingSystem,
      distributionId: host.distributionId,
      architecture: host.architecture,
      providerKind: supportsDesktopNotifications
          ? NotificationProviderKind.desktop
          : NotificationProviderKind.inAppFallback,
      supportsDesktopNotifications: supportsDesktopNotifications,
      supportsInAppFallback: true,
      detectedAt: host.detectedAt,
    );
  }

  static LocalServiceFacts _defaultLocalServiceFacts(FileSystemFacts host) {
    if (host.operatingSystem == 'linux') {
      return LocalServiceFacts.linuxDebianArm(
        targetId: host.targetId,
        architecture: host.architecture,
        detectedAt: host.detectedAt,
      );
    }
    return LocalServiceFacts(
      targetId: host.targetId,
      operatingSystem: host.operatingSystem,
      distributionId: host.distributionId,
      architecture: host.architecture,
      providerKind: LocalServiceProviderKind.loopback,
      supportsLoopbackHttpServer: true,
      supportsEphemeralPort: true,
      detectedAt: host.detectedAt,
    );
  }

  static PtyFacts _defaultPtyFacts(FileSystemFacts host, ShellFacts shell) {
    if (host.operatingSystem == 'linux') {
      return PtyFacts.linuxDebianArm(
        targetId: host.targetId,
        architecture: host.architecture,
        scriptUtilityPath: shell.supportsPty ? '/usr/bin/script' : null,
        detectedAt: host.detectedAt,
      );
    }
    final supportsConPty = host.operatingSystem == 'windows' && shell.supportsPty;
    return PtyFacts(
      targetId: host.targetId,
      operatingSystem: host.operatingSystem,
      distributionId: host.distributionId,
      distributionName: host.distributionName,
      architecture: host.architecture,
      providerKind: supportsConPty
          ? PtyProviderKind.conPty
          : PtyProviderKind.unsupported,
      supportsPty: supportsConPty,
      supportsResize: supportsConPty,
      supportsRawMode: supportsConPty,
      supportsSignals: false,
      supportsProcessGroup: false,
      supportsConPty: supportsConPty,
      supportsForkPty: false,
      supportsScriptUtility: false,
      detectedAt: host.detectedAt,
    );
  }

  static Map<String, Object?> _networkFactsToJson(NetworkFacts facts) {
    return <String, Object?>{
      'targetId': facts.targetId,
      'operatingSystem': facts.operatingSystem,
      'distributionId': facts.distributionId,
      'architecture': facts.architecture,
      'providerKind': facts.providerKind.wireValue,
      'supportsHttpClient': facts.supportsHttpClient,
      'supportsLoopback': facts.supportsLoopback,
      'proxyEnvironment': facts.proxyEnvironment,
      'compatibilityTarget': facts.compatibilityTarget,
      if (facts.detectedAt != null)
        'detectedAt': facts.detectedAt!.toIso8601String(),
    };
  }

  static Map<String, Object?> _clipboardFactsToJson(ClipboardFacts facts) {
    return <String, Object?>{
      'targetId': facts.targetId,
      'operatingSystem': facts.operatingSystem,
      'distributionId': facts.distributionId,
      'architecture': facts.architecture,
      'providerKind': facts.providerKind.wireValue,
      'supportsText': facts.supportsText,
      'supportsSystemClipboard': facts.supportsSystemClipboard,
      'supportsMemoryFallback': facts.supportsMemoryFallback,
      'compatibilityTarget': facts.compatibilityTarget,
      if (facts.detectedAt != null)
        'detectedAt': facts.detectedAt!.toIso8601String(),
    };
  }

  static Map<String, Object?> _notificationFactsToJson(
    NotificationFacts facts,
  ) {
    return <String, Object?>{
      'targetId': facts.targetId,
      'operatingSystem': facts.operatingSystem,
      'distributionId': facts.distributionId,
      'architecture': facts.architecture,
      'providerKind': facts.providerKind.wireValue,
      'supportsDesktopNotifications': facts.supportsDesktopNotifications,
      'supportsInAppFallback': facts.supportsInAppFallback,
      'compatibilityTarget': facts.compatibilityTarget,
      if (facts.detectedAt != null)
        'detectedAt': facts.detectedAt!.toIso8601String(),
    };
  }

  static Map<String, Object?> _localServiceFactsToJson(
    LocalServiceFacts facts,
  ) {
    return <String, Object?>{
      'targetId': facts.targetId,
      'operatingSystem': facts.operatingSystem,
      'distributionId': facts.distributionId,
      'architecture': facts.architecture,
      'providerKind': facts.providerKind.wireValue,
      'supportsLoopbackHttpServer': facts.supportsLoopbackHttpServer,
      'supportsEphemeralPort': facts.supportsEphemeralPort,
      'compatibilityTarget': facts.compatibilityTarget,
      if (facts.detectedAt != null)
        'detectedAt': facts.detectedAt!.toIso8601String(),
    };
  }

  static List<ShellExecutableFact> _shellExecutablesFromJson(Object? value) {
    if (value is! List) {
      return const <ShellExecutableFact>[];
    }
    return value
        .whereType<Map>()
        .map(
          (entry) => ShellExecutableFact(
            path: entry['path']?.toString() ?? '',
            family: _shellFamily(entry['family']?.toString()),
            version: entry['version']?.toString(),
            isDefault: entry['isDefault'] as bool? ?? false,
          ),
        )
        .where((entry) => entry.path.isNotEmpty)
        .toList(growable: false);
  }

  static FileSystemPathStyle _fileSystemPathStyle(String? value) {
    return switch (value) {
      'posix' => FileSystemPathStyle.posix,
      'windows' => FileSystemPathStyle.windows,
      _ => FileSystemPathStyle.unknown,
    };
  }

  static FileSystemProviderKind _fileSystemProviderKind(String? value) {
    return switch (value) {
      'local' => FileSystemProviderKind.local,
      'remote' => FileSystemProviderKind.remote,
      'browser-sandbox' => FileSystemProviderKind.browserSandbox,
      'virtual' => FileSystemProviderKind.virtual,
      'hosted' => FileSystemProviderKind.hosted,
      _ => FileSystemProviderKind.unknown,
    };
  }

  static FileSystemWatchSupport _fileSystemWatchSupport(String? value) {
    return switch (value) {
      'none' => FileSystemWatchSupport.none,
      'directory' => FileSystemWatchSupport.directory,
      'recursive' => FileSystemWatchSupport.recursive,
      'polling' => FileSystemWatchSupport.polling,
      _ => FileSystemWatchSupport.unknown,
    };
  }

  static ShellProviderKind _shellProviderKind(String? value) {
    return switch (value) {
      'local' => ShellProviderKind.local,
      'hosted' => ShellProviderKind.hosted,
      'virtual' => ShellProviderKind.virtual,
      _ => ShellProviderKind.unknown,
    };
  }

  static ProcessProviderKind _processProviderKind(String? value) {
    return switch (value) {
      'local' => ProcessProviderKind.local,
      'hosted' => ProcessProviderKind.hosted,
      'virtual' => ProcessProviderKind.virtual,
      _ => ProcessProviderKind.unknown,
    };
  }

  static ResourceProviderKind _resourceProviderKind(String? value) {
    return switch (value) {
      'local' => ResourceProviderKind.local,
      'hosted' => ResourceProviderKind.hosted,
      'virtual' => ResourceProviderKind.virtual,
      _ => ResourceProviderKind.unknown,
    };
  }

  static NetworkProviderKind _networkProviderKind(String? value) {
    return switch (value) {
      'local' => NetworkProviderKind.local,
      'hosted' => NetworkProviderKind.hosted,
      'virtual' => NetworkProviderKind.virtual,
      _ => NetworkProviderKind.unknown,
    };
  }

  static ClipboardProviderKind _clipboardProviderKind(String? value) {
    return switch (value) {
      'system' => ClipboardProviderKind.system,
      'memory-fallback' => ClipboardProviderKind.memoryFallback,
      _ => ClipboardProviderKind.unsupported,
    };
  }

  static NotificationProviderKind _notificationProviderKind(String? value) {
    return switch (value) {
      'desktop' => NotificationProviderKind.desktop,
      'in-app-fallback' => NotificationProviderKind.inAppFallback,
      _ => NotificationProviderKind.unsupported,
    };
  }

  static LocalServiceProviderKind _localServiceProviderKind(String? value) {
    return switch (value) {
      'loopback' => LocalServiceProviderKind.loopback,
      'hosted' => LocalServiceProviderKind.hosted,
      _ => LocalServiceProviderKind.unsupported,
    };
  }

  static PtyProviderKind _ptyProviderKind(String? value) {
    return switch (value) {
      'posix-pty' => PtyProviderKind.posixPty,
      'conpty' => PtyProviderKind.conPty,
      'script-utility' => PtyProviderKind.scriptUtility,
      'hosted' => PtyProviderKind.hosted,
      'unsupported' => PtyProviderKind.unsupported,
      _ => PtyProviderKind.unknown,
    };
  }

  static ShellFamily _shellFamily(String? value) {
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
}
