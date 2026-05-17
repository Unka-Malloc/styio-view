import 'dart:convert';

import 'package:cryptography/cryptography.dart';

enum ToolchainProvenanceAlgorithm { ed25519 }

enum ToolchainProvenanceVerificationStatus { notRequested, verified, failed }

class ToolchainProvenanceTrustRoot {
  const ToolchainProvenanceTrustRoot({
    required this.keyId,
    required this.algorithm,
    required this.publicKeyBase64,
  });

  factory ToolchainProvenanceTrustRoot.fromJson(Map<String, Object?> json) {
    return ToolchainProvenanceTrustRoot(
      keyId: json['keyId'] as String? ?? '',
      algorithm: ToolchainProvenanceSignatureBundle._parseAlgorithm(
        json['algorithm'] as String? ?? '',
      ),
      publicKeyBase64: json['publicKeyBase64'] as String? ?? '',
    );
  }

  final String keyId;
  final ToolchainProvenanceAlgorithm algorithm;
  final String publicKeyBase64;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'keyId': keyId,
      'algorithm': algorithm.name,
      'publicKeyBase64': publicKeyBase64,
    };
  }
}

class ToolchainProvenanceSignatureBundle {
  const ToolchainProvenanceSignatureBundle({
    required this.version,
    required this.algorithm,
    required this.keyId,
    required this.signatureBase64,
  });

  final int version;
  final ToolchainProvenanceAlgorithm algorithm;
  final String keyId;
  final String signatureBase64;

  static ToolchainProvenanceSignatureBundle parse(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Toolchain provenance signature payload must be a JSON object.',
      );
    }
    final version = decoded['version'];
    final algorithm = decoded['algorithm'];
    final keyId = decoded['keyId'];
    final signature = decoded['signature'] ?? decoded['signatureBase64'];
    if (version != 1) {
      throw const FormatException(
        'Toolchain provenance signature payload version is unsupported.',
      );
    }
    if (algorithm is! String || algorithm.trim().isEmpty) {
      throw const FormatException(
        'Toolchain provenance signature algorithm is missing.',
      );
    }
    if (keyId is! String || keyId.trim().isEmpty) {
      throw const FormatException(
        'Toolchain provenance signature keyId is missing.',
      );
    }
    if (signature is! String || signature.trim().isEmpty) {
      throw const FormatException(
        'Toolchain provenance signature bytes are missing.',
      );
    }
    return ToolchainProvenanceSignatureBundle(
      version: version as int,
      algorithm: _parseAlgorithm(algorithm),
      keyId: keyId.trim(),
      signatureBase64: signature.trim(),
    );
  }

  static ToolchainProvenanceAlgorithm _parseAlgorithm(String value) {
    return switch (value.trim().toLowerCase()) {
      'ed25519' => ToolchainProvenanceAlgorithm.ed25519,
      _ => throw FormatException(
        'Unsupported toolchain provenance signature algorithm: $value.',
      ),
    };
  }
}

class ToolchainProvenanceVerification {
  const ToolchainProvenanceVerification({
    required this.status,
    this.verifiedKeyId,
    this.message,
  });

  final ToolchainProvenanceVerificationStatus status;
  final String? verifiedKeyId;
  final String? message;

  bool get succeeded => status != ToolchainProvenanceVerificationStatus.failed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      if (verifiedKeyId != null) 'verifiedKeyId': verifiedKeyId,
      if (message != null) 'message': message,
      'succeeded': succeeded,
    };
  }
}

class ToolchainProvenanceVerifier {
  const ToolchainProvenanceVerifier();

  Future<ToolchainProvenanceVerification> verify({
    required List<int> artifactBytes,
    required String signaturePayload,
    required Iterable<ToolchainProvenanceTrustRoot> trustRoots,
  }) async {
    final roots = trustRoots.toList(growable: false);
    if (roots.isEmpty) {
      return const ToolchainProvenanceVerification(
        status: ToolchainProvenanceVerificationStatus.failed,
        message: 'Toolchain provenance verification has no trusted keys.',
      );
    }

    final ToolchainProvenanceSignatureBundle bundle;
    try {
      bundle = ToolchainProvenanceSignatureBundle.parse(signaturePayload);
    } on FormatException catch (error) {
      return ToolchainProvenanceVerification(
        status: ToolchainProvenanceVerificationStatus.failed,
        message: error.message,
      );
    }

    final trustRoot = roots
        .where(
          (root) =>
              root.keyId == bundle.keyId && root.algorithm == bundle.algorithm,
        )
        .firstOrNull;
    if (trustRoot == null) {
      return ToolchainProvenanceVerification(
        status: ToolchainProvenanceVerificationStatus.failed,
        message:
            'Toolchain provenance signature key ${bundle.keyId} is not trusted.',
      );
    }

    try {
      final verified = await switch (bundle.algorithm) {
        ToolchainProvenanceAlgorithm.ed25519 => _verifyEd25519(
          artifactBytes: artifactBytes,
          signatureBase64: bundle.signatureBase64,
          publicKeyBase64: trustRoot.publicKeyBase64,
        ),
      };
      if (!verified) {
        return const ToolchainProvenanceVerification(
          status: ToolchainProvenanceVerificationStatus.failed,
          message: 'Toolchain provenance signature verification failed.',
        );
      }
      return ToolchainProvenanceVerification(
        status: ToolchainProvenanceVerificationStatus.verified,
        verifiedKeyId: bundle.keyId,
      );
    } on FormatException catch (error) {
      return ToolchainProvenanceVerification(
        status: ToolchainProvenanceVerificationStatus.failed,
        message: error.message,
      );
    }
  }

  Future<bool> _verifyEd25519({
    required List<int> artifactBytes,
    required String signatureBase64,
    required String publicKeyBase64,
  }) {
    final publicKey = SimplePublicKey(
      base64Decode(publicKeyBase64),
      type: KeyPairType.ed25519,
    );
    final signature = Signature(
      base64Decode(signatureBase64),
      publicKey: publicKey,
    );
    return Ed25519().verify(artifactBytes, signature: signature);
  }
}
