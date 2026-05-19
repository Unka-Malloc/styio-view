import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/source_control/source_control.dart';

void main() {
  testWidgets('source control surface renders dirty documents and actions', (
    tester,
  ) async {
    String? openedDocumentId;
    var saveAllCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceControlSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            workspaceFileCount: 3,
            changedDocumentIds: const <String>[
              'src/main.styio',
              'src/lib.styio',
            ],
            status: const GitPorcelainStatusParser().parse('''
## ai-dev...origin/ai-dev
 M src/main.styio
R  src/old.styio -> src/new.styio
'''),
            onOpenFile: (documentId) async {
              openedDocumentId = documentId;
            },
            onSaveAll: () async {
              saveAllCount += 1;
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('source-control-surface')),
      findsOneWidget,
    );
    expect(find.text('Source Control'), findsOneWidget);
    expect(find.text('workspace-files 3'), findsOneWidget);
    expect(find.text('changed 2'), findsOneWidget);
    expect(find.text('provider git'), findsOneWidget);
    expect(find.text('branch ai-dev'), findsOneWidget);
    expect(find.text('git 2'), findsOneWidget);
    expect(find.text('src/new.styio'), findsOneWidget);
    expect(find.text('src/main.styio'), findsWidgets);
    expect(find.text('src/lib.styio'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('source-control-git-change-src/new.styio')),
    );
    await tester.pump();
    expect(openedDocumentId, 'src/new.styio');

    await tester.tap(
      find.byKey(const ValueKey('source-control-change-src/main.styio')),
    );
    await tester.tap(find.byKey(const ValueKey('source-control-save-all')));
    await tester.pump();

    expect(openedDocumentId, 'src/main.styio');
    expect(saveAllCount, 1);
  });
}
