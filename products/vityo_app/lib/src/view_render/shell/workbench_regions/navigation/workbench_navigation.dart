import 'package:flutter/material.dart';

import '../../../theme/vityo_theme.dart';

@immutable
final class WorkbenchDestination {
  const WorkbenchDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class WorkbenchActivityRail extends StatelessWidget {
  const WorkbenchActivityRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<WorkbenchDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = VityoWorkbenchTokens.of(context);
    return Container(
      key: const ValueKey('workbench-activity-rail'),
      width: 48,
      decoration: BoxDecoration(
        color: tokens.region,
        border: Border(right: BorderSide(color: tokens.divider)),
      ),
      child: ListView.builder(
        itemCount: destinations.length,
        itemBuilder: (context, index) {
          final destination = destinations[index];
          final selected = index == selectedIndex;
          return Semantics(
            button: true,
            selected: selected,
            label: destination.label,
            child: Tooltip(
              message: destination.label,
              child: InkWell(
                onTap: () => onSelected(index),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected ? tokens.selection : Colors.transparent,
                    border: Border(
                      left: BorderSide(
                        width: 2,
                        color: selected ? tokens.focus : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Icon(
                    destination.icon,
                    size: 20,
                    color: selected ? tokens.ink : tokens.muted,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
