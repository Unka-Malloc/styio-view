import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/workbench/workbench.dart';

void main() {
  test('context key service evaluates typed values and expressions', () {
    const hasProject = ContextKey<bool>(
      id: 'styio.hasProject',
      defaultValue: false,
    );
    final contextKeys = ContextKeyService();

    expect(contextKeys.valueFor(hasProject), isFalse);

    contextKeys.setValue(hasProject, true);

    expect(contextKeys.valueFor(hasProject), isTrue);
    expect(
      contextKeys.matchesAll(const <ContextKeyExpression>[
        ContextKeyExpression.equals(key: 'styio.hasProject', value: true),
      ]),
      isTrue,
    );
    expect(contextKeys.snapshot()['styio.hasProject'], isTrue);
  });

  test('context key expressions parse compound enablement rules', () {
    final contextKeys = ContextKeyService()
      ..setActiveEditor(editorId: 'src/main.styio', languageId: 'styio')
      ..setWorkspaceTrust(true)
      ..setWorkspaceIndexReady(true)
      ..setRawValue('runtime.taskCount', 3)
      ..setRawValue('workbench.features', <String>['debug', 'agent']);
    final expression = ContextKeyExpression.parse(
      "workbench.hasActiveEditor && "
      "editor.activeLanguageId in ['styio', 'dart'] && "
      'runtime.taskCount >= 2 && '
      "workbench.features contains 'debug' && "
      'not editor.hasSelection',
    );

    expect(contextKeys.matches(expression), isTrue);
    expect(
      ContextKeyExpression.fromJson(expression.toJson()).evaluate(contextKeys),
      isTrue,
    );

    contextKeys.setRawValue('runtime.taskCount', 1);

    expect(contextKeys.matches(expression), isFalse);
  });

  test('context key expression parser reports invalid input diagnostics', () {
    final result = ContextKeyExpression.tryParse(
      'workspace.isTrusted && == true',
    );

    expect(result.isValid, isFalse);
    expect(result.expression, isNull);
    expect(result.diagnostics, isNotEmpty);
    expect(
      () => ContextKeyExpression.parse('workspace.isTrusted && == true'),
      throwsFormatException,
    );
  });

  test('surface registry filters by context and keeps stable order', () {
    const hasProject = ContextKey<bool>(
      id: 'styio.hasProject',
      defaultValue: false,
    );
    final contextKeys = ContextKeyService();
    final registry = SurfaceRegistry(
      descriptors: const <IdeSurfaceDescriptor>[
        IdeSurfaceDescriptor(
          id: 'agent',
          label: 'Agent',
          placement: IdeSurfacePlacement.secondarySideBar,
          order: 20,
        ),
        IdeSurfaceDescriptor(
          id: 'runtime',
          label: 'Runtime',
          placement: IdeSurfacePlacement.bottomPanel,
          order: 10,
          preconditions: <ContextKeyExpression>[
            ContextKeyExpression.equals(key: 'styio.hasProject', value: true),
          ],
        ),
      ],
    );

    expect(registry.contains('runtime'), isTrue);
    expect(registry.visibleSurfaces(contextKeys).map((surface) => surface.id), [
      'agent',
    ]);

    contextKeys.setValue(hasProject, true);

    expect(registry.visibleSurfaces(contextKeys).map((surface) => surface.id), [
      'runtime',
      'agent',
    ]);
    expect(
      registry
          .visibleSurfaces(
            contextKeys,
            placement: IdeSurfacePlacement.bottomPanel,
          )
          .map((surface) => surface.id),
      ['runtime'],
    );
    expect(
      () => registry.register(registry.descriptorFor('runtime')),
      throwsStateError,
    );
  });
  group('Registry manifest projection', () {
    test('ide capability registry snapshot is metadata-only (no runtime values)', () {
      final registry = IdeCapabilityRegistry(descriptors: [
        const IdeCapabilityDescriptor(
          capabilityId: 'test.command',
          domain: IdeCapabilityDomain.workbench,
          label: 'Test Command',
          description: 'A test command capability.',
        ),
      ]);

      final snapshot = registry.toSnapshot();
      final entryJson = snapshot.toJson();

      // Must contain metadata keys
      expect(entryJson['totalCount'], 1);
      expect(entryJson['availableCount'], isA<int>());
      expect(entryJson['blockedCount'], isA<int>());
      expect(entryJson['byDomain'], isA<Map<String, Object?>>());
      expect(entryJson['generatedAtIso8601'], isA<String>());

      // Must NOT leak runtime handler closures or registrations
      expect(entryJson.containsKey('handler'), isFalse,
          reason: 'Snapshot must not leak runtime handler closures');
      expect(entryJson.containsKey('rawRuntimeValues'), isFalse,
          reason: 'Snapshot must not leak raw runtime instances');
    });

        test('ide capability descriptor is serializable without runtime values', () {
      const descriptor = IdeCapabilityDescriptor(
        capabilityId: 'language.diagnostics',
        domain: IdeCapabilityDomain.languageIntelligence,
        label: 'Diagnostics',
        description: 'Real-time diagnostics from language service.',
        maturity: IdeCapabilityMaturity.l2ContractBacked,
        availability: IdeCapabilityAvailability.previewOnly,
        blockedReason: 'Upstream StyioService contract is preview only.',
        ownerBoundary: 'LanguageServiceAdapter',
        relatedCommandIds: [AppCommandId.showWorkspaceProblems],
        requiredCapabilities: ['service.styio-language'],
        upstreamContract: 'styio-service/diagnostics',
      );

      final json = descriptor.toJson();

      expect(json['capabilityId'], 'language.diagnostics');
      expect(json['domain'], 'languageIntelligence');
      expect(json['label'], 'Diagnostics');
      expect(json['maturity'], 'l2ContractBacked');
      expect(json['availability'], 'previewOnly');
      expect(json['blockedReason'], isNotEmpty);
      expect(json['ownerBoundary'], 'LanguageServiceAdapter');
      expect(json['isAvailable'], isFalse);
      expect(json['isUsable'], isTrue);
      expect(json['upstreamContract'], 'styio-service/diagnostics');

      // Must NOT contain runtime closures
      expect(json.containsKey('handler'), isFalse);
      expect(json.containsKey('callback'), isFalse);
    });
test('surface registry manifest projection is metadata-only', () {
      final registry = SurfaceRegistry(
        descriptors: const <IdeSurfaceDescriptor>[
          IdeSurfaceDescriptor(
            id: 'agent',
            label: 'Agent',
            placement: IdeSurfacePlacement.secondarySideBar,
            order: 20,
          ),
          IdeSurfaceDescriptor(
            id: 'runtime',
            label: 'Runtime',
            placement: IdeSurfacePlacement.bottomPanel,
            order: 10,
          ),
        ],
      );

      expect(registry.contains('agent'), isTrue);
      expect(registry.contains('runtime'), isTrue);
      // Surface descriptors are themselves metadata-only (no runtime closures)
      final agent = registry.descriptorFor('agent');
      expect(agent.id, 'agent');
      expect(agent.label, 'Agent');
      // No runtime handlers exposed
    });
  });
}