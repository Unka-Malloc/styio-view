library;

import 'dart:async';

import 'hosts/host_workspace.dart';

final class AgentCancellationController {
  AgentCancellationController() : token = AgentCancellationToken._();

  final AgentCancellationToken token;

  void cancel() => token._cancel();
}

final class AgentCancellationToken implements HostCancellationSignal {
  AgentCancellationToken._();

  final Completer<void> _cancelled = Completer<void>();
  final StreamController<void> _cancellations =
      StreamController<void>.broadcast(sync: true);

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  Stream<void> get cancellations => _cancellations.stream;

  void _cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
      _cancellations.add(null);
      unawaited(_cancellations.close());
    }
  }
}
