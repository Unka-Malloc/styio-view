library;

import 'dart:async';

/// Host-provided durable journal used by [JournalSessionEventStore].
///
/// Implementations must serialize [synchronized] calls for the same key and
/// keep the lock for the full callback. [readLines] and [appendLine] are only
/// called from within that callback.
abstract interface class SessionJournal {
  Future<T> synchronized<T>(String sessionKey, FutureOr<T> Function() action);

  Stream<String> readLines(String sessionKey);

  void appendLine(String sessionKey, String line);
}
