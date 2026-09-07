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

  static const Color runtimeWaitLegend = Color(0xFF4A148C);
  static const List<double> runtimeWaitDashes = <double>[3, 2, 9, 2];

  static const Color runtimeHalo = Color(0xFF00838F);
  static const Color runtimeFailure = Color(0xFFC62828);
  static const Color runtimeQueue = Color(0xFFEF6C00);

  static Color waitReason(RuntimeWaitReason reason) {
    return switch (reason) {
      RuntimeWaitReason.runnable => const Color(0xFF1565C0),
      RuntimeWaitReason.task => const Color(0xFF6A1B9A),
      RuntimeWaitReason.backpressure => const Color(0xFFAD1457),
      RuntimeWaitReason.cooperative => const Color(0xFF00695C),
      RuntimeWaitReason.io => const Color(0xFF0277BD),
      RuntimeWaitReason.resource => const Color(0xFF5D4037),
      RuntimeWaitReason.timer => const Color(0xFF455A64),
      RuntimeWaitReason.cancellation => const Color(0xFF37474F),
      RuntimeWaitReason.unknown => const Color(0xFF78909C),
    };
  }

  static Color heatFill(Color base, double intensity) {
    if (intensity <= 0) {
      return base;
    }
    final hot = intensity <= 0.25
        ? const Color(0xFFFFF59D)
        : intensity <= 0.5
        ? const Color(0xFFFFD54F)
        : intensity <= 0.75
        ? const Color(0xFFFF8F00)
        : const Color(0xFFE65100);
    final t = intensity <= 0.25
        ? 0.28
        : intensity <= 0.5
        ? 0.45
        : intensity <= 0.75
        ? 0.62
        : 0.8;
    return Color.lerp(base, hot, t)!;
  }
}
