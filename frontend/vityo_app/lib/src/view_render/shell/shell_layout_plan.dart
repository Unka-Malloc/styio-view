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

enum ShellPanelContributionStatus { scaffolded, wired, production }

extension ShellPanelContributionStatusX on ShellPanelContributionStatus {
  String get wireValue => switch (this) {
    ShellPanelContributionStatus.scaffolded => 'scaffolded',
    ShellPanelContributionStatus.wired => 'wired',
    ShellPanelContributionStatus.production => 'production',
  };
}

class ShellPanelContribution {
  const ShellPanelContribution({
    required this.id,
    required this.title,
    required this.region,
    required this.surfaceId,
    required this.capabilities,
    required this.status,
    this.bottomTab,
    this.defaultVisible = true,
    this.metadata = const <String, Object?>{},
    this.todo = '',
  });

  factory ShellPanelContribution.bottomPanel({
    required BottomSurfaceTab tab,
    required String title,
    required String surfaceId,
    required List<String> capabilities,
    ShellPanelContributionStatus status = ShellPanelContributionStatus.wired,
    Map<String, Object?> metadata = const <String, Object?>{},
    String todo = '',
  }) {
    return ShellPanelContribution(
      id: 'bottom.${tab.name}',
      title: title,
      region: ShellLayoutRegion.bottomPanel,
      surfaceId: surfaceId,
      capabilities: capabilities,
      status: status,
      bottomTab: tab,
      metadata: metadata,
      todo: todo,
    );
  }

  final String id;
  final String title;
  final ShellLayoutRegion region;
  final String surfaceId;
  final List<String> capabilities;
  final ShellPanelContributionStatus status;
  final BottomSurfaceTab? bottomTab;
  final bool defaultVisible;
  final Map<String, Object?> metadata;
  final String todo;

  ShellPanelDescriptor toPanelDescriptor({
    required BottomSurfaceTab activeBottomTab,
  }) {
    return ShellPanelDescriptor(
      id: id,
      title: title,
      region: region,
      visible: defaultVisible,
      active: bottomTab == activeBottomTab,
      metadata: <String, Object?>{
        ...metadata,
        'surfaceId': surfaceId,
        'capabilities': capabilities,
        'contributionStatus': status.wireValue,
        if (bottomTab != null) 'bottomTab': bottomTab!.name,
      },
      todo: todo,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'region': region.wireValue,
      'surfaceId': surfaceId,
      'capabilities': capabilities,
      'status': status.wireValue,
      'defaultVisible': defaultVisible,
      if (bottomTab != null) 'bottomTab': bottomTab!.name,
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class ShellPanelContributionCoverage {
  const ShellPanelContributionCoverage({
    required this.requiredPanelIds,
    required this.registeredPanelIds,
    required this.missingPanelIds,
  });

  final List<String> requiredPanelIds;
  final List<String> registeredPanelIds;
  final List<String> missingPanelIds;

  bool get complete => missingPanelIds.isEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'complete': complete,
      'requiredPanelIds': requiredPanelIds,
      'registeredPanelIds': registeredPanelIds,
      'missingPanelIds': missingPanelIds,
    };
  }
}

class ShellPanelContributionRegistry {
  ShellPanelContributionRegistry({
    Iterable<ShellPanelContribution> contributions =
        const <ShellPanelContribution>[],
  }) {
    for (final contribution in contributions) {
      register(contribution);
    }
  }

  factory ShellPanelContributionRegistry.defaultIdePanels() {
    return ShellPanelContributionRegistry(
      contributions: _defaultBottomPanelContributions(),
    );
  }

  static const List<String> coreIdePanelIds = <String>[
    'bottom.problems',
    'bottom.search',
    'bottom.settings',
    'bottom.extensions',
    'bottom.debug',
    'bottom.agent',
  ];

  final List<ShellPanelContribution> _contributions =
      <ShellPanelContribution>[];

  List<ShellPanelContribution> get contributions {
    return List<ShellPanelContribution>.unmodifiable(_contributions);
  }

  void register(ShellPanelContribution contribution) {
    _contributions.removeWhere((candidate) => candidate.id == contribution.id);
    _contributions.add(contribution);
  }

  ShellPanelContribution? panelById(String panelId) {
    for (final contribution in _contributions) {
      if (contribution.id == panelId) {
        return contribution;
      }
    }
    return null;
  }

  List<ShellPanelDescriptor> descriptorsForRegion({
    required ShellLayoutRegion region,
    required BottomSurfaceTab activeBottomTab,
  }) {
    return _contributions
        .where((contribution) => contribution.region == region)
        .map(
          (contribution) =>
              contribution.toPanelDescriptor(activeBottomTab: activeBottomTab),
        )
        .toList(growable: false);
  }

  ShellPanelContributionCoverage coverageForCoreIdePanels() {
    return coverageFor(requiredPanelIds: coreIdePanelIds);
  }

