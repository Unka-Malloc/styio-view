import 'package:flutter/material.dart';

import '../../view_ide/services/observable_topology/observable_topology.dart';
import '../platform/platform.dart';
import 'observable_graph_palette.dart';

class ObservableGraphSurface extends StatefulWidget {
  const ObservableGraphSurface({
    super.key,
    required this.viewportProfile,
    required this.state,
    this.onRefresh,
    this.onSelectNode,
    this.onOpenAnchor,
    this.onRunObserved,
    this.observationUnavailableReason,
  });

  final ViewportProfile viewportProfile;
  final ObservableGraphState state;
  final VoidCallback? onRefresh;
  final ValueChanged<String>? onSelectNode;
  final ValueChanged<String>? onOpenAnchor;
  final ValueChanged<RuntimeObservationMode>? onRunObserved;
  final String? observationUnavailableReason;

  @override
  State<ObservableGraphSurface> createState() => _ObservableGraphSurfaceState();
}

class _ObservableGraphSurfaceState extends State<ObservableGraphSurface> {
  RuntimeObservationMode _mode = RuntimeObservationMode.aggregate;

  @override
  Widget build(BuildContext context) {
    final compact = widget.viewportProfile.isMobile;
    final state = widget.state;
    final showTopology =
        state.availability.showsTopology &&
        state.projection != null &&
        state.availability != ObservableAvailability.scalarNoop &&
        state.availability != ObservableAvailability.blocked;
    final chrome = _ObservableRuntimeChrome(
      state: state,
      mode: _mode,
      onModeChanged: (mode) => setState(() => _mode = mode),
      onRunObserved: widget.onRunObserved,
      observationUnavailableReason: widget.observationUnavailableReason,
    );

    if (compact) {
      return KeyedSubtree(
        key: const ValueKey('observable-graph-surface'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ListView(
            key: const ValueKey('observable-content-scroll'),
            children: [
              _ObservableBanner(
                state: state,
                onRefresh: widget.onRefresh,
                chrome: chrome,
              ),
              if (state.runtime.showsRuntimeChrome) ...[
                const SizedBox(height: 8),
                chrome.bannerRow(),
                chrome.chips(),
              ],
              const SizedBox(height: 8),
              _ObservableCounters(changeSet: state.changeSet),
              const SizedBox(height: 8),
              SizedBox(height: 180, child: _canvas(showTopology)),
              const SizedBox(height: 8),
              SizedBox(height: 168, child: _detail()),
              const SizedBox(height: 8),
              _ObservableLegend(showRuntimeWait: state.runtime.showsRuntimeChrome),
            ],
          ),
        ),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('observable-graph-surface'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ObservableBanner(
              state: state,
              onRefresh: widget.onRefresh,
              chrome: chrome,
            ),
            if (state.runtime.showsRuntimeChrome) ...[
              const SizedBox(height: 8),
              chrome.bannerRow(),
              chrome.chips(),
            ],
            const SizedBox(height: 8),
            _ObservableLegend(showRuntimeWait: state.runtime.showsRuntimeChrome),
            const SizedBox(height: 8),
            _ObservableCounters(changeSet: state.changeSet),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _canvas(showTopology)),
                  SizedBox(width: 280, child: _detail()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _canvas(bool showTopology) {
    if (!showTopology) {
      return const KeyedSubtree(
        key: ValueKey('observable-empty-canvas'),
        child: SizedBox.expand(),
      );
    }
    return _ObservableCanvas(
      state: widget.state,
      onSelectNode: widget.onSelectNode,
    );
  }

  Widget _detail() {
    return _ObservableDetailPanel(
      state: widget.state,
      onOpenAnchor: widget.onOpenAnchor,
    );
  }
}

class _ObservableRuntimeChrome {
  const _ObservableRuntimeChrome({
    required this.state,
    required this.mode,
    required this.onModeChanged,
    this.onRunObserved,
    this.observationUnavailableReason,
  });

  final ObservableGraphState state;
  final RuntimeObservationMode mode;
  final ValueChanged<RuntimeObservationMode> onModeChanged;
  final ValueChanged<RuntimeObservationMode>? onRunObserved;
  final String? observationUnavailableReason;

  bool get _busy {
    final phase = state.runtime.phase;
    return phase == RuntimeOverlayPhase.observing ||
        phase == RuntimeOverlayPhase.ingesting;
  }

  Widget actions() {
    if (onRunObserved == null) {
      return const SizedBox.shrink();
    }
    final disabledReason = observationUnavailableReason;
    final enabled = disabledReason == null && !_busy;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<RuntimeObservationMode>(
          key: const ValueKey('observable-observation-mode'),
          value: mode,
          onChanged: enabled
              ? (value) {
                  if (value != null) {
                    onModeChanged(value);
                  }
                }
              : null,
          items: const [
            DropdownMenuItem(
              value: RuntimeObservationMode.aggregate,
              child: Text('aggregate'),
            ),
            DropdownMenuItem(
              value: RuntimeObservationMode.sampled,
              child: Text('sampled'),
            ),
            DropdownMenuItem(
              value: RuntimeObservationMode.detailed,
              child: Text('detailed'),
            ),
          ],
        ),
        TextButton(
          key: const ValueKey('observable-run-observed'),
          onPressed: enabled ? () => onRunObserved!(mode) : null,
          child: const Text('Run observed'),
        ),
        if (disabledReason != null) Text('reason: $disabledReason'),
      ],
    );
  }

  Widget bannerRow() {
    final runtime = state.runtime;
    final overlay = runtime.overlay;
    final capability = overlay?.capability;
    final summary = overlay?.summary;
    // The capability record always carries a sampling spec; the ratio is only
    // meaningful (and only shown) when the producer ran in sampled mode.
    final sampling = capability?.mode == RuntimeObservationMode.sampled
        ? capability?.sampling
        : null;
    final sampled = _lossTotal(summary, (row) => row.sampledOut);
    final buffered = _lossTotal(summary, (row) => row.bufferDropped);
    final exported = _lossTotal(summary, (row) => row.exporterDropped);
    final aggregated = _lossTotal(summary, (row) => row.aggregated);
    final occupancy = summary == null
        ? null
        : '${summary.highWaterOccupancy}/${summary.laneCapacity}';
    final counters = overlay?.counters;
    return KeyedSubtree(
      key: const ValueKey('observable-runtime-banner'),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          Text('phase: ${runtime.phase.wireValue}'),
          Text(
            'mode: ${capability?.mode.wireValue ?? runtime.requestedMode?.wireValue ?? 'aggregate'}',
          ),
          if (sampling != null)
            Text('sampling: ${sampling.numerator}/${sampling.denominator}'),
          Text(
            'completeness: ${summary?.rawCompleteness ?? 'none'}',
          ),
          Text(
            'presentation: ${overlay?.presentation.label ?? 'none'}',
          ),
          Text(
            'loss: sampled $sampled buffer $buffered exporter $exported aggregated $aggregated',
          ),
          Text('exporter_failed: ${summary?.exporterFailed ?? false}'),
          if (occupancy != null) Text('occupancy: $occupancy'),
          Text(
            'rejected ${counters?.rejectedRecords ?? 0} unknown ${counters?.unknownKinds ?? 0} evicted ${counters?.totalEvictions ?? 0}',
          ),
        ],
      ),
    );
  }

