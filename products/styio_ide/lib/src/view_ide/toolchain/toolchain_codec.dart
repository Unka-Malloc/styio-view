import 'dart:convert';
import 'dart:typed_data';

enum ToolchainPayloadFormat {
  utf8Text,
  json,
  jsonLines,
}

extension ToolchainPayloadFormatX on ToolchainPayloadFormat {
  String get wireValue => switch (this) {
    ToolchainPayloadFormat.utf8Text => 'utf8-text',
    ToolchainPayloadFormat.json => 'json',
    ToolchainPayloadFormat.jsonLines => 'json-lines',
  };
}

class ToolchainPayload {
  const ToolchainPayload({
    required this.format,
    required this.bytes,
    this.contentType,
    this.metadata = const <String, Object?>{},
  });

  final ToolchainPayloadFormat format;
  final Uint8List bytes;
  final String? contentType;
  final Map<String, Object?> metadata;

  int get length => bytes.length;
}

class ToolchainPayloadCodec {
  const ToolchainPayloadCodec();

  ToolchainPayload encodeText(
    String value, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ToolchainPayload(
      format: ToolchainPayloadFormat.utf8Text,
      bytes: Uint8List.fromList(utf8.encode(value)),
      contentType: 'text/plain; charset=utf-8',
      metadata: metadata,
    );
  }

  String decodeText(ToolchainPayload payload) {
    return utf8.decode(payload.bytes);
  }

  ToolchainPayload encodeJson(
    Map<String, Object?> value, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ToolchainPayload(
      format: ToolchainPayloadFormat.json,
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(value))),
      contentType: 'application/json',
      metadata: metadata,
    );
  }

  Map<String, Object?> decodeJson(ToolchainPayload payload) {
    final decoded = jsonDecode(decodeText(payload));
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
    }
    throw const FormatException('Toolchain JSON payload must decode to a map.');
  }

  ToolchainPayload encodeJsonLines(
    Iterable<Map<String, Object?>> records, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final lines = records.map(jsonEncode).join('\n');
    return ToolchainPayload(
      format: ToolchainPayloadFormat.jsonLines,
      bytes: Uint8List.fromList(utf8.encode(lines)),
      contentType: 'application/x-ndjson',
      metadata: metadata,
    );
  }

  List<Map<String, Object?>> decodeJsonLines(ToolchainPayload payload) {
    final records = <Map<String, Object?>>[];
    for (final line in const LineSplitter().convert(decodeText(payload))) {
      if (line.trim().isEmpty) {
        continue;
      }
      final decoded = jsonDecode(line);
      if (decoded is Map<String, Object?>) {
        records.add(decoded);
      } else if (decoded is Map) {
        records.add(
          decoded.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        );
      } else {
        throw const FormatException(
          'Toolchain JSONL payload line must decode to a map.',
        );
      }
    }
    return records;
  }
}
