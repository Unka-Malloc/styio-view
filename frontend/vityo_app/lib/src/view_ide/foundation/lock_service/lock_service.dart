import 'dart:async';

class FoundationLockToken {
  const FoundationLockToken(this.key);

  final String key;
}

class FoundationLockService {
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  bool isLocked(String key) => _tails.containsKey(key);

  Future<T> runExclusive<T>(
    String key,
    FutureOr<T> Function(FoundationLockToken token) action,
  ) async {
    final previous = _tails[key] ?? Future<void>.value();
    final completer = Completer<void>();
    _tails[key] = completer.future;
    await previous;
    try {
      return await action(FoundationLockToken(key));
    } finally {
      if (identical(_tails[key], completer.future)) {
        _tails.remove(key);
      }
      completer.complete();
    }
  }
}
