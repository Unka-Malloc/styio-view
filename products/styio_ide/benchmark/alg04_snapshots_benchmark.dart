/// ALG-04: Snapshots Benchmark
///
/// Benchmarks snapshot operations:
/// - Snapshot creation time (various document sizes)
/// - Atomic swap time
/// - Stale detection time
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'alg01_piece_table_benchmark.dart';

class DocumentSnapshot {
  final String documentId;
  final String text;
  final int revision;
  final String contentHash;
  final DateTime createdAt;

  const DocumentSnapshot({
    required this.documentId,
    required this.text,
    required this.revision,
    required this.contentHash,
    required this.createdAt,
  });

  /// Create a snapshot from a document.
  factory DocumentSnapshot.fromDocument(String documentId, String text, int revision) {
    final hash = sha256.convert(utf8.encode(text)).toString();
    return DocumentSnapshot(
      documentId: documentId,
      text: text,
      revision: revision,
      contentHash: hash,
      createdAt: DateTime.now(),
    );
  }

  /// Check if snapshot matches current state.
  bool isStale(String currentText, int currentRevision) {
    if (revision != currentRevision) return true;
    final currentHash = sha256.convert(utf8.encode(currentText)).toString();
    return contentHash != currentHash;
  }
}

class SnapshotStore {
  final Map<String, DocumentSnapshot> _snapshots = {};

  /// Snap a document, atomically replacing.
  void snap(String id, DocumentSnapshot snapshot) {
    _snapshots[id] = snapshot;
  }

  /// Get a snapshot.
  DocumentSnapshot? get(String id) => _snapshots[id];

  /// Check staleness.
  bool isStale(String id, String currentText, int currentRevision) {
    final snapshot = _snapshots[id];
    if (snapshot == null) return true;
    return snapshot.isStale(currentText, currentRevision);
  }
}

/// Run all ALG-04 benchmarks.
List<Map<String, dynamic>> runAlg04Benchmarks() {
  final results = <Map<String, dynamic>>[];
  final rng = Random(42);
  final sizes = [1000, 10000, 100000];

  for (final size in sizes) {
    // Generate text
    final text = String.fromCharCodes(
      List.generate(size * 40, (_) => 0x20 + rng.nextInt(95)),
    );

    // Snapshot creation
    final r1 = BenchmarkRunner('snapshot_creation_${size}lines').run(500, (_) {
      DocumentSnapshot.fromDocument('doc_$size', text, 1);
    });
    results.add(r1.toJson());

    // Atomic swap (snap + get)
    final store = SnapshotStore();
    final snapshot = DocumentSnapshot.fromDocument('doc_$size', text, 1);
    final r2 = BenchmarkRunner('atomic_swap_${size}lines').run(500, (_) {
      store.snap('doc_$size', snapshot);
      store.get('doc_$size');
    });
    results.add(r2.toJson());

    // Stale detection (fresh)
    final r3 = BenchmarkRunner('stale_detection_fresh_${size}lines').run(500, (_) {
      snapshot.isStale(text, 1);
    });
    results.add(r3.toJson());

    // Stale detection (stale - different revision)
    final r4 = BenchmarkRunner('stale_detection_stale_revision_${size}lines').run(500, (_) {
      snapshot.isStale(text, 2);
    });
    results.add(r4.toJson());

    // Stale detection (stale - different content)
    final modifiedText = '${text}modified!';
    final r5 = BenchmarkRunner('stale_detection_stale_content_${size}lines').run(500, (_) {
      snapshot.isStale(modifiedText, 1);
    });
    results.add(r5.toJson());
  }

  return results;
}

void main() {
  print('=== ALG-04: Snapshots Benchmarks ===');
  final results = runAlg04Benchmarks();
  for (final r in results) {
    print('  ${r['name']}: mean=${r['meanMs']}ms p95=${r['p95Ms']}ms');
  }
  print('');
}
