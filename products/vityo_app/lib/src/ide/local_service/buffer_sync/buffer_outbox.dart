import 'dart:collection';

final class BufferDelta {
  const BufferDelta({
    required this.documentId,
    required this.baseRevision,
    required this.targetRevision,
    required this.startOffset,
    required this.deletedLength,
    required this.insertedText,
  });

  final String documentId;
  final int baseRevision;
  final int targetRevision;
  final int startOffset;
  final int deletedLength;
  final String insertedText;

  Map<String, Object?> toJson() => <String, Object?>{
    'documentId': documentId,
    'baseRevision': baseRevision,
    'targetRevision': targetRevision,
    'startOffset': startOffset,
    'deletedLength': deletedLength,
    'insertedText': insertedText,
  };
}

final class BufferDeltaOutbox {
  BufferDeltaOutbox({this.maximumPendingDeltas = 1024});

  final int maximumPendingDeltas;
  final ListQueue<BufferDelta> _pending = ListQueue<BufferDelta>();

  List<BufferDelta> get pending => List<BufferDelta>.unmodifiable(_pending);

  void add(BufferDelta delta) {
    if (_pending.length >= maximumPendingDeltas) {
      throw StateError('buffer delta outbox is full');
    }
    if (_pending.isNotEmpty) {
      final previous = _pending.last;
      if (previous.documentId == delta.documentId &&
          previous.targetRevision != delta.baseRevision) {
        throw StateError('buffer delta revisions are not contiguous');
      }
    }
    _pending.addLast(delta);
  }

  void acknowledge({required String documentId, required int revision}) {
    _pending.removeWhere(
      (delta) =>
          delta.documentId == documentId && delta.targetRevision <= revision,
    );
  }
}
