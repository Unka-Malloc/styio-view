import 'dart:convert';

import 'agent_tool_registry.dart';

class AgentToolInputValidationIssue {
  const AgentToolInputValidationIssue({
    required this.code,
    required this.message,
    this.propertyName,
    this.expectedType,
    this.actualType,
  });

  final String code;
  final String message;
  final String? propertyName;
  final String? expectedType;
  final String? actualType;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code,
      'message': message,
      if (propertyName != null) 'propertyName': propertyName,
      if (expectedType != null) 'expectedType': expectedType,
      if (actualType != null) 'actualType': actualType,
    };
  }
}

class AgentToolInputValidationResult {
  const AgentToolInputValidationResult({
    required this.toolId,
    required this.decodedObject,
    this.issues = const <AgentToolInputValidationIssue>[],
  });

  final String toolId;
  final Map<String, Object?>? decodedObject;
  final List<AgentToolInputValidationIssue> issues;

  bool get valid => issues.isEmpty;

  String get modelFacingMessage {
    if (valid) {
      return 'Tool $toolId input is valid.';
    }
    return 'The $toolId tool was called with invalid arguments: '
        '${issues.map((issue) => issue.message).join(' ')} '
        'Please rewrite the input so it satisfies the expected schema.';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'toolId': toolId,
      'valid': valid,
      'issueCount': issues.length,
      'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
    };
  }
}

class AgentToolInputValidator {
  const AgentToolInputValidator();

  AgentToolInputValidationResult validate({
    required AgentToolDefinition tool,
    required String inputText,
  }) {
    final schema = tool.schema;
    if (schema.isEmpty) {
      return AgentToolInputValidationResult(
        toolId: tool.toolId,
        decodedObject: null,
      );
    }

    final requiredProperties = schema
        .where((property) => property.required)
        .toList(growable: false);
    final trimmedInput = inputText.trim();
    if (trimmedInput.isEmpty) {
      if (requiredProperties.isEmpty) {
        return AgentToolInputValidationResult(
          toolId: tool.toolId,
          decodedObject: null,
        );
      }
      return AgentToolInputValidationResult(
        toolId: tool.toolId,
        decodedObject: null,
        issues: <AgentToolInputValidationIssue>[
          AgentToolInputValidationIssue(
            code: 'agent.tool.input.empty.${tool.toolId}',
            message: 'Tool ${tool.toolId} requires structured input.',
          ),
        ],
      );
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(trimmedInput);
    } on Object catch (error) {
      return AgentToolInputValidationResult(
        toolId: tool.toolId,
        decodedObject: null,
        issues: <AgentToolInputValidationIssue>[
          AgentToolInputValidationIssue(
            code: 'agent.tool.input.invalidJson.${tool.toolId}',
            message: 'Tool ${tool.toolId} input is not valid JSON: $error',
          ),
        ],
      );
    }
    if (decoded is! Map) {
      return AgentToolInputValidationResult(
        toolId: tool.toolId,
        decodedObject: null,
        issues: <AgentToolInputValidationIssue>[
          AgentToolInputValidationIssue(
            code: 'agent.tool.input.notObject.${tool.toolId}',
            message: 'Tool ${tool.toolId} input must be a JSON object.',
          ),
        ],
      );
    }

    final input = decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    final issues = <AgentToolInputValidationIssue>[];
    for (final property in schema) {
      if (!input.containsKey(property.name)) {
        if (property.required) {
          issues.add(
            AgentToolInputValidationIssue(
              code: 'agent.tool.input.missing.${tool.toolId}.${property.name}',
              message:
                  'Tool ${tool.toolId} input is missing required property ${property.name}.',
              propertyName: property.name,
              expectedType: property.type,
            ),
          );
        }
        continue;
      }
      final value = input[property.name];
      if (!_matchesType(value, property.type)) {
        issues.add(
          AgentToolInputValidationIssue(
            code:
                'agent.tool.input.type.${tool.toolId}.${property.name}.${property.type}',
            message:
                'Tool ${tool.toolId} property ${property.name} must be ${property.type}, but got ${_typeName(value)}.',
            propertyName: property.name,
            expectedType: property.type,
            actualType: _typeName(value),
          ),
        );
      }
    }
    return AgentToolInputValidationResult(
      toolId: tool.toolId,
      decodedObject: input,
      issues: List<AgentToolInputValidationIssue>.unmodifiable(issues),
    );
  }
}

class AgentToolResultValidationIssue {
  const AgentToolResultValidationIssue({
    required this.code,
    required this.message,
    this.propertyName,
    this.expectedType,
    this.actualType,
  });

