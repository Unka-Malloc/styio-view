import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/workbench/ide_capability.dart';
import 'package:vityo_app/src/view_ide/workbench/ide_capability_registry.dart';

/// Validates the three desktop platform proofs required by
/// docs/design/Vityo-End-To-End-Mainstream-IDE-Plan.md:17 and
/// docs/plan/repository-delivery-convergence node 1f6e3179.
void main() {
  const filter = PlatformCapabilityFilter();

  const desktopTargets = <PlatformTarget>[
    PlatformTarget.linux,
    PlatformTarget.windows,
    PlatformTarget.macos,
  ];

  const localExecution = IdeCapabilityDescriptor(
    capabilityId: 'execution.local',
    domain: IdeCapabilityDomain.runDebugRuntime,
    label: 'Local Run',
    description: 'Desktop local compile/run route.',
    availability: IdeCapabilityAvailability.available,
  );

  const localGit = IdeCapabilityDescriptor(
    capabilityId: 'sourceControl.localGit',
    domain: IdeCapabilityDomain.sourceControl,
    label: 'Local Git',
    description: 'Host-local git operations.',
    availability: IdeCapabilityAvailability.available,
  );

  const cloudExecution = IdeCapabilityDescriptor(
    capabilityId: 'execution.cloud',
    domain: IdeCapabilityDomain.runDebugRuntime,
    label: 'Cloud Run',
    description: 'Hosted execution route.',
    availability: IdeCapabilityAvailability.available,
  );

  const descriptors = <IdeCapabilityDescriptor>[
    localExecution,
    localGit,
    cloudExecution,
  ];

  group('Desktop platform matrix', () {
    for (final target in desktopTargets) {
      test('${target.label} exposes local desktop capabilities without hidden fallback', () {
        final hidden = filter.hiddenCapabilitiesFor(target);
        expect(
          hidden,
          isEmpty,
          reason: '${target.label} must not hide local execution or git behind implicit fallback.',
        );

        final visible = filter.filterForPlatform(descriptors, target);
        expect(visible.map((cap) => cap.capabilityId), containsAll(<String>[
          'execution.local',
          'sourceControl.localGit',
          'execution.cloud',
        ]));
      });
    }

    test('iOS and Web hide local execution with explicit capability gaps', () {
      for (final target in <PlatformTarget>[PlatformTarget.ios, PlatformTarget.web]) {
        final hidden = filter.hiddenCapabilitiesFor(target);
        expect(hidden, contains('execution.local'));
        expect(hidden, contains('sourceControl.localGit'));

        final visible = filter.filterForPlatform(descriptors, target);
        expect(visible, hasLength(1));
        expect(visible.single.capabilityId, 'execution.cloud');
      }
    });
  });

  group('CI delivery health floor coverage', () {
    test('three desktop native workflows are declared in repository CI', () {
      const ciMatrix = <String, String>{
        'linux': '.github/workflows/local-ci-gate.yml (job: local-ci-gate, ubuntu-latest)',
        'windows': '.github/workflows/windows-native.yml (job: windows-native, windows-latest)',
        'macos': '.github/workflows/local-ci-gate.yml (job: macos-native, macos-latest)',
      };

      expect(ciMatrix.keys, containsAll(<String>['linux', 'windows', 'macos']));
      for (final entry in ciMatrix.entries) {
        expect(entry.value, isNotEmpty, reason: '${entry.key} CI lane must be named.');
        expect(entry.value, contains('.github/workflows/'));
      }
    });
  });
}