  Widget chips() {
    final overlay = state.runtime.overlay;
    if (overlay == null) {
      return const SizedBox.shrink();
    }
    final buckets = overlay.uncorrelated;
    return KeyedSubtree(
      key: const ValueKey('observable-runtime-chips'),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          Text('runtime-only ${buckets.runtimeOnly}'),
          Text('unknown site ${buckets.unknownSite}'),
          Text('stale snapshot ${buckets.staleSnapshot}'),
          for (final entry in buckets.runtimeOnlyWaits.entries)
            Text('wait ${entry.key.wireValue} ${entry.value}'),
        ],
      ),
    );
  }

  int _lossTotal(
    RuntimeSummaryRecord? summary,
    int Function(RuntimeFamilyAccounting row) pick,
  ) {
    if (summary == null) {
      return 0;
    }
    var total = 0;
    for (final row in summary.families.values) {
      total += pick(row);
    }
    return total;
  }
}

class _ObservableBanner extends StatelessWidget {
  const _ObservableBanner({
    required this.state,
    this.onRefresh,
    required this.chrome,
  });

  final ObservableGraphState state;
  final VoidCallback? onRefresh;
  final _ObservableRuntimeChrome chrome;

  @override
  Widget build(BuildContext context) {
    final reason = state.reason;
    return KeyedSubtree(
      key: const ValueKey('observable-banner'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        'availability: ${state.availability.wireValue}',
                        if (reason != null && reason.isRendered)
                          'reason: ${reason.wireValue}',
                        if (state.detail != null && state.detail!.isNotEmpty)
                          'detail: ${state.detail}',
                      ].join(' · '),
                    ),
                  ),
                  if (onRefresh != null)
                    TextButton(
                      key: const ValueKey('observable-refresh'),
                      onPressed: onRefresh,
                      child: const Text('Refresh'),
                    ),
                ],
              ),
              chrome.actions(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ObservableLegend extends StatelessWidget {
  const _ObservableLegend({this.showRuntimeWait = false});

  final bool showRuntimeWait;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('observable-legend'),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final kind in ObservableNodeKindX.legendKinds)
            _LegendEntry(
              swatch: DecoratedBox(
                decoration: BoxDecoration(
                  color: ObservableGraphPalette.nodeFill(kind),
                  borderRadius: const BorderRadius.all(Radius.circular(3)),
                ),
              ),
              label: 'node ${kind.wireValue}',
            ),
          for (final kind in ObservableEdgeKindX.legendKinds)
            _LegendEntry(
              swatch: CustomPaint(
                painter: _LegendEdgePainter(kind),
                size: const Size(18, 10),
              ),
              label: 'edge ${kind.wireValue}',
            ),
          const _LegendEntry(
            swatch: CustomPaint(
              painter: _LegendLineagePainter(),
              size: Size(18, 10),
            ),
            label: 'lineage link',
          ),
          if (showRuntimeWait)
            const _LegendEntry(
              swatch: CustomPaint(
                painter: _LegendRuntimeWaitPainter(),
                size: Size(18, 10),
              ),
              label: 'runtime wait (waiter → subject)',
            ),
        ],
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.swatch, required this.label});

  final Widget swatch;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 18, height: 10, child: Center(child: swatch)),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}

