import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/file_system/file_system_facts.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';

void main() {
  test('adapter capability models normalize labels and merged snapshots', () {
    expect(
      AdapterKind.values.map((kind) => kind.wireValue),
      <String>['cli', 'ffi', 'cloud'],
    );
    expect(
      AdapterKind.values.map((kind) => kind.label),
      <String>['CLI Adapter', 'FFI Adapter', 'Cloud Adapter'],
    );
    expect(
      AdapterCapabilityLevel.values.map((level) => level.label),
      <String>['available', 'partial', 'unavailable'],
    );

    const unavailable = AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: '',
      supportedContractVersions: <int>[1, 3],
    );
    const available = AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'ready',
      supportedContractVersions: <int>[2],
    );
    final merged = const AdapterCapabilitySnapshot(
      adapterKind: AdapterKind.cli,
      languageService: unavailable,
      projectGraph: unavailable,
      execution: unavailable,
      runtimeEvents: unavailable,
    ).merge(
      const AdapterCapabilitySnapshot(
        adapterKind: AdapterKind.cli,
        languageService: available,
        projectGraph: available,
        execution: available,
        runtimeEvents: available,
      ),
    );

    expect(merged.languageService.isAvailable, isTrue);
    expect(merged.languageService.supportedContractVersions, <int>[1, 2, 3]);
    expect(
      mergeCapabilitySnapshots(const <AdapterCapabilitySnapshot>[])
          .languageService
          .isAvailable,
      isFalse,
    );
    expect(
      normalizeCapabilitySnapshots(<AdapterCapabilitySnapshot>[
        buildFfiAdapterCapability(
          visible: false,
          executionSlotVisible: true,
          detail: 'ffi',
        ),
        buildCloudAdapterCapability(
          supportsCloudExecution: true,
          supportsHostedProjectGraph: false,
          detail: 'cloud',
        ),
      ]).map((snapshot) => snapshot.adapterKind),
      <AdapterKind>[AdapterKind.ffi, AdapterKind.cloud],
    );
  });

  test('toolchain catalog handles loose JSON and activation edges', () {
    expect(
      <String?>[
        'compiler',
        'runner',
        'package-manager',
        'terminal',
        'language-service',
        'unknown',
        null,
      ].map(toolchainKindFromWireValue),
      <ToolchainKind>[
        ToolchainKind.compiler,
        ToolchainKind.runner,
        ToolchainKind.packageManager,
        ToolchainKind.terminal,
        ToolchainKind.languageService,
        ToolchainKind.runner,
        ToolchainKind.runner,
      ],
    );

    final snapshot = ToolchainCatalogSnapshot.fromJson(<String, Object?>{
      'descriptors': <Object?>[
        <Object, Object?>{
          'id': 'styio-runner',
          'kind': 'runner',
          'displayName': 'Styio Runner',
          'executablePath': '/opt/styio',
          'metadata': <Object, Object?>{1: 'one'},
        },
        <String, Object?>{'id': ''},
        'invalid',
      ],
      'activeToolchainIds': <Object, Object?>{'runner': 'styio-runner'},
    });
    final catalog = ToolchainCatalog()..restore(snapshot);

    expect(snapshot.descriptors, hasLength(1));
    expect(snapshot.descriptors.single.metadata, <String, Object?>{'1': 'one'});
    expect(catalog.active(ToolchainKind.runner)?.id, 'styio-runner');
    expect(catalog.list().single.toJson()['kind'], 'runner');
    expect(catalog.unregister('missing'), isFalse);
    expect(catalog.deactivate(ToolchainKind.compiler), isFalse);
    expect(
      () => catalog.register(snapshot.descriptors.single),
      throwsStateError,
    );
    expect(() => catalog.activate('missing'), throwsStateError);
    expect(catalog.unregister('styio-runner'), isTrue);
  });

  test(
    'file system facts cover compatibility and entry certainty variants',
    () {
      expect(
        FileSystemFactCertainty.values.map((value) => value.wireValue),
        <String>['confirmed', 'inferred', 'unknown', 'unsupported', 'stale'],
      );
      expect(
        FileSystemProviderKind.values.map((value) => value.wireValue),
        <String>[
          'local',
          'remote',
          'browser-sandbox',
          'virtual',
          'hosted',
          'unknown',
        ],
      );
      expect(
        FileSystemPathStyle.values.map((value) => value.wireValue),
        <String>['posix', 'windows', 'unknown'],
      );
      expect(
        FileSystemWatchSupport.values.map((value) => value.wireValue),
        <String>['none', 'directory', 'recursive', 'polling', 'unknown'],
      );

      final base = FileSystemFacts.linuxDebianArm();
      expect(base.compatibilityTarget, 'linux-debian-arm');
      expect(
        base.copyWith(architecture: 'x64').compatibilityTarget,
        'linux-debian',
      );
      expect(
        base
            .copyWith(distributionId: 'fedora', distributionName: 'Fedora')
            .compatibilityTarget,
        'linux-arm',
      );
      expect(
        base
            .copyWith(
              distributionId: 'fedora',
              distributionName: 'Fedora',
              architecture: 'x64',
            )
            .compatibilityTarget,
        'linux-generic',
      );
      expect(
        base.copyWith(operatingSystem: 'windows').compatibilityTarget,
        'unsupported',
      );

      final entries = FileSystemFacts.buildEntries(
        targetId: 'edge',
        operatingSystem: 'linux',
        distributionId: 'debian',
        distributionName: '',
        architecture: 'armv7',
        pathStyle: FileSystemPathStyle.posix,
        pathSeparator: '/',
        providerKind: FileSystemProviderKind.local,
        watchSupport: FileSystemWatchSupport.polling,
        caseSensitive: true,
        supportsFileUri: false,
        supportsSymbolicLinks: false,
        supportsAtomicWrite: false,
        source: 'test',
        detectedAt: DateTime.utc(2026, 6, 19),
      );

      expect(
        entries['host.distributionName']?.certainty,
        FileSystemFactCertainty.unknown,
      );
      expect(
        entries['filesystem.caseSensitivityHint']?.certainty,
        FileSystemFactCertainty.inferred,
      );
      expect(entries['filesystem.watchSupport']?.value, 'polling');
      expect(base.toJson()['entries'], isA<Map<String, Object?>>());
    },
  );
}
