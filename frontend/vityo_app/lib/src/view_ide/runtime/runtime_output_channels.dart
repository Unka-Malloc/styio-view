import 'dart:async';

enum RuntimeOutputChannelKind {
  runtimeEvents,
  stdout,
  stderr,
  nativeTools,
  agent,
  languageService,
  debug,
}

extension RuntimeOutputChannelKindX on RuntimeOutputChannelKind {
  String get wireValue {
    return switch (this) {
      RuntimeOutputChannelKind.runtimeEvents => 'runtime-events',
      RuntimeOutputChannelKind.stdout => 'stdout',
      RuntimeOutputChannelKind.stderr => 'stderr',
      RuntimeOutputChannelKind.nativeTools => 'native-tools',
      RuntimeOutputChannelKind.agent => 'agent',
      RuntimeOutputChannelKind.languageService => 'language-service',
      RuntimeOutputChannelKind.debug => 'debug',
    };
  }
}

enum RuntimeOutputSubscriptionStatus { pending, active, blocked }

extension RuntimeOutputSubscriptionStatusX on RuntimeOutputSubscriptionStatus {
  String get wireValue {
    return switch (this) {
      RuntimeOutputSubscriptionStatus.pending => 'pending',
      RuntimeOutputSubscriptionStatus.active => 'active',
      RuntimeOutputSubscriptionStatus.blocked => 'blocked',
    };
  }
}

enum RuntimeOutputProducerKind {
  shellManager,
  terminalRuntime,
  toolchainManager,
  hostedExecutor,
  languageService,
  debugAdapter,
  agent,
}

extension RuntimeOutputProducerKindX on RuntimeOutputProducerKind {
  String get wireValue => switch (this) {
    RuntimeOutputProducerKind.shellManager => 'shell-manager',
    RuntimeOutputProducerKind.terminalRuntime => 'terminal-runtime',
    RuntimeOutputProducerKind.toolchainManager => 'toolchain-manager',
    RuntimeOutputProducerKind.hostedExecutor => 'hosted-executor',
    RuntimeOutputProducerKind.languageService => 'language-service',
    RuntimeOutputProducerKind.debugAdapter => 'debug-adapter',
    RuntimeOutputProducerKind.agent => 'agent',
  };
}

class RuntimeOutputChannelSummary {
  const RuntimeOutputChannelSummary({
    required this.id,
    required this.label,
    required this.kind,
    required this.eventCount,
    required this.latestMessage,
  });

  final String id;
  final String label;
  final RuntimeOutputChannelKind kind;
  final int eventCount;
  final String latestMessage;

  bool get hasOutput => eventCount > 0;

  factory RuntimeOutputChannelSummary.fromJson(Map<String, Object?> json) {
    return RuntimeOutputChannelSummary(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      kind:
          _runtimeOutputChannelKindFromWireValue(
            json['kind'] as String? ?? '',
          ) ??
          RuntimeOutputChannelKind.runtimeEvents,
      eventCount: json['eventCount'] as int? ?? 0,
      latestMessage: json['latestMessage'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'kind': kind.wireValue,
      'eventCount': eventCount,
      'hasOutput': hasOutput,
      'latestMessage': latestMessage,
    };
  }
}

class RuntimeOutputProducerDescriptor {
  const RuntimeOutputProducerDescriptor({
    required this.producerId,
    required this.label,
    required this.kind,
    required this.managerId,
    required this.routeKind,
    this.channelIds = const <String>[],
    this.outputKinds = const <RuntimeOutputChannelKind>[],
    this.active = true,
    this.metadata = const <String, Object?>{},
    this.todo = '',
  });

  final String producerId;
  final String label;
  final RuntimeOutputProducerKind kind;
  final String managerId;
  final String routeKind;
  final List<String> channelIds;
  final List<RuntimeOutputChannelKind> outputKinds;
  final bool active;
  final Map<String, Object?> metadata;
  final String todo;