class _LegendEdgePainter extends CustomPainter {
  const _LegendEdgePainter(this.kind);

  final ObservableEdgeKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = ObservableGraphPalette.edgeColor(kind);
    final y = size.height / 2;
    final path = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y);
    final dashes = ObservableGraphPalette.edgeDashes(kind);
    if (dashes.isEmpty) {
      canvas.drawPath(path, paint);
    } else {
      canvas.drawPath(_dashPath(path, dashes), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LegendEdgePainter oldDelegate) {
    return oldDelegate.kind != kind;
  }
}

class _LegendLineagePainter extends CustomPainter {
  const _LegendLineagePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = ObservableGraphPalette.lineageLink;
    final y = size.height / 2;
    canvas.drawPath(
      _dashPath(
        Path()
          ..moveTo(0, y)
          ..lineTo(size.width, y),
        ObservableGraphPalette.lineageLinkDashes,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LegendLineagePainter oldDelegate) => false;
}

class _LegendRuntimeWaitPainter extends CustomPainter {
  const _LegendRuntimeWaitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = ObservableGraphPalette.runtimeWaitLegend;
    final y = size.height / 2;
    canvas.drawPath(
      _dashPath(
        Path()
          ..moveTo(0, y)
          ..lineTo(size.width, y),
        ObservableGraphPalette.runtimeWaitDashes,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LegendRuntimeWaitPainter oldDelegate) => false;
}

class _ObservableCounters extends StatelessWidget {
  const _ObservableCounters({required this.changeSet});

  final ObservableChangeSet? changeSet;

  @override
  Widget build(BuildContext context) {
    final added = changeSet?.addedCount ?? 0;
    final removed = changeSet?.removedCount ?? 0;
    final changed = changeSet?.changedCount ?? 0;
    final renamed = changeSet?.renamedCount ?? 0;
    final moved = changeSet?.movedCount ?? 0;
    final split = changeSet?.splitCount ?? 0;
    final merged = changeSet?.mergedCount ?? 0;
    return KeyedSubtree(
      key: const ValueKey('observable-counters'),
      child: Text(
        'added $added · removed $removed · changed $changed · renamed $renamed · moved $moved · split $split · merged $merged',
      ),
    );
  }
}

class _ObservableCanvas extends StatelessWidget {
  const _ObservableCanvas({required this.state, this.onSelectNode});

