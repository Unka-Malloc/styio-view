import 'toolchain_catalog.dart';

class ToolchainRequirement {
  const ToolchainRequirement({
    required this.kind,
    this.id,
    this.version,
    this.channel,
    this.metadata = const <String, Object?>{},
  });

  final ToolchainKind kind;
  final String? id;
  final String? version;
  final String? channel;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (channel != null) 'channel': channel,
      'metadata': metadata,
    };
  }
}

enum ToolchainResolutionStatus {
  resolved,
  missingKind,
  missingId,
  versionMismatch,
  channelMismatch,
  metadataMismatch,
}

class ToolchainResolution {
  const ToolchainResolution({
    required this.status,
    required this.requirement,
    this.descriptor,
    this.message,
  });

  final ToolchainResolutionStatus status;
  final ToolchainRequirement requirement;
  final ToolchainDescriptor? descriptor;
  final String? message;

  bool get resolved => status == ToolchainResolutionStatus.resolved;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'requirement': requirement.toJson(),
      if (descriptor != null) 'descriptor': descriptor!.toJson(),
      if (message != null) 'message': message,
      'resolved': resolved,
    };
  }
}

class ToolchainResolver {
  const ToolchainResolver();

  ToolchainResolution resolve(
    ToolchainCatalog catalog,
    ToolchainRequirement requirement,
  ) {
    final requestedId = requirement.id;
    if (requestedId != null && requestedId.isNotEmpty) {
      final descriptor = catalog.lookup(requestedId);
      if (descriptor == null) {
        return ToolchainResolution(
          status: ToolchainResolutionStatus.missingId,
          requirement: requirement,
          message: 'Toolchain $requestedId is not registered.',
        );
      }
      return _matchDescriptor(descriptor, requirement);
    }

    final active = catalog.active(requirement.kind);
    if (active != null) {
      final activeMatch = _matchDescriptor(active, requirement);
      if (activeMatch.resolved) {
        return activeMatch;
      }
    }

    final candidates = catalog.list(kind: requirement.kind);
    if (candidates.isEmpty) {
      return ToolchainResolution(
        status: ToolchainResolutionStatus.missingKind,
        requirement: requirement,
        message: 'No ${requirement.kind.wireValue} toolchain is registered.',
      );
    }

    ToolchainResolution? firstMismatch;
    for (final descriptor in candidates) {
      final result = _matchDescriptor(descriptor, requirement);
      if (result.resolved) {
        return result;
      }
      firstMismatch ??= result;
    }
    return firstMismatch!;
  }

  ToolchainResolution _matchDescriptor(
    ToolchainDescriptor descriptor,
    ToolchainRequirement requirement,
  ) {
    if (descriptor.kind != requirement.kind) {
      return ToolchainResolution(
        status: ToolchainResolutionStatus.missingKind,
        requirement: requirement,
        descriptor: descriptor,
        message:
            'Toolchain ${descriptor.id} is ${descriptor.kind.wireValue}, not ${requirement.kind.wireValue}.',
      );
    }
    final version = requirement.version;
    if (version != null && descriptor.version != version) {
      return ToolchainResolution(
        status: ToolchainResolutionStatus.versionMismatch,
        requirement: requirement,
        descriptor: descriptor,
        message:
            'Toolchain ${descriptor.id} version ${descriptor.version ?? "unknown"} does not match $version.',
      );
    }
    final channel = requirement.channel;
    if (channel != null && descriptor.channel != channel) {
      return ToolchainResolution(
        status: ToolchainResolutionStatus.channelMismatch,
        requirement: requirement,
        descriptor: descriptor,
        message:
            'Toolchain ${descriptor.id} channel ${descriptor.channel ?? "unknown"} does not match $channel.',
      );
    }
    for (final entry in requirement.metadata.entries) {
      if (descriptor.metadata[entry.key] != entry.value) {
        return ToolchainResolution(
          status: ToolchainResolutionStatus.metadataMismatch,
          requirement: requirement,
          descriptor: descriptor,
          message:
              'Toolchain ${descriptor.id} metadata ${entry.key} does not match ${entry.value}.',
        );
      }
    }
    return ToolchainResolution(
      status: ToolchainResolutionStatus.resolved,
      requirement: requirement,
      descriptor: descriptor,
    );
  }
}
