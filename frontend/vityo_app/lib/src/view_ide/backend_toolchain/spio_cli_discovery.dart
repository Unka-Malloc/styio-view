import 'dart:io';

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

Future<String?> resolveSpioBinary({required String workspaceRoot}) async {
  final candidates = <String>[];
  final seen = <String>{};
  final explicit = Platform.environment['VITYO_SPIO_BIN'];
  if (explicit != null && explicit.isNotEmpty) {
    candidates.add(explicit);
  }
  final fromEnv = Platform.environment['SPIO_BIN'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    candidates.add(fromEnv);
  }

  var current = Directory(workspaceRoot).absolute;
  while (true) {
    candidates.add(joinPath(current.path, '.spio/bin/spio'));
    candidates.add(joinPath(current.path, 'scripts/spio'));
    candidates.add(joinPath(current.path, '../styio-spio/scripts/spio'));
    candidates.add(
      joinPath(current.path, '../../Unka-Malloc/styio-spio/scripts/spio'),
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
    final result = await Process.run('spio', const <String>['--version']);
    if (result.exitCode == 0) {
      return 'spio';
    }
  } on ProcessException {
    // Fall through to null when the binary is unavailable.
  }
  return null;
}
