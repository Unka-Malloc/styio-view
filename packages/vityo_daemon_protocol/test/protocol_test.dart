import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

void main() {
  final conformance =
      jsonDecode(
            File('test/fixtures/conformance_cases.json').readAsStringSync(),
          )
          as Map<String, Object?>;

  test('control fixture round-trips while preserving unknown fields', () {
    final fixture = File(
      'test/fixtures/control_roundtrip.json',
    ).readAsBytesSync();
    final decoded = VityodControlCodec.decode(fixture);
    final roundTrip = VityodControlCodec.decode(
      VityodControlCodec.encode(decoded),
    );

    expect(roundTrip.method, 'workspace.snapshot');
    expect(roundTrip.workspaceRevision, 7);
    expect(roundTrip.unknownFields['futureField'], <String, Object?>{
      'preserved': true,
    });
  });

  test('binary frame header round-trips', () {
    const header = VityodFrameHeader(
      kind: VityodFrameKind.pty,
      streamId: 42,
      sequence: 99,
      payloadLength: 4096,
      flags: 3,
    );
    final decoded = VityodFrameHeader.decode(header.encode());
    expect(decoded.kind, VityodFrameKind.pty);
    expect(decoded.streamId, 42);
    expect(decoded.sequence, 99);
    expect(decoded.payloadLength, 4096);
    expect(decoded.flags, 3);
  });

  test('oversized control frame fails closed', () {
    expect(
      () => VityodFrameHeader(
        kind: VityodFrameKind.control,
        streamId: 1,
        sequence: 1,
        payloadLength: vityodMaxControlPayloadBytes + 1,
      ).encode(),
      throwsA(
        isA<VityodProtocolException>().having(
          (error) => error.code,
          'code',
          'frame_too_large',
        ),
      ),
    );
  });

  test(
    'shared conformance corpus covers versions, framing, and capabilities',
    () {
      final validHeaders = (conformance['validFrameHeaders'] as List<Object?>)
          .cast<Map<String, Object?>>();
      for (final fixture in validHeaders) {
        final header = VityodFrameHeader.decode(
          _hex(fixture['hex']! as String),
        );
        expect(
          header.kind.name,
          fixture['kind'],
          reason: fixture['name'] as String,
        );
        expect(header.flags, fixture['flags']);
        expect(header.streamId, fixture['streamId']);
        expect(header.sequence, fixture['sequence']);
        expect(header.payloadLength, fixture['payloadLength']);
        expect(header.encode(), _hex(fixture['hex']! as String));
      }

      final invalidHeaders =
          (conformance['invalidFrameHeaders'] as List<Object?>)
              .cast<Map<String, Object?>>();
      for (final fixture in invalidHeaders) {
        expect(
          () => VityodFrameHeader.decode(_hex(fixture['hex']! as String)),
          throwsA(
            isA<VityodProtocolException>().having(
              (error) => error.code,
              'code',
              fixture['expected'],
            ),
          ),
          reason: fixture['name'] as String,
        );
      }

      final source =
          jsonDecode(
                File(
                  'test/fixtures/${conformance['controlFixture']}',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      for (final version
          in (conformance['invalidControlVersions'] as List<Object?>)
              .cast<int>()) {
        expect(
          () => VityodControlEnvelope.fromJson(<String, Object?>{
            ...source,
            'protocolVersion': version,
          }),
          throwsA(
            isA<VityodProtocolException>().having(
              (error) => error.code,
              'code',
              'unsupported_protocol_version',
            ),
          ),
        );
      }
      expect(
        () => VityodControlCodec.decode(
          utf8.encode(conformance['malformedControl']! as String),
        ),
        throwsA(
          isA<VityodProtocolException>().having(
            (error) => error.code,
            'code',
            'invalid_json',
          ),
        ),
      );

      final negotiation =
          conformance['capabilityNegotiation'] as Map<String, Object?>;
      final offered = (negotiation['offered'] as List<Object?>)
          .cast<String>()
          .toSet();
      final required = (negotiation['requiredSupported'] as List<Object?>)
          .cast<String>();
      expect(offered.containsAll(required), isTrue);
      expect(offered, isNot(contains(negotiation['requiredUnsupported'])));
    },
  );

  test('Dart and Rust method catalogs stay canonical and legacy-free', () {
    expect(
      vityodCoreCapabilities.toSet().length,
      vityodCoreCapabilities.length,
    );
    expect(vityodMethodCatalog.length, vityodMethodCatalog.toSet().length);
    expect(
      vityodMethodCatalog.where(
        (method) => method.startsWith('agent.process.'),
      ),
      isEmpty,
    );
  });
}

List<int> _hex(String value) {
  expect(value.length.isEven, isTrue);
  return <int>[
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ];
}
