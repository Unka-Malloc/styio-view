import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

void main() {
  test('window retains eight generations and evicts oldest first', () {
    final window = ObservableLineageWindow();
    expect(window.maxGenerations, 8);
    for (var i = 0; i < 9; i += 1) {
      window.push(
        ObservableLineageWindowEntry(
          snapshotId: 's1_${i.toString().padLeft(32, '0')}',
          parentSnapshotId: i == 0
              ? null
              : 's1_${(i - 1).toString().padLeft(32, '0')}',
          changeSource: ObservableChangeSetSource.producerDelta,
          changeSet: const ObservableChangeSet(
            addedNodeIds: <String>[],
            removedNodeIds: <String>[],
            addedEdgeIds: <String>[],
            removedEdgeIds: <String>[],
          ),
          lineageRecords: const <ObservableLineageRecord>[],
        ),
      );
    }
    expect(window.length, 8);
    expect(window.evicted, 1);
    expect(window.containsSnapshot('s1_${0.toString().padLeft(32, '0')}'), isFalse);
    expect(window.containsSnapshot('s1_${1.toString().padLeft(32, '0')}'), isTrue);
    expect(window.head!.snapshotId, 's1_${8.toString().padLeft(32, '0')}');
  });

  test('reset clears retained generations', () {
    final window = ObservableLineageWindow();
    window.push(
      const ObservableLineageWindowEntry(
        snapshotId: 's1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        changeSource: ObservableChangeSetSource.idSetComparison,
        changeSet: ObservableChangeSet(
          addedNodeIds: <String>[],
          removedNodeIds: <String>[],
          addedEdgeIds: <String>[],
          removedEdgeIds: <String>[],
        ),
        lineageRecords: <ObservableLineageRecord>[],
      ),
    );
    window.reset();
    expect(window.length, 0);
    expect(window.head, isNull);
  });
}
