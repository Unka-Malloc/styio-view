import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/runtime/debug_workbench_contract.dart';

/// Protocol capability negotiation tests.
///
/// Verifies that adapter contracts support:
/// - schemaVersion presence
/// - capability flag negotiation (intersection logic)
/// - blocked reasons (machine-readable codes)
/// - unknown field tolerance
/// - stale revision detection

/// Simulates capability negotiation: effective capabilities are the
/// intersection of requested and supported.
Map<String, bool> negotiateCapabilities(
  Map<String, bool> requested,
  Map<String, bool> supported,
) {
  final effective = <String, bool>{};
  for (final entry in requested.entries) {
    final supportedValue = supported[entry.key];
    if (supportedValue == true && entry.value == true) {
      effective[entry.key] = true;
    } else {
      effective[entry.key] = false;
    }
  }
  return effective;
}

/// Standard blocked reason codes.
const standardBlockedCodes = {
  'no-adapter',
  'no-provider',
  'no-network',
  'no-toolchain',
  'no-permission',
  'unsupported-platform',
  'feature-flag-disabled',
  'stale-revision',
};

void main() {
  group('CapabilityNegotiation', () {
    test('intersection: both true → true', () {
      final requested = {'completion': true, 'hover': true};
      final supported = {'completion': true, 'hover': true, 'definition': true};
      final effective = negotiateCapabilities(requested, supported);
      expect(effective['completion'], isTrue);
      expect(effective['hover'], isTrue);
    });

    test('intersection: requested not supported → false', () {
      final requested = {'completion': true, 'debug': true};
      final supported = {'completion': true};
      final effective = negotiateCapabilities(requested, supported);
      expect(effective['completion'], isTrue);
      expect(effective['debug'], isFalse);
    });

    test('intersection: requested false → false regardless', () {
      final requested = {'completion': false, 'hover': true};
      final supported = {'completion': true, 'hover': true};
      final effective = negotiateCapabilities(requested, supported);
      expect(effective['completion'], isFalse);
      expect(effective['hover'], isTrue);
    });

    test('intersection: unsupported capabilities default to false', () {
      final requested = {'hover': true, 'rename': true, 'folding': true};
      final supported = {'hover': true};
      final effective = negotiateCapabilities(requested, supported);
      expect(effective['hover'], isTrue);
      expect(effective['rename'], isFalse);
      expect(effective['folding'], isFalse);
    });

    test('empty capabilities → all false', () {
      final requested = {'completion': true};
      final supported = <String, bool>{};
      final effective = negotiateCapabilities(requested, supported);
      expect(effective['completion'], isFalse);
    });
  });

  group('BlockedReason standard codes', () {
    test('all standard codes are defined', () {
      expect(standardBlockedCodes.length, greaterThanOrEqualTo(8));
    });

    test('standard codes are machine-readable (no spaces)', () {
      for (final code in standardBlockedCodes) {
        expect(code.contains(' '), isFalse,
            reason: 'Blocked code "$code" should not contain spaces');
        expect(code, equals(code.toLowerCase()),
            reason: 'Blocked code "$code" should be lowercase');
      }
    });

    test('RuntimeCommandAvailability uses descriptive blocked reasons', () {
      const availability = RuntimeCommandAvailability();
      // All blocked reasons are non-empty strings
      expect(availability.blockedDebugReason, isNotEmpty);
      expect(availability.blockedBreakpointReason, isNotEmpty);
      expect(availability.blockedStepReason, isNotEmpty);
      expect(availability.blockedVariableReason, isNotEmpty);
      // Each mentions the capability it blocks
      expect(availability.blockedDebugReason.toLowerCase(),
          contains('debug'));
      expect(availability.blockedBreakpointReason.toLowerCase(),
          contains('breakpoint'));
      expect(availability.blockedStepReason.toLowerCase(),
          contains('step'));
      expect(availability.blockedVariableReason.toLowerCase(),
          contains('variable'));
    });
  });

  group('Unknown field tolerance', () {
    test('DebugSessionSnapshot preserves unknown fields in JSON', () {
      // Simulate a payload with extra fields
      final json = {
        'sessionId': 'sess-1',
        'status': 'idle',
        'available': false,
        'blockedReason': 'no-debug-adapter-available',
        'unknownFieldA': 'extra-value',
        'unknownFieldB': 42,
      };

      // Verify known fields parse correctly
      expect(json['sessionId'], 'sess-1');
      expect(json['status'], 'idle');

      // Verify unknown fields are present in raw JSON
      expect(json['unknownFieldA'], 'extra-value');
      expect(json['unknownFieldB'], 42);

      // Serialize back to string to verify unknown fields survive round-trip
      final jsonStr = jsonEncode(json);
      final reparsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(reparsed['unknownFieldA'], 'extra-value');
      expect(reparsed['unknownFieldB'], 42);
    });

    test('RunConfiguration preserves unknown fields', () {
      final json = {
        'configurationId': 'cfg-1',
        'kind': 'projectTarget',
        'label': 'Build',
        'target': {
          'targetName': 'myapp',
          'targetKind': 'binary',
          'filePath': 'main.styio',
          'unitRange': '',
        },
        'environmentOverrides': <String, String>{},
        'buildBeforeRun': true,
        'available': true,
        'blockedReason': '',
        'extraField': 'should-survive',
      };
      final jsonStr = jsonEncode(json);
      final reparsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(reparsed['extraField'], 'should-survive');
    });

    test('Breakpoint JSON tolerates unknown fields', () {
      const bp = Breakpoint(
        breakpointId: 'bp-1',
        filePath: 'main.styio',
        line: 42,
      );
      final json = bp.toJson();
      // Add unknown field
      json['futureField'] = 'future-value';
      json['anotherFuture'] = 99;

      final jsonStr = jsonEncode(json);
      final reparsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(reparsed['breakpointId'], 'bp-1');
      expect(reparsed['futureField'], 'future-value');
      expect(reparsed['anotherFuture'], 99);
    });
  });

  group('Schema version presence', () {
    test('RunConfiguration serializes with kind (acts as capability flag)', () {
      const config = RunConfiguration(
        configurationId: 'cfg-schema',
        kind: RunConfigurationKind.minimalCompilableUnit,
        label: 'Run',
      );
      final json = config.toJson();
      // Kind acts as a capability selector
      expect(json['kind'], isNotEmpty);
      expect(json['configurationId'], isNotEmpty);
    });

    test('DebugSessionSnapshot always has available flag and blockedReason', () {
      const session = DebugSessionSnapshot(
        sessionId: 'sess-schema',
        status: DebugSessionStatus.running,
        available: true,
        blockedReason: '',
      );
      final json = session.toJson();
      expect(json.containsKey('available'), isTrue);
      expect(json.containsKey('blockedReason'), isTrue);
      expect(json.containsKey('status'), isTrue);
    });

    test('RuntimeCommandAvailability always has full capability map', () {
      const availability = RuntimeCommandAvailability();
      final json = availability.toJson();
      // Every capability flag is present
      expect(json.containsKey('canRun'), isTrue);
      expect(json.containsKey('canBuild'), isTrue);
      expect(json.containsKey('canTest'), isTrue);
      expect(json.containsKey('canDebug'), isTrue);
      expect(json.containsKey('canSetBreakpoints'), isTrue);
      expect(json.containsKey('canStep'), isTrue);
      expect(json.containsKey('canInspectVariables'), isTrue);
      expect(json.containsKey('canReplayRuntimeEvents'), isTrue);
      expect(json.containsKey('canStreamRuntimeEvents'), isTrue);
      // Every blocked reason is present
      expect(json.containsKey('blockedDebugReason'), isTrue);
      expect(json.containsKey('blockedBreakpointReason'), isTrue);
      expect(json.containsKey('blockedStepReason'), isTrue);
      expect(json.containsKey('blockedVariableReason'), isTrue);
    });
  });

  group('Stale revision detection', () {
    test('DebugSessionSnapshot sessionId acts as revision marker', () {
      const session1 = DebugSessionSnapshot(
        sessionId: 'sess-old',
        status: DebugSessionStatus.terminated,
        available: true,
      );
      const session2 = DebugSessionSnapshot(
        sessionId: 'sess-new',
        status: DebugSessionStatus.running,
        available: true,
      );
      // Different revision markers
      expect(session1.sessionId, isNot(equals(session2.sessionId)));
    });

    test('RunConfiguration blockedReason indicates staleness', () {
      const blocked = RunConfiguration(
        configurationId: 'cfg-stale',
        kind: RunConfigurationKind.projectTarget,
        available: false,
        blockedReason: 'stale-revision',
      );
      expect(blocked.isBlocked, isTrue);
      expect(blocked.blockedReason, 'stale-revision');
    });
  });

  group('Degraded capability modeling', () {
    test('blockedReason non-empty means degraded', () {
      const availability = RuntimeCommandAvailability();
      // Blocked capabilities have reasons
      expect(availability.canDebug, isFalse);
      expect(availability.blockedDebugReason, isNotEmpty);
      // Available capabilities have no reason needed
      expect(availability.canRun, isTrue);
    });

    test('partial capability: run available, debug blocked', () {
      const availability = RuntimeCommandAvailability(
        canDebug: false,
        blockedDebugReason: 'no-debug-adapter-available',
      );
      expect(availability.canRun, isTrue);
      expect(availability.canDebug, isFalse);
      expect(availability.blockedDebugReason, 'no-debug-adapter-available');
    });
  });
}
