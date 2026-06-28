import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/workbench/ide_capability.dart';
import 'package:vityo_app/src/view_ide/workbench/ide_capability_registry.dart';
import 'package:vityo_app/src/view_ide/workbench/ide_capability_gap.dart';
import 'package:vityo_app/src/view_ide/commands/app_commands.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';

void main() {
  group('IdeCapabilityDescriptor', () {
    test('available capability reports correct status', () {
      const cap = IdeCapabilityDescriptor(
        capabilityId: 'language.diagnostics',
        domain: IdeCapabilityDomain.languageIntelligence,
        label: 'Diagnostics',
        description: 'Compiler-driven diagnostics',
        maturity: IdeCapabilityMaturity.l3ProductWorkflow,
        availability: IdeCapabilityAvailability.available,
      );
      expect(cap.isAvailable, isTrue);
      expect(cap.isUsable, isTrue);
      expect(cap.isBlocked, isFalse);
    });

    test('blocked capability reports correct status', () {
      const cap = IdeCapabilityDescriptor(
        capabilityId: 'language.rename',
        domain: IdeCapabilityDomain.languageIntelligence,
        label: 'Rename',
        description: 'Safe symbol rename',
        availability: IdeCapabilityAvailability.blockedByUpstreamContract,
        upstreamContract: 'LanguageServiceAdapter.renamePlan',
      );
      expect(cap.isAvailable, isFalse);
      expect(cap.isBlocked, isTrue);
      expect(cap.isUsable, isFalse);
    });

    test('preview-only capability is usable but not available', () {
      const cap = IdeCapabilityDescriptor(
        capabilityId: 'debug.breakpoints',
        domain: IdeCapabilityDomain.runDebugRuntime,
        label: 'Breakpoints',
        description: 'Breakpoint support',
        availability: IdeCapabilityAvailability.previewOnly,
      );
      expect(cap.isAvailable, isFalse);
      expect(cap.isUsable, isTrue);
      expect(cap.isBlocked, isFalse);
    });

    test('serializes to JSON', () {
      const cap = IdeCapabilityDescriptor(
        capabilityId: 'workbench.commandPalette',
        domain: IdeCapabilityDomain.workbench,
        label: 'Command Palette',
        description: 'Searchable command palette',
        maturity: IdeCapabilityMaturity.l3ProductWorkflow,
        availability: IdeCapabilityAvailability.available,
        relatedCommandIds: [AppCommandId.commandPalette],
      );
      final json = cap.toJson();
      expect(json['capabilityId'], 'workbench.commandPalette');
      expect(json['domain'], 'workbench');
      expect(json['isAvailable'], true);
    });
  });

  group('IdeCapabilityRegistry', () {
    test('registers and looks up capabilities', () {
      final registry = IdeCapabilityRegistry(descriptors: [
        const IdeCapabilityDescriptor(
          capabilityId: 'a',
          domain: IdeCapabilityDomain.workbench,
          label: 'A',
          description: 'Cap A',
          availability: IdeCapabilityAvailability.available,
        ),
        const IdeCapabilityDescriptor(
          capabilityId: 'b',
          domain: IdeCapabilityDomain.languageIntelligence,
          label: 'B',
          description: 'Cap B',
          availability: IdeCapabilityAvailability.blockedByUpstreamContract,
        ),
      ]);

      expect(registry.all.length, 2);
      expect(registry.contains('a'), isTrue);
      expect(registry.contains('c'), isFalse);
      expect(registry.lookup('a')?.isAvailable, isTrue);
      expect(registry.lookup('b')?.isBlocked, isTrue);
    });

    test('filters available, usable, blocked', () {
      final registry = IdeCapabilityRegistry(descriptors: [
        const IdeCapabilityDescriptor(
          capabilityId: 'available',
          domain: IdeCapabilityDomain.workbench,
          label: 'Avail',
          description: '...',
          availability: IdeCapabilityAvailability.available,
        ),
        const IdeCapabilityDescriptor(
          capabilityId: 'preview',
          domain: IdeCapabilityDomain.workbench,
          label: 'Preview',
          description: '...',
          availability: IdeCapabilityAvailability.previewOnly,
        ),
        const IdeCapabilityDescriptor(
          capabilityId: 'blocked',
          domain: IdeCapabilityDomain.workbench,
          label: 'Blocked',
          description: '...',
          availability: IdeCapabilityAvailability.blockedByUpstreamContract,
        ),
        const IdeCapabilityDescriptor(
          capabilityId: 'planned',
          domain: IdeCapabilityDomain.workbench,
          label: 'Planned',
          description: '...',
          availability: IdeCapabilityAvailability.planned,
        ),
      ]);

      expect(registry.available.length, 1);
      expect(registry.usable.length, 2);
      expect(registry.blocked.length, 1);
      expect(registry.upstreamBlocked.length, 1);
    });

    test('toSnapshot aggregates correctly', () {
      final registry = IdeCapabilityRegistry(descriptors: [
        const IdeCapabilityDescriptor(
          capabilityId: 'a',
          domain: IdeCapabilityDomain.workbench,
          label: 'A',
          description: '...',
          availability: IdeCapabilityAvailability.available,
        ),
        const IdeCapabilityDescriptor(
          capabilityId: 'b',
          domain: IdeCapabilityDomain.languageIntelligence,
          label: 'B',
          description: '...',
          availability: IdeCapabilityAvailability.blockedByUpstreamContract,
        ),
      ]);

      final snapshot = registry.toSnapshot();
      expect(snapshot.totalCount, 2);
      expect(snapshot.availableCount, 1);
      expect(snapshot.blockedCount, 1);
      expect(snapshot.readinessRatio, 0.5);
    });
  });

  group('PlatformCapabilityFilter', () {
    test('iOS hides local execution and local git', () {
      const filter = PlatformCapabilityFilter();
      final hidden = filter.hiddenCapabilitiesFor(PlatformTarget.ios);
      expect(hidden, contains('execution.local'));
      expect(hidden, contains('sourceControl.localGit'));
    });

    test('Web hides local execution and local git', () {
      const filter = PlatformCapabilityFilter();
      final hidden = filter.hiddenCapabilitiesFor(PlatformTarget.web);
      expect(hidden, contains('execution.local'));
      expect(hidden, contains('sourceControl.localGit'));
    });

    test('Desktop does not hide local capabilities', () {
      const filter = PlatformCapabilityFilter();
      final hidden = filter.hiddenCapabilitiesFor(PlatformTarget.linux);
      expect(hidden, isEmpty);
    });

    test('Android hides local git only', () {
      const filter = PlatformCapabilityFilter();
      final hidden = filter.hiddenCapabilitiesFor(PlatformTarget.android);
      expect(hidden, contains('sourceControl.localGit'));
      expect(hidden, isNot(contains('execution.local')));
    });

    test('filters descriptors for platform', () {
      const filter = PlatformCapabilityFilter();
      final descriptors = [
        const IdeCapabilityDescriptor(
          capabilityId: 'execution.local',
          domain: IdeCapabilityDomain.runDebugRuntime,
          label: 'Local Run',
          description: '...',
          availability: IdeCapabilityAvailability.available,
        ),
        const IdeCapabilityDescriptor(
          capabilityId: 'execution.cloud',
          domain: IdeCapabilityDomain.runDebugRuntime,
          label: 'Cloud Run',
          description: '...',
          availability: IdeCapabilityAvailability.available,
        ),
        const IdeCapabilityDescriptor(
          capabilityId: 'sourceControl.localGit',
          domain: IdeCapabilityDomain.sourceControl,
          label: 'Local Git',
          description: '...',
          availability: IdeCapabilityAvailability.available,
        ),
      ];

      final iosFiltered = filter.filterForPlatform(descriptors, PlatformTarget.ios);
      expect(iosFiltered.length, 1);
      expect(iosFiltered.first.capabilityId, 'execution.cloud');

      final linuxFiltered = filter.filterForPlatform(descriptors, PlatformTarget.linux);
      expect(linuxFiltered.length, 3);
    });
  });

  group('IdeCapabilityGap', () {
    test('displayMessage is descriptive', () {
      final gap = const IdeCapabilityGap(
        capabilityId: 'language.rename',
        reason: IdeCapabilityAvailability.blockedByUpstreamContract,
        upstreamContract: 'LanguageServiceAdapter.renamePlan',
        detail: 'StyioService must expose rename safety analysis.',
        affectedCommandIds: ['renameWorkspaceSymbol'],
        affectedSurfaces: ['editor', 'workspaceSidebar'],
      );

      expect(gap.displayMessage, contains('blocked by upstream'));
      expect(gap.displayMessage, contains('LanguageServiceAdapter'));
    });

    test('platform blocked displays platform reason', () {
      const gap = IdeCapabilityGap(
        capabilityId: 'execution.local',
        reason: IdeCapabilityAvailability.blockedByPlatform,
        detail: 'iOS does not support local compilation.',
      );
      expect(gap.displayMessage, contains('not supported on this platform'));
    });
  });

  group('IdeCapabilityGapReport', () {
    test('empty report has no gaps', () {
      const report = IdeCapabilityGapReport();
      expect(report.hasGaps, isFalse);
      expect(report.hasBlockers, isFalse);
      expect(report.summary, contains('available'));
    });

    test('separates upstream vs platform blocked', () {
      final report = const IdeCapabilityGapReport(
        platformTarget: 'ios',
        gaps: [
          IdeCapabilityGap(
            capabilityId: 'language.rename',
            reason: IdeCapabilityAvailability.blockedByUpstreamContract,
          ),
          IdeCapabilityGap(
            capabilityId: 'execution.local',
            reason: IdeCapabilityAvailability.blockedByPlatform,
          ),
        ],
      );

      expect(report.hasBlockers, isTrue);
      expect(report.upstreamBlocked.length, 1);
      expect(report.platformBlocked.length, 1);
    });
  });
}
