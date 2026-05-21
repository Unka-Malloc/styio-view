import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../editor/document_state.dart';
import '../../environment/configuration/environment_variable_configuration.dart';
import '../../environment/system_compatibility/file_system/file_system.dart';
import '../../environment/system_compatibility/resource/resource.dart';
import '../../foundation/foundation.dart';
import '../../runtime/runtime_output_channels.dart';
import '../../toolchain/toolchain_catalog.dart';
import '../../toolchain/toolchain_catalog_change.dart';
import '../../toolchain/toolchain_codec.dart';
import '../../toolchain/toolchain_health_check.dart';
import '../../toolchain/toolchain_resolver.dart';
import '../../toolchain/toolchain_runtime.dart';
import '../contract/language_contract.dart';
import '../features/styio_semantic_token_feature.dart';
import 'language_service_foundation.dart';
import 'local_styio_language_service.dart';
import 'semantic_snapshot_event_bridge.dart';
import 'styio_service_capability.dart';
import 'styio_language_service.dart';

enum StyioServiceStatus { succeeded, failed, unavailable, protocolError, stale }

class StyioServiceDocument {
  const StyioServiceDocument({
    required this.documentId,
    required this.text,
    required this.revision,
    this.filePath,
    this.configPath,
    this.workingDirectory,
    this.languageId = 'styio',
  });

  factory StyioServiceDocument.fromDocumentState(
    DocumentState document, {
    String? filePath,
    String? configPath,
    String? workingDirectory,
    String languageId = 'styio',
  }) {
    return StyioServiceDocument(
      documentId: document.documentId,
      text: document.text,
      revision: document.revision,
      filePath: filePath,
      configPath: configPath,
      workingDirectory: workingDirectory,
      languageId: languageId,
    );
  }

  final String documentId;
  final String text;
  final int revision;
  final String? filePath;
  final String? configPath;
  final String? workingDirectory;
  final String languageId;
}

class StyioServiceDocumentMaterializer {
  const StyioServiceDocumentMaterializer({
    required this.fileSystemManager,
    required this.resourceManager,
  });

  final FileSystemManager fileSystemManager;
  final ResourceManager resourceManager;

  Future<T> materialize<T>(
    StyioServiceDocument document,
    Future<T> Function(StyioServiceDocument document) action,
  ) async {
    if (document.filePath != null) {
      return action(document);
    }
    final tempRoot = await resourceManager.createTempDirectory(
      'vityo_styio_service_',
    );
    final tempFilePath = fileSystemManager.joinPath(<String>[
      tempRoot,
      '${_safeFileStem(document.documentId)}.styio',
    ]);
    await fileSystemManager.writeText(tempFilePath, document.text);
    try {
      return await action(
        StyioServiceDocument(
          documentId: document.documentId,
          text: document.text,
          revision: document.revision,
          filePath: tempFilePath,
          configPath: document.configPath,
          workingDirectory: document.workingDirectory,
          languageId: document.languageId,
        ),
      );
    } finally {
      await fileSystemManager.delete(tempRoot, recursive: true);
    }
  }

  String _safeFileStem(String documentId) {
    final sanitized = documentId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    if (sanitized.isEmpty) {
      return 'unsaved';
    }
    return sanitized.length > 80 ? sanitized.substring(0, 80) : sanitized;
  }
}

class StyioServiceDiagnosticDto {
  const StyioServiceDiagnosticDto({
    required this.severity,
    required this.code,
    required this.message,
    required this.range,
  });

  final DiagnosticSeverity severity;
  final String code;
  final String message;
  final SourceRange range;
}

class StyioServiceResponse {
  const StyioServiceResponse({
    required this.status,
    required this.documentId,
    required this.revision,
    this.diagnostics = const <StyioServiceDiagnosticDto>[],
    this.completions = const <CompletionItem>[],
    this.hovers = const <HoverPayload>[],
    this.semanticSpans = const <SemanticSpan>[],
    this.formattingEdits = const <FormattingEdit>[],
    this.semanticBlocks = const <SemanticBlockRange>[],
    this.inlayHints = const <InlayHint>[],
    this.documentSymbols = const <DocumentSymbol>[],
    this.referenceSpans = const <ReferenceSpan>[],
    this.definitionTargets = const <DefinitionTarget>[],
    this.codeActions = const <DiagnosticQuickFix>[],
    this.renamePlans = const <RenamePlan>[],
    this.safeDeletePlans = const <SafeDeletePlan>[],
    this.inlineVariablePlans = const <InlineVariablePlan>[],
    this.introduceVariablePlans = const <IntroduceVariablePlan>[],
    this.extractFunctionPlans = const <ExtractFunctionPlan>[],
    this.changeSignaturePlans = const <ChangeSignaturePlan>[],
    this.parameterInfos = const <ParameterInfoPayload>[],
    this.surroundTemplates = const <SurroundTemplate>[],
    this.stdout = '',
    this.stderr = '',
    this.exitCode,
    this.message,
    this.protocolVersion = 'styio-cli-jsonl-v1',
    this.parserEngine,
    this.grammarVersion,
    this.toolchainId = '',
    this.configPath,
    this.workingDirectory,
    this.capabilityStates = const <String, String>{},
    this.capabilityMessages = const <String, String>{},
  });

  final StyioServiceStatus status;
  final String documentId;
  final int revision;
  final List<StyioServiceDiagnosticDto> diagnostics;
  final List<CompletionItem> completions;
  final List<HoverPayload> hovers;
  final List<SemanticSpan> semanticSpans;
  final List<FormattingEdit> formattingEdits;
  final List<SemanticBlockRange> semanticBlocks;
  final List<InlayHint> inlayHints;
  final List<DocumentSymbol> documentSymbols;
  final List<ReferenceSpan> referenceSpans;
  final List<DefinitionTarget> definitionTargets;
  final List<DiagnosticQuickFix> codeActions;
  final List<RenamePlan> renamePlans;
  final List<SafeDeletePlan> safeDeletePlans;
  final List<InlineVariablePlan> inlineVariablePlans;
  final List<IntroduceVariablePlan> introduceVariablePlans;
  final List<ExtractFunctionPlan> extractFunctionPlans;
  final List<ChangeSignaturePlan> changeSignaturePlans;
  final List<ParameterInfoPayload> parameterInfos;
  final List<SurroundTemplate> surroundTemplates;
  final String stdout;
  final String stderr;
  final int? exitCode;
  final String? message;
  final String protocolVersion;
  final String? parserEngine;
  final String? grammarVersion;
  final String toolchainId;
  final String? configPath;
  final String? workingDirectory;
  final Map<String, String> capabilityStates;
  final Map<String, String> capabilityMessages;

  bool get succeeded => status == StyioServiceStatus.succeeded;

  bool get hasPayload {
    return payloadCounts.values.any((count) => count > 0);
  }

  Map<String, int> get payloadCounts {
    return <String, int>{
      StyioServiceCapability.diagnostics.wireValue: diagnostics.length,
      StyioServiceCapability.completion.wireValue: completions.length,
      StyioServiceCapability.hover.wireValue: hovers.length,
      StyioServiceCapability.semanticTokens.wireValue: semanticSpans.length,
      StyioServiceCapability.formatting.wireValue: formattingEdits.length,
      StyioServiceCapability.semanticBlocks.wireValue: semanticBlocks.length,
      StyioServiceCapability.inlayHints.wireValue: inlayHints.length,
      StyioServiceCapability.documentSymbols.wireValue: documentSymbols.length,
      StyioServiceCapability.references.wireValue: referenceSpans.length,
      StyioServiceCapability.definition.wireValue: definitionTargets.length,
      StyioServiceCapability.codeActions.wireValue: codeActions.length,
      StyioServiceCapability.rename.wireValue: renamePlans.length,
      StyioServiceCapability.safeDelete.wireValue: safeDeletePlans.length,
      StyioServiceCapability.inlineVariable.wireValue:
          inlineVariablePlans.length,
      StyioServiceCapability.introduceVariable.wireValue:
          introduceVariablePlans.length,
      StyioServiceCapability.extractFunction.wireValue:
          extractFunctionPlans.length,
      StyioServiceCapability.changeSignature.wireValue:
          changeSignaturePlans.length,
      StyioServiceCapability.parameterInfo.wireValue: parameterInfos.length,
      StyioServiceCapability.surround.wireValue: surroundTemplates.length,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'documentId': documentId,
      'revision': revision,
      'protocolVersion': protocolVersion,
      if (toolchainId.isNotEmpty) 'toolchainId': toolchainId,
      if (exitCode != null) 'exitCode': exitCode,
      if (message != null) 'message': message,
      'succeeded': succeeded,
      'hasPayload': hasPayload,
      'payloadCounts': payloadCounts,
      if (parserEngine != null) 'parserEngine': parserEngine,
      if (grammarVersion != null) 'grammarVersion': grammarVersion,
      if (configPath != null) 'configPath': configPath,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      if (capabilityStates.isNotEmpty) 'capabilityStates': capabilityStates,
      'stdoutBytes': utf8.encode(stdout).length,
      'stderrBytes': utf8.encode(stderr).length,
    };
  }

  bool isStaleFor(DocumentState document) {
    return documentId != document.documentId || revision != document.revision;
  }
}

abstract class StyioServiceConnector {
  Future<StyioServiceResponse> analyzeDocument(StyioServiceDocument document);
}

class StyioCliJsonlProtocol {
  const StyioCliJsonlProtocol({
    this.parserEngine = 'nightly',
    this.protocolVersion = 'styio-cli-jsonl-v1',
    this.emitAstText = false,
    this.payloadCodec = const ToolchainPayloadCodec(),
  });

  final String parserEngine;
  final String protocolVersion;
  final bool emitAstText;
  final ToolchainPayloadCodec payloadCodec;

  List<String> analyzeArguments(StyioServiceDocument document) {
    final filePath = document.filePath;
    return <String>[
      '--parser-engine',
      parserEngine,
      if (emitAstText) '--styio-ast',
      '--error-format',
      'jsonl',
      if (document.configPath != null) ...<String>[
        '--config',
        document.configPath!,
      ],
      if (filePath != null) ...<String>['--file', filePath],
    ];
  }

  StyioServiceResponse decode({
    required StyioServiceDocument document,
    required String stdout,
    required String stderr,
    required int? exitCode,
    required bool toolchainSucceeded,
    String toolchainId = '',
    String? message,
  }) {
    final diagnostics = <StyioServiceDiagnosticDto>[];
    final completions = <CompletionItem>[];
    final hovers = <HoverPayload>[];
    final semanticSpans = <SemanticSpan>[];
    final formattingEdits = <FormattingEdit>[];
    final semanticBlocks = <SemanticBlockRange>[];
    final inlayHints = <InlayHint>[];
    final documentSymbols = <DocumentSymbol>[];
    final referenceSpans = <ReferenceSpan>[];
    final definitionTargets = <DefinitionTarget>[];
    final codeActions = <DiagnosticQuickFix>[];
    final renamePlans = <RenamePlan>[];
    final safeDeletePlans = <SafeDeletePlan>[];
    final inlineVariablePlans = <InlineVariablePlan>[];
    final introduceVariablePlans = <IntroduceVariablePlan>[];
    final extractFunctionPlans = <ExtractFunctionPlan>[];
    final changeSignaturePlans = <ChangeSignaturePlan>[];
    final parameterInfos = <ParameterInfoPayload>[];
    final surroundTemplates = <SurroundTemplate>[];
    final capabilityStates = <String, String>{};
    final capabilityMessages = <String, String>{};
    var effectiveProtocolVersion = protocolVersion;
    String? effectiveParserEngine = parserEngine;
    String? effectiveGrammarVersion;
    var protocolError = false;

    for (final line in _jsonLines(stdout, stderr)) {
      final decoded = _decodeJsonObject(line);
      if (decoded == null) {
        protocolError = true;
        continue;
      }
      effectiveProtocolVersion =
          _stringValue(decoded['protocolVersion']) ??
          _stringValue(decoded['protocol_version']) ??
          effectiveProtocolVersion;
      effectiveParserEngine =
          _stringValue(decoded['parserEngine']) ??
          _stringValue(decoded['parser_engine']) ??
          effectiveParserEngine;
      effectiveGrammarVersion =
          _stringValue(decoded['grammarVersion']) ??
          _stringValue(decoded['grammar_version']) ??
          effectiveGrammarVersion;
      final kind = _kindFromJson(decoded);
      switch (kind) {
        case _StyioJsonRecordKind.facts:
          _appendFactEnvelope(
            decoded,
            diagnostics: diagnostics,
            completions: completions,
            hovers: hovers,
            semanticSpans: semanticSpans,
            formattingEdits: formattingEdits,
            semanticBlocks: semanticBlocks,
            inlayHints: inlayHints,
            documentSymbols: documentSymbols,
            referenceSpans: referenceSpans,
            definitionTargets: definitionTargets,
            codeActions: codeActions,
            renamePlans: renamePlans,
            safeDeletePlans: safeDeletePlans,
            inlineVariablePlans: inlineVariablePlans,
            introduceVariablePlans: introduceVariablePlans,
            extractFunctionPlans: extractFunctionPlans,
            changeSignaturePlans: changeSignaturePlans,
            parameterInfos: parameterInfos,
            surroundTemplates: surroundTemplates,
            capabilityStates: capabilityStates,
            capabilityMessages: capabilityMessages,
          );
          break;
        case _StyioJsonRecordKind.capability:
          _appendCapabilityStates(
            decoded,
            capabilityStates,
            capabilityMessages,
          );
          break;
        case _StyioJsonRecordKind.diagnostic:
          final diagnostic = _diagnosticFromJson(decoded);
          if (diagnostic != null) {
            diagnostics.add(diagnostic);
          }
          break;
        case _StyioJsonRecordKind.completion:
          final completion = _completionFromJson(decoded);
          if (completion != null) {
            completions.add(completion);
          }
          break;
        case _StyioJsonRecordKind.hover:
          final hover = _hoverFromJson(decoded);
          if (hover != null) {
            hovers.add(hover);
          }
          break;
        case _StyioJsonRecordKind.semantic:
          final semantic = _semanticSpanFromJson(decoded);
          if (semantic != null) {
            semanticSpans.add(semantic);
          }
          break;
        case _StyioJsonRecordKind.formatting:
          final edit = _formattingEditFromJson(decoded);
          if (edit != null) {
            formattingEdits.add(edit);
          }
          break;
        case _StyioJsonRecordKind.semanticBlock:
          final block = _semanticBlockFromJson(decoded);
          if (block != null) {
            semanticBlocks.add(block);
          }
          break;
        case _StyioJsonRecordKind.inlayHint:
          final hint = _inlayHintFromJson(decoded);
          if (hint != null) {
            inlayHints.add(hint);
          }
          break;
        case _StyioJsonRecordKind.symbol:
          final symbol = _documentSymbolFromJson(decoded);
          if (symbol != null) {
            documentSymbols.add(symbol);
          }
          break;
        case _StyioJsonRecordKind.reference:
          final reference = _referenceSpanFromJson(decoded);
          if (reference != null) {
            referenceSpans.add(reference);
          }
          break;
        case _StyioJsonRecordKind.definition:
          final definition = _definitionTargetFromJson(decoded);
          if (definition != null) {
            definitionTargets.add(definition);
          }
          break;
        case _StyioJsonRecordKind.codeAction:
          final codeAction = _codeActionFromJson(decoded);
          if (codeAction != null) {
            codeActions.add(codeAction);
          }
          break;
        case _StyioJsonRecordKind.rename:
          final renamePlan = _renamePlanFromJson(decoded);
          if (renamePlan != null) {
            renamePlans.add(renamePlan);
          }
          break;
        case _StyioJsonRecordKind.safeDelete:
          final safeDeletePlan = _safeDeletePlanFromJson(decoded);
          if (safeDeletePlan != null) {
            safeDeletePlans.add(safeDeletePlan);
          }
          break;
        case _StyioJsonRecordKind.inlineVariable:
          final inlineVariablePlan = _inlineVariablePlanFromJson(decoded);
          if (inlineVariablePlan != null) {
            inlineVariablePlans.add(inlineVariablePlan);
          }
          break;
        case _StyioJsonRecordKind.introduceVariable:
          final introduceVariablePlan = _introduceVariablePlanFromJson(decoded);
          if (introduceVariablePlan != null) {
            introduceVariablePlans.add(introduceVariablePlan);
          }
          break;
        case _StyioJsonRecordKind.extractFunction:
          final extractFunctionPlan = _extractFunctionPlanFromJson(decoded);
          if (extractFunctionPlan != null) {
            extractFunctionPlans.add(extractFunctionPlan);
          }
          break;
        case _StyioJsonRecordKind.changeSignature:
          final changeSignaturePlan = _changeSignaturePlanFromJson(decoded);
          if (changeSignaturePlan != null) {
            changeSignaturePlans.add(changeSignaturePlan);
          }
          break;
        case _StyioJsonRecordKind.parameterInfo:
          final parameterInfo = _parameterInfoFromJson(decoded);
          if (parameterInfo != null) {
            parameterInfos.add(parameterInfo);
          }
          break;
        case _StyioJsonRecordKind.surround:
          final template = _surroundTemplateFromJson(decoded);
          if (template != null) {
            surroundTemplates.add(template);
          }
          break;
      }
    }

    final hasServiceFacts =
        diagnostics.isNotEmpty ||
        completions.isNotEmpty ||
        hovers.isNotEmpty ||
        semanticSpans.isNotEmpty ||
        formattingEdits.isNotEmpty ||
        semanticBlocks.isNotEmpty ||
        inlayHints.isNotEmpty ||
        documentSymbols.isNotEmpty ||
        referenceSpans.isNotEmpty ||
        definitionTargets.isNotEmpty ||
        codeActions.isNotEmpty ||
        renamePlans.isNotEmpty ||
        safeDeletePlans.isNotEmpty ||
        inlineVariablePlans.isNotEmpty ||
        introduceVariablePlans.isNotEmpty ||
        extractFunctionPlans.isNotEmpty ||
        changeSignaturePlans.isNotEmpty ||
        parameterInfos.isNotEmpty ||
        surroundTemplates.isNotEmpty;
    final status = protocolError && !hasServiceFacts
        ? StyioServiceStatus.protocolError
        : toolchainSucceeded || hasServiceFacts
        ? StyioServiceStatus.succeeded
        : StyioServiceStatus.failed;

    return StyioServiceResponse(
      status: status,
      documentId: document.documentId,
      revision: document.revision,
      diagnostics: List.unmodifiable(diagnostics),
      completions: List.unmodifiable(completions),
      hovers: List.unmodifiable(hovers),
      semanticSpans: List.unmodifiable(semanticSpans),
      formattingEdits: List.unmodifiable(formattingEdits),
      semanticBlocks: List.unmodifiable(semanticBlocks),
      inlayHints: List.unmodifiable(inlayHints),
      documentSymbols: List.unmodifiable(documentSymbols),
      referenceSpans: List.unmodifiable(referenceSpans),
      definitionTargets: List.unmodifiable(definitionTargets),
      codeActions: List.unmodifiable(codeActions),
      renamePlans: List.unmodifiable(renamePlans),
      safeDeletePlans: List.unmodifiable(safeDeletePlans),
      inlineVariablePlans: List.unmodifiable(inlineVariablePlans),
      introduceVariablePlans: List.unmodifiable(introduceVariablePlans),
      extractFunctionPlans: List.unmodifiable(extractFunctionPlans),
      changeSignaturePlans: List.unmodifiable(changeSignaturePlans),
      parameterInfos: List.unmodifiable(parameterInfos),
      surroundTemplates: List.unmodifiable(surroundTemplates),
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
      message: message,
      protocolVersion: effectiveProtocolVersion,
      parserEngine: effectiveParserEngine,
      grammarVersion: effectiveGrammarVersion,
      toolchainId: toolchainId,
      configPath: document.configPath,
      workingDirectory: document.workingDirectory,
      capabilityStates: Map<String, String>.unmodifiable(capabilityStates),
      capabilityMessages: Map<String, String>.unmodifiable(capabilityMessages),
    );
  }

