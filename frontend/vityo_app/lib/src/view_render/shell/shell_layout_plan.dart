import 'shell_model.dart';

enum ShellLayoutMode { desktop, compact }

extension ShellLayoutModeX on ShellLayoutMode {
  String get wireValue => switch (this) {
    ShellLayoutMode.desktop => 'desktop',
    ShellLayoutMode.compact => 'compact',
  };
}

enum ShellLayoutRegion { topBar, activityRail, editor, bottomPanel, statusBar }

extension ShellLayoutRegionX on ShellLayoutRegion {
  String get wireValue => switch (this) {
    ShellLayoutRegion.topBar => 'top-bar',
    ShellLayoutRegion.activityRail => 'activity-rail',
    ShellLayoutRegion.editor => 'editor',
    ShellLayoutRegion.bottomPanel => 'bottom-panel',
    ShellLayoutRegion.statusBar => 'status-bar',
  };
}

class ShellPanelDescriptor {
  const ShellPanelDescriptor({
    required this.id,
    required this.title,
    required this.region,
    required this.visible,
    this.active = false,
    this.metadata = const <String, Object?>{},
    this.todo = '',
  });

  factory ShellPanelDescriptor.fromJson(Map<String, Object?> json) {
    return ShellPanelDescriptor(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      region: _regionFromWire(json['region']),
      visible: json['visible'] as bool? ?? false,
      active: json['active'] as bool? ?? false,
      metadata: _jsonObjectMap(json['metadata']),
      todo: json['todo'] as String? ?? '',
    );
  }

  final String id;
  final String title;
  final ShellLayoutRegion region;
  final bool visible;
  final bool active;
  final Map<String, Object?> metadata;
  final String todo;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'region': region.wireValue,
      'visible': visible,
      'active': active,
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class ShellLayoutPlan {
  const ShellLayoutPlan({
    required this.mode,
    required this.activeBottomTab,
    required this.panels,
    this.todo = '',
  });

  factory ShellLayoutPlan.fromJson(Map<String, Object?> json) {
    return ShellLayoutPlan(
      mode: _modeFromWire(json['mode']),
      activeBottomTab: _bottomTabFromWire(json['activeBottomTab']),
      panels: _jsonPanels(json['panels']),
      todo: json['todo'] as String? ?? '',
    );
  }

  factory ShellLayoutPlan.forViewport({
    required BottomSurfaceTab activeBottomTab,
    required bool compact,
  }) {
    final mode = compact ? ShellLayoutMode.compact : ShellLayoutMode.desktop;
    final panels = <ShellPanelDescriptor>[
      const ShellPanelDescriptor(
        id: 'top-bar',
        title: 'Top Bar',
        region: ShellLayoutRegion.topBar,
        visible: true,
      ),
      ShellPanelDescriptor(
        id: 'activity-rail',
        title: 'Activity Rail',
        region: ShellLayoutRegion.activityRail,
        visible: !compact,
        todo: compact
            ? 'TODO: expose compact activity actions through a mobile command surface.'
            : '',
      ),
      const ShellPanelDescriptor(
        id: 'editor',
        title: 'Editor',
        region: ShellLayoutRegion.editor,
        visible: true,
        active: true,
      ),
      ...BottomSurfaceTab.values.map(
        (tab) => ShellPanelDescriptor(
          id: 'bottom.${tab.name}',
          title: _bottomTabTitle(tab),
          region: ShellLayoutRegion.bottomPanel,
          visible: true,
          active: tab == activeBottomTab,
        ),
      ),
      const ShellPanelDescriptor(
        id: 'status-bar',
        title: 'Status Bar',
        region: ShellLayoutRegion.statusBar,
        visible: true,
      ),
    ];
    return ShellLayoutPlan(
      mode: mode,
      activeBottomTab: activeBottomTab,
      panels: panels,
      todo:
          'TODO: bind this layout contract directly into shell scaffold rendering and persisted layout preferences.',
    );
  }

  final ShellLayoutMode mode;
  final BottomSurfaceTab activeBottomTab;
  final List<ShellPanelDescriptor> panels;
  final String todo;

  ShellPanelDescriptor? panelById(String id) {
    for (final panel in panels) {
      if (panel.id == id) {
        return panel;
      }
    }
    return null;
  }

  List<String> get visiblePanelIds {
    return panels
        .where((panel) => panel.visible)
        .map((panel) => panel.id)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': mode.wireValue,
      'activeBottomTab': activeBottomTab.name,
      'visiblePanelIds': visiblePanelIds,
      'panels': panels.map((panel) => panel.toJson()).toList(growable: false),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

ShellLayoutMode _modeFromWire(Object? value) {
  return switch (value) {
    'desktop' => ShellLayoutMode.desktop,
    'compact' => ShellLayoutMode.compact,
    _ => ShellLayoutMode.desktop,
  };
}

ShellLayoutRegion _regionFromWire(Object? value) {
  return switch (value) {
    'top-bar' => ShellLayoutRegion.topBar,
    'activity-rail' => ShellLayoutRegion.activityRail,
    'editor' => ShellLayoutRegion.editor,
    'bottom-panel' => ShellLayoutRegion.bottomPanel,
    'status-bar' => ShellLayoutRegion.statusBar,
    _ => ShellLayoutRegion.editor,
  };
}

BottomSurfaceTab _bottomTabFromWire(Object? value) {
  final name = value as String? ?? '';
  for (final tab in BottomSurfaceTab.values) {
    if (tab.name == name) {
      return tab;
    }
  }
  return BottomSurfaceTab.runtime;
}

String _bottomTabTitle(BottomSurfaceTab tab) {
  return switch (tab) {
    BottomSurfaceTab.runtime => 'Runtime',
    BottomSurfaceTab.terminal => 'Terminal',
    BottomSurfaceTab.commandPalette => 'Command Palette',
    BottomSurfaceTab.agent => 'Agent',
    BottomSurfaceTab.sourceControl => 'Source Control',
    BottomSurfaceTab.search => 'Search',
    BottomSurfaceTab.problems => 'Problems',
    BottomSurfaceTab.testing => 'Testing',
    BottomSurfaceTab.extensions => 'Extensions',
    BottomSurfaceTab.debug => 'Debug',
    BottomSurfaceTab.settings => 'Settings',
  };
}

List<ShellPanelDescriptor> _jsonPanels(Object? value) {
  if (value is! List) {
    return const <ShellPanelDescriptor>[];
  }
  return value
      .whereType<Map>()
      .map(
        (panel) => ShellPanelDescriptor.fromJson(
          panel.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}

Map<String, Object?> _jsonObjectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry<String, Object?>(key.toString(), value)),
  );
}
