import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_breakpoint_store.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('debug breakpoint set replaces file breakpoints deterministically', () {
    const set = DebugBreakpointSet(
      workspaceId: 'demo',
      breakpoints: <DebugLaunchBreakpoint>[
        DebugLaunchBreakpoint(filePath: '/workspace/main.styio', line: 1),
        DebugLaunchBreakpoint(filePath: '/workspace/other.styio', line: 9),
      ],
    );

    final next = set.replaceFileBreakpoints(
      filePath: '/workspace/main.styio',
      breakpoints: const <DebugLaunchBreakpoint>[
        DebugLaunchBreakpoint(filePath: 'ignored.styio', line: 4),
        DebugLaunchBreakpoint(
          filePath: 'ignored.styio',
          line: 2,
          enabled: false,
        ),
        DebugLaunchBreakpoint(filePath: 'ignored.styio', line: 0),
      ],
    );

    expect(
      next.breakpoints
          .map(
            (breakpoint) =>
                '${breakpoint.filePath}:${breakpoint.line}:${breakpoint.enabled}',
          )
          .toList(growable: false),
      <String>[
        '/workspace/main.styio:2:false',
        '/workspace/main.styio:4:true',
        '/workspace/other.styio:9:true',
      ],
    );
    expect(next.breakpointsForFile('/workspace/main.styio'), hasLength(2));
    expect(
      DebugBreakpointSet.fromJson(next.toJson()).breakpoints,
      hasLength(3),
    );
  });

  test('debug breakpoint store persists workspace breakpoints', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_debug_breakpoint_store_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final dataStore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    );
    final store = DebugBreakpointStore.fromDataStore(dataStore: dataStore);

    await store.saveBreakpointSet(
      const DebugBreakpointSet(
        workspaceId: 'demo',
        breakpoints: <DebugLaunchBreakpoint>[
          DebugLaunchBreakpoint(filePath: '/workspace/main.styio', line: 12),
        ],
      ),
    );
    final updated = await store.replaceFileBreakpoints(
      workspaceId: 'demo',
      filePath: '/workspace/main.styio',
      breakpoints: const <DebugLaunchBreakpoint>[
        DebugLaunchBreakpoint(filePath: '/workspace/main.styio', line: 20),
      ],
    );
    final persisted = await store.readBreakpointSet(workspaceId: 'demo');

    expect(updated.breakpoints.single.line, 20);
    expect(persisted.workspaceId, 'demo');
    expect(persisted.breakpoints.single.filePath, '/workspace/main.styio');
    expect(persisted.breakpoints.single.line, 20);
    expect(await store.deleteBreakpointSet(workspaceId: 'demo'), isTrue);
    expect(
      await store.readBreakpointSet(workspaceId: 'demo'),
      isA<DebugBreakpointSet>()
          .having((set) => set.workspaceId, 'workspaceId', 'demo')
          .having((set) => set.breakpoints, 'breakpoints', isEmpty),
    );
  });
}
