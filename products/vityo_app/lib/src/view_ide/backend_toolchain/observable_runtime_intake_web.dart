import '../services/observable_topology/observable_runtime_model.dart';
import '../services/observable_topology/observable_snapshot_model.dart';

ObservableRuntimeIntake createObservableRuntimeIntake() {
  return const WebObservableRuntimeIntake();
}

class WebObservableRuntimeIntake implements ObservableRuntimeIntake {
  const WebObservableRuntimeIntake();

  @override
  Future<RuntimeIntakeResult> ingest(RuntimeIntakeRequest request) async {
    return const RuntimeIntakeResult.rejected(
      reason: ObservableReasonCode.unsupportedPlatform,
      detail: 'Runtime observation intake is unavailable on this platform.',
    );
  }
}
