import '../../backend_toolchain/project_graph_contract.dart';
import 'observable_delta_model.dart';
import 'observable_snapshot_model.dart';

class ObservableSnapshotAdvertisement {
  const ObservableSnapshotAdvertisement({
    required this.schemaVersions,
    required this.capabilities,
    this.optionalCapabilities = const <String>[],
  });

  factory ObservableSnapshotAdvertisement.fromHandshake(
    CompilerHandshakeSnapshot? compiler,
  ) {
    if (compiler == null) {
      return const ObservableSnapshotAdvertisement(
        schemaVersions: <int>[],
        capabilities: <String>[],
      );
    }
    final versions = compiler.observableStaticSnapshotSchemaVersions.isNotEmpty
        ? compiler.observableStaticSnapshotSchemaVersions
        : (compiler.supportedContractVersions[kObservableMachineInfoKey] ??
              const <int>[]);
    final capabilities =
        compiler.observableStaticSnapshotCapabilities.isNotEmpty
        ? compiler.observableStaticSnapshotCapabilities
        : compiler.capabilities
              .where(kObservableRequiredCapabilities.contains)
              .toList(growable: false);
    return ObservableSnapshotAdvertisement(
      schemaVersions: versions,
      capabilities: capabilities,
      optionalCapabilities:
          compiler.observableStaticSnapshotOptionalCapabilities,
    );
  }

  factory ObservableSnapshotAdvertisement.fromMachineInfo(
    Map<String, Object?> payload,
  ) {
    final raw = payload[kObservableMachineInfoKey];
    if (raw is! Map) {
      return const ObservableSnapshotAdvertisement(
        schemaVersions: <int>[],
        capabilities: <String>[],
      );
    }
    final map = raw.map(
      (key, value) => MapEntry<String, Object?>(key.toString(), value),
    );
    final versions = <int>[];
    final versionValue = map['schema_versions'];
    if (versionValue is List) {
      for (final item in versionValue) {
        if (item is num) {
          versions.add(item.toInt());
        }
      }
    }
    final capabilities = <String>[];
    final capabilityValue = map['capabilities'];
    if (capabilityValue is List) {
      for (final item in capabilityValue) {
        if (item is String) {
          capabilities.add(item);
        }
      }
    }
    final optionalCapabilities = <String>[];
    final optionalValue = map[kObservableMachineInfoOptionalCapabilitiesKey];
    if (optionalValue is List) {
      for (final item in optionalValue) {
        if (item is String) {
          optionalCapabilities.add(item);
        }
      }
    }
    return ObservableSnapshotAdvertisement(
      schemaVersions: versions,
      capabilities: capabilities,
      optionalCapabilities: optionalCapabilities,
    );
  }

  final List<int> schemaVersions;
  final List<String> capabilities;
  final List<String> optionalCapabilities;

  bool get advertisesSchemaV1 =>
      schemaVersions.contains(kObservableStaticSnapshotSchemaVersion);

  bool advertisesOptionalCapability(String name) {
    return optionalCapabilities.contains(name) || capabilities.contains(name);
  }

  List<String> get missingRequiredCapabilities {
    final advertised = capabilities.toSet();
    return kObservableRequiredCapabilities
        .where((name) => !advertised.contains(name))
        .toList(growable: false);
  }
}

class ObservableNegotiationInput {
  const ObservableNegotiationInput({
    required this.ioPlatform,
    required this.pafioAvailable,
    this.compiler,
    this.manifestPath,
    this.hosted = false,
    this.advertisement,
  });

  final bool ioPlatform;
  final bool pafioAvailable;
  final CompilerHandshakeSnapshot? compiler;
  final String? manifestPath;
  final bool hosted;
  final ObservableSnapshotAdvertisement? advertisement;
}

ObservableNegotiationDecision negotiateObservableCapability(
  ObservableNegotiationInput input,
) {
  if (!input.ioPlatform || input.hosted) {
    return ObservableNegotiationDecision.reject(
      availability: ObservableAvailability.unsupported,
      reason: ObservableReasonCode.unsupportedPlatform,
      detail: input.hosted
          ? 'Hosted workspaces do not publish local observable snapshots.'
          : 'Observable snapshot publication requires a local IO toolchain.',
    );
  }
  if (input.compiler == null || !input.pafioAvailable) {
    return ObservableNegotiationDecision.reject(
      availability: ObservableAvailability.unavailable,
      reason: ObservableReasonCode.noToolchain,
      detail: input.compiler == null
          ? 'No Styio compiler handshake is available.'
          : 'No Pafio binary is available.',
    );
  }
  final manifest = input.manifestPath?.trim() ?? '';
  if (manifest.isEmpty) {
    return ObservableNegotiationDecision.reject(
      availability: ObservableAvailability.unavailable,
      reason: ObservableReasonCode.noManifest,
      detail: 'Observable snapshot publication requires a package manifest.',
    );
  }

  final advertisement =
      input.advertisement ??
      ObservableSnapshotAdvertisement.fromHandshake(input.compiler);
  if (!advertisement.advertisesSchemaV1) {
    return ObservableNegotiationDecision.reject(
      availability: ObservableAvailability.unsupported,
      reason: ObservableReasonCode.unsupportedSchemaVersion,
      detail:
          'Compiler does not advertise observable static snapshot schema v1.',
    );
  }
  final missing = advertisement.missingRequiredCapabilities;
  if (missing.isNotEmpty) {
    return ObservableNegotiationDecision.reject(
      availability: ObservableAvailability.unsupported,
      reason: ObservableReasonCode.missingCapability,
      detail:
          'Compiler is missing required capabilities: ${missing.join(', ')}.',
    );
  }
  return ObservableNegotiationDecision.ok(
    snapshotDeltaAvailable: advertisement.advertisesOptionalCapability(
      kObservableDeltaCapability,
    ),
    producerLineageAvailable: advertisement.advertisesOptionalCapability(
      kObservableLineageCapability,
    ),
  );
}

bool shouldDecodeObservableSnapshot(ObservableNegotiationDecision decision) {
  return decision.accepted;
}