  ShellPanelContributionCoverage coverageFor({
    required List<String> requiredPanelIds,
  }) {
    final registered = _contributions
        .map((contribution) => contribution.id)
        .toSet();
    return ShellPanelContributionCoverage(
      requiredPanelIds: requiredPanelIds,
      registeredPanelIds: _contributions
          .map((contribution) => contribution.id)
          .toList(growable: false),
      missingPanelIds: requiredPanelIds
          .where((panelId) => !registered.contains(panelId))
          .toList(growable: false),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'contributionCount': _contributions.length,
      'coreIdeCoverage': coverageForCoreIdePanels().toJson(),
      'contributions': _contributions
          .map((contribution) => contribution.toJson())
          .toList(growable: false),
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
    ShellPanelContributionRegistry? panelRegistry,
  }) {
    final mode = compact ? ShellLayoutMode.compact : ShellLayoutMode.desktop;
    final contributions =
        panelRegistry ?? ShellPanelContributionRegistry.defaultIdePanels();
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
      ...contributions.descriptorsForRegion(
        region: ShellLayoutRegion.bottomPanel,
        activeBottomTab: activeBottomTab,
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
          'TODO: mature diagnostics, search, settings, extensions, debug, and agent panel internals behind ShellPanelContributionRegistry renderers.',
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

List<ShellPanelContribution> _defaultBottomPanelContributions() {
  return BottomSurfaceTab.values
      .map((tab) {
        final panelId = 'bottom.${tab.name}';
        final metadata = <String, Object?>{
          'coreIdePanel': ShellPanelContributionRegistry.coreIdePanelIds
              .contains(panelId),
        };
        return ShellPanelContribution.bottomPanel(
          tab: tab,
          title: _bottomTabTitle(tab),
          surfaceId: _bottomTabSurfaceId(tab),
          capabilities: _bottomTabCapabilities(tab),
          metadata: metadata,
          todo: _bottomTabPanelTodo(tab),
        );
      })
      .toList(growable: false);
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

class ShellLayoutPreferenceController {
  ShellLayoutPreferenceController({
    required ShellLayoutPreferences initialPreferences,
  }) : _preferences = initialPreferences;

  ShellLayoutPreferences _preferences;
  int _revision = 0;

  ShellLayoutPreferences get preferences => _preferences;

  int get revision => _revision;

  Future<void> loadFromStore(
    ShellLayoutPreferencesStore store, {
    required String workspaceId,
  }) async {
    hydrate(await store.readPreferences(workspaceId: workspaceId));
  }

  Future<void> saveToStore(ShellLayoutPreferencesStore store) {
    return store.savePreferences(_preferences);
  }

  void hydrate(ShellLayoutPreferences preferences) {
    _setPreferences(preferences);
  }

  void selectBottomTab(BottomSurfaceTab tab) {
    if (_preferences.activeBottomTab == tab) {
      return;
    }
    _setPreferences(_preferences.copyWith(activeBottomTab: tab));
  }

  void setPanelVisible(String panelId, {required bool visible}) {
    final hiddenPanelIds = <String>{..._preferences.hiddenPanelIds};
    final changed = visible
        ? hiddenPanelIds.remove(panelId)
        : hiddenPanelIds.add(panelId);
    if (!changed) {
      return;
    }
    _setPreferences(_preferences.copyWith(hiddenPanelIds: hiddenPanelIds));
  }

  void setPanelPinned(String panelId, {required bool pinned}) {
    final pinnedPanelIds = <String>{..._preferences.pinnedPanelIds};
    final changed = pinned
        ? pinnedPanelIds.add(panelId)
        : pinnedPanelIds.remove(panelId);
    if (!changed) {
      return;
    }
    _setPreferences(_preferences.copyWith(pinnedPanelIds: pinnedPanelIds));
  }

  void setBottomPanelExpanded(bool expanded) {
    if (_preferences.bottomPanelExpanded == expanded) {
      return;
    }
    _setPreferences(_preferences.copyWith(bottomPanelExpanded: expanded));
  }

  ShellLayoutPlan planForViewport({required bool compact}) {
    return _preferences.applyTo(
      ShellLayoutPlan.forViewport(
        activeBottomTab: _preferences.activeBottomTab,
        compact: compact,
      ),
    );
  }

  ShellLayoutRenderBinding renderBindingForViewport({required bool compact}) {
    return planForViewport(compact: compact).renderBinding();
  }

  void _setPreferences(ShellLayoutPreferences preferences) {
    _preferences = preferences.copyWith(updatedAt: DateTime.now().toUtc());
    _revision += 1;
  }
}

class ShellLayoutRenderBinding {
  const ShellLayoutRenderBinding({
    required this.mode,
    required this.viewportKey,
    required this.activeBottomPanelId,
    required this.visiblePanelIds,
    required this.bottomPanelExpanded,
    required this.compactActivityFallback,
  });

  factory ShellLayoutRenderBinding.fromPlan(ShellLayoutPlan plan) {
    final activeBottomPanelId = 'bottom.${plan.activeBottomTab.name}';
    final activeBottomPanel = plan.panelById(activeBottomPanelId);
    final viewportKey = plan.mode == ShellLayoutMode.compact
        ? 'shell-viewport-mobile'
        : 'shell-viewport-${plan.mode.wireValue}';
    return ShellLayoutRenderBinding(
      mode: plan.mode,
      viewportKey: viewportKey,
      activeBottomPanelId: activeBottomPanelId,
      visiblePanelIds: plan.visiblePanelIds,
      bottomPanelExpanded:
          activeBottomPanel?.metadata['bottomPanelExpanded'] as bool? ?? true,
      compactActivityFallback:
          plan.panelById('activity-rail')?.visible == false &&
          plan.mode == ShellLayoutMode.compact,
    );
  }

  final ShellLayoutMode mode;
  final String viewportKey;
  final String activeBottomPanelId;
  final List<String> visiblePanelIds;
  final bool bottomPanelExpanded;
  final bool compactActivityFallback;

  bool isPanelVisible(String panelId) {
    return visiblePanelIds.contains(panelId);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': mode.wireValue,
      'viewportKey': viewportKey,
      'activeBottomPanelId': activeBottomPanelId,
      'visiblePanelIds': visiblePanelIds,
      'bottomPanelExpanded': bottomPanelExpanded,
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
    BottomSurfaceTab.commands => 'Command Palette',
    BottomSurfaceTab.agent => 'Agent',
    BottomSurfaceTab.sourceControl => 'Source Control',
    BottomSurfaceTab.search => 'Search',
    BottomSurfaceTab.problems => 'Problems',
    BottomSurfaceTab.testing => 'Testing',
    BottomSurfaceTab.extensions => 'Extensions',
    BottomSurfaceTab.debug => 'Debug',
    BottomSurfaceTab.navigate => 'Navigate',
    BottomSurfaceTab.settings => 'Settings',
    BottomSurfaceTab.locations => 'Locations',
    _ => '',
  };
}

String _bottomTabSurfaceId(BottomSurfaceTab tab) {
  return switch (tab) {
    BottomSurfaceTab.runtime => 'runtime.output',
    BottomSurfaceTab.terminal => 'terminal.session',
    BottomSurfaceTab.commands => 'commands.palette',
    BottomSurfaceTab.agent => 'agent.activity',
    BottomSurfaceTab.sourceControl => 'source-control.changes',
    BottomSurfaceTab.search => 'workspace.search',
    BottomSurfaceTab.problems => 'workspace.problems',
    BottomSurfaceTab.testing => 'testing.results',
    BottomSurfaceTab.extensions => 'extensions.marketplace',
    BottomSurfaceTab.debug => 'debug.console',
    BottomSurfaceTab.navigate => 'navigate.quick',
    BottomSurfaceTab.settings => 'settings.workspace',
    BottomSurfaceTab.locations => 'locations.list',
    _ => '',
  };
}

List<String> _bottomTabCapabilities(BottomSurfaceTab tab) {
  return switch (tab) {
    BottomSurfaceTab.runtime => const <String>[
      'runtime-output',
      'task-activity',
    ],
    BottomSurfaceTab.terminal => const <String>['terminal', 'pty-session'],
    BottomSurfaceTab.commands => const <String>[
      'command-search',
      'command-execution',
    ],
    BottomSurfaceTab.agent => const <String>[
      'agent-activity',
      'coding-session-history',
    ],
    BottomSurfaceTab.sourceControl => const <String>[
      'source-control',
      'diff-preview',
    ],
    BottomSurfaceTab.search => const <String>[
      'workspace-search',
      'replace-preview',
    ],
    BottomSurfaceTab.problems => const <String>['diagnostics', 'quick-fix'],
    BottomSurfaceTab.testing => const <String>[
      'test-results',
      'failed-test-debug',
    ],
    BottomSurfaceTab.extensions => const <String>[
      'extension-management',
      'marketplace',
    ],
    BottomSurfaceTab.debug => const <String>['debug-console', 'debug-session'],
    BottomSurfaceTab.navigate => const <String>[
      'quick-navigate',
      'fuzzy-file-search',
    ],
    BottomSurfaceTab.settings => const <String>[
      'settings',
      'toolchain-configuration',
    ],
    BottomSurfaceTab.locations => const <String>[
      'recent-locations',
      'location-history',
    ],
    _ => const <String>[],
  };
}

String _bottomTabPanelTodo(BottomSurfaceTab tab) {
  return switch (tab) {
    BottomSurfaceTab.search =>
      'TODO: add production-scale virtualized search result rendering.',
    BottomSurfaceTab.problems =>
      'TODO: add virtualized multi-file diagnostics diff expansion.',
    BottomSurfaceTab.settings =>
      'TODO: bind all recovery and credential configuration routes.',
    BottomSurfaceTab.extensions =>
      'TODO: render marketplace IO progress and lifecycle policy persistence.',
    BottomSurfaceTab.debug =>
      'TODO: expose launch configuration editing and adapter process controls.',
    BottomSurfaceTab.agent =>
      'TODO: add long-running coding session timeline virtualization.',
    _ => '',
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
