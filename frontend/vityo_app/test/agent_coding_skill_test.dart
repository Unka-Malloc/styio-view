import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';

void main() {
  test('agent coding skills use capability facts instead of TODO prompts', () {
    final skills = AgentCodingSkillCatalog.defaultSkills;
    final encoded = skills
        .expand(
          (skill) => <String>[
            ...skill.toolchainDefaults,
            ...skill.instructions,
            ...skill.validationHints,
          ],
        )
        .join('\n');

    expect(
      skills.map((skill) => skill.skillId),
      containsAll(<String>[
        'styio-language-service-truth',
        'styio-agent-command-loop',
        'styio-fixture-confidence-matrix',
      ]),
    );
    expect(encoded, contains('unsupported capability facts'));
    expect(encoded, contains('capability readiness'));
    expect(encoded, contains('deferred expectation marker'));
    expect(encoded, isNot(contains('TODO')));
  });
}
