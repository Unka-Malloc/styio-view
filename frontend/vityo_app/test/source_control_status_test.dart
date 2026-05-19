import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('git porcelain status parser records branch and file states', () {
    final snapshot = const GitPorcelainStatusParser().parse('''
## feature/scm...origin/feature/scm
 M lib/main.styio
A  lib/new.styio
R  lib/old.styio -> lib/renamed.styio
?? notes/todo.md
''');

    expect(snapshot.providerKind, SourceControlProviderKind.git);
    expect(snapshot.branchName, 'feature/scm');
    expect(snapshot.clean, isFalse);
    expect(snapshot.changes.map((change) => change.path), <String>[
      'lib/main.styio',
      'lib/new.styio',
      'lib/renamed.styio',
      'notes/todo.md',
    ]);
    expect(
      snapshot.changes.first.unstagedStatus,
      SourceControlFileStatus.modified,
    );
    expect(snapshot.changes[1].stagedStatus, SourceControlFileStatus.added);
    expect(snapshot.changes[2].originalPath, 'lib/old.styio');
    expect(snapshot.changes[2].stagedStatus, SourceControlFileStatus.renamed);
    expect(
      snapshot.changes.last.stagedStatus,
      SourceControlFileStatus.untracked,
    );
  });
}
