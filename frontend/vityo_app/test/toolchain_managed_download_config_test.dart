import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('managed download metadata survives toolchain catalog persistence', () {
    final trustRoot = ToolchainProvenanceTrustRoot(
      keyId: 'styio-nightly',
      algorithm: ToolchainProvenanceAlgorithm.ed25519,
      publicKeyBase64: base64.encode(List<int>.filled(32, 7)),
    );
    final config = ToolchainManagedDownloadConfig(
      downloadUri: Uri.parse('https://downloads.vityo.dev/styio/nightly'),
      expectedSha256:
          '0000000000000000000000000000000000000000000000000000000000000000',
      expectedSizeBytes: 12,
      stagedFileName: 'styio',
      markExecutable: true,
      provenanceSignatureUri: Uri.parse(
        'https://downloads.vityo.dev/styio/nightly.sig',
      ),
      trustedProvenanceKeys: <ToolchainProvenanceTrustRoot>[trustRoot],
    );
    final catalog = ToolchainCatalog()
      ..register(
        ToolchainDescriptor(
          id: 'styio-language-service-nightly',
          kind: ToolchainKind.languageService,
          displayName: 'Styio Language Service Nightly',
          executablePath: '',
          version: '2026.05',
          channel: 'nightly',
          metadata: <String, Object?>{
            ToolchainManagedDownloadConfig.metadataKey: config.toJson(),
          },
        ),
        activate: true,
      );

    final restored = ToolchainCatalog()
      ..restore(ToolchainCatalogSnapshot.fromJson(catalog.snapshot().toJson()));
    final descriptor = restored.active(ToolchainKind.languageService)!;
    final loaded = descriptor.managedDownloadConfig!;
    final requirement = ToolchainRequirement(
      kind: descriptor.kind,
      version: descriptor.version,
      channel: descriptor.channel,
    );
    final plan = loaded
        .toInstallPolicy(
          requireManagedDownloadSha256: true,
          requireManagedDownloadSignature: true,
        )
        .plan(loaded.toInstallRequest(requirement));

    expect(loaded.downloadUri.host, 'downloads.vityo.dev');
    expect(loaded.provenanceSignatureUri!.path, endsWith('.sig'));
    expect(loaded.trustedProvenanceKeys.single.keyId, 'styio-nightly');
    expect(plan.status, ToolchainInstallPlanStatus.planned);
    expect(plan.trustedProvenanceKeys.single.keyId, 'styio-nightly');
    expect(plan.expectedSha256, isNotNull);
  });

  test('managed download metadata blocks required signature without key', () {
    final config = ToolchainManagedDownloadConfig(
      downloadUri: Uri.parse('https://downloads.vityo.dev/styio/nightly'),
      provenanceSignatureUri: Uri.parse(
        'https://downloads.vityo.dev/styio/nightly.sig',
      ),
    );

    final plan = config
        .toInstallPolicy(requireManagedDownloadSignature: true)
        .plan(
          config.toInstallRequest(
            const ToolchainRequirement(kind: ToolchainKind.languageService),
          ),
        );

    expect(plan.status, ToolchainInstallPlanStatus.blocked);
    expect(plan.message, contains('trusted provenance key'));
  });

  test('managed download metadata normalizes loose descriptor input', () {
    final trustRoot = ToolchainProvenanceTrustRoot(
      keyId: 'styio-nightly',
      algorithm: ToolchainProvenanceAlgorithm.ed25519,
      publicKeyBase64: base64.encode(List<int>.filled(32, 3)),
    );
    final descriptor = ToolchainDescriptor(
      id: 'loose-metadata',
      kind: ToolchainKind.languageService,
      displayName: 'Loose Metadata',
      executablePath: '',
      metadata: <String, Object?>{
        ToolchainManagedDownloadConfig.metadataKey: <Object?, Object?>{
          'downloadUri': 'https://downloads.vityo.dev/styio.tar',
          'expectedSha256': '   ',
          'expectedSizeBytes': 12.8,
          'stagedFileName': '   ',
          'markExecutable': true,
          'archiveFormat': 'tar',
          'archiveExecutablePath': 'bin/styio',
          'archiveManifestPath': 'manifest.json',
          'provenanceSignatureUri':
              'https://signatures.vityo.dev/styio.tar.sig',
          'trustedProvenanceKeys': <Object?>[
            trustRoot.toJson(),
            <Object?, Object?>{
              'keyId': 'loose',
              'algorithm': 'ed25519',
              'publicKeyBase64': trustRoot.publicKeyBase64,
            },
            <String, Object?>{
              'keyId': '',
              'algorithm': 'ed25519',
              'publicKeyBase64': '',
            },
            'ignored',
          ],
          'trustedDownloadHosts': <Object?>[' downloads.vityo.dev ', '', 7],
        },
      },
    );
    const noMetadata = ToolchainDescriptor(
      id: 'plain',
      kind: ToolchainKind.languageService,
      displayName: 'Plain',
      executablePath: '/bin/styio',
    );
    final loaded = descriptor.managedDownloadConfig!;
    final request = loaded.toInstallRequest(
      const ToolchainRequirement(kind: ToolchainKind.languageService),
    );
    final policy = loaded.toInstallPolicy(
      requireManagedDownloadSha256: true,
      requireManagedDownloadSignature: true,
    );
    final inferred = ToolchainManagedDownloadConfig.fromJson(
      <String, Object?>{
        'downloadUri': 'https://downloads.vityo.dev/styio',
        'expectedSizeBytes': 8,
        'provenanceSignatureUri':
            'https://signatures.vityo.dev/styio.sig',
        'trustedDownloadHosts': const <Object?>[],
      },
    );
    final minimal = ToolchainManagedDownloadConfig.fromJson(
      const <String, Object?>{
        'downloadUri': '',
        'expectedSha256': 42,
        'expectedSizeBytes': 'large',
        'archiveFormat': '',
        'trustedProvenanceKeys': 'invalid',
      },
    );

    expect(loaded.hasExpectedSha256, isFalse);
    expect(loaded.hasProvenanceInputs, isTrue);
    expect(loaded.expectedSizeBytes, 12);
    expect(loaded.stagedFileName, isNull);
    expect(loaded.archiveFormat, ToolchainArchiveFormat.tar);
    expect(request.archiveExecutablePath, 'bin/styio');
    expect(request.archiveManifestPath, 'manifest.json');
    expect(policy.trustedDownloadHosts, <String>{'downloads.vityo.dev'});
    expect(policy.trustedProvenanceKeys.map((root) => root.keyId), <String>[
      'styio-nightly',
      'loose',
    ]);
    expect(noMetadata.managedDownloadConfig, isNull);
    expect(
      inferred.trustedDownloadHosts,
      <String>{'downloads.vityo.dev', 'signatures.vityo.dev'},
    );
    expect(minimal.expectedSha256, isNull);
    expect(minimal.expectedSizeBytes, isNull);
    expect(minimal.archiveFormat, ToolchainArchiveFormat.none);
    expect(minimal.trustedProvenanceKeys, isEmpty);
    expect(minimal.trustedDownloadHosts, isEmpty);
  });
}
