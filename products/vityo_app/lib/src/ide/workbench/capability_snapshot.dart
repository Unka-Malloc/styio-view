import 'dart:collection';

enum IdeCapabilityState { available, degraded, blocked }

enum IdeCapabilityDomain {
  save,
  language,
  diagnostics,
  formatting,
  build,
  run,
  test,
  debug,
  sourceControl,
  terminal,
  toolchain,
  packageManagement,
}

final class IdeCapabilityFact {
  IdeCapabilityFact({
    required this.id,
    required this.domain,
    required this.state,
    required this.provenance,
    required this.message,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (provenance.trim().isEmpty) {
      throw ArgumentError.value(provenance, 'provenance', 'must not be empty');
    }
    if (message.trim().isEmpty) {
      throw ArgumentError.value(message, 'message', 'must not be empty');
    }
  }

  final String id;
  final IdeCapabilityDomain domain;
  final IdeCapabilityState state;
  final String provenance;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'domain': domain.name,
    'state': state.name,
    'provenance': provenance,
    'message': message,
  };

  @override
  bool operator ==(Object other) =>
      other is IdeCapabilityFact &&
      id == other.id &&
      domain == other.domain &&
      state == other.state &&
      provenance == other.provenance &&
      message == other.message;

  @override
  int get hashCode => Object.hash(id, domain, state, provenance, message);
}

final class CapabilitySnapshot {
  CapabilitySnapshot({
    required this.schemaVersion,
    required this.workspaceRevision,
    required Map<String, IdeCapabilityFact> capabilities,
  }) : capabilities = UnmodifiableMapView(_sortedCapabilities(capabilities)) {
    if (schemaVersion <= 0) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'must be positive',
      );
    }
    if (workspaceRevision < 0) {
      throw ArgumentError.value(
        workspaceRevision,
        'workspaceRevision',
        'must not be negative',
      );
    }
    for (final entry in this.capabilities.entries) {
      if (entry.key != entry.value.id) {
        throw ArgumentError.value(
          entry.key,
          'capabilities',
          'map key must match capability id',
        );
      }
    }
  }

  final int schemaVersion;
  final int workspaceRevision;
  final Map<String, IdeCapabilityFact> capabilities;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'workspaceRevision': workspaceRevision,
    'capabilities': <String, Object?>{
      for (final entry in capabilities.entries) entry.key: entry.value.toJson(),
    },
  };

  @override
  bool operator ==(Object other) {
    if (other is! CapabilitySnapshot ||
        schemaVersion != other.schemaVersion ||
        workspaceRevision != other.workspaceRevision ||
        capabilities.length != other.capabilities.length) {
      return false;
    }
    for (final entry in capabilities.entries) {
      if (other.capabilities[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    var result = Object.hash(schemaVersion, workspaceRevision);
    for (final entry in capabilities.entries) {
      result = Object.hash(result, entry.key, entry.value);
    }
    return result;
  }
}

Map<String, IdeCapabilityFact> _sortedCapabilities(
  Map<String, IdeCapabilityFact> capabilities,
) {
  final keys = capabilities.keys.toList(growable: false)..sort();
  return <String, IdeCapabilityFact>{
    for (final key in keys) key: capabilities[key]!,
  };
}
