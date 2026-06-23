import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('archive extractor expands tar directories and files', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_archive_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final manager = LocalFileSystemManager.linuxDebianArmForTest();
    final extractor = ToolchainArchiveExtractor(fileSystemManager: manager);
    final destination = manager.joinPath(<String>[tempRoot.path, 'extracted']);
    final archive = _tarArchive(<_TarEntry>[
      _TarEntry.directory('bin/'),
      _TarEntry.file('bin/styio', utf8.encode('styio executable')),
      _TarEntry.file('manifest.json', utf8.encode('{"name":"styio"}')),
    ]);

    final result = await extractor.extractTar(
      archiveBytes: archive,
      destinationDirectory: destination,
    );

    expect(result.succeeded, isTrue);
    expect(result.extractedEntryCount, 3);
    expect(result.toJson()['succeeded'], isTrue);
    expect(
      await File(
        manager.joinPath(<String>[destination, 'bin/styio']),
      ).readAsString(),
      'styio executable',
    );
    expect(
      await File(
        manager.joinPath(<String>[destination, 'manifest.json']),
      ).readAsString(),
      '{"name":"styio"}',
    );
  });

  test('archive extractor rejects unsafe tar entry paths', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_archive_unsafe_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final extractor = ToolchainArchiveExtractor(
      fileSystemManager: LocalFileSystemManager.linuxDebianArmForTest(),
    );

    final emptyPath = await extractor.extractTar(
      archiveBytes: _tarArchive(<_TarEntry>[_TarEntry.file('', const <int>[])]),
      destinationDirectory: tempRoot.path,
    );
    final absolutePath = await extractor.extractTar(
      archiveBytes: _tarArchive(<_TarEntry>[
        _TarEntry.file('/tmp/styio', const <int>[]),
      ]),
      destinationDirectory: tempRoot.path,
    );
    final parentEscape = await extractor.extractTar(
      archiveBytes: _tarArchive(<_TarEntry>[
        _TarEntry.file('../styio', const <int>[]),
      ]),
      destinationDirectory: tempRoot.path,
    );

    expect(emptyPath.succeeded, isFalse);
    expect(emptyPath.message, contains('path is empty'));
    expect(absolutePath.message, contains('absolute'));
    expect(parentEscape.message, contains('escapes'));
  });

  test('archive extractor reports truncated and unterminated tar archives', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_archive_invalid_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final extractor = ToolchainArchiveExtractor(
      fileSystemManager: LocalFileSystemManager.linuxDebianArmForTest(),
    );

    final truncated = await extractor.extractTar(
      archiveBytes: _header(name: 'bin/styio', size: 12, typeFlag: 48),
      destinationDirectory: tempRoot.path,
    );
    final unterminated = await extractor.extractTar(
      archiveBytes: _header(name: 'bin/styio', size: 0, typeFlag: 48),
      destinationDirectory: tempRoot.path,
    );

    expect(truncated.succeeded, isFalse);
    expect(truncated.message, contains('exceeds archive length'));
    expect(unterminated.succeeded, isFalse);
    expect(unterminated.message, contains('before a terminator block'));
  });
}

class _TarEntry {
  const _TarEntry._({
    required this.name,
    required this.bytes,
    required this.typeFlag,
  });

  factory _TarEntry.file(String name, List<int> bytes) {
    return _TarEntry._(name: name, bytes: bytes, typeFlag: 48);
  }

  factory _TarEntry.directory(String name) {
    return _TarEntry._(name: name, bytes: const <int>[], typeFlag: 53);
  }

  final String name;
  final List<int> bytes;
  final int typeFlag;
}

List<int> _tarArchive(List<_TarEntry> entries) {
  return <int>[
    for (final entry in entries) ...[
      ..._header(
        name: entry.name,
        size: entry.bytes.length,
        typeFlag: entry.typeFlag,
      ),
      ...entry.bytes,
      ...List<int>.filled(_paddingFor(entry.bytes.length), 0),
    ],
    ...List<int>.filled(512, 0),
  ];
}

List<int> _header({
  required String name,
  required int size,
  required int typeFlag,
}) {
  final header = List<int>.filled(512, 0);
  _writeAscii(header, 0, 100, name);
  _writeAscii(header, 100, 8, '0000777');
  _writeAscii(header, 108, 8, '0000000');
  _writeAscii(header, 116, 8, '0000000');
  _writeAscii(header, 124, 12, size.toRadixString(8).padLeft(11, '0'));
  _writeAscii(header, 136, 12, '00000000000');
  header[156] = typeFlag;
  return header;
}

void _writeAscii(List<int> target, int start, int length, String value) {
  final bytes = ascii.encode(value);
  for (var index = 0; index < bytes.length && index < length; index += 1) {
    target[start + index] = bytes[index];
  }
}

int _paddingFor(int size) {
  final remainder = size % 512;
  return remainder == 0 ? 0 : 512 - remainder;
}
