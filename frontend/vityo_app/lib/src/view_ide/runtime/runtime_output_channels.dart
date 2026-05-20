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
  });

  final List<RuntimeOutputEvent> events;
  final RuntimeOutputChannelFilterState filter;

  RuntimeOutputChannelSnapshot get channelSnapshot {
    final grouped = <String, List<RuntimeOutputEvent>>{};
    for (final event in events) {
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
    return events
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
      'eventCount': events.length,
      'visibleEventCount': visibleEvents.length,
      'eventCountsByKind': eventCountsByKind,
      'events': visibleEvents
          .map((event) => event.toJson())
          .toList(growable: false),
    };
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
