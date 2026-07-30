import 'context_key_service.dart';

enum IdeSurfacePlacement {
  primarySideBar,
  secondarySideBar,
  bottomPanel,
  editorAuxiliary,
  modal,
}

class IdeSurfaceDescriptor {
  const IdeSurfaceDescriptor({
    required this.id,
    required this.label,
    required this.placement,
    this.order = 0,
    this.preconditions = const <ContextKeyExpression>[],
  });

  final String id;
  final String label;
  final IdeSurfacePlacement placement;
  final int order;
  final List<ContextKeyExpression> preconditions;

  bool isVisible(ContextKeyService contextKeys) {
    return contextKeys.matchesAll(preconditions);
  }
}

class SurfaceRegistry {
  SurfaceRegistry({
    Iterable<IdeSurfaceDescriptor> descriptors = const <IdeSurfaceDescriptor>[],
  }) {
    for (final descriptor in descriptors) {
      register(descriptor);
    }
  }

  final Map<String, IdeSurfaceDescriptor> _descriptors =
      <String, IdeSurfaceDescriptor>{};

  List<IdeSurfaceDescriptor> get surfaces {
    return _sorted(_descriptors.values);
  }

  bool contains(String id) => _descriptors.containsKey(id);

  IdeSurfaceDescriptor descriptorFor(String id) {
    final descriptor = _descriptors[id];
    if (descriptor == null) {
      throw StateError('Surface `$id` is not registered.');
    }
    return descriptor;
  }

  void register(IdeSurfaceDescriptor descriptor) {
    if (_descriptors.containsKey(descriptor.id)) {
      throw StateError('Surface `${descriptor.id}` is already registered.');
    }
    _descriptors[descriptor.id] = descriptor;
  }

  bool unregister(String id) {
    return _descriptors.remove(id) != null;
  }

  List<IdeSurfaceDescriptor> visibleSurfaces(
    ContextKeyService contextKeys, {
    IdeSurfacePlacement? placement,
  }) {
    final descriptors = _descriptors.values.where((descriptor) {
      if (placement != null && descriptor.placement != placement) {
        return false;
      }
      return descriptor.isVisible(contextKeys);
    });
    return _sorted(descriptors);
  }

  List<IdeSurfaceDescriptor> _sorted(
    Iterable<IdeSurfaceDescriptor> descriptors,
  ) {
    return descriptors.toList(growable: false)
      ..sort((left, right) {
        final orderCompare = left.order.compareTo(right.order);
        if (orderCompare != 0) {
          return orderCompare;
        }
        return left.id.compareTo(right.id);
      });
  }
}
