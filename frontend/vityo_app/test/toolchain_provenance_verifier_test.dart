import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  Future<_SignedArtifact> createSignedArtifact(List<int> bytes) async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final signature = await algorithm.sign(bytes, keyPair: keyPair);
    return _SignedArtifact(
      bytes: bytes,
      trustRoot: ToolchainProvenanceTrustRoot(
        keyId: 'styio-nightly-test',
        algorithm: ToolchainProvenanceAlgorithm.ed25519,
        publicKeyBase64: base64.encode(publicKey.bytes),
      ),
      signaturePayload: jsonEncode(<String, Object?>{
        'version': 1,
        'algorithm': 'ed25519',
        'keyId': 'styio-nightly-test',
        'signature': base64.encode(signature.bytes),
      }),
    );
  }

  test(
    'toolchain provenance verifier accepts trusted Ed25519 signature',
    () async {
      final artifact = await createSignedArtifact(
        utf8.encode('styio artifact'),
      );

      final result = await const ToolchainProvenanceVerifier().verify(
        artifactBytes: artifact.bytes,
        signaturePayload: artifact.signaturePayload,
        trustRoots: <ToolchainProvenanceTrustRoot>[artifact.trustRoot],
      );

      expect(result.status, ToolchainProvenanceVerificationStatus.verified);
      expect(result.verifiedKeyId, 'styio-nightly-test');
      expect(result.succeeded, isTrue);
    },
  );

  test(
    'toolchain provenance verifier rejects tampered artifact bytes',
    () async {
      final artifact = await createSignedArtifact(
        utf8.encode('styio artifact'),
      );

      final result = await const ToolchainProvenanceVerifier().verify(
        artifactBytes: utf8.encode('tampered styio artifact'),
        signaturePayload: artifact.signaturePayload,
        trustRoots: <ToolchainProvenanceTrustRoot>[artifact.trustRoot],
      );

      expect(result.status, ToolchainProvenanceVerificationStatus.failed);
      expect(result.message, contains('signature verification failed'));
    },
  );

  test(
    'toolchain install policy blocks required provenance without trust roots',
    () {
      const policy = ToolchainInstallPolicy(
        allowedModes: <ToolchainInstallMode>{
          ToolchainInstallMode.managedDownload,
        },
        trustedDownloadHosts: <String>{'downloads.vityo.dev'},
        requireManagedDownloadSignature: true,
      );

      final plan = policy.plan(
        ToolchainInstallRequest(
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.languageService,
          ),
          downloadUri: Uri.parse('https://downloads.vityo.dev/styio'),
          provenanceSignatureUri: Uri.parse(
            'https://downloads.vityo.dev/styio.sig',
          ),
        ),
      );

      expect(plan.status, ToolchainInstallPlanStatus.blocked);
      expect(plan.message, contains('trusted provenance key'));
    },
  );

  test(
    'toolchain install executor verifies signed managed downloads',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_toolchain_provenance_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final platformManagers = await createDetectedPlatformManagerBundle(
        targetId: 'toolchain-provenance-test',
      );
      final artifact = await createSignedArtifact(
        utf8.encode('styio artifact'),
      );
      final artifactUri = Uri.parse('https://downloads.vityo.dev/styio');
      final signatureUri = Uri.parse('https://downloads.vityo.dev/styio.sig');
      final executor = ToolchainInstallExecutor(
        platformManagers: platformManagers.copyWithNetwork(
          _MemoryNetworkManager(
            delegate: platformManagers.network,
            responses: <Uri, List<int>>{
              artifactUri: artifact.bytes,
              signatureUri: utf8.encode(artifact.signaturePayload),
            },
          ),
        ),
      );
      final policy = ToolchainInstallPolicy(
        allowedModes: const <ToolchainInstallMode>{
          ToolchainInstallMode.managedDownload,
        },
        trustedDownloadHosts: const <String>{'downloads.vityo.dev'},
        requireManagedDownloadSha256: true,
        requireManagedDownloadSignature: true,
        trustedProvenanceKeys: <ToolchainProvenanceTrustRoot>[
          artifact.trustRoot,
        ],
      );
      final plan = policy.plan(
        ToolchainInstallRequest(
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.languageService,
          ),
          downloadUri: artifactUri,
          expectedSha256: sha256.convert(artifact.bytes).toString(),
          expectedSizeBytes: artifact.bytes.length,
          stagedFileName: 'styio',
          provenanceSignatureUri: signatureUri,
        ),
      );

      final result = await executor.execute(plan);

      expect(result.status, ToolchainInstallExecutionStatus.staged);
      expect(
        result.verificationStatus,
        ToolchainArtifactVerificationStatus.verified,
      );
      expect(
        result.provenanceVerificationStatus,
        ToolchainProvenanceVerificationStatus.verified,
      );
      expect(result.provenanceKeyId, 'styio-nightly-test');
      expect(result.stagedPath, isNotNull);
      expect(await File(result.stagedPath!).readAsString(), 'styio artifact');
    },
  );
}

class _SignedArtifact {
  const _SignedArtifact({
    required this.bytes,
    required this.trustRoot,
    required this.signaturePayload,
  });

  final List<int> bytes;
  final ToolchainProvenanceTrustRoot trustRoot;
  final String signaturePayload;
}

class _MemoryNetworkManager implements NetworkManager {
  const _MemoryNetworkManager({
    required this.delegate,
    required this.responses,
  });

  final NetworkManager delegate;
  final Map<Uri, List<int>> responses;

  @override
  NetworkFacts get facts => delegate.facts;

  @override
  NetworkCompatibility get compatibility => delegate.compatibility;

  @override
  Future<NetworkTextResponse> getText(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final bytes = responses[uri];
    if (bytes == null) {
      return NetworkTextResponse(
        status: NetworkRequestStatus.failed,
        uri: uri,
        statusCode: 404,
        body: '',
        message: 'Missing memory network response.',
      );
    }
    return NetworkTextResponse(
      status: NetworkRequestStatus.succeeded,
      uri: uri,
      statusCode: 200,
      body: utf8.decode(bytes),
    );
  }

  @override
  Future<NetworkTextResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return delegate.postJson(
      uri,
      headers: headers,
      body: body,
      timeout: timeout,
    );
  }

  @override
  Future<NetworkBinaryResponse> getBytes(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final bytes = responses[uri];
    if (bytes == null) {
      return NetworkBinaryResponse(
        status: NetworkRequestStatus.failed,
        uri: uri,
        statusCode: 404,
        bytes: const <int>[],
        message: 'Missing memory network response.',
      );
    }
    return NetworkBinaryResponse(
      status: NetworkRequestStatus.succeeded,
      uri: uri,
      statusCode: 200,
      bytes: bytes,
    );
  }

  @override
  NetworkOperationFailure? failureForBytes(
    NetworkBinaryResponse response, {
    String operation = 'network.getBytes',
    String? recoveryHint,
  }) {
    return delegate.failureForBytes(
      response,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }

  @override
  NetworkOperationFailure? failureForText(
    NetworkTextResponse response, {
    String operation = 'network.getText',
    String? recoveryHint,
  }) {
    return delegate.failureForText(
      response,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }
}

extension on PlatformManagerBundle {
  PlatformManagerBundle copyWithNetwork(NetworkManager network) {
    return PlatformManagerBundle(
      context: context,
      compatibility: compatibility,
      fileSystem: fileSystem,
      shell: shell,
      process: process,
      resource: resource,
      network: network,
      clipboard: clipboard,
      notification: notification,
      localService: localService,
      pty: pty,
    );
  }
}