  final ObservableGraphState state;
  final ValueChanged<String>? onSelectNode;

  @override
  Widget build(BuildContext context) {
    final layout = state.layout;
    final projection = state.projection;
    if (layout == null || projection == null) {
      return const SizedBox.expand();
    }
    return ClipRect(
      child: InteractiveViewer(
        constrained: false,
        boundaryMargin: const EdgeInsets.all(48),
        minScale: 0.2,
        maxScale: 2.5,
        child: SizedBox(
          width: layout.width,
          height: layout.height,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(layout.width, layout.height),
                painter: _ObservableGraphPainter(
                  projection: projection,
                  layout: layout,
                  overlay: state.runtime.marksCurrentHead(
                    state.currentIdentity?.snapshotId,
                  )
                      ? state.runtime.overlay
                      : null,
                ),
              ),
              for (final node in projection.nodes)
                if (layout.nodeRects[node.id] != null)
                  _nodeHitTarget(layout.nodeRects[node.id]!, node),
              for (final node in projection.nodes)
                if (layout.nodeRects[node.id] != null &&
                    node.continuity != null &&
                    (node.continuity!.kind == ObservableLineageKind.rename ||
                        node.continuity!.kind == ObservableLineageKind.move) &&
                    node.changeTag != GraphItemChangeTag.removed)
                  _continuityBadge(layout.nodeRects[node.id]!, node),
              if (state.runtime.marksCurrentHead(
                state.currentIdentity?.snapshotId,
              ))
                ..._runtimeMarks(layout, projection, state.runtime.overlay!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _continuityBadge(LayoutRect rect, ProjectedGraphNode node) {
    return Positioned(
      left: rect.x,
      top: rect.y - 14,
      width: rect.width,
      height: 14,
      child: Text(
        node.continuity!.kind.wireValue,
        key: ValueKey('observable-badge-${node.id}'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          color: ObservableGraphPalette.continuityBadge,
        ),
      ),
    );
  }

  Widget _nodeHitTarget(LayoutRect rect, ProjectedGraphNode node) {
    return Positioned(
      left: rect.x,
      top: rect.y,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        key: ValueKey('observable-node-${node.id}'),
        onTap: onSelectNode == null ? null : () => onSelectNode!(node.id),
        child: const ColoredBox(color: Color(0x00000000)),
      ),
    );
  }

  List<Widget> _runtimeMarks(
    ObservableLayoutResult layout,
    GraphProjection projection,
    RuntimeOverlay overlay,
  ) {
    final marks = <Widget>[];
    for (final node in projection.nodes) {
      final rect = layout.nodeRects[node.id];
      final facts = overlay.sites[node.id];
      if (rect == null || facts == null) {
        continue;
      }
      final activity = facts.activity(overlay.activitySource);
      if (activity > 0) {
        marks.add(
          Positioned(
            left: rect.x,
            top: rect.y + 2,
            width: rect.width,
            child: Text(
              '$activity',
              key: ValueKey('observable-runtime-activity-${node.id}'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
            ),
          ),
        );
      }
      if (facts.instancesActive > 0) {
        marks.add(
          Positioned(
            left: rect.x - 4,
            top: rect.y - 4,
            width: rect.width + 8,
            height: rect.height + 8,
            child: IgnorePointer(
              child: DecoratedBox(
                key: ValueKey('observable-runtime-halo-${node.id}'),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: ObservableGraphPalette.runtimeHalo,
                    width: 2,
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Text('${facts.instancesActive}'),
                ),
              ),
            ),
          ),
        );
      }
      var badgeTop = rect.y + rect.height + 2;
      if (facts.instancesFailed > 0) {
        marks.add(
          Positioned(
            left: rect.x,
            top: badgeTop,
            child: Text(
              'fail ${facts.instancesFailed}',
              key: ValueKey('observable-runtime-failure-${node.id}'),
              style: const TextStyle(
                fontSize: 10,
                color: ObservableGraphPalette.runtimeFailure,
              ),
            ),
          ),
        );
        badgeTop += 12;
      }
      for (final entry in facts.waits.entries) {
        marks.add(
          Positioned(
            left: rect.x,
            top: badgeTop,
            child: Text(
              '${entry.key.wireValue} ${entry.value.open}/${entry.value.closed} ${entry.value.totalDurationNs}',
              key: ValueKey(
                'observable-runtime-wait-${node.id}-${entry.key.wireValue}',
              ),
              style: TextStyle(
                fontSize: 10,
                color: ObservableGraphPalette.waitReason(entry.key),
              ),
            ),
          ),
        );
        badgeTop += 12;
      }
      if (facts.queuePressureEvents > 0) {
        marks.add(
          Positioned(
            left: rect.x,
            top: badgeTop,
            child: Text(
              'queue ${facts.maxQueueDepth}/${facts.queueCapacity}',
              key: ValueKey('observable-runtime-queue-${node.id}'),
              style: const TextStyle(
                fontSize: 10,
                color: ObservableGraphPalette.runtimeQueue,
              ),
            ),
          ),
        );
      }
    }
    return marks;
  }
}

class _ObservableGraphPainter extends CustomPainter {
  _ObservableGraphPainter({
    required this.projection,
    required this.layout,
    this.overlay,
  }) : _edgesById = <String, ProjectedGraphEdge>{
          for (final edge in projection.edges) edge.id: edge,
        };

  final GraphProjection projection;
  final ObservableLayoutResult layout;
  final RuntimeOverlay? overlay;
  final Map<String, ProjectedGraphEdge> _edgesById;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = Offset.zero & size;
    for (final line in layout.edgePolylines) {
      final edge = _edgesById[line.edgeId];
      if (edge == null) {
        continue;
      }
      final path = Path();
      if (line.points.isEmpty) {
        continue;
      }
      path.moveTo(line.points.first.x, line.points.first.y);
      for (var i = 1; i < line.points.length; i += 1) {
        path.lineTo(line.points[i].x, line.points[i].y);
      }
      if (!path.getBounds().overlaps(visible)) {
        continue;
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edge.changeTag == GraphItemChangeTag.added ||
                edge.changeTag == GraphItemChangeTag.changed
            ? 2.4
            : 1.4
        ..color = edge.changeTag == GraphItemChangeTag.removed
            ? ObservableGraphPalette.removedGhost
            : edge.changeTag == GraphItemChangeTag.changed
            ? ObservableGraphPalette.changedAccent
            : ObservableGraphPalette.edgeColor(edge.kind);
      final dashes = edge.changeTag == GraphItemChangeTag.removed
          ? const <double>[2, 4]
          : ObservableGraphPalette.edgeDashes(edge.kind);
      if (dashes.isEmpty) {
        canvas.drawPath(path, paint);
      } else {
        canvas.drawPath(_dashPath(path, dashes), paint);
      }
    }
    for (final link in projection.lineageLinks) {
      final from = layout.nodeRects[link.fromId];
      final to = layout.nodeRects[link.toId];
      if (from == null || to == null) {
        continue;
      }
      final start = Offset(from.x + from.width / 2, from.y + from.height / 2);
      final end = Offset(to.x + to.width / 2, to.y + to.height / 2);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = ObservableGraphPalette.lineageLink;
      canvas.drawPath(
        _dashPath(
          Path()
            ..moveTo(start.dx, start.dy)
            ..lineTo(end.dx, end.dy),
          ObservableGraphPalette.lineageLinkDashes,
        ),
        paint,
      );
      final dot = Paint()
        ..style = PaintingStyle.fill
        ..color = ObservableGraphPalette.lineageLink;
      canvas.drawCircle(start, 3, dot);
      canvas.drawCircle(end, 3, dot);
    }
    final overlay = this.overlay;
    if (overlay != null) {
      for (final link in overlay.blockedLinks) {
        final from = layout.nodeRects[link.fromSite];
        final to = layout.nodeRects[link.toSite];
        if (from == null || to == null) {
          continue;
        }
        final start = Offset(from.x + from.width / 2, from.y + from.height / 2);
        final end = Offset(to.x + to.width / 2, to.y + to.height / 2);
        final color = ObservableGraphPalette.waitReason(link.reason);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = link.open > 0 ? 3.2 : 2.2
          ..color = color;
        canvas.drawPath(
          _dashPath(
            Path()
              ..moveTo(start.dx, start.dy)
              ..lineTo(end.dx, end.dy),
            ObservableGraphPalette.runtimeWaitDashes,
          ),
          paint,
        );
        // The link is an arrow from waiter to subject: without a head the
        // direction would be invisible on the canvas.
        final direction = end - start;
        final length = direction.distance;
        if (length > 0) {
          final unit = direction / length;
          final normal = Offset(-unit.dy, unit.dx);
          const headLength = 10.0;
          const headWidth = 6.0;
          final tip = end;
          final base = end - unit * headLength;
          canvas.drawPath(
            Path()
              ..moveTo(tip.dx, tip.dy)
              ..lineTo(base.dx + normal.dx * headWidth / 2, base.dy + normal.dy * headWidth / 2)
              ..lineTo(base.dx - normal.dx * headWidth / 2, base.dy - normal.dy * headWidth / 2)
              ..close(),
            Paint()
              ..style = PaintingStyle.fill
              ..color = color,
          );
        }
      }
    }
    for (final node in projection.nodes) {
      final rect = layout.nodeRects[node.id];
      if (rect == null) {
        continue;
      }
      final bounds = Rect.fromLTWH(rect.x, rect.y, rect.width, rect.height);
      if (!bounds.overlaps(visible)) {
        continue;
      }
      final intensity = overlay?.intensityFor(node.id) ?? 0;
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = node.changeTag == GraphItemChangeTag.removed
            ? ObservableGraphPalette.removedGhost.withValues(alpha: 0.35)
            : ObservableGraphPalette.heatFill(
                ObservableGraphPalette.nodeFill(node.kind),
                intensity,
              );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(6)),
        fill,
      );
      if (node.changeTag == GraphItemChangeTag.added) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(bounds, const Radius.circular(6)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = ObservableGraphPalette.addedAccent,
        );
      } else if (node.changeTag == GraphItemChangeTag.changed) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(bounds, const Radius.circular(6)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = ObservableGraphPalette.changedAccent,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ObservableGraphPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.projection != projection ||
        oldDelegate.overlay != overlay;
  }
}

Path _dashPath(Path source, List<double> dash) {
  final metrics = source.computeMetrics();
  final dest = Path();
  for (final metric in metrics) {
    var distance = 0.0;
    var draw = true;
    var index = 0;
    while (distance < metric.length) {
      final length = dash[index % dash.length];
      final next = distance + length;
      if (draw) {
        dest.addPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          Offset.zero,
        );
      }
      distance = next;
      draw = !draw;
      index += 1;
    }
  }
  return dest;
}

class _ObservableDetailPanel extends StatelessWidget {
  const _ObservableDetailPanel({required this.state, this.onOpenAnchor});

