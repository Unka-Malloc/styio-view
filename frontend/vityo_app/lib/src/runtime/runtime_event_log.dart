import '../backend_toolchain/execution_adapter.dart';
import 'runtime_replay_summary.dart';

/// An append-only log of [RuntimeEventEnvelope] values.
///
/// Supports filtered queries with pagination and derives replay / graph
/// summaries from a tail window of events.
class AppendOnlyEventLog {
  final List<RuntimeEventEnvelope> _events = <RuntimeEventEnvelope>[];

  /// Appends a single [event] to the log.
  void append(RuntimeEventEnvelope event) {
    _events.add(event);
  }

  /// Appends all [events] to the log.
  void appendAll(Iterable<RuntimeEventEnvelope> events) {
    _events.addAll(events);
  }

  /// Returns a filtered snapshot of the log.
  ///
  /// [sessionId] narrows to a specific session.
  /// [eventKind] narrows to a specific event kind string.
  /// [family] narrows to events whose [runtimeEventFamily] matches.
  /// [offset] skips that many results after filtering (default 0).
  /// [limit] caps the number of results returned.
  List<RuntimeEventEnvelope> query({
    String? sessionId,
    String? eventKind,
    String? family,
    int offset = 0,
    int? limit,
  }) {
    var results = _events.where((event) {
      if (sessionId != null && event.sessionId != sessionId) return false;
      if (eventKind != null && event.eventKind != eventKind) return false;
      if (family != null &&
          runtimeEventFamily(event.eventKind) != family) {
        return false;
      }
      return true;
    });

    var list = results.toList(growable: false);

    if (offset > 0) {
      if (offset >= list.length) return <RuntimeEventEnvelope>[];
      list = list.sublist(offset);
    }

    if (limit != null && limit < list.length) {
      list = list.sublist(0, limit);
    }

    return list;
  }

  /// Total number of events in the log.
  int get length => _events.length;

  /// An unmodifiable view of every event in the log.
  List<RuntimeEventEnvelope> get all => List<RuntimeEventEnvelope>.unmodifiable(_events);

  /// Derives a [RuntimeReplaySummary] from the tail [maxEvents] events
  /// (or all events when [maxEvents] is omitted).
  RuntimeReplaySummary replaySummary({int? maxEvents}) {
    final window = _tailWindow(maxEvents);
    return summarizeRuntimeReplay(window);
  }

  /// Derives a [RuntimeGraphSummary] from the tail [maxEvents] events
  /// (or all events when [maxEvents] is omitted).
  RuntimeGraphSummary graphSummary({int? maxEvents}) {
    final window = _tailWindow(maxEvents);
    return summarizeRuntimeGraph(window);
  }

  List<RuntimeEventEnvelope> _tailWindow(int? maxEvents) {
    if (maxEvents == null || maxEvents >= _events.length) {
      return _events;
    }
    return _events.sublist(_events.length - maxEvents);
  }
}

/// A generic bounded ring buffer (circular buffer) with a fixed [capacity].
///
/// When the buffer is full, adding a new item silently evicts the oldest item.
class RingBuffer<T> {
  final int capacity;
  final List<T?> _buffer;
  int _head = 0;
  int _length = 0;

  /// Creates a ring buffer that can hold at most [capacity] items.
  RingBuffer(this.capacity) : _buffer = List<T?>.filled(capacity, null);

  /// The number of items currently in the buffer.
  int get length => _length;

  /// Whether the buffer contains no items.
  bool get isEmpty => _length == 0;

  /// Whether the buffer has reached its maximum capacity.
  bool get isFull => _length == capacity;

  /// Adds [item] to the buffer, evicting the oldest item if the buffer is full.
  void add(T item) {
    if (isFull) {
      _buffer[_head] = item;
      _head = (_head + 1) % capacity;
    } else {
      final index = (_head + _length) % capacity;
      _buffer[index] = item;
      _length++;
    }
  }

  /// Accesses the item at logical [index] where 0 is the oldest item.
  /// Returns `null` when [index] is out of range.
  T? operator [](int index) {
    if (index < 0 || index >= _length) return null;
    return _buffer[(_head + index) % capacity];
  }

  /// Returns a snapshot of the buffer contents ordered oldest-first.
  List<T> toList() {
    final result = <T>[];
    for (var i = 0; i < _length; i++) {
      final item = _buffer[(_head + i) % capacity];
      // The internal slots at indices [0.._length) always hold non-null values.
      if (item != null) result.add(item);
    }
    return result;
  }

