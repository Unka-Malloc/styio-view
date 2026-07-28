library;

import 'dart:convert';

import '../cancellation.dart';

enum ToolSourceKind { builtin, mcp }

enum ToolRisk { read, write, process, network, credential, destructive }

final class ToolDescriptor {
  ToolDescriptor({
    required this.id,
    required this.description,
    required this.sourceKind,
    required Map<String, Object?> inputSchema,
    required Map<String, Object?> outputSchema,
    required this.risk,
    required Set<String> tags,
    this.pathArgument,
    this.networkHostArgument,
    Map<String, String> secretArguments = const <String, String>{},
    this.maxResultBytes = 64 * 1024,
  }) : inputSchema = ToolJson.freezeMap(inputSchema),
       outputSchema = ToolJson.freezeMap(outputSchema),
       tags = Set<String>.unmodifiable(tags),
       secretArguments = Map<String, String>.unmodifiable(secretArguments) {
    if (id.isEmpty || description.isEmpty || maxResultBytes <= 0) {
      throw ArgumentError('Tool descriptor fields are invalid.');
    }
    ToolSchema.validateDefinition(this.inputSchema);
    ToolSchema.validateDefinition(this.outputSchema);
  }

  final String id;
  final String description;
  final ToolSourceKind sourceKind;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?> outputSchema;
  final ToolRisk risk;
  final Set<String> tags;
  final String? pathArgument;
  final String? networkHostArgument;
  final Map<String, String> secretArguments;
  final int maxResultBytes;
}

final class ToolCatalog {
  ToolCatalog({
    required this.version,
    required List<ToolDescriptor> tools,
    this.truncated = false,
  }) : tools = List<ToolDescriptor>.unmodifiable(tools),
       _byId = <String, ToolDescriptor>{
         for (final tool in tools) tool.id: tool,
       } {
    if (version.isEmpty || _byId.length != tools.length) {
      throw ArgumentError('Catalog version and tool IDs must be unique.');
    }
  }

  final String version;
  final List<ToolDescriptor> tools;
  final bool truncated;
  final Map<String, ToolDescriptor> _byId;

  ToolDescriptor? find(String id) => _byId[id];

  List<ToolDescriptor> relevantFor(Set<String> taskTags, {required int limit}) {
    if (limit < 0) throw ArgumentError.value(limit, 'limit');
    final ranked =
        tools
            .where(
              (tool) =>
                  taskTags.isEmpty ||
                  tool.tags.any((tag) => taskTags.contains(tag)),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final leftMatches = left.tags
                .where((tag) => taskTags.contains(tag))
                .length;
            final rightMatches = right.tags
                .where((tag) => taskTags.contains(tag))
                .length;
            final score = rightMatches.compareTo(leftMatches);
            return score != 0 ? score : left.id.compareTo(right.id);
          });
    return List<ToolDescriptor>.unmodifiable(ranked.take(limit));
  }
}

enum ToolAdapterFailureCode { unavailable, invalidResponse }

final class ToolAdapterFailure implements Exception {
  const ToolAdapterFailure({required this.code, required this.message});

  final ToolAdapterFailureCode code;
  final String message;
}

abstract interface class ToolAdapter {
  Future<Map<String, Object?>> execute(
    ToolDescriptor descriptor,
    Map<String, Object?> arguments,
    AgentCancellationToken cancellation,
  );
}

final class ToolSchema {
  const ToolSchema._();

  static void validateDefinition(Map<String, Object?> schema) {
    _validateSchema(schema, root: true);
  }

  static bool accepts(Map<String, Object?> schema, Object? value) {
    try {
      _validateValue(schema, value);
      return true;
    } on FormatException {
      return false;
    }
  }

  static int encodedBytes(Object? value) =>
      utf8.encode(jsonEncode(value)).length;

  static void _validateSchema(
    Map<String, Object?> schema, {
    bool root = false,
  }) {
    final type = schema['type'];
    const supported = <String>{
      'object',
      'array',
      'string',
      'integer',
      'number',
      'boolean',
      'null',
    };
    if (type is! String || !supported.contains(type)) {
      throw const FormatException('Unsupported tool schema type.');
    }
    if (root && type != 'object') {
      throw const FormatException('Tool schemas must have object roots.');
    }
    if (type == 'object') {
      final rawProperties = schema['properties'];
      if (rawProperties != null && rawProperties is! Map) {
        throw const FormatException('Object properties must be a map.');
      }
      final propertyNames = <String>{};
      if (rawProperties is Map) {
        for (final entry in rawProperties.entries) {
          if (entry.key is! String || entry.value is! Map) {
            throw const FormatException('Object property schema is invalid.');
          }
          propertyNames.add(entry.key as String);
          _validateSchema(Map<String, Object?>.from(entry.value as Map));
        }
      }
      final required = schema['required'];
      if (required != null &&
          (required is! List ||
              required.any(
                (item) => item is! String || !propertyNames.contains(item),
              ))) {
        throw const FormatException('Required properties are invalid.');
      }
      final additional = schema['additionalProperties'];
      if (additional != null && additional is! bool) {
        throw const FormatException('additionalProperties must be boolean.');
      }
    }
    if (type == 'array') {
      final items = schema['items'];
      if (items is Map) {
        _validateSchema(Map<String, Object?>.from(items));
      }
    }
  }

  static void _validateValue(Map<String, Object?> schema, Object? value) {
    final type = schema['type'];
    switch (type) {
      case 'object':
        if (value is! Map) throw const FormatException('Expected object.');
        final properties = schema['properties'] is Map
            ? Map<String, Object?>.from(schema['properties']! as Map)
            : const <String, Object?>{};
        final required = schema['required'] is List
            ? List<Object?>.from(schema['required']! as List)
            : const <Object?>[];
        for (final name in required.cast<String>()) {
          if (!value.containsKey(name)) {
            throw const FormatException('Required property is missing.');
          }
        }
        if (schema['additionalProperties'] == false) {
          for (final key in value.keys) {
            if (key is! String || !properties.containsKey(key)) {
              throw const FormatException('Unknown property.');
            }
          }
        }
        for (final entry in value.entries) {
          final child = properties[entry.key];
          if (child is Map) {
            _validateValue(Map<String, Object?>.from(child), entry.value);
          }
        }
      case 'array':
        if (value is! List) throw const FormatException('Expected array.');
        if (schema['items'] case final Map items) {
          final itemSchema = Map<String, Object?>.from(items);
          for (final item in value) {
            _validateValue(itemSchema, item);
          }
        }
      case 'string':
        if (value is! String) throw const FormatException('Expected string.');
      case 'integer':
        if (value is! int) throw const FormatException('Expected integer.');
      case 'number':
        if (value is! num) throw const FormatException('Expected number.');
      case 'boolean':
        if (value is! bool) throw const FormatException('Expected boolean.');
      case 'null':
        if (value != null) throw const FormatException('Expected null.');
      default:
        throw const FormatException('Unsupported schema.');
    }
  }
}

final class ToolJson {
  const ToolJson._();

  static Map<String, Object?> freezeMap(Map<String, Object?> value) =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in value.entries) entry.key: freeze(entry.value),
      });

  static Object? freeze(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): freeze(entry.value),
      });
    }
    if (value is Iterable) {
      return List<Object?>.unmodifiable(value.map(freeze));
    }
    return value;
  }
}
