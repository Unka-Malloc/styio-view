import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('payload codec preserves text, json, json lines, and metadata', () {
    const codec = ToolchainPayloadCodec();

    final text = codec.encodeText(
      'hello styio',
      metadata: const <String, Object?>{'source': 'test'},
    );
    final jsonPayload = codec.encodeJson(
      const <String, Object?>{
        'toolchain': 'styio',
        'features': <String>['compile', 'run'],
      },
    );
    final jsonLines = codec.encodeJsonLines(const <Map<String, Object?>>[
      <String, Object?>{'event': 'start', 'id': 1},
      <String, Object?>{'event': 'finish', 'id': 2},
    ]);

    expect(text.format.wireValue, 'utf8-text');
    expect(text.contentType, 'text/plain; charset=utf-8');
    expect(text.metadata['source'], 'test');
    expect(text.length, utf8.encode('hello styio').length);
    expect(codec.decodeText(text), 'hello styio');
    expect(codec.decodeJson(jsonPayload)['toolchain'], 'styio');
    expect(codec.decodeJson(jsonPayload)['features'], <String>['compile', 'run']);
    expect(codec.decodeJsonLines(jsonLines).map((row) => row['event']), <String>[
      'start',
      'finish',
    ]);
  });

  test('payload codec normalizes dynamic map keys and skips blank jsonl rows', () {
    const codec = ToolchainPayloadCodec();
    final jsonPayload = ToolchainPayload(
      format: ToolchainPayloadFormat.json,
      bytes: Uint8List.fromList(utf8.encode('{"1":"one","true":"yes"}')),
    );
    final jsonLines = ToolchainPayload(
      format: ToolchainPayloadFormat.jsonLines,
      bytes: Uint8List.fromList(
        utf8.encode('{"event":"first"}\n\n{"event":"second"}\n'),
      ),
    );

    expect(codec.decodeJson(jsonPayload), <String, Object?>{
      '1': 'one',
      'true': 'yes',
    });
    expect(codec.decodeJsonLines(jsonLines), <Map<String, Object?>>[
      <String, Object?>{'event': 'first'},
      <String, Object?>{'event': 'second'},
    ]);
  });

  test('payload codec rejects non-map json and jsonl records', () {
    const codec = ToolchainPayloadCodec();

    expect(
      () => codec.decodeJson(
        ToolchainPayload(
          format: ToolchainPayloadFormat.json,
          bytes: Uint8List.fromList(utf8.encode('[1,2,3]')),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => codec.decodeJsonLines(
        ToolchainPayload(
          format: ToolchainPayloadFormat.jsonLines,
          bytes: Uint8List.fromList(utf8.encode('{"ok":true}\n42')),
        ),
      ),
      throwsFormatException,
    );
  });

  test('install policy plans trusted managed download with provenance', () {
    final trustRoot = ToolchainProvenanceTrustRoot(
      keyId: 'styio-nightly',
      algorithm: ToolchainProvenanceAlgorithm.ed25519,
      publicKeyBase64: base64.encode(List<int>.filled(32, 1)),
    );
    final plan = ToolchainInstallPolicy(
      allowedModes: const <ToolchainInstallMode>{
        ToolchainInstallMode.managedDownload,
      },
      trustedDownloadHosts: const <String>{'downloads.vityo.dev'},
      requireManagedDownloadSha256: true,
      requireManagedDownloadSignature: true,
      trustedProvenanceKeys: <ToolchainProvenanceTrustRoot>[trustRoot],
    ).plan(
      ToolchainInstallRequest(
        requirement: const ToolchainRequirement(kind: ToolchainKind.compiler),
        downloadUri: Uri.parse('https://downloads.vityo.dev/styio.tar.xz'),
        expectedSha256:
            '1111111111111111111111111111111111111111111111111111111111111111',
        expectedSizeBytes: 42,
        stagedFileName: 'styio',
        markExecutable: true,
        archiveFormat: ToolchainArchiveFormat.tar,
        archiveExecutablePath: 'bin/styio',
        archiveManifestPath: 'manifest.json',
        provenanceSignatureUri: Uri.parse(
          'https://downloads.vityo.dev/styio.tar.xz.sig',
        ),
      ),
    );

    expect(plan.status, ToolchainInstallPlanStatus.planned);
    expect(plan.actionable, isTrue);
    expect(plan.mode, ToolchainInstallMode.managedDownload);
    expect(plan.trustedProvenanceKeys.single.keyId, 'styio-nightly');
    expect(plan.toJson()['archiveFormat'], 'tar');
    expect(plan.toJson()['trustedProvenanceKeyIds'], <String>['styio-nightly']);
  });

  test('install policy blocks untrusted managed download inputs', () {
    const policy = ToolchainInstallPolicy(
      allowedModes: <ToolchainInstallMode>{
        ToolchainInstallMode.managedDownload,
      },
      trustedDownloadHosts: <String>{'downloads.vityo.dev'},
      requireManagedDownloadSha256: true,
      requireManagedDownloadSignature: true,
      trustedProvenanceKeys: <ToolchainProvenanceTrustRoot>[],
    );
    const requirement = ToolchainRequirement(kind: ToolchainKind.compiler);

    final untrustedHost = policy.plan(
      ToolchainInstallRequest(
        requirement: requirement,
        downloadUri: Uri.parse('https://evil.example/styio'),
      ),
    );
    final missingHash = policy.plan(
      ToolchainInstallRequest(
        requirement: requirement,
        downloadUri: Uri.parse('https://downloads.vityo.dev/styio'),
      ),
    );
    final missingSignature = policy.plan(
      ToolchainInstallRequest(
        requirement: requirement,
        downloadUri: Uri.parse('https://downloads.vityo.dev/styio'),
        expectedSha256:
            '2222222222222222222222222222222222222222222222222222222222222222',
      ),
    );
    final untrustedSignatureHost = policy.plan(
      ToolchainInstallRequest(
        requirement: requirement,
        downloadUri: Uri.parse('https://downloads.vityo.dev/styio'),
        expectedSha256:
            '3333333333333333333333333333333333333333333333333333333333333333',
        provenanceSignatureUri: Uri.parse('https://evil.example/styio.sig'),
      ),
    );

    expect(untrustedHost.status, ToolchainInstallPlanStatus.blocked);
    expect(untrustedHost.message, contains('not trusted'));
    expect(missingHash.message, contains('expected SHA-256'));
    expect(missingSignature.message, contains('provenance signature URI'));
    expect(untrustedSignatureHost.message, contains('signature host'));
  });

  test('install policy falls back to external command, manual, and disabled', () {
    const requirement = ToolchainRequirement(kind: ToolchainKind.runner);

    final external = const ToolchainInstallPolicy(
      allowedModes: <ToolchainInstallMode>{
        ToolchainInstallMode.externalCommand,
        ToolchainInstallMode.manualSelection,
      },
    ).plan(
      const ToolchainInstallRequest(
        requirement: requirement,
        externalCommand: '/usr/bin/styio-bootstrap',
        externalArguments: <String>['--channel', 'nightly'],
      ),
    );
    final manual = const ToolchainInstallPolicy().plan(
      const ToolchainInstallRequest(requirement: requirement),
    );
    final disabled = const ToolchainInstallPolicy(
      allowedModes: <ToolchainInstallMode>{},
    ).plan(const ToolchainInstallRequest(requirement: requirement));

    expect(external.status, ToolchainInstallPlanStatus.planned);
    expect(external.mode, ToolchainInstallMode.externalCommand);
    expect(external.externalArguments, <String>['--channel', 'nightly']);
    expect(manual.mode, ToolchainInstallMode.manualSelection);
    expect(manual.message, contains('Select an existing'));
    expect(disabled.status, ToolchainInstallPlanStatus.blocked);
    expect(disabled.mode, ToolchainInstallMode.disabled);
    expect(disabled.actionable, isFalse);
  });
}
