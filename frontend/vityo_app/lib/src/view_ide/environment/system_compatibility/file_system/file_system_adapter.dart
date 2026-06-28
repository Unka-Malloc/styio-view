import 'file_system_facts.dart';

class FileSystemAdapter {
  const FileSystemAdapter(this.facts);

  final FileSystemFacts facts;

  FileSystemCompatibility adapt() {
    return FileSystemCompatibility(
      targetId: facts.targetId,
      compatibilityTarget: facts.compatibilityTarget,
      pathStyle: facts.pathStyle,
      pathSeparator: facts.pathSeparator,
      caseSensitive: facts.caseSensitive,
      providerKind: facts.providerKind,
      watchSupport: facts.watchSupport,
      supportsFileUri: facts.supportsFileUri,
      supportsSymbolicLinks: facts.supportsSymbolicLinks,
      supportsAtomicWrite: facts.supportsAtomicWrite,
    );
  }
}

class FileSystemCompatibility {
  const FileSystemCompatibility({
    required this.targetId,
    required this.compatibilityTarget,
    required this.pathStyle,
    required this.pathSeparator,
    required this.caseSensitive,
    required this.providerKind,
    required this.watchSupport,
    required this.supportsFileUri,
    required this.supportsSymbolicLinks,
    required this.supportsAtomicWrite,
  });

  final String targetId;
  final String compatibilityTarget;
  final FileSystemPathStyle pathStyle;
  final String pathSeparator;
  final bool caseSensitive;
  final FileSystemProviderKind providerKind;
  final FileSystemWatchSupport watchSupport;
  final bool supportsFileUri;
  final bool supportsSymbolicLinks;
  final bool supportsAtomicWrite;

  bool get isLinuxDebianArm => compatibilityTarget == 'linux-debian-arm';

  bool get supportsDirectoryWatch {
    return watchSupport == FileSystemWatchSupport.directory ||
        watchSupport == FileSystemWatchSupport.recursive;
  }

  bool get supportsRecursiveWatch {
    return watchSupport == FileSystemWatchSupport.recursive;
  }

  bool isAbsolutePath(String path) {
    if (path.isEmpty) {
      return false;
    }
    if (pathStyle == FileSystemPathStyle.windows) {
      return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
          path.startsWith(r'\\');
    }
    return path.startsWith('/');
  }

  String joinPath(Iterable<String> segments) {
    final values = segments.where((segment) => segment.isNotEmpty).toList();
    if (values.isEmpty) {
      return '.';
    }
    return normalizePath(values.join(pathSeparator));
  }

  Uri toFileUri(String path) {
    if (!supportsFileUri) {
      throw UnsupportedError('File URI is not supported by this file system.');
    }
    final useWindowsUri =
        pathStyle == FileSystemPathStyle.windows || _hasWindowsDrive(path);
    return Uri.file(
      normalizePath(path),
      windows: useWindowsUri,
    );
  }

  String pathFromFileUri(Uri uri) {
    if (!supportsFileUri) {
      throw UnsupportedError('File URI is not supported by this file system.');
    }
    if (uri.scheme != 'file') {
      throw FormatException('Unsupported file URI scheme ${uri.scheme}.');
    }
    final useWindowsUri =
        pathStyle == FileSystemPathStyle.windows ||
        RegExp(r'^/[A-Za-z]:').hasMatch(uri.path);
    return normalizePath(
      uri.toFilePath(windows: useWindowsUri),
    );
  }

  bool isWithin(String childPath, String parentPath) {
    var child = normalizePath(childPath);
    var parent = normalizePath(parentPath);
    if (!caseSensitive) {
      child = child.toLowerCase();
      parent = parent.toLowerCase();
    }
    if (child == parent) {
      return true;
    }
    final parentPrefix = parent.endsWith(pathSeparator)
        ? parent
        : '$parent$pathSeparator';
    return child.startsWith(parentPrefix);
  }

  String normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '.';
    }

    if (pathStyle == FileSystemPathStyle.windows) {
      return _normalizeWindowsPath(trimmed);
    }
    return _normalizePosixPath(trimmed);
  }

  String _normalizePosixPath(String path) {
    final source = path.replaceAll(r'\', '/');
    final absolute = source.startsWith('/');
    final parts = <String>[];
    for (final segment in source.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (parts.isNotEmpty && parts.last != '..') {
          parts.removeLast();
        } else if (!absolute) {
          parts.add(segment);
        }
        continue;
      }
      parts.add(segment);
    }

    if (absolute) {
      return parts.isEmpty ? '/' : '/${parts.join('/')}';
    }
    return parts.isEmpty ? '.' : parts.join('/');
  }

  String _normalizeWindowsPath(String path) {
    final source = path.replaceAll('/', r'\');
    final driveMatch = RegExp(r'^[A-Za-z]:').firstMatch(source);
    final drive = driveMatch?.group(0) ?? '';
    final withoutDrive = drive.isEmpty ? source : source.substring(2);
    final absolute = drive.isNotEmpty || withoutDrive.startsWith(r'\');
    final parts = <String>[];
    for (final segment in withoutDrive.split(r'\')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (parts.isNotEmpty && parts.last != '..') {
          parts.removeLast();
        } else if (!absolute) {
          parts.add(segment);
        }
        continue;
      }
      parts.add(segment);
    }
    final body = parts.join(r'\');
    if (drive.isNotEmpty) {
      return body.isEmpty ? '$drive\\' : '$drive\\$body';
    }
    if (absolute) {
      return body.isEmpty ? r'\' : '\\$body';
    }
    return body.isEmpty ? '.' : body;
  }
}

bool _hasWindowsDrive(String path) {
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path.trim());
}
