@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/default_backend_providers.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';

void main() {
  test('web build registers only the hosted Web backend provider', () {
    final registry = createDefaultBackendProviderRegistry();

    expect(registry.providers, hasLength(1));
    expect(registry.resolve(PlatformTarget.web).id, 'web.hosted');
    expect(
      () => registry.resolve(PlatformTarget.windows),
      throwsA(isA<StateError>()),
    );
  });
}
