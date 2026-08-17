enum VityodConnectionPhase {
  disconnected,
  connecting,
  connected,
  reconnecting,
  resyncRequired,
  blocked,
}

final class VityodConnectionState {
  const VityodConnectionState({
    required this.phase,
    this.daemonInstanceId,
    this.reasonCode,
    this.lastEventCursor = 0,
  });

  const VityodConnectionState.disconnected()
    : this(phase: VityodConnectionPhase.disconnected);

  final VityodConnectionPhase phase;
  final String? daemonInstanceId;
  final String? reasonCode;
  final int lastEventCursor;

  bool get canDispatch => phase == VityodConnectionPhase.connected;
}
