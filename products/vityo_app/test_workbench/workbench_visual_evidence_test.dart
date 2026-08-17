import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_render/shell/workbench_regions/workbench_regions.dart';
import 'package:vityo_app/src/view_render/theme/vityo_theme.dart';

void main() {
  const sizes = <Size>[
    Size(1440, 900),
    Size(1024, 768),
    Size(600, 800),
    Size(360, 720),
  ];

  for (final dark in <bool>[false, true]) {
    for (final size in sizes) {
      testWidgets(
        'renders ${dark ? 'dark' : 'light'} workbench at ${size.width}x${size.height}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? VityoTheme.dark() : VityoTheme.light(),
              home: const _EvidenceWorkbench(),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('workbench-title-bar')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('workbench-status-bar')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('workbench-editor-anchor')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('workbench-evidence-boundary')),
            );
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            expect(bytes, isNotNull);
            expect(bytes!.lengthInBytes, greaterThan(1000));
            image.dispose();
          });
        },
      );
    }
  }
}

class _EvidenceWorkbench extends StatefulWidget {
  const _EvidenceWorkbench();

  @override
  State<_EvidenceWorkbench> createState() => _EvidenceWorkbenchState();
}

class _EvidenceWorkbenchState extends State<_EvidenceWorkbench> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('workbench-evidence-boundary'),
    child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            WorkbenchTitleBar(
              title: 'Vityo — example.styio',
              commandHint: 'Search files or run a command',
              connectionLabel: 'Connected · revision 42',
              onOpenCommands: () {},
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 600) {
                    return Column(
                      children: [
                        Expanded(child: _editor()),
                        const SizedBox(
                          height: 180,
                          child: WorkbenchRegionSurface(
                            label: 'Terminal',
                            child: _Rows(prefix: r'$ ', count: 24),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      WorkbenchActivityRail(
                        destinations: const <WorkbenchDestination>[
                          WorkbenchDestination(
                            label: 'Explorer',
                            icon: Icons.folder_outlined,
                          ),
                          WorkbenchDestination(
                            label: 'Search',
                            icon: Icons.search,
                          ),
                          WorkbenchDestination(
                            label: 'Source control',
                            icon: Icons.fork_right,
                          ),
                          WorkbenchDestination(
                            label: 'Coding Agent',
                            icon: Icons.auto_awesome_outlined,
                          ),
                        ],
                        selectedIndex: selected,
                        onSelected: (value) => setState(() => selected = value),
                      ),
                      if (constraints.maxWidth >= 760)
                        const SizedBox(
                          width: 220,
                          child: WorkbenchRegionSurface(
                            label: 'Explorer',
                            child: _Rows(prefix: 'lib/', count: 40),
                          ),
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(child: _editor()),
                            const SizedBox(
                              height: 180,
                              child: WorkbenchRegionSurface(
                                label: 'Terminal',
                                child: _Rows(prefix: r'$ ', count: 100000),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (constraints.maxWidth >= 1200)
                        const WorkbenchAuxiliaryPanel(
                          label: 'Coding Agent',
                          child: _Rows(prefix: 'Task ', count: 100000),
                        ),
                    ],
                  );
                },
              ),
            ),
            const WorkbenchStatusBar(
              leading: 'main · 0 problems',
              trailing: 'Styio · UTF-8 · Ln 12, Col 4',
            ),
          ],
        ),
      ),
    ),
  );

  Widget _editor() => const ColoredBox(
    key: ValueKey('workbench-editor-anchor'),
    color: Colors.transparent,
    child: Center(child: Text('editor source buffer')),
  );
}

class _Rows extends StatelessWidget {
  const _Rows({required this.prefix, required this.count});

  final String prefix;
  final int count;

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: count,
    itemExtent: 24,
    itemBuilder: (context, index) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '$prefix$index',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}
