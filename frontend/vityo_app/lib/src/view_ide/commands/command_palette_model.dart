import 'app_commands.dart';

class CommandPaletteQueryState {
  const CommandPaletteQueryState({
    this.query = '',
    this.category,
    this.recentCommandIds = const <AppCommandId>[],
  });

  final String query;
  final AppCommandCategory? category;
  final List<AppCommandId> recentCommandIds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (query.trim().isNotEmpty) 'query': query.trim(),
      if (category != null) 'category': category!.wireValue,
      'recentCommandIds': recentCommandIds.map((id) => id.name).toList(),
    };
  }
}

class CommandPaletteCommandEntry {
  const CommandPaletteCommandEntry({
    required this.command,
    required this.score,
    this.recentRank,
  });

  final AppCommandDescriptor command;
  final int score;
  final int? recentRank;

  bool get recent => recentRank != null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': command.id.name,
      'label': command.label,
      'category': command.category.wireValue,
      'score': score,
      'recent': recent,
      if (recentRank != null) 'recentRank': recentRank,
      'requiresInput': command.requiresInput,
      if (command.inputLabel.isNotEmpty) 'inputLabel': command.inputLabel,
      if (command.inputContract.isNotEmpty)
        'inputContract': command.inputContract,
      if (command.inputExamples.isNotEmpty)
        'inputExamples': command.inputExamples,
    };
  }
}

class CommandPaletteInputDraft {
  const CommandPaletteInputDraft({required this.command, this.input = ''});

  final AppCommandDescriptor command;
  final String input;

  bool get ready {
    return !command.requiresInput || input.trim().isNotEmpty;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'commandId': command.id.name,
      'requiresInput': command.requiresInput,
      if (command.inputLabel.isNotEmpty) 'inputLabel': command.inputLabel,
      if (command.inputContract.isNotEmpty)
        'inputContract': command.inputContract,
      if (command.inputExamples.isNotEmpty)
        'inputExamples': command.inputExamples,
      if (input.trim().isNotEmpty) 'input': input.trim(),
      'ready': ready,
    };
  }
}

class CommandPaletteOverlayState {
  const CommandPaletteOverlayState({
    required this.queryState,
    required this.entries,
    this.selectedIndex = 0,
  });

  factory CommandPaletteOverlayState.fromModel({
    required CommandPaletteModel model,
    required CommandPaletteQueryState queryState,
    int selectedIndex = 0,
  }) {
    final entries = model.entriesFor(queryState);
    return CommandPaletteOverlayState(
      queryState: queryState,
      entries: entries,
      selectedIndex: entries.isEmpty
          ? 0
          : selectedIndex.clamp(0, entries.length - 1),
    );
  }

  final CommandPaletteQueryState queryState;
  final List<CommandPaletteCommandEntry> entries;
  final int selectedIndex;

  bool get visible => true;
  bool get empty => entries.isEmpty;
  int get visibleCount => entries.length;
  CommandPaletteCommandEntry? get selectedEntry {
    if (entries.isEmpty) {
      return null;
    }
    return entries[selectedIndex.clamp(0, entries.length - 1)];
  }

  CommandPaletteInputDraft? get selectedInputDraft {
    final entry = selectedEntry;
    if (entry == null) {
      return null;
    }
    return CommandPaletteInputDraft(command: entry.command);
  }

  CommandPaletteOverlayState moveSelection(int delta) {
    if (entries.isEmpty) {
      return this;
    }
    final nextIndex = (selectedIndex + delta).clamp(0, entries.length - 1);
    return CommandPaletteOverlayState(
      queryState: queryState,
      entries: entries,
      selectedIndex: nextIndex,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'visible': visible,
      'empty': empty,
      'selectedIndex': selectedIndex,
      'visibleCount': visibleCount,
      'queryState': queryState.toJson(),
      if (selectedEntry != null) 'selectedEntry': selectedEntry!.toJson(),
      if (selectedInputDraft != null)
        'selectedInputDraft': selectedInputDraft!.toJson(),
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class CommandPaletteModel {
  const CommandPaletteModel({required this.commands});

  final List<AppCommandDescriptor> commands;

  List<CommandPaletteCommandEntry> entriesFor(CommandPaletteQueryState state) {
    final normalizedQuery = state.query.trim().toLowerCase();
    final recentRanks = <AppCommandId, int>{
      for (var index = 0; index < state.recentCommandIds.length; index += 1)
        state.recentCommandIds[index]: index,
    };
    final entries = <CommandPaletteCommandEntry>[];

    for (final command in commands) {
      if (state.category != null && command.category != state.category) {
        continue;
      }
      final score = _score(command, normalizedQuery);
      if (normalizedQuery.isNotEmpty && score == 0) {
        continue;
      }
      final recentRank = recentRanks[command.id];
      entries.add(
        CommandPaletteCommandEntry(
          command: command,
          score: score + _recentBoost(recentRank),
          recentRank: recentRank,
        ),
      );
    }

    entries.sort((left, right) {
      final scoreOrder = right.score.compareTo(left.score);
      if (scoreOrder != 0) {
        return scoreOrder;
      }
      final leftRecent = left.recentRank ?? 1 << 20;
      final rightRecent = right.recentRank ?? 1 << 20;
      final recentOrder = leftRecent.compareTo(rightRecent);
      if (recentOrder != 0) {
        return recentOrder;
      }
      return left.command.label.compareTo(right.command.label);
    });
    return List<CommandPaletteCommandEntry>.unmodifiable(entries);
  }

  List<AppCommandDescriptor> commandsFor(CommandPaletteQueryState state) {
    return entriesFor(
      state,
    ).map((entry) => entry.command).toList(growable: false);
  }

  CommandPaletteOverlayState overlayStateFor(
    CommandPaletteQueryState state, {
    int selectedIndex = 0,
  }) {
    return CommandPaletteOverlayState.fromModel(
      model: this,
      queryState: state,
      selectedIndex: selectedIndex,
    );
  }

  int _score(AppCommandDescriptor command, String query) {
    if (query.isEmpty) {
      return 1;
    }
    final label = command.label.toLowerCase();
    final id = command.id.name.toLowerCase();
    final category = command.category.wireValue.toLowerCase();
    final description = command.description.toLowerCase();
    if (label.startsWith(query)) {
      return 100;
    }
    if (label.contains(query)) {
      return 80;
    }
    if (id.contains(query)) {
      return 60;
    }
    if (category.contains(query)) {
      return 50;
    }
    if (description.contains(query)) {
      return 30;
    }
    return 0;
  }

  int _recentBoost(int? recentRank) {
    if (recentRank == null) {
      return 0;
    }
    return 20 - recentRank.clamp(0, 20);
  }
}