  RuntimeOutputStreamSubscriptionPlan createSubscriptionPlan({
    required String taskId,
    String? outputChannelId,
    RuntimeOutputRetentionPolicy retentionPolicy =
        const RuntimeOutputRetentionPolicy.workspaceHistory(),
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeOutputStreamSubscriptionPlan.forManager(
      taskId: taskId,
      managerId: managerId,
      routeKind: routeKind,
      channelIds: outputChannelId == null
          ? channelIds
          : <String>[outputChannelId],
      kinds: outputKinds,
      status: active
          ? RuntimeOutputSubscriptionStatus.active
          : RuntimeOutputSubscriptionStatus.blocked,
      retentionPolicy: retentionPolicy,
      metadata: <String, Object?>{
        'producerId': producerId,
        'producerKind': kind.wireValue,
        ...this.metadata,
        ...metadata,
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'producerId': producerId,
      'label': label,
      'kind': kind.wireValue,
      'managerId': managerId,
      'routeKind': routeKind,
      'channelIds': channelIds,
      'outputKinds': outputKinds
          .map((kind) => kind.wireValue)
          .toList(growable: false),
      'active': active,
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class RuntimeOutputProducerRegistry {
  RuntimeOutputProducerRegistry({
    Iterable<RuntimeOutputProducerDescriptor> producers =
        const <RuntimeOutputProducerDescriptor>[],
  }) : _producers = <String, RuntimeOutputProducerDescriptor>{
         for (final producer in producers) producer.producerId: producer,
       };

  factory RuntimeOutputProducerRegistry.defaultProducers() {
    return RuntimeOutputProducerRegistry(
      producers: const <RuntimeOutputProducerDescriptor>[
        RuntimeOutputProducerDescriptor(
          producerId: 'shell-manager',
          label: 'Shell Manager',
          kind: RuntimeOutputProducerKind.shellManager,
          managerId: 'shell-manager',
          routeKind: 'shell-task',
          channelIds: <String>['runtime.shell'],
          outputKinds: <RuntimeOutputChannelKind>[
            RuntimeOutputChannelKind.stdout,
            RuntimeOutputChannelKind.stderr,
          ],
          todo: 'TODO: bind this producer to concrete ShellManager streams.',
        ),
        RuntimeOutputProducerDescriptor(
          producerId: 'terminal-runtime',
          label: 'Terminal Runtime',
          kind: RuntimeOutputProducerKind.terminalRuntime,
          managerId: 'terminal-runtime',
          routeKind: 'terminal-task',
          channelIds: <String>['runtime.terminal'],
          outputKinds: <RuntimeOutputChannelKind>[
            RuntimeOutputChannelKind.runtimeEvents,
          ],
          todo: 'TODO: bind this producer to concrete PTY terminal streams.',
        ),
        RuntimeOutputProducerDescriptor(
          producerId: 'toolchain-manager',
          label: 'Toolchain Manager',
          kind: RuntimeOutputProducerKind.toolchainManager,
          managerId: 'toolchain-manager',
          routeKind: 'toolchain-task',
          channelIds: <String>['runtime.toolchain'],
          outputKinds: <RuntimeOutputChannelKind>[
            RuntimeOutputChannelKind.nativeTools,
          ],
          todo: 'TODO: bind this producer to concrete toolchain process IO.',
        ),
        RuntimeOutputProducerDescriptor(
          producerId: 'hosted-executor',
          label: 'Hosted Executor',
          kind: RuntimeOutputProducerKind.hostedExecutor,
          managerId: 'hosted-executor',
          routeKind: 'hosted-task',
          channelIds: <String>['runtime.hosted'],
          outputKinds: <RuntimeOutputChannelKind>[
            RuntimeOutputChannelKind.runtimeEvents,
          ],
          todo:
              'TODO: bind this producer to hosted backend event streams and retry telemetry.',
        ),
        RuntimeOutputProducerDescriptor(
          producerId: 'language-service',
          label: 'Language Service',
          kind: RuntimeOutputProducerKind.languageService,
          managerId: 'language-service',
          routeKind: 'language-service-task',
          channelIds: <String>['runtime.language-service'],
          outputKinds: <RuntimeOutputChannelKind>[
            RuntimeOutputChannelKind.languageService,
          ],
          todo:
              'TODO: bind this producer to StyioService diagnostics, semantic snapshot, and provider health streams.',
        ),
        RuntimeOutputProducerDescriptor(
          producerId: 'debug-adapter',
          label: 'Debug Adapter',
          kind: RuntimeOutputProducerKind.debugAdapter,
          managerId: 'debug-adapter',
          routeKind: 'debug-task',
          channelIds: <String>['runtime.debug'],
          outputKinds: <RuntimeOutputChannelKind>[
            RuntimeOutputChannelKind.debug,
          ],
          todo:
              'TODO: bind this producer to concrete DAP adapter lifecycle and debug console streams.',
        ),
        RuntimeOutputProducerDescriptor(
          producerId: 'agent',
          label: 'Agent Runtime',
          kind: RuntimeOutputProducerKind.agent,
          managerId: 'agent-runtime',
          routeKind: 'agent-task',
          channelIds: <String>['runtime.agent'],
          outputKinds: <RuntimeOutputChannelKind>[
            RuntimeOutputChannelKind.agent,
          ],
          todo:
              'TODO: bind this producer to coding-agent provider streams, recovery events, and patch application telemetry.',
        ),
      ],
    );
  }

  final Map<String, RuntimeOutputProducerDescriptor> _producers;

  List<RuntimeOutputProducerDescriptor> get producers {
    final values = _producers.values.toList(growable: false);
    values.sort((left, right) => left.producerId.compareTo(right.producerId));
    return values;
  }

  List<RuntimeOutputProducerDescriptor> get activeProducers {
    return producers
        .where((producer) => producer.active)
        .toList(growable: false);
  }

  RuntimeOutputProducerDescriptor? lookup(String producerId) {
    return _producers[producerId];
  }

  List<RuntimeOutputStreamSubscriptionPlan> subscriptionPlansForTask({
    required String taskId,
    RuntimeOutputRetentionPolicy retentionPolicy =
        const RuntimeOutputRetentionPolicy.workspaceHistory(),
  }) {
    return activeProducers
        .map(
          (producer) => producer.createSubscriptionPlan(
            taskId: taskId,
            retentionPolicy: retentionPolicy,
          ),
        )
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'producerCount': producers.length,
      'activeProducerCount': activeProducers.length,
      'producers': producers
          .map((producer) => producer.toJson())
          .toList(growable: false),
    };
  }
}

class RuntimeOutputProducerEmission {
  const RuntimeOutputProducerEmission({
    required this.message,
    required this.timestamp,
    this.channelId,
    this.label,
    this.kind,
    this.metadata = const <String, Object?>{},
  });

  const RuntimeOutputProducerEmission.stdout({
    required String message,
    required DateTime timestamp,
    String? channelId,
    String? label,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         message: message,
         timestamp: timestamp,
         channelId: channelId,
         label: label,
         kind: RuntimeOutputChannelKind.stdout,
         metadata: metadata,
       );

  const RuntimeOutputProducerEmission.stderr({
    required String message,
    required DateTime timestamp,
    String? channelId,
    String? label,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         message: message,
         timestamp: timestamp,
         channelId: channelId,
         label: label,
         kind: RuntimeOutputChannelKind.stderr,
         metadata: metadata,
       );

  const RuntimeOutputProducerEmission.nativeTool({
    required String message,
    required DateTime timestamp,
    String? channelId,
    String? label,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         message: message,
         timestamp: timestamp,
         channelId: channelId,
         label: label,
         kind: RuntimeOutputChannelKind.nativeTools,
         metadata: metadata,
       );

  const RuntimeOutputProducerEmission.runtimeEvent({
    required String message,
    required DateTime timestamp,
    String? channelId,
    String? label,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         message: message,
         timestamp: timestamp,
         channelId: channelId,
         label: label,
         kind: RuntimeOutputChannelKind.runtimeEvents,
         metadata: metadata,
       );

  final String message;
  final DateTime timestamp;
  final String? channelId;
  final String? label;
  final RuntimeOutputChannelKind? kind;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      if (channelId != null) 'channelId': channelId,
      if (label != null) 'label': label,
      if (kind != null) 'kind': kind!.wireValue,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class RuntimeOutputProducerAdapter {
  const RuntimeOutputProducerAdapter({
    required this.descriptor,
    required this.defaultChannelId,
    required this.defaultLabel,
    required this.defaultKind,
  });

  factory RuntimeOutputProducerAdapter.forDescriptor(
    RuntimeOutputProducerDescriptor descriptor,
  ) {
    final defaultChannelId = descriptor.channelIds.isEmpty
        ? descriptor.producerId
        : descriptor.channelIds.first;
    final defaultKind = descriptor.outputKinds.isEmpty
        ? RuntimeOutputChannelKind.runtimeEvents
        : descriptor.outputKinds.first;
    return RuntimeOutputProducerAdapter(
      descriptor: descriptor,
      defaultChannelId: defaultChannelId,
      defaultLabel: descriptor.label,
      defaultKind: defaultKind,
    );
  }

  final RuntimeOutputProducerDescriptor descriptor;
  final String defaultChannelId;
  final String defaultLabel;
  final RuntimeOutputChannelKind defaultKind;

  RuntimeOutputEvent event(RuntimeOutputProducerEmission emission) {
    return RuntimeOutputEvent(
      channelId: emission.channelId ?? defaultChannelId,
      label: emission.label ?? defaultLabel,
      kind: emission.kind ?? defaultKind,
      message: emission.message,
      timestamp: emission.timestamp.toUtc(),
      metadata: <String, Object?>{
        'producerId': descriptor.producerId,
        'producerKind': descriptor.kind.wireValue,
        'managerId': descriptor.managerId,
        'routeKind': descriptor.routeKind,
        ...descriptor.metadata,
        ...emission.metadata,
      },
    );
  }

  StreamSubscription<RuntimeOutputProducerEmission> bind(
    Stream<RuntimeOutputProducerEmission> emissions,
    RuntimeOutputLiveBuffer buffer,
  ) {
    return emissions.listen((emission) {
      buffer.addEvent(event(emission));
    });
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'producer': descriptor.toJson(),
      'defaultChannelId': defaultChannelId,
      'defaultLabel': defaultLabel,
      'defaultKind': defaultKind.wireValue,
    };
  }
}

class RuntimeOutputProducerAdapterRegistry {
  RuntimeOutputProducerAdapterRegistry({
    Iterable<RuntimeOutputProducerAdapter> adapters =
        const <RuntimeOutputProducerAdapter>[],
  }) : _adapters = <String, RuntimeOutputProducerAdapter>{
         for (final adapter in adapters) adapter.descriptor.producerId: adapter,
       };

  factory RuntimeOutputProducerAdapterRegistry.fromProducerRegistry(
    RuntimeOutputProducerRegistry registry,
  ) {
    return RuntimeOutputProducerAdapterRegistry(
      adapters: registry.producers.map(
        RuntimeOutputProducerAdapter.forDescriptor,
      ),
    );
  }

  factory RuntimeOutputProducerAdapterRegistry.defaultAdapters() {
    return RuntimeOutputProducerAdapterRegistry.fromProducerRegistry(
      RuntimeOutputProducerRegistry.defaultProducers(),
    );
  }

  final Map<String, RuntimeOutputProducerAdapter> _adapters;

  List<RuntimeOutputProducerAdapter> get adapters {
    final values = _adapters.values.toList(growable: false);
    values.sort(
      (left, right) =>
          left.descriptor.producerId.compareTo(right.descriptor.producerId),
    );
    return values;
  }

  RuntimeOutputProducerAdapter? lookup(String producerId) {
    return _adapters[producerId];
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'adapterCount': adapters.length,
      'adapters': adapters.map((adapter) => adapter.toJson()).toList(),
    };
  }
}

class RuntimeOutputProducerBindingState {
  const RuntimeOutputProducerBindingState({
    required this.producerId,
    required this.status,
    this.managerId = '',
    this.routeKind = '',
    this.defaultChannelId = '',
    this.message = '',
    this.todo = '',
  });

  final String producerId;
  final RuntimeOutputSubscriptionStatus status;
  final String managerId;
  final String routeKind;
  final String defaultChannelId;
  final String message;
  final String todo;

  bool get active => status == RuntimeOutputSubscriptionStatus.active;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'producerId': producerId,
      'status': status.wireValue,
      if (managerId.isNotEmpty) 'managerId': managerId,
      if (routeKind.isNotEmpty) 'routeKind': routeKind,
      if (defaultChannelId.isNotEmpty) 'defaultChannelId': defaultChannelId,
      if (message.isNotEmpty) 'message': message,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class RuntimeOutputProducerBindingController {
  RuntimeOutputProducerBindingController({
    required RuntimeOutputProducerAdapterRegistry adapters,
    required RuntimeOutputLiveBuffer buffer,
  }) : _adapters = adapters,
       _buffer = buffer;

  final RuntimeOutputProducerAdapterRegistry _adapters;
  final RuntimeOutputLiveBuffer _buffer;
  final Map<String, StreamSubscription<RuntimeOutputProducerEmission>>
  _subscriptions =
      <String, StreamSubscription<RuntimeOutputProducerEmission>>{};
  final Map<String, RuntimeOutputProducerBindingState> _states =
      <String, RuntimeOutputProducerBindingState>{};

  List<RuntimeOutputProducerBindingState> get bindings {
    final values = _states.values.toList(growable: false);
    values.sort((left, right) => left.producerId.compareTo(right.producerId));
    return values;
  }

  bool get hasActiveBindings {
    return bindings.any((binding) => binding.active);
  }

  RuntimeOutputProducerBindingState? lookup(String producerId) {
    return _states[producerId];
  }

  RuntimeOutputProducerBindingState bindProducer({
    required String producerId,
    required Stream<RuntimeOutputProducerEmission> emissions,
  }) {
    final adapter = _adapters.lookup(producerId);
    if (adapter == null) {
      final blocked = RuntimeOutputProducerBindingState(
        producerId: producerId,
        status: RuntimeOutputSubscriptionStatus.blocked,
        message: 'No RuntimeOutputProducerAdapter registered.',
        todo:
            'TODO: register this producer before wiring concrete manager streams.',
      );
      _states[producerId] = blocked;
      return blocked;
    }

    final previousSubscription = _subscriptions.remove(producerId);
    previousSubscription?.cancel();
    _subscriptions[producerId] = adapter.bind(emissions, _buffer);
    final active = RuntimeOutputProducerBindingState(
      producerId: producerId,
      status: RuntimeOutputSubscriptionStatus.active,
      managerId: adapter.descriptor.managerId,
      routeKind: adapter.descriptor.routeKind,
      defaultChannelId: adapter.defaultChannelId,
      message: 'Runtime output producer stream bound.',
      todo: adapter.descriptor.todo,
    );
    _states[producerId] = active;
    return active;
  }

  Future<bool> unbindProducer(String producerId) async {
    final subscription = _subscriptions.remove(producerId);
    if (subscription == null) {
      return false;
    }
    await subscription.cancel();
    final existing = _states[producerId];
    _states[producerId] = RuntimeOutputProducerBindingState(
      producerId: producerId,
      status: RuntimeOutputSubscriptionStatus.pending,
      managerId: existing?.managerId ?? '',
      routeKind: existing?.routeKind ?? '',
      defaultChannelId: existing?.defaultChannelId ?? '',
      message: 'Runtime output producer stream detached.',
      todo:
          existing?.todo ??
          'TODO: reconnect this producer when the manager stream restarts.',
    );
    return true;
  }

  Future<void> dispose() async {
    final subscriptions = _subscriptions.values.toList(growable: false);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'bindingCount': bindings.length,
      'activeBindingCount': bindings.where((binding) => binding.active).length,
      'bindings': bindings
          .map((binding) => binding.toJson())
          .toList(growable: false),
    };
  }
}

class RuntimeOutputChannelFilterState {
  const RuntimeOutputChannelFilterState({
    this.channelIds = const <String>[],
    this.kinds = const <RuntimeOutputChannelKind>[],
    this.includeEmpty = false,
  });

  final List<String> channelIds;
  final List<RuntimeOutputChannelKind> kinds;
  final bool includeEmpty;

  bool get active {
    return channelIds.isNotEmpty || kinds.isNotEmpty || includeEmpty;
  }

  String get summary {
    final parts = <String>[
      if (channelIds.isNotEmpty) 'channels ${channelIds.join(',')}',
      if (kinds.isNotEmpty)
        'kinds ${kinds.map((kind) => kind.wireValue).join(',')}',
      if (includeEmpty) 'include-empty',
    ];
    return parts.join(' · ');
  }

  bool matches(RuntimeOutputChannelSummary channel) {
    if (!includeEmpty && !channel.hasOutput) {
      return false;
    }
    if (channelIds.isNotEmpty && !channelIds.contains(channel.id)) {
      return false;
    }
    if (kinds.isNotEmpty && !kinds.contains(channel.kind)) {
      return false;
    }
    return true;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'channelIds': channelIds,
      'kinds': kinds.map((kind) => kind.wireValue).toList(),
      'includeEmpty': includeEmpty,
      'active': active,
      if (summary.isNotEmpty) 'summary': summary,
    };
  }

  factory RuntimeOutputChannelFilterState.fromJson(Map<String, Object?> json) {
    final channelIds = json['channelIds'];
    final kinds = json['kinds'];
    return RuntimeOutputChannelFilterState(
      channelIds: channelIds is List
          ? channelIds.map((id) => '$id').toList(growable: false)
          : const <String>[],
      kinds: kinds is List
          ? kinds
                .map((kind) => _runtimeOutputChannelKindFromWireValue('$kind'))
                .whereType<RuntimeOutputChannelKind>()
                .toList(growable: false)
          : const <RuntimeOutputChannelKind>[],
      includeEmpty: json['includeEmpty'] as bool? ?? false,
    );
  }
}

class RuntimeOutputRetentionPolicy {
  const RuntimeOutputRetentionPolicy({
    required this.maxEventsPerChannel,
    required this.persistHistory,
    required this.trimEmptyChannels,
    this.maxEventAge,
  });

  const RuntimeOutputRetentionPolicy.ephemeral({this.maxEventsPerChannel = 500})
    : persistHistory = false,
      trimEmptyChannels = true,
      maxEventAge = null;

  const RuntimeOutputRetentionPolicy.workspaceHistory({
    this.maxEventsPerChannel = 2000,
    this.maxEventAge = const Duration(days: 7),
  }) : persistHistory = true,
       trimEmptyChannels = false;

  final int maxEventsPerChannel;
  final Duration? maxEventAge;
  final bool persistHistory;
  final bool trimEmptyChannels;

  bool get bounded => maxEventsPerChannel > 0 || maxEventAge != null;

  String get summary {
    final parts = <String>[
      if (maxEventsPerChannel > 0)
        'retain last $maxEventsPerChannel event(s) per channel'
      else
        'retain all events',
      if (maxEventAge != null) 'max age ${maxEventAge!.inHours}h',
      persistHistory ? 'persisted history' : 'memory only',
      trimEmptyChannels ? 'trim empty channels' : 'keep empty channels',
    ];
    return parts.join(' · ');
  }

  factory RuntimeOutputRetentionPolicy.fromJson(Map<String, Object?> json) {
    final maxEventAgeMs = json['maxEventAgeMs'];
    return RuntimeOutputRetentionPolicy(
      maxEventsPerChannel: json['maxEventsPerChannel'] as int? ?? 0,
      maxEventAge: maxEventAgeMs is int
          ? Duration(milliseconds: maxEventAgeMs)
          : null,
      persistHistory: json['persistHistory'] as bool? ?? false,
      trimEmptyChannels: json['trimEmptyChannels'] as bool? ?? true,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'maxEventsPerChannel': maxEventsPerChannel,
      if (maxEventAge != null) 'maxEventAgeMs': maxEventAge!.inMilliseconds,
      'persistHistory': persistHistory,
      'trimEmptyChannels': trimEmptyChannels,
      'bounded': bounded,
      'summary': summary,
    };
  }
}

class RuntimeOutputStreamSubscriptionPlan {
  const RuntimeOutputStreamSubscriptionPlan({
    required this.taskId,
    required this.managerId,
    required this.routeKind,
    required this.channelIds,
    required this.kinds,
    this.status = RuntimeOutputSubscriptionStatus.pending,
    this.retentionPolicy =
        const RuntimeOutputRetentionPolicy.workspaceHistory(),
    this.metadata = const <String, Object?>{},
  });

  factory RuntimeOutputStreamSubscriptionPlan.forManager({
    required String taskId,
    required String managerId,
    required String routeKind,
    Iterable<String> channelIds = const <String>[],
    Iterable<RuntimeOutputChannelKind> kinds =
        const <RuntimeOutputChannelKind>[],
    RuntimeOutputSubscriptionStatus status =
        RuntimeOutputSubscriptionStatus.pending,
    RuntimeOutputRetentionPolicy retentionPolicy =
        const RuntimeOutputRetentionPolicy.workspaceHistory(),
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeOutputStreamSubscriptionPlan(
      taskId: taskId,
      managerId: managerId,
      routeKind: routeKind,
      channelIds: _uniqueStrings(channelIds),
      kinds: _uniqueKinds(kinds),
      status: status,
      retentionPolicy: retentionPolicy,
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  final String taskId;
  final String managerId;
  final String routeKind;
  final List<String> channelIds;
  final List<RuntimeOutputChannelKind> kinds;
  final RuntimeOutputSubscriptionStatus status;
  final RuntimeOutputRetentionPolicy retentionPolicy;
  final Map<String, Object?> metadata;

  bool get active => status == RuntimeOutputSubscriptionStatus.active;

  String get summary {
    final channelSummary = channelIds.isEmpty
        ? 'all channels'
        : channelIds.join('/');
    final kindSummary = kinds.isEmpty
        ? 'all kinds'
        : kinds.map((kind) => kind.wireValue).join('/');
    return '$managerId -> $routeKind · $channelSummary · $kindSummary · ${retentionPolicy.summary}';
  }

  bool accepts(RuntimeOutputEvent event) {
    if (channelIds.isNotEmpty && !channelIds.contains(event.channelId)) {
      return false;
    }
    if (kinds.isNotEmpty && !kinds.contains(event.kind)) {
      return false;
    }
    return true;
  }

  List<RuntimeOutputEvent> retain(
    Iterable<RuntimeOutputEvent> events, {
    DateTime? now,
  }) {
    final cutoff = retentionPolicy.maxEventAge == null || now == null
        ? null
        : now.subtract(retentionPolicy.maxEventAge!);
    final grouped = <String, List<RuntimeOutputEvent>>{};
    for (final event in events) {
      if (!accepts(event)) {
        continue;
      }
      if (cutoff != null && event.timestamp.isBefore(cutoff)) {
        continue;
      }
      grouped.putIfAbsent(event.channelId, () => <RuntimeOutputEvent>[]);
      grouped[event.channelId]!.add(event);
    }
    final retained = <RuntimeOutputEvent>[];
    for (final channelEvents in grouped.values) {
      channelEvents.sort(
        (left, right) => left.timestamp.compareTo(right.timestamp),
      );
      if (retentionPolicy.maxEventsPerChannel > 0 &&
          channelEvents.length > retentionPolicy.maxEventsPerChannel) {
        retained.addAll(
          channelEvents.sublist(
            channelEvents.length - retentionPolicy.maxEventsPerChannel,
          ),
        );
      } else {
        retained.addAll(channelEvents);
      }
    }
    retained.sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return retained;
  }

  RuntimeOutputStreamSubscriptionPlan activate() {
    return copyWith(status: RuntimeOutputSubscriptionStatus.active);
  }

  RuntimeOutputStreamSubscriptionPlan copyWith({
    RuntimeOutputSubscriptionStatus? status,
    RuntimeOutputRetentionPolicy? retentionPolicy,
    Map<String, Object?>? metadata,
  }) {
    return RuntimeOutputStreamSubscriptionPlan(
      taskId: taskId,
      managerId: managerId,
      routeKind: routeKind,
      channelIds: channelIds,
      kinds: kinds,
      status: status ?? this.status,
      retentionPolicy: retentionPolicy ?? this.retentionPolicy,
      metadata: metadata ?? this.metadata,
    );
  }

  factory RuntimeOutputStreamSubscriptionPlan.fromJson(
    Map<String, Object?> json,
  ) {
    final channelIds = json['channelIds'];
    final kinds = json['kinds'];
    final retentionPolicy = json['retentionPolicy'];
    return RuntimeOutputStreamSubscriptionPlan.forManager(
      taskId: json['taskId'] as String? ?? '',
      managerId: json['managerId'] as String? ?? '',
      routeKind: json['routeKind'] as String? ?? '',
      channelIds: channelIds is List
          ? channelIds.map((channelId) => '$channelId')
          : const <String>[],
      kinds: kinds is List
          ? kinds
                .map((kind) => _runtimeOutputChannelKindFromWireValue('$kind'))
                .whereType<RuntimeOutputChannelKind>()
          : const <RuntimeOutputChannelKind>[],
      status:
          _runtimeOutputSubscriptionStatusFromWireValue(
            json['status'] as String? ?? '',
          ) ??
          RuntimeOutputSubscriptionStatus.pending,
      retentionPolicy: retentionPolicy is Map
          ? RuntimeOutputRetentionPolicy.fromJson(
              retentionPolicy.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : const RuntimeOutputRetentionPolicy.workspaceHistory(),
      metadata: json['metadata'] is Map
          ? (json['metadata']! as Map).map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            )
          : const <String, Object?>{},
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'taskId': taskId,
      'managerId': managerId,
      'routeKind': routeKind,
      'status': status.wireValue,
      'active': active,
      'channelIds': channelIds,
      'kinds': kinds.map((kind) => kind.wireValue).toList(growable: false),
      'retentionPolicy': retentionPolicy.toJson(),
      'summary': summary,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class RuntimeOutputEvent {
  const RuntimeOutputEvent({
    required this.channelId,
    required this.label,
    required this.kind,
    required this.message,
    required this.timestamp,
    this.metadata = const <String, Object?>{},
  });

  final String channelId;
  final String label;
  final RuntimeOutputChannelKind kind;
  final String message;
  final DateTime timestamp;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'channelId': channelId,
      'label': label,
      'kind': kind.wireValue,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class RuntimeOutputChannelSnapshot {
  const RuntimeOutputChannelSnapshot({
    required this.channels,
    this.filter = const RuntimeOutputChannelFilterState(),
  });

  final List<RuntimeOutputChannelSummary> channels;
  final RuntimeOutputChannelFilterState filter;

  factory RuntimeOutputChannelSnapshot.fromJson(Map<String, Object?> json) {
    final channels = json['channels'];
    final filter = json['filter'];
    return RuntimeOutputChannelSnapshot(
      channels: channels is List
          ? channels
                .whereType<Map>()
                .map(
                  (channel) => RuntimeOutputChannelSummary.fromJson(
                    channel.map(
                      (key, value) =>
                          MapEntry<String, Object?>(key.toString(), value),
                    ),
                  ),
                )
                .toList(growable: false)
          : const <RuntimeOutputChannelSummary>[],
      filter: filter is Map
          ? RuntimeOutputChannelFilterState.fromJson(
              filter.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : const RuntimeOutputChannelFilterState(),
    );
  }

  List<RuntimeOutputChannelSummary> get visibleChannels {
    return channels.where(filter.matches).toList(growable: false);
  }

  int get totalEventCount {
    return channels.fold<int>(
      0,
      (total, channel) => total + channel.eventCount,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'filter': filter.toJson(),
      'channelCount': channels.length,
      'visibleChannelCount': visibleChannels.length,
      'totalEventCount': totalEventCount,
      'channels': visibleChannels
          .map((channel) => channel.toJson())
          .toList(growable: false),
    };
  }
}

class RuntimeOutputPanelSnapshot {
  const RuntimeOutputPanelSnapshot({
    required this.events,
    this.filter = const RuntimeOutputChannelFilterState(),
    this.subscriptionPlan,
  });

  final List<RuntimeOutputEvent> events;
  final RuntimeOutputChannelFilterState filter;
  final RuntimeOutputStreamSubscriptionPlan? subscriptionPlan;

  List<RuntimeOutputEvent> get retainedEvents {
    return subscriptionPlan?.retain(events) ?? events;
  }

  RuntimeOutputChannelSnapshot get channelSnapshot {
    final grouped = <String, List<RuntimeOutputEvent>>{};
    for (final event in retainedEvents) {
      grouped.putIfAbsent(event.channelId, () => <RuntimeOutputEvent>[]);
      grouped[event.channelId]!.add(event);
    }
    final channels = grouped.entries
        .map((entry) {
          final channelEvents = entry.value;
          final latest = channelEvents.last;
          return RuntimeOutputChannelSummary(
            id: latest.channelId,
            label: latest.label,
            kind: latest.kind,
            eventCount: channelEvents.length,
            latestMessage: latest.message,
          );
        })
        .toList(growable: false);
    channels.sort((left, right) => left.id.compareTo(right.id));
    return RuntimeOutputChannelSnapshot(channels: channels, filter: filter);
  }

  List<RuntimeOutputEvent> get visibleEvents {
    final visibleChannelIds = channelSnapshot.visibleChannels
        .map((channel) => channel.id)
        .toSet();
    return retainedEvents
        .where((event) => visibleChannelIds.contains(event.channelId))
        .toList(growable: false);
  }

  Map<String, int> get eventCountsByKind {
    return <String, int>{
      for (final kind in RuntimeOutputChannelKind.values)
        kind.wireValue: events.where((event) => event.kind == kind).length,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'channelSnapshot': channelSnapshot.toJson(),
      'sourceEventCount': events.length,
      'eventCount': retainedEvents.length,
      'visibleEventCount': visibleEvents.length,
      'eventCountsByKind': eventCountsByKind,
      if (subscriptionPlan != null)
        'subscriptionPlan': subscriptionPlan!.toJson(),
      'events': visibleEvents
          .map((event) => event.toJson())
          .toList(growable: false),
    };
  }
}

class RuntimeOutputLiveBuffer {
  RuntimeOutputLiveBuffer({
    Iterable<RuntimeOutputEvent> seedEvents = const <RuntimeOutputEvent>[],
    this.filter = const RuntimeOutputChannelFilterState(),
    this.subscriptionPlan,
  }) : _events = <RuntimeOutputEvent>[] {
    _events.addAll(subscriptionPlan?.retain(seedEvents) ?? seedEvents);
  }

  final List<RuntimeOutputEvent> _events;
  final StreamController<RuntimeOutputPanelSnapshot> _snapshots =
      StreamController<RuntimeOutputPanelSnapshot>.broadcast(sync: true);

  RuntimeOutputChannelFilterState filter;
  RuntimeOutputStreamSubscriptionPlan? subscriptionPlan;
  var _closed = false;

  Stream<RuntimeOutputPanelSnapshot> get snapshots => _snapshots.stream;

  RuntimeOutputPanelSnapshot get snapshot {
    return RuntimeOutputPanelSnapshot(
      events: List<RuntimeOutputEvent>.unmodifiable(_events),
      filter: filter,
      subscriptionPlan: subscriptionPlan,
    );
  }

  void addEvent(RuntimeOutputEvent event, {DateTime? now}) {
    if (subscriptionPlan != null && !subscriptionPlan!.accepts(event)) {
      return;
    }
    _events.add(event);
    _compact(now: now ?? event.timestamp);
    _publish();
  }

  StreamSubscription<RuntimeOutputEvent> bind(
    Stream<RuntimeOutputEvent> events, {
    DateTime Function(RuntimeOutputEvent event)? now,
  }) {
    return events.listen((event) {
      addEvent(event, now: now?.call(event));
    });
  }

  void updateFilter(RuntimeOutputChannelFilterState nextFilter) {
    filter = nextFilter;
    _publish();
  }

  void updateSubscriptionPlan(
    RuntimeOutputStreamSubscriptionPlan? nextPlan, {
    DateTime? now,
  }) {
    subscriptionPlan = nextPlan;
    _compact(now: now);
    _publish();
  }

  void clear() {
    _events.clear();
    _publish();
  }

  Future<void> dispose() async {
    _closed = true;
    await _snapshots.close();
  }

  void _compact({DateTime? now}) {
    final plan = subscriptionPlan;
    if (plan == null) {
      _events.sort((left, right) => left.timestamp.compareTo(right.timestamp));
      return;
    }
    final retained = plan.retain(_events, now: now);
    _events
      ..clear()
      ..addAll(retained);
  }

  void _publish() {
    if (_closed) {
      return;
    }
    _snapshots.add(snapshot);
  }
}

RuntimeOutputChannelKind? _runtimeOutputChannelKindFromWireValue(String value) {
  for (final kind in RuntimeOutputChannelKind.values) {
    if (kind.wireValue == value) {
      return kind;
    }
  }
  return null;
}

RuntimeOutputSubscriptionStatus? _runtimeOutputSubscriptionStatusFromWireValue(
  String value,
) {
  for (final status in RuntimeOutputSubscriptionStatus.values) {
    if (status.wireValue == value) {
      return status;
    }
  }
  return null;
}

List<String> _uniqueStrings(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    if (value.isEmpty || result.contains(value)) {
      continue;
    }
    result.add(value);
  }
  return List<String>.unmodifiable(result);
}

List<RuntimeOutputChannelKind> _uniqueKinds(
  Iterable<RuntimeOutputChannelKind> values,
) {
  final result = <RuntimeOutputChannelKind>[];
  for (final value in values) {
    if (result.contains(value)) {
      continue;
    }
    result.add(value);
  }
  return List<RuntimeOutputChannelKind>.unmodifiable(result);
}
