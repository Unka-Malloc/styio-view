import 'package:flutter/material.dart';

import '../panels/workbench_panel.dart';

class WorkbenchAuxiliaryPanel extends StatelessWidget {
  const WorkbenchAuxiliaryPanel({
    required this.label,
    required this.child,
    this.width = 280,
    super.key,
  });

  final String label;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('workbench-auxiliary-panel'),
    width: width,
    child: WorkbenchRegionSurface(label: label, child: child),
  );
}
