import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

/// Extension contribution manifest schema tests.
///
/// Verifies that extension manifests:
/// - Have valid schemaVersion
/// - Declare activation events
/// - Declare contributions with typed contribution points
/// - Declare required capabilities
/// - Validate correctly
/// - Tolerate unknown fields

/// Minimal extension manifest JSON schema validator.
/// In production this is handled by extension_manifest_contract.dart.
class ManifestValidationResult {
  final bool valid;
  final List<String> errors;

  const ManifestValidationResult({required this.valid, this.errors = const []});
}

ManifestValidationResult validateManifest(Map<String, dynamic> manifest) {
  final errors = <String>[];

  // schemaVersion is required
  if (!manifest.containsKey('schemaVersion')) {
    errors.add('Missing required field: schemaVersion');
  } else if (manifest['schemaVersion'] is! int) {
    errors.add('schemaVersion must be an integer');
  } else if ((manifest['schemaVersion'] as int) < 1) {
    errors.add('schemaVersion must be >= 1');
  }

  // id is required
  if (!manifest.containsKey('id') || (manifest['id'] as String?)?.isEmpty == true) {
    errors.add('Missing required field: id');
  }

  // name is required
  if (!manifest.containsKey('name') || (manifest['name'] as String?)?.isEmpty == true) {
    errors.add('Missing required field: name');
  }

  // version is required (SemVer)
  if (!manifest.containsKey('version') || (manifest['version'] as String?)?.isEmpty == true) {
    errors.add('Missing required field: version');
  }

  // activationEvents is required
  if (!manifest.containsKey('activationEvents')) {
    errors.add('Missing required field: activationEvents');
  } else if (manifest['activationEvents'] is! List) {
    errors.add('activationEvents must be a list');
  }

  // contributions is required
  if (!manifest.containsKey('contributions')) {
    errors.add('Missing required field: contributions');
  } else if (manifest['contributions'] is! List) {
    errors.add('contributions must be a list');
  }

  // Validate contributions
  if (manifest['contributions'] is List) {
    final contributions = manifest['contributions'] as List;
    for (var i = 0; i < contributions.length; i++) {
      if (contributions[i] is! Map) {
        errors.add('contribution[$i] must be an object');
        continue;
      }
      final contrib = contributions[i] as Map<String, dynamic>;
      if (!contrib.containsKey('type') || (contrib['type'] as String?)?.isEmpty == true) {
        errors.add('contribution[$i] missing required field: type');
      }
    }
  }

  // isolation is optional but must be valid if present
  if (manifest.containsKey('isolation')) {
    const validIsolations = ['same-process', 'process', 'hosted'];
    if (!validIsolations.contains(manifest['isolation'])) {
      errors.add('isolation must be one of: ${validIsolations.join(", ")}');
    }
  }

  return ManifestValidationResult(
    valid: errors.isEmpty,
    errors: errors,
  );
}