  final ObservableGraphState state;
  final ValueChanged<String>? onOpenAnchor;

  @override
  Widget build(BuildContext context) {
    final projection = state.projection;
    final selectedId = state.selectedNodeId;
    final node = selectedId == null ? null : projection?.nodeById(selectedId);
    final chain = node == null || projection == null
        ? const <ObservableEvidenceRecord>[]
        : walkEvidenceChain(projection: projection, startRef: node.evidenceRef);
    final resolved = state.selectedAnchorResolved;
    return KeyedSubtree(
      key: const ValueKey('observable-detail'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: node == null
              ? const Text('No node selected.')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text('kind ${node.rawKind}'),
                    Text('role ${node.role}'),
                    Text(
                      'anchor ${state.selectedAnchorRelativePath ?? 'unanchored'}',
                    ),
                    TextButton(
                      key: const ValueKey('observable-open-anchor'),
                      onPressed: !resolved || onOpenAnchor == null
                          ? null
                          : () => onOpenAnchor!(node.id),
                      child: Text(
                        resolved ? 'Open anchor' : 'anchor-unresolved',
                      ),
                    ),
                    for (final fact in node.facts)
                      Text('fact ${fact.predicate} → ${fact.canonicalValue}'),
                    const SizedBox(height: 8),
                    const Text('Change'),
                    for (final operation in _operationsFor(state, node))
                      Text(
                        '${operation.op.wireValue} ${operation.category.wireValue} ${operation.key}',
                      ),
                    for (final operation in _operationsFor(state, node))
                      for (final field in operation.fields)
                        Text(
                          '${field.name} ${field.before} → ${field.after}',
                        ),
                    const SizedBox(height: 8),
                    const Text('Lineage'),
                    for (final record in _lineageFor(state, node)) ...[
                      Text('kind ${record.kind.wireValue}'),
                      Text(
                        'counterparts ${[...record.prior, ...record.target].where((id) => id != node.id).join(' ')}',
                      ),
                      Text(
                        'producer_rule ${record.producerRule}@${record.ruleVersion}',
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text('evidence'),
                    for (final record in chain)
                      Text(
                        '${record.producerRule}@${record.ruleVersion}',
                      ),
                    const SizedBox(height: 8),
                    const Text('History'),
                    for (final record in _historyFor(state, node))
                      Text(
                        '${record.kind.wireValue} ${record.id}',
                      ),
                    ..._runtimeDetail(state, node),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

List<Widget> _runtimeDetail(
  ObservableGraphState state,
  ProjectedGraphNode node,
) {
  if (!state.runtime.marksCurrentHead(state.currentIdentity?.snapshotId)) {
    return const <Widget>[];
  }
  final overlay = state.runtime.overlay!;
  final facts = overlay.sites[node.id];
  if (facts == null) {
    return const <Widget>[];
  }
  final blockedOn = [
    for (final link in overlay.blockedLinks)
      if (link.fromSite == node.id) link,
  ];
  final blocking = [
    for (final link in overlay.blockedLinks)
      if (link.toSite == node.id) link,
  ];
  return <Widget>[
    const SizedBox(height: 8),
    const Text('Runtime'),
    Text(
      'instances ${facts.instancesActive} active ${facts.instancesCreated} created ${facts.instancesCompleted} completed ${facts.instancesFailed} failed',
    ),
    Text(
      'activity ${facts.activity(overlay.activitySource)} ${overlay.activitySource.legendName}',
    ),
    for (final entry in facts.waits.entries)
      Text(
        'wait ${entry.key.wireValue} open ${entry.value.open} closed ${entry.value.closed} duration ${entry.value.totalDurationNs}',
      ),
    for (final link in blockedOn)
      Text('blocked-on ${link.toSite} ${link.reason.wireValue}'),
    for (final link in blocking)
      Text('blocking ${link.fromSite} ${link.reason.wireValue}'),
    if (facts.queuePressureEvents > 0)
      Text('queue ${facts.maxQueueDepth}/${facts.queueCapacity}'),
    for (final event in facts.recentEvents)
      Text(
        '${event.rawKind} ${event.instanceId ?? ''} ${event.eventId} ${event.monotonicNs} ${event.causes.map((cause) => cause.rawKind).join(' ')}',
      ),
  ];
}

List<ObservableDeltaOperation> _operationsFor(
  ObservableGraphState state,
  ProjectedGraphNode node,
) {
  final operations = state.changeSet?.operations ?? const <ObservableDeltaOperation>[];
  return [
    for (final operation in operations)
      if (operation.key == node.id ||
          (operation.record != null &&
              (operation.record!['subject'] == node.id ||
                  operation.record!['id'] == node.id)) ||
          (operation.category == ObservableDeltaCategory.lineage &&
              ((operation.record?['prior'] as List?)?.contains(node.id) ==
                      true ||
                  (operation.record?['target'] as List?)?.contains(node.id) ==
                      true)))
        operation,
  ];
}

List<ObservableLineageRecord> _lineageFor(
  ObservableGraphState state,
  ProjectedGraphNode node,
) {
  final records = state.changeSet?.lineage ??
      state.snapshot?.lineage ??
      const <ObservableLineageRecord>[];
  return [
    for (final record in records)
      if (record.mentions(node.id)) record,
  ];
}

List<ObservableLineageRecord> _historyFor(
  ObservableGraphState state,
  ProjectedGraphNode node,
) {
  return [
    for (final entry in state.lineageHistory)
      for (final record in entry.lineageRecords)
        if (record.mentions(node.id)) record,
  ];
}