  void _appendFactEnvelope(
    Map<String, Object?> json, {
    required List<StyioServiceDiagnosticDto> diagnostics,
    required List<CompletionItem> completions,
    required List<HoverPayload> hovers,
    required List<SemanticSpan> semanticSpans,
    required List<FormattingEdit> formattingEdits,
    required List<SemanticBlockRange> semanticBlocks,
    required List<InlayHint> inlayHints,
    required List<DocumentSymbol> documentSymbols,
    required List<ReferenceSpan> referenceSpans,
    required List<DefinitionTarget> definitionTargets,
    required List<DiagnosticQuickFix> codeActions,
    required List<RenamePlan> renamePlans,
    required List<SafeDeletePlan> safeDeletePlans,
    required List<InlineVariablePlan> inlineVariablePlans,
    required List<IntroduceVariablePlan> introduceVariablePlans,
    required List<ExtractFunctionPlan> extractFunctionPlans,
    required List<ChangeSignaturePlan> changeSignaturePlans,
    required List<ParameterInfoPayload> parameterInfos,
    required List<SurroundTemplate> surroundTemplates,
    required Map<String, String> capabilityStates,
    required Map<String, String> capabilityMessages,
  }) {
    final facts =
        _objectMap(json['facts']) ??
        _objectMap(json['semanticSnapshot']) ??
        _objectMap(json['snapshot']) ??
        json;
    _appendDecodedList(
      _firstPresent(facts, const <String>['diagnostics', 'errors']),
      diagnostics,
      _diagnosticFromJson,
    );
    _appendDecodedList(
      _firstPresent(facts, const <String>['completions', 'completionItems']),
      completions,
      _completionFromJson,
    );
    _appendDecodedList(facts['hovers'], hovers, _hoverFromJson);
    _appendDecodedList(
      _firstPresent(facts, const <String>[
        'semanticSpans',
        'semanticTokens',
        'semantic',
      ]),
      semanticSpans,
      _semanticSpanFromJson,
    );
    _appendDecodedList(
      _firstPresent(facts, const <String>['formattingEdits', 'formatting']),
      formattingEdits,
      _formattingEditFromJson,
    );
    _appendDecodedList(
      facts['semanticBlocks'],
      semanticBlocks,
      _semanticBlockFromJson,
    );
    _appendDecodedList(facts['inlayHints'], inlayHints, _inlayHintFromJson);
    _appendDecodedList(
      _firstPresent(facts, const <String>['documentSymbols', 'symbols']),
      documentSymbols,
      _documentSymbolFromJson,
    );
    _appendDecodedList(
      _firstPresent(facts, const <String>['references', 'referenceSpans']),
      referenceSpans,
      _referenceSpanFromJson,
    );
    _appendDecodedList(
      _firstPresent(facts, const <String>['definitions', 'definitionTargets']),
      definitionTargets,
      _definitionTargetFromJson,
    );
    _appendDecodedList(
      _firstPresent(facts, const <String>['codeActions', 'quickFixes']),
      codeActions,
      _codeActionFromJson,
    );
    _appendDecodedList(
      _firstPresent(facts, const <String>['renamePlans', 'renames']),
      renamePlans,
      _renamePlanFromJson,
    );
    _appendDecodedList(
      facts['safeDeletePlans'],
      safeDeletePlans,
      _safeDeletePlanFromJson,
    );
    _appendDecodedList(
      facts['inlineVariablePlans'],
      inlineVariablePlans,
      _inlineVariablePlanFromJson,
    );
    _appendDecodedList(
      facts['introduceVariablePlans'],
      introduceVariablePlans,
      _introduceVariablePlanFromJson,
    );
    _appendDecodedList(
      facts['extractFunctionPlans'],
      extractFunctionPlans,
      _extractFunctionPlanFromJson,
    );
    _appendDecodedList(
      facts['changeSignaturePlans'],
      changeSignaturePlans,
      _changeSignaturePlanFromJson,
    );
    _appendDecodedList(
      _firstPresent(facts, const <String>['parameterInfos', 'signatureHelp']),
      parameterInfos,
      _parameterInfoFromJson,
    );
    _appendDecodedList(
      _firstPresent(facts, const <String>['surroundTemplates', 'surrounds']),
      surroundTemplates,
      _surroundTemplateFromJson,
    );
    _appendCapabilityStates(
      facts['capabilities'],
      capabilityStates,
      capabilityMessages,
    );
  }

  void _appendCapabilityStates(
    Object? value,
    Map<String, String> states,
    Map<String, String> messages,
  ) {
    final object = _objectMap(value);
    if (object != null) {
      final capability =
          _stringValue(object['capability']) ??
          _stringValue(object['name']) ??
          _stringValue(object['id']);
      final state =
          _stringValue(object['state']) ?? _stringValue(object['status']);
      if (capability != null && state != null) {
        final capabilityKey = normalizeStyioServiceCapabilityKey(capability);
        states[capabilityKey] = state;
        final message = _stringValue(object['message']);
        if (message != null) {
          messages[capabilityKey] = message;
        }
        return;
      }
      for (final entry in object.entries) {
        final capabilityKey = normalizeStyioServiceCapabilityKey(entry.key);
        final nested = _objectMap(entry.value);
        if (nested != null) {
          final nestedState =
              _stringValue(nested['state']) ?? _stringValue(nested['status']);
          if (nestedState != null) {
            states[capabilityKey] = nestedState;
            final message = _stringValue(nested['message']);
            if (message != null) {
              messages[capabilityKey] = message;
            }
          }
          continue;
        }
        final valueState = _stringValue(entry.value);
        if (valueState != null) {
          states[capabilityKey] = valueState;
        }
      }
      return;
    }
    if (value is List) {
      for (final entry in value) {
        _appendCapabilityStates(entry, states, messages);
      }
    }
  }

  void _appendDecodedList<T>(
    Object? value,
    List<T> output,
    T? Function(Map<String, Object?> json) decode,
  ) {
    for (final json in _objectMaps(value)) {
      final decoded = decode(json);
      if (decoded != null) {
        output.add(decoded);
      }
    }
  }

  Iterable<Map<String, Object?>> _objectMaps(Object? value) sync* {
    final object = _objectMap(value);
    if (object != null) {
      yield object;
      return;
    }
    if (value is List) {
      for (final entry in value) {
        final nested = _objectMap(entry);
        if (nested != null) {
          yield nested;
        }
      }
    }
  }