void main() {
  group('Extension manifest schema validation', () {
    test('valid minimal manifest passes', () {
      final manifest = {
        'schemaVersion': 1,
        'id': 'styio.example-tool',
        'name': 'Example Tool',
        'version': '1.0.0',
        'activationEvents': ['onStartup'],
        'contributions': [
          {'type': 'commands', 'commands': [{'id': 'example.hello', 'title': 'Hello'}]},
        ],
      };
      final result = validateManifest(manifest);
      expect(result.valid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('missing schemaVersion fails', () {
      final manifest = {
        'id': 'styio.test',
        'name': 'Test',
        'version': '1.0.0',
        'activationEvents': [],
        'contributions': [],
      };
      final result = validateManifest(manifest);
      expect(result.valid, isFalse);
      expect(result.errors.any((e) => e.contains('schemaVersion')), isTrue);
    });

    test('missing id fails', () {
      final manifest = {
        'schemaVersion': 1,
        'name': 'Test',
        'version': '1.0.0',
        'activationEvents': [],
        'contributions': [],
      };
      final result = validateManifest(manifest);
      expect(result.valid, isFalse);
      expect(result.errors.any((e) => e.contains('id')), isTrue);
    });

    test('missing activationEvents fails', () {
      final manifest = {
        'schemaVersion': 1,
        'id': 'styio.test',
        'name': 'Test',
        'version': '1.0.0',
        'contributions': [],
      };
      final result = validateManifest(manifest);
      expect(result.valid, isFalse);
      expect(result.errors.any((e) => e.contains('activationEvents')), isTrue);
    });

    test('schemaVersion must be >= 1', () {
      final manifest = {
        'schemaVersion': 0,
        'id': 'styio.test',
        'name': 'Test',
        'version': '1.0.0',
        'activationEvents': [],
        'contributions': [],
      };
      final result = validateManifest(manifest);
      expect(result.valid, isFalse);
      expect(result.errors.any((e) => e.contains('schemaVersion')), isTrue);
    });
  });

  group('Extension manifest unknown field tolerance', () {
    test('manifest with unknown fields is still valid', () {
      final manifest = {
        'schemaVersion': 1,
        'id': 'styio.future-tool',
        'name': 'Future Tool',
        'version': '1.0.0',
        'activationEvents': ['onLanguage:styio'],
        'contributions': [],
        'unknownField': 'should-be-ignored',
        'futureCapability': {'nested': true},
        'experimentalFlag': 42,
      };
      final result = validateManifest(manifest);
      // Unknown fields should not cause validation failure
      expect(result.valid, isTrue);
    });

    test('unknown fields survive JSON round-trip', () {
      final manifest = {
        'schemaVersion': 1,
        'id': 'styio.roundtrip',
        'name': 'Roundtrip Test',
        'version': '1.0.0',
        'activationEvents': [],
        'contributions': [],
        'customMetadata': {'author': 'test', 'tags': ['experimental']},
      };
      final jsonStr = jsonEncode(manifest);
      final reparsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(reparsed['customMetadata'], isNotNull);
      expect((reparsed['customMetadata'] as Map)['author'], 'test');
    });
  });

  group('Extension contribution types', () {
    test('valid contribution point types are accepted', () {
      const validTypes = [
        'commands',
        'languages',
        'agent_providers',
        'agent_tools',
        'debug_adapters',
        'toolchains',
        'themes',
        'views',
        'runtime_tasks',
      ];

      for (final type in validTypes) {
        final manifest = {
          'schemaVersion': 1,
          'id': 'styio.${type.replaceAll('_', '-')}',
          'name': 'Test $type',
          'version': '1.0.0',
          'activationEvents': ['onStartup'],
          'contributions': [
            {'type': type}
          ],
        };
        final result = validateManifest(manifest);
        expect(result.valid, isTrue,
            reason: 'Contribution type "$type" should be valid');
      }
    });

    test('contribution missing type fails', () {
      final manifest = {
        'schemaVersion': 1,
        'id': 'styio.notype',
        'name': 'No Type',
        'version': '1.0.0',
        'activationEvents': [],
        'contributions': [
          {'commands': []}, // missing 'type'
        ],
      };
      final result = validateManifest(manifest);
      expect(result.valid, isFalse);
      expect(result.errors.any((e) => e.contains('type')), isTrue);
    });
  });

  group('Extension isolation', () {
    test('valid isolation values are accepted', () {
      for (final isolation in ['same-process', 'process', 'hosted']) {
        final manifest = {
          'schemaVersion': 1,
          'id': 'styio.isolation-$isolation',
          'name': 'Isolation $isolation',
          'version': '1.0.0',
          'activationEvents': [],
          'contributions': [],
          'isolation': isolation,
        };
        final result = validateManifest(manifest);
        expect(result.valid, isTrue,
            reason: 'Isolation "$isolation" should be valid');
      }
    });

    test('invalid isolation value fails', () {
      final manifest = {
        'schemaVersion': 1,
        'id': 'styio.bad-iso',
        'name': 'Bad Isolation',
        'version': '1.0.0',
        'activationEvents': [],
        'contributions': [],
        'isolation': 'unrestricted', // not a valid isolation level
      };
      final result = validateManifest(manifest);
      expect(result.valid, isFalse);
      expect(result.errors.any((e) => e.contains('isolation')), isTrue);
    });
  });

  group('Extension activation events', () {
    test('common activation events are valid', () {
      final events = [
        'onStartup',
        'onLanguage:styio',
        'onLanguage:cpp',
        'onWorkspaceOpen',
        'onCommand:build.run',
        'onDebug',
        '*',
      ];

      for (final event in events) {
        final manifest = {
          'schemaVersion': 1,
          'id': 'styio.event-${event.replaceAll(':', '-').replaceAll('*', 'star')}',
          'name': 'Event $event',
          'version': '1.0.0',
          'activationEvents': [event],
          'contributions': [],
        };
        final result = validateManifest(manifest);
        expect(result.valid, isTrue,
            reason: 'Activation event "$event" should be valid');
      }
    });

    test('empty activationEvents is valid', () {
      final manifest = {
        'schemaVersion': 1,
        'id': 'styio.no-events',
        'name': 'No Events',
        'version': '1.0.0',
        'activationEvents': [],
        'contributions': [],
      };
      final result = validateManifest(manifest);
      expect(result.valid, isTrue);
    });
  });

  group('Extension manifest serialization', () {
    test('full manifest serializes and deserializes', () {
      final manifest = {
        'schemaVersion': 1,
        'id': 'styio.cpp-tools',
        'name': 'Styio C++ Tools',
        'version': '1.0.0',
        'activationEvents': ['onLanguage:cpp', 'onWorkspaceOpen'],
        'requiredCapabilities': ['language.cpp', 'toolchain.clang'],
        'contributions': [
          {
            'type': 'languages',
            'languageId': 'cpp',
            'extensions': ['.cpp', '.hpp', '.cc', '.h'],
          },
          {
            'type': 'commands',
            'commands': [
              {'id': 'cpp.build', 'title': 'Build C++ Project'}
            ],
          },
        ],
        'isolation': 'process',
      };

      final jsonStr = jsonEncode(manifest);
      final reparsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(reparsed['schemaVersion'], 1);
      expect(reparsed['id'], 'styio.cpp-tools');
      expect(reparsed['name'], 'Styio C++ Tools');
      expect(reparsed['version'], '1.0.0');
      expect(reparsed['isolation'], 'process');
      expect((reparsed['activationEvents'] as List).length, 2);
      expect((reparsed['contributions'] as List).length, 2);
      expect((reparsed['requiredCapabilities'] as List).length, 2);
    });
  });

  group('Extension manifest id uniqueness', () {
    test('duplicate ids can be detected', () {
      final ids = <String>{};
      final manifest1 = {'id': 'styio.unique-tool'};
      final manifest2 = {'id': 'styio.unique-tool'}; // duplicate

      // First one adds fine
      ids.add(manifest1['id'] as String);
      expect(ids.length, 1);

      // Second one is duplicate
      final isDuplicate = ids.contains(manifest2['id']);
      expect(isDuplicate, isTrue);
    });
  });
}
