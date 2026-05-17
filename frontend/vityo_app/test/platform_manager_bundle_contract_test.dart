import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';

void main() {
  test(
    'platform manager bundle exposes the complete system manager contract',
    () async {
      final bundle = await createDetectedPlatformManagerBundle(
        targetId: 'platform-manager-contract-test',
      );
      final snapshot = bundle.snapshot();

      expect(snapshot.targetId, 'platform-manager-contract-test');
      expect(snapshot.managerKeys, <String>[
        'fileSystem',
        'shell',
        'process',
        'resource',
        'network',
        'clipboard',
        'notification',
        'localService',
        'pty',
      ]);
      expect(bundle.fileSystem.compatibility, isNotNull);
      expect(bundle.shell.compatibility, isNotNull);
      expect(bundle.process.compatibility, isNotNull);
      expect(bundle.resource.compatibility, isNotNull);
      expect(bundle.network.compatibility, isNotNull);
      expect(bundle.clipboard.compatibility, isNotNull);
      expect(bundle.notification.compatibility, isNotNull);
      expect(bundle.localService.compatibility, isNotNull);
      expect(bundle.pty.compatibility, isNotNull);
    },
  );
}
