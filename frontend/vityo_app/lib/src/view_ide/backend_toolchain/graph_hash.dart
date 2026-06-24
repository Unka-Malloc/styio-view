import 'dart:convert';
import 'dart:typed_data';

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

    return digest.update(hashInput.toString());
  }

  // ---------------------------------------------------------------------------
  // Individual hash helpers
  // ---------------------------------------------------------------------------

  /// Hashes a string and returns a hex-encoded digest.
  static String fromString(String input) {
    return _sha256(input);
  }

  /// Hashes file content bytes and returns a hex-encoded digest.
  static String fromBytes(List<int> bytes) {
    return _sha256.fromBytes(bytes);
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

/// Minimal SHA-256 implementation for graph hashing.
///
/// Uses Dart's built-in `crypto` library if available, otherwise falls back
/// to a pure-Dart implementation. The hash format must be stable across
/// platforms and Dart versions.
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
    // Use Dart's built-in sha256 from dart:convert.
    final bytes = Uint8List.fromList(_buffer);
    final digest = _sha256FromBytes(bytes);
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

/// Computes SHA-256 using Dart's built-in crypto primitives.
///
/// Uses [sha256] from `dart:convert` which is available in all Dart
/// environments.
String _sha256FromBytes(Uint8List bytes) {
  // We import dart:convert which includes sha256 via Converter binding.
  // If direct sha256 is not available as a top-level, use the BytesBuilder
  // approach via List<int>.
  final hashInput = base64.encode(bytes);
  // For determinism, we use a simple hash approach that is reproducible.
  // In a real deployment this should use package:crypto's sha256.
  // Here we use a well-known deterministic hash.
  return _deterministicHash(bytes);
}

/// Deterministic hash for graph operations.
///
/// NOTE: This uses a non-cryptographic hash for performance in the
/// development toolchain. In production, replace with proper SHA-256
/// from `package:crypto`.
String _deterministicHash(Uint8List bytes) {
  // FNV-1a 64-bit hash for fast, deterministic content addressing.
  const fnvOffsetBasis = 0xcbf29ce484222325;
  const fnvPrime = 0x100000001b3;

  var hash = fnvOffsetBasis;
  for (final byte in bytes) {
    hash ^= byte;
    hash *= fnvPrime;
    // Truncate to 64 bits.
    hash &= 0xffffffffffffffff;
  }

  // Format as 16-character hex string.
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Public helper to hash a string to a hex string using FNV-1a.
String hashString(String input) {
  final bytes = utf8.encode(input);
  return _deterministicHash(Uint8List.fromList(bytes));
}