  /// Returns a snapshot of the buffer contents ordered newest-first.
  List<T> toReversedList() {
    final result = <T>[];
    for (var i = _length - 1; i >= 0; i--) {
      final item = _buffer[(_head + i) % capacity];
      if (item != null) result.add(item);
    }
    return result;
  }

  /// Removes all items from the buffer, resetting it to an empty state.
  void clear() {
    for (var i = 0; i < capacity; i++) {
      _buffer[i] = null;
    }
    _head = 0;
    _length = 0;
  }
}

/// A [RuntimeEventEnvelope]-specific ring buffer that also exposes replay and
/// graph summaries over its current contents.
class RuntimeEventRingBuffer {
  final RingBuffer<RuntimeEventEnvelope> _buffer;

  /// Creates a ring buffer with the given [capacity].
  RuntimeEventRingBuffer(int capacity) : _buffer = RingBuffer<RuntimeEventEnvelope>(capacity);

  /// The maximum number of events the buffer can hold.
  int get capacity => _buffer.capacity;

  /// The number of events currently in the buffer.
  int get length => _buffer.length;

  /// Whether the buffer contains no events.
  bool get isEmpty => _buffer.isEmpty;

  /// Whether the buffer has reached its maximum capacity.
  bool get isFull => _buffer.isFull;

  /// Adds [item] to the buffer, evicting the oldest event if full.
  void add(RuntimeEventEnvelope item) => _buffer.add(item);

  /// Accesses the event at logical [index] where 0 is the oldest.
  /// Returns `null` when [index] is out of range.
  RuntimeEventEnvelope? operator [](int index) => _buffer[index];

  /// Returns a snapshot of events ordered oldest-first.
  List<RuntimeEventEnvelope> toList() => _buffer.toList();

  /// Returns a snapshot of events ordered newest-first.
  List<RuntimeEventEnvelope> toReversedList() => _buffer.toReversedList();

  /// Removes all events from the buffer.
  void clear() => _buffer.clear();

  /// Derives a [RuntimeReplaySummary] from the current buffer contents.
  RuntimeReplaySummary replaySummary() {
    return summarizeRuntimeReplay(_buffer.toList());
  }

  /// Derives a [RuntimeGraphSummary] from the current buffer contents.
  RuntimeGraphSummary graphSummary() {
    return summarizeRuntimeGraph(_buffer.toList());
  }
}

/// A pure data class that holds the current event digest state and supports
/// incremental reduction via [reduce].
///
/// Internally stores all events that have been reduced so far and lazily
/// recomputes the graph summary when [summary] is first accessed after a new
/// event is added via [reduce].
class RuntimeGraphDigest {
  final int eventCount;
  final List<RuntimeEventEnvelope> _events;
  RuntimeGraphSummary? _cachedSummary;

  RuntimeGraphDigest._({
    required this.eventCount,
    required List<RuntimeEventEnvelope> events,
    RuntimeGraphSummary? cachedSummary,
  })  : _events = events,
        _cachedSummary = cachedSummary;

  /// The lazily-computed graph summary. Recomputes only when the cache is
  /// stale (i.e. after [reduce] has been called).
  RuntimeGraphSummary get summary {
    _cachedSummary ??= summarizeRuntimeGraph(_events);
    return _cachedSummary!;
  }

  /// Creates an empty digest with no events and a default empty summary.
  factory RuntimeGraphDigest.initial() {
    return RuntimeGraphDigest._(
      eventCount: 0,
      events: <RuntimeEventEnvelope>[],
      cachedSummary: null,
    );
  }

  /// Returns a new [RuntimeGraphDigest] with [event] appended.
  ///
  /// The returned digest invalidates the cached summary; it will be
  /// recomputed the next time [summary] is accessed.
  RuntimeGraphDigest reduce(RuntimeEventEnvelope event) {
    final updatedEvents = <RuntimeEventEnvelope>[..._events, event];
    return RuntimeGraphDigest._(
      eventCount: updatedEvents.length,
      events: updatedEvents,
      cachedSummary: null,
    );
  }
}

/// Pure function for incremental graph reduction.
///
/// Computes a new [RuntimeGraphSummary] from the full set of
/// [previousEvents] combined with [newEvent]. When [oldState] is non-null
/// it can be used as a hint for future incremental optimisations; currently
/// the computation always performs a full pass via [summarizeRuntimeGraph].
RuntimeGraphSummary incrementalGraphReducer(
  RuntimeGraphSummary? oldState,
  List<RuntimeEventEnvelope> previousEvents,
  RuntimeEventEnvelope newEvent,
) {
  final allEvents = <RuntimeEventEnvelope>[...previousEvents, newEvent];
  return summarizeRuntimeGraph(allEvents);
}