  Object? _firstPresent(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key)) {
        return json[key];
      }
    }
    return null;
  }

  Iterable<String> _jsonLines(String stdout, String stderr) sync* {
    for (final text in <String>[stdout, stderr]) {
      for (final rawLine in const LineSplitter().convert(text)) {
        final line = rawLine.trim();
        if (line.startsWith('{') && line.endsWith('}')) {
          yield line;
        }
      }
    }
  }

  Map<String, Object?>? _decodeJsonObject(String line) {
    try {
      return payloadCodec.decodeJson(
        ToolchainPayload(
          format: ToolchainPayloadFormat.json,
          bytes: Uint8List.fromList(utf8.encode(line)),
          contentType: 'application/json',
          metadata: const <String, Object?>{'protocol': 'styio-cli-jsonl-v1'},
        ),
      );
    } on FormatException {
      return null;
    }
  }

  StyioServiceDiagnosticDto? _diagnosticFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['diagnostic']) ?? _objectMap(json['error']) ?? json;
    final range = _rangeFromJson(nested);
    if (range == null) {
      return null;
    }

    return StyioServiceDiagnosticDto(
      severity: _severityFromJson(nested['severity']),
      code: _stringValue(nested['code']) ?? 'styio.diagnostic',
      message: _stringValue(nested['message']) ?? 'Styio diagnostic.',
      range: range,
    );
  }

  CompletionItem? _completionFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['completion']) ?? _objectMap(json['item']) ?? json;
    final label = _stringValue(nested['label']) ?? _stringValue(nested['name']);
    if (label == null || label.isEmpty) {
      return null;
    }
    return CompletionItem(
      label: label,
      kind: _completionKindFromJson(nested['kind']),
      insertText: _stringValue(nested['insertText']) ?? label,
      detail: _stringValue(nested['detail']) ?? '',
      documentation: _stringValue(nested['documentation']) ?? '',
      replacementRange: _rangeFromJson(nested),
    );
  }

  HoverPayload? _hoverFromJson(Map<String, Object?> json) {
    final nested = _objectMap(json['hover']) ?? json;
    final range = _rangeFromJson(nested);
    final markdown =
        _stringValue(nested['markdown']) ?? _stringValue(nested['contents']);
    if (range == null || markdown == null) {
      return null;
    }
    return HoverPayload(range: range, markdown: markdown);
  }

  SemanticSpan? _semanticSpanFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['semantic']) ??
        _objectMap(json['semanticToken']) ??
        json;
    final range = _rangeFromJson(nested);
    if (range == null) {
      return null;
    }
    return SemanticSpan(
      range: range,
      kind: _semanticKindFromJson(nested['kind']),
      modifiers: _stringList(nested['modifiers']),
    );
  }

  FormattingEdit? _formattingEditFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['formattingEdit']) ?? _objectMap(json['edit']) ?? json;
    final range = _rangeFromJson(nested);
    final newText =
        _stringValue(nested['newText']) ?? _stringValue(nested['replacement']);
    if (range == null || newText == null) {
      return null;
    }
    return FormattingEdit(range: range, newText: newText);
  }

  SemanticBlockRange? _semanticBlockFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['semanticBlock']) ?? _objectMap(json['block']) ?? json;
    final range = _rangeFromJson(nested);
    final label = _stringValue(nested['label']);
    if (range == null || label == null) {
      return null;
    }
    return SemanticBlockRange(range: range, label: label);
  }

  InlayHint? _inlayHintFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['inlayHint']) ?? _objectMap(json['hint']) ?? json;
    final label = _stringValue(nested['label']);
    final position = _intValue(nested['position']);
    final range = _rangeFromJson(nested);
    if (label == null || position == null || range == null) {
      return null;
    }
    return InlayHint(
      label: label,
      kind: _inlayHintKindFromJson(nested['kind']),
      position: position,
      range: range,
    );
  }

  DocumentSymbol? _documentSymbolFromJson(Map<String, Object?> json) {
    final nested = _objectMap(json['symbol']) ?? json;
    final name = _stringValue(nested['name']);
    final nameRange = _rangeFromJson(_objectMap(nested['nameRange']) ?? nested);
    final declarationRange =
        _rangeFromJson(_objectMap(nested['declarationRange']) ?? nested) ??
        nameRange;
    if (name == null || nameRange == null || declarationRange == null) {
      return null;
    }
    return DocumentSymbol(
      name: name,
      kind: _symbolKindFromJson(nested['kind']),
      nameRange: nameRange,
      declarationRange: declarationRange,
      detail: _stringValue(nested['detail']) ?? '',
      documentation: _stringValue(nested['documentation']) ?? '',
    );
  }

  ReferenceSpan? _referenceSpanFromJson(Map<String, Object?> json) {
    final nested = _objectMap(json['reference']) ?? json;
    final name = _stringValue(nested['name']);
    final range = _rangeFromJson(nested);
    final targetRange = _rangeFromJson(
      _objectMap(nested['targetRange']) ?? <String, Object?>{},
    );
    if (name == null || range == null || targetRange == null) {
      return null;
    }
    return ReferenceSpan(
      name: name,
      kind: _symbolKindFromJson(nested['kind']),
      range: range,
      targetRange: targetRange,
      isDeclaration: nested['isDeclaration'] == true,
      access: _referenceAccessFromJson(nested['access']),
    );
  }

  DefinitionTarget? _definitionTargetFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['definition']) ??
        _objectMap(json['definitionTarget']) ??
        json;
    final symbol = _documentSymbolFromJson(
      _objectMap(nested['symbol']) ?? _objectMap(nested['target']) ?? nested,
    );
    final originRange = _rangeFromJson(
      _objectMap(nested['originRange']) ??
          _objectMap(nested['origin']) ??
          _objectMap(nested['sourceRange']) ??
          nested,
    );
    if (symbol == null || originRange == null) {
      return null;
    }
    return DefinitionTarget(symbol: symbol, originRange: originRange);
  }

  DiagnosticQuickFix? _codeActionFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['codeAction']) ??
        _objectMap(json['quickFix']) ??
        _objectMap(json['intention']) ??
        json;
    final label =
        _stringValue(nested['label']) ?? _stringValue(nested['title']);
    if (label == null || label.isEmpty) {
      return null;
    }
    return DiagnosticQuickFix(
      label: label,
      detail: _stringValue(nested['detail']) ?? '',
      edits: _formattingEditsFromJson(nested['edits']),
    );
  }

  SurroundTemplate? _surroundTemplateFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['surroundTemplate']) ??
        _objectMap(json['surround']) ??
        _objectMap(json['template']) ??
        json;
    final id = _stringValue(nested['id']) ?? _stringValue(nested['key']);
    final label =
        _stringValue(nested['label']) ?? _stringValue(nested['title']) ?? id;
    final openingLine =
        _stringValue(nested['openingLine']) ??
        _stringValue(nested['opening']) ??
        _stringValue(nested['open']);
    final closingLine =
        _stringValue(nested['closingLine']) ??
        _stringValue(nested['closing']) ??
        _stringValue(nested['close']);
    if (id == null ||
        id.isEmpty ||
        label == null ||
        label.isEmpty ||
        openingLine == null ||
        closingLine == null) {
      return null;
    }
    return SurroundTemplate(
      id: id,
      label: label,
      openingLine: openingLine,
      closingLine: closingLine,
      bodyIndent: _stringValue(nested['bodyIndent']) ?? '  ',
      detail: _stringValue(nested['detail']) ?? '',
    );
  }

  ParameterInfoPayload? _parameterInfoFromJson(Map<String, Object?> json) {
    final nested = _objectMap(json['parameterInfo']) ?? json;
    final callableName = _stringValue(nested['callableName']);
    final signature = _stringValue(nested['signature']);
    final activeParameterIndex =
        _intValue(nested['activeParameterIndex']) ?? -1;
    final invocationRange = _rangeFromJson(
      _objectMap(nested['invocationRange']) ??
          _objectMap(nested['range']) ??
          nested,
    );
    final callableRange =
        _rangeFromJson(
          _objectMap(nested['callableRange']) ??
              _objectMap(nested['callable']) ??
              <String, Object?>{},
        ) ??
        invocationRange;
    if (callableName == null ||
        signature == null ||
        invocationRange == null ||
        callableRange == null) {
      return null;
    }
    return ParameterInfoPayload(
      callableName: callableName,
      signature: signature,
      parameters: _parametersFromJson(nested['parameters']),
      activeParameterIndex: activeParameterIndex,
      invocationRange: invocationRange,
      callableRange: callableRange,
      documentation: _stringValue(nested['documentation']) ?? '',
    );
  }

  List<ParameterInfoParameter> _parametersFromJson(Object? value) {
    if (value is! List) {
      return const <ParameterInfoParameter>[];
    }
    final parameters = <ParameterInfoParameter>[];
    for (final entry in value) {
      final json = _objectMap(entry);
      if (json == null) {
        continue;
      }
      final name = _stringValue(json['name']);
      final range =
          _rangeFromJson(
            _objectMap(json['range']) ?? _objectMap(json['nameRange']) ?? json,
          ) ??
          const SourceRange(start: 0, end: 0);
      if (name == null) {
        continue;
      }
      parameters.add(
        ParameterInfoParameter(
          name: name,
          range: range,
          type: _stringValue(json['type']) ?? '',
          defaultValue: _stringValue(json['defaultValue']) ?? '',
          documentation: _stringValue(json['documentation']) ?? '',
        ),
      );
    }
    return parameters;
  }

  RenamePlan? _renamePlanFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['rename']) ?? _objectMap(json['renamePlan']) ?? json;
    final targetJson = _objectMap(nested['target']);
    final target = targetJson == null
        ? null
        : _documentSymbolFromJson(targetJson);
    final newName = _stringValue(nested['newName']);
    if (target == null || newName == null || newName.isEmpty) {
      return null;
    }
    return RenamePlan(
      target: target,
      newName: newName,
      references: _referenceSpansFromJson(nested['references']),
      edits: _formattingEditsFromJson(nested['edits']),
      conflicts: _renameConflictsFromJson(nested['conflicts']),
    );
  }

  SafeDeletePlan? _safeDeletePlanFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['safeDelete']) ??
        _objectMap(json['safeDeletePlan']) ??
        json;
    final targetJson = _objectMap(nested['target']);
    final target = targetJson == null
        ? null
        : _documentSymbolFromJson(targetJson);
    if (target == null) {
      return null;
    }
    return SafeDeletePlan(
      target: target,
      references: _referenceSpansFromJson(nested['references']),
      edits: _formattingEditsFromJson(nested['edits']),
      conflicts: _safeDeleteConflictsFromJson(nested['conflicts']),
    );
  }

  InlineVariablePlan? _inlineVariablePlanFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['inlineVariable']) ??
        _objectMap(json['inlineVariablePlan']) ??
        json;
    final targetJson = _objectMap(nested['target']);
    final target = targetJson == null
        ? null
        : _documentSymbolFromJson(targetJson);
    final initializerRange = _rangeFromJson(
      _objectMap(nested['initializerRange']) ?? <String, Object?>{},
    );
    final initializerText = _stringValue(nested['initializerText']);
    if (target == null || initializerRange == null || initializerText == null) {
      return null;
    }
    return InlineVariablePlan(
      target: target,
      initializerRange: initializerRange,
      initializerText: initializerText,
      references: _referenceSpansFromJson(nested['references']),
      edits: _formattingEditsFromJson(nested['edits']),
      conflicts: _inlineVariableConflictsFromJson(nested['conflicts']),
    );
  }

  IntroduceVariablePlan? _introduceVariablePlanFromJson(
    Map<String, Object?> json,
  ) {
    final nested =
        _objectMap(json['introduceVariable']) ??
        _objectMap(json['introduceVariablePlan']) ??
        json;
    final variableName =
        _stringValue(nested['variableName']) ?? _stringValue(nested['name']);
    final expressionRange = _rangeFromJson(
      _objectMap(nested['expressionRange']) ?? <String, Object?>{},
    );
    final expressionText = _stringValue(nested['expressionText']);
    if (variableName == null ||
        expressionRange == null ||
        expressionText == null) {
      return null;
    }
    return IntroduceVariablePlan(
      variableName: variableName,
      expressionRange: expressionRange,
      expressionText: expressionText,
      edits: _formattingEditsFromJson(nested['edits']),
      conflicts: _introduceVariableConflictsFromJson(nested['conflicts']),
    );
  }

  ExtractFunctionPlan? _extractFunctionPlanFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['extractFunction']) ??
        _objectMap(json['extractFunctionPlan']) ??
        json;
    final functionName =
        _stringValue(nested['functionName']) ?? _stringValue(nested['name']);
    final selectionRange = _rangeFromJson(
      _objectMap(nested['selectionRange']) ?? <String, Object?>{},
    );
    final selectedText = _stringValue(nested['selectedText']);
    final callText = _stringValue(nested['callText']);
    final functionText = _stringValue(nested['functionText']);
    if (functionName == null ||
        selectionRange == null ||
        selectedText == null ||
        callText == null ||
        functionText == null) {
      return null;
    }
    return ExtractFunctionPlan(
      functionName: functionName,
      selectionRange: selectionRange,
      selectedText: selectedText,
      parameters: _stringList(nested['parameters']),
      callText: callText,
      functionText: functionText,
      edits: _formattingEditsFromJson(nested['edits']),
      duplicateOccurrences: _rangesFromJson(nested['duplicateOccurrences']),
      conflicts: _extractFunctionConflictsFromJson(nested['conflicts']),
    );
  }

  ChangeSignaturePlan? _changeSignaturePlanFromJson(Map<String, Object?> json) {
    final nested =
        _objectMap(json['changeSignature']) ??
        _objectMap(json['changeSignaturePlan']) ??
        json;
    final targetJson = _objectMap(nested['target']);
    final target = targetJson == null
        ? null
        : _documentSymbolFromJson(targetJson);
    final originalName = _stringValue(nested['originalName']);
    final newName = _stringValue(nested['newName']);
    if (target == null ||
        originalName == null ||
        originalName.isEmpty ||
        newName == null ||
        newName.isEmpty) {
      return null;
    }
    return ChangeSignaturePlan(
      target: target,
      originalName: originalName,
      newName: newName,
      originalParameters: _parametersFromJson(nested['originalParameters']),
      newParameters: _parameterUpdatesFromJson(nested['newParameters']),
      references: _referenceSpansFromJson(nested['references']),
      edits: _formattingEditsFromJson(nested['edits']),
      conflicts: _changeSignatureConflictsFromJson(nested['conflicts']),
    );
  }

  List<ReferenceSpan> _referenceSpansFromJson(Object? value) {
    if (value is! List) {
      return const <ReferenceSpan>[];
    }
    final references = <ReferenceSpan>[];
    for (final entry in value) {
      final json = _objectMap(entry);
      if (json == null) {
        continue;
      }
      final reference = _referenceSpanFromJson(json);
      if (reference != null) {
        references.add(reference);
      }
    }
    return references;
  }

  List<RenameConflict> _renameConflictsFromJson(Object? value) {
    if (value is! List) {
      return const <RenameConflict>[];
    }
    final conflicts = <RenameConflict>[];
    for (final entry in value) {
      final json = _objectMap(entry);
      if (json == null) {
        continue;
      }
      final range = _rangeFromJson(json);
      final message = _stringValue(json['message']);
      if (range == null || message == null) {
        continue;
      }
      conflicts.add(RenameConflict(message: message, range: range));
    }
    return conflicts;
  }

  List<SafeDeleteConflict> _safeDeleteConflictsFromJson(Object? value) {
    if (value is! List) {
      return const <SafeDeleteConflict>[];
    }
    final conflicts = <SafeDeleteConflict>[];
    for (final entry in value) {
      final json = _objectMap(entry);
      if (json == null) {
        continue;
      }
      final range = _rangeFromJson(json);
      final message = _stringValue(json['message']);
      if (range == null || message == null) {
        continue;
      }
      conflicts.add(SafeDeleteConflict(message: message, range: range));
    }
    return conflicts;
  }

  List<InlineVariableConflict> _inlineVariableConflictsFromJson(Object? value) {
    if (value is! List) {
      return const <InlineVariableConflict>[];
    }
    final conflicts = <InlineVariableConflict>[];
    for (final entry in value) {
      final json = _objectMap(entry);
      if (json == null) {
        continue;
      }
      final range = _rangeFromJson(json);
      final message = _stringValue(json['message']);
      if (range == null || message == null) {
        continue;
      }
      conflicts.add(InlineVariableConflict(message: message, range: range));
    }
    return conflicts;
  }

  List<IntroduceVariableConflict> _introduceVariableConflictsFromJson(
    Object? value,
  ) {
    if (value is! List) {
      return const <IntroduceVariableConflict>[];
    }
    final conflicts = <IntroduceVariableConflict>[];
    for (final entry in value) {
      final json = _objectMap(entry);
      if (json == null) {
        continue;
      }
      final range = _rangeFromJson(json);
      final message = _stringValue(json['message']);
      if (range == null || message == null) {
        continue;
      }
      conflicts.add(IntroduceVariableConflict(message: message, range: range));
    }
    return conflicts;
  }

  List<ExtractFunctionConflict> _extractFunctionConflictsFromJson(
    Object? value,
  ) {
    if (value is! List) {
      return const <ExtractFunctionConflict>[];
    }
    final conflicts = <ExtractFunctionConflict>[];
    for (final entry in value) {
      final json = _objectMap(entry);
      if (json == null) {
        continue;
      }
      final range = _rangeFromJson(json);
      final message = _stringValue(json['message']);
      if (range == null || message == null) {
        continue;
      }
      conflicts.add(ExtractFunctionConflict(message: message, range: range));
    }
    return conflicts;
  }

  List<ChangeSignatureConflict> _changeSignatureConflictsFromJson(
    Object? value,
  ) {
    if (value is! List) {
      return const <ChangeSignatureConflict>[];
    }
    final conflicts = <ChangeSignatureConflict>[];
    for (final entry in value) {
      final json = _objectMap(entry);
      if (json == null) {
        continue;
      }
      final range = _rangeFromJson(json);
      final message = _stringValue(json['message']);
      if (range == null || message == null) {
        continue;
      }
      conflicts.add(ChangeSignatureConflict(message: message, range: range));
    }
    return conflicts;
  }

  List<FormattingEdit> _formattingEditsFromJson(Object? value) {
    if (value is! List) {
      return const <FormattingEdit>[];
    }
    final edits = <FormattingEdit>[];
    for (final entry in value) {
      final editJson = _objectMap(entry);
      if (editJson == null) {
        continue;
      }
      final edit = _formattingEditFromJson(editJson);
      if (edit != null) {
        edits.add(edit);
      }
    }
    return edits;
  }

  List<SourceRange> _rangesFromJson(Object? value) {
    if (value is! List) {
      return const <SourceRange>[];
    }
    final ranges = <SourceRange>[];
    for (final entry in value) {
      final json = _objectMap(entry);
      if (json == null) {
        continue;
      }
      final range = _rangeFromJson(json);
      if (range != null) {
        ranges.add(range);
      }
    }
    return ranges;
  }

  List<ChangeSignatureParameterUpdate> _parameterUpdatesFromJson(
    Object? value,
  ) {
    if (value is! List) {
      return const <ChangeSignatureParameterUpdate>[];
    }
    final updates = <ChangeSignatureParameterUpdate>[];
    for (final entry in value) {
      final json = _objectMap(entry);
      if (json == null) {
        continue;
      }
      final name = _stringValue(json['name']);
      final originalName = _stringValue(json['originalName']) ?? name;
      if (name == null || originalName == null) {
        continue;
      }
      updates.add(
        ChangeSignatureParameterUpdate(originalName: originalName, name: name),
      );
    }
    return updates;
  }

  _StyioJsonRecordKind _kindFromJson(Map<String, Object?> json) {
    final kind =
        _stringValue(json['kind']) ??
        _stringValue(json['type']) ??
        _stringValue(json['record']);
    switch (_normalizedStyioServiceRecordKind(kind)) {
      case 'facts':
      case 'semanticfacts':
      case 'semanticsnapshot':
      case 'languagesnapshot':
        return _StyioJsonRecordKind.facts;
      case 'capability':
      case 'capabilitystate':
      case 'capabilitystatus':
        return _StyioJsonRecordKind.capability;
      case 'completion':
      case 'completionitem':
        return _StyioJsonRecordKind.completion;
      case 'hover':
        return _StyioJsonRecordKind.hover;
      case 'semantic':
      case 'semantictoken':
      case 'semanticspan':
        return _StyioJsonRecordKind.semantic;
      case 'formatting':
      case 'formattingedit':
      case 'formatedit':
        return _StyioJsonRecordKind.formatting;
      case 'semanticblock':
      case 'block':
        return _StyioJsonRecordKind.semanticBlock;
      case 'inlayhint':
      case 'inlay':
        return _StyioJsonRecordKind.inlayHint;
      case 'symbol':
      case 'documentsymbol':
        return _StyioJsonRecordKind.symbol;
      case 'reference':
      case 'referencespan':
        return _StyioJsonRecordKind.reference;
      case 'definition':
      case 'definitiontarget':
        return _StyioJsonRecordKind.definition;
      case 'codeaction':
      case 'quickfix':
      case 'intention':
        return _StyioJsonRecordKind.codeAction;
      case 'rename':
      case 'renameplan':
        return _StyioJsonRecordKind.rename;
      case 'safedelete':
      case 'safedeleteplan':
        return _StyioJsonRecordKind.safeDelete;
      case 'inlinevariable':
      case 'inlinevariableplan':
        return _StyioJsonRecordKind.inlineVariable;
      case 'introducevariable':
      case 'introducevariableplan':
        return _StyioJsonRecordKind.introduceVariable;
      case 'extractfunction':
      case 'extractfunctionplan':
        return _StyioJsonRecordKind.extractFunction;
      case 'changesignature':
      case 'changesignatureplan':
        return _StyioJsonRecordKind.changeSignature;
      case 'parameterinfo':
      case 'signaturehelp':
        return _StyioJsonRecordKind.parameterInfo;
      case 'surround':
      case 'surroundtemplate':
      case 'surroundtemplateitem':
        return _StyioJsonRecordKind.surround;
      case 'diagnostic':
      case 'error':
      default:
        return _StyioJsonRecordKind.diagnostic;
    }
  }

  String? _normalizedStyioServiceRecordKind(String? value) {
    return value?.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  SourceRange? _rangeFromJson(Map<String, Object?> json) {
    final range =
        _objectMap(json['range']) ??
        _objectMap(json['span']) ??
        _objectMap(json['location']);
    final source = range ?? json;
    final start =
        _intValue(source['start']) ??
        _intValue(source['offset']) ??
        _intValue(source['startOffset']);
    final end =
        _intValue(source['end']) ??
        _intValue(source['endOffset']) ??
        _intValue(source['length'], base: start);

    if (start == null || end == null) {
      return null;
    }

    return SourceRange(start: start, end: end < start ? start : end);
  }

  Map<String, Object?>? _objectMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, nestedValue) => MapEntry(key.toString(), nestedValue as Object?),
      );
    }
    return null;
  }

  DiagnosticSeverity _severityFromJson(Object? value) {
    final text = _stringValue(value)?.toLowerCase();
    switch (text) {
      case 'error':
      case 'fatal':
        return DiagnosticSeverity.error;
      case 'warning':
      case 'warn':
        return DiagnosticSeverity.warning;
      case 'hint':
      case 'info':
      case 'information':
        return DiagnosticSeverity.hint;
    }
    return DiagnosticSeverity.error;
  }

  CompletionItemKind _completionKindFromJson(Object? value) {
    switch (_stringValue(value)?.toLowerCase()) {
      case 'function':
        return CompletionItemKind.function;
      case 'variable':
        return CompletionItemKind.variable;
      case 'snippet':
        return CompletionItemKind.snippet;
      case 'keyword':
      default:
        return CompletionItemKind.keyword;
    }
  }

  SemanticKind _semanticKindFromJson(Object? value) {
    switch (_stringValue(value)?.toLowerCase()) {
      case 'function':
        return SemanticKind.function;
      case 'pipeline':
        return SemanticKind.pipeline;
      case 'state':
        return SemanticKind.state;
      case 'resource':
        return SemanticKind.resource;
      case 'parameter':
        return SemanticKind.parameter;
      case 'typename':
      case 'type':
        return SemanticKind.typeName;
      case 'variable':
      default:
        return SemanticKind.variable;
    }
  }

  SymbolKind _symbolKindFromJson(Object? value) {
    switch (_stringValue(value)?.toLowerCase()) {
      case 'function':
        return SymbolKind.function;
      case 'pipeline':
        return SymbolKind.pipeline;
      case 'state':
        return SymbolKind.state;
      case 'resource':
        return SymbolKind.resource;
      case 'parameter':
        return SymbolKind.parameter;
      case 'task':
        return SymbolKind.task;
      case 'variable':
      default:
        return SymbolKind.variable;
    }
  }

  ReferenceAccess _referenceAccessFromJson(Object? value) {
    switch (_stringValue(value)?.toLowerCase()) {
      case 'declaration':
        return ReferenceAccess.declaration;
      case 'write':
        return ReferenceAccess.write;
      case 'read':
      default:
        return ReferenceAccess.read;
    }
  }

  InlayHintKind _inlayHintKindFromJson(Object? value) {
    switch (_stringValue(value)?.toLowerCase()) {
      case 'parameter':
        return InlayHintKind.parameter;
      case 'type':
      default:
        return InlayHintKind.type;
    }
  }

  int? _intValue(Object? value, {int? base}) {
    if (value is int) {
      return base == null ? value : base + value;
    }
    if (value is num) {
      final number = value.toInt();
      return base == null ? number : base + number;
    }
    if (value is String) {
      final number = int.tryParse(value);
      if (number == null) {
        return null;
      }
      return base == null ? number : base + number;
    }
    return null;
  }

  String? _stringValue(Object? value) {
    if (value == null) {
      return null;
    }
    return value.toString();
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value.map((entry) => entry.toString()).toList(growable: false);
    }
    return const <String>[];
  }
}

