import 'agent_coding_skill.dart';

class AgentCodingSkillMatch {
  const AgentCodingSkillMatch({
    required this.skill,
    required this.score,
    required this.matchedSignals,
  });

  final AgentCodingSkill skill;
  final int score;
  final List<String> matchedSignals;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'skillId': skill.skillId,
      'title': skill.title,
      'score': score,
      'matchedSignals': matchedSignals,
      'skill': skill.toJson(),
    };
  }
}

class AgentCodingSkillSelection {
  const AgentCodingSkillSelection({
    required this.matches,
    required this.unmatchedSignals,
  });

  final List<AgentCodingSkillMatch> matches;
  final List<String> unmatchedSignals;

  bool get isEmpty => matches.isEmpty;

  List<String> get skillIds {
    return matches.map((match) => match.skill.skillId).toList(growable: false);
  }

  List<String> get promptSections {
    return matches
        .map((match) {
          final skill = match.skill;
          return <String>[
            'Skill: ${skill.title} (${skill.skillId})',
            if (skill.toolchainDefaults.isNotEmpty) 'Toolchain defaults:',
            for (final item in skill.toolchainDefaults) '- $item',
            if (skill.instructions.isNotEmpty) 'Instructions:',
            for (final item in skill.instructions) '- $item',
            if (skill.validationHints.isNotEmpty) 'Validation hints:',
            for (final item in skill.validationHints) '- $item',
          ].join('\n');
        })
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'matchCount': matches.length,
      'skillIds': skillIds,
      'unmatchedSignals': unmatchedSignals,
      'matches': matches.map((match) => match.toJson()).toList(growable: false),
      'promptSections': promptSections,
    };
  }
}

class AgentCodingSkillRegistry {
  const AgentCodingSkillRegistry({
    this.skills = AgentCodingSkillCatalog.defaultSkills,
  });

  final List<AgentCodingSkill> skills;

  AgentCodingSkill? skillById(String skillId) {
    for (final skill in skills) {
      if (skill.skillId == skillId) {
        return skill;
      }
    }

    return null;
  }

  AgentCodingSkillSelection selectForContext({
    Iterable<String> languages = const <String>[],
    Iterable<String> documentPaths = const <String>[],
    Iterable<String> taskHints = const <String>[],
    Iterable<String> toolchainHints = const <String>[],
    int limit = 6,
  }) {
    final signals = <String>[
      ...languages,
      ...documentPaths.map(_pathSignal),
      ...taskHints,
      ...toolchainHints,
    ].map(_normalizeSignal).where((signal) => signal.isNotEmpty).toList();

    final scored = <_ScoredSkill>[];

    for (var index = 0; index < skills.length; index += 1) {
      final skill = skills[index];
      final matchedSignals = _matchedSignals(skill, signals);
      if (matchedSignals.isEmpty) {
        continue;
      }

      scored.add(
        _ScoredSkill(
          index: index,
          match: AgentCodingSkillMatch(
            skill: skill,
            score: _scoreSkill(skill, matchedSignals),
            matchedSignals: matchedSignals,
          ),
        ),
      );
    }

    scored.sort((left, right) {
      final byScore = right.match.score.compareTo(left.match.score);
      if (byScore != 0) {
        return byScore;
      }

      return left.index.compareTo(right.index);
    });

    final matches = scored
        .take(limit)
        .map((scoredSkill) => scoredSkill.match)
        .toList(growable: false);
    final matchedSignalSet = matches
        .expand((match) => match.matchedSignals)
        .toSet();

    return AgentCodingSkillSelection(
      matches: matches,
      unmatchedSignals: signals
          .where((signal) => !matchedSignalSet.contains(signal))
          .toList(growable: false),
    );
  }

  List<String> _matchedSignals(AgentCodingSkill skill, List<String> signals) {
    final searchable = <String>[
      skill.skillId,
      skill.title,
      ...skill.appliesTo,
      ...skill.toolchainDefaults,
    ].map(_normalizeSignal).toList(growable: false);

    return signals
        .where((signal) {
          return searchable.any((candidate) {
            return _signalMatchesCandidate(signal, candidate);
          });
        })
        .toList(growable: false);
  }

  int _scoreSkill(AgentCodingSkill skill, List<String> matchedSignals) {
    var score = matchedSignals.length;
    final appliesTo = skill.appliesTo.map(_normalizeSignal).toSet();
    final title = _normalizeSignal(skill.title);

    for (final signal in matchedSignals) {
      if (appliesTo.any(
        (candidate) => candidate == signal || candidate.contains(signal),
      )) {
        score += 3;
      }

      if (title.contains(signal)) {
        score += 2;
      }
    }

    return score;
  }

  String _pathSignal(String path) {
    final normalizedPath = path.replaceAll('\\', '/').toLowerCase();
    if (normalizedPath.endsWith('.styio')) {
      return 'Styio';
    }
    if (normalizedPath.endsWith('.cc') ||
        normalizedPath.endsWith('.cpp') ||
        normalizedPath.endsWith('.cxx') ||
        normalizedPath.endsWith('.hpp') ||
        normalizedPath.endsWith('.hxx')) {
      return 'C++';
    }
    if (normalizedPath.endsWith('.c') || normalizedPath.endsWith('.h')) {
      return 'C';
    }

    return path;
  }

  String _normalizeSignal(String signal) {
    return signal.trim().toLowerCase();
  }

  bool _signalMatchesCandidate(String signal, String candidate) {
    if (signal == candidate || signal.contains(candidate)) {
      return true;
    }
    return signal.length >= 8 && candidate.contains(signal);
  }
}

class _ScoredSkill {
  const _ScoredSkill({required this.index, required this.match});

  final int index;
  final AgentCodingSkillMatch match;
}
