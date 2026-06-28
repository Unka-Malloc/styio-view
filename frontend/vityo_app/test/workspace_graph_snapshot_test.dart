import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/backend_toolchain/workspace_graph_snapshot.dart';

void main() {
  group('CanonicalFileEntry', () {
    test('creates a canonical file entry with required fields', () {
      final entry = CanonicalFileEntry(
        filePath: '/workspace/spio.toml',
        contentHash: 'abc123',
        lastModifiedAt: DateTime(2026, 6, 24, 12, 0, 0),
      );

      expect(entry.filePath, '/workspace/spio.toml');
      expect(entry.contentHash, 'abc123');
      expect(entry.lastModifiedAt, DateTime(2026, 6, 24, 12, 0, 0));
    });

    test('equality is based on filePath and contentHash', () {
      final a = CanonicalFileEntry(
        filePath: '/workspace/spio.toml',
        contentHash: 'abc123',
        lastModifiedAt: DateTime(2026, 6, 24),
      );
      final b = CanonicalFileEntry(
        filePath: '/workspace/spio.toml',
        contentHash: 'abc123',
        lastModifiedAt: DateTime(2026, 6, 25), // different time
      );
      final c = CanonicalFileEntry(
        filePath: '/workspace/spio.toml',
        contentHash: 'def456',
        lastModifiedAt: DateTime(2026, 6, 24),
      );

      expect(a == b, isTrue); // Same path + hash = equal
      expect(a == c, isFalse); // Different hash = not equal
    });

    test('copyWith preserves or overrides fields', () {
      final entry = CanonicalFileEntry(
        filePath: '/workspace/spio.toml',
        contentHash: 'abc123',
        lastModifiedAt: DateTime(2026, 6, 24),
      );

      final copied = entry.copyWith(contentHash: 'def456');
      expect(copied.filePath, '/workspace/spio.toml');
      expect(copied.contentHash, 'def456');
      expect(copied.lastModifiedAt, DateTime(2026, 6, 24));
    });
  });

  group('GraphDiagnostic', () {
    test('creates a diagnostic with required fields', () {
      final diag = const GraphDiagnostic(
        severity: 'error',
        message: 'Dependency cycle detected: a -> b -> a',
        source: 'package-a',
        code: 'cycle_detected',
      );

      expect(diag.severity, 'error');
      expect(diag.message, contains('cycle'));
      expect(diag.source, 'package-a');
      expect(diag.code, 'cycle_detected');
    });

    test('equality compares all fields', () {
      final a = const GraphDiagnostic(
        severity: 'warning', message: 'test', source: 'src', code: 'w001',
      );
      final b = const GraphDiagnostic(
        severity: 'warning', message: 'test', source: 'src', code: 'w001',
      );
      final c = const GraphDiagnostic(
        severity: 'error', message: 'test', source: 'src', code: 'w001',
      );

      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });
  });

  group('WorkspaceGraphSnapshot', () {
    final defaultToolchain = const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.unavailable,
      detail: 'Test toolchain.',
    );

    final defaultUri = Uri.parse('file:///workspace');

    test('creates a minimal valid snapshot', () {
      final snapshot = WorkspaceGraphSnapshot(
        snapshotId: 'test-001',
        workspaceRootUri: defaultUri,
        graphHash: 'hash001',
        createdAt: DateTime(2026, 6, 24),
        toolchain: defaultToolchain,
      );

      expect(snapshot.snapshotId, 'test-001');
      expect(snapshot.workspaceRootUri, defaultUri);
      expect(snapshot.graphHash, 'hash001');
      expect(snapshot.packages, isEmpty);
      expect(snapshot.targets, isEmpty);
      expect(snapshot.dependencies, isEmpty);
      expect(snapshot.graphCompleteness, GraphCompleteness.full);
      expect(snapshot.isPartial, isFalse);
      expect(snapshot.isHosted, isFalse);
      expect(snapshot.hasErrors, isFalse);
      expect(snapshot.hasCycles, isFalse);
    });

    test('creates a partial snapshot with reason', () {
      final snapshot = WorkspaceGraphSnapshot(
        snapshotId: 'partial-001',
        workspaceRootUri: defaultUri,
        graphHash: 'hash-partial',
        createdAt: DateTime(2026, 6, 24),
        toolchain: defaultToolchain,
        graphCompleteness: GraphCompleteness.partial,
        partialReason: 'Missing canonical files.',
        upstreamPayloadMissing: true,
      );

      expect(snapshot.isPartial, isTrue);
      expect(snapshot.partialReason, 'Missing canonical files.');
      expect(snapshot.upstreamPayloadMissing, isTrue);
    });

    test('empty factory creates a partial snapshot', () {
      final snapshot = WorkspaceGraphSnapshot.empty(
        workspaceRootUri: defaultUri,
        toolchain: defaultToolchain,
        partialReason: 'No files found.',
      );

      expect(snapshot.isPartial, isTrue);
      expect(snapshot.graphHash, '');
      expect(snapshot.diagnostics, isNotEmpty);
      expect(snapshot.upstreamPayloadMissing, isTrue);
      expect(
        snapshot.diagnostics.any((d) => d.code == 'empty_snapshot'),
        isTrue,
      );
    });

    test('hosted workspace indicates isHosted', () {
      final hosted = HostedWorkspaceRecordSnapshot(
        workspaceId: 'ws-001',
        schemaVersion: '1.0',
        ownerRef: 'user-001',
        status: HostedWorkspaceStatus.active,
        entryUrl: 'https://hosted.example/ws-001',
        createdAt: DateTime(2026, 6, 24),
        lastActiveAt: DateTime(2026, 6, 24),
        retentionDays: 7,
        exportState: HostedWorkspaceExportState.notRequested,
      );

      final snapshot = WorkspaceGraphSnapshot(
        snapshotId: 'hosted-001',
        workspaceRootUri: defaultUri,
        graphHash: 'hash-hosted',
        createdAt: DateTime(2026, 6, 24),
        toolchain: defaultToolchain,
        hostedWorkspace: hosted,
      );

      expect(snapshot.isHosted, isTrue);
      expect(snapshot.hostedWorkspace?.workspaceId, 'ws-001');
      expect(snapshot.hostedWorkspace?.status, HostedWorkspaceStatus.active);
    });

    test('detects error diagnostics', () {
      final snapshot = WorkspaceGraphSnapshot(
        snapshotId: 'err-001',
        workspaceRootUri: defaultUri,
        graphHash: 'hash-err',
        createdAt: DateTime(2026, 6, 24),
        toolchain: defaultToolchain,
        diagnostics: [
          const GraphDiagnostic(
            severity: 'error',
            message: 'Test error',
            code: 'test_error',
          ),
          const GraphDiagnostic(
            severity: 'warning',
            message: 'Test warning',
            code: 'test_warning',
          ),
        ],
      );

      expect(snapshot.hasErrors, isTrue);
      expect(snapshot.diagnosticCount, 2);
    });

    test('detects cycle diagnostics', () {
      final snapshot = WorkspaceGraphSnapshot(
        snapshotId: 'cycle-001',
        workspaceRootUri: defaultUri,
        graphHash: 'hash-cycle',
        createdAt: DateTime(2026, 6, 24),
        toolchain: defaultToolchain,
        diagnostics: [
          const GraphDiagnostic(
            severity: 'error',
            message: 'Cycle: a -> b -> a',
            code: 'cycle_detected',
          ),
        ],
      );

      expect(snapshot.hasCycles, isTrue);
    });

    test('rootPackages returns packages with no incoming edges', () {
      final snapshot = WorkspaceGraphSnapshot(
        snapshotId: 'root-test',
        workspaceRootUri: defaultUri,
        graphHash: 'hash-root',
        createdAt: DateTime(2026, 6, 24),
        toolchain: defaultToolchain,
        packages: <String, List<String>>{
          'app': ['core', 'utils'],
          'core': ['utils'],
          'utils': <String>[],
          'standalone': <String>[],
        },
      );

      final roots = snapshot.rootPackages;
      expect(roots, containsAll(['app', 'standalone']));
      expect(roots, isNot(contains('core')));
      expect(roots, isNot(contains('utils')));
    });

    test('copyWith allows partial updates', () {
      final original = WorkspaceGraphSnapshot(
        snapshotId: 'orig',
        workspaceRootUri: defaultUri,
        graphHash: 'hash1',
        createdAt: DateTime(2026, 6, 24),
        toolchain: defaultToolchain,
      );

      final updated = original.copyWith(
        graphHash: 'hash2',
        diagnostics: [
          const GraphDiagnostic(severity: 'info', message: 'Updated.'),
        ],
      );

      expect(updated.snapshotId, 'orig');
      expect(updated.graphHash, 'hash2');
      expect(updated.diagnostics.single.message, 'Updated.');
    });

    test('package, dependency, target, canonical file counts', () {
      final snapshot = WorkspaceGraphSnapshot(
        snapshotId: 'counts',
        workspaceRootUri: defaultUri,
        graphHash: 'hash-cnt',
        createdAt: DateTime(2026, 6, 24),
        toolchain: defaultToolchain,
        packages: <String, List<String>>{
          'pkg1': <String>[],
          'pkg2': <String>[],
          'pkg3': <String>[],
        },
        dependencies: [
          const ProjectDependencySnapshot(
            sourcePackageName: 'pkg1',
            dependencyName: 'dep1',
            kind: ProjectDependencyKind.runtime,
            requirement: '^1.0.0',
          ),
        ],
        targets: [
          const ProjectTargetDescriptor(
            id: 'pkg1:lib:lib',
            packageName: 'pkg1',
            kind: ProjectTargetKind.lib,
            name: 'lib',
            filePath: '/workspace/packages/pkg1/src/lib.styio',
          ),
        ],
        canonicalFiles: [
          CanonicalFileEntry(
            filePath: '/workspace/spio.toml',
            contentHash: 'h1',
            lastModifiedAt: DateTime(2026, 6, 24),
          ),
        ],
      );

      expect(snapshot.packageCount, 3);
      expect(snapshot.dependencyCount, 1);
      expect(snapshot.targetCount, 1);
      expect(snapshot.canonicalFileCount, 1);
    });
  });
}
