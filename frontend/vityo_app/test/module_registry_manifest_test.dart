import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';

void main() {
  test('module manifest parses wire values and capability flags', () {
    final manifest = ModuleManifest.parse(
      jsonEncode(<String, Object?>{
        'moduleId': 'core.editor',
        'displayName': 'Editor',
        'version': '1.0.0',
        'kind': 'core',
        'slot': 'editor',
        'description': 'Editor module',
        'enabledByDefault': true,
        'entrypoint': 'editor.dart',
        'distributionPolicyRef': 'bundled',
        'capabilityFlags': <String, Object?>{
          'offline': true,
          'experimental': false,
          'truthy-string': 'yes',
        },
      }),
    );

    expect(manifest.moduleId, 'core.editor');
    expect(manifest.kind, ModuleKind.core);
    expect(manifest.kind.wireValue, 'core');
    expect(manifest.slot, ModuleSlot.editor);
    expect(manifest.slot.wireValue, 'editor');
    expect(manifest.enabledByDefault, isTrue);
    expect(manifest.capabilityFlags, <String, bool>{
      'offline': true,
      'experimental': false,
      'truthy-string': false,
    });
  });

  test('module manifest rejects unknown kind and slot wire values', () {
    expect(() => moduleKindFromWireValue('plugin'), throwsFormatException);
    expect(() => moduleSlotFromWireValue('sidebar'), throwsFormatException);
  });

  test('capability matrix parses platform rules and default fallback', () {
    final matrix = ModuleCapabilityMatrix.parse(
      jsonEncode(<String, Object?>{
        'moduleId': 'core.editor',
        'platforms': <String, Object?>{
          'web': <String, Object?>{
            'supported': true,
            'visible': true,
            'installable': false,
            'mountedByDefault': true,
            'iosSafe': true,
            'distributionChannel': 'bundled',
            'note': 'Web shell',
          },
          'ios': <String, Object?>{
            'supported': true,
            'visible': false,
            'installable': false,
            'mountedByDefault': true,
          },
        },
      }),
    );

    expect(matrix.ruleFor(PlatformTarget.web).supported, isTrue);
    expect(matrix.ruleFor(PlatformTarget.web).note, 'Web shell');
    expect(matrix.isVisibleOn(PlatformTarget.web), isTrue);
    expect(matrix.isMountedOn(PlatformTarget.web), isTrue);
    expect(matrix.isVisibleOn(PlatformTarget.ios), isFalse);
    expect(matrix.isMountedOn(PlatformTarget.ios), isFalse);
    expect(matrix.ruleFor(PlatformTarget.android).supported, isFalse);
    expect(matrix.ruleFor(PlatformTarget.android).note, 'No platform rule found.');
    expect(platformTargetFromWireValue('beos'), PlatformTarget.unknown);
  });

  test('module registry filters visible, mounted, slots, and ids', () {
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.web,
      definitions: <ModuleDefinition>[
        _definition(
          moduleId: 'core.editor',
          slot: ModuleSlot.editor,
          visible: true,
          mountedByDefault: true,
        ),
        _definition(
          moduleId: 'optional.agent',
          slot: ModuleSlot.agentSurface,
          visible: true,
          mountedByDefault: false,
        ),
        _definition(
          moduleId: 'hidden.debug',
          slot: ModuleSlot.debugTools,
          visible: false,
          mountedByDefault: true,
        ),
      ],
    );

    expect(registry.allModules, hasLength(3));
    expect(
      registry.visibleModules.map((definition) => definition.manifest.moduleId),
      <String>['core.editor', 'optional.agent'],
    );
    expect(
      registry.mountedModules.map((definition) => definition.manifest.moduleId),
      <String>['core.editor'],
    );
    expect(
      registry
          .modulesForSlot(ModuleSlot.agentSurface)
          .single
          .manifest
          .moduleId,
      'optional.agent',
    );
    expect(registry.findById('hidden.debug'), isNotNull);
    expect(registry.isMounted('missing'), isFalse);
  });

  test('module registry loads module definitions from asset index', () async {
    final bundle = _MemoryAssetBundle(<String, String>{
      'assets/modules/index.json': jsonEncode(<String, Object?>{
        'modules': <Object?>[
          <String, Object?>{
            'manifest': 'assets/modules/editor.manifest.json',
            'matrix': 'assets/modules/editor.matrix.json',
          },
        ],
      }),
      'assets/modules/editor.manifest.json': _manifestSource(
        moduleId: 'core.editor',
        slot: ModuleSlot.editor,
      ),
      'assets/modules/editor.matrix.json': _matrixSource(
        moduleId: 'core.editor',
        visible: true,
        mountedByDefault: true,
      ),
    });

    final registry = await ModuleRegistry.loadFromAssets(
      indexAssetPath: 'assets/modules/index.json',
      platformTarget: PlatformTarget.web,
      bundle: bundle,
    );

    expect(registry.allModules, hasLength(1));
    expect(registry.visibleModules.single.manifest.displayName, 'core.editor');
    expect(registry.isMounted('core.editor'), isTrue);
  });
}

ModuleDefinition _definition({
  required String moduleId,
  required ModuleSlot slot,
  required bool visible,
  required bool mountedByDefault,
}) {
  return ModuleDefinition(
    manifest: ModuleManifest.parse(_manifestSource(moduleId: moduleId, slot: slot)),
    matrix: ModuleCapabilityMatrix.parse(
      _matrixSource(
        moduleId: moduleId,
        visible: visible,
        mountedByDefault: mountedByDefault,
      ),
    ),
  );
}

String _manifestSource({
  required String moduleId,
  required ModuleSlot slot,
}) {
  return jsonEncode(<String, Object?>{
    'moduleId': moduleId,
    'displayName': moduleId,
    'version': '1.0.0',
    'kind': moduleId.startsWith('core.') ? 'core' : 'optional',
    'slot': slot.wireValue,
    'description': '$moduleId test module',
    'enabledByDefault': true,
    'entrypoint': '$moduleId.dart',
    'distributionPolicyRef': 'test',
    'capabilityFlags': <String, Object?>{},
  });
}

String _matrixSource({
  required String moduleId,
  required bool visible,
  required bool mountedByDefault,
}) {
  return jsonEncode(<String, Object?>{
    'moduleId': moduleId,
    'platforms': <String, Object?>{
      'web': <String, Object?>{
        'supported': true,
        'visible': visible,
        'installable': true,
        'mountedByDefault': mountedByDefault,
        'iosSafe': true,
        'distributionChannel': 'bundled',
        'note': '$moduleId web rule',
      },
    },
  });
}

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this._assets);

  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final source = _assets[key];
    if (source == null) {
      throw StateError('Missing asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source)));
  }
}
