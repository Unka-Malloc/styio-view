import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';

void main() {
  group('Agent role defaults', () {
    test('cover build, plan, general, explore, scout, and review roles', () {
      expect(
        AgentRolePolicy.permissionsFor(AgentRole.build).capabilities,
        unorderedEquals(<AgentCapability>[
          AgentCapability.fileRead,
          AgentCapability.fileWrite,
          AgentCapability.processExec,
        ]),
      );
      expect(
        AgentRolePolicy.permissionsFor(AgentRole.plan).capabilities,
        unorderedEquals(<AgentCapability>[AgentCapability.fileRead]),
      );
      expect(
        AgentRolePolicy.permissionsFor(AgentRole.general).capabilities,
        unorderedEquals(<AgentCapability>[
          AgentCapability.fileRead,
          AgentCapability.fileWrite,
          AgentCapability.processExec,
        ]),
      );
      expect(
        AgentRolePolicy.permissionsFor(AgentRole.explore).capabilities,
        unorderedEquals(<AgentCapability>[AgentCapability.fileRead]),
      );
      expect(
        AgentRolePolicy.permissionsFor(AgentRole.scout).capabilities,
        unorderedEquals(<AgentCapability>[AgentCapability.network]),
      );
      expect(
        AgentRolePolicy.permissionsFor(AgentRole.review).capabilities,
        unorderedEquals(<AgentCapability>[AgentCapability.fileRead]),
      );
    });

    test('default roles do not grant privileged ambient capabilities', () {
      const privileged = <AgentCapability>[
        AgentCapability.secretAccess,
        AgentCapability.moduleInstall,
        AgentCapability.cloudUpload,
        AgentCapability.terminalInteractive,
      ];

      for (final role in AgentRole.values) {
        expect(
          AgentRolePolicy.permissionsFor(role).deniesAll(privileged),
          isTrue,
          reason: '$role must not grant privileged capabilities by default.',
        );
      }
    });
  });

  group('Agent permission lattice', () {
    test('intersect computes the lattice meet', () {
      const readWrite = AgentPermissionSet(<AgentCapability>{
        AgentCapability.fileRead,
        AgentCapability.fileWrite,
      });
      const writeExec = AgentPermissionSet(<AgentCapability>{
        AgentCapability.fileWrite,
        AgentCapability.processExec,
      });

      final meet = readWrite.intersect(writeExec);

      expect(
        meet.capabilities,
        unorderedEquals(<AgentCapability>[AgentCapability.fileWrite]),
      );
      expect(meet.isSubsetOf(readWrite), isTrue);
      expect(meet.isSubsetOf(writeExec), isTrue);
    });

    test('child agent permissions are clamped to role defaults', () {
      const lattice = AgentPermissionLattice();
      final parent = AgentRolePolicy.permissionsFor(AgentRole.build);
      const requested = AgentPermissionSet(<AgentCapability>{
        AgentCapability.fileRead,
        AgentCapability.fileWrite,
        AgentCapability.processExec,
        AgentCapability.network,
      });

      final decision = lattice.deriveChildPermissions(
        parent: parent,
        requestedRole: AgentRole.review,
        requestedPermissions: requested,
      );

      expect(decision.allowed, isTrue);
      expect(
        decision.permissions.capabilities,
        unorderedEquals(<AgentCapability>[AgentCapability.fileRead]),
      );
    });

    test('child agent cannot upgrade beyond parent permissions', () {
      const lattice = AgentPermissionLattice();
      final decision = lattice.deriveChildPermissions(
        parent: AgentRolePolicy.permissionsFor(AgentRole.plan),
        requestedRole: AgentRole.build,
      );

      expect(decision.allowed, isFalse);
      expect(decision.permissions.capabilities, isEmpty);
      expect(
        decision.deniedReason,
        contains('subset of the parent permissions'),
      );
    });
  });

  group('Review role policy', () {
    test('review is read-only', () {
      const lattice = AgentPermissionLattice();
      final review = AgentRolePolicy.permissionsFor(AgentRole.review);
      const reviewWithNetwork = AgentPermissionSet(<AgentCapability>{
        AgentCapability.fileRead,
        AgentCapability.network,
      });

      expect(lattice.isReadOnlyReview(AgentRole.review, review), isTrue);
      expect(
        lattice.isReadOnlyReview(AgentRole.review, reviewWithNetwork),
        isFalse,
      );
      expect(
        lattice.isReadOnlyReview(
          AgentRole.review,
          AgentRolePolicy.permissionsFor(AgentRole.build),
        ),
        isFalse,
      );
      expect(lattice.isReadOnlyReview(AgentRole.plan, review), isFalse);
    });
  });

  group('Provider capability profile', () {
    test('neutral profile excludes provider identity', () {
      const openAiCompatible = AiProviderCapabilityProfile(
        providerId: 'openai-compatible',
        maxInputTokens: 128000,
        retentionPolicy: AiProviderRetentionPolicy.none,
        supportsTools: true,
        supportsStreaming: true,
        networkRequired: true,
        redactionRequired: true,
      );
      const localCompatible = AiProviderCapabilityProfile(
        providerId: 'local-compatible',
        maxInputTokens: 128000,
        retentionPolicy: AiProviderRetentionPolicy.none,
        supportsTools: true,
        supportsStreaming: true,
        networkRequired: true,
        redactionRequired: true,
      );

      expect(
        openAiCompatible.neutralProfile.toJson(),
        localCompatible.neutralProfile.toJson(),
      );
      expect(
        openAiCompatible.neutralProfile.toJson().keys,
        isNot(contains('providerId')),
      );
      expect(openAiCompatible.toJson()['providerId'], 'openai-compatible');
    });
  });

  group('Agent context minimization', () {
    test('redacts common secret shapes before context upload', () {
      const minimizer = AgentContextMinimizer();
      final minimized = minimizer.minimize(
        'OPENAI_API_KEY=sk-env\n'
        'githubToken: ghp-token\n'
        '{"apiKey": "sk-json", "password": "pw-json"}\n'
        'Authorization: Bearer bearer-token\n'
        'https://example.test/callback?token=query-token&safe=1\n',
      );

      expect(minimized, contains('OPENAI_API_KEY=<redacted>'));
      expect(minimized, contains('githubToken: <redacted>'));
      expect(minimized, contains('"apiKey": "<redacted>"'));
      expect(minimized, contains('"password": "<redacted>"'));
      expect(minimized, contains('Authorization: Bearer <redacted>'));
      expect(minimized, contains('?token=<redacted>&safe=1'));
      expect(minimized, isNot(contains('sk-env')));
      expect(minimized, isNot(contains('ghp-token')));
      expect(minimized, isNot(contains('sk-json')));
      expect(minimized, isNot(contains('pw-json')));
      expect(minimized, isNot(contains('bearer-token')));
      expect(minimized, isNot(contains('query-token')));
    });

    test('limits context by UTF-8 byte budget', () {
      const minimizer = AgentContextMinimizer(
        policy: AgentContextPolicy(maxContextBytes: 7),
      );

      final minimized = minimizer.minimize('abc你好def');

      expect(utf8.encode(minimized).length, lessThanOrEqualTo(7));
      expect(minimized, 'abc你');
    });

    test('can preserve secrets for local-only explicit policy', () {
      const minimizer = AgentContextMinimizer(
        policy: AgentContextPolicy(includeSecrets: true),
      );

      expect(minimizer.minimize('TOKEN=local-only'), 'TOKEN=local-only');
    });
  });
}
