import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_quick_open.dart';

void main() {
  test('workspace quick open returns recent files first for an empty query', () {
    final result = const WorkspaceQuickOpenService().findFiles(
      filePaths: const <String>[
        'src/main.styio',
        'src/worker.styio',
        'README.md',
        'src/main.styio',
      ],
      recentFilePaths: const <String>[
        'src/worker.styio',
        'missing.styio',
        'src/main.styio',
      ],
      query: const WorkspaceQuickOpenQuery(maxResults: 2),
    );

    expect(result.status, WorkspaceQuickOpenStatus.hitLimit);
    expect(result.hitLimit, isTrue);
    expect(result.filesSearched, 3);
    expect(
      result.items.map((item) => item.filePath),
      <String>['src/worker.styio', 'src/main.styio'],
    );
    expect(result.items.map((item) => item.recentRank), <int?>[0, 1]);
  });

  test('workspace quick open scores fuzzy filename matches', () {
    final result = const WorkspaceQuickOpenService().findFiles(
      filePaths: const <String>[
        'src/view_ide/workspace/workspace_search.dart',
        'src/view_ide/workspace/workspace_quick_open.dart',
        'src/runtime/project_graph.dart',
      ],
      query: const WorkspaceQuickOpenQuery(pattern: 'wqo'),
    );

    expect(result.status, WorkspaceQuickOpenStatus.completed);
    expect(
      result.items.first.filePath,
      'src/view_ide/workspace/workspace_quick_open.dart',
    );
    expect(result.items.first.fileName, 'workspace_quick_open.dart');
    expect(result.items.first.parentPath, 'src/view_ide/workspace');
    expect(result.items.first.matches, isNotEmpty);
  });

  test('workspace quick open narrows by path substring', () {
    final result = const WorkspaceQuickOpenService().findFiles(
      filePaths: const <String>[
        'lib/runtime/project_graph.dart',
        'lib/workspace/project_graph.dart',
        'lib/workspace/runtime_surface.dart',
      ],
      query: const WorkspaceQuickOpenQuery(pattern: 'runtime/project'),
    );

    expect(result.matchCount, 1);
    expect(result.items.single.filePath, 'lib/runtime/project_graph.dart');
  });

// FIXME: WorkspaceController.recentFiles was removed during the subbranch merge.
// The recent-files tracking was refactored into WorkspaceQuickOpenService.
// This test needs to be rewritten against the new API.
// FIXME: test('workspace controller tracks recent opened files across project refreshes', ...
}

// FIXME: _projectGraph helper was removed along with the recentFiles test.
// ProjectGraphSnapshot is from backend_toolchain, imported via workspace barrel.
// When the test is rewritten, restore the appropriate helper.
