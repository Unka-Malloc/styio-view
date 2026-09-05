import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/owner_adapters/styio_compiler_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

void main() {
  CompilerHandshakeSnapshot handshake({
    List<int> schemaVersions = const <int>[1],
    List<String> capabilities = kObservableRequiredCapabilities,
    List<String> optionalCapabilities = const <String>[],
    String variant = 'full',
  }) {
    return CompilerHandshakeSnapshot(
      binaryPath: 'styio',
      tool: 'styio',
      compilerVersion: '0.0.1',
      channel: 'nightly',
      variant: variant,
      capabilities: const <String>['compile-plan'],
      supportedContractVersions: const <String, List<int>>{
        'compile_plan': <int>[1],
      },
      integrationPhase: 'compile-plan-live',
      observableStaticSnapshotSchemaVersions: schemaVersions,
      observableStaticSnapshotCapabilities: capabilities,
      observableStaticSnapshotOptionalCapabilities: optionalCapabilities,
    );
  }

  ObservableNegotiationDecision decide({
    CompilerHandshakeSnapshot? compiler,
    bool pafioAvailable = true,
    bool ioPlatform = true,
    String? manifestPath = 'Styio.toml',
    bool hosted = false,
  }) {
    return negotiateObservableCapability(
      ObservableNegotiationInput(
        ioPlatform: ioPlatform,
        pafioAvailable: pafioAvailable,
        compiler: compiler,
        manifestPath: manifestPath,
        hosted: hosted,
      ),
    );
  }

  test(
    'negotiation matrix covers toolchain, schema and capability failures',
    () {
      final missingStyio = decide(compiler: null);
      expect(missingStyio.accepted, isFalse);
      expect(missingStyio.availability, ObservableAvailability.unavailable);
      expect(missingStyio.reason, ObservableReasonCode.noToolchain);
      expect(shouldDecodeObservableSnapshot(missingStyio), isFalse);

      final missingPafio = decide(compiler: handshake(), pafioAvailable: false);
      expect(missingPafio.availability, ObservableAvailability.unavailable);
      expect(missingPafio.reason, ObservableReasonCode.noToolchain);
      expect(shouldDecodeObservableSnapshot(missingPafio), isFalse);

      final nano = decide(
        compiler: handshake(schemaVersions: const <int>[], variant: 'nano'),
      );
      expect(nano.availability, ObservableAvailability.unsupported);
      expect(nano.reason, ObservableReasonCode.unsupportedSchemaVersion);
      expect(shouldDecodeObservableSnapshot(nano), isFalse);

      final older = decide(compiler: handshake(schemaVersions: const <int>[0]));
      expect(older.reason, ObservableReasonCode.unsupportedSchemaVersion);
      expect(shouldDecodeObservableSnapshot(older), isFalse);

      final missingCapability = decide(
        compiler: handshake(
          capabilities: const <String>['static-topology-nodes'],
        ),
      );
      expect(missingCapability.reason, ObservableReasonCode.missingCapability);
      expect(shouldDecodeObservableSnapshot(missingCapability), isFalse);

      final success = decide(compiler: handshake());
      expect(success.accepted, isTrue);
      expect(shouldDecodeObservableSnapshot(success), isTrue);

      final again = decide(compiler: handshake());
      expect(again.accepted, success.accepted);
      expect(again.reason, success.reason);
      expect(success.snapshotDeltaAvailable, isFalse);
      expect(success.producerLineageAvailable, isFalse);

      final deltaOnly = decide(
        compiler: handshake(
          capabilities: <String>[
            ...kObservableRequiredCapabilities,
            kObservableDeltaCapability,
          ],
        ),
      );
      expect(deltaOnly.accepted, isTrue);
      expect(deltaOnly.snapshotDeltaAvailable, isTrue);
      expect(deltaOnly.producerLineageAvailable, isFalse);

      final both = decide(
        compiler: handshake(
          capabilities: <String>[
            ...kObservableRequiredCapabilities,
            kObservableDeltaCapability,
            kObservableLineageCapability,
          ],
        ),
      );
      expect(both.accepted, isTrue);
      expect(both.snapshotDeltaAvailable, isTrue);
      expect(both.producerLineageAvailable, isTrue);
      expect(shouldDecodeObservableSnapshot(both), isTrue);

      final styioOptional = decide(
        compiler: handshake(
          optionalCapabilities: const <String>[
            kObservableLineageCapability,
            kObservableDeltaCapability,
          ],
        ),
      );
      expect(styioOptional.accepted, isTrue);
      expect(styioOptional.snapshotDeltaAvailable, isTrue);
      expect(styioOptional.producerLineageAvailable, isTrue);

      final fromMachineInfo = ObservableSnapshotAdvertisement.fromMachineInfo(
        <String, Object?>{
          kObservableMachineInfoKey: <String, Object?>{
            'schema_versions': <int>[1],
            'capabilities': kObservableRequiredCapabilities,
            kObservableMachineInfoOptionalCapabilitiesKey: <String>[
              kObservableLineageCapability,
              kObservableDeltaCapability,
            ],
          },
        },
      );
      expect(fromMachineInfo.advertisesSchemaV1, isTrue);
      expect(fromMachineInfo.missingRequiredCapabilities, isEmpty);
      expect(
        fromMachineInfo.advertisesOptionalCapability(
          kObservableDeltaCapability,
        ),
        isTrue,
      );
      expect(
        fromMachineInfo.advertisesOptionalCapability(
          kObservableLineageCapability,
        ),
        isTrue,
      );

      final decoded = StyioCompilerAdapter.decode(
        jsonEncode(<String, Object?>{
          'tool': 'styio',
          'compiler_version': '0.0.1',
          'channel': 'nightly',
          'variant': 'full',
          'capabilities': <String>['compile-plan'],
          'supported_contracts': <String, Object?>{
            'compile_plan': <int>[1],
          },
          kObservableMachineInfoKey: <String, Object?>{
            'schema_versions': <int>[1],
            'capabilities': kObservableRequiredCapabilities,
            kObservableMachineInfoOptionalCapabilitiesKey: <String>[
              kObservableLineageCapability,
              kObservableDeltaCapability,
            ],
          },
        }),
        binaryPath: 'styio',
      );
      final fromDecoded = ObservableSnapshotAdvertisement.fromHandshake(
        decoded,
      );
      expect(fromDecoded.advertisesSchemaV1, isTrue);
      expect(
        fromDecoded.advertisesOptionalCapability(kObservableDeltaCapability),
        isTrue,
      );
      expect(
        fromDecoded.advertisesOptionalCapability(kObservableLineageCapability),
        isTrue,
      );
    },
  );

  test('runtime observation negotiation matrix', () {
    CompilerHandshakeSnapshot runtimeHandshake({
      List<int> runtimeEvents = const <int>[2],
      List<String> runtimeCapabilities = kRuntimeRequiredCapabilities,
      List<String> unavailable = const <String>['cancellation'],
      String? defaultMode = 'aggregate',
      String variant = 'full',
    }) {
      return CompilerHandshakeSnapshot(
        binaryPath: 'styio',
        tool: 'styio',
        compilerVersion: '0.0.1',
        channel: 'nightly',
        variant: variant,
        capabilities: const <String>['compile-plan'],
        supportedContractVersions: <String, List<int>>{
          'compile_plan': const <int>[1],
          'runtime_events': runtimeEvents,
        },
        integrationPhase: 'compile-plan-live',
        observableStaticSnapshotSchemaVersions: const <int>[1],
        observableStaticSnapshotCapabilities: kObservableRequiredCapabilities,
        runtimeEventsCapabilities: runtimeCapabilities,
        runtimeEventsUnavailableCapabilities: unavailable,
        runtimeEventsDefaultMode: defaultMode,
      );
    }

    final nano = negotiateRuntimeObservation(
      ObservableNegotiationInput(
        ioPlatform: true,
        pafioAvailable: true,
        compiler: runtimeHandshake(
          runtimeEvents: const <int>[],
          variant: 'nano',
        ),
        manifestPath: 'Styio.toml',
      ),
    );
    expect(nano.available, isFalse);
    expect(
      nano.reason,
      ObservableReasonCode.unsupportedRuntimeEventsVersion,
    );

    final missingVersions = negotiateRuntimeObservation(
      ObservableNegotiationInput(
        ioPlatform: true,
        pafioAvailable: true,
        compiler: runtimeHandshake(runtimeEvents: const <int>[]),
        manifestPath: 'Styio.toml',
      ),
    );
    expect(
      missingVersions.reason,
      ObservableReasonCode.unsupportedRuntimeEventsVersion,
    );

    final missingCapability = negotiateRuntimeObservation(
      ObservableNegotiationInput(
        ioPlatform: true,
        pafioAvailable: true,
        compiler: runtimeHandshake(
          runtimeCapabilities: const <String>['task-lifecycle'],
        ),
        manifestPath: 'Styio.toml',
      ),
    );
    expect(
      missingCapability.reason,
      ObservableReasonCode.missingRuntimeCapability,
    );

    final success = negotiateRuntimeObservation(
      ObservableNegotiationInput(
        ioPlatform: true,
        pafioAvailable: true,
        compiler: runtimeHandshake(),
        manifestPath: 'Styio.toml',
      ),
    );
    expect(success.available, isTrue);
    expect(success.defaultMode, RuntimeObservationMode.aggregate);
    expect(success.unavailableCapabilities, contains('cancellation'));

    final snapshotUnchanged = negotiateObservableCapability(
      ObservableNegotiationInput(
        ioPlatform: true,
        pafioAvailable: true,
        compiler: runtimeHandshake(),
        manifestPath: 'Styio.toml',
      ),
    );
    expect(snapshotUnchanged.accepted, isTrue);
  });

  test('runtime advertisement parses machine-info runtime_events object', () {
    final advertisement = RuntimeEventsAdvertisement.fromMachineInfo(
      <String, Object?>{
        kRuntimeEventsMachineInfoKey: <String, Object?>{
          'schema_versions': <int>[2],
          'default_mode': 'aggregate',
          'capabilities': kRuntimeRequiredCapabilities,
          'unavailable_capabilities': const <String>['cancellation'],
        },
      },
    );
    expect(advertisement.advertisesSchemaV2, isTrue);
    expect(advertisement.missingRequiredCapabilities, isEmpty);
    expect(advertisement.unavailableCapabilities, <String>['cancellation']);

    final decoded = StyioCompilerAdapter.decode(
      jsonEncode(<String, Object?>{
        'tool': 'styio',
        'compiler_version': '0.0.1',
        'channel': 'nightly',
        'variant': 'full',
        'capabilities': <String>['compile-plan'],
        'supported_contracts': <String, Object?>{
          'compile_plan': <int>[1],
          'runtime_events': <int>[2],
        },
        kRuntimeEventsMachineInfoKey: <String, Object?>{
          'schema_versions': <int>[2],
          'default_mode': 'aggregate',
          'capabilities': kRuntimeRequiredCapabilities,
          'unavailable_capabilities': const <String>['wait-timer'],
        },
      }),
      binaryPath: 'styio',
    );
    expect(decoded.runtimeEventsCapabilities, kRuntimeRequiredCapabilities);
    expect(decoded.runtimeEventsUnavailableCapabilities, <String>['wait-timer']);
    expect(decoded.runtimeEventsDefaultMode, 'aggregate');
  });
}
