import 'package:flutter_test/flutter_test.dart';
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
      contextKeys.matchesAll(
        const <ContextKeyExpression>[
          ContextKeyExpression.equals(
            key: 'styio.hasProject',
            value: true,
          ),
        ],
      ),
      isTrue,
    );
    expect(contextKeys.snapshot()['styio.hasProject'], isTrue);
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
            ContextKeyExpression.equals(
              key: 'styio.hasProject',
              value: true,
            ),
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
}
