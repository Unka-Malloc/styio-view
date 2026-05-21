import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';

void main() {
  test('agent coding skill registry selects Styio skills first', () {
    final selection = const AgentCodingSkillRegistry().selectForContext(
      languages: const <String>['Styio'],
      documentPaths: const <String>['/workspace/demo/src/main.styio'],
      taskHints: const <String>[
        'syntax diagnostics',
        'semantic facts',
        'completion',
      ],
      toolchainHints: const <String>['StyioService'],
    );

    expect(selection.isEmpty, isFalse);
    expect(selection.skillIds.first, 'styio-language-service-truth');
    expect(selection.skillIds, contains('styio-agent-command-loop'));
    expect(selection.skillIds, contains('styio-ide-feature-loop'));
    expect(selection.skillIds, isNot(contains('styio-cpp-compiler-project')));
    expect(selection.promptSections.join('\n'), contains('StyioService'));
    expect(selection.promptSections.join('\n'), contains('SemanticSnapshot'));
    expect(selection.promptSections.join('\n'), contains('suggestedCommandIds'));
    expect(selection.toJson()['matchCount'], greaterThanOrEqualTo(2));
  });

  test('agent coding skill registry selects Styio command loop skill', () {
    final selection = const AgentCodingSkillRegistry().selectForContext(
      taskHints: const <String>[
        'refreshLanguageService',
        'quick fix',
        'agent coding',
      ],
      limit: 3,
    );

    expect(selection.skillIds.first, 'styio-agent-command-loop');
    expect(
      selection.promptSections.join('\n'),
      contains('previewQuickFix before applyQuickFix'),
    );
  });

  test('agent coding skill registry requires explicit compiler signal', () {
    final genericStyio = const AgentCodingSkillRegistry().selectForContext(
      languages: const <String>['Styio'],
      documentPaths: const <String>['/workspace/demo/src/main.styio'],
      limit: 10,
    );
    final compilerStyio = const AgentCodingSkillRegistry().selectForContext(
      taskHints: const <String>['Styio compiler'],
      limit: 10,
    );

    expect(
      genericStyio.skillIds,
      isNot(contains('styio-cpp-compiler-project')),
    );
    expect(compilerStyio.skillIds, contains('styio-cpp-compiler-project'));
  });

  test(
    'agent coding skill registry maps document paths to language signals',
    () {
      final selection = const AgentCodingSkillRegistry().selectForContext(
        documentPaths: const <String>['/workspace/styio/src/parser.styio'],
        limit: 1,
      );

      expect(selection.skillIds, <String>['styio-language-service-truth']);
      expect(selection.unmatchedSignals, isEmpty);
    },
  );

  test('agent coding skill registry preserves unmatched signals', () {
    final selection = const AgentCodingSkillRegistry().selectForContext(
      taskHints: const <String>['unmapped-zeta-needle'],
    );

    expect(selection.isEmpty, isTrue);
    expect(selection.unmatchedSignals, <String>['unmapped-zeta-needle']);
  });
}
