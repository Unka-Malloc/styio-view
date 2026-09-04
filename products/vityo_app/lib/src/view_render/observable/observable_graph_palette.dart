import 'package:flutter/material.dart';

import '../../view_ide/services/observable_topology/observable_topology.dart';

class ObservableGraphPalette {
  const ObservableGraphPalette._();

  static Color nodeFill(ObservableNodeKind kind) {
    return switch (kind) {
      ObservableNodeKind.program => const Color(0xFF1F4E79),
      ObservableNodeKind.driverSource => const Color(0xFF2E7D32),
      ObservableNodeKind.handle => const Color(0xFF6A1B9A),
      ObservableNodeKind.streamOp => const Color(0xFF0277BD),
      ObservableNodeKind.stateSlot => const Color(0xFFEF6C00),
      ObservableNodeKind.hiddenLedger => const Color(0xFF455A64),
      ObservableNodeKind.sink => const Color(0xFFC62828),
      ObservableNodeKind.task => const Color(0xFF00838F),
      ObservableNodeKind.failureDomain => const Color(0xFFAD1457),
      ObservableNodeKind.value => const Color(0xFF558B2F),
      ObservableNodeKind.unknown => const Color(0xFF78909C),
    };
  }

  static List<double> edgeDashes(ObservableEdgeKind kind) {
    return switch (kind) {
      ObservableEdgeKind.flow => const <double>[],
      ObservableEdgeKind.intent => const <double>[8, 4],
      ObservableEdgeKind.ownership => const <double>[],
      ObservableEdgeKind.borrow => const <double>[2, 4],
      ObservableEdgeKind.mutation => const <double>[10, 3, 2, 3],
      ObservableEdgeKind.backpressure => const <double>[4, 4],
      ObservableEdgeKind.commit => const <double>[12, 6],
      ObservableEdgeKind.happensBefore => const <double>[1, 3],
      ObservableEdgeKind.failure => const <double>[6, 2, 2, 2],
      ObservableEdgeKind.placement => const <double>[14, 4],
      ObservableEdgeKind.unknown => const <double>[3, 3],
    };
  }

  static Color edgeColor(ObservableEdgeKind kind) {
    return switch (kind) {
      ObservableEdgeKind.flow => const Color(0xFF1565C0),
      ObservableEdgeKind.intent => const Color(0xFF6A1B9A),
      ObservableEdgeKind.ownership => const Color(0xFF2E7D32),
      ObservableEdgeKind.borrow => const Color(0xFF00838F),
      ObservableEdgeKind.mutation => const Color(0xFFEF6C00),
      ObservableEdgeKind.backpressure => const Color(0xFFAD1457),
      ObservableEdgeKind.commit => const Color(0xFF37474F),
      ObservableEdgeKind.happensBefore => const Color(0xFF5D4037),
      ObservableEdgeKind.failure => const Color(0xFFC62828),
      ObservableEdgeKind.placement => const Color(0xFF546E7A),
      ObservableEdgeKind.unknown => const Color(0xFF90A4AE),
    };
  }

  static const Color addedAccent = Color(0xFF2E7D32);
  static const Color removedGhost = Color(0xFF90A4AE);
  static const Color changedAccent = Color(0xFF1565C0);
  static const Color continuityBadge = Color(0xFF6A1B9A);

  /// Producer lineage links must be distinguishable from every producer edge
  /// kind at a glance, so both the colour and the dash pattern are unique:
  /// no [edgeColor] or [edgeDashes] entry uses them.
  static const Color lineageLink = Color(0xFFF9A825);
  static const List<double> lineageLinkDashes = <double>[6, 3];
}
