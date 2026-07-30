import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/services/project_graph/project_graph.dart';

void main() {
  const parser = StyioProjectGraphParser();
  final workspaceRoot = Uri.parse('file:///workspace');

  test('canonical file model rejects non-project files', () {
    expect(
      () => StyioCanonicalProjectFile.fromPath(
        path: 'src/main.styio',
        content: 'value = 1',
      ),
      throwsArgumentError,
    );
    expect(styioIsCanonicalProjectFilePath('styio.toml'), isTrue);
    expect(styioIsCanonicalProjectFilePath('package.json'), isFalse);
  });

  test('empty project produces a partial workspace graph diagnostic', () {
    final graph = parser.parse(
      workspaceRootUri: workspaceRoot,
      canonicalFiles: _loadGraphFixture('empty'),
    );

    expect(graph.modules, isEmpty);
    expect(graph.nodes.values.single.kind, StyioProjectNodeKind.workspace);
    expect(
      graph.diagnostics.map((diagnostic) => diagnostic.code),
      contains(StyioGraphDiagnosticCode.emptyProject),
    );
  });

  test('multi-module graph builds typed nodes, edges, hash, topo, diff', () {
    final files = _loadGraphFixture('multi_module');
    final graph = parser.parse(
      workspaceRootUri: workspaceRoot,
      canonicalFiles: files,
      hostPlatform: 'web',
    );

    expect(
      graph.modules.map((module) => module.name).toSet(),
      <String>{'demo/core', 'demo/ui', 'demo/app'},
    );
    expect(
      graph.edges.map((edge) => edge.kind).toSet(),
      containsAll(<StyioProjectEdgeKind>[
        StyioProjectEdgeKind.workspaceMember,
        StyioProjectEdgeKind.moduleDependency,
        StyioProjectEdgeKind.targetEntry,
        StyioProjectEdgeKind.toolchainPin,
      ]),
    );
    expect(graph.hasCycles, isFalse);
    expect(graph.toolchain.version, '2026.6.25');
    expect(graph.moduleDependencyGraph(), <String, List<String>>{
      'module:demo/app': <String>['module:demo/core', 'module:demo/ui'],
      'module:demo/core': <String>[],
      'module:demo/ui': <String>['module:demo/core'],
    });
    expect(graph.topologicalOrder, <String>[
      'module:demo/core',
      'module:demo/ui',
      'module:demo/app',
    ]);
    expect(
      graph.affectedSet(<String>{'module:demo/core'}),
      <String>{'module:demo/core', 'module:demo/ui', 'module:demo/app'},
    );

    final sameGraph = parser.parse(
      workspaceRootUri: workspaceRoot,
      canonicalFiles: StyioCanonicalProjectFiles(files.files.reversed.toList()),
      hostPlatform: 'web',
    );
    expect(sameGraph.stableHash, graph.stableHash);

    final changedFiles = StyioCanonicalProjectFiles(
      files.files
          .map(
            (file) => file.normalizedPath == 'modules/core/styio.toml'
                ? StyioCanonicalProjectFile.fromPath(
                    path: file.path,
                    content: file.content.replaceFirst('1.0.0', '1.1.0'),
                  )
                : file,
          )
          .toList(growable: false),
    );
    final changedGraph = parser.parse(
      workspaceRootUri: workspaceRoot,
      canonicalFiles: changedFiles,
      hostPlatform: 'web',
    );
    final diff = graph.diff(changedGraph);
    expect(diff.hasChanges, isTrue);
    expect(diff.changedNodes.map((node) => node.id), contains('module:demo/core'));
    expect(
      diff.changedCanonicalFiles.map((file) => file.normalizedPath),
      contains('modules/core/styio.toml'),
    );
  });

  test('cycle fixture reports Tarjan SCC and blocks Kahn topo sort', () {
    final graph = parser.parse(
      workspaceRootUri: workspaceRoot,
      canonicalFiles: _loadGraphFixture('cycle'),
    );

    expect(graph.hasCycles, isTrue);
    expect(graph.topologicalOrder, isNull);
    expect(
      graph.stronglyConnectedComponents,
      contains(
        equals(<String>[
          'module:cycle/a',
          'module:cycle/b',
          'module:cycle/c',
        ]),
      ),
    );
    expect(
      graph.diagnostics.map((diagnostic) => diagnostic.code),
      containsAll(<StyioGraphDiagnosticCode>[
        StyioGraphDiagnosticCode.dependencyCycle,
        StyioGraphDiagnosticCode.topologicalSortBlocked,
      ]),
    );
  });

  test('missing fixture reports missing workspace member and dependency', () {
    final graph = parser.parse(
      workspaceRootUri: workspaceRoot,
      canonicalFiles: _loadGraphFixture('missing'),
    );

    expect(
      graph.nodes.values.map((node) => node.kind),
      contains(StyioProjectNodeKind.missingModule),
    );
    expect(
      graph.diagnostics.map((diagnostic) => diagnostic.code),
      containsAll(<StyioGraphDiagnosticCode>[
        StyioGraphDiagnosticCode.missingModule,
        StyioGraphDiagnosticCode.missingDependency,
      ]),
    );
  });

  test('version conflict fixture flags incompatible module requirements', () {
    final graph = parser.parse(
      workspaceRootUri: workspaceRoot,
      canonicalFiles: _loadGraphFixture('version_conflict'),
    );

    expect(
      graph.diagnostics.map((diagnostic) => diagnostic.code),
      contains(StyioGraphDiagnosticCode.versionConflict),
    );
  });

  test('platform conflict fixture flags incompatible module platforms', () {
    final graph = parser.parse(
      workspaceRootUri: workspaceRoot,
      canonicalFiles: _loadGraphFixture('platform_conflict'),
      hostPlatform: 'linux',
    );

    expect(
      graph.diagnostics.map((diagnostic) => diagnostic.code),
      contains(StyioGraphDiagnosticCode.platformConflict),
    );
  });
}

StyioCanonicalProjectFiles _loadGraphFixture(String name) {
  final root = Directory('test/fixtures/project_graph/$name');
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) {
        final relativePath = file.path
            .substring(root.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        if (!styioIsCanonicalProjectFilePath(relativePath)) {
          return null;
        }
        return StyioCanonicalProjectFile.fromPath(
          path: relativePath,
          content: file.readAsStringSync(),
          lastModifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
      })
      .whereType<StyioCanonicalProjectFile>()
      .toList()
    ..sort((left, right) => left.normalizedPath.compareTo(right.normalizedPath));
  return StyioCanonicalProjectFiles(files);
}

