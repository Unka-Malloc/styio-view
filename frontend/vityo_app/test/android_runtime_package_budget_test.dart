import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

void main() {
  test('android runtime package budget accepts artifacts up to 50 MB', () {
    const gate = AndroidRuntimePackageBudgetGate();

    final result = gate.evaluate(
      const AndroidRuntimePackageArtifact(
        artifactId: 'local-runtime-debug.apk',
        sizeBytes: AndroidRuntimePackageBudgetGate.defaultMaxBytes,
        moduleIds: <String>['local.runtime.android'],
      ),
    );

    expect(result.passed, isTrue);
    expect(result.status, AndroidRuntimePackageBudgetStatus.withinBudget);
    expect(result.excessBytes, 0);
  });

  test('android runtime package budget rejects artifacts over 50 MB', () {
    const gate = AndroidRuntimePackageBudgetGate();

    final result = gate.evaluate(
      const AndroidRuntimePackageArtifact(
        artifactId: 'local-runtime-debug.apk',
        sizeBytes: AndroidRuntimePackageBudgetGate.defaultMaxBytes + 2048,
      ),
    );

    expect(result.passed, isFalse);
    expect(result.status, AndroidRuntimePackageBudgetStatus.overBudget);
    expect(result.excessBytes, 2048);
  });

  test('android runtime package budget rejects invalid artifacts', () {
    const gate = AndroidRuntimePackageBudgetGate();

    final result = gate.evaluate(
      const AndroidRuntimePackageArtifact(artifactId: '', sizeBytes: -1),
    );

    expect(result.passed, isFalse);
    expect(result.status, AndroidRuntimePackageBudgetStatus.invalidArtifact);
  });
}
