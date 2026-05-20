import '../../view_ide/foundation/foundation.dart';
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

  ShellPanelDescriptor copyWith({
    String? id,
    String? title,
    ShellLayoutRegion? region,
    bool? visible,
    bool? active,
    Map<String, Object?>? metadata,
    String? todo,
  }) {
    return ShellPanelDescriptor(
      id: id ?? this.id,
      title: title ?? this.title,
      region: region ?? this.region,
      visible: visible ?? this.visible,
      active: active ?? this.active,
      metadata: metadata ?? this.metadata,
      todo: todo ?? this.todo,
    );
  }

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

  ShellLayoutPlan copyWith({
    ShellLayoutMode? mode,
    BottomSurfaceTab? activeBottomTab,
    List<ShellPanelDescriptor>? panels,
    String? todo,
  }) {
    return ShellLayoutPlan(
      mode: mode ?? this.mode,
      activeBottomTab: activeBottomTab ?? this.activeBottomTab,
      panels: panels ?? this.panels,
      todo: todo ?? this.todo,
    );
  }

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

  ShellLayoutRenderBinding renderBinding() {
    return ShellLayoutRenderBinding.fromPlan(this);
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

class ShellLayoutPreferences {
  const ShellLayoutPreferences({
    required this.workspaceId,
    this.activeBottomTab = BottomSurfaceTab.runtime,
    this.hiddenPanelIds = const <String>{},
    this.pinnedPanelIds = const <String>{},
    this.bottomPanelExpanded = true,
    this.updatedAt,
  });

  factory ShellLayoutPreferences.fromJson(Map<String, Object?> json) {
    return ShellLayoutPreferences(
      workspaceId: json['workspaceId'] as String? ?? '',
      activeBottomTab: _bottomTabFromWire(json['activeBottomTab']),
      hiddenPanelIds: _jsonStringSet(json['hiddenPanelIds']),
      pinnedPanelIds: _jsonStringSet(json['pinnedPanelIds']),
      bottomPanelExpanded: json['bottomPanelExpanded'] as bool? ?? true,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final BottomSurfaceTab activeBottomTab;
  final Set<String> hiddenPanelIds;
  final Set<String> pinnedPanelIds;
  final bool bottomPanelExpanded;
  final DateTime? updatedAt;

  ShellLayoutPreferences copyWith({
    String? workspaceId,
    BottomSurfaceTab? activeBottomTab,
    Set<String>? hiddenPanelIds,
    Set<String>? pinnedPanelIds,
    bool? bottomPanelExpanded,
    DateTime? updatedAt,
  }) {
    return ShellLayoutPreferences(
      workspaceId: workspaceId ?? this.workspaceId,
      activeBottomTab: activeBottomTab ?? this.activeBottomTab,
      hiddenPanelIds: hiddenPanelIds ?? this.hiddenPanelIds,
      pinnedPanelIds: pinnedPanelIds ?? this.pinnedPanelIds,
      bottomPanelExpanded: bottomPanelExpanded ?? this.bottomPanelExpanded,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  ShellLayoutPlan applyTo(ShellLayoutPlan plan) {
    final activeBottomPanelId = 'bottom.${activeBottomTab.name}';
    return plan.copyWith(
      activeBottomTab: activeBottomTab,
      panels: plan.panels
          .map((panel) {
            final metadata = <String, Object?>{
              ...panel.metadata,
              if (pinnedPanelIds.contains(panel.id)) 'pinned': true,
              if (panel.region == ShellLayoutRegion.bottomPanel)
                'bottomPanelExpanded': bottomPanelExpanded,
            };
            return panel.copyWith(
              visible: hiddenPanelIds.contains(panel.id)
                  ? false
                  : panel.visible,
              active: panel.region == ShellLayoutRegion.bottomPanel
                  ? panel.id == activeBottomPanelId
                  : panel.active,
              metadata: metadata,
            );
          })
          .toList(growable: false),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'activeBottomTab': activeBottomTab.name,
      'hiddenPanelIds': _sortedStrings(hiddenPanelIds),
      'pinnedPanelIds': _sortedStrings(pinnedPanelIds),
      'bottomPanelExpanded': bottomPanelExpanded,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class ShellLayoutPreferencesStore {
  ShellLayoutPreferencesStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'presentation.shell-layout-preferences',
             layer: 'presentation',
             stateFamily: 'shell-layout',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const ShellLayoutPreferencesStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'presentation.shell-layout';
  static const String _key = 'preferences';

  final FoundationDataStoreOwner _owner;

  Future<void> savePreferences(ShellLayoutPreferences preferences) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: preferences.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: preferences.workspaceId,
    );
  }

  Future<ShellLayoutPreferences> readPreferences({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return ShellLayoutPreferences(workspaceId: workspaceId);
    }
    final preferences = ShellLayoutPreferences.fromJson(value);
    return preferences.workspaceId.isEmpty
        ? preferences.copyWith(workspaceId: workspaceId)
        : preferences;
  }

  Future<bool> deletePreferences({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchPreferences({
    required String workspaceId,
  }) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

class ShellLayoutRenderBinding {
  const ShellLayoutRenderBinding({
    required this.mode,
    required this.viewportKey,
    required this.activeBottomPanelId,
    required this.visiblePanelIds,
    required this.compactActivityFallback,
  });

  factory ShellLayoutRenderBinding.fromPlan(ShellLayoutPlan plan) {
    final activeBottomPanelId = 'bottom.${plan.activeBottomTab.name}';
    return ShellLayoutRenderBinding(
      mode: plan.mode,
      viewportKey: 'shell-viewport-${plan.mode.wireValue}',
      activeBottomPanelId: activeBottomPanelId,
      visiblePanelIds: plan.visiblePanelIds,
      compactActivityFallback:
          plan.panelById('activity-rail')?.visible == false &&
          plan.mode == ShellLayoutMode.compact,
    );
  }

  final ShellLayoutMode mode;
  final String viewportKey;
  final String activeBottomPanelId;
  final List<String> visiblePanelIds;
  final bool compactActivityFallback;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': mode.wireValue,
      'viewportKey': viewportKey,
      'activeBottomPanelId': activeBottomPanelId,
      'visiblePanelIds': visiblePanelIds,
      'compactActivityFallback': compactActivityFallback,
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

Set<String> _jsonStringSet(Object? value) {
  if (value is! List) {
    return const <String>{};
  }
  return Set<String>.unmodifiable(
    value.whereType<String>().where((item) => item.trim().isNotEmpty),
  );
}

List<String> _sortedStrings(Iterable<String> values) {
  final sorted = values.toList(growable: false)..sort();
  return sorted;
}
