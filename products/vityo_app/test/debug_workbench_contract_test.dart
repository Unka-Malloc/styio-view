import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/runtime/debug_workbench_contract.dart';

void main() {
  group('Breakpoint', () {
    test('tracks location and verification state', () {
      const bp = Breakpoint(
        breakpointId: 'bp-1',
        filePath: 'main.styio',
        line: 42,
        enabled: true,
        verified: false,
        verificationMessage: 'Pending adapter check',
      );
      expect(bp.breakpointId, 'bp-1');
      expect(bp.filePath, 'main.styio');
      expect(bp.line, 42);
      expect(bp.enabled, isTrue);
      expect(bp.verified, isFalse);
    });

    test('conditional breakpoint has condition', () {
      const bp = Breakpoint(
        breakpointId: 'bp-2',
        filePath: 'lib.styio',
        line: 100,
        column: 5,
        condition: 'x > 10',
        enabled: true,
      );
      expect(bp.condition, 'x > 10');
      expect(bp.column, 5);
    });

    test('serializes to JSON', () {
      const bp = Breakpoint(
        breakpointId: 'bp-3',
        filePath: 'test.styio',
        line: 15,
        condition: '',
        enabled: false,
        verified: true,
      );
      final json = bp.toJson();
      expect(json['breakpointId'], 'bp-3');
      expect(json['line'], 15);
      expect(json['enabled'], isFalse);
      expect(json['verified'], isTrue);
    });
  });

  group('BreakpointSet', () {
    test('isEmpty when no breakpoints', () {
      const bpSet = BreakpointSet();
      expect(bpSet.isEmpty, isTrue);
      expect(bpSet.enabledCount, 0);
    });

    test('counts enabled breakpoints', () {
      const bpSet = BreakpointSet(breakpoints: [
        Breakpoint(breakpointId: '1', filePath: 'a.styio', line: 1),
        Breakpoint(breakpointId: '2', filePath: 'a.styio', line: 5,
            enabled: false),
        Breakpoint(breakpointId: '3', filePath: 'b.styio', line: 10),
      ]);
      expect(bpSet.isEmpty, isFalse);
      expect(bpSet.enabledCount, 2);
    });

    test('filters by file path', () {
      const bpSet = BreakpointSet(breakpoints: [
        Breakpoint(breakpointId: '1', filePath: 'a.styio', line: 1),
        Breakpoint(breakpointId: '2', filePath: 'a.styio', line: 5),
        Breakpoint(breakpointId: '3', filePath: 'b.styio', line: 10),
      ]);
      final aBps = bpSet.forFile('a.styio');
      expect(aBps.length, 2);
      final bBps = bpSet.forFile('b.styio');
      expect(bBps.length, 1);
      final cBps = bpSet.forFile('c.styio');
      expect(cBps, isEmpty);
    });
  });

  group('RunConfiguration', () {
    test('isBlocked when not available', () {
      const config = RunConfiguration(
        configurationId: 'cfg-1',
        kind: RunConfigurationKind.projectTarget,
        label: 'Build project',
        available: false,
        blockedReason: 'No toolchain installed',
      );
      expect(config.isBlocked, isTrue);
      expect(config.blockedReason, 'No toolchain installed');
    });

    test('available when not blocked', () {
      const config = RunConfiguration(
        configurationId: 'cfg-2',
        kind: RunConfigurationKind.minimalCompilableUnit,
        label: 'Run current file',
        available: true,
      );
      expect(config.isBlocked, isFalse);
    });

    test('serializes to JSON with kind name', () {
      const config = RunConfiguration(
        configurationId: 'cfg-3',
        kind: RunConfigurationKind.testTarget,
        label: 'Run tests',
        target: RunConfigurationTarget(
          targetName: 'unit_tests',
          targetKind: 'test',
          filePath: 'tests/',
        ),
        buildBeforeRun: true,
      );
      final json = config.toJson();
      expect(json['configurationId'], 'cfg-3');
      expect(json['kind'], 'testTarget');
      expect(json['buildBeforeRun'], isTrue);
    });
  });

  group('DebugSessionSnapshot', () {
    test('isBlocked when not available', () {
      const session = DebugSessionSnapshot(
        sessionId: 'sess-1',
        status: DebugSessionStatus.idle,
        available: false,
        blockedReason: 'Styio runtime debug contract not yet published.',
      );
      expect(session.isBlocked, isTrue);
      expect(session.available, isFalse);
    });

    test('isStopped when status is stopped', () {
      const session = DebugSessionSnapshot(
        sessionId: 'sess-2',
        status: DebugSessionStatus.stopped,
        stoppedReason: DebugStoppedReason.breakpoint,
        stoppedFilePath: 'main.styio',
        stoppedLine: 42,
        available: true,
      );
      expect(session.isStopped, isTrue);
      expect(session.stoppedReason, DebugStoppedReason.breakpoint);
      expect(session.stoppedFilePath, 'main.styio');
      expect(session.stoppedLine, 42);
    });

    test('serializes with stack frames', () {
      const session = DebugSessionSnapshot(
        sessionId: 'sess-3',
        status: DebugSessionStatus.stopped,
        stoppedReason: DebugStoppedReason.step,
        stoppedFilePath: 'lib.styio',
        stoppedLine: 100,
        stackFrames: [
          StackFrameSnapshot(
            frameId: 0,
            name: 'main',
            filePath: 'main.styio',
            line: 10,
          ),
          StackFrameSnapshot(
            frameId: 1,
            name: 'helper',
            filePath: 'lib.styio',
            line: 100,
          ),
        ],
        variables: [
          RuntimeVariableSnapshot(
            variableId: 1,
            name: 'x',
            value: '42',
            typeName: 'int',
          ),
        ],
        available: true,
      );
      final json = session.toJson();
      expect(json['status'], 'stopped');
      expect((json['stackFrames'] as List).length, 2);
      expect((json['variables'] as List).length, 1);
    });

    test('default blocked reason mentions Styio', () {
      const session = DebugSessionSnapshot(
        sessionId: 'sess-4',
        status: DebugSessionStatus.idle,
      );
      expect(session.blockedReason,
          'Styio runtime debug contract not yet published.');
    });
  });

  group('RuntimeCommandAvailability', () {
    test('debug commands are blocked by default with reasons', () {
      const availability = RuntimeCommandAvailability();
      expect(availability.canRun, isTrue);
      expect(availability.canBuild, isTrue);
      expect(availability.canTest, isTrue);
      expect(availability.canDebug, isFalse);
      expect(availability.canSetBreakpoints, isFalse);
      expect(availability.canStep, isFalse);
      expect(availability.canInspectVariables, isFalse);
      expect(availability.canReplayRuntimeEvents, isTrue);
      expect(availability.canStreamRuntimeEvents, isFalse);
      // All blocked reasons are present
      expect(availability.blockedDebugReason, isNotEmpty);
      expect(availability.blockedBreakpointReason, isNotEmpty);
      expect(availability.blockedStepReason, isNotEmpty);
      expect(availability.blockedVariableReason, isNotEmpty);
    });

    test('serializes all capability flags and blocked reasons', () {
      const availability = RuntimeCommandAvailability(
        canDebug: true,
        canSetBreakpoints: true,
        blockedStepReason: 'Step not supported on this platform',
      );
      final json = availability.toJson();
      expect(json['canRun'], isTrue);
      expect(json['canDebug'], isTrue);
      expect(json['canSetBreakpoints'], isTrue);
      expect(json['canStep'], isFalse);
      expect(json['blockedStepReason'], 'Step not supported on this platform');
    });
  });

  group('StackFrameSnapshot', () {
    test('serializes to JSON', () {
      const frame = StackFrameSnapshot(
        frameId: 0,
        name: 'compute',
        filePath: 'math.styio',
        line: 42,
        column: 5,
      );
      final json = frame.toJson();
      expect(json['frameId'], 0);
      expect(json['name'], 'compute');
      expect(json['filePath'], 'math.styio');
      expect(json['line'], 42);
      expect(json['column'], 5);
    });
  });

  group('RuntimeVariableSnapshot', () {
    test('serializes nested variables', () {
      const variable = RuntimeVariableSnapshot(
        variableId: 1,
        name: 'result',
        value: '{...}',
        typeName: 'Struct',
        children: [
          RuntimeVariableSnapshot(
            variableId: 2,
            name: 'field_a',
            value: '10',
            typeName: 'int',
          ),
          RuntimeVariableSnapshot(
            variableId: 3,
            name: 'field_b',
            value: '"hello"',
            typeName: 'string',
          ),
        ],
      );
      final json = variable.toJson();
      expect(json['variableId'], 1);
      expect(json['name'], 'result');
      expect(json['typeName'], 'Struct');
      expect((json['children'] as List).length, 2);
    });
  });

  group('DebugSessionStatus lifecycle', () {
    test('status enum covers full lifecycle', () {
      const statuses = DebugSessionStatus.values;
      final names = statuses.map((s) => s.name).toSet();
      expect(names.contains('idle'), isTrue);
      expect(names.contains('launching'), isTrue);
      expect(names.contains('running'), isTrue);
      expect(names.contains('stopped'), isTrue);
      expect(names.contains('terminated'), isTrue);
      expect(names.contains('failed'), isTrue);
    });
  });

  group('DebugStoppedReason', () {
    test('covers standard stop reasons', () {
      const reasons = DebugStoppedReason.values;
      final names = reasons.map((r) => r.name).toSet();
      expect(names.contains('breakpoint'), isTrue);
      expect(names.contains('step'), isTrue);
      expect(names.contains('exception'), isTrue);
      expect(names.contains('pause'), isTrue);
      expect(names.contains('entry'), isTrue);
    });
  });
}
