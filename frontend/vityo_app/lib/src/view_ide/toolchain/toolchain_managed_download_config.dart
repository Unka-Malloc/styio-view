import 'toolchain_archive_extractor.dart';
import 'toolchain_catalog.dart';
import 'toolchain_install_policy.dart';
import 'toolchain_provenance_verifier.dart';
import 'toolchain_resolver.dart';

class ToolchainManagedDownloadConfig {
  const ToolchainManagedDownloadConfig({
    required this.downloadUri,
    this.expectedSha256,
    this.expectedSizeBytes,
    this.stagedFileName,
    this.markExecutable = false,
    this.archiveFormat = ToolchainArchiveFormat.none,
    this.archiveExecutablePath,
    this.archiveManifestPath,
    this.provenanceSignatureUri,
    this.trustedProvenanceKeys = const <ToolchainProvenanceTrustRoot>[],
    this.trustedDownloadHosts = const <String>{},
  });

  static const String metadataKey = 'managedDownload';

  final Uri downloadUri;
  final String? expectedSha256;
  final int? expectedSizeBytes;
  final String? stagedFileName;
  final bool markExecutable;
  final ToolchainArchiveFormat archiveFormat;
  final String? archiveExecutablePath;
  final String? archiveManifestPath;
  final Uri? provenanceSignatureUri;
  final List<ToolchainProvenanceTrustRoot> trustedProvenanceKeys;
  final Set<String> trustedDownloadHosts;

  factory ToolchainManagedDownloadConfig.fromJson(Map<String, Object?> json) {
    final downloadUri = Uri.parse(json['downloadUri'] as String? ?? '');
    final provenanceSignatureUri = _optionalUri(json['provenanceSignatureUri']);
    return ToolchainManagedDownloadConfig(
      downloadUri: downloadUri,
      expectedSha256: _optionalString(json['expectedSha256']),
      expectedSizeBytes: _optionalInt(json['expectedSizeBytes']),
      stagedFileName: _optionalString(json['stagedFileName']),
      markExecutable: json['markExecutable'] == true,
      archiveFormat: _archiveFormatFromJson(json['archiveFormat']),
      archiveExecutablePath: _optionalString(json['archiveExecutablePath']),
      archiveManifestPath: _optionalString(json['archiveManifestPath']),
      provenanceSignatureUri: provenanceSignatureUri,
      trustedProvenanceKeys: _trustRootsFromJson(json['trustedProvenanceKeys']),
      trustedDownloadHosts: _trustedHostsFromJson(
        json['trustedDownloadHosts'],
        downloadUri: downloadUri,
        provenanceSignatureUri: provenanceSignatureUri,
      ),
    );
  }

  static ToolchainManagedDownloadConfig? fromDescriptor(
    ToolchainDescriptor descriptor,
  ) {
    final value = descriptor.metadata[metadataKey];
    if (value is Map<String, Object?>) {
      return ToolchainManagedDownloadConfig.fromJson(value);
    }
    if (value is Map) {
      return ToolchainManagedDownloadConfig.fromJson(
        value.map(
          (key, value) => MapEntry<String, Object?>(key.toString(), value),
        ),
      );
    }
    return null;
  }

  bool get hasExpectedSha256 => expectedSha256?.trim().isNotEmpty == true;

  bool get hasProvenanceInputs =>
      provenanceSignatureUri != null && trustedProvenanceKeys.isNotEmpty;

  ToolchainInstallRequest toInstallRequest(ToolchainRequirement requirement) {
    return ToolchainInstallRequest(
      requirement: requirement,
      downloadUri: downloadUri,
      expectedSha256: expectedSha256,
      expectedSizeBytes: expectedSizeBytes,
      stagedFileName: stagedFileName,
      markExecutable: markExecutable,
      archiveFormat: archiveFormat,
      archiveExecutablePath: archiveExecutablePath,
      archiveManifestPath: archiveManifestPath,
      provenanceSignatureUri: provenanceSignatureUri,
    );
  }

