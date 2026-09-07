import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';
import 'package:vityo_app/src/view_render/observable/observable.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

import 'observable_fixture_support.dart';

void main() {
  final viewport = resolveViewportProfile(
    platformTarget: PlatformTarget.macos,
    width: 1200,
    height: 800,
  );

  final compactViewport = resolveViewportProfile(
    platformTarget: PlatformTarget.android,
    width: 370,
    height: 156,
  );

  Future<void> pumpState(
    WidgetTester tester,
    ObservableGraphState state, {
    ValueChanged<String>? onSelectNode,
    ValueChanged<String>? onOpenAnchor,
    ValueChanged<RuntimeObservationMode>? onRunObserved,
    String? observationUnavailableReason,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: ObservableGraphSurface(
              viewportProfile: viewport,
              state: state,
              onRefresh: () {},
              onSelectNode: onSelectNode,
              onOpenAnchor: onOpenAnchor,
              onRunObserved: onRunObserved,
              observationUnavailableReason: observationUnavailableReason,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpCompactState(
    WidgetTester tester,
    ObservableGraphState state,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 370,
            height: 156,
            child: ObservableGraphSurface(
              viewportProfile: compactViewport,
              state: state,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('every availability state shows its banner', (tester) async {
    for (final availability in ObservableAvailability.values) {
      final reason = switch (availability) {
        ObservableAvailability.unavailable => ObservableReasonCode.noToolchain,
        ObservableAvailability.unsupported =>
          ObservableReasonCode.unsupportedSchemaVersion,
        ObservableAvailability.refreshing => ObservableReasonCode.workspaceChanged,
        ObservableAvailability.fresh => null,
        ObservableAvailability.stale => ObservableReasonCode.publicationFailed,
        ObservableAvailability.blocked => ObservableReasonCode.invalidSnapshot,
        ObservableAvailability.scalarNoop => null,
      };
      await pumpState(
        tester,
        ObservableGraphState(
          availability: availability,
          reason: reason,
          detail: 'detail-${availability.wireValue}',
        ),
      );
      expect(find.byKey(const ValueKey('observable-banner')), findsOneWidget);
      expect(find.textContaining('availability: ${availability.wireValue}'), findsOneWidget);
      expect(find.textContaining('detail-${availability.wireValue}'), findsOneWidget);
      if (availability == ObservableAvailability.blocked ||
          availability == ObservableAvailability.unavailable ||
          availability == ObservableAvailability.unsupported) {
        expect(find.byKey(const ValueKey('observable-empty-canvas')), findsOneWidget);
      }
    }
    expect(find.byKey(const ValueKey('observable-legend')), findsOneWidget);
    expect(find.text('lineage link'), findsWidgets);
    for (final kind in ObservableNodeKindX.legendKinds) {
      expect(find.text('node ${kind.wireValue}'), findsWidgets);
    }
    for (final kind in ObservableEdgeKindX.legendKinds) {
      expect(find.text('edge ${kind.wireValue}'), findsWidgets);
    }
  });

  testWidgets('fresh graph shows counters, detail, and open-anchor actions', (
    tester,
  ) async {
    final snapshot = decodeAuthoredCanonicalFixture();
    final edited = decodeObservableSnapshotJson(
      readObservableFixture('edited.json'),
    ).snapshot!;
    const source = IdSetComparisonChangeSource();
    final changeSet = source.compare(snapshot, edited)!;
    final projection = projectObservableGraph(
      current: edited,
      previous: snapshot,
      changeSet: changeSet,
    );
    final layout = layoutObservableGraph(
      ObservableLayoutRequest(projection: projection),
    ).layout!;
    String? selected;
    String? opened;
    await pumpState(
      tester,
      ObservableGraphState(
        availability: ObservableAvailability.fresh,
        changeSet: changeSet,
        projection: projection,
        layout: layout,
        snapshot: edited,
        selectedNodeId: 'n1_01000000000000000000000000000002',
        selectedAnchorResolved: true,
        selectedAnchorRelativePath: 'src/main.styio',
      ),
      onSelectNode: (id) => selected = id,
      onOpenAnchor: (id) => opened = id,
    );

    expect(find.textContaining('added ${changeSet.addedCount} · removed ${changeSet.removedCount}'), findsOneWidget);
    expect(find.text('kind DriverSource'), findsOneWidget);
    expect(find.text('role DriverSource'), findsOneWidget);
    expect(find.text('anchor src/main.styio'), findsOneWidget);
    expect(find.textContaining('sema.'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('observable-open-anchor')));
    await tester.pump();
    expect(opened, 'n1_01000000000000000000000000000002');

    await tester.tap(
      find.byKey(
        const ValueKey('observable-node-n1_01000000000000000000000000000001'),
      ),
    );
    await tester.pump();
    expect(selected, 'n1_01000000000000000000000000000001');

    await pumpState(
      tester,
      ObservableGraphState(
        availability: ObservableAvailability.fresh,
        changeSet: changeSet,
        projection: projection,
        layout: layout,
        snapshot: edited,
        selectedNodeId: 'n1_01000000000000000000000000000009',
        selectedAnchorResolved: false,
      ),
      onOpenAnchor: (id) => opened = id,
    );
    expect(find.text('anchor-unresolved'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('observable-open-anchor')))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('/Users/'), findsNothing);
    expect(find.textContaining('/home/'), findsNothing);
  });

  testWidgets('every availability state fits the compact mobile panel', (
    tester,
  ) async {
    final snapshot = decodeAuthoredCanonicalFixture();
    final edited = decodeObservableSnapshotJson(
      readObservableFixture('edited.json'),
    ).snapshot!;
    const source = IdSetComparisonChangeSource();
    final changeSet = source.compare(snapshot, edited)!;
    final projection = projectObservableGraph(
      current: edited,
      previous: snapshot,
      changeSet: changeSet,
    );
    final layout = layoutObservableGraph(
      ObservableLayoutRequest(projection: projection),
    ).layout!;

    for (final availability in ObservableAvailability.values) {
      final withTopology =
          availability == ObservableAvailability.fresh ||
          availability == ObservableAvailability.refreshing ||
          availability == ObservableAvailability.stale;
      await pumpCompactState(
        tester,
        ObservableGraphState(
          availability: availability,
          reason: availability == ObservableAvailability.fresh
              ? null
              : ObservableReasonCode.publicationFailed,
          detail: 'detail-${availability.wireValue}',
          changeSet: withTopology ? changeSet : null,
          projection: withTopology ? projection : null,
          layout: withTopology ? layout : null,
          snapshot: withTopology ? edited : null,
        ),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'compact state ${availability.wireValue} must not overflow',
      );
      expect(
        find.byKey(const ValueKey('observable-banner')),
        findsOneWidget,
        reason: 'compact state ${availability.wireValue}',
      );
      expect(
        find.byKey(const ValueKey('observable-content-scroll')),
        findsOneWidget,
        reason: 'compact state ${availability.wireValue} must scroll',
      );
      expect(
        find.textContaining('availability: ${availability.wireValue}'),
        findsOneWidget,
      );
    }

    // The legend stays available in compact mode by scrolling to it.
    await tester.drag(
      find.byKey(const ValueKey('observable-content-scroll')),
      const Offset(0, -600),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('observable-legend'), skipOffstage: false),
      findsOneWidget,
    );
  });

  test('lineage link visuals are distinct from every producer edge kind', () {
    for (final kind in ObservableEdgeKindX.legendKinds) {
      expect(
        ObservableGraphPalette.lineageLink,
        isNot(ObservableGraphPalette.edgeColor(kind)),
        reason: 'lineage link colour collides with edge ${kind.wireValue}',
      );
      expect(
        ObservableGraphPalette.lineageLinkDashes,
        isNot(ObservableGraphPalette.edgeDashes(kind)),
        reason: 'lineage link dash collides with edge ${kind.wireValue}',
      );
    }
    expect(
      ObservableGraphPalette.lineageLink,
      isNot(ObservableGraphPalette.addedAccent),
    );
    expect(
      ObservableGraphPalette.lineageLink,
      isNot(ObservableGraphPalette.removedGhost),
    );
    expect(
      ObservableGraphPalette.lineageLink,
      isNot(ObservableGraphPalette.changedAccent),
    );
  });

  test('runtime wait visuals are distinct from edges and lineage links', () {
    for (final kind in ObservableEdgeKindX.legendKinds) {
      expect(
        ObservableGraphPalette.runtimeWaitDashes,
        isNot(ObservableGraphPalette.edgeDashes(kind)),
        reason: 'runtime wait dash collides with edge ${kind.wireValue}',
      );
      expect(
        ObservableGraphPalette.runtimeWaitLegend,
        isNot(ObservableGraphPalette.edgeColor(kind)),
        reason: 'runtime wait legend colour collides with edge ${kind.wireValue}',
      );
    }
    expect(
      ObservableGraphPalette.runtimeWaitDashes,
      isNot(ObservableGraphPalette.lineageLinkDashes),
    );
    expect(
      ObservableGraphPalette.runtimeWaitLegend,
      isNot(ObservableGraphPalette.lineageLink),
    );
  });

  testWidgets('producer delta states render badges, lineage, counters and detail', (
    tester,
  ) async {
    final parent = decodeNamedTopologySnapshot('parent/complete.json');
    final rename = decodeNamedTopologySnapshot('child/rename.json');
    final renameDelta = decodeNamedTopologyDelta('delta/rename.json');
    final renameSet = ObservableDeltaChangeSource(
      delta: renameDelta,
      lineage: rename.lineage,
    ).compare(parent, rename)!;
    final renameProjection = projectObservableGraph(
      current: rename,
      previous: parent,
      changeSet: renameSet,
    );
    final renameLayout = layoutObservableGraph(
      ObservableLayoutRequest(projection: renameProjection),
    ).layout!;

    await pumpState(
      tester,
      ObservableGraphState(
        availability: ObservableAvailability.fresh,
        changeSet: renameSet,
        projection: renameProjection,
        layout: renameLayout,
        snapshot: rename,
        selectedNodeId: 'n1_ccccccccccccccccccccccccccccccc1',
        lineageHistory: [
          ObservableLineageWindowEntry(
            snapshotId: observableSnapshotId(
              readObservableTopologyFixtureBytes('child/rename.json'),
            ),
            changeSource: ObservableChangeSetSource.producerDelta,
            changeSet: renameSet,
            lineageRecords: rename.lineage,
          ),
        ],
      ),
    );
    expect(find.textContaining('renamed ${renameSet.renamedCount}'), findsOneWidget);
    expect(find.byKey(const ValueKey('observable-badge-n1_ccccccccccccccccccccccccccccccc1')), findsOneWidget);
    expect(find.text('rename'), findsWidgets);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('Lineage'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.textContaining('kind rename'), findsOneWidget);
    expect(find.textContaining('/Users/'), findsNothing);

    final split = decodeNamedTopologySnapshot('child/split.json');
    final splitDelta = decodeNamedTopologyDelta('delta/split.json');
    final splitSet = ObservableDeltaChangeSource(
      delta: splitDelta,
      lineage: split.lineage,
    ).compare(parent, split)!;
    final splitProjection = projectObservableGraph(
      current: split,
      previous: parent,
      changeSet: splitSet,
    );
    await pumpState(
      tester,
      ObservableGraphState(
        availability: ObservableAvailability.fresh,
        changeSet: splitSet,
        projection: splitProjection,
        layout: layoutObservableGraph(
          ObservableLayoutRequest(projection: splitProjection),
        ).layout!,
        snapshot: split,
      ),
    );
    expect(find.text('lineage link'), findsOneWidget);
    expect(find.textContaining('split ${splitSet.splitCount}'), findsOneWidget);

    for (final reason in <ObservableReasonCode>[
      ObservableReasonCode.fullSnapshotRequired,
      ObservableReasonCode.wrongParent,
      ObservableReasonCode.staleDelta,
      ObservableReasonCode.duplicateDelta,
      ObservableReasonCode.outOfOrderDelta,
      ObservableReasonCode.unsupportedDelta,
      ObservableReasonCode.malformedDelta,
      ObservableReasonCode.invalidDelta,
    ]) {
      await pumpState(
        tester,
        ObservableGraphState(
          availability: reason == ObservableReasonCode.fullSnapshotRequired
              ? ObservableAvailability.fresh
              : ObservableAvailability.stale,
          reason: reason,
          detail: 'detail-${reason.wireValue}',
          changeSet: renameSet,
          projection: renameProjection,
          layout: renameLayout,
          snapshot: rename,
        ),
      );
      expect(find.textContaining('reason: ${reason.wireValue}'), findsOneWidget);
      expect(find.textContaining('detail-${reason.wireValue}'), findsOneWidget);
    }

    await pumpCompactState(
      tester,
      ObservableGraphState(
        availability: ObservableAvailability.fresh,
        changeSet: renameSet,
        projection: renameProjection,
        layout: renameLayout,
        snapshot: rename,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('observable-content-scroll')), findsOneWidget);
  });

  testWidgets('none phase has no runtime chrome', (tester) async {
    await pumpState(
      tester,
      const ObservableGraphState(availability: ObservableAvailability.fresh),
    );
    expect(find.byKey(const ValueKey('observable-runtime-banner')), findsNothing);
    expect(find.byKey(const ValueKey('observable-runtime-chips')), findsNothing);
    expect(find.byKey(const ValueKey('observable-run-observed')), findsNothing);
    expect(find.text('runtime wait (waiter → subject)'), findsNothing);
    expect(find.text('Run observed'), findsNothing);
  });

  testWidgets('sampled mode banner shows the producer ratio', (tester) async {
    const snapshotId = 's1_0123456789abcdef0123456789abcdef';
    await pumpState(
      tester,
      const ObservableGraphState(
        availability: ObservableAvailability.fresh,
        currentIdentity: SnapshotIdentity(
          snapshotId: snapshotId,
          compilationUnitKey: 'unit',
        ),
        runtime: RuntimeOverlayState(
          phase: RuntimeOverlayPhase.overlaid,
          requestedMode: RuntimeObservationMode.sampled,
          overlay: RuntimeOverlay(
            snapshotId: snapshotId,
            executionId: 'x2_0000000000000001',
            mode: RuntimeObservationMode.sampled,
            activitySource: RuntimeActivitySource.emittedEvents,
            presentation: RuntimeOverlayPresentation(
              kind: RuntimePresentationKind.partial,
              classes: <String>['partial/sampling', 'sampling'],
            ),
            sites: <String, RuntimeSiteFacts>{},
            blockedLinks: <RuntimeBlockedLink>[],
            uncorrelated: RuntimeUncorrelatedBuckets(),
            counters: RuntimeOverlayCounters(),
            capability: RuntimeCapabilityRecord(
              mode: RuntimeObservationMode.sampled,
              snapshotSchema: 1,
              snapshotId: snapshotId,
              executionId: 'x2_0000000000000001',
              privacyProfile: 'strict',
              producerLanes: 1,
              laneCapacity: 256,
              priorityReserved: 32,
              drainBatch: 64,
              sampling: RuntimeSamplingSpec(
                numerator: 1,
                denominator: 16,
                seed: 0,
              ),
              clockUnit: 'ns',
              supportedCapabilities: kRuntimeRequiredCapabilities,
              activeCapabilities: kRuntimeRequiredCapabilities,
              unavailableCapabilities: <String>[],
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('mode: sampled'), findsOneWidget);
    expect(find.textContaining('sampling: 1/16'), findsOneWidget);
    expect(
      find.textContaining('presentation: partial: partial/sampling, sampling'),
      findsOneWidget,
    );
  });

  testWidgets('overlaid runtime marks, chips, banner, action and detail', (
    tester,
  ) async {
    final snapshot = decodeAuthoredCanonicalFixture();
    final projection = projectObservableGraph(current: snapshot);
    final layout = layoutObservableGraph(
      ObservableLayoutRequest(projection: projection),
    ).layout!;
    final hot = projection.nodes.first.id;
    final waiting = projection.nodes[1].id;
    const snapshotId = 's1_0123456789abcdef0123456789abcdef';
    RuntimeObservationMode? ran;
    await pumpState(
      tester,
      ObservableGraphState(
        availability: ObservableAvailability.fresh,
        currentIdentity: SnapshotIdentity(
          snapshotId: snapshotId,
          compilationUnitKey: snapshot.compilationUnit.identityKey,
        ),
        projection: projection,
        layout: layout,
        snapshot: snapshot,
        selectedNodeId: waiting,
        runtime: RuntimeOverlayState(
          phase: RuntimeOverlayPhase.overlaid,
          requestedMode: RuntimeObservationMode.aggregate,
          overlay: RuntimeOverlay(
            snapshotId: snapshotId,
            executionId: 'x2_0000000000000001',
            mode: RuntimeObservationMode.aggregate,
            activitySource: RuntimeActivitySource.emittedEvents,
            presentation: const RuntimeOverlayPresentation(
              kind: RuntimePresentationKind.complete,
            ),
            sites: <String, RuntimeSiteFacts>{
              hot: RuntimeSiteFacts(
                siteId: hot,
                instancesCreated: 4,
                instancesCompleted: 1,
                instancesFailed: 1,
                lifecycleEvents: 8,
                queuePressureEvents: 1,
                maxQueueDepth: 8,
                queueCapacity: 8,
              ),
              waiting: RuntimeSiteFacts(
                siteId: waiting,
                lifecycleEvents: 1,
                waits: const <RuntimeWaitReason, RuntimeWaitFacts>{
                  RuntimeWaitReason.task: RuntimeWaitFacts(
                    open: 1,
                    closed: 1,
                    totalDurationNs: 60,
                  ),
                },
                recentEvents: const <RuntimeSiteEvent>[
                  RuntimeSiteEvent(
                    kind: RuntimeEventKind.waitBegin,
                    rawKind: 'wait.begin',
                    instanceId: 'i2_0000000000000002',
                    eventId: 'r2_0000000000000003',
                    monotonicNs: 120,
                    causes: <RuntimeCausalEdge>[
                      RuntimeCausalEdge(
                        kind: RuntimeCausalKind.wake,
                        rawKind: 'wake',
                        eventId: 'r2_0000000000000002',
                        subjectInstance: 'i2_0000000000000001',
                      ),
                    ],
                  ),
                ],
              ),
            },
            blockedLinks: <RuntimeBlockedLink>[
              RuntimeBlockedLink(
                fromSite: waiting,
                toSite: hot,
                reason: RuntimeWaitReason.task,
                open: 1,
                closed: 1,
                totalDurationNs: 60,
              ),
            ],
            uncorrelated: const RuntimeUncorrelatedBuckets(
              runtimeOnly: 2,
              unknownSite: 1,
              staleSnapshot: 1,
              runtimeOnlyWaits: <RuntimeWaitReason, int>{
                RuntimeWaitReason.runnable: 1,
              },
            ),
            counters: const RuntimeOverlayCounters(),
            capability: const RuntimeCapabilityRecord(
              mode: RuntimeObservationMode.aggregate,
              snapshotSchema: 1,
              snapshotId: snapshotId,
              executionId: 'x2_0000000000000001',
              privacyProfile: 'strict',
              producerLanes: 1,
              laneCapacity: 256,
              priorityReserved: 32,
              drainBatch: 64,
              sampling: RuntimeSamplingSpec(
                numerator: 1,
                denominator: 16,
                seed: 0,
              ),
              clockUnit: 'ns',
              supportedCapabilities: kRuntimeRequiredCapabilities,
              activeCapabilities: kRuntimeRequiredCapabilities,
              unavailableCapabilities: <String>[],
            ),
            summary: const RuntimeSummaryRecord(
              mode: RuntimeObservationMode.aggregate,
              executionId: 'x2_0000000000000001',
              completeness: RuntimeCompleteness.complete,
              rawCompleteness: 'complete',
              exporterFailed: false,
              laneCapacity: 256,
              priorityReserved: 32,
              producerLanes: 1,
              highWaterOccupancy: 4,
              families: <String, RuntimeFamilyAccounting>{
                'task_lifecycle': RuntimeFamilyAccounting(
                  observed: 8,
                  emitted: 8,
                  aggregated: 0,
                  sampledOut: 0,
                  bufferDropped: 0,
                  exporterDropped: 0,
                  summaryUpdates: 8,
                ),
              },
            ),
            maxActivity: 8,
          ),
        ),
      ),
      onRunObserved: (mode) => ran = mode,
    );

    expect(find.byKey(const ValueKey('observable-runtime-banner')), findsOneWidget);
    expect(find.textContaining('phase: overlaid'), findsOneWidget);
    expect(find.textContaining('mode: aggregate'), findsOneWidget);
    // The capability record always carries a sampling spec, but the ratio is
    // shown only when the producer actually ran in sampled mode.
    expect(find.textContaining('sampling:'), findsNothing);
    expect(find.textContaining('completeness: complete'), findsOneWidget);
    expect(find.textContaining('presentation: complete'), findsOneWidget);
    expect(find.text('runtime-only 2'), findsOneWidget);
    expect(find.text('unknown site 1'), findsOneWidget);
    expect(find.text('stale snapshot 1'), findsOneWidget);
    expect(find.text('runtime wait (waiter → subject)'), findsOneWidget);
    expect(find.byKey(ValueKey('observable-runtime-halo-$hot')), findsOneWidget);
    expect(find.byKey(ValueKey('observable-runtime-failure-$hot')), findsOneWidget);
    expect(find.byKey(ValueKey('observable-runtime-queue-$hot')), findsOneWidget);
    expect(
      find.byKey(ValueKey('observable-runtime-wait-$waiting-task')),
      findsOneWidget,
    );
    expect(find.text('Runtime'), findsOneWidget);
    expect(find.textContaining('activity 1 emitted events'), findsOneWidget);
    expect(find.byKey(const ValueKey('observable-run-observed')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('observable-run-observed')));
    await tester.pump();
    expect(ran, RuntimeObservationMode.aggregate);
    expect(find.textContaining('/Users/'), findsNothing);
    expect(find.textContaining('/home/'), findsNothing);
    expect(find.textContaining('/tmp/'), findsNothing);

    await pumpState(
      tester,
      ObservableGraphState(
        availability: ObservableAvailability.fresh,
        currentIdentity: SnapshotIdentity(
          snapshotId: 's1_ffffffffffffffffffffffffffffffff',
          compilationUnitKey: snapshot.compilationUnit.identityKey,
        ),
        projection: projection,
        layout: layout,
        snapshot: snapshot,
        runtime: RuntimeOverlayState(
          phase: RuntimeOverlayPhase.staleSnapshot,
          reason: ObservableReasonCode.headAdvanced,
          detail: 'head-advanced',
          overlay: RuntimeOverlay(
            snapshotId: snapshotId,
            executionId: 'x2_0000000000000001',
            mode: RuntimeObservationMode.aggregate,
            activitySource: RuntimeActivitySource.emittedEvents,
            presentation: const RuntimeOverlayPresentation(
              kind: RuntimePresentationKind.complete,
            ),
            sites: <String, RuntimeSiteFacts>{
              hot: RuntimeSiteFacts(siteId: hot, instancesCreated: 4),
            },
            blockedLinks: const <RuntimeBlockedLink>[],
            uncorrelated: const RuntimeUncorrelatedBuckets(runtimeOnly: 1),
            counters: const RuntimeOverlayCounters(),
            maxActivity: 4,
          ),
        ),
      ),
    );
    expect(find.textContaining('phase: stale-snapshot'), findsOneWidget);
    expect(find.byKey(ValueKey('observable-runtime-halo-$hot')), findsNothing);
    expect(find.text('runtime-only 1'), findsOneWidget);

    await pumpState(
      tester,
      ObservableGraphState(
        availability: ObservableAvailability.fresh,
        projection: projection,
        layout: layout,
        snapshot: snapshot,
      ),
      onRunObserved: (_) {},
      observationUnavailableReason: 'missing-runtime-capability',
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('observable-run-observed')),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('reason: missing-runtime-capability'), findsOneWidget);

    await pumpCompactState(
      tester,
      ObservableGraphState(
        availability: ObservableAvailability.fresh,
        currentIdentity: SnapshotIdentity(
          snapshotId: snapshotId,
          compilationUnitKey: snapshot.compilationUnit.identityKey,
        ),
        projection: projection,
        layout: layout,
        snapshot: snapshot,
        runtime: const RuntimeOverlayState(
          phase: RuntimeOverlayPhase.overlaid,
          overlay: null,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('observable-content-scroll')), findsOneWidget);
  });
}
