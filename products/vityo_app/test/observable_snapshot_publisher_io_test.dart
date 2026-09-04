import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/observable_snapshot_publisher_io.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/observable_snapshot_publisher_web.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'observable_fixture_support.dart';

void main() {
  Future<Directory> workspace() async {
    final root = await Directory.systemTemp.createTemp('vityo_observable_pub_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    await File('${root.path}${Platform.pathSeparator}pafio.toml').writeAsString(
      'package = "example.app"\n',
    );
    return root;
  }

  Future<File> writeScript(Directory root, String name, String body) async {
    final file = File('${root.path}${Platform.pathSeparator}$name');
    await file.writeAsString(body);
    await Process.run('chmod', <String>['+x', file.path]);
    return file;
  }

  /// Mirrors the real producer contract: Pafio prints one success envelope
  /// `{action, command, intent, message, mode, plan, profile, status, styio,
  /// sync, target}` on stdout, and Styio writes the schema-v1 receipt file at
  /// `<plan.build_root>/receipt.json` naming the snapshot artifact under
  /// `<plan.artifact_dir>`.
  Future<File> writeFakePafio(
    Directory root, {
    required String artifactPath,
    bool writeReceipt = true,
  }) async {
    final buildRoot = '${root.path}${Platform.pathSeparator}build';
    final artifactDir = '$buildRoot${Platform.pathSeparator}artifacts';
    final receipt = '''
{"schema_version":1,"tool":"styio","compiler_version":"0.0.1","channel":"nightly","plan_version":1,"intent":"check","session_id":"s1","executed":true,"wall_time_ms":0,"outputs":{"build_root":"$buildRoot","artifact_dir":"$artifactDir","diag_dir":"$buildRoot${Platform.pathSeparator}diag"},"artifacts":["$artifactPath"]}
''';
    final envelope = '''
{"action":"check","command":"check","intent":"check","message":"completed Styio check via compile-plan","mode":"execute","plan":{"artifact_dir":"$artifactDir","build_root":"$buildRoot","diag_dir":"$buildRoot${Platform.pathSeparator}diag","path":"${root.path}${Platform.pathSeparator}pafio-plan.json"},"profile":"dev","status":"succeeded","styio":{"status":"succeeded"},"sync":{"status":"succeeded"},"target":{"kind":"lib","name":"example","package":"example.app","package_id":"example.app"}}
''';
    return writeScript(root, 'fake-pafio', '''
#!/bin/sh
set -e
mkdir -p "$artifactDir"
${writeReceipt ? 'cat > "$buildRoot/receipt.json" <<\'EOF\'\n$receipt\nEOF' : ''}
cat <<'EOF'
$envelope
EOF
''');
  }

  test('IO publisher reads the receipt-named artifact', () async {
    final root = await workspace();
    final artifact = File(
      '${root.path}${Platform.pathSeparator}build${Platform.pathSeparator}artifacts${Platform.pathSeparator}example.observable-static-snapshot.json',
    );
    await artifact.create(recursive: true);
    await artifact.writeAsBytes(readObservableFixtureBytes('canonical.json'));
    final pafio = await writeFakePafio(root, artifactPath: artifact.path);
    final publisher = IoObservableSnapshotPublisher();
    final result = await publisher.publish(
      ObservableSnapshotPublishRequest(
        workspaceRoot: root.path,
        manifestPath: '${root.path}${Platform.pathSeparator}pafio.toml',
        pafioBinary: pafio.path,
        compilerBinary: 'styio',
      ),
    );
    expect(result.isSuccess, isTrue);
    expect(result.bytes, readObservableFixtureBytes('canonical.json'));
    expect(result.artifactPath, artifact.path);
  });

  test('IO publisher fails closed when the receipt file is missing', () async {
    final root = await workspace();
    final artifact = File(
      '${root.path}${Platform.pathSeparator}build${Platform.pathSeparator}artifacts${Platform.pathSeparator}example.observable-static-snapshot.json',
    );
    await artifact.create(recursive: true);
    await artifact.writeAsBytes(readObservableFixtureBytes('canonical.json'));
    final pafio = await writeFakePafio(
      root,
      artifactPath: artifact.path,
      writeReceipt: false,
    );
    final publisher = IoObservableSnapshotPublisher();
    final result = await publisher.publish(
      ObservableSnapshotPublishRequest(
        workspaceRoot: root.path,
        manifestPath: '${root.path}${Platform.pathSeparator}pafio.toml',
        pafioBinary: pafio.path,
        compilerBinary: 'styio',
      ),
    );
    expect(result.isSuccess, isFalse);
    expect(result.reason, ObservableReasonCode.publicationFailed);
    expect(result.detail, contains('receipt'));
  });

  test('IO publisher maps a JSON error payload to publication-failed', () async {
    final root = await workspace();
    final pafio = await writeScript(root, 'fake-pafio-fail', '''
#!/bin/sh
cat >&2 <<EOF
{"category":"CompilerError","code":70,"message":"check exploded","command":"check"}
EOF
exit 2
''');
    final publisher = IoObservableSnapshotPublisher();
    final result = await publisher.publish(
      ObservableSnapshotPublishRequest(
        workspaceRoot: root.path,
        manifestPath: '${root.path}${Platform.pathSeparator}pafio.toml',
        pafioBinary: pafio.path,
        compilerBinary: 'styio',
      ),
    );
    expect(result.status, ObservablePublishStatus.failed);
    expect(result.reason, ObservableReasonCode.publicationFailed);
    expect(result.detail, 'check exploded');
  });

  test('IO publisher redacts absolute paths from failure details', () async {
    final root = await workspace();
    final pafio = await writeScript(root, 'fake-pafio-paths', '''
#!/bin/sh
cat >&2 <<EOF
{"category":"CompilerError","code":70,"message":"Styio failed for compile-plan /secret/machine/plan.json: boom","command":"check"}
EOF
exit 2
''');
    final publisher = IoObservableSnapshotPublisher();
    final result = await publisher.publish(
      ObservableSnapshotPublishRequest(
        workspaceRoot: root.path,
        manifestPath: '${root.path}${Platform.pathSeparator}pafio.toml',
        pafioBinary: pafio.path,
        compilerBinary: 'styio',
      ),
    );
    expect(result.status, ObservablePublishStatus.failed);
    expect(result.detail, 'Styio failed for compile-plan <path> boom');
    expect(result.detail, isNot(contains('/secret')));
  });

  test('IO publisher returns cancelled after the process is killed', () async {
    final root = await workspace();
    final pafio = await writeScript(root, 'fake-pafio-sleep', '''
#!/bin/sh
sleep 30
''');
    final publisher = IoObservableSnapshotPublisher();
    final future = publisher.publish(
      ObservableSnapshotPublishRequest(
        workspaceRoot: root.path,
        manifestPath: '${root.path}${Platform.pathSeparator}pafio.toml',
        pafioBinary: pafio.path,
        compilerBinary: 'styio',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    publisher.cancel();
    final result = await future;
    expect(result.status, ObservablePublishStatus.cancelled);
    expect(result.reason, ObservableReasonCode.cancelled);
  });

  test('IO publisher rejects an artifact outside the allowed tree', () async {
    final root = await workspace();
    final other = await Directory.systemTemp.createTemp('vityo_observable_out_');
    addTearDown(() async {
      if (await other.exists()) {
        await other.delete(recursive: true);
      }
    });
    final artifact = File(
      '${other.path}${Platform.pathSeparator}stolen.observable-static-snapshot.json',
    );
    await artifact.writeAsBytes(readObservableFixtureBytes('canonical.json'));
    final pafio = await writeFakePafio(root, artifactPath: artifact.path);
    final publisher = IoObservableSnapshotPublisher();
    final result = await publisher.publish(
      ObservableSnapshotPublishRequest(
        workspaceRoot: root.path,
        manifestPath: '${root.path}${Platform.pathSeparator}pafio.toml',
        pafioBinary: pafio.path,
        compilerBinary: 'styio',
      ),
    );
    expect(result.isSuccess, isFalse);
    expect(result.detail, contains('outside the allowed tree'));
  });

  test('web stub returns unsupported-platform', () async {
    final publisher = createObservableSnapshotPublisherOnWeb();
    final result = await publisher.publish(
      const ObservableSnapshotPublishRequest(
        workspaceRoot: 'workspace',
        manifestPath: 'Styio.toml',
        pafioBinary: 'pafio',
        compilerBinary: 'styio',
      ),
    );
    expect(result.reason, ObservableReasonCode.unsupportedPlatform);
    expect(result.status, ObservablePublishStatus.unsupported);
  });
}

ObservableSnapshotPublisher createObservableSnapshotPublisherOnWeb() {
  return const WebObservableSnapshotPublisher();
}
