import 'observable_delta_model.dart';
import 'observable_snapshot_model.dart';

class ObservableLineageWindow {
  ObservableLineageWindow({
    this.maxGenerations = kObservableLineageWindowGenerations,
  }) : assert(maxGenerations > 0, 'maxGenerations must be positive');

  final int maxGenerations;
  final List<ObservableLineageWindowEntry> _entries =
      <ObservableLineageWindowEntry>[];
  int _evicted = 0;

  List<ObservableLineageWindowEntry> get entries =>
      List<ObservableLineageWindowEntry>.unmodifiable(_entries);

  int get length => _entries.length;

  int get evicted => _evicted;

  ObservableLineageWindowEntry? get head =>
      _entries.isEmpty ? null : _entries.last;

  void reset() {
    _entries.clear();
  }

  ObservableLineageWindowEntry push(ObservableLineageWindowEntry entry) {
    _entries.add(entry);
    while (_entries.length > maxGenerations) {
      _entries.removeAt(0);
      _evicted += 1;
    }
    return entry;
  }

  bool containsSnapshot(String snapshotId) {
    for (final entry in _entries) {
      if (entry.snapshotId == snapshotId) {
        return true;
      }
    }
    return false;
  }

  ObservableLineageWindowEntry? entryFor(String snapshotId) {
    for (final entry in _entries) {
      if (entry.snapshotId == snapshotId) {
        return entry;
      }
    }
    return null;
  }

  List<ObservableLineageRecord> recordsMentioning(String identity) {
    final records = <ObservableLineageRecord>[];
    for (final entry in _entries) {
      for (final record in entry.lineageRecords) {
        if (record.mentions(identity)) {
          records.add(record);
        }
      }
    }
    return records;
  }
}
