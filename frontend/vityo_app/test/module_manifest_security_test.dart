import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/module_host/module_manifest.dart';
import 'package:vityo_app/src/module_host/module_manifest_security.dart';

void main() {
  test('manifest security validator accepts signed supply-chain schema', () {
    final manifest = _signedManifest();

    final result = _validator().validateJson(manifest);

    expect(result.isValid, isTrue);
    expect(result.toJson()['valid'], isTrue);
  });

  test(
    'module parser feeds activation and contribution schema to validator',
    () {
      final module = ModuleManifest.parse(
        jsonEncode(<String, Object?>{
          'moduleId': 'agent.surface.basic',
          'displayName': 'Agent Surface',
          'version': '1.2.3',
          'kind': 'optional',
          'slot': 'agentSurface',
          'description': 'Agent host',
          'enabledByDefault': true,
          'entrypoint': 'lib/src/agent/agent_surface.dart',
          'distributionPolicyRef': 'signed-marketplace',
          'extension': <String, Object?>{
            'activationEvents': <Object?>['onStartup', 'bad event'],
            'metadata': <String, Object?>{
              'permissions': <String>['file.read'],
              'platforms': <String>['macos'],
            },
            'contributions': <Object?>[
              <String, Object?>{
                'kind': 'agent',
                'id': 'bad id',
                'target': 'agent.tools',
              },
            ],
          },
          'capabilityFlags': <String, Object?>{'agentPanel': true},
        }),
      );

      final result = _validator().validateModule(module);

      expect(result.hasCode(ModuleManifestSecurityCode.invalidActivation), isTrue);
      expect(
        result.hasCode(ModuleManifestSecurityCode.invalidContribution),
        isTrue,
      );
    },
  );

  test('validator reports schema and policy blockers by code', () {
    final manifest = _signedManifest()
      ..['id'] = 'Bad Id'
      ..['publisher'] = 'Bad Publisher'
      ..['version'] = '1.0'
      ..['engine'] = '>=bad'
      ..['activation'] = <Object?>['onStartup', 'bad event']
      ..['contributions'] = <Object?>[
        <String, Object?>{
          'kind': 'agent',
          'id': 'bad id',
          'target': 'agent.tools',
        },
        42,
      ]
      ..['permissions'] = <String>['file.read', 'workspace.admin']
      ..['platforms'] = <String>['ios']
      ..['checksum'] = 'sha256:${List<String>.filled(64, '0').join()}'
      ..['channel'] = 'canary'
      ..remove('signature');

    final result = _validator().validateJson(manifest);

    expect(result.hasCode(ModuleManifestSecurityCode.invalidIdentifier), isTrue);
    expect(result.hasCode(ModuleManifestSecurityCode.invalidVersion), isTrue);
    expect(result.hasCode(ModuleManifestSecurityCode.invalidActivation), isTrue);
    expect(
      result.hasCode(ModuleManifestSecurityCode.invalidContribution),
      isTrue,
    );
    expect(result.hasCode(ModuleManifestSecurityCode.invalidPermission), isTrue);
    expect(
      result.hasCode(ModuleManifestSecurityCode.platformUnsupported),
      isTrue,
    );
    expect(result.hasCode(ModuleManifestSecurityCode.channelUnsupported), isTrue);
    expect(result.hasCode(ModuleManifestSecurityCode.checksumMismatch), isTrue);
    expect(result.hasCode(ModuleManifestSecurityCode.signatureMissing), isTrue);
  });

  test('validator reports missing and failed signatures distinctly', () {
    final missingSignature = _signedManifest()..remove('signature');
    final invalidSignature = _signedManifest()..['signature'] = 'tampered';

    final missing = _validator().validateJson(missingSignature);
    final invalid = _validator().validateJson(invalidSignature);

    expect(missing.hasCode(ModuleManifestSecurityCode.signatureMissing), isTrue);
    expect(missing.hasCode(ModuleManifestSecurityCode.signatureInvalid), isFalse);
    expect(invalid.hasCode(ModuleManifestSecurityCode.signatureInvalid), isTrue);
    expect(invalid.hasCode(ModuleManifestSecurityCode.checksumMismatch), isFalse);
  });

  test('validator blocks incompatible engine versions', () {
    final manifest = _signedManifest(<String, Object?>{
      'engine': '>=2.0.0 <3.0.0',
    });

    final result = _validator().validateJson(manifest);

    expect(
      result.hasCode(ModuleManifestSecurityCode.engineVersionIncompatible),
      isTrue,
    );
    expect(result.hasCode(ModuleManifestSecurityCode.signatureInvalid), isFalse);
  });

  test('manifest security state exposes quarantine and rollback status', () {
    const issue = ModuleManifestSecurityIssue(
      code: ModuleManifestSecurityCode.invalidPermission,
      field: 'permissions',
      message: 'Permission `workspace.admin` is not allowed by policy.',
    );
    const result = ModuleManifestSecurityResult(
      issues: <ModuleManifestSecurityIssue>[issue],
    );

    final state = ModuleManifestSecurityState.fromValidation(
      moduleId: 'agent.surface.basic',
      version: '2.0.0',
      result: result,
      rollbackVersion: '1.9.0',
    );
    final rolledBack = state.markRolledBack(reason: 'Restored trusted build.');

    expect(state.quarantined, isTrue);
    expect(state.rollbackAvailable, isTrue);
    expect(state.canActivate, isFalse);
    expect(state.toJson()['status'], 'quarantined');
    expect(rolledBack.rolledBack, isTrue);
    expect(rolledBack.activeVersion, '1.9.0');
    expect(rolledBack.toJson()['status'], 'rolled-back');
  });
}

Map<String, Object?> _baseManifest() {
  return <String, Object?>{
    'id': 'agent.surface.basic',
    'publisher': 'vityo',
    'version': '1.2.3',
    'engine': '>=1.0.0 <2.0.0',
    'activation': <String>['onStartup', 'onLanguage:styio'],
    'contributions': <Map<String, Object?>>[
      <String, Object?>{
        'kind': 'agent',
        'id': 'collect-agent-surface-context',
        'target': 'agent.tools',
      },
    ],
    'permissions': <String>['file.read', 'network'],
    'platforms': <String>['macos', 'web'],
    'channel': 'stable',
    'entrypoint': 'lib/src/agent/agent_surface.dart',
    'distributionPolicyRef': 'signed-marketplace',
  };
}

Map<String, Object?> _signedManifest([
  Map<String, Object?> overrides = const <String, Object?>{},
]) {
  final manifest = _baseManifest()..addAll(overrides);
  final canonical = canonicalModuleManifestJson(manifest);
  manifest['checksum'] = 'sha256:${sha256.convert(utf8.encode(canonical))}';
  manifest['signature'] = _signatureFor(canonical);
  return manifest;
}

ModuleManifestSecurityValidator _validator() {
  return ModuleManifestSecurityValidator(
    policy: const ModuleManifestSecurityPolicy(
      requireActivation: true,
      allowedPermissions: <String>{'file.read', 'network'},
      allowedChannels: <String>{'stable', 'nightly'},
      platform: 'macos',
      currentEngineVersion: '1.5.0',
    ),
    signatureVerifier:
        ({
          required String canonicalManifestJson,
          required String signature,
          String? algorithm,
          String? keyId,
        }) {
          return signature == _signatureFor(canonicalManifestJson);
        },
  );
}

String _signatureFor(String canonicalManifestJson) {
  final digest = sha256.convert(
    utf8.encode('module-manifest-signature:$canonicalManifestJson'),
  );
  return 'test-ed25519:$digest';
}
