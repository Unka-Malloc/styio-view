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
}
