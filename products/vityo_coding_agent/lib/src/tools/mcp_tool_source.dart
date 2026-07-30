library;

import 'dart:convert';

import '../cancellation.dart';
import 'tool_catalog.dart';

enum McpTransportFailureCode { unavailable, cancelled, invalidResponse }

final class McpTransportFailure implements Exception {
  const McpTransportFailure({required this.code, required this.message});

  final McpTransportFailureCode code;
  final String message;
}

final class McpToolMetadata {
  const McpToolMetadata({
    required this.id,
    required this.description,
    required this.inputSchema,
    required this.outputSchema,
    required this.risk,
    required this.tags,
    this.pathArgument,
    this.networkHostArgument,
    this.secretArguments = const <String, String>{},
    this.maxResultBytes = 64 * 1024,
  });

  final String id;
  final String description;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?> outputSchema;
  final ToolRisk risk;
  final Set<String> tags;
  final String? pathArgument;
  final String? networkHostArgument;
  final Map<String, String> secretArguments;
  final int maxResultBytes;
}

final class McpDiscoveryPage {
  McpDiscoveryPage({
    required this.serverVersion,
    required List<McpToolMetadata> tools,
    required this.hasMore,
  }) : tools = List<McpToolMetadata>.unmodifiable(tools);

  final String serverVersion;
  final List<McpToolMetadata> tools;
  final bool hasMore;
}

abstract interface class McpClient {
  Future<McpDiscoveryPage> listTools({
    required int limit,
    required AgentCancellationToken cancellation,
  });

  Future<Map<String, Object?>> callTool(
    String id,
    Map<String, Object?> arguments,
    AgentCancellationToken cancellation,
  );
}

enum McpSourceFailureCode {
  unavailable,
  cancelled,
  schemaInvalid,
  responseTooLarge,
}

final class McpSourceFailure implements Exception {
  const McpSourceFailure({required this.code, required this.message});

  final McpSourceFailureCode code;
  final String message;
}

final class McpToolSource implements ToolAdapter {
  McpToolSource({
    required McpClient client,
    required this.maxTools,
    required this.maxSchemaBytes,
    Map<String, ToolRisk> trustedRiskOverrides = const <String, ToolRisk>{},
  }) : _client = client,
       _trustedRiskOverrides = Map<String, ToolRisk>.unmodifiable(
         trustedRiskOverrides,
       ) {
    if (maxTools <= 0 || maxSchemaBytes <= 0) {
      throw ArgumentError('MCP source bounds must be positive.');
    }
  }

  final McpClient _client;
  final int maxTools;
  final int maxSchemaBytes;
  final Map<String, ToolRisk> _trustedRiskOverrides;

  Future<ToolCatalog> refresh(AgentCancellationToken cancellation) async {
    if (cancellation.isCancelled) {
      throw const McpSourceFailure(
        code: McpSourceFailureCode.cancelled,
        message: 'MCP discovery was cancelled.',
      );
    }
    try {
      final page = await _client.listTools(
        limit: maxTools,
        cancellation: cancellation,
      );
      if (page.serverVersion.isEmpty || page.tools.length > maxTools) {
        throw const McpSourceFailure(
          code: McpSourceFailureCode.schemaInvalid,
          message: 'MCP discovery page is invalid.',
        );
      }
      final descriptors = <ToolDescriptor>[];
      for (final metadata in page.tools) {
        int schemaBytes;
        try {
          schemaBytes = utf8
              .encode(
                jsonEncode(<Object?>[
                  metadata.inputSchema,
                  metadata.outputSchema,
                ]),
              )
              .length;
        } on Object {
          throw const McpSourceFailure(
            code: McpSourceFailureCode.schemaInvalid,
            message: 'MCP tool schema is not valid JSON.',
          );
        }
        if (schemaBytes > maxSchemaBytes) {
          throw const McpSourceFailure(
            code: McpSourceFailureCode.responseTooLarge,
            message: 'MCP tool schema exceeds the configured bound.',
          );
        }
        try {
          descriptors.add(
            ToolDescriptor(
              id: metadata.id,
              description: metadata.description,
              sourceKind: ToolSourceKind.mcp,
              inputSchema: metadata.inputSchema,
              outputSchema: metadata.outputSchema,
              risk: _trustedRiskOverrides[metadata.id] ?? ToolRisk.destructive,
              tags: metadata.tags,
              pathArgument: metadata.pathArgument,
              networkHostArgument: metadata.networkHostArgument,
              secretArguments: metadata.secretArguments,
              maxResultBytes: metadata.maxResultBytes,
            ),
          );
        } on Object {
          throw const McpSourceFailure(
            code: McpSourceFailureCode.schemaInvalid,
            message: 'MCP tool metadata or schema is invalid.',
          );
        }
      }
      return ToolCatalog(
        version: 'mcp:${page.serverVersion}',
        tools: descriptors,
        truncated: page.hasMore,
      );
    } on McpTransportFailure catch (error) {
      throw McpSourceFailure(
        code: switch (error.code) {
          McpTransportFailureCode.cancelled => McpSourceFailureCode.cancelled,
          McpTransportFailureCode.unavailable =>
            McpSourceFailureCode.unavailable,
          McpTransportFailureCode.invalidResponse =>
            McpSourceFailureCode.schemaInvalid,
        },
        message: 'MCP discovery failed.',
      );
    }
  }

  @override
  Future<Map<String, Object?>> execute(
    ToolDescriptor descriptor,
    Map<String, Object?> arguments,
    AgentCancellationToken cancellation,
  ) async {
    try {
      return await _client.callTool(descriptor.id, arguments, cancellation);
    } on McpTransportFailure catch (error) {
      throw ToolAdapterFailure(
        code: error.code == McpTransportFailureCode.invalidResponse
            ? ToolAdapterFailureCode.invalidResponse
            : ToolAdapterFailureCode.unavailable,
        message: 'MCP tool invocation failed.',
      );
    }
  }
}