class ToolchainStyioServiceConnector implements StyioServiceConnector {
  const ToolchainStyioServiceConnector({
    required ToolchainRuntime runtime,
    this.protocol = const StyioCliJsonlProtocol(),
    this.documentMaterializer,
    ToolchainRequirement? requirement,
    this.timeout = const Duration(seconds: 10),
  }) : _runtime = runtime,
       _requirement = requirement;

  final ToolchainRuntime _runtime;
  final StyioCliJsonlProtocol protocol;
  final StyioServiceDocumentMaterializer? documentMaterializer;
  final ToolchainRequirement? _requirement;
  final Duration timeout;

  Future<ToolchainHealthReport> checkHealth({
    List<String>? probeArguments,
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
  }) {
    return _runtime.checkHealth(
      kind: ToolchainKind.languageService,
      requirement:
          _requirement ??
          ToolchainRequirement(
            kind: ToolchainKind.languageService,
            metadata: <String, Object?>{'contract': protocol.protocolVersion},
          ),
      probeArguments: probeArguments,
      environment: environment,
      environmentOverlays: environmentOverlays,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
  }

  @override
  Future<StyioServiceResponse> analyzeDocument(
    StyioServiceDocument document,
  ) async {
    final materializer = documentMaterializer;
    if (document.filePath == null && materializer != null) {
      try {
        return await materializer.materialize(document, _analyzeMaterialized);
      } on Object catch (error) {
        return StyioServiceResponse(
          status: StyioServiceStatus.unavailable,
          documentId: document.documentId,
          revision: document.revision,
          message: 'Failed to materialize Styio document: $error',
          configPath: document.configPath,
          workingDirectory: document.workingDirectory,
        );
      }
    }
    if (document.filePath == null) {
      return StyioServiceResponse(
        status: StyioServiceStatus.unavailable,
        documentId: document.documentId,
        revision: document.revision,
        message: 'Styio CLI analysis requires a file path or materializer.',
        configPath: document.configPath,
        workingDirectory: document.workingDirectory,
      );
    }
    return _analyzeMaterialized(document);
  }

  Future<StyioServiceResponse> _analyzeMaterialized(
    StyioServiceDocument document,
  ) async {
    final result = await _runtime.run(
      kind: ToolchainKind.languageService,
      requirement:
          _requirement ??
          ToolchainRequirement(
            kind: ToolchainKind.languageService,
            metadata: <String, Object?>{'contract': protocol.protocolVersion},
          ),
      arguments: protocol.analyzeArguments(document),
      workingDirectory: document.workingDirectory,
      timeout: timeout,
    );

    if (result.status == ToolchainRuntimeStatus.blocked) {
      return StyioServiceResponse(
        status: StyioServiceStatus.unavailable,
        documentId: document.documentId,
        revision: document.revision,
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        message: result.message,
        toolchainId: result.toolchainId,
        configPath: document.configPath,
        workingDirectory: document.workingDirectory,
      );
    }

    return protocol.decode(
      document: document,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      toolchainSucceeded: result.succeeded,
      toolchainId: result.toolchainId,
      message: result.message,
    );
  }
}

class StyioServiceResultAdapter {
  const StyioServiceResultAdapter();

  List<Diagnostic> diagnosticsFromResponse(StyioServiceResponse response) {
    return response.diagnostics
        .map(
          (diagnostic) => Diagnostic(
            severity: diagnostic.severity,
            code: diagnostic.code,
            message: diagnostic.message,
            range: diagnostic.range,
          ),
        )
        .toList(growable: false);
  }

  StyioDocumentAnalysis mergeAnalysis({
    required DocumentState document,
    required StyioDocumentAnalysis localAnalysis,
    required StyioServiceResponse response,
  }) {
    if (response.isStaleFor(document)) {
      return localAnalysis;
    }

    final responseDiagnostics = diagnosticsFromResponse(response)
        .where((diagnostic) => _isSafeRange(document, diagnostic.range))
        .toList(growable: false);
    final diagnostics = switch (response.status) {
      StyioServiceStatus.succeeded => responseDiagnostics,
      StyioServiceStatus.failed =>
        responseDiagnostics.isEmpty
            ? localAnalysis.diagnostics
            : responseDiagnostics,
      StyioServiceStatus.unavailable => localAnalysis.diagnostics,
      StyioServiceStatus.protocolError => localAnalysis.diagnostics,
      StyioServiceStatus.stale => localAnalysis.diagnostics,
    };

    final responseFormattingEdits = normalizeFormattingEditsForDocument(
      documentLength: document.length,
      edits: response.formattingEdits,
    );
    final formattingEdits = responseFormattingEdits.isNotEmpty
        ? responseFormattingEdits
        : response.formattingEdits.isEmpty &&
              _hasAvailableServiceCapability(
                response,
                StyioServiceCapability.formatting,
              )
        ? const <FormattingEdit>[]
        : localAnalysis.formattingEdits;
    final responseSemanticBlocks = response.semanticBlocks
        .where((block) => _isSafeRange(document, block.range))
        .toList(growable: false);
    final semanticBlocks = responseSemanticBlocks.isNotEmpty
        ? responseSemanticBlocks
        : response.semanticBlocks.isEmpty &&
              _hasAvailableServiceCapability(
                response,
                StyioServiceCapability.semanticBlocks,
              )
        ? const <SemanticBlockRange>[]
        : localAnalysis.semanticBlocks;
    final responseInlayHints = response.inlayHints
        .where((hint) => _isSafeInlayHint(document, hint))
        .toList(growable: false);
    final inlayHints = responseInlayHints.isNotEmpty
        ? responseInlayHints
        : response.inlayHints.isEmpty &&
              _hasAvailableServiceCapability(
                response,
                StyioServiceCapability.inlayHints,
              )
        ? const <InlayHint>[]
        : localAnalysis.inlayHints;
    final responseDocumentSymbols = response.documentSymbols
        .where((symbol) => _isSafeDocumentSymbol(document, symbol))
        .toList(growable: false);
    final documentSymbols = responseDocumentSymbols.isNotEmpty
        ? responseDocumentSymbols
        : response.documentSymbols.isEmpty &&
              _hasAvailableServiceCapability(
                response,
                StyioServiceCapability.documentSymbols,
              )
        ? const <DocumentSymbol>[]
        : localAnalysis.documentSymbols;
    final responseReferenceSpans = response.referenceSpans
        .where((reference) => _isSafeReferenceSpan(document, reference))
        .toList(growable: false);
    final rawReferenceSpans = responseReferenceSpans.isNotEmpty
        ? responseReferenceSpans
        : response.referenceSpans.isEmpty &&
              _hasAvailableServiceCapability(
                response,
                StyioServiceCapability.references,
              )
        ? const <ReferenceSpan>[]
        : localAnalysis.referenceSpans;
    final referenceSpans = documentSymbols.isEmpty
        ? rawReferenceSpans
        : _completeReferenceSpansFromSnapshot(
            document: document,
            localAnalysis: localAnalysis,
            diagnostics: diagnostics,
            formattingEdits: formattingEdits,
            semanticBlocks: semanticBlocks,
            inlayHints: inlayHints,
            documentSymbols: documentSymbols,
            referenceSpans: rawReferenceSpans,
          );
    final responseSemanticSpans = response.semanticSpans
        .where((span) => _isSafeRange(document, span.range))
        .toList(growable: false);
    final semanticSpans = responseSemanticSpans.isNotEmpty
        ? responseSemanticSpans
        : response.semanticSpans.isEmpty &&
              _hasAvailableServiceCapability(
                response,
                StyioServiceCapability.semanticTokens,
              )
        ? const <SemanticSpan>[]
        : response.documentSymbols.isNotEmpty
        ? const StyioSemanticTokenFeature().semanticSpans(
            snapshot: SemanticSnapshot.fromAnalysis(
              document: document,
              analysis: StyioDocumentAnalysis(
                tokenSpans: localAnalysis.tokenSpans,
                semanticSpans: const <SemanticSpan>[],
                diagnostics: diagnostics,
                formattingEdits: formattingEdits,
                semanticBlocks: semanticBlocks,
                inlayHints: inlayHints,
                documentSymbols: documentSymbols,
                referenceSpans: referenceSpans,
              ),
            ),
          )
        : localAnalysis.semanticSpans;

    return StyioDocumentAnalysis(
      tokenSpans: localAnalysis.tokenSpans,
      semanticSpans: semanticSpans,
      diagnostics: diagnostics,
      formattingEdits: formattingEdits,
      semanticBlocks: semanticBlocks,
      inlayHints: inlayHints,
      documentSymbols: documentSymbols,
      referenceSpans: referenceSpans,
    );
  }

  SemanticSnapshot semanticSnapshot({
    required DocumentState document,
    required StyioDocumentAnalysis localAnalysis,
    required StyioServiceResponse response,
  }) {
    return SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: mergeAnalysis(
        document: document,
        localAnalysis: localAnalysis,
        response: response,
      ),
    );
  }

