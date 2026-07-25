const Set<String> knownRuntimeEventKinds = <String>{
  'compile.started',
  'compile.finished',
  'compile.failed',
  'diagnostic.emitted',
  'log.emitted',
  'run.started',
  'run.finished',
  'run.failed',
  'state.changed',
  'thread.spawned',
  'transition.fired',
  'unit.entered',
  'unit.exited',
  'unit.test.started',
  'unit.test.finished',
};

bool isKnownRuntimeEventKind(String eventKind) =>
    knownRuntimeEventKinds.contains(eventKind);

String runtimeEventFamily(String eventKind) {
  if (!isKnownRuntimeEventKind(eventKind)) return 'unsupported';
  if (eventKind.startsWith('unit.test.')) return 'unit.test';
  final separator = eventKind.indexOf('.');
  return separator <= 0 ? eventKind : eventKind.substring(0, separator);
}
