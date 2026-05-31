import '../language/language.dart';

enum WorkspaceNavigationLocationKind {
  caret,
  file,
  symbol,
  search,
  problem,
}

class WorkspaceNavigationLocation {
  const WorkspaceNavigationLocation({
    required this.filePath,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
    required this.label,
    this.kind = WorkspaceNavigationLocationKind.caret,
  });

  final String filePath;
  final SourceRange range;
  final int line;
  final int column;
  final String previewText;
  final String label;
  final WorkspaceNavigationLocationKind kind;

  bool sameTarget(WorkspaceNavigationLocation other) {
    return filePath == other.filePath &&
        range.start == other.range.start &&
        range.end == other.range.end;
  }

  String get displayLocation => '$filePath:${line + 1}:${column + 1}';
}

class WorkspaceNavigationHistorySnapshot {
  const WorkspaceNavigationHistorySnapshot({
    required this.entries,
    required this.currentIndex,
  });

  final List<WorkspaceNavigationLocation> entries;
  final int currentIndex;

  bool get canGoBack => currentIndex > 0 && entries.isNotEmpty;

  bool get canGoForward =>
      currentIndex >= 0 && currentIndex < entries.length - 1;

  WorkspaceNavigationLocation? get currentLocation {
    if (currentIndex < 0 || currentIndex >= entries.length) {
      return null;
    }
    return entries[currentIndex];
  }

  List<WorkspaceNavigationLocation> get recentLocations {
    final seen = <String>{};
    final locations = <WorkspaceNavigationLocation>[];
    for (final location in entries.reversed) {
      final key =
          '${location.filePath}:${location.range.start}:${location.range.end}';
      if (seen.add(key)) {
        locations.add(location);
      }
    }
    return List<WorkspaceNavigationLocation>.unmodifiable(locations);
  }
}
