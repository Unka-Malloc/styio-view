import 'dart:io';

Future<File> writeFakePafioCli({
  required Directory workspaceRoot,
  required String pythonSource,
}) async {
  final binDirectory = Directory(
    '${workspaceRoot.path}${Platform.pathSeparator}.pafio'
    '${Platform.pathSeparator}bin',
  );
  return writeFakePythonCli(
    directory: binDirectory,
    executableName: 'pafio',
    pythonSource: pythonSource,
  );
}

Future<File> writeFakePythonCli({
  required Directory directory,
  required String executableName,
  required String pythonSource,
}) async {
  await directory.create(recursive: true);

  if (Platform.isWindows) {
    final script = File(
      '${directory.path}${Platform.pathSeparator}$executableName.py',
    );
    await script.writeAsString(pythonSource);
    final launcher = File(
      '${directory.path}${Platform.pathSeparator}$executableName.cmd',
    );
    await launcher.writeAsString(
      '@echo off\r\npython "%~dp0$executableName.py" %*\r\n',
    );
    return launcher;
  }

  final executable = File(
    '${directory.path}${Platform.pathSeparator}$executableName',
  );
  await executable.writeAsString(pythonSource);
  final chmod = Process.runSync('chmod', <String>['+x', executable.path]);
  if (chmod.exitCode != 0) {
    throw FileSystemException(
      'Failed to mark fake pafio executable: ${chmod.stderr}',
      executable.path,
    );
  }
  return executable;
}