  List<ReferenceSpan> _completeReferenceSpansFromSnapshot({
    required DocumentState document,
    required StyioDocumentAnalysis localAnalysis,
    required List<Diagnostic> diagnostics,
    required List<FormattingEdit> formattingEdits,
    required List<SemanticBlockRange> semanticBlocks,
    required List<InlayHint> inlayHints,
    required List<DocumentSymbol> documentSymbols,
    required List<ReferenceSpan> referenceSpans,
  }) {
    final snapshot = SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: StyioDocumentAnalysis(
        tokenSpans: localAnalysis.tokenSpans,
        semanticSpans: const <SemanticSpan>[],
        diagnostics: diagnostics,
        formattingEdits: formattingEdits,
        semanticBlocks: semanticBlocks,
        inlayHints: inlayHints,
        documentSymbols: documentSymbols,
        referenceSpans: referenceSpans,
      ),
    );
    final derivedReferences = snapshot.references
        .map(_referenceSpanFromResolvedReference)
        .toList(growable: false);
    return _mergeReferenceSpans(referenceSpans, derivedReferences);
  }

  ReferenceSpan _referenceSpanFromResolvedReference(
    ResolvedReference reference,
  ) {
    return ReferenceSpan(
      name: reference.name,
      kind: symbolKindFromResolvedElementKind(reference.target.kind),
      range: reference.range,
      targetRange: reference.target.nameRange,
      isDeclaration: reference.isDeclaration,
      access: referenceAccessFromResolvedReferenceAccess(reference.access),
    );
  }

  List<ReferenceSpan> _mergeReferenceSpans(
    List<ReferenceSpan> primary,
    List<ReferenceSpan> fallback,
  ) {
    final merged = <ReferenceSpan>[...primary];
    for (final reference in fallback) {
      if (!merged.any((existing) => _sameReferenceSpan(existing, reference))) {
        merged.add(reference);
      }
    }
    return List.unmodifiable(merged);
  }

  bool _sameReferenceSpan(ReferenceSpan left, ReferenceSpan right) {
    return _sameRange(left.range, right.range) &&
        _sameRange(left.targetRange, right.targetRange);
  }

  bool _sameRange(SourceRange left, SourceRange right) {
    return left.start == right.start && left.end == right.end;
  }

  bool _isSafeDocumentSymbol(DocumentState document, DocumentSymbol symbol) {
    return _isSafeRange(document, symbol.nameRange) &&
        _isSafeRange(document, symbol.declarationRange);
  }

  bool _isSafeReferenceSpan(DocumentState document, ReferenceSpan reference) {
    return _isSafeRange(document, reference.range) &&
        _isSafeRange(document, reference.targetRange);
  }

  bool _isSafeInlayHint(DocumentState document, InlayHint hint) {
    return _isSafeOffset(document, hint.position) &&
        _isSafeRange(document, hint.range);
  }

  bool _hasAvailableServiceCapability(
    StyioServiceResponse response,
    StyioServiceCapability capability,
  ) {
    final state = lookupStyioServiceCapabilityValue(
      response.capabilityStates,
      capability,
    );
    return state?.toLowerCase() == 'available';
  }

  bool _isSafeRange(DocumentState document, SourceRange range) {
    return range.start >= 0 &&
        range.end >= range.start &&
        range.end <= document.length;
  }

  bool _isSafeOffset(DocumentState document, int offset) {
    return offset >= 0 && offset <= document.length;
  }
}

class StyioServiceResponseTelemetryBridge {
  const StyioServiceResponseTelemetryBridge({
    this.semanticBridge = const SemanticSnapshotEventBridge(),
  });

  final SemanticSnapshotEventBridge semanticBridge;

  List<RuntimeOutputEvent> eventsForResponse(
    StyioServiceResponse response, {
    DateTime? timestamp,
  }) {
    final emittedAt = timestamp ?? DateTime.now().toUtc();
    return <RuntimeOutputEvent>[
      semanticBridge.diagnosticsSnapshotEvent(
        documentId: response.documentId,
        providerId: _providerId(response),
        diagnosticCount: response.diagnostics.length,
        hasErrors: _hasErrors(response),
        severityCounts: _severityCounts(response),
        documentCount: response.documentId.isEmpty ? 0 : 1,
        sourceCount: response.diagnostics.isEmpty ? 0 : 1,
        timestamp: emittedAt,
        message:
            'StyioService ${response.status.name} diagnostics: '
            '${response.diagnostics.length} diagnostic(s).',
        payload: _basePayload(response),
      ),
      semanticBridge.semanticTokensEvent(
        documentId: response.documentId,
        semanticSpanCount: response.semanticSpans.length,
        semanticBlockCount: response.semanticBlocks.length,
        documentSymbolCount: response.documentSymbols.length,
        inlayHintCount: response.inlayHints.length,
        diagnosticCount: response.diagnostics.length,
        timestamp: emittedAt,
        message:
            'StyioService ${response.status.name} semantic tokens: '
            '${response.semanticSpans.length} span(s), '
            '${response.semanticBlocks.length} block(s).',
        payload: _basePayload(response),
      ),
    ];
  }

  String _providerId(StyioServiceResponse response) {
    return response.toolchainId.isEmpty
        ? 'styio-service'
        : 'styio-service:${response.toolchainId}';
  }

  bool _hasErrors(StyioServiceResponse response) {
    return response.diagnostics.any(
      (diagnostic) => diagnostic.severity == DiagnosticSeverity.error,
    );
  }

  Map<String, int> _severityCounts(StyioServiceResponse response) {
    return <String, int>{
      for (final severity in DiagnosticSeverity.values)
        severity.name: response.diagnostics
            .where((diagnostic) => diagnostic.severity == severity)
            .length,
    };
  }

  Map<String, Object?> _basePayload(StyioServiceResponse response) {
    return <String, Object?>{
      'source': 'styio-service-response',
      'status': response.status.name,
      'protocolVersion': response.protocolVersion,
      if (response.parserEngine != null) 'parserEngine': response.parserEngine,
      if (response.grammarVersion != null)
        'grammarVersion': response.grammarVersion,
      if (response.toolchainId.isNotEmpty) 'toolchainId': response.toolchainId,
      if (response.configPath != null) 'configPath': response.configPath,
      if (response.workingDirectory != null)
        'workingDirectory': response.workingDirectory,
      'payloadCounts': response.payloadCounts,
      'stdoutBytes': utf8.encode(response.stdout).length,
      'stderrBytes': utf8.encode(response.stderr).length,
      if (response.exitCode != null) 'exitCode': response.exitCode,
      if (response.message != null) 'message': response.message,
    };
  }
}

class StyioServiceResultCacheKey {
  const StyioServiceResultCacheKey({
    required this.documentId,
    required this.revision,
    required this.protocolVersion,
    this.toolchainId = '',
    this.configPath,
    this.workingDirectory,
  });

  final String documentId;
  final int revision;
  final String protocolVersion;
  final String toolchainId;
  final String? configPath;
  final String? workingDirectory;

  @override
  bool operator ==(Object other) {
    return other is StyioServiceResultCacheKey &&
        other.documentId == documentId &&
        other.revision == revision &&
        other.protocolVersion == protocolVersion &&
        other.toolchainId == toolchainId &&
        other.configPath == configPath &&
        other.workingDirectory == workingDirectory;
  }

  @override
  int get hashCode => Object.hash(
    documentId,
    revision,
    protocolVersion,
    toolchainId,
    configPath,
    workingDirectory,
  );
}

class StyioServiceResultCacheEntry {
  const StyioServiceResultCacheEntry({
    required this.documentId,
    required this.revision,
    required this.protocolVersion,
    required this.toolchainId,
    required this.status,
    required this.diagnosticCount,
    required this.completionCount,
    required this.hoverCount,
    required this.semanticSpanCount,
    required this.formattingEditCount,
    required this.semanticBlockCount,
    required this.inlayHintCount,
    required this.documentSymbolCount,
    required this.referenceSpanCount,
    required this.definitionTargetCount,
    required this.codeActionCount,
    required this.renamePlanCount,
    required this.safeDeletePlanCount,
    required this.inlineVariablePlanCount,
    required this.introduceVariablePlanCount,
    required this.extractFunctionPlanCount,
    required this.changeSignaturePlanCount,
    required this.parameterInfoCount,
    required this.surroundTemplateCount,
    this.configPath,
    this.workingDirectory,
    this.parserEngine,
    this.grammarVersion,
    this.message,
  });

  final String documentId;
  final int revision;
  final String protocolVersion;
  final String toolchainId;
  final StyioServiceStatus status;
  final String? configPath;
  final String? workingDirectory;
  final String? parserEngine;
  final String? grammarVersion;
  final int diagnosticCount;
  final int completionCount;
  final int hoverCount;
  final int semanticSpanCount;
  final int formattingEditCount;
  final int semanticBlockCount;
  final int inlayHintCount;
  final int documentSymbolCount;
  final int referenceSpanCount;
  final int definitionTargetCount;
  final int codeActionCount;
  final int renamePlanCount;
  final int safeDeletePlanCount;
  final int inlineVariablePlanCount;
  final int introduceVariablePlanCount;
  final int extractFunctionPlanCount;
  final int changeSignaturePlanCount;
  final int parameterInfoCount;
  final int surroundTemplateCount;
  final String? message;

  factory StyioServiceResultCacheEntry.fromJson(Map<String, Object?> json) {
    return StyioServiceResultCacheEntry(
      documentId: json['documentId'] as String? ?? '',
      revision: _intValue(json['revision']),
      protocolVersion:
          json['protocolVersion'] as String? ?? 'styio-cli-jsonl-v1',
      toolchainId: json['toolchainId'] as String? ?? '',
      status: _statusFromJson(json['status']),
      configPath: json['configPath'] as String?,
      workingDirectory: json['workingDirectory'] as String?,
      parserEngine: json['parserEngine'] as String?,
      grammarVersion: json['grammarVersion'] as String?,
      diagnosticCount: _intValue(json['diagnosticCount']),
      completionCount: _intValue(json['completionCount']),
      hoverCount: _intValue(json['hoverCount']),
      semanticSpanCount: _intValue(json['semanticSpanCount']),
      formattingEditCount: _intValue(json['formattingEditCount']),
      semanticBlockCount: _intValue(json['semanticBlockCount']),
      inlayHintCount: _intValue(json['inlayHintCount']),
      documentSymbolCount: _intValue(json['documentSymbolCount']),
      referenceSpanCount: _intValue(json['referenceSpanCount']),
      definitionTargetCount: _intValue(json['definitionTargetCount']),
      codeActionCount: _intValue(json['codeActionCount']),
      renamePlanCount: _intValue(json['renamePlanCount']),
      safeDeletePlanCount: _intValue(json['safeDeletePlanCount']),
      inlineVariablePlanCount: _intValue(json['inlineVariablePlanCount']),
      introduceVariablePlanCount: _intValue(json['introduceVariablePlanCount']),
      extractFunctionPlanCount: _intValue(json['extractFunctionPlanCount']),
      changeSignaturePlanCount: _intValue(json['changeSignaturePlanCount']),
      parameterInfoCount: _intValue(json['parameterInfoCount']),
      surroundTemplateCount: _intValue(json['surroundTemplateCount']),
      message: json['message'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'revision': revision,
      'protocolVersion': protocolVersion,
      'toolchainId': toolchainId,
      'status': status.name,
      if (configPath != null) 'configPath': configPath,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      if (parserEngine != null) 'parserEngine': parserEngine,
      if (grammarVersion != null) 'grammarVersion': grammarVersion,
      'diagnosticCount': diagnosticCount,
      'completionCount': completionCount,
      'hoverCount': hoverCount,
      'semanticSpanCount': semanticSpanCount,
      'formattingEditCount': formattingEditCount,
      'semanticBlockCount': semanticBlockCount,
      'inlayHintCount': inlayHintCount,
      'documentSymbolCount': documentSymbolCount,
      'referenceSpanCount': referenceSpanCount,
      'definitionTargetCount': definitionTargetCount,
      'codeActionCount': codeActionCount,
      'renamePlanCount': renamePlanCount,
      'safeDeletePlanCount': safeDeletePlanCount,
      'inlineVariablePlanCount': inlineVariablePlanCount,
      'introduceVariablePlanCount': introduceVariablePlanCount,
      'extractFunctionPlanCount': extractFunctionPlanCount,
      'changeSignaturePlanCount': changeSignaturePlanCount,
      'parameterInfoCount': parameterInfoCount,
      'surroundTemplateCount': surroundTemplateCount,
      if (message != null) 'message': message,
    };
  }

  static int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static StyioServiceStatus _statusFromJson(Object? value) {
    final name = value?.toString();
    for (final status in StyioServiceStatus.values) {
      if (status.name == name) {
        return status;
      }
    }
    return StyioServiceStatus.failed;
  }
}

class StyioServiceResultCacheSnapshot {
  const StyioServiceResultCacheSnapshot({
    required this.entries,
    this.lookupHits = 0,
    this.lookupMisses = 0,
  });

  factory StyioServiceResultCacheSnapshot.fromJson(Map<String, Object?> json) {
    final entries = json['entries'];
    return StyioServiceResultCacheSnapshot(
      entries: entries is List
          ? entries
                .map(_entryFromJson)
                .whereType<StyioServiceResultCacheEntry>()
                .toList(growable: false)
          : const <StyioServiceResultCacheEntry>[],
      lookupHits: _intValue(json['lookupHits']),
      lookupMisses: _intValue(json['lookupMisses']),
    );
  }

  final List<StyioServiceResultCacheEntry> entries;
  final int lookupHits;
  final int lookupMisses;

  int get lookupCount => lookupHits + lookupMisses;
  double get lookupHitRate => lookupCount == 0 ? 0 : lookupHits / lookupCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'lookupHits': lookupHits,
      'lookupMisses': lookupMisses,
      'lookupCount': lookupCount,
      'lookupHitRate': lookupHitRate,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  static StyioServiceResultCacheEntry? _entryFromJson(Object? value) {
    if (value is Map<String, Object?>) {
      return StyioServiceResultCacheEntry.fromJson(value);
    }
    if (value is Map) {
      return StyioServiceResultCacheEntry.fromJson(
        value.map(
          (key, value) => MapEntry<String, Object?>(key.toString(), value),
        ),
      );
    }
    return null;
  }

  static int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

class StyioServiceResultCacheManifestStore {
  const StyioServiceResultCacheManifestStore({
    required FoundationDataStoreOwner dataStoreOwner,
    this.namespaceName = 'language.result-cache-manifest',
    this.key = 'styio-service-result-cache',
    this.scope = FoundationResourceScope.user,
    this.workspaceId,
  }) : _dataStoreOwner = dataStoreOwner;