  final String code;
  final String message;
  final String? propertyName;
  final String? expectedType;
  final String? actualType;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code,
      'message': message,
      if (propertyName != null) 'propertyName': propertyName,
      if (expectedType != null) 'expectedType': expectedType,
      if (actualType != null) 'actualType': actualType,
    };
  }
}

class AgentToolResultValidationResult {
  const AgentToolResultValidationResult({
    required this.toolId,
    required this.decodedObject,
    this.issues = const <AgentToolResultValidationIssue>[],
  });

  final String toolId;
  final Map<String, Object?>? decodedObject;
  final List<AgentToolResultValidationIssue> issues;

  bool get valid => issues.isEmpty;

  String get modelFacingMessage {
    if (valid) {
      return 'Tool $toolId result is valid.';
    }
    return 'The $toolId tool returned output that does not satisfy its result schema: '
        '${issues.map((issue) => issue.message).join(' ')}';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'toolId': toolId,
      'valid': valid,
      'issueCount': issues.length,
      'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
    };
  }
}

class AgentToolResultValidator {
  const AgentToolResultValidator();

  AgentToolResultValidationResult validate({
    required AgentToolDefinition tool,
    required String outputText,
  }) {
    final schema = tool.resultSchema;
    if (schema.isEmpty) {
      return AgentToolResultValidationResult(
        toolId: tool.toolId,
        decodedObject: null,
      );
    }

    final trimmedOutput = outputText.trim();
    if (trimmedOutput.isEmpty) {
      return AgentToolResultValidationResult(
        toolId: tool.toolId,
        decodedObject: null,
        issues: <AgentToolResultValidationIssue>[
          AgentToolResultValidationIssue(
            code: 'agent.tool.result.empty.${tool.toolId}',
            message: 'Tool ${tool.toolId} returned empty output.',
          ),
        ],
      );
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(trimmedOutput);
    } on Object catch (error) {
      return AgentToolResultValidationResult(
        toolId: tool.toolId,
        decodedObject: null,
        issues: <AgentToolResultValidationIssue>[
          AgentToolResultValidationIssue(
            code: 'agent.tool.result.invalidJson.${tool.toolId}',
            message: 'Tool ${tool.toolId} result is not valid JSON: $error',
          ),
        ],
      );
    }
    if (decoded is! Map) {
      return AgentToolResultValidationResult(
        toolId: tool.toolId,
        decodedObject: null,
        issues: <AgentToolResultValidationIssue>[
          AgentToolResultValidationIssue(
            code: 'agent.tool.result.notObject.${tool.toolId}',
            message: 'Tool ${tool.toolId} result must be a JSON object.',
          ),
        ],
      );
    }

    final output = decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    final issues = <AgentToolResultValidationIssue>[];
    for (final property in schema) {
      if (!output.containsKey(property.name)) {
        if (property.required) {
          issues.add(
            AgentToolResultValidationIssue(
              code: 'agent.tool.result.missing.${tool.toolId}.${property.name}',
              message:
                  'Tool ${tool.toolId} result is missing required property ${property.name}.',
              propertyName: property.name,
              expectedType: property.type,
            ),
          );
        }
        continue;
      }
      final value = output[property.name];
      if (!_matchesType(value, property.type)) {
        issues.add(
          AgentToolResultValidationIssue(
            code:
                'agent.tool.result.type.${tool.toolId}.${property.name}.${property.type}',
            message:
                'Tool ${tool.toolId} result property ${property.name} must be ${property.type}, but got ${_typeName(value)}.',
            propertyName: property.name,
            expectedType: property.type,
            actualType: _typeName(value),
          ),
        );
      }
    }
    return AgentToolResultValidationResult(
      toolId: tool.toolId,
      decodedObject: output,
      issues: List<AgentToolResultValidationIssue>.unmodifiable(issues),
    );
  }
}

bool _matchesType(Object? value, String expectedType) {
  final types = expectedType
      .split('|')
      .map((type) => type.trim().toLowerCase())
      .where((type) => type.isNotEmpty)
      .toList(growable: false);
  if (types.isEmpty) {
    return true;
  }
  return types.any((type) {
    return switch (type) {
      'any' || 'json' => true,
      'string' => value is String,
      'object' => value is Map,
      'array' => value is List,
      'boolean' || 'bool' => value is bool,
      'number' => value is num,
      'integer' || 'int' => value is int,
      _ => true,
    };
  });
}

String _typeName(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is String) {
    return 'string';
  }
  if (value is Map) {
    return 'object';
  }
  if (value is List) {
    return 'array';
  }
  if (value is bool) {
    return 'boolean';
  }
  if (value is int) {
    return 'integer';
  }
  if (value is num) {
    return 'number';
  }
  return value.runtimeType.toString();
}
