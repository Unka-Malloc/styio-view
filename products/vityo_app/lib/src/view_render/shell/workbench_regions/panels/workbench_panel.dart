import 'package:flutter/material.dart';

import '../../../theme/vityo_theme.dart';

class WorkbenchRegionSurface extends StatelessWidget {
  const WorkbenchRegionSurface({
    required this.label,
    required this.child,
    this.headerActions = const <Widget>[],
    this.showHeader = true,
    super.key,
  });

  final String label;
  final Widget child;
  final List<Widget> headerActions;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final tokens = VityoWorkbenchTokens.of(context);
    return Semantics(
      container: true,
      label: '$label region',
      child: ColoredBox(
        color: tokens.region,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader)
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: tokens.divider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    ...headerActions,
                  ],
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class WorkbenchBottomPanelFrame extends StatelessWidget {
  const WorkbenchBottomPanelFrame({
    required this.label,
    required this.child,
    required this.expanded,
    super.key,
  });

  final String label;
  final Widget child;
  final bool expanded;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 120),
    alignment: Alignment.topCenter,
    child: expanded
        ? SizedBox(
            key: const ValueKey('workbench-bottom-panel'),
            height: 220,
            child: WorkbenchRegionSurface(label: label, child: child),
          )
        : const SizedBox.shrink(),
  );
}