  factory StyioServiceResultCacheManifestStore.fromDataStore({
    required FoundationDataStore dataStore,
    String namespaceName = 'language.result-cache-manifest',
    String key = 'styio-service-result-cache',
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    return StyioServiceResultCacheManifestStore(
      dataStoreOwner: FoundationDataStoreOwner(
        descriptor: FoundationDataStoreOwnerDescriptor(
          ownerId: 'service.language.result-cache',
          layer: 'service',
          stateFamily: 'language-result-cache',
          allowedNamespaces: <String>{namespaceName},
        ),
        dataStore: dataStore,
      ),
      namespaceName: namespaceName,
      key: key,
      scope: scope,
      workspaceId: workspaceId,
    );
  }

  final FoundationDataStoreOwner _dataStoreOwner;
  final String namespaceName;
  final String key;
  final FoundationResourceScope scope;
  final String? workspaceId;

  Future<void> save(StyioServiceResultCacheSnapshot snapshot) {
    return _dataStoreOwner.writeJson(
      namespaceName: namespaceName,
      key: key,
      value: snapshot.toJson(),
      schemaVersion: 1,
      scope: scope,
      workspaceId: workspaceId,
    );
  }

  Future<StyioServiceResultCacheSnapshot?> load() async {
    final value = await _dataStoreOwner.readJson(
      namespaceName: namespaceName,
      key: key,
      schemaVersion: 1,
      scope: scope,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return null;
    }
    return StyioServiceResultCacheSnapshot.fromJson(value);
  }

  Future<bool> delete() {
    return _dataStoreOwner.delete(
      namespaceName: namespaceName,
      key: key,
      schemaVersion: 1,
      scope: scope,
      workspaceId: workspaceId,
    );
  }

  Stream<StyioServiceResultCacheManifestChange> watch() {
    return _dataStoreOwner
        .watchJson(
          namespaceName: namespaceName,
          key: key,
          schemaVersion: 1,
          scope: scope,
          workspaceId: workspaceId,
        )
        .map(StyioServiceResultCacheManifestChange.fromDataStoreChange);
  }
}

class StyioServiceResultCacheManifestChange {
  const StyioServiceResultCacheManifestChange({
    required this.kind,
    required this.snapshot,
    required this.emittedAt,
  });

  factory StyioServiceResultCacheManifestChange.fromDataStoreChange(
    FoundationDataStoreChange change,
  ) {
    return StyioServiceResultCacheManifestChange(
      kind: change.kind,
      snapshot: change.value == null
          ? null
          : StyioServiceResultCacheSnapshot.fromJson(change.value!),
      emittedAt: change.emittedAt,
    );
  }

  final FoundationDataStoreChangeKind kind;
  final StyioServiceResultCacheSnapshot? snapshot;
  final DateTime emittedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      if (snapshot != null) 'snapshot': snapshot!.toJson(),
      'emittedAt': emittedAt.toIso8601String(),
    };
  }
}

class StyioServiceResultCache {
  StyioServiceResultCache({this.maximumEntries = 64});

  final int maximumEntries;
  final Map<StyioServiceResultCacheKey, StyioServiceResponse> _responses =
      <StyioServiceResultCacheKey, StyioServiceResponse>{};
  var _lookupHits = 0;
  var _lookupMisses = 0;

  StyioServiceResponse? lookup(StyioServiceResultCacheKey key) {
    final response = _lookupExact(key);
    _recordLookup(response != null);
    return response;
  }

  StyioServiceResponse? lookupDocument({
    required String documentId,
    required int revision,
    required String protocolVersion,
    String toolchainId = '',
    String? configPath,
    String? workingDirectory,
  }) {
    final exact = _lookupExact(
      StyioServiceResultCacheKey(
        documentId: documentId,
        revision: revision,
        protocolVersion: protocolVersion,
        toolchainId: toolchainId,
        configPath: configPath,
        workingDirectory: workingDirectory,
      ),
    );
    if (exact != null) {
      _recordLookup(true);
      return exact;
    }

    final matches = _responses.entries
        .where((entry) {
          final key = entry.key;
          return key.documentId == documentId &&
              key.revision == revision &&
              key.protocolVersion == protocolVersion &&
              (toolchainId.isEmpty || key.toolchainId == toolchainId) &&
              (configPath == null || key.configPath == configPath) &&
              (workingDirectory == null ||
                  key.workingDirectory == workingDirectory);
        })
        .toList(growable: false);
    if (matches.length == 1) {
      _recordLookup(true);
      return matches.single.value;
    }
    _recordLookup(false);
    return null;
  }

  void store(StyioServiceResponse response, {String? toolchainId}) {
    final key = StyioServiceResultCacheKey(
      documentId: response.documentId,
      revision: response.revision,
      protocolVersion: response.protocolVersion,
      toolchainId: toolchainId ?? response.toolchainId,
      configPath: response.configPath,
      workingDirectory: response.workingDirectory,
    );
    _responses[key] = response;
    _evictOverflow();
  }

  void retainDocuments(Iterable<String> documentIds) {
    final retained = documentIds.toSet();
    _responses.removeWhere((key, value) => !retained.contains(key.documentId));
  }

  void clearDocument(String documentId) {
    _responses.removeWhere((key, value) => key.documentId == documentId);
  }

  int clearConfigurationContext({
    String? configPath,
    String? workingDirectory,
  }) {
    if (configPath == null && workingDirectory == null) {
      return 0;
    }
    var removed = 0;
    _responses.removeWhere((key, value) {
      final shouldRemove =
          (configPath == null || key.configPath == configPath) &&
          (workingDirectory == null ||
              key.workingDirectory == workingDirectory);
      if (shouldRemove) {
        removed += 1;
      }
      return shouldRemove;
    });
    return removed;
  }

  int clearToolchain(String toolchainId) {
    var removed = 0;
    _responses.removeWhere((key, value) {
      final shouldRemove = key.toolchainId == toolchainId;
      if (shouldRemove) {
        removed += 1;
      }
      return shouldRemove;
    });
    return removed;
  }

  int retainToolchains(Iterable<String> toolchainIds) {
    final retained = toolchainIds.where((id) => id.isNotEmpty).toSet();
    var removed = 0;
    _responses.removeWhere((key, value) {
      final shouldRemove = !retained.contains(key.toolchainId);
      if (shouldRemove) {
        removed += 1;
      }
      return shouldRemove;
    });
    return removed;
  }

  void clear() {
    _responses.clear();
  }

  int get length => _responses.length;
  int get lookupHits => _lookupHits;
  int get lookupMisses => _lookupMisses;
  int get lookupCount => _lookupHits + _lookupMisses;
  double get lookupHitRate => lookupCount == 0 ? 0 : _lookupHits / lookupCount;

  void resetTelemetry() {
    _lookupHits = 0;
    _lookupMisses = 0;
  }

  StyioServiceResponse? _lookupExact(StyioServiceResultCacheKey key) {
    return _responses[key];
  }

  void _recordLookup(bool hit) {
    if (hit) {
      _lookupHits += 1;
    } else {
      _lookupMisses += 1;
    }
  }

  StyioServiceResultCacheSnapshot snapshot({String? documentId}) {
    final entries = <StyioServiceResultCacheEntry>[];
    for (final entry in _responses.entries) {
      final key = entry.key;
      final response = entry.value;
      if (documentId != null && key.documentId != documentId) {
        continue;
      }
      entries.add(
        StyioServiceResultCacheEntry(
          documentId: key.documentId,
          revision: key.revision,
          protocolVersion: key.protocolVersion,
          toolchainId: key.toolchainId,
          status: response.status,
          configPath: key.configPath,
          workingDirectory: key.workingDirectory,
          parserEngine: response.parserEngine,
          grammarVersion: response.grammarVersion,
          diagnosticCount: response.diagnostics.length,
          completionCount: response.completions.length,
          hoverCount: response.hovers.length,
          semanticSpanCount: response.semanticSpans.length,
          formattingEditCount: response.formattingEdits.length,
          semanticBlockCount: response.semanticBlocks.length,
          inlayHintCount: response.inlayHints.length,
          documentSymbolCount: response.documentSymbols.length,
          referenceSpanCount: response.referenceSpans.length,
          definitionTargetCount: response.definitionTargets.length,
          codeActionCount: response.codeActions.length,
          renamePlanCount: response.renamePlans.length,
          safeDeletePlanCount: response.safeDeletePlans.length,
          inlineVariablePlanCount: response.inlineVariablePlans.length,
          introduceVariablePlanCount: response.introduceVariablePlans.length,
          extractFunctionPlanCount: response.extractFunctionPlans.length,
          changeSignaturePlanCount: response.changeSignaturePlans.length,
          parameterInfoCount: response.parameterInfos.length,
          surroundTemplateCount: response.surroundTemplates.length,
          message: response.message,
        ),
      );
    }
    entries.sort((left, right) {
      final document = left.documentId.compareTo(right.documentId);
      if (document != 0) {
        return document;
      }
      final revision = left.revision.compareTo(right.revision);
      if (revision != 0) {
        return revision;
      }
      final protocol = left.protocolVersion.compareTo(right.protocolVersion);
      if (protocol != 0) {
        return protocol;
      }
      final toolchain = left.toolchainId.compareTo(right.toolchainId);
      if (toolchain != 0) {
        return toolchain;
      }
      final config = (left.configPath ?? '').compareTo(right.configPath ?? '');
      if (config != 0) {
        return config;
      }
      return (left.workingDirectory ?? '').compareTo(
        right.workingDirectory ?? '',
      );
    });
    return StyioServiceResultCacheSnapshot(
      entries: entries,
      lookupHits: lookupHits,
      lookupMisses: lookupMisses,
    );
  }

  void _evictOverflow() {
    while (_responses.length > maximumEntries) {
      _responses.remove(_responses.keys.first);
    }
  }
}

class StyioServiceToolchainCacheInvalidator {
  const StyioServiceToolchainCacheInvalidator({
    required StyioServiceResultCache cache,
  }) : _cache = cache;

  final StyioServiceResultCache _cache;

  int applyCatalogChange(ToolchainCatalogChange change) {
    if (change.deleted || change.catalog == null) {
      final removed = _cache.length;
      _cache.clear();
      return removed;
    }
    final activeLanguageService = change.catalog!.active(
      ToolchainKind.languageService,
    );
    if (activeLanguageService == null) {
      final removed = _cache.length;
      _cache.clear();
      return removed;
    }
    return _cache.retainToolchains(<String>{activeLanguageService.id});
  }
}

class StyioServiceToolchainCacheBinding {
  StyioServiceToolchainCacheBinding._({
    required StyioServiceToolchainCacheInvalidator invalidator,
    required StreamSubscription<ToolchainCatalogChange> subscription,
  }) : _invalidator = invalidator,
       _subscription = subscription;

  factory StyioServiceToolchainCacheBinding.bind({
    required StyioServiceResultCache cache,
    required Stream<ToolchainCatalogChange> catalogChanges,
    StyioServiceResultCacheManifestStore? resultCacheManifestStore,
  }) {
    final invalidator = StyioServiceToolchainCacheInvalidator(cache: cache);
    return StyioServiceToolchainCacheBinding._(
      invalidator: invalidator,
      subscription: catalogChanges.listen((change) async {
        invalidator.applyCatalogChange(change);
        if (resultCacheManifestStore == null) {
          return;
        }
        if (cache.length == 0) {
          await resultCacheManifestStore.delete();
          return;
        }
        await resultCacheManifestStore.save(cache.snapshot());
      }),
    );
  }

  final StyioServiceToolchainCacheInvalidator _invalidator;
  final StreamSubscription<ToolchainCatalogChange> _subscription;

  StyioServiceToolchainCacheInvalidator get invalidator => _invalidator;

  Future<void> dispose() {
    return _subscription.cancel();
  }
}

enum StyioServiceFallbackStatus {
  noCachedResponse,
  staleResponse,
  servicePayload,
  serviceEmpty,
  serviceDerived,
  localFallback,
}

class StyioServiceFallbackEntry {
  const StyioServiceFallbackEntry({
    required this.capability,
    required this.status,
    this.message = '',
  });

  final StyioServiceCapability capability;
  final StyioServiceFallbackStatus status;
  final String message;

  bool get usesLocalFallback {
    return status == StyioServiceFallbackStatus.noCachedResponse ||
        status == StyioServiceFallbackStatus.staleResponse ||
        status == StyioServiceFallbackStatus.localFallback;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'capability': capability.wireValue,
      'status': status.name,
      'usesLocalFallback': usesLocalFallback,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

class StyioServiceFallbackSnapshot {
  const StyioServiceFallbackSnapshot({
    required this.documentId,
    required this.revision,
    required this.entries,
  });

  final String documentId;
  final int revision;
  final List<StyioServiceFallbackEntry> entries;

  StyioServiceFallbackStatus statusOf(StyioServiceCapability capability) {
    for (final entry in entries) {
      if (entry.capability == capability) {
        return entry.status;
      }
    }
    return StyioServiceFallbackStatus.localFallback;
  }

  Set<StyioServiceCapability> get localFallbackCapabilities {
    return entries
        .where((entry) => entry.usesLocalFallback)
        .map((entry) => entry.capability)
        .toSet();
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'revision': revision,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class CachedStyioLanguageService implements StyioLanguageService {
  const CachedStyioLanguageService({
    required StyioServiceResultCache cache,
    this.localService = const LocalStyioLanguageService(),
    this.resultAdapter = const StyioServiceResultAdapter(),
    this.protocolVersion = 'styio-cli-jsonl-v1',
    this.toolchainId = '',
    this.configPath,
    this.workingDirectory,
    this.allowLocalFallback = true,
  }) : _cache = cache;

  final StyioServiceResultCache _cache;
  final LocalStyioLanguageService localService;
  final StyioServiceResultAdapter resultAdapter;
  final String protocolVersion;
  final String toolchainId;
  final String? configPath;
  final String? workingDirectory;
  final bool allowLocalFallback;

  StyioServiceFallbackSnapshot fallbackSnapshot(
    DocumentState document, {
    Iterable<StyioServiceCapability> capabilities =
        StyioServiceCapability.values,
  }) {
    final response = _cachedResponse(document);
    final entries = <StyioServiceFallbackEntry>[];
    for (final capability in capabilities) {
      entries.add(
        StyioServiceFallbackEntry(
          capability: capability,
          status: _fallbackStatusFor(document, response, capability),
          message: response == null
              ? 'No cached StyioService response.'
              : lookupStyioServiceCapabilityValue(
                      response.capabilityMessages,
                      capability,
                    ) ??
                    '',
        ),
      );
    }
    return StyioServiceFallbackSnapshot(
      documentId: document.documentId,
      revision: document.revision,
      entries: List.unmodifiable(entries),
    );
  }

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    final localAnalysis = _fallbackAnalysis(document);
    final response = _cache.lookupDocument(
      documentId: document.documentId,
      revision: document.revision,
      protocolVersion: protocolVersion,
      toolchainId: toolchainId,
      configPath: configPath,
      workingDirectory: workingDirectory,
    );
    if (response == null) {
      return localAnalysis;
    }
    return resultAdapter.mergeAnalysis(
      document: document,
      localAnalysis: localAnalysis,
      response: response,
    );
  }

  @override
  List<CompletionItem> completeAt(DocumentState document, int offset) {
    final response = _cachedResponse(document);
    if (response != null && response.completions.isNotEmpty) {
      final completions = response.completions
          .where((item) => _hasSafeCompletion(document, item))
          .toList(growable: false);
      if (completions.isNotEmpty) {
        return completions;
      }
    }
    if (response != null &&
        response.completions.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.completion,
        )) {
      return const <CompletionItem>[];
    }
    if (response != null && _hasSnapshotFacts(response)) {
      final snapshot = _semanticSnapshot(document, response);
      final completions = localService.completionFeature.completeAt(
        document: document,
        snapshot: snapshot,
        offset: offset,
      );
      if (completions.isNotEmpty) {
        return completions;
      }
    }
    return _localListOrEmpty(() => localService.completeAt(document, offset));
  }

  @override
  ChangeSignaturePlan? changeSignatureAt(
    DocumentState document,
    int offset, {
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) {
    final response = _cachedResponse(document);
    if (response != null && response.changeSignaturePlans.isNotEmpty) {
      for (final plan in response.changeSignaturePlans) {
        if (!_hasSafeEdits(document, plan.edits)) {
          continue;
        }
        if (plan.newName == newName &&
            _sameParameterUpdates(plan.newParameters, parameters) &&
            _planContainsOffset(plan.target, plan.references, offset)) {
          return plan;
        }
      }
    }
    if (response != null &&
        response.changeSignaturePlans.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.changeSignature,
        )) {
      return null;
    }
    if (response != null && _hasSnapshotFacts(response)) {
      final plan = localService.refactorFeature.changeSignatureAt(
        document: document,
        snapshot: _semanticSnapshot(document, response),
        offset: offset,
        newName: newName,
        parameters: parameters,
      );
      if (plan != null) {
        return plan;
      }
    }
    return _localNullableOrNull(
      () => localService.changeSignatureAt(
        document,
        offset,
        newName: newName,
        parameters: parameters,
      ),
    );
  }

  @override
  DefinitionTarget? definitionAt(DocumentState document, int offset) {
    final response = _cachedResponse(document);
    if (response != null && response.definitionTargets.isNotEmpty) {
      for (final definition in response.definitionTargets) {
        if (_isSafeDefinitionTarget(document, definition) &&
            _contains(definition.originRange, offset)) {
          return definition;
        }
      }
    }
    if (response != null &&
        response.definitionTargets.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.definition,
        )) {
      return null;
    }
    if (response != null && response.referenceSpans.isNotEmpty) {
      final reference = _referenceAt(response.referenceSpans, offset);
      if (reference != null) {
        final symbol =
            _symbolForTarget(response.documentSymbols, reference.targetRange) ??
            _symbolFromReference(reference);
        return DefinitionTarget(symbol: symbol, originRange: reference.range);
      }
    }
    if (response != null && _hasSnapshotFacts(response)) {
      final definition = localService.navigationFeature.definitionAt(
        document: document,
        snapshot: _semanticSnapshot(document, response),
        offset: offset,
      );
      if (definition != null) {
        return definition;
      }
    }
    return _localNullableOrNull(
      () => localService.definitionAt(document, offset),
    );
  }

  @override
  ExtractFunctionPlan? extractFunction(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    final response = _cachedResponse(document);
    if (response != null && response.extractFunctionPlans.isNotEmpty) {
      for (final plan in response.extractFunctionPlans) {
        if (!_hasSafeEdits(document, plan.edits)) {
          continue;
        }
        if (plan.functionName == name &&
            _sameRange(plan.selectionRange, range)) {
          return plan;
        }
      }
    }
    if (response != null &&
        response.extractFunctionPlans.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.extractFunction,
        )) {
      return null;
    }
    return _localNullableOrNull(
      () => localService.extractFunction(document, range, name),
    );
  }