  ToolchainInstallPolicy toInstallPolicy({
    bool requireManagedDownloadSha256 = false,
    bool requireManagedDownloadSignature = false,
  }) {
    return ToolchainInstallPolicy(
      allowedModes: const <ToolchainInstallMode>{
        ToolchainInstallMode.managedDownload,
      },
      trustedDownloadHosts: trustedDownloadHosts.isEmpty
          ? _inferredTrustedHosts(
              downloadUri: downloadUri,
              provenanceSignatureUri: provenanceSignatureUri,
            )
          : trustedDownloadHosts,
      requireManagedDownloadSha256: requireManagedDownloadSha256,
      requireManagedDownloadSignature: requireManagedDownloadSignature,
      trustedProvenanceKeys: trustedProvenanceKeys,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'downloadUri': downloadUri.toString(),
      if (expectedSha256 != null) 'expectedSha256': expectedSha256,
      if (expectedSizeBytes != null) 'expectedSizeBytes': expectedSizeBytes,
      if (stagedFileName != null) 'stagedFileName': stagedFileName,
      'markExecutable': markExecutable,
      'archiveFormat': archiveFormat.name,
      if (archiveExecutablePath != null)
        'archiveExecutablePath': archiveExecutablePath,
      if (archiveManifestPath != null)
        'archiveManifestPath': archiveManifestPath,
      if (provenanceSignatureUri != null)
        'provenanceSignatureUri': provenanceSignatureUri.toString(),
      if (trustedProvenanceKeys.isNotEmpty)
        'trustedProvenanceKeys': trustedProvenanceKeys
            .map((key) => key.toJson())
            .toList(growable: false),
      if (trustedDownloadHosts.isNotEmpty)
        'trustedDownloadHosts': trustedDownloadHosts.toList(growable: false),
    };
  }

  static Uri? _optionalUri(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return Uri.parse(value.trim());
  }

  static String? _optionalString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  static int? _optionalInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static ToolchainArchiveFormat _archiveFormatFromJson(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return ToolchainArchiveFormat.none;
    }
    return ToolchainArchiveFormat.values
            .where((format) => format.name == value.trim())
            .firstOrNull ??
        ToolchainArchiveFormat.none;
  }

  static List<ToolchainProvenanceTrustRoot> _trustRootsFromJson(Object? value) {
    if (value is! List) {
      return const <ToolchainProvenanceTrustRoot>[];
    }
    return value
        .map((entry) {
          if (entry is Map<String, Object?>) {
            return ToolchainProvenanceTrustRoot.fromJson(entry);
          }
          if (entry is Map) {
            return ToolchainProvenanceTrustRoot.fromJson(
              entry.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            );
          }
          return null;
        })
        .whereType<ToolchainProvenanceTrustRoot>()
        .where(
          (root) =>
              root.keyId.isNotEmpty && root.publicKeyBase64.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  static Set<String> _trustedHostsFromJson(
    Object? value, {
    required Uri downloadUri,
    required Uri? provenanceSignatureUri,
  }) {
    if (value is! List) {
      return _inferredTrustedHosts(
        downloadUri: downloadUri,
        provenanceSignatureUri: provenanceSignatureUri,
      );
    }
    final hosts = value
        .whereType<String>()
        .map((host) => host.trim())
        .where((host) => host.isNotEmpty)
        .toSet();
    return hosts.isEmpty
        ? _inferredTrustedHosts(
            downloadUri: downloadUri,
            provenanceSignatureUri: provenanceSignatureUri,
          )
        : hosts;
  }

  static Set<String> _inferredTrustedHosts({
    required Uri downloadUri,
    required Uri? provenanceSignatureUri,
  }) {
    return <String>{
      if (downloadUri.host.isNotEmpty) downloadUri.host,
      if (provenanceSignatureUri?.host.isNotEmpty == true)
        provenanceSignatureUri!.host,
    };
  }
}

extension ToolchainManagedDownloadDescriptorX on ToolchainDescriptor {
  ToolchainManagedDownloadConfig? get managedDownloadConfig {
    return ToolchainManagedDownloadConfig.fromDescriptor(this);
  }
}
