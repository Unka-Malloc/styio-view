import '../services/observable_topology/observable_snapshot_model.dart';

ObservableSnapshotPublisher createObservableSnapshotPublisher() {
  return const WebObservableSnapshotPublisher();
}

class WebObservableSnapshotPublisher implements ObservableSnapshotPublisher {
  const WebObservableSnapshotPublisher();

  @override
  Future<ObservableSnapshotPublishResult> publish(
    ObservableSnapshotPublishRequest request,
  ) async {
    return ObservableSnapshotPublishResult.unsupported(
      detail: 'Observable snapshot publication is unavailable on this platform.',
    );
  }

  @override
  void cancel() {}
}