  @override
  List<FormattingEdit> formatDocument(DocumentState document) {
    final response = _cachedResponse(document);
    if (response != null && response.formattingEdits.isNotEmpty) {
      if (_hasSafeEdits(document, response.formattingEdits)) {
        return response.formattingEdits;
      }
    }
    if (response != null &&
        response.formattingEdits.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.formatting,
        )) {
      return const <FormattingEdit>[];
    }
    return _localListOrEmpty(() => localService.formatDocument(document));
  }

  @override
  HoverPayload? hoverAt(DocumentState document, int offset) {
    final response = _cachedResponse(document);
    if (response != null) {
      for (final hover in response.hovers) {
        if (_isSafeRange(document, hover.range) &&
            _contains(hover.range, offset)) {
          return hover;
        }
      }
      if (response.hovers.isEmpty &&
          _hasAvailableServiceCapability(
            response,
            StyioServiceCapability.hover,
          )) {
        return null;
      }
      if (_hasSnapshotFacts(response)) {
        final hover = localService.hoverFeature.hoverAt(
          document: document,
          snapshot: _semanticSnapshot(document, response),
          offset: offset,
        );
        if (hover != null) {
          return hover;
        }
      }
    }
    return _localNullableOrNull(() => localService.hoverAt(document, offset));
  }

