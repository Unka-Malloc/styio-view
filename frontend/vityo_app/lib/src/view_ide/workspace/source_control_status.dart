enum SourceControlProviderKind { localDirtyDocuments, git }

enum SourceControlFileStatus {
  added,
  copied,
  deleted,
  ignored,
  modified,
  renamed,
  untracked,
  conflicted,
  unknown,
}

extension SourceControlProviderKindX on SourceControlProviderKind {
  String get wireValue {
    return switch (this) {
      SourceControlProviderKind.localDirtyDocuments => 'local-dirty-documents',
      SourceControlProviderKind.git => 'git',
    };
  }
}

extension SourceControlFileStatusX on SourceControlFileStatus {
  String get wireValue {
    return switch (this) {
      SourceControlFileStatus.added => 'added',
      SourceControlFileStatus.copied => 'copied',
      SourceControlFileStatus.deleted => 'deleted',
      SourceControlFileStatus.ignored => 'ignored',
      SourceControlFileStatus.modified => 'modified',
      SourceControlFileStatus.renamed => 'renamed',
      SourceControlFileStatus.untracked => 'untracked',
      SourceControlFileStatus.conflicted => 'conflicted',
      SourceControlFileStatus.unknown => 'unknown',
    };
  }
}

class SourceControlFileChange {
  const SourceControlFileChange({
    required this.path,
    this.originalPath = '',
    this.stagedStatus,
    this.unstagedStatus,
  });

  final String path;
  final String originalPath;
  final SourceControlFileStatus? stagedStatus;
  final SourceControlFileStatus? unstagedStatus;

  bool get staged => stagedStatus != null;
  bool get unstaged => unstagedStatus != null;

  String get summary {
    final parts = <String>[
      if (stagedStatus != null) 'staged ${stagedStatus!.wireValue}',
      if (unstagedStatus != null) 'unstaged ${unstagedStatus!.wireValue}',
    ];
    return parts.isEmpty ? 'unknown' : parts.join(' · ');
  }
}

class SourceControlStatusSnapshot {
  const SourceControlStatusSnapshot({
    required this.providerKind,
    required this.changes,
    this.branchName = '',
    this.message = '',
  });

  final SourceControlProviderKind providerKind;
  final List<SourceControlFileChange> changes;
  final String branchName;
  final String message;

  bool get clean => changes.isEmpty;
}

class GitPorcelainStatusParser {
  const GitPorcelainStatusParser();

  SourceControlStatusSnapshot parse(String output) {
    final changes = <SourceControlFileChange>[];
    var branchName = '';

    for (final rawLine in output.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('## ')) {
        branchName = _parseBranchName(line.substring(3));
        continue;
      }
      if (line.length < 3) {
        changes.add(
          SourceControlFileChange(
            path: line,
            stagedStatus: SourceControlFileStatus.unknown,
          ),
        );
        continue;
      }

      final stagedStatus = _statusFromPorcelainCode(line.codeUnitAt(0));
      final unstagedStatus = _statusFromPorcelainCode(line.codeUnitAt(1));
      final pathText = line.substring(3);
      final renameParts = _splitRenamePath(pathText);

      changes.add(
        SourceControlFileChange(
          path: renameParts.$2,
          originalPath: renameParts.$1,
          stagedStatus: stagedStatus,
          unstagedStatus: unstagedStatus,
        ),
      );
    }

    return SourceControlStatusSnapshot(
      providerKind: SourceControlProviderKind.git,
      branchName: branchName,
      changes: List<SourceControlFileChange>.unmodifiable(changes),
      message: changes.isEmpty ? 'Git workspace is clean.' : 'Git changes.',
    );
  }
}

String _parseBranchName(String value) {
  final aheadMarker = value.indexOf('...');
  if (aheadMarker >= 0) {
    return value.substring(0, aheadMarker).trim();
  }
  final spaceMarker = value.indexOf(' ');
  if (spaceMarker >= 0) {
    return value.substring(0, spaceMarker).trim();
  }
  return value.trim();
}

(String, String) _splitRenamePath(String pathText) {
  final separator = pathText.indexOf(' -> ');
  if (separator < 0) {
    return ('', pathText.trim());
  }
  return (
    pathText.substring(0, separator).trim(),
    pathText.substring(separator + 4).trim(),
  );
}

SourceControlFileStatus? _statusFromPorcelainCode(int codeUnit) {
  return switch (codeUnit) {
    32 => null,
    33 => SourceControlFileStatus.ignored,
    63 => SourceControlFileStatus.untracked,
    65 => SourceControlFileStatus.added,
    67 => SourceControlFileStatus.copied,
    68 => SourceControlFileStatus.deleted,
    77 => SourceControlFileStatus.modified,
    82 => SourceControlFileStatus.renamed,
    85 => SourceControlFileStatus.conflicted,
    _ => SourceControlFileStatus.unknown,
  };
}
