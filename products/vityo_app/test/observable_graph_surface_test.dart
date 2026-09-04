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
}
