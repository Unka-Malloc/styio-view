import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'workspace_graph_snapshot.dart';

/// Computes cryptographic hashes for workspace graph snapshots.
///
/// The [compute] method produces a stable hash that reflects the full
/// topology and content of a workspace graph. It is used to detect
/// changes and invalidate caches (e.g. language service caches) when
/// the graph changes.
class GraphHash {
  // ---------------------------------------------------------------------------
  // Graph hash computation
  // ---------------------------------------------------------------------------

  /// Computes the full graph hash from its constituent parts.
  ///
  /// The hash is derived from:
  /// - Each canonical file's content hash
  /// - Each package's identity
  /// - Each dependency's identity
  /// - Toolchain identifier (if present)
  /// - Protocol version
  ///
  /// Returns a hex-encoded SHA-256 string.
  static String compute({
    required List<CanonicalFileEntry> canonicalFiles,
    required List<String> packageIds,
    required List<String> dependencyIds,
    required String? toolchainId,
    required int protocolVersion,
  }) {
    final digest = _sha256();
    final hashInput = StringBuffer();

    // 1. Canonical file hashes (sorted by path for determinism).
    final sortedFiles = List<CanonicalFileEntry>.from(canonicalFiles)
      ..sort((a, b) => a.filePath.compareTo(b.filePath));
    for (final file in sortedFiles) {
      hashInput.write('file:${file.filePath}=${file.contentHash}\n');
    }

    // 2. Package IDs (sorted for determinism).
    final sortedPackages = List<String>.from(packageIds)..sort();
    for (final pkgId in sortedPackages) {
      hashInput.write('pkg:$pkgId\n');
    }

    // 3. Dependency IDs (sorted for determinism).
    final sortedDeps = List<String>.from(dependencyIds)..sort();
    for (final depId in sortedDeps) {
      hashInput.write('dep:$depId\n');
    }

    // 4. Toolchain ID.
    if (toolchainId != null && toolchainId.isNotEmpty) {
      hashInput.write('toolchain:$toolchainId\n');
    }

    // 5. Protocol version.
    hashInput.write('protocol:$protocolVersion');

    digest.update(hashInput.toString());
    return digest.finish();
  }

  // ---------------------------------------------------------------------------
  // Individual hash helpers
  // ---------------------------------------------------------------------------

  /// Hashes a string and returns a hex-encoded digest.
  static String fromString(String input) {
    return _sha256(input).finish();
  }

  /// Hashes file content bytes and returns a hex-encoded digest.
  static String fromBytes(List<int> bytes) {
    return _sha256().fromBytes(bytes);
  }

  /// Creates a package ID string suitable for hashing.
  ///
  /// Format: `<packageName>@<version>:<rootPath>`.
  static String packageId({
    required String packageName,
    required String version,
    required String rootPath,
  }) {
    return '$packageName@$version:$rootPath';
  }

  /// Creates a dependency ID string suitable for hashing.
  ///
  /// Format: `<source>:<name>:<kind>:<requirement>`.
  static String dependencyId({
    required String sourcePackageName,
    required String dependencyName,
    required String kind,
    required String requirement,
  }) {
    return '$sourcePackageName:$dependencyName:$kind:$requirement';
  }

  /// Creates a toolchain ID string suitable for hashing.
  static String? toolchainId({
    required String? channel,
    required String? version,
    required String source,
  }) {
    if (channel == null && version == null) return null;
    return '$source:${channel ?? 'unspecified'}:${version ?? 'unspecified'}';
  }

  // ---------------------------------------------------------------------------
  // Internal SHA-256 helper
  // ---------------------------------------------------------------------------

  static _Sha256Helper _sha256([String? input]) {
    return _Sha256Helper(input);
  }
}

/// Incremental SHA-256 helper for graph hashing.
class _Sha256Helper {
  _Sha256Helper([String? input]) {
    if (input != null) {
      update(input);
    }
  }

  final List<int> _buffer = [];
  static final _encoder = utf8;

  void update(String input) {
    _buffer.addAll(_encoder.encode(input));
  }

  /// Produces a hex-encoded SHA-256 digest of all data fed so far.
  String finish() {
    final digest = _sha256FromBytes(_buffer);
    _buffer.clear();
    return digest;
  }

  /// Convenience: update + finish.
  String call(String input) {
    update(input);
    return finish();
  }

  String fromBytes(List<int> bytes) {
    _buffer.addAll(bytes);
    return finish();
  }
}

String _sha256FromBytes(List<int> bytes) =>
    crypto.sha256.convert(bytes).toString();

/// Public helper to hash a string to a hex-encoded SHA-256 digest.
String hashString(String input) {
  return GraphHash.fromString(input);
}
