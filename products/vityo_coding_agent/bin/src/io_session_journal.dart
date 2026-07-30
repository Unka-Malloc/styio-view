import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vityo_coding_agent/vityo_coding_agent.dart';

/// Process and cross-process serialized JSON-lines journal adapter.
final class IoSessionJournal implements SessionJournal {
  IoSessionJournal(Directory root) : _root = root.absolute;

  final Directory _root;
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  @override
  Future<T> synchronized<T>(String sessionKey, FutureOr<T> Function() action) {
    final result = Completer<T>();
    final previous = _tails[sessionKey] ?? Future<void>.value();
    late final Future<void> next;
    next = previous.then<void>((_) async {
      _root.createSync(recursive: true);
      final lock = _lockFile(sessionKey).openSync(mode: FileMode.write);
      try {
        lock.lockSync(FileLock.exclusive);
        result.complete(await action());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        lock.unlockSync();
        lock.closeSync();
      }
    });
    _tails[sessionKey] = next;
    unawaited(
      next.whenComplete(() {
        if (identical(_tails[sessionKey], next)) {
          _tails.remove(sessionKey);
        }
      }),
    );
    return result.future;
  }

  @override
  Stream<String> readLines(String sessionKey) async* {
    final file = _journalFile(sessionKey);
    if (!file.existsSync()) return;
    yield* file
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
  }

  @override
  void appendLine(String sessionKey, String line) {
    _root.createSync(recursive: true);
    _journalFile(
      sessionKey,
    ).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  }

  File _journalFile(String sessionKey) =>
      File('${_root.path}${Platform.pathSeparator}$sessionKey.session.jsonl');

  File _lockFile(String sessionKey) =>
      File('${_root.path}${Platform.pathSeparator}$sessionKey.lock');
}