  @override
  InlineVariablePlan? inlineVariableAt(DocumentState document, int offset) {
    final response = _cachedResponse(document);
    if (response != null && response.inlineVariablePlans.isNotEmpty) {
      for (final plan in response.inlineVariablePlans) {
        if (!_hasSafeEdits(document, plan.edits)) {
          continue;
        }
        if (_planContainsOffset(plan.target, plan.references, offset)) {
          return plan;
        }
      }
    }
    if (response != null &&
        response.inlineVariablePlans.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.inlineVariable,
        )) {
      return null;
    }
    if (response != null && response.referenceSpans.isNotEmpty) {
      final plan = _inlineVariableFromServiceReferences(
        document: document,
        response: response,
        offset: offset,
      );
      if (plan != null) {
        return plan;
      }
    }
    if (response != null && _hasSnapshotFacts(response)) {
      final plan = localService.refactorFeature.inlineVariableAt(
        document: document,
        snapshot: _semanticSnapshot(document, response),
        offset: offset,
      );
      if (plan != null) {
        return plan;
      }
    }
    return _localNullableOrNull(
      () => localService.inlineVariableAt(document, offset),
    );
  }

  @override
  List<InlayHint> inlayHints(DocumentState document) {
    final response = _cachedResponse(document);
    if (response != null && response.inlayHints.isNotEmpty) {
      final hints = response.inlayHints
          .where((hint) => _isSafeInlayHint(document, hint))
          .toList(growable: false);
      if (hints.isNotEmpty) {
        return hints;
      }
    }
    if (response != null &&
        response.inlayHints.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.inlayHints,
        )) {
      return const <InlayHint>[];
    }
    return _localListOrEmpty(() => localService.inlayHints(document));
  }

  @override
  List<DiagnosticQuickFix> intentionsAt(DocumentState document, int offset) {
    final response = _cachedResponse(document);
    if (response != null && response.codeActions.isNotEmpty) {
      final actions = response.codeActions
          .where(
            (action) =>
                action.edits.isNotEmpty &&
                _hasSafeEdits(document, action.edits) &&
                action.edits.any((edit) => _contains(edit.range, offset)),
          )
          .toList(growable: false);
      if (actions.isNotEmpty) {
        return actions;
      }
    }
    if (response != null &&
        response.codeActions.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.codeActions,
        )) {
      return const <DiagnosticQuickFix>[];
    }
    return _localListOrEmpty(() => localService.intentionsAt(document, offset));
  }

  @override
  IntroduceVariablePlan? introduceVariable(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    final response = _cachedResponse(document);
    if (response != null && response.introduceVariablePlans.isNotEmpty) {
      for (final plan in response.introduceVariablePlans) {
        if (!_hasSafeEdits(document, plan.edits)) {
          continue;
        }
        if (plan.variableName == name &&
            _sameRange(plan.expressionRange, range)) {
          return plan;
        }
      }
    }
    if (response != null &&
        response.introduceVariablePlans.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.introduceVariable,
        )) {
      return null;
    }
    return _localNullableOrNull(
      () => localService.introduceVariable(document, range, name),
    );
  }

  @override
  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset) {
    final response = _cachedResponse(document);
    if (response != null && response.parameterInfos.isNotEmpty) {
      for (final payload in response.parameterInfos) {
        if (_isSafeParameterInfo(document, payload) &&
            _contains(payload.invocationRange, offset)) {
          return payload;
        }
      }
    }
    if (response != null &&
        response.parameterInfos.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.parameterInfo,
        )) {
      return null;
    }
    return _localNullableOrNull(
      () => localService.parameterInfoAt(document, offset),
    );
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final response = _cachedResponse(document);
    if (response != null && response.codeActions.isNotEmpty) {
      final fixes = response.codeActions
          .where(
            (action) =>
                action.edits.isNotEmpty &&
                _hasSafeEdits(document, action.edits) &&
                action.edits.any(
                  (edit) => edit.range.intersects(diagnostic.range),
                ),
          )
          .toList(growable: false);
      if (fixes.isNotEmpty) {
        return fixes;
      }
    }
    if (response != null &&
        response.codeActions.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.codeActions,
        )) {
      return const <DiagnosticQuickFix>[];
    }
    return _localListOrEmpty(
      () => localService.quickFixesForDiagnostic(document, diagnostic),
    );
  }

  @override
  List<ReferenceSpan> referencesAt(DocumentState document, int offset) {
    final response = _cachedResponse(document);
    if (response != null && response.referenceSpans.isNotEmpty) {
      final reference = _referenceAt(response.referenceSpans, offset);
      if (reference != null) {
        final targetRange = _canonicalTargetRange(
          response.documentSymbols,
          reference.targetRange,
        );
        final rawReferences = response.referenceSpans
            .where(
              (span) => _sameRange(
                _canonicalTargetRange(
                  response.documentSymbols,
                  span.targetRange,
                ),
                targetRange,
              ),
            )
            .toList(growable: false);
        if (_hasSnapshotFacts(response)) {
          final derivedReferences = localService.navigationFeature.referencesAt(
            document: document,
            snapshot: _semanticSnapshot(document, response),
            offset: offset,
          );
          if (derivedReferences.isNotEmpty) {
            return _mergeReferenceSpans(rawReferences, derivedReferences);
          }
        }
        return rawReferences;
      }
    }
    if (response != null &&
        response.referenceSpans.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.references,
        )) {
      return const <ReferenceSpan>[];
    }
    if (response != null && _hasSnapshotFacts(response)) {
      final references = localService.navigationFeature.referencesAt(
        document: document,
        snapshot: _semanticSnapshot(document, response),
        offset: offset,
      );
      if (references.isNotEmpty) {
        return references;
      }
    }
    return _localListOrEmpty(() => localService.referencesAt(document, offset));
  }

  @override
  RenamePlan? renameAt(DocumentState document, int offset, String newName) {
    final response = _cachedResponse(document);
    if (response != null && response.renamePlans.isNotEmpty) {
      for (final plan in response.renamePlans) {
        if (!_hasSafeEdits(document, plan.edits)) {
          continue;
        }
        if (plan.newName == newName &&
            _contains(plan.target.nameRange, offset)) {
          return plan;
        }
        for (final reference in plan.references) {
          if (plan.newName == newName && _contains(reference.range, offset)) {
            return plan;
          }
        }
      }
    }
    if (response != null &&
        response.renamePlans.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.rename,
        )) {
      return null;
    }
    if (response != null && response.referenceSpans.isNotEmpty) {
      final plan = _renameFromServiceReferences(
        document: document,
        response: response,
        offset: offset,
        newName: newName,
      );
      if (plan != null) {
        return plan;
      }
    }
    if (response != null && _hasSnapshotFacts(response)) {
      final plan = localService.navigationFeature.renameAt(
        document: document,
        snapshot: _semanticSnapshot(document, response),
        offset: offset,
        newName: newName,
      );
      if (plan != null) {
        return plan;
      }
    }
    return _localNullableOrNull(
      () => localService.renameAt(document, offset, newName),
    );
  }

  @override
  SafeDeletePlan? safeDeleteAt(DocumentState document, int offset) {
    final response = _cachedResponse(document);
    if (response != null && response.safeDeletePlans.isNotEmpty) {
      for (final plan in response.safeDeletePlans) {
        if (!_hasSafeEdits(document, plan.edits)) {
          continue;
        }
        if (_planContainsOffset(plan.target, plan.references, offset)) {
          return plan;
        }
      }
    }
    if (response != null &&
        response.safeDeletePlans.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.safeDelete,
        )) {
      return null;
    }
    if (response != null && response.referenceSpans.isNotEmpty) {
      final plan = _safeDeleteFromServiceReferences(
        document: document,
        response: response,
        offset: offset,
      );
      if (plan != null) {
        return plan;
      }
    }
    if (response != null && _hasSnapshotFacts(response)) {
      final plan = localService.refactorFeature.safeDeleteAt(
        document: document,
        snapshot: _semanticSnapshot(document, response),
        offset: offset,
      );
      if (plan != null) {
        return plan;
      }
    }
    return _localNullableOrNull(
      () => localService.safeDeleteAt(document, offset),
    );
  }

  @override
  List<SurroundTemplate> surroundTemplatesAt(
    DocumentState document,
    SourceRange range,
  ) {
    final response = _cachedResponse(document);
    if (response != null && response.surroundTemplates.isNotEmpty) {
      if (_isSafeRange(document, range)) {
        return response.surroundTemplates;
      }
    }
    if (response != null &&
        response.surroundTemplates.isEmpty &&
        _hasAvailableServiceCapability(
          response,
          StyioServiceCapability.surround,
        )) {
      return const <SurroundTemplate>[];
    }
    return _localListOrEmpty(
      () => localService.surroundTemplatesAt(document, range),
    );
  }

  StyioServiceResponse? _cachedResponse(DocumentState document) {
    return _cache.lookupDocument(
      documentId: document.documentId,
      revision: document.revision,
      protocolVersion: protocolVersion,
      toolchainId: toolchainId,
      configPath: configPath,
      workingDirectory: workingDirectory,
    );
  }

  bool _hasSnapshotFacts(StyioServiceResponse response) {
    return response.documentSymbols.isNotEmpty ||
        response.referenceSpans.isNotEmpty ||
        response.semanticSpans.isNotEmpty;
  }

  StyioServiceFallbackStatus _fallbackStatusFor(
    DocumentState document,
    StyioServiceResponse? response,
    StyioServiceCapability capability,
  ) {
    if (response == null) {
      return StyioServiceFallbackStatus.noCachedResponse;
    }
    if (response.isStaleFor(document)) {
      return StyioServiceFallbackStatus.staleResponse;
    }
    if (_hasDirectServicePayload(response, capability)) {
      return StyioServiceFallbackStatus.servicePayload;
    }
    if (_hasAuthoritativeEmptyServiceResult(response, capability)) {
      return StyioServiceFallbackStatus.serviceEmpty;
    }
    if (_canDeriveCapabilityFromSnapshotFacts(response, capability)) {
      return StyioServiceFallbackStatus.serviceDerived;
    }
    return StyioServiceFallbackStatus.localFallback;
  }

  bool _hasDirectServicePayload(
    StyioServiceResponse response,
    StyioServiceCapability capability,
  ) {
    if (capability == StyioServiceCapability.analysis) {
      return response.hasPayload;
    }
    if (capability == StyioServiceCapability.syntax ||
        capability == StyioServiceCapability.diagnostics) {
      return response.diagnostics.isNotEmpty;
    }
    return (response.payloadCounts[capability.wireValue] ?? 0) > 0;
  }

  bool _hasAuthoritativeEmptyServiceResult(
    StyioServiceResponse response,
    StyioServiceCapability capability,
  ) {
    if ((capability == StyioServiceCapability.analysis ||
            capability == StyioServiceCapability.syntax ||
            capability == StyioServiceCapability.diagnostics) &&
        response.status == StyioServiceStatus.succeeded &&
        !response.hasPayload) {
      return true;
    }
    return !_hasDirectServicePayload(response, capability) &&
        _hasAvailableServiceCapability(response, capability);
  }

  bool _canDeriveCapabilityFromSnapshotFacts(
    StyioServiceResponse response,
    StyioServiceCapability capability,
  ) {
    if (response.status != StyioServiceStatus.succeeded) {
      return false;
    }
    final hasSymbols = response.documentSymbols.isNotEmpty;
    final hasReferences = response.referenceSpans.isNotEmpty;
    return switch (capability) {
      StyioServiceCapability.completion ||
      StyioServiceCapability.hover ||
      StyioServiceCapability.semanticTokens => hasSymbols,
      StyioServiceCapability.definition ||
      StyioServiceCapability.rename ||
      StyioServiceCapability.safeDelete ||
      StyioServiceCapability.inlineVariable ||
      StyioServiceCapability.changeSignature => hasSymbols && hasReferences,
      _ => false,
    };
  }

  SemanticSnapshot _semanticSnapshot(
    DocumentState document,
    StyioServiceResponse response,
  ) {
    return resultAdapter.semanticSnapshot(
      document: document,
      localAnalysis: _fallbackAnalysis(document),
      response: response,
    );
  }

  StyioDocumentAnalysis _fallbackAnalysis(DocumentState document) {
    if (allowLocalFallback) {
      return localService.analyzeDocument(document);
    }
    return const StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[],
      referenceSpans: <ReferenceSpan>[],
    );
  }

  List<T> _localListOrEmpty<T>(List<T> Function() resolve) {
    if (!allowLocalFallback) {
      return <T>[];
    }
    return resolve();
  }

  T? _localNullableOrNull<T>(T? Function() resolve) {
    if (!allowLocalFallback) {
      return null;
    }
    return resolve();
  }

  ReferenceSpan? _referenceAt(List<ReferenceSpan> references, int offset) {
    for (final reference in references) {
      if (_contains(reference.range, offset)) {
        return reference;
      }
    }
    return null;
  }

  List<ReferenceSpan> _mergeReferenceSpans(
    List<ReferenceSpan> primary,
    List<ReferenceSpan> fallback,
  ) {
    final merged = <ReferenceSpan>[...primary];
    for (final reference in fallback) {
      if (!merged.any((existing) => _sameReferenceSpan(existing, reference))) {
        merged.add(reference);
      }
    }
    return List.unmodifiable(merged);
  }

  bool _sameReferenceSpan(ReferenceSpan left, ReferenceSpan right) {
    return _sameRange(left.range, right.range) &&
        _sameRange(left.targetRange, right.targetRange);
  }

  DocumentSymbol? _symbolForTarget(
    List<DocumentSymbol> symbols,
    SourceRange targetRange,
  ) {
    for (final symbol in symbols) {
      if (_sameRange(symbol.nameRange, targetRange) ||
          _sameRange(symbol.declarationRange, targetRange)) {
        return symbol;
      }
    }
    return null;
  }

  DocumentSymbol _symbolFromReference(ReferenceSpan reference) {
    return DocumentSymbol(
      name: reference.name,
      kind: reference.kind,
      nameRange: reference.targetRange,
      declarationRange: reference.targetRange,
    );
  }

  RenamePlan? _renameFromServiceReferences({
    required DocumentState document,
    required StyioServiceResponse response,
    required int offset,
    required String newName,
  }) {
    if (!_isValidIdentifier(newName)) {
      return null;
    }
    final reference = _referenceAt(response.referenceSpans, offset);
    if (reference == null ||
        !_isSafeRange(document, reference.range) ||
        !_isSafeRange(document, reference.targetRange)) {
      return null;
    }
    final targetRange = _canonicalTargetRange(
      response.documentSymbols,
      reference.targetRange,
    );
    final references = response.referenceSpans
        .where(
          (span) =>
              _isSafeRange(document, span.range) &&
              _isSafeRange(document, span.targetRange) &&
              _sameRange(
                _canonicalTargetRange(
                  response.documentSymbols,
                  span.targetRange,
                ),
                targetRange,
              ),
        )
        .toList(growable: false);
    if (references.isEmpty) {
      return null;
    }
    final target =
        _symbolForTarget(response.documentSymbols, targetRange) ??
        _symbolFromReference(reference);
    final conflicts = response.documentSymbols
        .where(
          (symbol) =>
              symbol.name == newName &&
              !_sameRange(symbol.nameRange, targetRange),
        )
        .map(
          (symbol) => RenameConflict(
            message: 'A symbol named $newName already exists.',
            range: symbol.nameRange,
          ),
        )
        .toList(growable: false);
    return RenamePlan(
      target: target,
      newName: newName,
      references: references,
      edits: newName == target.name || conflicts.isNotEmpty
          ? const <FormattingEdit>[]
          : [
              for (final span in references)
                FormattingEdit(range: span.range, newText: newName),
            ],
      conflicts: conflicts,
    );
  }

  SafeDeletePlan? _safeDeleteFromServiceReferences({
    required DocumentState document,
    required StyioServiceResponse response,
    required int offset,
  }) {
    final reference = _referenceAt(response.referenceSpans, offset);
    if (reference == null ||
        !_isSafeRange(document, reference.range) ||
        !_isSafeRange(document, reference.targetRange)) {
      return null;
    }
    final targetRange = _canonicalTargetRange(
      response.documentSymbols,
      reference.targetRange,
    );
    final references = response.referenceSpans
        .where(
          (span) =>
              _isSafeRange(document, span.range) &&
              _isSafeRange(document, span.targetRange) &&
              _sameRange(
                _canonicalTargetRange(
                  response.documentSymbols,
                  span.targetRange,
                ),
                targetRange,
              ),
        )
        .toList(growable: false);
    if (references.isEmpty) {
      return null;
    }
    final target =
        _symbolForTarget(response.documentSymbols, targetRange) ??
        _symbolFromReference(reference);
    final conflicts = [
      for (final span in references)
        if (!span.isDeclaration)
          SafeDeleteConflict(
            message: 'Symbol is still referenced.',
            range: span.range,
          ),
    ];
    return SafeDeletePlan(
      target: target,
      references: references,
      edits: conflicts.isEmpty
          ? [
              FormattingEdit(
                range: _lineRemovalRange(
                  document.text,
                  target.declarationRange,
                ),
                newText: '',
              ),
            ]
          : const <FormattingEdit>[],
      conflicts: conflicts,
    );
  }

  InlineVariablePlan? _inlineVariableFromServiceReferences({
    required DocumentState document,
    required StyioServiceResponse response,
    required int offset,
  }) {
    final reference = _referenceAt(response.referenceSpans, offset);
    if (reference == null ||
        reference.kind != SymbolKind.variable ||
        !_isSafeRange(document, reference.range) ||
        !_isSafeRange(document, reference.targetRange)) {
      return null;
    }
    final targetRange = _canonicalTargetRange(
      response.documentSymbols,
      reference.targetRange,
    );
    final references = response.referenceSpans
        .where(
          (span) =>
              _isSafeRange(document, span.range) &&
              _isSafeRange(document, span.targetRange) &&
              _sameRange(
                _canonicalTargetRange(
                  response.documentSymbols,
                  span.targetRange,
                ),
                targetRange,
              ),
        )
        .toList(growable: false);
    final referenceUses = references
        .where((span) => !span.isDeclaration)
        .toList(growable: false);
    if (referenceUses.isEmpty) {
      return null;
    }
    final initializerRange = _initializerRange(document.text, targetRange);
    if (initializerRange == null) {
      return null;
    }
    final initializerText = document.text.substring(
      initializerRange.start,
      initializerRange.end,
    );
    final target =
        _symbolForTarget(response.documentSymbols, targetRange) ??
        _symbolFromReference(reference);
    return InlineVariablePlan(
      target: target,
      initializerRange: initializerRange,
      initializerText: initializerText,
      references: referenceUses,
      edits: [
        for (final span in referenceUses)
          FormattingEdit(range: span.range, newText: initializerText),
        FormattingEdit(
          range: _lineRemovalRange(document.text, target.declarationRange),
          newText: '',
        ),
      ],
    );
  }

  SourceRange _canonicalTargetRange(
    List<DocumentSymbol> symbols,
    SourceRange targetRange,
  ) {
    return _symbolForTarget(symbols, targetRange)?.nameRange ?? targetRange;
  }

  bool _contains(SourceRange range, int offset) {
    return range.contains(offset);
  }

  bool _isValidIdentifier(String value) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
  }

  SourceRange _lineRemovalRange(String text, SourceRange targetRange) {
    var start = targetRange.start;
    while (start > 0 && text.codeUnitAt(start - 1) != 10) {
      start--;
    }
    var end = targetRange.end;
    while (end < text.length && text.codeUnitAt(end) != 10) {
      end++;
    }
    if (end < text.length) {
      end++;
    }
    return SourceRange(start: start, end: end);
  }

  SourceRange? _initializerRange(String text, SourceRange targetRange) {
    var lineEnd = targetRange.end;
    while (lineEnd < text.length && text.codeUnitAt(lineEnd) != 10) {
      lineEnd++;
    }
    final suffix = text.substring(targetRange.end, lineEnd);
    final operatorIndex = suffix.indexOf(':=');
    final fallbackIndex = suffix.indexOf('=');
    final index = operatorIndex >= 0 ? operatorIndex : fallbackIndex;
    if (index < 0) {
      return null;
    }
    final operatorLength = operatorIndex >= 0 ? 2 : 1;
    final rawStart = targetRange.end + index + operatorLength;
    return _trimmedRange(text, SourceRange(start: rawStart, end: lineEnd));
  }

  SourceRange _trimmedRange(String text, SourceRange range) {
    var start = range.start.clamp(0, text.length);
    var end = range.end.clamp(start, text.length);
    while (start < end && text[start].trim().isEmpty) {
      start++;
    }
    while (end > start && text[end - 1].trim().isEmpty) {
      end--;
    }
    return SourceRange(start: start, end: end);
  }

  bool _sameRange(SourceRange left, SourceRange right) {
    return left.start == right.start && left.end == right.end;
  }

  bool _planContainsOffset(
    DocumentSymbol target,
    List<ReferenceSpan> references,
    int offset,
  ) {
    if (_contains(target.nameRange, offset)) {
      return true;
    }
    for (final reference in references) {
      if (_contains(reference.range, offset)) {
        return true;
      }
    }
    return false;
  }

  bool _sameParameterUpdates(
    List<ChangeSignatureParameterUpdate> left,
    List<ChangeSignatureParameterUpdate> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      if (left[i].originalName != right[i].originalName ||
          left[i].name != right[i].name) {
        return false;
      }
    }
    return true;
  }

  bool _hasSafeEdits(DocumentState document, List<FormattingEdit> edits) {
    return normalizeFormattingEditsForDocument(
          documentLength: document.length,
          edits: edits,
        ).length ==
        edits.length;
  }

  bool _hasAvailableServiceCapability(
    StyioServiceResponse response,
    StyioServiceCapability capability,
  ) {
    final state = lookupStyioServiceCapabilityValue(
      response.capabilityStates,
      capability,
    );
    return state?.toLowerCase() == 'available';
  }

  bool _hasSafeCompletion(DocumentState document, CompletionItem item) {
    final replacementRange = item.replacementRange;
    return replacementRange == null || _isSafeRange(document, replacementRange);
  }

  bool _isSafeInlayHint(DocumentState document, InlayHint hint) {
    return _isSafeOffset(document, hint.position) &&
        _isSafeRange(document, hint.range);
  }

  bool _isSafeParameterInfo(
    DocumentState document,
    ParameterInfoPayload payload,
  ) {
    return _isSafeRange(document, payload.invocationRange) &&
        _isSafeRange(document, payload.callableRange) &&
        payload.parameters.every(
          (parameter) => _isSafeRange(document, parameter.range),
        );
  }

  bool _isSafeDefinitionTarget(
    DocumentState document,
    DefinitionTarget definition,
  ) {
    return _isSafeRange(document, definition.originRange) &&
        _isSafeRange(document, definition.symbol.nameRange) &&
        _isSafeRange(document, definition.symbol.declarationRange);
  }

  bool _isSafeRange(DocumentState document, SourceRange range) {
    return range.start >= 0 &&
        range.end >= range.start &&
        range.end <= document.length;
  }

  bool _isSafeOffset(DocumentState document, int offset) {
    return offset >= 0 && offset <= document.length;
  }
}

enum _StyioJsonRecordKind {
  facts,
  capability,
  diagnostic,
  completion,
  hover,
  semantic,
  formatting,
  semanticBlock,
  inlayHint,
  symbol,
  reference,
  definition,
  codeAction,
  rename,
  safeDelete,
  inlineVariable,
  introduceVariable,
  extractFunction,
  changeSignature,
  parameterInfo,
  surround,
}

class StyioServiceAnalysisReport {
  const StyioServiceAnalysisReport({
    required this.documentId,
    required this.revision,
    required this.analysis,
    required this.response,
    required this.cachedResponseStored,
    this.document,
    this.cacheSnapshot,
  });

  final String documentId;
  final int revision;
  final DocumentState? document;
  final StyioDocumentAnalysis analysis;
  final StyioServiceResponse response;
  final bool cachedResponseStored;
  final StyioServiceResultCacheSnapshot? cacheSnapshot;

  bool get usedFreshStyioServiceResponse {
    return response.documentId == documentId && response.revision == revision;
  }

  bool get serviceSucceeded {
    return usedFreshStyioServiceResponse && response.succeeded;
  }

  SemanticSnapshot? get semanticSnapshot {
    final sourceDocument = document;
    if (sourceDocument == null) {
      return null;
    }
    return SemanticSnapshot.fromAnalysis(
      document: sourceDocument,
      analysis: analysis,
    );
  }
}

class StyioServiceAnalysisDriver {
  const StyioServiceAnalysisDriver({
    required StyioServiceConnector connector,
    this.localService = const LocalStyioLanguageService(),
    this.resultAdapter = const StyioServiceResultAdapter(),
    this.resultCache,
    this.resultCacheManifestStore,
  }) : _connector = connector;

  final StyioServiceConnector _connector;
  final LocalStyioLanguageService localService;
  final StyioServiceResultAdapter resultAdapter;
  final StyioServiceResultCache? resultCache;
  final StyioServiceResultCacheManifestStore? resultCacheManifestStore;

  Future<StyioDocumentAnalysis> analyzeDocument(
    DocumentState document, {
    String? filePath,
    String? configPath,
    String? workingDirectory,
  }) async {
    final report = await analyzeDocumentWithReport(
      document,
      filePath: filePath,
      configPath: configPath,
      workingDirectory: workingDirectory,
    );
    return report.analysis;
  }

  Future<StyioServiceAnalysisReport> analyzeDocumentWithReport(
    DocumentState document, {
    String? filePath,
    String? configPath,
    String? workingDirectory,
  }) async {
    final localAnalysis = localService.analyzeDocument(document);
    final response = await _connector.analyzeDocument(
      StyioServiceDocument.fromDocumentState(
        document,
        filePath: filePath,
        configPath: configPath,
        workingDirectory: workingDirectory,
      ),
    );
    final fresh = !response.isStaleFor(document);
    if (fresh) {
      resultCache?.store(response);
      final cache = resultCache;
      final manifestStore = resultCacheManifestStore;
      if (cache != null && manifestStore != null) {
        await manifestStore.save(cache.snapshot());
      }
    }
    final analysis = resultAdapter.mergeAnalysis(
      document: document,
      localAnalysis: localAnalysis,
      response: response,
    );
    return StyioServiceAnalysisReport(
      documentId: document.documentId,
      revision: document.revision,
      document: document,
      analysis: analysis,
      response: response,
      cachedResponseStored: fresh && resultCache != null,
      cacheSnapshot: resultCache?.snapshot(documentId: document.documentId),
    );
  }
}
