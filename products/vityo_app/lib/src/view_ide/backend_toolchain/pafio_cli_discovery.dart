import 'dart:io';

void appendPafioExecutableCandidates(List<String> candidates, String path) {
  if (Platform.isWindows && !_hasExecutableExtension(path)) {
    candidates.add('$path.cmd');
    candidates.add('$path.exe');
    candidates.add('$path.bat');
  }
  candidates.add(path);
}

String joinPath(String left, String right) {
  if (left.isEmpty) {
    return right;
  }
  if (right.isEmpty) {
    return left;
  }
  final separator = Platform.pathSeparator;
  final normalizedLeft = left.endsWith(separator)
      ? left.substring(0, left.length - separator.length)
      : left;
  final normalizedRight = right.startsWith(separator)
      ? right.substring(separator.length)
      : right;
  return '$normalizedLeft$separator$normalizedRight';
}

Future<String?> resolvePafioBinary({required String workspaceRoot}) async {
  final candidates = <String>[];
  final seen = <String>{};
  final explicit = Platform.environment['VITYO_PAFIO_BIN'];
  if (explicit != null && explicit.isNotEmpty) {
    appendPafioExecutableCandidates(candidates, explicit);
  }
  final fromEnv = Platform.environment['PAFIO_BIN'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    appendPafioExecutableCandidates(candidates, fromEnv);
  }

  var current = Directory(workspaceRoot).absolute;
  while (true) {
    appendPafioExecutableCandidates(
      candidates,
      joinPath(current.path, '.pafio/bin/pafio'),
    );
    appendPafioExecutableCandidates(
      candidates,
      joinPath(current.path, 'scripts/pafio'),
    );
    appendPafioExecutableCandidates(
      candidates,
      joinPath(current.path, '../styio-pafio/scripts/pafio'),
    );
    appendPafioExecutableCandidates(
      candidates,
      joinPath(current.path, '../../SymPolicy/Pafio/scripts/pafio'),
    );
    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  for (final candidate in candidates) {
    if (!seen.add(candidate)) {
      continue;
    }
    final file = File(candidate);
    if (await file.exists()) {
      return file.path;
    }
  }

  try {
    final pathCandidates = <String>[];
    appendPafioExecutableCandidates(pathCandidates, 'pafio');
    for (final candidate in pathCandidates) {
      try {
        final result = await Process.run(candidate, const <String>['--version']);
        if (result.exitCode == 0) {
          return candidate;
        }
      } on ProcessException {
        continue;
      }
    }
  } on ProcessException {
    // Fall through to null when the binary is unavailable.
  }
  return null;
}

bool _hasExecutableExtension(String path) {
  return RegExp(r'\.(bat|cmd|com|exe)$', caseSensitive: false).hasMatch(path);
}
