import 'package:flutter/material.dart';

import '../../view_ide/services/observable_topology/observable_topology.dart';
import '../platform/platform.dart';
import 'observable_graph_palette.dart';

class ObservableGraphSurface extends StatelessWidget {
  const ObservableGraphSurface({
    super.key,
    required this.viewportProfile,
    required this.state,
    this.onRefresh,
    this.onSelectNode,
    this.onOpenAnchor,
  });

  final ViewportProfile viewportProfile;
  final ObservableGraphState state;
  final VoidCallback? onRefresh;
  final ValueChanged<String>? onSelectNode;
  final ValueChanged<String>? onOpenAnchor;

  @override
  Widget build(BuildContext context) {
    final compact = viewportProfile.isMobile;
    final showTopology =
        state.availability.showsTopology &&
        state.projection != null &&
        state.availability != ObservableAvailability.scalarNoop &&
        state.availability != ObservableAvailability.blocked;

    // Compact bottom panels are as short as 156 logical pixels, so the
    // surface follows the repository convention for compact bottom surfaces:
    // one scrollable column with a fixed-height level-of-detail canvas and
    // detail panel instead of a stretched fixed Column.
    if (compact) {
      return KeyedSubtree(
        key: const ValueKey('observable-graph-surface'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ListView(
            key: const ValueKey('observable-content-scroll'),
            children: [
              _ObservableBanner(state: state, onRefresh: onRefresh),
              const SizedBox(height: 8),
              _ObservableCounters(changeSet: state.changeSet),
              const SizedBox(height: 8),
              SizedBox(height: 180, child: _canvas(showTopology)),
              const SizedBox(height: 8),
              SizedBox(height: 168, child: _detail()),
              const SizedBox(height: 8),
              const _ObservableLegend(),
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
            _ObservableBanner(state: state, onRefresh: onRefresh),
            const SizedBox(height: 8),
            const _ObservableLegend(),
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
      state: state,
      onSelectNode: onSelectNode,
    );
  }

  Widget _detail() {
    return _ObservableDetailPanel(
      state: state,
      onOpenAnchor: onOpenAnchor,
    );
  }
}

class _ObservableBanner extends StatelessWidget {
  const _ObservableBanner({required this.state, this.onRefresh});

  final ObservableGraphState state;
  final VoidCallback? onRefresh;

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
          child: Row(
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
        ),
      ),
    );
  }
}

class _ObservableLegend extends StatelessWidget {
  const _ObservableLegend();

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

class _ObservableCounters extends StatelessWidget {
  const _ObservableCounters({required this.changeSet});

  final ObservableChangeSet? changeSet;

  @override
  Widget build(BuildContext context) {
    final added = changeSet?.addedCount ?? 0;
    final removed = changeSet?.removedCount ?? 0;
    return KeyedSubtree(
      key: const ValueKey('observable-counters'),
      child: Text('added $added · removed $removed'),
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
                ),
              ),
              for (final node in projection.nodes)
                if (layout.nodeRects[node.id] != null)
                  _nodeHitTarget(layout.nodeRects[node.id]!, node),
            ],
          ),
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
}

class _ObservableGraphPainter extends CustomPainter {
  _ObservableGraphPainter({
    required this.projection,
    required this.layout,
  }) : _edgesById = <String, ProjectedGraphEdge>{
          for (final edge in projection.edges) edge.id: edge,
        };

  final GraphProjection projection;
  final ObservableLayoutResult layout;
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
        ..strokeWidth = edge.changeTag == GraphItemChangeTag.added ? 2.4 : 1.4
        ..color = edge.changeTag == GraphItemChangeTag.removed
            ? ObservableGraphPalette.removedGhost
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
    for (final node in projection.nodes) {
      final rect = layout.nodeRects[node.id];
      if (rect == null) {
        continue;
      }
      final bounds = Rect.fromLTWH(rect.x, rect.y, rect.width, rect.height);
      if (!bounds.overlaps(visible)) {
        continue;
      }
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = node.changeTag == GraphItemChangeTag.removed
            ? ObservableGraphPalette.removedGhost.withValues(alpha: 0.35)
            : ObservableGraphPalette.nodeFill(node.kind);
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
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ObservableGraphPainter oldDelegate) {
    return oldDelegate.layout != layout || oldDelegate.projection != projection;
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
              : ListView(
                  children: [
                    Text('kind ${node.rawKind}'),
                    Text('role ${node.role}'),
                    Text(
                      'anchor ${state.selectedAnchorRelativePath ?? 'unanchored'}',
                    ),
                    for (final fact in node.facts)
                      Text('fact ${fact.predicate} → ${fact.canonicalValue}'),
                    const SizedBox(height: 8),
                    const Text('evidence'),
                    for (final record in chain)
                      Text(
                        '${record.producerRule}@${record.ruleVersion}',
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const ValueKey('observable-open-anchor'),
                      onPressed: !resolved || onOpenAnchor == null
                          ? null
                          : () => onOpenAnchor!(node.id),
                      child: Text(
                        resolved ? 'Open anchor' : 'anchor-unresolved',
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
