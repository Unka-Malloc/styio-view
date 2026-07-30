import 'dart:io';

Map<String, String> Function() _environmentProvider = () =>
    Platform.environment;

void debugOverridePafioDiscoveryEnvironment(
  Map<String, String>? environment,
) {
  _environmentProvider = environment == null
      ? () => Platform.environment
      : () => Map<String, String>.unmodifiable(environment);
}

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

Future<String?> resolvePafioBinary({
  Map<String, String>? environment,
}) async {
  final env = environment ?? _environmentProvider();
  final candidates = <String>[];
  final explicit = env['VITYO_PAFIO_BIN'];
  if (explicit != null && explicit.isNotEmpty) {
    appendPafioExecutableCandidates(candidates, explicit);
  }
  appendPafioExecutableCandidates(candidates, 'pafio');
  for (final candidate in candidates) {
    try {
      final result = await Process.run(candidate, const <String>[
        '--version',
      ], environment: env);
      if (result.exitCode == 0) {
        return candidate;
      }
    } on ProcessException {
      continue;
    }
  }
  return null;
}

bool _hasExecutableExtension(String path) {
  return RegExp(r'\.(bat|cmd|com|exe)$', caseSensitive: false).hasMatch(path);
}
