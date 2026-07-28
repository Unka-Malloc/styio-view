import '../environment/system_compatibility/file_system/file_system_manager.dart';

enum ToolchainArchiveFormat {
  none,
  tar,
}

class ToolchainArchiveExtractionResult {
  const ToolchainArchiveExtractionResult({
    required this.succeeded,
    required this.extractionDirectory,
    this.extractedEntryCount = 0,
    this.message,
  });

  final bool succeeded;
  final String extractionDirectory;
  final int extractedEntryCount;
  final String? message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'succeeded': succeeded,
      'extractionDirectory': extractionDirectory,
      'extractedEntryCount': extractedEntryCount,
      if (message != null) 'message': message,
    };
  }
}

class ToolchainArchiveExtractor {
  const ToolchainArchiveExtractor({required FileSystemManager fileSystemManager})
    : _fileSystemManager = fileSystemManager;

  final FileSystemManager _fileSystemManager;

  Future<ToolchainArchiveExtractionResult> extractTar({
    required List<int> archiveBytes,
    required String destinationDirectory,
  }) async {
    var offset = 0;
    var extractedEntries = 0;
    while (offset + 512 <= archiveBytes.length) {
      final header = archiveBytes.sublist(offset, offset + 512);
      offset += 512;
      if (_isZeroBlock(header)) {
        return ToolchainArchiveExtractionResult(
          succeeded: true,
          extractionDirectory: destinationDirectory,
          extractedEntryCount: extractedEntries,
        );
      }

      final name = _readNullTerminated(header, 0, 100);
      final size = _readOctal(header, 124, 12);
      final typeFlag = header[156];
      final validationError = _validateRelativePath(name);
      if (validationError != null) {
        return ToolchainArchiveExtractionResult(
          succeeded: false,
          extractionDirectory: destinationDirectory,
          extractedEntryCount: extractedEntries,
          message: validationError,
        );
      }
      if (offset + size > archiveBytes.length) {
        return ToolchainArchiveExtractionResult(
          succeeded: false,
          extractionDirectory: destinationDirectory,
          extractedEntryCount: extractedEntries,
          message: 'Tar archive entry $name exceeds archive length.',
        );
      }

      final targetPath = _fileSystemManager.joinPath(
        <String>[destinationDirectory, name],
      );
      if (typeFlag == 53) {
        await _fileSystemManager.createDirectory(targetPath, recursive: true);
        extractedEntries += 1;
      } else if (typeFlag == 0 || typeFlag == 48) {
        await _fileSystemManager.writeBytes(
          targetPath,
          archiveBytes.sublist(offset, offset + size),
          createParents: true,
          atomic: true,
        );
        extractedEntries += 1;
      }
      offset += _paddedSize(size);
    }

    return ToolchainArchiveExtractionResult(
      succeeded: false,
      extractionDirectory: destinationDirectory,
      extractedEntryCount: extractedEntries,
      message: 'Tar archive ended before a terminator block.',
    );
  }

  bool _isZeroBlock(List<int> block) {
    for (final byte in block) {
      if (byte != 0) {
        return false;
      }
    }
    return true;
  }

  String _readNullTerminated(List<int> bytes, int start, int length) {
    final buffer = StringBuffer();
    for (var index = start; index < start + length; index += 1) {
      final byte = bytes[index];
      if (byte == 0) {
        break;
      }
      buffer.writeCharCode(byte);
    }
    return buffer.toString();
  }

  int _readOctal(List<int> bytes, int start, int length) {
    final value = _readNullTerminated(bytes, start, length).trim();
    if (value.isEmpty) {
      return 0;
    }
    return int.parse(value, radix: 8);
  }

  String? _validateRelativePath(String path) {
    if (path.isEmpty) {
      return 'Tar archive entry path is empty.';
    }
    if (path.startsWith('/')) {
      return 'Tar archive entry $path is absolute.';
    }
    final segments = path.split('/');
    for (final segment in segments) {
      if (segment == '..') {
        return 'Tar archive entry $path escapes the extraction directory.';
      }
    }
    return null;
  }

  int _paddedSize(int size) {
    final remainder = size % 512;
    return remainder == 0 ? size : size + 512 - remainder;
  }
}
