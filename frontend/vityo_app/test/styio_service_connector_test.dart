import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/editor/editor_controller.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_capability_detector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_manager_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_runtime.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  Future<ConfigurationStore> createConfigurationStore(Directory root) async {
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: root.path,
        homePath: root.path,
      ),
    );
    return ConfigurationStore(
      dataStore: FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      ),
      credentialDataStore: InMemoryCredentialDataStore(),
    );
  }

  test('JSONL protocol decodes Styio diagnostics', () {
    const protocol = StyioCliJsonlProtocol();
    const document = StyioServiceDocument(
      documentId: 'fixture://syntax',
      text: '#main := () => {}',
      revision: 3,
      filePath: '/workspace/main.styio',
    );

    final response = protocol.decode(
      document: document,
      stdout:
          '{"severity":"error","code":"styio.syntax","message":"bad token",'
          '"range":{"start":1,"end":5}}\n',
      stderr: '',
      exitCode: 1,
      toolchainSucceeded: false,
    );

    expect(response.status, StyioServiceStatus.succeeded);
    expect(response.diagnostics, hasLength(1));
    expect(response.diagnostics.first.severity, DiagnosticSeverity.error);
    expect(response.diagnostics.first.code, 'styio.syntax');
    expect(response.diagnostics.first.range.start, 1);
    expect(response.diagnostics.first.range.end, 5);
  });

  test('JSONL protocol includes project config when provided', () {
    const protocol = StyioCliJsonlProtocol();
    const document = StyioServiceDocument(
      documentId: 'fixture://configured',
      text: '#main := () => {}',
      revision: 1,
      filePath: '/workspace/src/main.styio',
      configPath: '/workspace/styio.toml',
    );

    final arguments = protocol.analyzeArguments(document);

    expect(
      arguments,
      containsAllInOrder(<String>[
        '--config',
        '/workspace/styio.toml',
        '--file',
        '/workspace/src/main.styio',
      ]),
    );
  });

  test('JSONL protocol decodes Styio language facts', () {
    const protocol = StyioCliJsonlProtocol();
    const document = StyioServiceDocument(
      documentId: 'fixture://facts',
      text: 'value = 1\nvalue\n',
      revision: 1,
      filePath: '/workspace/main.styio',
    );

    final response = protocol.decode(
      document: document,
      stdout: [
        '{"record":"completion","completion":{"label":"value",'
            '"kind":"variable","insertText":"value","detail":"binding"}}',
        '{"record":"hover","hover":{"markdown":"**value**",'
            '"range":{"start":10,"end":15}}}',
        '{"record":"semantic","semantic":{"kind":"variable",'
            '"range":{"start":10,"end":15}}}',
        '{"record":"formattingEdit","formattingEdit":{"start":15,'
            '"end":15,"newText":"\\n"}}',
        '{"record":"semanticBlock","semanticBlock":{"label":"main",'
            '"range":{"start":0,"end":15}}}',
        '{"record":"inlayHint","inlayHint":{"label":": i64",'
            '"kind":"type","position":5,"range":{"start":0,"end":5}}}',
        '{"record":"symbol","symbol":{"name":"value","kind":"variable",'
            '"nameRange":{"start":0,"end":5},'
            '"declarationRange":{"start":0,"end":9}}}',
        '{"record":"reference","reference":{"name":"value",'
            '"kind":"variable","range":{"start":10,"end":15},'
            '"targetRange":{"start":0,"end":5},"access":"read"}}',
        '{"record":"definition","definition":{'
            '"originRange":{"start":10,"end":15},'
            '"target":{"name":"value","kind":"variable",'
            '"nameRange":{"start":0,"end":5},'
            '"declarationRange":{"start":0,"end":9}}}}',
        '{"record":"codeAction","codeAction":{"label":"Replace value",'
            '"detail":"demo action","edits":[{"start":10,"end":15,'
            '"newText":"nextValue"}]}}',
        '{"record":"rename","rename":{"newName":"nextValue",'
            '"target":{"name":"value","kind":"variable",'
            '"nameRange":{"start":0,"end":5},'
            '"declarationRange":{"start":0,"end":9}},'
            '"references":[{"name":"value","kind":"variable",'
            '"range":{"start":10,"end":15},'
            '"targetRange":{"start":0,"end":5}}],'
            '"edits":[{"start":10,"end":15,"newText":"nextValue"}],'
            '"conflicts":[]}}',
        '{"record":"safeDelete","safeDelete":{"target":{"name":"value",'
            '"kind":"variable","nameRange":{"start":0,"end":5},'
            '"declarationRange":{"start":0,"end":9}},'
            '"references":[{"name":"value","kind":"variable",'
            '"range":{"start":10,"end":15},'
            '"targetRange":{"start":0,"end":5}}],'
            '"edits":[{"start":0,"end":10,"newText":""}],'
            '"conflicts":[]}}',
        '{"record":"inlineVariable","inlineVariable":{"target":{"name":"value",'
            '"kind":"variable","nameRange":{"start":0,"end":5},'
            '"declarationRange":{"start":0,"end":9}},'
            '"initializerRange":{"start":8,"end":9},'
            '"initializerText":"1",'
            '"references":[{"name":"value","kind":"variable",'
            '"range":{"start":10,"end":15},'
            '"targetRange":{"start":0,"end":5}}],'
            '"edits":[{"start":10,"end":15,"newText":"1"}],'
            '"conflicts":[]}}',
        '{"record":"introduceVariable","introduceVariable":{'
            '"variableName":"nextValue",'
            '"expressionRange":{"start":10,"end":15},'
            '"expressionText":"value",'
            '"edits":[{"start":10,"end":15,"newText":"nextValue"}],'
            '"conflicts":[]}}',
        '{"record":"extractFunction","extractFunction":{'
            '"functionName":"readValue",'
            '"selectionRange":{"start":10,"end":15},'
            '"selectedText":"value","parameters":["value"],'
            '"callText":"readValue(value)",'
            '"functionText":"#readValue := () => {\\n  value\\n}\\n",'
            '"edits":[{"start":10,"end":15,"newText":"readValue(value)"}],'
            '"duplicateOccurrences":[{"start":10,"end":15}],'
            '"conflicts":[]}}',
        '{"record":"changeSignature","changeSignature":{'
            '"target":{"name":"value","kind":"function",'
            '"nameRange":{"start":0,"end":5},'
            '"declarationRange":{"start":0,"end":9}},'
            '"originalName":"value","newName":"nextValue",'
            '"originalParameters":[{"name":"x","type":"i64",'
            '"start":1,"end":2}],'
            '"newParameters":[{"originalName":"x","name":"nextX"}],'
            '"references":[{"name":"value","kind":"function",'
            '"range":{"start":10,"end":15},'
            '"targetRange":{"start":0,"end":5}}],'
            '"edits":[{"start":10,"end":15,"newText":"nextValue"}],'
            '"conflicts":[]}}',
        '{"record":"parameterInfo","parameterInfo":{"callableName":"value",'
            '"signature":"value(x: i64)","activeParameterIndex":0,'
            '"invocationRange":{"start":10,"end":15},'
            '"callableRange":{"start":10,"end":15},'
            '"parameters":[{"name":"x","type":"i64",'
            '"start":11,"end":12}]}}',
        '{"record":"surroundTemplate","surroundTemplate":{'
            '"id":"styio.service-block","label":"service block",'
            '"openingLine":"{","closingLine":"}",'
            '"detail":"Wrap with service-provided block."}}',
      ].join('\n'),
      stderr: '',
      exitCode: 0,
      toolchainSucceeded: true,
    );

    expect(response.status, StyioServiceStatus.succeeded);
    expect(response.completions.single.label, 'value');
    expect(response.hovers.single.markdown, '**value**');
    expect(response.semanticSpans.single.kind, SemanticKind.variable);
    expect(response.formattingEdits.single.newText, '\n');
    expect(response.semanticBlocks.single.label, 'main');
    expect(response.inlayHints.single.label, ': i64');
    expect(response.documentSymbols.single.name, 'value');
    expect(response.referenceSpans.single.targetRange.start, 0);
    expect(response.definitionTargets.single.symbol.name, 'value');
    expect(response.codeActions.single.label, 'Replace value');
    expect(response.renamePlans.single.newName, 'nextValue');
    expect(response.safeDeletePlans.single.edits.single.newText, '');
    expect(response.inlineVariablePlans.single.initializerText, '1');
    expect(response.introduceVariablePlans.single.variableName, 'nextValue');
    expect(response.extractFunctionPlans.single.functionName, 'readValue');
    expect(
      response.changeSignaturePlans.single.newParameters.single.name,
      'nextX',
    );
    expect(response.parameterInfos.single.callableName, 'value');
    expect(response.surroundTemplates.single.id, 'styio.service-block');
    expect(response.hasPayload, isTrue);
    expect(
      response.payloadCounts[StyioServiceCapability.completion.wireValue],
      1,
    );
    expect(response.payloadCounts[StyioServiceCapability.rename.wireValue], 1);
    expect(
      response.payloadCounts[StyioServiceCapability.definition.wireValue],
      1,
    );
    expect(
      response.payloadCounts[StyioServiceCapability.surround.wireValue],
      1,
    );
    expect(
      response.payloadCounts.keys,
      everyElement(
        isIn(
          StyioServiceCapability.values
              .map((capability) => capability.wireValue)
              .toSet(),
        ),
      ),
    );
    expect(
      response.payloadCounts.keys.toSet(),
      StyioServiceCapability.values
          .where(
            (capability) =>
                capability != StyioServiceCapability.analysis &&
                capability != StyioServiceCapability.syntax,
          )
          .map((capability) => capability.wireValue)
          .toSet(),
    );
    final envelope = response.toJson();
    expect(
      (envelope['payloadCounts']
          as Map)[StyioServiceCapability.parameterInfo.wireValue],
      1,
    );
    expect(envelope['stdoutBytes'], greaterThan(0));
    expect(envelope.containsKey('stdout'), isFalse);
  });

  test('JSONL protocol decodes published Styio facts envelope', () {
    const protocol = StyioCliJsonlProtocol();
    const document = StyioServiceDocument(
      documentId: 'fixture://facts-envelope',
      text: 'value\n',
      revision: 1,
      filePath: '/workspace/main.styio',
    );

    final response = protocol.decode(
      document: document,
      stdout: File(
        'test/fixtures/styio_service/facts_envelope.jsonl',
      ).readAsStringSync(),
      stderr: '',
      exitCode: 0,
      toolchainSucceeded: true,
    );

    expect(response.status, StyioServiceStatus.succeeded);
    expect(response.diagnostics.single.code, 'styio.demo');
    expect(response.completions.single.label, 'value');
    expect(response.hovers.single.markdown, '**value**');
    expect(response.semanticSpans.single.kind, SemanticKind.variable);
    expect(response.documentSymbols.single.name, 'value');
    expect(response.referenceSpans.single.isDeclaration, isTrue);
    expect(
      response.capabilityStates[StyioServiceCapability.completion.wireValue],
      'available',
    );
    expect(
      response.capabilityStates[StyioServiceCapability.hover.wireValue],
      'unsupported',
    );
    expect(
      response.capabilityMessages[StyioServiceCapability.hover.wireValue],
      'hover facts are not emitted by this toolchain',
    );
    expect(
      response.payloadCounts[StyioServiceCapability.completion.wireValue],
      1,
    );
    expect(response.protocolVersion, 'styio-service-facts-v1');
  });

  test('JSONL protocol decodes Styio parser and grammar versions', () {
    const protocol = StyioCliJsonlProtocol();
    const document = StyioServiceDocument(
      documentId: 'fixture://grammar-version',
      text: 'value\n',
      revision: 1,
      filePath: '/workspace/main.styio',
    );

    final response = protocol.decode(
      document: document,
      stdout:
          '{"record":"facts","protocolVersion":"styio-service-facts-v1",'
          '"parserEngine":"nightly","grammarVersion":"2026.05",'
          '"facts":{"completions":[{"label":"value",'
          '"kind":"variable","insertText":"value"}]}}\n',
      stderr: '',
      exitCode: 0,
      toolchainSucceeded: true,
    );

    expect(response.protocolVersion, 'styio-service-facts-v1');
    expect(response.parserEngine, 'nightly');
    expect(response.grammarVersion, '2026.05');
    expect(response.toJson()['parserEngine'], 'nightly');
    expect(response.toJson()['grammarVersion'], '2026.05');
  });

  test('JSONL protocol accepts snake case service protocol version', () {
    const protocol = StyioCliJsonlProtocol();
    const document = StyioServiceDocument(
      documentId: 'fixture://snake-case-protocol',
      text: 'value\n',
      revision: 1,
      filePath: '/workspace/main.styio',
    );

    final response = protocol.decode(
      document: document,
      stdout:
          '{"record":"facts","protocol_version":"styio-service-facts-v2",'
          '"parser_engine":"nightly","grammar_version":"2026.06",'
          '"facts":{"completions":[{"label":"value",'
          '"kind":"variable","insertText":"value"}]}}\n',
      stderr: '',
      exitCode: 0,
      toolchainSucceeded: true,
    );

    expect(response.protocolVersion, 'styio-service-facts-v2');
    expect(response.parserEngine, 'nightly');
    expect(response.grammarVersion, '2026.06');
    expect(response.completions.single.label, 'value');
  });

  test('JSONL protocol normalizes capability names from service records', () {
    const protocol = StyioCliJsonlProtocol();
    const document = StyioServiceDocument(
      documentId: 'fixture://capability-normalization',
      text: 'value\n',
      revision: 1,
      filePath: '/workspace/main.styio',
    );

    final response = protocol.decode(
      document: document,
      stdout: [
        '{"record":"capability_state","capability":"semantic_tokens",'
            '"state":"available"}',
        '{"record":"capabilityStatus","name":"codeActions",'
            '"status":"unsupported","message":"code actions unavailable"}',
        '{"record":"facts","facts":{"capabilities":{'
            '"safe_delete":"available",'
            '"parameterInfo":{"state":"empty",'
            '"message":"signature help unavailable"}}}}',
      ].join('\n'),
      stderr: '',
      exitCode: 0,
      toolchainSucceeded: true,
    );

    expect(
      response.capabilityStates[StyioServiceCapability
          .semanticTokens
          .wireValue],
      'available',
    );
    expect(
      response.capabilityStates[StyioServiceCapability.codeActions.wireValue],
      'unsupported',
    );
    expect(
      response.capabilityMessages[StyioServiceCapability.codeActions.wireValue],
      'code actions unavailable',
    );
    expect(
      response.capabilityStates[StyioServiceCapability.safeDelete.wireValue],
      'available',
    );
    expect(
      response.capabilityMessages[StyioServiceCapability
          .parameterInfo
          .wireValue],
      'signature help unavailable',
    );
  });

  test('JSONL protocol decodes alias wrappers and conflict payloads', () {
    const protocol = StyioCliJsonlProtocol();
    const document = StyioServiceDocument(
      documentId: 'fixture://alias-facts',
      text: 'value = 1\nvalue\n',
      revision: 2,
      filePath: '/workspace/alias.styio',
    );

    Map<String, Object?> range(int start, int end) {
      return <String, Object?>{'start': start, 'end': end};
    }

    Map<String, Object?> symbol(String name) {
      return <String, Object?>{
        'name': name,
        'kind': 'variable',
        'nameRange': range(0, 5),
        'declarationRange': range(0, 9),
      };
    }

    final response = protocol.decode(
      document: document,
      stdout: <String>[
        jsonEncode(<String, Object?>{
          'record': 'facts',
          'semanticSnapshot': <String, Object?>{
            'errors': <Object?>[
              <String, Object?>{
                'error': <String, Object?>{
                  'severity': 'warn',
                  'code': 'styio.alias.warning',
                  'message': 'alias diagnostic',
                  'location': <String, Object?>{'offset': '0', 'length': '5'},
                },
              },
            ],
            'completionItems': <Object?>[
              <String, Object?>{
                'item': <String, Object?>{
                  'name': 'aliasCompletion',
                  'kind': 'function',
                },
              },
            ],
            'capabilities': <Object?>[
              <String, Object?>{
                'name': 'hover',
                'status': 'available',
                'message': 'hover alias available',
              },
              <String, Object?>{
                'formatting': <String, Object?>{
                  'state': 'available',
                  'message': 'formatting alias available',
                },
              },
              <String, Object?>{'surround': 'available'},
            ],
          },
        }),
        jsonEncode(<String, Object?>{
          'type': 'facts',
          'snapshot': <String, Object?>{
            'symbols': <Object?>[
              <String, Object?>{
                'symbol': <String, Object?>{
                  'name': 'snapshotValue',
                  'kind': 'task',
                  'span': <String, Object?>{
                    'startOffset': 0,
                    'endOffset': 5,
                  },
                },
              },
            ],
            'referenceSpans': <Object?>[
              <String, Object?>{
                'reference': <String, Object?>{
                  'name': 'snapshotValue',
                  'kind': 'task',
                  'span': range(10, 15),
                  'targetRange': range(0, 5),
                  'access': 'declaration',
                },
              },
            ],
          },
        }),
        jsonEncode(<String, Object?>{
          'kind': 'definitionTarget',
          'definitionTarget': <String, Object?>{
            'origin': range(10, 15),
            'symbol': symbol('value'),
          },
        }),
        jsonEncode(<String, Object?>{
          'kind': 'quickFix',
          'quickFix': <String, Object?>{
            'title': 'Quick fix alias',
            'edits': <Object?>[
              1,
              <String, Object?>{
                'edit': <String, Object?>{
                  'offset': 10,
                  'length': 5,
                  'replacement': 'nextValue',
                },
              },
            ],
          },
        }),
        jsonEncode(<String, Object?>{
          'kind': 'intention',
          'intention': <String, Object?>{'label': 'Intention alias'},
        }),
        jsonEncode(<String, Object?>{
          'kind': 'surroundTemplateItem',
          'template': <String, Object?>{
            'key': 'alias-surround',
            'title': 'Alias surround',
            'open': '{',
            'close': '}',
          },
        }),
        jsonEncode(<String, Object?>{
          'kind': 'renamePlan',
          'renamePlan': <String, Object?>{
            'newName': 'nextValue',
            'target': symbol('value'),
            'references': <Object?>[
              <String, Object?>{
                'name': 'value',
                'kind': 'variable',
                'range': range(10, 15),
                'targetRange': range(0, 5),
              },
            ],
            'conflicts': <Object?>[
              'invalid',
              <String, Object?>{
                'span': range(0, 5),
                'message': 'rename conflict',
              },
            ],
          },
        }),
        jsonEncode(<String, Object?>{
          'kind': 'safeDeletePlan',
          'safeDeletePlan': <String, Object?>{
            'target': symbol('value'),
            'references': <Object?>[],
            'conflicts': <Object?>[
              'invalid',
              <String, Object?>{
                'location': range(0, 5),
                'message': 'delete conflict',
              },
            ],
          },
        }),
        jsonEncode(<String, Object?>{
          'kind': 'inlineVariablePlan',
          'inlineVariablePlan': <String, Object?>{
            'target': symbol('value'),
            'initializerRange': range(8, 9),
            'initializerText': '1',
            'references': <Object?>[],
            'conflicts': <Object?>[
              'invalid',
              <String, Object?>{
                'range': range(0, 5),
                'message': 'inline conflict',
              },
            ],
          },
        }),
        jsonEncode(<String, Object?>{
          'kind': 'introduceVariablePlan',
          'introduceVariablePlan': <String, Object?>{
            'name': 'introduced',
            'expressionRange': range(10, 15),
            'expressionText': 'value',
            'conflicts': <Object?>[
              'invalid',
              <String, Object?>{
                'range': range(10, 15),
                'message': 'introduce conflict',
              },
            ],
          },
        }),
        jsonEncode(<String, Object?>{
          'kind': 'extractFunctionPlan',
          'extractFunctionPlan': <String, Object?>{
            'name': 'readValue',
            'selectionRange': range(10, 15),
            'selectedText': 'value',
            'callText': 'readValue()',
            'functionText': 'fn readValue() => value',
            'duplicateOccurrences': <Object?>[
              'invalid',
              <String, Object?>{'span': range(10, 15)},
            ],
            'conflicts': <Object?>[
              'invalid',
              <String, Object?>{
                'range': range(10, 15),
                'message': 'extract conflict',
              },
            ],
          },
        }),
        jsonEncode(<String, Object?>{
          'kind': 'changeSignaturePlan',
          'changeSignaturePlan': <String, Object?>{
            'target': symbol('value'),
            'originalName': 'value',
            'newName': 'nextValue',
            'newParameters': <Object?>[
              'invalid',
              <String, Object?>{'name': 'renamed'},
            ],
            'conflicts': <Object?>[
              'invalid',
              <String, Object?>{
                'range': range(0, 5),
                'message': 'signature conflict',
              },
            ],
          },
        }),
      ].join('\n'),
      stderr: '{not json}\n',
      exitCode: 0,
      toolchainSucceeded: true,
    );

    expect(response.status, StyioServiceStatus.succeeded);
    expect(response.diagnostics.single.severity, DiagnosticSeverity.warning);
    expect(response.completions.single.label, 'aliasCompletion');
    expect(response.documentSymbols.single.kind, SymbolKind.task);
    expect(response.referenceSpans.single.access, ReferenceAccess.declaration);
    expect(response.definitionTargets.single.originRange.start, 10);
    expect(
      response.codeActions.map((action) => action.label),
      containsAll(<String>['Quick fix alias', 'Intention alias']),
    );
    expect(response.surroundTemplates.single.id, 'alias-surround');
    expect(
      response.renamePlans.single.conflicts.single.message,
      'rename conflict',
    );
    expect(
      response.safeDeletePlans.single.conflicts.single.message,
      'delete conflict',
    );
    expect(
      response.inlineVariablePlans.single.conflicts.single.message,
      'inline conflict',
    );
    expect(
      response.introduceVariablePlans.single.conflicts.single.message,
      'introduce conflict',
    );
    expect(
      response.extractFunctionPlans.single.duplicateOccurrences.single.start,
      10,
    );
    expect(
      response.changeSignaturePlans.single.newParameters.single.name,
      'renamed',
    );
    expect(response.capabilityStates['hover'], 'available');
    expect(
      response.capabilityMessages['formatting'],
      'formatting alias available',
    );
    expect(response.capabilityStates['surround'], 'available');
  });

  test('document materializer preserves already materialized files', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_styio_materializer_existing_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final materializer = StyioServiceDocumentMaterializer(
      fileSystemManager: LocalFileSystemManager.linuxDebianArmForTest(),
      resourceManager: LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      ),
    );
    const document = StyioServiceDocument(
      documentId: 'fixture://materialized',
      text: 'value = 1\n',
      revision: 1,
      filePath: '/workspace/materialized.styio',
    );

    final result = await materializer.materialize<String>(
      document,
      (materialized) async => materialized.filePath!,
    );

    expect(result, '/workspace/materialized.styio');
  });

  test('JSONL protocol accepts compact parameter info payloads', () {
    const document = StyioServiceDocument(
      documentId: 'fixture://compact-parameter-info',
      text: 'value = zero()',
      revision: 1,
    );
    final response = const StyioCliJsonlProtocol().decode(
      document: document,
      stdout:
          '{"record":"parameterInfo","parameterInfo":{'
          '"callableName":"zero","signature":"zero()",'
          '"range":{"start":8,"end":14},'
          '"parameters":[{"name":"x","type":"i64"}]}}\n',
      stderr: '',
      exitCode: 0,
      toolchainSucceeded: true,
    );

    final info = response.parameterInfos.single;

    expect(info.callableName, 'zero');
    expect(info.activeParameterIndex, -1);
    expect(info.invocationRange.start, 8);
    expect(info.invocationRange.end, 14);
    expect(info.callableRange.start, 8);
    expect(info.callableRange.end, 14);
    expect(info.parameters.single.displayText, 'x: i64');
    expect(info.parameters.single.range.start, 0);
    expect(info.parameters.single.range.end, 0);
  });

  test(
    'result adapter replaces local diagnostics with fresh Styio diagnostics',
    () {
      const adapter = StyioServiceResultAdapter();
      const document = DocumentState(
        documentId: 'fixture://syntax',
        text: '#main := () => {}',
        revision: 3,
      );
      const local = StyioDocumentAnalysis(
        tokenSpans: <TokenSpan>[],
        semanticSpans: <SemanticSpan>[],
        diagnostics: <Diagnostic>[
          Diagnostic(
            severity: DiagnosticSeverity.hint,
            code: 'local.hint',
            message: 'local',
            range: SourceRange(start: 0, end: 0),
          ),
        ],
        formattingEdits: <FormattingEdit>[],
        semanticBlocks: <SemanticBlockRange>[],
        inlayHints: <InlayHint>[],
        documentSymbols: <DocumentSymbol>[],
        referenceSpans: <ReferenceSpan>[],
      );
      const response = StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://syntax',
        revision: 3,
        diagnostics: <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.error,
            code: 'styio.syntax',
            message: 'bad token',
            range: SourceRange(start: 1, end: 5),
          ),
        ],
      );

      final merged = adapter.mergeAnalysis(
        document: document,
        localAnalysis: local,
        response: response,
      );

      expect(merged.diagnostics, hasLength(1));
      expect(merged.diagnostics.first.code, 'styio.syntax');
    },
  );

  test(
    'result adapter keeps local diagnostics when Styio service fails empty',
    () {
      const adapter = StyioServiceResultAdapter();
      const document = DocumentState(
        documentId: 'fixture://failed-empty',
        text: '#main := () => {}',
        revision: 3,
      );
      const local = StyioDocumentAnalysis(
        tokenSpans: <TokenSpan>[],
        semanticSpans: <SemanticSpan>[],
        diagnostics: <Diagnostic>[
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'local.syntax',
            message: 'local diagnostic',
            range: SourceRange(start: 0, end: 5),
          ),
        ],
        formattingEdits: <FormattingEdit>[],
        semanticBlocks: <SemanticBlockRange>[],
        inlayHints: <InlayHint>[],
        documentSymbols: <DocumentSymbol>[],
        referenceSpans: <ReferenceSpan>[],
      );
      const response = StyioServiceResponse(
        status: StyioServiceStatus.failed,
        documentId: 'fixture://failed-empty',
        revision: 3,
        message: 'toolchain failed before diagnostics',
      );

      final merged = adapter.mergeAnalysis(
        document: document,
        localAnalysis: local,
        response: response,
      );

      expect(merged.diagnostics.single.code, 'local.syntax');
    },
  );

  test('result adapter respects empty available service analysis payloads', () {
    const adapter = StyioServiceResultAdapter();
    const document = DocumentState(
      documentId: 'fixture://empty-available-analysis',
      text: 'value',
      revision: 3,
    );
    const localSymbol = DocumentSymbol(
      name: 'value',
      kind: SymbolKind.variable,
      nameRange: SourceRange(start: 0, end: 5),
      declarationRange: SourceRange(start: 0, end: 5),
    );
    const local = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[
        SemanticSpan(
          range: SourceRange(start: 0, end: 5),
          kind: SemanticKind.variable,
        ),
      ],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[
        FormattingEdit(range: SourceRange(start: 5, end: 5), newText: '\n'),
      ],
      semanticBlocks: <SemanticBlockRange>[
        SemanticBlockRange(
          range: SourceRange(start: 0, end: 5),
          label: 'local',
        ),
      ],
      inlayHints: <InlayHint>[
        InlayHint(
          label: ': i64',
          kind: InlayHintKind.type,
          position: 5,
          range: SourceRange(start: 0, end: 5),
        ),
      ],
      documentSymbols: <DocumentSymbol>[localSymbol],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.variable,
          range: SourceRange(start: 0, end: 5),
          targetRange: SourceRange(start: 0, end: 5),
          isDeclaration: true,
        ),
      ],
    );
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://empty-available-analysis',
      revision: 3,
      capabilityStates: <String, String>{
        'formatting': 'available',
        'semantic-tokens': 'available',
        'semantic-blocks': 'available',
        'inlay-hints': 'available',
        'document-symbols': 'available',
        'references': 'available',
      },
    );

    final merged = adapter.mergeAnalysis(
      document: document,
      localAnalysis: local,
      response: response,
    );

    expect(merged.formattingEdits, isEmpty);
    expect(merged.semanticSpans, isEmpty);
    expect(merged.semanticBlocks, isEmpty);
    expect(merged.inlayHints, isEmpty);
    expect(merged.documentSymbols, isEmpty);
    expect(merged.referenceSpans, isEmpty);
  });

  test('response telemetry bridge emits semantic panel events', () {
    const bridge = StyioServiceResponseTelemetryBridge();
    final events = bridge.eventsForResponse(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://telemetry',
        revision: 7,
        diagnostics: <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.error,
            code: 'styio.syntax',
            message: 'Unexpected token.',
            range: SourceRange(start: 0, end: 1),
          ),
        ],
        semanticSpans: <SemanticSpan>[
          SemanticSpan(
            range: SourceRange(start: 0, end: 4),
            kind: SemanticKind.function,
          ),
        ],
        semanticBlocks: <SemanticBlockRange>[
          SemanticBlockRange(
            range: SourceRange(start: 0, end: 4),
            label: 'function',
          ),
        ],
        documentSymbols: <DocumentSymbol>[
          DocumentSymbol(
            name: 'main',
            kind: SymbolKind.function,
            nameRange: SourceRange(start: 0, end: 4),
            declarationRange: SourceRange(start: 0, end: 4),
          ),
        ],
        inlayHints: <InlayHint>[
          InlayHint(
            label: ': string',
            kind: InlayHintKind.type,
            position: 4,
            range: SourceRange(start: 0, end: 4),
          ),
        ],
        protocolVersion: 'styio-cli-jsonl-v2',
        parserEngine: 'nightly',
        grammarVersion: '2026.05',
        toolchainId: 'styio-nightly',
      ),
      timestamp: DateTime.utc(2026, 5, 21, 3),
    );

    final diagnosticsPayload =
        events.first.metadata['payload']! as Map<String, Object?>;
    final tokensPayload =
        events.last.metadata['payload']! as Map<String, Object?>;

    expect(events, hasLength(2));
    expect(events.first.metadata['semanticEventKind'], 'diagnostics-snapshot');
    expect(events.last.metadata['semanticEventKind'], 'semantic-tokens');
    expect(diagnosticsPayload['providerId'], 'styio-service:styio-nightly');
    expect(diagnosticsPayload['diagnosticCount'], 1);
    expect(diagnosticsPayload['hasErrors'], isTrue);
    expect(diagnosticsPayload['status'], 'succeeded');
    expect(diagnosticsPayload['grammarVersion'], '2026.05');
    expect(tokensPayload['semanticSpanCount'], 1);
    expect(tokensPayload['semanticBlockCount'], 1);
    expect(tokensPayload['documentSymbolCount'], 1);
    expect(tokensPayload['inlayHintCount'], 1);
  });

  test(
    'result adapter keeps local diagnostics when failed service diagnostics are unsafe',
    () {
      const adapter = StyioServiceResultAdapter();
      const document = DocumentState(
        documentId: 'fixture://failed-unsafe-diagnostics',
        text: '#main := () => {}',
        revision: 3,
      );
      const local = StyioDocumentAnalysis(
        tokenSpans: <TokenSpan>[],
        semanticSpans: <SemanticSpan>[],
        diagnostics: <Diagnostic>[
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'local.syntax',
            message: 'local diagnostic',
            range: SourceRange(start: 0, end: 5),
          ),
        ],
        formattingEdits: <FormattingEdit>[],
        semanticBlocks: <SemanticBlockRange>[],
        inlayHints: <InlayHint>[],
        documentSymbols: <DocumentSymbol>[],
        referenceSpans: <ReferenceSpan>[],
      );
      const response = StyioServiceResponse(
        status: StyioServiceStatus.failed,
        documentId: 'fixture://failed-unsafe-diagnostics',
        revision: 3,
        diagnostics: <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.error,
            code: 'service.unsafe',
            message: 'unsafe diagnostic',
            range: SourceRange(start: 0, end: 99),
          ),
        ],
      );

      final merged = adapter.mergeAnalysis(
        document: document,
        localAnalysis: local,
        response: response,
      );

      expect(merged.diagnostics.single.code, 'local.syntax');
    },
  );

  test('result adapter builds semantic snapshot from Styio facts', () {
    const adapter = StyioServiceResultAdapter();
    const document = DocumentState(
      documentId: 'fixture://semantic',
      text: 'value := 1\nvalue\n',
      revision: 5,
    );
    const local = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[],
      referenceSpans: <ReferenceSpan>[],
    );
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://semantic',
      revision: 5,
      documentSymbols: <DocumentSymbol>[
        DocumentSymbol(
          name: 'value',
          kind: SymbolKind.variable,
          nameRange: SourceRange(start: 0, end: 5),
          declarationRange: SourceRange(start: 0, end: 10),
          detail: 'Styio binding',
        ),
      ],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.variable,
          range: SourceRange(start: 11, end: 16),
          targetRange: SourceRange(start: 0, end: 5),
          access: ReferenceAccess.read,
        ),
      ],
    );

    final snapshot = adapter.semanticSnapshot(
      document: document,
      localAnalysis: local,
      response: response,
    );
    final reference = snapshot.referenceAt(11);

    expect(snapshot.documentId, document.documentId);
    expect(snapshot.revision, document.revision);
    expect(snapshot.elements.single.name, 'value');
    expect(reference, isNotNull);
    expect(reference!.target.name, 'value');
    expect(reference.access, ResolvedReferenceAccess.read);
  });

  test(
    'result adapter completes declaration references from Styio symbols',
    () {
      const adapter = StyioServiceResultAdapter();
      const document = DocumentState(
        documentId: 'fixture://semantic-analysis-references',
        text: 'serviceValue\nserviceValue\n',
        revision: 6,
      );
      const local = StyioDocumentAnalysis(
        tokenSpans: <TokenSpan>[],
        semanticSpans: <SemanticSpan>[],
        diagnostics: <Diagnostic>[],
        formattingEdits: <FormattingEdit>[],
        semanticBlocks: <SemanticBlockRange>[],
        inlayHints: <InlayHint>[],
        documentSymbols: <DocumentSymbol>[],
        referenceSpans: <ReferenceSpan>[],
      );
      const response = StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://semantic-analysis-references',
        revision: 6,
        documentSymbols: <DocumentSymbol>[
          DocumentSymbol(
            name: 'serviceValue',
            kind: SymbolKind.variable,
            nameRange: SourceRange(start: 0, end: 12),
            declarationRange: SourceRange(start: 0, end: 12),
          ),
        ],
        referenceSpans: <ReferenceSpan>[
          ReferenceSpan(
            name: 'serviceValue',
            kind: SymbolKind.variable,
            range: SourceRange(start: 13, end: 25),
            targetRange: SourceRange(start: 0, end: 12),
            access: ReferenceAccess.read,
          ),
        ],
      );

      final merged = adapter.mergeAnalysis(
        document: document,
        localAnalysis: local,
        response: response,
      );

      expect(merged.referenceSpans, hasLength(2));
      expect(
        merged.referenceSpans.any(
          (reference) =>
              reference.range.start == 0 &&
              reference.range.end == 12 &&
              reference.isDeclaration,
        ),
        isTrue,
      );
      expect(
        merged.referenceSpans.any(
          (reference) =>
              reference.range.start == 13 &&
              reference.range.end == 25 &&
              reference.access == ReferenceAccess.read,
        ),
        isTrue,
      );
    },
  );

  test('result adapter filters unsafe service analysis payload ranges', () {
    const adapter = StyioServiceResultAdapter();
    const document = DocumentState(
      documentId: 'fixture://unsafe-analysis-payloads',
      text: 'value = 1\nvalue\n',
      revision: 1,
    );
    const local = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[],
      referenceSpans: <ReferenceSpan>[],
    );
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://unsafe-analysis-payloads',
      revision: 1,
      diagnostics: <StyioServiceDiagnosticDto>[
        StyioServiceDiagnosticDto(
          severity: DiagnosticSeverity.warning,
          code: 'unsafe.diagnostic',
          message: 'Unsafe diagnostic.',
          range: SourceRange(start: 0, end: 99),
        ),
      ],
      formattingEdits: <FormattingEdit>[
        FormattingEdit(
          range: SourceRange(start: 0, end: 99),
          newText: 'unsafe',
        ),
      ],
      semanticSpans: <SemanticSpan>[
        SemanticSpan(
          range: SourceRange(start: 0, end: 99),
          kind: SemanticKind.variable,
        ),
      ],
      semanticBlocks: <SemanticBlockRange>[
        SemanticBlockRange(
          range: SourceRange(start: 0, end: 99),
          label: 'unsafeBlock',
        ),
      ],
      inlayHints: <InlayHint>[
        InlayHint(
          label: ': unsafe',
          kind: InlayHintKind.type,
          position: 99,
          range: SourceRange(start: 0, end: 99),
        ),
      ],
      documentSymbols: <DocumentSymbol>[
        DocumentSymbol(
          name: 'unsafeSymbol',
          kind: SymbolKind.variable,
          nameRange: SourceRange(start: 0, end: 99),
          declarationRange: SourceRange(start: 0, end: 99),
        ),
      ],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'unsafeReference',
          kind: SymbolKind.variable,
          range: SourceRange(start: 0, end: 99),
          targetRange: SourceRange(start: 0, end: 99),
        ),
      ],
    );

    final merged = adapter.mergeAnalysis(
      document: document,
      localAnalysis: local,
      response: response,
    );

    bool safe(SourceRange range) {
      return range.start >= 0 &&
          range.end >= range.start &&
          range.end <= document.length;
    }

    expect(
      merged.diagnostics.map((diagnostic) => diagnostic.code),
      isNot(contains('unsafe.diagnostic')),
    );
    expect(merged.formattingEdits.every((edit) => safe(edit.range)), isTrue);
    expect(merged.semanticSpans.every((span) => safe(span.range)), isTrue);
    expect(
      merged.semanticBlocks.map((block) => block.label),
      isNot(contains('unsafeBlock')),
    );
    expect(
      merged.inlayHints.map((hint) => hint.label),
      isNot(contains(': unsafe')),
    );
    expect(
      merged.documentSymbols.map((symbol) => symbol.name),
      isNot(contains('unsafeSymbol')),
    );
    expect(
      merged.referenceSpans.map((reference) => reference.name),
      isNot(contains('unsafeReference')),
    );
  });

  test(
    'capability detector observes fresh, empty, and stale capability states',
    () {
      const detector = StyioServiceCapabilityDetector();
      const document = DocumentState(
        documentId: 'fixture://capabilities',
        text: 'value = 1\nvalue\n',
        revision: 3,
      );
      const response = StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://capabilities',
        revision: 3,
        toolchainId: 'styio-nightly',
        completions: <CompletionItem>[
          CompletionItem(
            label: 'value',
            kind: CompletionItemKind.variable,
            insertText: 'value',
          ),
        ],
      );

      final snapshot = detector.detect(response, document: document);
      final stale = detector.detect(
        response,
        document: const DocumentState(
          documentId: 'fixture://capabilities',
          text: 'value = 1\nvalue\n',
          revision: 4,
        ),
      );

      expect(
        snapshot.stateOf(StyioServiceCapability.completion),
        StyioServiceCapabilityState.available,
      );
      expect(
        snapshot.stateOf(StyioServiceCapability.analysis),
        StyioServiceCapabilityState.available,
      );
      expect(
        snapshot.stateOf(StyioServiceCapability.syntax),
        StyioServiceCapabilityState.available,
      );
      expect(snapshot.toolchainId, 'styio-nightly');
      expect(
        snapshot.stateOf(StyioServiceCapability.hover),
        StyioServiceCapabilityState.empty,
      );
      expect(
        snapshot.capabilitiesWithFreshPayload,
        contains(StyioServiceCapability.completion),
      );
      expect(
        stale.stateOf(StyioServiceCapability.completion),
        StyioServiceCapabilityState.stale,
      );
    },
  );

  test('capability detector ignores unsafe service payload ranges', () {
    const detector = StyioServiceCapabilityDetector();
    const document = DocumentState(
      documentId: 'fixture://unsafe-capabilities',
      text: 'value\n',
      revision: 1,
    );
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://unsafe-capabilities',
      revision: 1,
      completions: <CompletionItem>[
        CompletionItem(
          label: 'unsafeCompletion',
          kind: CompletionItemKind.variable,
          insertText: 'unsafeCompletion',
          replacementRange: SourceRange(start: 0, end: 99),
        ),
      ],
      hovers: <HoverPayload>[
        HoverPayload(
          range: SourceRange(start: 0, end: 99),
          markdown: 'unsafe hover',
        ),
      ],
      semanticSpans: <SemanticSpan>[
        SemanticSpan(
          range: SourceRange(start: 0, end: 99),
          kind: SemanticKind.variable,
        ),
      ],
      documentSymbols: <DocumentSymbol>[
        DocumentSymbol(
          name: 'unsafeSymbol',
          kind: SymbolKind.variable,
          nameRange: SourceRange(start: 0, end: 99),
          declarationRange: SourceRange(start: 0, end: 99),
        ),
      ],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'unsafeReference',
          kind: SymbolKind.variable,
          range: SourceRange(start: 0, end: 99),
          targetRange: SourceRange(start: 0, end: 99),
        ),
      ],
    );

    final snapshot = detector.detect(
      response,
      document: document,
      expectedCapabilities: const <StyioServiceCapability>[
        StyioServiceCapability.completion,
        StyioServiceCapability.hover,
        StyioServiceCapability.semanticTokens,
        StyioServiceCapability.documentSymbols,
        StyioServiceCapability.references,
      ],
    );

    expect(
      snapshot.capabilitiesWithFreshPayload,
      isNot(contains(StyioServiceCapability.completion)),
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.completion),
      StyioServiceCapabilityState.empty,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.hover),
      StyioServiceCapabilityState.empty,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.semanticTokens),
      StyioServiceCapabilityState.empty,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.documentSymbols),
      StyioServiceCapabilityState.empty,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.references),
      StyioServiceCapabilityState.empty,
    );
  });

  test('capability detector uses report document for payload validation', () {
    const detector = StyioServiceCapabilityDetector();
    const document = DocumentState(
      documentId: 'fixture://report-document-capabilities',
      text: 'value\n',
      revision: 1,
    );
    const analysis = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[],
      referenceSpans: <ReferenceSpan>[],
    );
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://report-document-capabilities',
      revision: 1,
      hovers: <HoverPayload>[
        HoverPayload(
          range: SourceRange(start: 0, end: 5),
          markdown: 'value hover',
        ),
      ],
    );
    const report = StyioServiceAnalysisReport(
      documentId: 'fixture://report-document-capabilities',
      revision: 1,
      document: document,
      analysis: analysis,
      response: response,
      cachedResponseStored: false,
    );

    final snapshot = detector.detectReport(
      report,
      expectedCapabilities: const <StyioServiceCapability>[
        StyioServiceCapability.hover,
      ],
    );

    expect(
      snapshot.stateOf(StyioServiceCapability.hover),
      StyioServiceCapabilityState.available,
    );
  });

  test('capability detector does not mark empty edit plans available', () {
    const detector = StyioServiceCapabilityDetector();
    const document = DocumentState(
      documentId: 'fixture://empty-edit-capabilities',
      text: 'value\n',
      revision: 1,
    );
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://empty-edit-capabilities',
      revision: 1,
      codeActions: <DiagnosticQuickFix>[
        DiagnosticQuickFix(label: 'Empty action', edits: <FormattingEdit>[]),
      ],
    );

    final snapshot = detector.detect(
      response,
      document: document,
      expectedCapabilities: const <StyioServiceCapability>[
        StyioServiceCapability.codeActions,
      ],
    );
    final rawSnapshot = detector.detect(
      response,
      expectedCapabilities: const <StyioServiceCapability>[
        StyioServiceCapability.codeActions,
      ],
    );

    expect(
      snapshot.stateOf(StyioServiceCapability.codeActions),
      StyioServiceCapabilityState.empty,
    );
    expect(snapshot.capabilitiesWithFreshPayload, isEmpty);
    expect(
      rawSnapshot.stateOf(StyioServiceCapability.codeActions),
      StyioServiceCapabilityState.empty,
    );
    expect(rawSnapshot.capabilitiesWithFreshPayload, isEmpty);
  });

  test(
    'capability detector marks semantic fallback capabilities as derived',
    () {
      const detector = StyioServiceCapabilityDetector();
      const document = DocumentState(
        documentId: 'fixture://derived-capabilities',
        text: 'value := 1\nvalue\n',
        revision: 2,
      );
      const response = StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://derived-capabilities',
        revision: 2,
        documentSymbols: <DocumentSymbol>[
          DocumentSymbol(
            name: 'value',
            kind: SymbolKind.variable,
            nameRange: SourceRange(start: 0, end: 5),
            declarationRange: SourceRange(start: 0, end: 10),
          ),
        ],
        referenceSpans: <ReferenceSpan>[
          ReferenceSpan(
            name: 'value',
            kind: SymbolKind.variable,
            range: SourceRange(start: 0, end: 5),
            targetRange: SourceRange(start: 0, end: 9),
            isDeclaration: true,
            access: ReferenceAccess.declaration,
          ),
          ReferenceSpan(
            name: 'value',
            kind: SymbolKind.variable,
            range: SourceRange(start: 11, end: 16),
            targetRange: SourceRange(start: 0, end: 5),
          ),
        ],
      );

      final snapshot = detector.detect(response, document: document);

      expect(
        snapshot.stateOf(StyioServiceCapability.completion),
        StyioServiceCapabilityState.derived,
      );
      expect(
        snapshot.stateOf(StyioServiceCapability.hover),
        StyioServiceCapabilityState.derived,
      );
      expect(
        snapshot.stateOf(StyioServiceCapability.semanticTokens),
        StyioServiceCapabilityState.derived,
      );
      expect(
        snapshot.stateOf(StyioServiceCapability.rename),
        StyioServiceCapabilityState.derived,
      );
      expect(
        snapshot.stateOf(StyioServiceCapability.definition),
        StyioServiceCapabilityState.derived,
      );
      expect(
        snapshot.stateOf(StyioServiceCapability.documentSymbols),
        StyioServiceCapabilityState.available,
      );
      expect(
        snapshot.capabilitiesWithFreshPayload,
        isNot(contains(StyioServiceCapability.completion)),
      );
      expect(
        snapshot.capabilitiesWithUsableResult,
        contains(StyioServiceCapability.completion),
      );
      expect(
        snapshot.providerCapabilityWireValues(),
        contains(StyioServiceCapability.completion.wireValue),
      );
      expect(
        snapshot.providerCapabilityWireValues(),
        contains(StyioServiceCapability.semanticTokens.wireValue),
      );
      expect(
        snapshot.providerCapabilityWireValues(),
        contains(StyioServiceCapability.definition.wireValue),
      );
      expect(
        snapshot.providerCapabilityWireValues(includeDerived: false),
        isNot(contains(StyioServiceCapability.completion.wireValue)),
      );
      final descriptor = snapshot.providerDescriptor(
        languageId: 'styio',
        providerId: 'styio-service',
        displayName: 'StyioService',
        priority: 10,
      );
      expect(descriptor.languageId, 'styio');
      expect(descriptor.providerId, 'styio-service');
      expect(descriptor.priority, 10);
      expect(
        descriptor.capabilities,
        contains(StyioServiceCapability.completion.wireValue),
      );
      final registry = LanguageProviderRegistry<String>()
        ..register(
          snapshot.providerRegistration(
            languageId: 'styio',
            providerId: 'styio-service',
            displayName: 'StyioService',
            priority: 10,
            provider: 'styio-service-provider',
          ),
        );
      expect(
        registry.resolve(
          'styio',
          capability: StyioServiceCapability.completion.wireValue,
        ),
        'styio-service-provider',
      );
      expect(
        registry.resolve(
          'styio',
          capability: StyioServiceCapability.codeActions.wireValue,
        ),
        isNull,
      );
      final refreshingRegistry = LanguageProviderRegistry<String>();
      final registration = const StyioServiceCapabilityRegistrar<String>()
          .refresh(
            registry: refreshingRegistry,
            snapshot: snapshot,
            languageId: 'styio',
            providerId: 'styio-service',
            displayName: 'StyioService',
            priority: 20,
            provider: 'refreshed-provider',
          );
      expect(registration.descriptor.priority, 20);
      expect(
        refreshingRegistry.resolve(
          'styio',
          capability: StyioServiceCapability.hover.wireValue,
        ),
        'refreshed-provider',
      );
      expect(
        const StyioServiceCapabilityRegistrar<String>().unregister(
          registry: refreshingRegistry,
          languageId: 'styio',
          providerId: 'styio-service',
        ),
        isTrue,
      );
      const emptyAnalysis = StyioDocumentAnalysis(
        tokenSpans: <TokenSpan>[],
        semanticSpans: <SemanticSpan>[],
        diagnostics: <Diagnostic>[],
        formattingEdits: <FormattingEdit>[],
        semanticBlocks: <SemanticBlockRange>[],
        inlayHints: <InlayHint>[],
        documentSymbols: <DocumentSymbol>[],
        referenceSpans: <ReferenceSpan>[],
      );
      const report = StyioServiceAnalysisReport(
        documentId: 'fixture://derived-capabilities',
        revision: 2,
        analysis: emptyAnalysis,
        response: response,
        cachedResponseStored: true,
      );
      final reportRegistry = LanguageProviderRegistry<String>();
      const StyioServiceCapabilityRegistrar<String>().refreshFromReport(
        registry: reportRegistry,
        report: report,
        languageId: 'styio',
        providerId: 'styio-service',
        displayName: 'StyioService',
        provider: 'report-provider',
      );
      expect(
        reportRegistry.resolve(
          'styio',
          capability: StyioServiceCapability.rename.wireValue,
        ),
        'report-provider',
      );
      expect(snapshot.toJson()['statuses'], isA<List<Object?>>());
    },
  );

  test('capability detector respects explicit service capability states', () {
    const detector = StyioServiceCapabilityDetector();
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://explicit-capabilities',
      revision: 1,
      capabilityStates: <String, String>{
        'completion': 'available',
        'hover': 'unsupported',
        'semantic_tokens': 'empty',
        'codeActions': 'available',
      },
      capabilityMessages: <String, String>{
        'hover': 'hover facts are not emitted by this toolchain',
        'code_actions': 'code actions are available through camel case state',
      },
    );

    final snapshot = detector.detect(response);

    expect(
      snapshot.stateOf(StyioServiceCapability.completion),
      StyioServiceCapabilityState.available,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.hover),
      StyioServiceCapabilityState.unsupported,
    );
    expect(
      snapshot.statuses[StyioServiceCapability.hover]!.message,
      'hover facts are not emitted by this toolchain',
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.semanticTokens),
      StyioServiceCapabilityState.empty,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.codeActions),
      StyioServiceCapabilityState.available,
    );
    expect(
      snapshot.statuses[StyioServiceCapability.codeActions]!.message,
      'code actions are available through camel case state',
    );
    expect(
      snapshot.capabilitiesWithFreshPayload,
      contains(StyioServiceCapability.completion),
    );
    expect(
      snapshot.capabilitiesWithUsableResult,
      isNot(contains(StyioServiceCapability.hover)),
    );
  });

  test('capability detector maps explicit failure and stale state aliases', () {
    const detector = StyioServiceCapabilityDetector();
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://explicit-capability-aliases',
      revision: 1,
      capabilityStates: <String, String>{
        'completion': 'supported',
        'hover': 'unavailable',
        'semantic_tokens': 'derived',
        'code_actions': 'error',
        'rename': 'protocol-error',
        'safe_delete': 'protocolerror',
        'inline-variable': 'stale',
        'formatting': '  ',
      },
    );

    final snapshot = detector.detect(
      response,
      expectedCapabilities: const <StyioServiceCapability>[
        StyioServiceCapability.completion,
        StyioServiceCapability.hover,
        StyioServiceCapability.semanticTokens,
        StyioServiceCapability.codeActions,
        StyioServiceCapability.rename,
        StyioServiceCapability.safeDelete,
        StyioServiceCapability.inlineVariable,
        StyioServiceCapability.formatting,
      ],
    );

    expect(
      snapshot.stateOf(StyioServiceCapability.completion),
      StyioServiceCapabilityState.available,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.hover),
      StyioServiceCapabilityState.unavailable,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.semanticTokens),
      StyioServiceCapabilityState.derived,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.codeActions),
      StyioServiceCapabilityState.failed,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.rename),
      StyioServiceCapabilityState.protocolError,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.safeDelete),
      StyioServiceCapabilityState.protocolError,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.inlineVariable),
      StyioServiceCapabilityState.stale,
    );
    expect(
      snapshot.stateOf(StyioServiceCapability.formatting),
      StyioServiceCapabilityState.empty,
    );

    for (final status in const <StyioServiceStatus>[
      StyioServiceStatus.unavailable,
      StyioServiceStatus.failed,
      StyioServiceStatus.protocolError,
    ]) {
      final fallback = detector.detect(
        StyioServiceResponse(
          status: status,
          documentId: 'fixture://fallback-capability-status',
          revision: 1,
        ),
        expectedCapabilities: const <StyioServiceCapability>[
          StyioServiceCapability.hover,
        ],
      );
      expect(
        fallback.stateOf(StyioServiceCapability.hover),
        switch (status) {
          StyioServiceStatus.unavailable =>
            StyioServiceCapabilityState.unavailable,
          StyioServiceStatus.failed => StyioServiceCapabilityState.failed,
          StyioServiceStatus.protocolError =>
            StyioServiceCapabilityState.protocolError,
          StyioServiceStatus.succeeded => StyioServiceCapabilityState.empty,
          StyioServiceStatus.stale => StyioServiceCapabilityState.stale,
        },
      );
    }
  });

  test('capability detector marks safe refactor payloads available', () {
    const detector = StyioServiceCapabilityDetector();
    const document = DocumentState(
      documentId: 'fixture://safe-refactor-capabilities',
      text: 'value := 1\nvalue()\n',
      revision: 1,
    );
    const symbol = DocumentSymbol(
      name: 'value',
      kind: SymbolKind.function,
      nameRange: SourceRange(start: 0, end: 5),
      declarationRange: SourceRange(start: 0, end: 10),
    );
    const reference = ReferenceSpan(
      name: 'value',
      kind: SymbolKind.function,
      range: SourceRange(start: 11, end: 16),
      targetRange: SourceRange(start: 0, end: 5),
    );
    const edit = FormattingEdit(
      range: SourceRange(start: 11, end: 16),
      newText: 'nextValue',
    );
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://safe-refactor-capabilities',
      revision: 1,
      formattingEdits: <FormattingEdit>[
        FormattingEdit(range: SourceRange(start: 5, end: 5), newText: ' '),
      ],
      semanticBlocks: <SemanticBlockRange>[
        SemanticBlockRange(
          range: SourceRange(start: 0, end: 18),
          label: 'function-call',
        ),
      ],
      inlayHints: <InlayHint>[
        InlayHint(
          label: ': i64',
          kind: InlayHintKind.type,
          position: 5,
          range: SourceRange(start: 0, end: 5),
        ),
      ],
      definitionTargets: <DefinitionTarget>[
        DefinitionTarget(
          symbol: symbol,
          originRange: SourceRange(start: 11, end: 16),
        ),
      ],
      renamePlans: <RenamePlan>[
        RenamePlan(
          target: symbol,
          newName: 'nextValue',
          references: <ReferenceSpan>[reference],
          edits: <FormattingEdit>[edit],
        ),
      ],
      safeDeletePlans: <SafeDeletePlan>[
        SafeDeletePlan(
          target: symbol,
          references: <ReferenceSpan>[reference],
          edits: <FormattingEdit>[
            FormattingEdit(range: SourceRange(start: 0, end: 10), newText: ''),
          ],
        ),
      ],
      inlineVariablePlans: <InlineVariablePlan>[
        InlineVariablePlan(
          target: symbol,
          initializerRange: SourceRange(start: 9, end: 10),
          initializerText: '1',
          references: <ReferenceSpan>[reference],
          edits: <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 11, end: 16),
              newText: '1',
            ),
          ],
        ),
      ],
      introduceVariablePlans: <IntroduceVariablePlan>[
        IntroduceVariablePlan(
          variableName: 'nextValue',
          expressionRange: SourceRange(start: 11, end: 16),
          expressionText: 'value',
          edits: <FormattingEdit>[edit],
        ),
      ],
      extractFunctionPlans: <ExtractFunctionPlan>[
        ExtractFunctionPlan(
          functionName: 'extractValue',
          selectionRange: SourceRange(start: 11, end: 18),
          selectedText: 'value()',
          parameters: <String>[],
          callText: 'extractValue()',
          functionText: '#extractValue := () => value()\n',
          edits: <FormattingEdit>[edit],
        ),
      ],
      changeSignaturePlans: <ChangeSignaturePlan>[
        ChangeSignaturePlan(
          target: symbol,
          originalName: 'value',
          newName: 'nextValue',
          originalParameters: <ParameterInfoParameter>[
            ParameterInfoParameter(
              name: 'x',
              range: SourceRange(start: 16, end: 16),
            ),
          ],
          newParameters: <ChangeSignatureParameterUpdate>[
            ChangeSignatureParameterUpdate(originalName: 'x', name: 'nextX'),
          ],
          references: <ReferenceSpan>[reference],
          edits: <FormattingEdit>[edit],
        ),
      ],
      parameterInfos: <ParameterInfoPayload>[
        ParameterInfoPayload(
          callableName: 'value',
          signature: 'value(x: i64)',
          parameters: <ParameterInfoParameter>[
            ParameterInfoParameter(
              name: 'x',
              type: 'i64',
              range: SourceRange(start: 16, end: 16),
            ),
          ],
          activeParameterIndex: 0,
          invocationRange: SourceRange(start: 11, end: 18),
          callableRange: SourceRange(start: 11, end: 16),
        ),
      ],
    );
    const expected = <StyioServiceCapability>[
      StyioServiceCapability.formatting,
      StyioServiceCapability.semanticBlocks,
      StyioServiceCapability.inlayHints,
      StyioServiceCapability.definition,
      StyioServiceCapability.rename,
      StyioServiceCapability.safeDelete,
      StyioServiceCapability.inlineVariable,
      StyioServiceCapability.introduceVariable,
      StyioServiceCapability.extractFunction,
      StyioServiceCapability.changeSignature,
      StyioServiceCapability.parameterInfo,
    ];

    final snapshot = detector.detect(
      response,
      document: document,
      expectedCapabilities: expected,
    );
    final rawSnapshot = detector.detect(
      response,
      expectedCapabilities: expected,
    );

    for (final capability in expected) {
      expect(
        snapshot.stateOf(capability),
        StyioServiceCapabilityState.available,
        reason: capability.wireValue,
      );
      expect(
        rawSnapshot.stateOf(capability),
        StyioServiceCapabilityState.available,
        reason: 'raw ${capability.wireValue}',
      );
    }
  });

  test(
    'analysis driver keeps local analysis for stale Styio responses',
    () async {
      final driver = const StyioServiceAnalysisDriver(
        connector: _FakeStyioServiceConnector(
          StyioServiceResponse(
            status: StyioServiceStatus.succeeded,
            documentId: 'fixture://syntax',
            revision: 2,
            diagnostics: <StyioServiceDiagnosticDto>[
              StyioServiceDiagnosticDto(
                severity: DiagnosticSeverity.error,
                code: 'styio.stale',
                message: 'stale',
                range: SourceRange(start: 0, end: 1),
              ),
            ],
          ),
        ),
      );
      const document = DocumentState(
        documentId: 'fixture://syntax',
        text: '#main := () => {\n',
        revision: 3,
      );

      final analysis = await driver.analyzeDocument(document);

      expect(
        analysis.diagnostics.map((diagnostic) => diagnostic.code),
        isNot(contains('styio.stale')),
      );
      expect(
        analysis.diagnostics.map((diagnostic) => diagnostic.code),
        contains('local.unclosed-delimiter'),
      );
    },
  );

  test(
    'capability negotiator analyzes and refreshes provider registry',
    () async {
      final cache = StyioServiceResultCache();
      const document = DocumentState(
        documentId: 'fixture://negotiation',
        text: 'value := 1\nvalue\n',
        revision: 9,
      );
      final connector = _RecordingStyioServiceConnector(
        (_) => const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://negotiation',
          revision: 9,
          protocolVersion: 'styio-service-facts-v1',
          parserEngine: 'nightly',
          grammarVersion: '2026.05',
          documentSymbols: <DocumentSymbol>[
            DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 5),
              declarationRange: SourceRange(start: 0, end: 10),
            ),
          ],
          referenceSpans: <ReferenceSpan>[
            ReferenceSpan(
              name: 'value',
              kind: SymbolKind.variable,
              range: SourceRange(start: 0, end: 5),
              targetRange: SourceRange(start: 0, end: 5),
              isDeclaration: true,
              access: ReferenceAccess.declaration,
            ),
          ],
        ),
      );
      final driver = StyioServiceAnalysisDriver(
        connector: connector,
        resultCache: cache,
      );
      final registry = LanguageProviderRegistry<String>();

      final result = await StyioServiceCapabilityNegotiator<String>()
          .analyzeAndRefresh(
            driver: driver,
            document: document,
            registry: registry,
            languageId: 'styio',
            providerId: 'styio-service',
            displayName: 'StyioService',
            provider: 'negotiated-provider',
            priority: 30,
            filePath: '/workspace/main.styio',
            configPath: '/workspace/styio.toml',
            workingDirectory: '/workspace',
          );

      expect(result.report.cachedResponseStored, isTrue);
      final resultJson = result.toJson();
      final reportJson = resultJson['report']! as Map<String, Object?>;
      expect(connector.documents.single.filePath, '/workspace/main.styio');
      expect(connector.documents.single.configPath, '/workspace/styio.toml');
      expect(connector.documents.single.workingDirectory, '/workspace');
      expect(reportJson['protocolVersion'], 'styio-service-facts-v1');
      expect(reportJson['parserEngine'], 'nightly');
      expect(reportJson['grammarVersion'], '2026.05');
      expect(result.registration.descriptor.priority, 30);
      expect(
        registry.resolve(
          'styio',
          capability: StyioServiceCapability.rename.wireValue,
        ),
        'negotiated-provider',
      );
      expect(resultJson['registration'], isA<Map<String, Object?>>());
    },
  );

  test('capability session refreshes and unregisters provider', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_capability_session_manifest_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final datastore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    );
    addTearDown(datastore.close);
    final manifestStore = LanguageProviderRegistryManifestStore(
      owner: FoundationDataStoreOwner(
        descriptor: const FoundationDataStoreOwnerDescriptor(
          ownerId: 'service.language',
          layer: 'service',
          stateFamily: 'language-provider-registry',
          allowedNamespaces: <String>{'service.language.provider-registry'},
        ),
        dataStore: datastore,
      ),
    );
    const document = DocumentState(
      documentId: 'fixture://capability-session',
      text: 'value := 1\nvalue\n',
      revision: 10,
    );
    final driver = const StyioServiceAnalysisDriver(
      connector: _FakeStyioServiceConnector(
        StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://capability-session',
          revision: 10,
          documentSymbols: <DocumentSymbol>[
            DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 5),
              declarationRange: SourceRange(start: 0, end: 10),
            ),
          ],
          referenceSpans: <ReferenceSpan>[
            ReferenceSpan(
              name: 'value',
              kind: SymbolKind.variable,
              range: SourceRange(start: 0, end: 5),
              targetRange: SourceRange(start: 0, end: 5),
              isDeclaration: true,
              access: ReferenceAccess.declaration,
            ),
          ],
        ),
      ),
    );
    final registry = LanguageProviderRegistry<String>();
    final session = StyioServiceCapabilitySession<String>(
      driver: driver,
      registry: registry,
      languageId: 'styio',
      providerId: 'styio-service',
      displayName: 'StyioService',
      provider: 'session-provider',
      manifestStore: manifestStore,
      manifestKey: 'workspace-providers',
      manifestScope: FoundationResourceScope.workspace,
      manifestWorkspaceId: 'demo-workspace',
    );

    final result = await session.refresh(document);
    final manifest = await manifestStore.readManifest(
      key: 'workspace-providers',
      scope: FoundationResourceScope.workspace,
      workspaceId: 'demo-workspace',
    );

    expect(session.lastResult, result);
    expect(
      registry.resolve(
        'styio',
        capability: StyioServiceCapability.rename.wireValue,
      ),
      'session-provider',
    );
    expect(manifest, isNotNull);
    expect(manifest!.entries.single.providerId, 'styio-service');
    expect(
      manifest.entries.single.capabilities,
      contains(StyioServiceCapability.rename.wireValue),
    );
    expect(await session.dispose(), isTrue);
    expect(session.disposed, isTrue);
    expect(
      registry.resolve(
        'styio',
        capability: StyioServiceCapability.rename.wireValue,
      ),
      isNull,
    );
    expect(
      await manifestStore.readManifest(
        key: 'workspace-providers',
        scope: FoundationResourceScope.workspace,
        workspaceId: 'demo-workspace',
      ),
      isNull,
    );
    expect(() => session.refresh(document), throwsStateError);
  });

  test(
    'styio service runtime session refreshes provider and persists manifest',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_styio_runtime_session_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final datastore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      addTearDown(datastore.close);
      final manifestStore = LanguageProviderRegistryManifestStore(
        owner: FoundationDataStoreOwner(
          descriptor: const FoundationDataStoreOwnerDescriptor(
            ownerId: 'service.language',
            layer: 'service',
            stateFamily: 'language-provider-registry',
            allowedNamespaces: <String>{'service.language.provider-registry'},
          ),
          dataStore: datastore,
        ),
      );
      const document = DocumentState(
        documentId: 'fixture://runtime-session',
        text: 'value := 1\nvalue\n',
        revision: 11,
      );
      final connector = _RecordingStyioServiceConnector(
        (_) => const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://runtime-session',
          revision: 11,
          documentSymbols: <DocumentSymbol>[
            DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 5),
              declarationRange: SourceRange(start: 0, end: 10),
            ),
          ],
          referenceSpans: <ReferenceSpan>[
            ReferenceSpan(
              name: 'value',
              kind: SymbolKind.variable,
              range: SourceRange(start: 0, end: 5),
              targetRange: SourceRange(start: 0, end: 5),
              isDeclaration: true,
              access: ReferenceAccess.declaration,
            ),
          ],
        ),
      );
      final driver = StyioServiceAnalysisDriver(connector: connector);
      final registry = LanguageProviderRegistry<String>();
      final session = StyioServiceRuntimeSession<String>(
        driver: driver,
        registry: registry,
        languageId: 'styio',
        providerId: 'styio-service',
        displayName: 'StyioService',
        provider: 'runtime-provider',
        providerManifestStore: manifestStore,
        providerManifestKey: 'runtime-providers',
        providerManifestScope: FoundationResourceScope.workspace,
        providerManifestWorkspaceId: 'demo-workspace',
        allowLocalFallback: false,
      );
      final events = <StyioServiceRuntimeSessionEvent>[];
      final subscription = session.events.listen(events.add);
      addTearDown(subscription.cancel);

      final result = await session.refresh(
        document,
        filePath: '/workspace/runtime.styio',
        configPath: '/workspace/styio.toml',
        workingDirectory: '/workspace',
      );
      final manifest = await manifestStore.readManifest(
        key: 'runtime-providers',
        scope: FoundationResourceScope.workspace,
        workspaceId: 'demo-workspace',
      );

      expect(result.report.serviceSucceeded, isTrue);
      expect(connector.documents.single.filePath, '/workspace/runtime.styio');
      expect(connector.documents.single.configPath, '/workspace/styio.toml');
      expect(connector.documents.single.workingDirectory, '/workspace');
      expect(session.state, StyioServiceRuntimeSessionState.active);
      expect(session.toJson()['state'], 'active');
      expect(session.statusSnapshot.allowLocalFallback, isFalse);
      expect(
        session.statusSnapshot.stateOf(StyioServiceCapability.completion),
        StyioServiceCapabilityState.derived,
      );
      expect(
        session.statusSnapshot.primaryCapabilityStates,
        containsPair(
          StyioServiceCapability.completion.wireValue,
          StyioServiceCapabilityState.derived.name,
        ),
      );
      expect(session.statusSnapshot.usableCapabilityCount, greaterThan(0));
      expect(
        (session.toJson()['statusSnapshot'] as Map)['usableCapabilityCount'],
        greaterThan(0),
      );
      expect(
        (session.toJson()['statusSnapshot'] as Map)['allowLocalFallback'],
        isFalse,
      );
      expect(
        registry.resolve(
          'styio',
          capability: StyioServiceCapability.rename.wireValue,
        ),
        'runtime-provider',
      );
      expect(manifest, isNotNull);
      expect(manifest!.entries.single.providerId, 'styio-service');
      expect(await session.dispose(), isTrue);
      expect(session.disposed, isTrue);
      expect(
        events.map((event) => event.state),
        <StyioServiceRuntimeSessionState>[
          StyioServiceRuntimeSessionState.refreshing,
          StyioServiceRuntimeSessionState.active,
          StyioServiceRuntimeSessionState.disposed,
        ],
      );
      expect(
        events[1].statusSnapshot!.state,
        StyioServiceRuntimeSessionState.active,
      );
      expect(events[1].statusSnapshot!.allowLocalFallback, isFalse);
      expect(
        events[1].statusSnapshot!.primaryCapabilityStates,
        containsPair(
          StyioServiceCapability.hover.wireValue,
          StyioServiceCapabilityState.derived.name,
        ),
      );
      expect(events.last.statusSnapshot!.disposed, isTrue);
      expect(events.last.toJson()['state'], 'disposed');
      expect(
        await manifestStore.readManifest(
          key: 'runtime-providers',
          scope: FoundationResourceScope.workspace,
          workspaceId: 'demo-workspace',
        ),
        isNull,
      );
    },
  );

  test('cached language service merges fresh cached Styio diagnostics', () {
    final cache = StyioServiceResultCache();
    const document = DocumentState(
      documentId: 'fixture://syntax',
      text: '#main := () => {}',
      revision: 4,
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://syntax',
        revision: 4,
        diagnostics: <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.error,
            code: 'styio.cached',
            message: 'cached diagnostic',
            range: SourceRange(start: 1, end: 5),
          ),
        ],
      ),
    );
    final service = CachedStyioLanguageService(cache: cache);

    final analysis = service.analyzeDocument(document);

    expect(analysis.diagnostics, hasLength(1));
    expect(analysis.diagnostics.first.code, 'styio.cached');
  });

  test(
    'cached language service keeps local diagnostics when Styio fails empty',
    () {
      final cache = StyioServiceResultCache();
      final source = File(
        'test/fixtures/language_service/unclosed_delimiter.false.styio',
      ).readAsStringSync();
      final document = DocumentState(
        documentId: 'fixture://cached-failed-empty',
        text: source,
        revision: 1,
      );
      cache.store(
        const StyioServiceResponse(
          status: StyioServiceStatus.failed,
          documentId: 'fixture://cached-failed-empty',
          revision: 1,
          message: 'toolchain failed before diagnostics',
        ),
      );
      final service = CachedStyioLanguageService(cache: cache);

      final analysis = service.analyzeDocument(document);

      expect(
        analysis.diagnostics.map((diagnostic) => diagnostic.code),
        contains('local.unclosed-delimiter'),
      );
    },
  );

  test('editor refresh reads fresh cached Styio diagnostics', () {
    final cache = StyioServiceResultCache();
    const document = DocumentState(
      documentId: 'fixture://syntax',
      text: 'value = 1\nvalue\n',
      revision: 6,
    );
    final controller = EditorSessionController(
      initialDocument: document,
      languageService: CachedStyioLanguageService(cache: cache),
    );
    expect(controller.analysis.diagnostics, isEmpty);

    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://syntax',
        revision: 6,
        diagnostics: <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.error,
            code: 'styio.cached.refresh',
            message: 'cached diagnostic',
            range: SourceRange(start: 0, end: 5),
          ),
        ],
      ),
    );
    controller.refreshAnalysis();

    expect(controller.analysis.diagnostics, hasLength(1));
    expect(controller.analysis.diagnostics.first.code, 'styio.cached.refresh');
  });

  test('cached language service serves Styio facts when cached', () {
    final cache = StyioServiceResultCache();
    const document = DocumentState(
      documentId: 'fixture://facts',
      text: 'value = 1\nvalue\n',
      revision: 7,
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://facts',
        revision: 7,
        completions: <CompletionItem>[
          CompletionItem(
            label: 'serviceValue',
            kind: CompletionItemKind.variable,
            insertText: 'serviceValue',
          ),
        ],
        hovers: <HoverPayload>[
          HoverPayload(
            range: SourceRange(start: 10, end: 15),
            markdown: '**service value**',
          ),
        ],
        semanticSpans: <SemanticSpan>[
          SemanticSpan(
            range: SourceRange(start: 10, end: 15),
            kind: SemanticKind.variable,
          ),
        ],
        formattingEdits: <FormattingEdit>[
          FormattingEdit(range: SourceRange(start: 15, end: 15), newText: '\n'),
        ],
        semanticBlocks: <SemanticBlockRange>[
          SemanticBlockRange(
            range: SourceRange(start: 0, end: 15),
            label: 'main',
          ),
        ],
        inlayHints: <InlayHint>[
          InlayHint(
            label: ': i64',
            kind: InlayHintKind.type,
            position: 5,
            range: SourceRange(start: 0, end: 5),
          ),
        ],
        documentSymbols: <DocumentSymbol>[
          DocumentSymbol(
            name: 'value',
            kind: SymbolKind.variable,
            nameRange: SourceRange(start: 0, end: 5),
            declarationRange: SourceRange(start: 0, end: 9),
          ),
        ],
        referenceSpans: <ReferenceSpan>[
          ReferenceSpan(
            name: 'value',
            kind: SymbolKind.variable,
            range: SourceRange(start: 0, end: 5),
            targetRange: SourceRange(start: 0, end: 5),
            isDeclaration: true,
            access: ReferenceAccess.declaration,
          ),
          ReferenceSpan(
            name: 'value',
            kind: SymbolKind.variable,
            range: SourceRange(start: 10, end: 15),
            targetRange: SourceRange(start: 0, end: 5),
          ),
        ],
        codeActions: <DiagnosticQuickFix>[
          DiagnosticQuickFix(
            label: 'Replace cached value',
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 10, end: 15),
                newText: 'nextValue',
              ),
            ],
          ),
        ],
        renamePlans: <RenamePlan>[
          RenamePlan(
            target: DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 5),
              declarationRange: SourceRange(start: 0, end: 9),
            ),
            newName: 'nextValue',
            references: <ReferenceSpan>[
              ReferenceSpan(
                name: 'value',
                kind: SymbolKind.variable,
                range: SourceRange(start: 10, end: 15),
                targetRange: SourceRange(start: 0, end: 5),
              ),
            ],
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 10, end: 15),
                newText: 'nextValue',
              ),
            ],
          ),
        ],
        safeDeletePlans: <SafeDeletePlan>[
          SafeDeletePlan(
            target: DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 5),
              declarationRange: SourceRange(start: 0, end: 9),
            ),
            references: <ReferenceSpan>[
              ReferenceSpan(
                name: 'value',
                kind: SymbolKind.variable,
                range: SourceRange(start: 10, end: 15),
                targetRange: SourceRange(start: 0, end: 5),
              ),
            ],
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 0, end: 10),
                newText: '',
              ),
            ],
          ),
        ],
        inlineVariablePlans: <InlineVariablePlan>[
          InlineVariablePlan(
            target: DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 5),
              declarationRange: SourceRange(start: 0, end: 9),
            ),
            initializerRange: SourceRange(start: 8, end: 9),
            initializerText: '1',
            references: <ReferenceSpan>[
              ReferenceSpan(
                name: 'value',
                kind: SymbolKind.variable,
                range: SourceRange(start: 10, end: 15),
                targetRange: SourceRange(start: 0, end: 5),
              ),
            ],
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 10, end: 15),
                newText: '1',
              ),
            ],
          ),
        ],
        introduceVariablePlans: <IntroduceVariablePlan>[
          IntroduceVariablePlan(
            variableName: 'serviceVar',
            expressionRange: SourceRange(start: 10, end: 15),
            expressionText: 'value',
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 10, end: 15),
                newText: 'serviceVar',
              ),
            ],
          ),
        ],
        extractFunctionPlans: <ExtractFunctionPlan>[
          ExtractFunctionPlan(
            functionName: 'serviceFunction',
            selectionRange: SourceRange(start: 10, end: 15),
            selectedText: 'value',
            parameters: <String>['value'],
            callText: 'serviceFunction(value)',
            functionText: '#serviceFunction := () => {\n  value\n}\n',
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 10, end: 15),
                newText: 'serviceFunction(value)',
              ),
            ],
          ),
        ],
        changeSignaturePlans: <ChangeSignaturePlan>[
          ChangeSignaturePlan(
            target: DocumentSymbol(
              name: 'value',
              kind: SymbolKind.function,
              nameRange: SourceRange(start: 0, end: 5),
              declarationRange: SourceRange(start: 0, end: 9),
            ),
            originalName: 'value',
            newName: 'serviceValue',
            originalParameters: <ParameterInfoParameter>[
              ParameterInfoParameter(
                name: 'x',
                type: 'i64',
                range: SourceRange(start: 1, end: 2),
              ),
            ],
            newParameters: <ChangeSignatureParameterUpdate>[
              ChangeSignatureParameterUpdate(originalName: 'x', name: 'nextX'),
            ],
            references: <ReferenceSpan>[
              ReferenceSpan(
                name: 'value',
                kind: SymbolKind.function,
                range: SourceRange(start: 10, end: 15),
                targetRange: SourceRange(start: 0, end: 5),
              ),
            ],
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 10, end: 15),
                newText: 'serviceValue',
              ),
            ],
          ),
        ],
        parameterInfos: <ParameterInfoPayload>[
          ParameterInfoPayload(
            callableName: 'value',
            signature: 'value(x: i64)',
            parameters: <ParameterInfoParameter>[
              ParameterInfoParameter(
                name: 'x',
                type: 'i64',
                range: SourceRange(start: 11, end: 12),
              ),
            ],
            activeParameterIndex: 0,
            invocationRange: SourceRange(start: 10, end: 15),
            callableRange: SourceRange(start: 10, end: 15),
          ),
        ],
      ),
    );
    final service = CachedStyioLanguageService(cache: cache);

    final analysis = service.analyzeDocument(document);

    expect(analysis.semanticSpans.single.kind, SemanticKind.variable);
    expect(analysis.formattingEdits.single.newText, '\n');
    expect(analysis.semanticBlocks.single.label, 'main');
    expect(analysis.inlayHints.single.label, ': i64');
    expect(analysis.documentSymbols.single.name, 'value');
    expect(analysis.referenceSpans, hasLength(2));
    expect(service.completeAt(document, 10).single.label, 'serviceValue');
    expect(service.hoverAt(document, 12)?.markdown, '**service value**');
    expect(service.formatDocument(document).single.newText, '\n');
    expect(service.inlayHints(document).single.label, ': i64');
    expect(service.parameterInfoAt(document, 12)?.callableName, 'value');
    expect(service.definitionAt(document, 12)?.symbol.name, 'value');
    expect(service.referencesAt(document, 12), hasLength(2));
    expect(
      service.intentionsAt(document, 12).single.label,
      'Replace cached value',
    );
    expect(
      service
          .quickFixesForDiagnostic(
            document,
            const Diagnostic(
              severity: DiagnosticSeverity.error,
              code: 'styio.demo',
              message: 'demo',
              range: SourceRange(start: 10, end: 15),
            ),
          )
          .single
          .label,
      'Replace cached value',
    );
    expect(
      service.renameAt(document, 12, 'nextValue')?.edits.single.newText,
      'nextValue',
    );
    expect(service.safeDeleteAt(document, 12)?.edits.single.newText, '');
    expect(service.inlineVariableAt(document, 12)?.initializerText, '1');
    expect(
      service
          .introduceVariable(
            document,
            const SourceRange(start: 10, end: 15),
            'serviceVar',
          )
          ?.edits
          .single
          .newText,
      'serviceVar',
    );
    expect(
      service
          .extractFunction(
            document,
            const SourceRange(start: 10, end: 15),
            'serviceFunction',
          )
          ?.callText,
      'serviceFunction(value)',
    );
    expect(
      service
          .changeSignatureAt(
            document,
            12,
            newName: 'serviceValue',
            parameters: const <ChangeSignatureParameterUpdate>[
              ChangeSignatureParameterUpdate(originalName: 'x', name: 'nextX'),
            ],
          )
          ?.newParameters
          .single
          .name,
      'nextX',
    );
  });

  test('cached language service treats service ranges as half open', () {
    final cache = StyioServiceResultCache();
    const document = DocumentState(
      documentId: 'fixture://cached-range-boundary',
      text: 'value\n',
      revision: 1,
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://cached-range-boundary',
        revision: 1,
        hovers: <HoverPayload>[
          HoverPayload(
            range: SourceRange(start: 0, end: 5),
            markdown: '**service value**',
          ),
        ],
        codeActions: <DiagnosticQuickFix>[
          DiagnosticQuickFix(
            label: 'Replace service value',
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 0, end: 5),
                newText: 'nextValue',
              ),
            ],
          ),
        ],
      ),
    );
    final service = CachedStyioLanguageService(cache: cache);

    expect(service.hoverAt(document, 4)?.markdown, '**service value**');
    expect(service.hoverAt(document, 5), isNull);
    expect(
      service.intentionsAt(document, 4).single.label,
      'Replace service value',
    );
    expect(service.intentionsAt(document, 5), isEmpty);
  });

  test(
    'cached language service rejects stale cached revision for IDE features',
    () {
      final cache = StyioServiceResultCache();
      const document = DocumentState(
        documentId: 'fixture://stale-feature-guard',
        text: 'current = 2\ncurrent\n',
        revision: 8,
      );
      cache.store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://stale-feature-guard',
          revision: 7,
          diagnostics: <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.error,
              code: 'styio.stale.cached',
              message: 'stale diagnostic',
              range: SourceRange(start: 0, end: 7),
            ),
          ],
          completions: <CompletionItem>[
            CompletionItem(
              label: 'staleServiceValue',
              kind: CompletionItemKind.variable,
              insertText: 'staleServiceValue',
            ),
          ],
          hovers: <HoverPayload>[
            HoverPayload(
              range: SourceRange(start: 0, end: 7),
              markdown: '**stale hover**',
            ),
          ],
          semanticSpans: <SemanticSpan>[
            SemanticSpan(
              range: SourceRange(start: 99, end: 100),
              kind: SemanticKind.typeName,
            ),
          ],
          documentSymbols: <DocumentSymbol>[
            DocumentSymbol(
              name: 'staleSymbol',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 7),
              declarationRange: SourceRange(start: 0, end: 11),
            ),
          ],
          referenceSpans: <ReferenceSpan>[
            ReferenceSpan(
              name: 'staleSymbol',
              kind: SymbolKind.variable,
              range: SourceRange(start: 0, end: 7),
              targetRange: SourceRange(start: 0, end: 7),
              isDeclaration: true,
              access: ReferenceAccess.declaration,
            ),
            ReferenceSpan(
              name: 'staleSymbol',
              kind: SymbolKind.variable,
              range: SourceRange(start: 12, end: 19),
              targetRange: SourceRange(start: 0, end: 7),
            ),
          ],
          renamePlans: <RenamePlan>[
            RenamePlan(
              target: DocumentSymbol(
                name: 'staleSymbol',
                kind: SymbolKind.variable,
                nameRange: SourceRange(start: 0, end: 7),
                declarationRange: SourceRange(start: 0, end: 11),
              ),
              newName: 'nextStale',
              references: <ReferenceSpan>[
                ReferenceSpan(
                  name: 'staleSymbol',
                  kind: SymbolKind.variable,
                  range: SourceRange(start: 12, end: 19),
                  targetRange: SourceRange(start: 0, end: 7),
                ),
              ],
              edits: <FormattingEdit>[
                FormattingEdit(
                  range: SourceRange(start: 0, end: 7),
                  newText: 'nextStale',
                ),
              ],
            ),
          ],
        ),
      );
      final service = CachedStyioLanguageService(cache: cache);

      final analysis = service.analyzeDocument(document);
      final completions = service.completeAt(document, document.text.length);
      final hover = service.hoverAt(document, 1);
      final references = service.referencesAt(document, 1);
      final rename = service.renameAt(document, 1, 'nextStale');

      expect(
        analysis.diagnostics.map((diagnostic) => diagnostic.code),
        isNot(contains('styio.stale.cached')),
      );
      expect(
        analysis.semanticSpans.any(
          (span) =>
              span.range.start == 99 &&
              span.range.end == 100 &&
              span.kind == SemanticKind.typeName,
        ),
        isFalse,
      );
      expect(
        completions.map((completion) => completion.label),
        isNot(contains('staleServiceValue')),
      );
      expect(hover?.markdown, isNot('**stale hover**'));
      expect(
        references.map((reference) => reference.name),
        isNot(contains('staleSymbol')),
      );
      expect(rename?.target.name, isNot('staleSymbol'));
    },
  );

  test(
    'cached language service falls back when service code actions miss target',
    () {
      final cache = StyioServiceResultCache();
      const formatDocument = DocumentState(
        documentId: 'fixture://service-code-action-miss-format',
        text: 'value := 1  ',
        revision: 1,
      );
      final brokenSource = File(
        'test/fixtures/language_service/unclosed_delimiter.false.styio',
      ).readAsStringSync();
      final brokenDocument = DocumentState(
        documentId: 'fixture://service-code-action-miss-fix',
        text: brokenSource,
        revision: 1,
      );
      const unrelatedAction = DiagnosticQuickFix(
        label: 'Unrelated service action',
        edits: <FormattingEdit>[
          FormattingEdit(range: SourceRange(start: 0, end: 1), newText: 'x'),
        ],
      );
      cache.store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://service-code-action-miss-format',
          revision: 1,
          codeActions: <DiagnosticQuickFix>[unrelatedAction],
        ),
      );
      cache.store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://service-code-action-miss-fix',
          revision: 1,
          codeActions: <DiagnosticQuickFix>[unrelatedAction],
        ),
      );
      final service = CachedStyioLanguageService(cache: cache);
      final openingOffset = brokenSource.indexOf('{');
      final diagnostic = Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'local.unclosed-delimiter',
        message: 'Unclosed delimiter.',
        range: SourceRange(start: openingOffset, end: openingOffset + 1),
      );

      final intentions = service.intentionsAt(
        formatDocument,
        formatDocument.length,
      );
      final fixes = service.quickFixesForDiagnostic(brokenDocument, diagnostic);

      expect(intentions.single.label, 'Format document whitespace');
      expect(fixes.single.label, startsWith('Insert matching'));
    },
  );

  test(
    'cached language service falls back through Styio semantic snapshot',
    () {
      final cache = StyioServiceResultCache();
      const document = DocumentState(
        documentId: 'fixture://semantic-fallback',
        text: 'serviceValue\n',
        revision: 8,
      );
      cache.store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://semantic-fallback',
          revision: 8,
          documentSymbols: <DocumentSymbol>[
            DocumentSymbol(
              name: 'serviceValue',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 12),
              declarationRange: SourceRange(start: 0, end: 12),
              detail: 'StyioService binding',
            ),
          ],
          referenceSpans: <ReferenceSpan>[
            ReferenceSpan(
              name: 'serviceValue',
              kind: SymbolKind.variable,
              range: SourceRange(start: 0, end: 12),
              targetRange: SourceRange(start: 0, end: 12),
              isDeclaration: true,
              access: ReferenceAccess.declaration,
            ),
          ],
        ),
      );
      final service = CachedStyioLanguageService(cache: cache);

      final completions = service.completeAt(document, document.text.length);
      final hover = service.hoverAt(document, 1);
      final definition = service.definitionAt(document, 1);
      final references = service.referencesAt(document, 1);
      final rename = service.renameAt(document, 1, 'nextServiceValue');
      final safeDelete = service.safeDeleteAt(document, 1);
      final analysis = service.analyzeDocument(document);
      final changeSignature = service.changeSignatureAt(
        document,
        1,
        newName: 'nextServiceValue',
        parameters: const <ChangeSignatureParameterUpdate>[],
      );

      expect(completions.map((item) => item.label), contains('serviceValue'));
      expect(hover?.markdown, contains('serviceValue'));
      expect(hover?.markdown, contains('StyioService binding'));
      expect(analysis.semanticSpans.single.kind, SemanticKind.variable);
      expect(analysis.semanticSpans.single.range.start, 0);
      expect(analysis.semanticSpans.single.range.end, 12);
      expect(definition?.symbol.name, 'serviceValue');
      expect(references.single.name, 'serviceValue');
      expect(rename?.target.name, 'serviceValue');
      expect(rename?.edits.single.newText, 'nextServiceValue');
      expect(safeDelete?.target.name, 'serviceValue');
      expect(changeSignature?.target.name, 'serviceValue');
      expect(changeSignature?.edits.single.newText, 'nextServiceValue');
    },
  );

  test('cached language service respects empty service formatting result', () {
    final cache = StyioServiceResultCache();
    const document = DocumentState(
      documentId: 'fixture://empty-service-formatting',
      text: 'value',
      revision: 9,
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://empty-service-formatting',
        revision: 9,
        capabilityStates: <String, String>{'formatting': 'available'},
      ),
    );
    final service = CachedStyioLanguageService(cache: cache);

    final edits = service.formatDocument(document);

    expect(edits, isEmpty);
  });

  test(
    'cached language service respects empty available interaction payloads',
    () {
      final cache = StyioServiceResultCache();
      const document = DocumentState(
        documentId: 'fixture://empty-service-interactions',
        text: 'value := 41\nvalue\n',
        revision: 10,
      );
      cache.store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://empty-service-interactions',
          revision: 10,
          capabilityStates: <String, String>{
            'completion': 'available',
            'hover': 'available',
            'inlay-hints': 'available',
            'parameter-info': 'available',
            'references': 'available',
            'definition': 'available',
            'rename': 'available',
            'safe-delete': 'available',
            'inline-variable': 'available',
            'introduce-variable': 'available',
            'extract-function': 'available',
            'change-signature': 'available',
            'code-actions': 'available',
            'surround': 'available',
          },
        ),
      );
      final service = CachedStyioLanguageService(cache: cache);
      const diagnostic = Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'styio.empty',
        message: 'empty',
        range: SourceRange(start: 0, end: 5),
      );

      expect(service.completeAt(document, document.length), isEmpty);
      expect(service.hoverAt(document, 1), isNull);
      expect(service.inlayHints(document), isEmpty);
      expect(service.parameterInfoAt(document, 1), isNull);
      expect(service.referencesAt(document, 1), isEmpty);
      expect(service.definitionAt(document, 1), isNull);
      expect(service.renameAt(document, 1, 'nextValue'), isNull);
      expect(service.safeDeleteAt(document, 1), isNull);
      expect(service.inlineVariableAt(document, 13), isNull);
      expect(
        service.introduceVariable(
          document,
          const SourceRange(start: 9, end: 11),
          'nextValue',
        ),
        isNull,
      );
      expect(
        service.extractFunction(
          document,
          const SourceRange(start: 0, end: 11),
          'nextFunction',
        ),
        isNull,
      );
      expect(
        service.changeSignatureAt(
          document,
          1,
          newName: 'nextValue',
          parameters: const <ChangeSignatureParameterUpdate>[],
        ),
        isNull,
      );
      expect(service.intentionsAt(document, 1), isEmpty);
      expect(service.quickFixesForDiagnostic(document, diagnostic), isEmpty);
      expect(
        service.surroundTemplatesAt(
          document,
          const SourceRange(start: 0, end: 5),
        ),
        isEmpty,
      );
    },
  );

  test('cached language service returns service surround templates', () {
    final cache = StyioServiceResultCache();
    const document = DocumentState(
      documentId: 'fixture://service-surround',
      text: 'value',
      revision: 11,
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://service-surround',
        revision: 11,
        surroundTemplates: <SurroundTemplate>[
          SurroundTemplate(
            id: 'styio.service-surround',
            label: 'service surround',
            openingLine: 'service {',
            closingLine: '}',
            detail: 'Service-provided surround template.',
          ),
        ],
      ),
    );
    final service = CachedStyioLanguageService(cache: cache);

    final templates = service.surroundTemplatesAt(
      document,
      const SourceRange(start: 0, end: 5),
    );

    expect(templates, hasLength(1));
    expect(templates.single.id, 'styio.service-surround');
  });

  test('cached language service returns service definition targets', () {
    final cache = StyioServiceResultCache();
    const document = DocumentState(
      documentId: 'fixture://service-definition',
      text: 'value := 1\nvalue\n',
      revision: 12,
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://service-definition',
        revision: 12,
        definitionTargets: <DefinitionTarget>[
          DefinitionTarget(
            symbol: DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 5),
              declarationRange: SourceRange(start: 0, end: 10),
            ),
            originRange: SourceRange(start: 11, end: 16),
          ),
        ],
      ),
    );
    final service = CachedStyioLanguageService(cache: cache);

    final definition = service.definitionAt(document, 12);

    expect(definition?.symbol.name, 'value');
    expect(definition?.originRange.start, 11);
  });

  test('cached language service reports fallback sources per capability', () {
    final cache = StyioServiceResultCache();
    const document = DocumentState(
      documentId: 'fixture://fallback-snapshot',
      text: 'value := 1\nvalue\n',
      revision: 13,
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://fallback-snapshot',
        revision: 13,
        completions: <CompletionItem>[
          CompletionItem(
            label: 'value',
            kind: CompletionItemKind.variable,
            insertText: 'value',
          ),
        ],
        documentSymbols: <DocumentSymbol>[
          DocumentSymbol(
            name: 'value',
            kind: SymbolKind.variable,
            nameRange: SourceRange(start: 0, end: 5),
            declarationRange: SourceRange(start: 0, end: 10),
          ),
        ],
        referenceSpans: <ReferenceSpan>[
          ReferenceSpan(
            name: 'value',
            kind: SymbolKind.variable,
            range: SourceRange(start: 11, end: 16),
            targetRange: SourceRange(start: 0, end: 5),
          ),
        ],
        capabilityStates: <String, String>{'hover': 'available'},
      ),
    );
    final service = CachedStyioLanguageService(cache: cache);

    final snapshot = service.fallbackSnapshot(
      document,
      capabilities: const <StyioServiceCapability>[
        StyioServiceCapability.completion,
        StyioServiceCapability.hover,
        StyioServiceCapability.definition,
        StyioServiceCapability.surround,
      ],
    );
    final fullSnapshot = service.fallbackSnapshot(document);
    final missingSnapshot =
        CachedStyioLanguageService(
          cache: StyioServiceResultCache(),
        ).fallbackSnapshot(
          document,
          capabilities: const <StyioServiceCapability>[
            StyioServiceCapability.completion,
          ],
        );

    expect(
      snapshot.statusOf(StyioServiceCapability.completion),
      StyioServiceFallbackStatus.servicePayload,
    );
    expect(
      snapshot.statusOf(StyioServiceCapability.hover),
      StyioServiceFallbackStatus.serviceEmpty,
    );
    expect(
      snapshot.statusOf(StyioServiceCapability.definition),
      StyioServiceFallbackStatus.serviceDerived,
    );
    expect(
      snapshot.statusOf(StyioServiceCapability.surround),
      StyioServiceFallbackStatus.localFallback,
    );
    expect(
      snapshot.localFallbackCapabilities,
      contains(StyioServiceCapability.surround),
    );
    expect(
      missingSnapshot.statusOf(StyioServiceCapability.completion),
      StyioServiceFallbackStatus.noCachedResponse,
    );
    expect(
      fullSnapshot.entries.map((entry) => entry.capability).toSet(),
      StyioServiceCapability.values.toSet(),
    );
    expect(snapshot.toJson()['entries'], isA<List<Object?>>());
  });

  test('cached language service can disable local fallback', () {
    const document = DocumentState(
      documentId: 'fixture://strict-service',
      text: 'value := 1\nvalue\n',
      revision: 14,
    );
    final service = CachedStyioLanguageService(
      cache: StyioServiceResultCache(),
      allowLocalFallback: false,
    );

    final analysis = service.analyzeDocument(document);

    expect(analysis.documentSymbols, isEmpty);
    expect(service.completeAt(document, document.length), isEmpty);
    expect(service.hoverAt(document, 1), isNull);
    expect(service.referencesAt(document, 1), isEmpty);
    expect(service.renameAt(document, 1, 'nextValue'), isNull);
    expect(
      service.surroundTemplatesAt(
        document,
        const SourceRange(start: 0, end: 5),
      ),
      isEmpty,
    );
  });

  test('cached language service strict mode still uses service facts', () {
    final cache = StyioServiceResultCache();
    const document = DocumentState(
      documentId: 'fixture://strict-service-facts',
      text: 'value := 1\nvalue\n',
      revision: 15,
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://strict-service-facts',
        revision: 15,
        completions: <CompletionItem>[
          CompletionItem(
            label: 'serviceValue',
            kind: CompletionItemKind.variable,
            insertText: 'serviceValue',
          ),
        ],
        documentSymbols: <DocumentSymbol>[
          DocumentSymbol(
            name: 'value',
            kind: SymbolKind.variable,
            nameRange: SourceRange(start: 0, end: 5),
            declarationRange: SourceRange(start: 0, end: 10),
          ),
        ],
        referenceSpans: <ReferenceSpan>[
          ReferenceSpan(
            name: 'value',
            kind: SymbolKind.variable,
            range: SourceRange(start: 11, end: 16),
            targetRange: SourceRange(start: 0, end: 5),
            access: ReferenceAccess.read,
          ),
        ],
      ),
    );
    final service = CachedStyioLanguageService(
      cache: cache,
      allowLocalFallback: false,
    );

    final analysis = service.analyzeDocument(document);
    final definition = service.definitionAt(document, 12);
    final references = service.referencesAt(document, 12);

    expect(analysis.documentSymbols.single.name, 'value');
    expect(
      service.completeAt(document, document.length).single.label,
      'serviceValue',
    );
    expect(definition?.symbol.name, 'value');
    expect(references.map((reference) => reference.range.start), contains(11));
  });

  test(
    'cached language service derives definition from service references',
    () {
      final cache = StyioServiceResultCache();
      const document = DocumentState(
        documentId: 'fixture://reference-only-definition',
        text: 'abcde fghi\n',
        revision: 9,
      );
      cache.store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://reference-only-definition',
          revision: 9,
          referenceSpans: <ReferenceSpan>[
            ReferenceSpan(
              name: 'remoteValue',
              kind: SymbolKind.variable,
              range: SourceRange(start: 0, end: 5),
              targetRange: SourceRange(start: 6, end: 10),
              access: ReferenceAccess.read,
            ),
          ],
        ),
      );
      final service = CachedStyioLanguageService(cache: cache);

      final definition = service.definitionAt(document, 1);

      expect(definition?.symbol.name, 'remoteValue');
      expect(definition?.symbol.nameRange.start, 6);
      expect(definition?.symbol.nameRange.end, 10);
      expect(definition?.originRange.start, 0);
      expect(definition?.originRange.end, 5);
    },
  );

  test('cached language service renames from service references', () {
    final cache = StyioServiceResultCache();
    const document = DocumentState(
      documentId: 'fixture://reference-only-rename',
      text: 'abcde fghi\nabcde\n',
      revision: 10,
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://reference-only-rename',
        revision: 10,
        referenceSpans: <ReferenceSpan>[
          ReferenceSpan(
            name: 'remoteValue',
            kind: SymbolKind.variable,
            range: SourceRange(start: 0, end: 5),
            targetRange: SourceRange(start: 6, end: 10),
            access: ReferenceAccess.read,
          ),
          ReferenceSpan(
            name: 'remoteValue',
            kind: SymbolKind.variable,
            range: SourceRange(start: 11, end: 16),
            targetRange: SourceRange(start: 6, end: 10),
            access: ReferenceAccess.read,
          ),
        ],
      ),
    );
    final service = CachedStyioLanguageService(cache: cache);

    final rename = service.renameAt(document, 1, 'remoteNext');

    expect(rename?.target.name, 'remoteValue');
    expect(rename?.references, hasLength(2));
    expect(rename?.edits.map((edit) => edit.range.start), <int>[0, 11]);
    expect(rename?.edits.map((edit) => edit.newText), <String>[
      'remoteNext',
      'remoteNext',
    ]);
  });

  test('cached language service safe deletes from service references', () {
    final cache = StyioServiceResultCache();
    const conflictDocument = DocumentState(
      documentId: 'fixture://reference-only-safe-delete-conflict',
      text: 'abcde fghi\nabcde\n',
      revision: 11,
    );
    const deleteDocument = DocumentState(
      documentId: 'fixture://reference-only-safe-delete-edit',
      text: 'fghi\n',
      revision: 12,
    );
    cache
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://reference-only-safe-delete-conflict',
          revision: 11,
          referenceSpans: <ReferenceSpan>[
            ReferenceSpan(
              name: 'remoteValue',
              kind: SymbolKind.variable,
              range: SourceRange(start: 6, end: 10),
              targetRange: SourceRange(start: 6, end: 10),
              isDeclaration: true,
              access: ReferenceAccess.declaration,
            ),
            ReferenceSpan(
              name: 'remoteValue',
              kind: SymbolKind.variable,
              range: SourceRange(start: 0, end: 5),
              targetRange: SourceRange(start: 6, end: 10),
              access: ReferenceAccess.read,
            ),
          ],
        ),
      )
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://reference-only-safe-delete-edit',
          revision: 12,
          referenceSpans: <ReferenceSpan>[
            ReferenceSpan(
              name: 'remoteValue',
              kind: SymbolKind.variable,
              range: SourceRange(start: 0, end: 4),
              targetRange: SourceRange(start: 0, end: 4),
              isDeclaration: true,
              access: ReferenceAccess.declaration,
            ),
          ],
        ),
      );
    final service = CachedStyioLanguageService(cache: cache);

    final conflictPlan = service.safeDeleteAt(conflictDocument, 7);
    final deletePlan = service.safeDeleteAt(deleteDocument, 1);

    expect(conflictPlan?.target.name, 'remoteValue');
    expect(conflictPlan?.conflicts.single.range.start, 0);
    expect(conflictPlan?.edits, isEmpty);
    expect(deletePlan?.target.name, 'remoteValue');
    expect(deletePlan?.conflicts, isEmpty);
    expect(deletePlan?.edits.single.range.start, 0);
    expect(deletePlan?.edits.single.range.end, deleteDocument.text.length);
  });

  test('cached language service inlines from service references', () {
    final cache = StyioServiceResultCache();
    const document = DocumentState(
      documentId: 'fixture://reference-only-inline',
      text: 'abcde := 41\nabcde\n',
      revision: 13,
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://reference-only-inline',
        revision: 13,
        referenceSpans: <ReferenceSpan>[
          ReferenceSpan(
            name: 'remoteValue',
            kind: SymbolKind.variable,
            range: SourceRange(start: 0, end: 5),
            targetRange: SourceRange(start: 0, end: 5),
            isDeclaration: true,
            access: ReferenceAccess.declaration,
          ),
          ReferenceSpan(
            name: 'remoteValue',
            kind: SymbolKind.variable,
            range: SourceRange(start: 12, end: 17),
            targetRange: SourceRange(start: 0, end: 5),
            access: ReferenceAccess.read,
          ),
        ],
      ),
    );
    final service = CachedStyioLanguageService(cache: cache);

    final inline = service.inlineVariableAt(document, 12);

    expect(inline?.target.name, 'remoteValue');
    expect(inline?.initializerText, '41');
    expect(inline?.references.single.range.start, 12);
    expect(inline?.edits.first.newText, '41');
    expect(inline?.edits.last.range.start, 0);
    expect(inline?.edits.last.range.end, 12);
  });

  test(
    'cached language service derives declaration navigation from Styio symbols',
    () {
      final cache = StyioServiceResultCache();
      const document = DocumentState(
        documentId: 'fixture://semantic-declaration-navigation',
        text: 'serviceValue\nserviceValue\n',
        revision: 9,
      );
      cache.store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://semantic-declaration-navigation',
          revision: 9,
          documentSymbols: <DocumentSymbol>[
            DocumentSymbol(
              name: 'serviceValue',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 12),
              declarationRange: SourceRange(start: 0, end: 12),
              detail: 'StyioService binding',
            ),
          ],
          referenceSpans: <ReferenceSpan>[
            ReferenceSpan(
              name: 'serviceValue',
              kind: SymbolKind.variable,
              range: SourceRange(start: 13, end: 25),
              targetRange: SourceRange(start: 0, end: 12),
              access: ReferenceAccess.read,
            ),
          ],
        ),
      );
      final service = CachedStyioLanguageService(cache: cache);

      final definition = service.definitionAt(document, 1);
      final references = service.referencesAt(document, 1);
      final usageReferences = service.referencesAt(document, 14);
      final rename = service.renameAt(document, 1, 'nextValue');

      expect(definition?.symbol.name, 'serviceValue');
      expect(definition?.originRange.start, 0);
      expect(definition?.originRange.end, 12);
      expect(references, hasLength(2));
      expect(
        references.any(
          (reference) =>
              reference.range.start == 0 &&
              reference.range.end == 12 &&
              reference.isDeclaration,
        ),
        isTrue,
      );
      expect(
        references.any(
          (reference) =>
              reference.range.start == 13 &&
              reference.range.end == 25 &&
              reference.access == ReferenceAccess.read,
        ),
        isTrue,
      );
      expect(usageReferences, hasLength(2));
      expect(
        usageReferences.any(
          (reference) =>
              reference.range.start == 0 &&
              reference.range.end == 12 &&
              reference.isDeclaration,
        ),
        isTrue,
      );
      expect(
        usageReferences.any(
          (reference) =>
              reference.range.start == 13 &&
              reference.range.end == 25 &&
              reference.access == ReferenceAccess.read,
        ),
        isTrue,
      );
      expect(rename?.target.name, 'serviceValue');
      expect(rename?.edits, hasLength(2));
      expect(
        rename?.edits.any(
          (edit) =>
              edit.range.start == 0 &&
              edit.range.end == 12 &&
              edit.newText == 'nextValue',
        ),
        isTrue,
      );
      expect(
        rename?.edits.any(
          (edit) =>
              edit.range.start == 13 &&
              edit.range.end == 25 &&
              edit.newText == 'nextValue',
        ),
        isTrue,
      );
    },
  );

  test('analysis driver stores fresh Styio responses in cache', () async {
    final cache = StyioServiceResultCache();
    final driver = StyioServiceAnalysisDriver(
      connector: const _FakeStyioServiceConnector(
        StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://syntax',
          revision: 5,
          diagnostics: <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.error,
              code: 'styio.fresh',
              message: 'fresh',
              range: SourceRange(start: 0, end: 1),
            ),
          ],
        ),
      ),
      resultCache: cache,
    );
    const document = DocumentState(
      documentId: 'fixture://syntax',
      text: '#main := () => {}',
      revision: 5,
    );

    await driver.analyzeDocument(document);

    final response = cache.lookup(
      const StyioServiceResultCacheKey(
        documentId: 'fixture://syntax',
        revision: 5,
        protocolVersion: 'styio-cli-jsonl-v1',
      ),
    );
    expect(response?.diagnostics.first.code, 'styio.fresh');
  });

  test(
    'analysis driver forwards project config context to connector and cache',
    () async {
      final cache = StyioServiceResultCache();
      final connector = _RecordingStyioServiceConnector(
        (document) => StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: document.documentId,
          revision: document.revision,
          configPath: document.configPath,
          workingDirectory: document.workingDirectory,
          diagnostics: const <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.error,
              code: 'styio.config.forwarded',
              message: 'forwarded config',
              range: SourceRange(start: 0, end: 1),
            ),
          ],
        ),
      );
      final driver = StyioServiceAnalysisDriver(
        connector: connector,
        resultCache: cache,
      );
      const document = DocumentState(
        documentId: 'fixture://driver-config',
        text: '#main := () => {}',
        revision: 12,
      );

      final report = await driver.analyzeDocumentWithReport(
        document,
        filePath: '/workspace/src/main.styio',
        configPath: '/workspace/styio.toml',
        workingDirectory: '/workspace',
      );
      final cached = cache.lookupDocument(
        documentId: document.documentId,
        revision: document.revision,
        protocolVersion: 'styio-cli-jsonl-v1',
        configPath: '/workspace/styio.toml',
        workingDirectory: '/workspace',
      );

      expect(connector.documents.single.filePath, '/workspace/src/main.styio');
      expect(connector.documents.single.configPath, '/workspace/styio.toml');
      expect(connector.documents.single.workingDirectory, '/workspace');
      expect(report.response.configPath, '/workspace/styio.toml');
      expect(report.response.workingDirectory, '/workspace');
      expect(cached?.diagnostics.single.code, 'styio.config.forwarded');
    },
  );

  test(
    'analysis driver persists metadata manifest after caching fresh response',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_styio_service_driver_manifest_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final dataStore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final manifestStore = StyioServiceResultCacheManifestStore.fromDataStore(
        dataStore: dataStore,
      );
      final cache = StyioServiceResultCache();
      final driver = StyioServiceAnalysisDriver(
        connector: const _FakeStyioServiceConnector(
          StyioServiceResponse(
            status: StyioServiceStatus.succeeded,
            documentId: 'fixture://driver-manifest',
            revision: 8,
            toolchainId: 'styio-nightly',
            parserEngine: 'nightly',
            grammarVersion: '2026.05',
            diagnostics: <StyioServiceDiagnosticDto>[
              StyioServiceDiagnosticDto(
                severity: DiagnosticSeverity.error,
                code: 'styio.driver.raw',
                message: 'driver raw payload',
                range: SourceRange(start: 0, end: 1),
              ),
            ],
          ),
        ),
        resultCache: cache,
        resultCacheManifestStore: manifestStore,
      );
      const document = DocumentState(
        documentId: 'fixture://driver-manifest',
        text: '#main := () => {}',
        revision: 8,
      );

      await driver.analyzeDocument(document);
      final manifest = await manifestStore.load();
      final manifestText = manifest!.toJson().toString();

      expect(manifest.entries.single.documentId, 'fixture://driver-manifest');
      expect(manifest.entries.single.toolchainId, 'styio-nightly');
      expect(manifest.entries.single.parserEngine, 'nightly');
      expect(manifest.entries.single.grammarVersion, '2026.05');
      expect(manifest.entries.single.diagnosticCount, 1);
      expect(manifest.toJson().toString(), contains('grammarVersion'));
      expect(manifestText, isNot(contains('driver raw payload')));
      expect(manifestText, isNot(contains('styio.driver.raw')));
    },
  );

  test('analysis driver report exposes response and cache status', () async {
    final cache = StyioServiceResultCache();
    final driver = StyioServiceAnalysisDriver(
      connector: const _FakeStyioServiceConnector(
        StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://report',
          revision: 4,
          toolchainId: 'styio-nightly',
          diagnostics: <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.warning,
              code: 'styio.report',
              message: 'reported',
              range: SourceRange(start: 0, end: 1),
            ),
          ],
        ),
      ),
      resultCache: cache,
    );
    const document = DocumentState(
      documentId: 'fixture://report',
      text: 'value = 1\n',
      revision: 4,
    );

    final report = await driver.analyzeDocumentWithReport(document);

    expect(report.serviceSucceeded, isTrue);
    expect(report.cachedResponseStored, isTrue);
    expect(report.response.toolchainId, 'styio-nightly');
    expect(report.analysis.diagnostics.single.code, 'styio.report');
    expect(report.semanticSnapshot?.documentId, 'fixture://report');
    expect(report.semanticSnapshot?.revision, 4);
    expect(report.semanticSnapshot?.tokens, isNotEmpty);
    expect(report.cacheSnapshot?.entries.single.toolchainId, 'styio-nightly');

    final capabilities = const StyioServiceCapabilityDetector().detectReport(
      report,
    );
    expect(capabilities.toolchainId, 'styio-nightly');
    expect(
      capabilities.stateOf(StyioServiceCapability.diagnostics),
      StyioServiceCapabilityState.available,
    );
    expect(capabilities.toJson()['toolchainId'], 'styio-nightly');
    expect(
      capabilities.toJson()['statuses'],
      contains(
        containsPair(
          'capability',
          StyioServiceCapability.diagnostics.wireValue,
        ),
      ),
    );
  });

  test('result cache uses response toolchain identity by default', () {
    final cache = StyioServiceResultCache();
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://toolchain-cache',
        revision: 1,
        toolchainId: 'styio-nightly',
        diagnostics: <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.error,
            code: 'styio.cached.toolchain',
            message: 'cached',
            range: SourceRange(start: 0, end: 1),
          ),
        ],
      ),
    );

    expect(
      cache
          .lookup(
            const StyioServiceResultCacheKey(
              documentId: 'fixture://toolchain-cache',
              revision: 1,
              protocolVersion: 'styio-cli-jsonl-v1',
              toolchainId: 'styio-nightly',
            ),
          )
          ?.diagnostics
          .single
          .code,
      'styio.cached.toolchain',
    );
    expect(
      cache.lookup(
        const StyioServiceResultCacheKey(
          documentId: 'fixture://toolchain-cache',
          revision: 1,
          protocolVersion: 'styio-cli-jsonl-v1',
        ),
      ),
      isNull,
    );
  });

  test('result cache resolves unspecified toolchain only when unambiguous', () {
    final cache = StyioServiceResultCache();
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://unambiguous',
        revision: 1,
        toolchainId: 'styio-nightly',
        diagnostics: <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.warning,
            code: 'styio.unambiguous',
            message: 'cached',
            range: SourceRange(start: 0, end: 1),
          ),
        ],
      ),
    );
    cache
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://ambiguous',
          revision: 1,
          toolchainId: 'styio-nightly',
        ),
      )
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://ambiguous',
          revision: 1,
          toolchainId: 'styio-stable',
        ),
      );

    expect(
      cache
          .lookupDocument(
            documentId: 'fixture://unambiguous',
            revision: 1,
            protocolVersion: 'styio-cli-jsonl-v1',
          )
          ?.diagnostics
          .single
          .code,
      'styio.unambiguous',
    );
    expect(
      cache.lookupDocument(
        documentId: 'fixture://ambiguous',
        revision: 1,
        protocolVersion: 'styio-cli-jsonl-v1',
      ),
      isNull,
    );
  });

  test('result cache records lookup hit and miss telemetry', () {
    final cache = StyioServiceResultCache();
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://cache-telemetry',
        revision: 1,
        toolchainId: 'styio-nightly',
      ),
    );

    expect(
      cache.lookupDocument(
        documentId: 'fixture://cache-telemetry',
        revision: 1,
        protocolVersion: 'styio-cli-jsonl-v1',
      ),
      isNotNull,
    );
    expect(
      cache.lookup(
        const StyioServiceResultCacheKey(
          documentId: 'fixture://cache-telemetry',
          revision: 2,
          protocolVersion: 'styio-cli-jsonl-v1',
          toolchainId: 'styio-nightly',
        ),
      ),
      isNull,
    );

    expect(cache.lookupHits, 1);
    expect(cache.lookupMisses, 1);
    expect(cache.lookupCount, 2);
    expect(cache.lookupHitRate, 0.5);

    cache.resetTelemetry();

    expect(cache.lookupHits, 0);
    expect(cache.lookupMisses, 0);
    expect(cache.lookupCount, 0);
  });

  test('result cache snapshot exposes lookup telemetry metadata', () {
    final cache = StyioServiceResultCache();
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://cache-snapshot-telemetry',
        revision: 1,
        toolchainId: 'styio-nightly',
      ),
    );

    expect(
      cache.lookupDocument(
        documentId: 'fixture://cache-snapshot-telemetry',
        revision: 1,
        protocolVersion: 'styio-cli-jsonl-v1',
      ),
      isNotNull,
    );
    expect(
      cache.lookup(
        const StyioServiceResultCacheKey(
          documentId: 'fixture://cache-snapshot-telemetry',
          revision: 2,
          protocolVersion: 'styio-cli-jsonl-v1',
          toolchainId: 'styio-nightly',
        ),
      ),
      isNull,
    );

    final snapshot = cache.snapshot(
      documentId: 'fixture://cache-snapshot-telemetry',
    );
    final json = snapshot.toJson();
    final restored = StyioServiceResultCacheSnapshot.fromJson(json);
    final legacy = StyioServiceResultCacheSnapshot.fromJson(<String, Object?>{
      'entries': const <Object?>[],
    });

    expect(snapshot.entries, hasLength(1));
    expect(snapshot.lookupHits, 1);
    expect(snapshot.lookupMisses, 1);
    expect(snapshot.lookupCount, 2);
    expect(snapshot.lookupHitRate, 0.5);
    expect(json['lookupHits'], 1);
    expect(json['lookupMisses'], 1);
    expect(json['lookupCount'], 2);
    expect(json['lookupHitRate'], 0.5);
    expect(restored.lookupHits, 1);
    expect(restored.lookupMisses, 1);
    expect(restored.lookupCount, 2);
    expect(restored.lookupHitRate, 0.5);
    expect(legacy.lookupCount, 0);
    expect(legacy.lookupHitRate, 0);
  });

  test('result cache snapshot exposes manifest counts without payloads', () {
    final cache = StyioServiceResultCache();
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://manifest-b',
        revision: 2,
        protocolVersion: 'styio-cli-jsonl-v2',
        diagnostics: <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.error,
            code: 'styio.demo',
            message: 'demo diagnostic',
            range: SourceRange(start: 0, end: 1),
          ),
        ],
        completions: <CompletionItem>[
          CompletionItem(
            label: 'value',
            kind: CompletionItemKind.variable,
            insertText: 'value',
          ),
        ],
        hovers: <HoverPayload>[
          HoverPayload(
            range: SourceRange(start: 0, end: 1),
            markdown: '**value**',
          ),
        ],
        semanticSpans: <SemanticSpan>[
          SemanticSpan(
            range: SourceRange(start: 0, end: 1),
            kind: SemanticKind.variable,
          ),
        ],
        formattingEdits: <FormattingEdit>[
          FormattingEdit(range: SourceRange(start: 1, end: 1), newText: '\n'),
        ],
        semanticBlocks: <SemanticBlockRange>[
          SemanticBlockRange(
            range: SourceRange(start: 0, end: 1),
            label: 'main',
          ),
        ],
        inlayHints: <InlayHint>[
          InlayHint(
            label: ': i64',
            kind: InlayHintKind.type,
            position: 1,
            range: SourceRange(start: 0, end: 1),
          ),
        ],
        documentSymbols: <DocumentSymbol>[
          DocumentSymbol(
            name: 'value',
            kind: SymbolKind.variable,
            nameRange: SourceRange(start: 0, end: 1),
            declarationRange: SourceRange(start: 0, end: 1),
          ),
        ],
        referenceSpans: <ReferenceSpan>[
          ReferenceSpan(
            name: 'value',
            kind: SymbolKind.variable,
            range: SourceRange(start: 0, end: 1),
            targetRange: SourceRange(start: 0, end: 1),
          ),
        ],
        definitionTargets: <DefinitionTarget>[
          DefinitionTarget(
            symbol: DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 1),
              declarationRange: SourceRange(start: 0, end: 1),
            ),
            originRange: SourceRange(start: 0, end: 1),
          ),
        ],
        codeActions: <DiagnosticQuickFix>[
          DiagnosticQuickFix(label: 'Fix value', edits: <FormattingEdit>[]),
        ],
        renamePlans: <RenamePlan>[
          RenamePlan(
            target: DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 1),
              declarationRange: SourceRange(start: 0, end: 1),
            ),
            newName: 'nextValue',
            references: <ReferenceSpan>[],
            edits: <FormattingEdit>[],
          ),
        ],
        safeDeletePlans: <SafeDeletePlan>[
          SafeDeletePlan(
            target: DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 1),
              declarationRange: SourceRange(start: 0, end: 1),
            ),
            references: <ReferenceSpan>[],
            edits: <FormattingEdit>[],
          ),
        ],
        inlineVariablePlans: <InlineVariablePlan>[
          InlineVariablePlan(
            target: DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 1),
              declarationRange: SourceRange(start: 0, end: 1),
            ),
            initializerRange: SourceRange(start: 2, end: 3),
            initializerText: '1',
            references: <ReferenceSpan>[],
            edits: <FormattingEdit>[],
          ),
        ],
        introduceVariablePlans: <IntroduceVariablePlan>[
          IntroduceVariablePlan(
            variableName: 'nextValue',
            expressionRange: SourceRange(start: 0, end: 1),
            expressionText: 'value',
            edits: <FormattingEdit>[],
          ),
        ],
        extractFunctionPlans: <ExtractFunctionPlan>[
          ExtractFunctionPlan(
            functionName: 'readValue',
            selectionRange: SourceRange(start: 0, end: 1),
            selectedText: 'value',
            callText: 'readValue()',
            functionText: '#readValue := () => {\\n  value\\n}\\n',
            parameters: <String>[],
            edits: <FormattingEdit>[],
          ),
        ],
        changeSignaturePlans: <ChangeSignaturePlan>[
          ChangeSignaturePlan(
            target: DocumentSymbol(
              name: 'value',
              kind: SymbolKind.function,
              nameRange: SourceRange(start: 0, end: 1),
              declarationRange: SourceRange(start: 0, end: 1),
            ),
            originalName: 'value',
            newName: 'nextValue',
            originalParameters: <ParameterInfoParameter>[],
            newParameters: <ChangeSignatureParameterUpdate>[],
            references: <ReferenceSpan>[],
            edits: <FormattingEdit>[],
          ),
        ],
        parameterInfos: <ParameterInfoPayload>[
          ParameterInfoPayload(
            callableName: 'value',
            signature: 'value()',
            parameters: <ParameterInfoParameter>[],
            activeParameterIndex: 0,
            invocationRange: SourceRange(start: 0, end: 1),
            callableRange: SourceRange(start: 0, end: 1),
          ),
        ],
        surroundTemplates: <SurroundTemplate>[
          SurroundTemplate(
            id: 'styio.block',
            label: 'Block',
            openingLine: '{',
            closingLine: '}',
          ),
        ],
      ),
      toolchainId: 'toolchain-b',
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.failed,
        documentId: 'fixture://manifest-a',
        revision: 1,
        message: 'toolchain failed',
      ),
      toolchainId: 'toolchain-a',
    );

    final snapshot = cache.snapshot();
    final filtered = cache.snapshot(documentId: 'fixture://manifest-b');

    expect(snapshot.entries.map((entry) => entry.documentId), <String>[
      'fixture://manifest-a',
      'fixture://manifest-b',
    ]);
    expect(filtered.entries, hasLength(1));

    final failedJson = snapshot.entries.first.toJson();
    expect(failedJson['status'], 'failed');
    expect(failedJson['message'], 'toolchain failed');

    final manifestJson = filtered.entries.single.toJson();
    expect(manifestJson['toolchainId'], 'toolchain-b');
    expect(manifestJson['protocolVersion'], 'styio-cli-jsonl-v2');
    expect(manifestJson['diagnosticCount'], 1);
    expect(manifestJson['completionCount'], 1);
    expect(manifestJson['hoverCount'], 1);
    expect(manifestJson['semanticSpanCount'], 1);
    expect(manifestJson['formattingEditCount'], 1);
    expect(manifestJson['semanticBlockCount'], 1);
    expect(manifestJson['inlayHintCount'], 1);
    expect(manifestJson['documentSymbolCount'], 1);
    expect(manifestJson['referenceSpanCount'], 1);
    expect(manifestJson['definitionTargetCount'], 1);
    expect(manifestJson['codeActionCount'], 1);
    expect(manifestJson['renamePlanCount'], 1);
    expect(manifestJson['safeDeletePlanCount'], 1);
    expect(manifestJson['inlineVariablePlanCount'], 1);
    expect(manifestJson['introduceVariablePlanCount'], 1);
    expect(manifestJson['extractFunctionPlanCount'], 1);
    expect(manifestJson['changeSignaturePlanCount'], 1);
    expect(manifestJson['parameterInfoCount'], 1);
    expect(manifestJson['surroundTemplateCount'], 1);
    expect(manifestJson.containsKey('diagnostics'), isFalse);
    expect(manifestJson.containsKey('completions'), isFalse);
    expect(manifestJson.containsKey('hovers'), isFalse);
  });

  test('result cache separates project configuration contexts', () {
    final cache = StyioServiceResultCache()
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://configured-cache',
          revision: 1,
          toolchainId: 'styio-nightly',
          configPath: '/workspace-a/styio.toml',
          workingDirectory: '/workspace-a',
          diagnostics: <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.error,
              code: 'styio.config.a',
              message: 'config a',
              range: SourceRange(start: 0, end: 1),
            ),
          ],
        ),
      )
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://configured-cache',
          revision: 1,
          toolchainId: 'styio-nightly',
          configPath: '/workspace-b/styio.toml',
          workingDirectory: '/workspace-b',
          diagnostics: <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.error,
              code: 'styio.config.b',
              message: 'config b',
              range: SourceRange(start: 0, end: 1),
            ),
          ],
        ),
      );

    final ambiguous = cache.lookupDocument(
      documentId: 'fixture://configured-cache',
      revision: 1,
      protocolVersion: 'styio-cli-jsonl-v1',
      toolchainId: 'styio-nightly',
    );
    final configured = cache.lookupDocument(
      documentId: 'fixture://configured-cache',
      revision: 1,
      protocolVersion: 'styio-cli-jsonl-v1',
      toolchainId: 'styio-nightly',
      configPath: '/workspace-a/styio.toml',
      workingDirectory: '/workspace-a',
    );
    final snapshot = cache.snapshot(documentId: 'fixture://configured-cache');
    final restoredSnapshot = StyioServiceResultCacheSnapshot.fromJson(
      snapshot.toJson(),
    );

    expect(ambiguous, isNull);
    expect(configured?.diagnostics.single.code, 'styio.config.a');
    expect(snapshot.entries.map((entry) => entry.configPath), <String>[
      '/workspace-a/styio.toml',
      '/workspace-b/styio.toml',
    ]);
    expect(snapshot.entries.map((entry) => entry.workingDirectory), <String>[
      '/workspace-a',
      '/workspace-b',
    ]);
    expect(restoredSnapshot.entries.map((entry) => entry.configPath), <String>[
      '/workspace-a/styio.toml',
      '/workspace-b/styio.toml',
    ]);
    expect(
      restoredSnapshot.entries.map((entry) => entry.workingDirectory),
      <String>['/workspace-a', '/workspace-b'],
    );
    expect(
      cache.clearConfigurationContext(configPath: '/workspace-a/styio.toml'),
      1,
    );
    expect(
      cache.lookupDocument(
        documentId: 'fixture://configured-cache',
        revision: 1,
        protocolVersion: 'styio-cli-jsonl-v1',
        toolchainId: 'styio-nightly',
        configPath: '/workspace-a/styio.toml',
        workingDirectory: '/workspace-a',
      ),
      isNull,
    );
    expect(
      cache
          .lookupDocument(
            documentId: 'fixture://configured-cache',
            revision: 1,
            protocolVersion: 'styio-cli-jsonl-v1',
            toolchainId: 'styio-nightly',
            configPath: '/workspace-b/styio.toml',
            workingDirectory: '/workspace-b',
          )
          ?.diagnostics
          .single
          .code,
      'styio.config.b',
    );
  });

  test(
    'result cache manifest store persists metadata without payloads',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_styio_service_manifest_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final dataStore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final manifestStore = StyioServiceResultCacheManifestStore.fromDataStore(
        dataStore: dataStore,
      );
      final changes = <StyioServiceResultCacheManifestChange>[];
      final subscription = manifestStore.watch().listen(changes.add);
      addTearDown(subscription.cancel);
      final cache = StyioServiceResultCache()
        ..store(
          const StyioServiceResponse(
            status: StyioServiceStatus.succeeded,
            documentId: 'fixture://manifest',
            revision: 7,
            toolchainId: 'styio-nightly',
            diagnostics: <StyioServiceDiagnosticDto>[
              StyioServiceDiagnosticDto(
                severity: DiagnosticSeverity.error,
                code: 'styio.secret.payload',
                message: 'raw payload must not be persisted',
                range: SourceRange(start: 0, end: 1),
              ),
            ],
          ),
        );
      cache.lookupDocument(
        documentId: 'fixture://manifest',
        revision: 7,
        protocolVersion: 'styio-cli-jsonl-v1',
      );
      cache.lookupDocument(
        documentId: 'fixture://manifest-missing',
        revision: 1,
        protocolVersion: 'styio-cli-jsonl-v1',
      );

      await manifestStore.save(cache.snapshot());
      final loaded = await manifestStore.load();
      final jsonText = loaded!.toJson().toString();

      expect(loaded.entries.single.documentId, 'fixture://manifest');
      expect(loaded.entries.single.toolchainId, 'styio-nightly');
      expect(loaded.entries.single.diagnosticCount, 1);
      expect(loaded.lookupHits, 1);
      expect(loaded.lookupMisses, 1);
      expect(loaded.lookupCount, 2);
      expect(jsonText, isNot(contains('raw payload must not be persisted')));
      expect(jsonText, isNot(contains('styio.secret.payload')));
      expect(await manifestStore.delete(), isTrue);
      expect(await manifestStore.load(), isNull);
      expect(
        changes.map((change) => change.kind),
        <FoundationDataStoreChangeKind>[
          FoundationDataStoreChangeKind.written,
          FoundationDataStoreChangeKind.deleted,
        ],
      );
      expect(changes.first.snapshot!.entries.single.diagnosticCount, 1);
      expect(changes.last.snapshot, isNull);
    },
  );

  test(
    'result cache invalidates stale toolchain entries on catalog change',
    () {
      final cache = StyioServiceResultCache()
        ..store(
          const StyioServiceResponse(
            status: StyioServiceStatus.succeeded,
            documentId: 'fixture://main',
            revision: 1,
            toolchainId: 'styio-stable',
          ),
        )
        ..store(
          const StyioServiceResponse(
            status: StyioServiceStatus.succeeded,
            documentId: 'fixture://main',
            revision: 1,
            toolchainId: 'styio-nightly',
          ),
        );
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'styio-nightly',
            kind: ToolchainKind.languageService,
            displayName: 'Styio Nightly',
            executablePath: '/opt/styio/bin/styio',
          ),
          activate: true,
        );
      const key = StyioServiceResultCacheKey(
        documentId: 'fixture://main',
        revision: 1,
        protocolVersion: 'styio-cli-jsonl-v1',
        toolchainId: 'styio-stable',
      );
      const activeKey = StyioServiceResultCacheKey(
        documentId: 'fixture://main',
        revision: 1,
        protocolVersion: 'styio-cli-jsonl-v1',
        toolchainId: 'styio-nightly',
      );
      final invalidator = StyioServiceToolchainCacheInvalidator(cache: cache);

      final removed = invalidator.applyCatalogChange(
        ToolchainCatalogConfigurationChange(
          kind: ConfigurationSettingChangeKind.written,
          workspaceId: 'demo',
          catalog: catalog,
          emittedAt: DateTime.utc(2026, 5, 17),
        ),
      );

      expect(removed, 1);
      expect(cache.lookup(key), isNull);
      expect(cache.lookup(activeKey), isNotNull);

      final removedOnDelete = invalidator.applyCatalogChange(
        ToolchainCatalogConfigurationChange(
          kind: ConfigurationSettingChangeKind.deleted,
          workspaceId: 'demo',
          catalog: null,
          emittedAt: DateTime.utc(2026, 5, 17),
        ),
      );

      expect(removedOnDelete, 1);
      expect(cache.length, 0);
    },
  );

  test('result cache binding listens to toolchain catalog changes', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_styio_service_cache_binding_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final dataStore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    );
    final manifestStore = StyioServiceResultCacheManifestStore.fromDataStore(
      dataStore: dataStore,
    );
    final cache = StyioServiceResultCache()
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://main',
          revision: 1,
          toolchainId: 'styio-stable',
        ),
      )
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://main',
          revision: 1,
          toolchainId: 'styio-nightly',
        ),
      );
    await manifestStore.save(cache.snapshot());
    final catalogChanges =
        StreamController<ToolchainCatalogConfigurationChange>.broadcast(
          sync: true,
        );
    addTearDown(catalogChanges.close);
    final binding = StyioServiceToolchainCacheBinding.bind(
      cache: cache,
      catalogChanges: catalogChanges.stream,
      resultCacheManifestStore: manifestStore,
    );
    addTearDown(binding.dispose);
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'styio-nightly',
          kind: ToolchainKind.languageService,
          displayName: 'Styio Nightly',
          executablePath: '/opt/styio/bin/styio',
        ),
        activate: true,
      );

    catalogChanges.add(
      ToolchainCatalogConfigurationChange(
        kind: ConfigurationSettingChangeKind.written,
        workspaceId: 'demo',
        catalog: catalog,
        emittedAt: DateTime.utc(2026, 5, 17),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(cache.length, 1);
    expect(cache.snapshot().entries.single.toolchainId, 'styio-nightly');
    expect(
      (await manifestStore.load())!.entries.single.toolchainId,
      'styio-nightly',
    );

    catalogChanges.add(
      ToolchainCatalogConfigurationChange(
        kind: ConfigurationSettingChangeKind.deleted,
        workspaceId: 'demo',
        catalog: null,
        emittedAt: DateTime.utc(2026, 5, 17),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(cache.length, 0);
    expect(await manifestStore.load(), isNull);
  });

  test(
    'toolchain connector reports unavailable without active toolchain',
    () async {
      final catalog = ToolchainCatalog();
      final runtime = ToolchainRuntime(
        catalog: catalog,
        processManager: UnsupportedProcessManager(
          facts: ProcessFacts.linuxDebianArm(),
        ),
      );
      final connector = ToolchainStyioServiceConnector(runtime: runtime);

      final response = await connector.analyzeDocument(
        const StyioServiceDocument(
          documentId: 'fixture://syntax',
          text: '#main := () => {}',
          revision: 1,
          filePath: '/workspace/main.styio',
        ),
      );

      expect(response.status, StyioServiceStatus.unavailable);
      expect(response.message, contains('No language-service toolchain'));
    },
  );

  test(
    'toolchain connector requires matching Styio protocol contract',
    () async {
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'old-styio',
            kind: ToolchainKind.languageService,
            displayName: 'Old Styio',
            executablePath: '/usr/local/bin/styio',
            metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v0'},
          ),
          activate: true,
        );
      final runtime = ToolchainRuntime(
        catalog: catalog,
        processManager: UnsupportedProcessManager(
          facts: ProcessFacts.linuxDebianArm(),
        ),
      );
      final connector = ToolchainStyioServiceConnector(runtime: runtime);

      final response = await connector.analyzeDocument(
        const StyioServiceDocument(
          documentId: 'fixture://syntax',
          text: '#main := () => {}',
          revision: 1,
          filePath: '/workspace/main.styio',
        ),
      );

      expect(response.status, StyioServiceStatus.unavailable);
      expect(response.message, contains('metadata contract'));
    },
  );

  test(
    'toolchain connector passes project config and working directory',
    () async {
      final processManager = _RecordingProcessManager(
        stdout:
            '{"severity":"error","code":"styio.configured",'
            '"message":"configured diagnostic","range":{"start":1,"end":5}}\n',
      );
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'fake-styio',
            kind: ToolchainKind.languageService,
            displayName: 'Fake Styio',
            executablePath: '/usr/bin/fake-styio',
            metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
          ),
          activate: true,
        );
      final runtime = ToolchainRuntime(
        catalog: catalog,
        processManager: processManager,
      );
      final connector = ToolchainStyioServiceConnector(runtime: runtime);

      final response = await connector.analyzeDocument(
        const StyioServiceDocument(
          documentId: 'fixture://configured',
          text: '#main := () => {}',
          revision: 1,
          filePath: '/workspace/src/main.styio',
          configPath: '/workspace/styio.toml',
          workingDirectory: '/workspace',
        ),
      );
      final request = processManager.requests.single;

      expect(response.status, StyioServiceStatus.succeeded);
      expect(response.diagnostics.single.code, 'styio.configured');
      expect(request.workingDirectory, '/workspace');
      expect(
        request.arguments,
        containsAllInOrder(<String>[
          '--config',
          '/workspace/styio.toml',
          '--file',
          '/workspace/src/main.styio',
        ]),
      );
    },
  );

  test(
    'toolchain connector reports unavailable for unsaved documents without materializer',
    () async {
      final processManager = _RecordingProcessManager();
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'fake-styio',
            kind: ToolchainKind.languageService,
            displayName: 'Fake Styio',
            executablePath: '/usr/bin/fake-styio',
            metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
          ),
          activate: true,
        );
      final runtime = ToolchainRuntime(
        catalog: catalog,
        processManager: processManager,
      );
      final connector = ToolchainStyioServiceConnector(runtime: runtime);
      const document = StyioServiceDocument(
        documentId: 'fixture://unsaved-stdin',
        text: '#main := () => {}',
        revision: 1,
      );

      final response = await connector.analyzeDocument(document);

      expect(response.status, StyioServiceStatus.unavailable);
      expect(response.message, contains('file path or materializer'));
      expect(processManager.requests, isEmpty);
    },
  );

  test(
    'toolchain connector materializes unsaved documents through file managers',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_styio_materializer_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final processManager = _RecordingProcessManager(
        stdout:
            '{"severity":"error","code":"styio.materialized",'
            '"message":"materialized diagnostic",'
            '"range":{"start":1,"end":5}}\n',
      );
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'fake-styio',
            kind: ToolchainKind.languageService,
            displayName: 'Fake Styio',
            executablePath: '/usr/bin/fake-styio',
            metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
          ),
          activate: true,
        );
      final runtime = ToolchainRuntime(
        catalog: catalog,
        processManager: processManager,
      );
      final connector = ToolchainStyioServiceConnector(
        runtime: runtime,
        documentMaterializer: StyioServiceDocumentMaterializer(
          fileSystemManager: LocalFileSystemManager.linuxDebianArmForTest(),
          resourceManager: LocalResourceManager(
            facts: ResourceFacts.linuxDebianArm(
              systemTempPath: tempRoot.path,
              homePath: tempRoot.path,
            ),
          ),
        ),
      );
      const document = StyioServiceDocument(
        documentId: 'fixture://unsaved-materialized',
        text: '#main := () => {}',
        revision: 1,
        configPath: '/workspace/styio.toml',
        workingDirectory: '/workspace',
      );

      final response = await connector.analyzeDocument(document);
      final request = processManager.requests.single;
      final filePath = processManager.materializedFilePath!;

      expect(response.status, StyioServiceStatus.succeeded);
      expect(response.diagnostics.single.code, 'styio.materialized');
      expect(request.standardInput, isNull);
      expect(request.workingDirectory, '/workspace');
      expect(
        request.arguments,
        containsAllInOrder(<String>['--config', '/workspace/styio.toml']),
      );
      expect(request.arguments, contains('--file'));
      expect(processManager.materializedFileContents, document.text);
      expect(File(filePath).existsSync(), isFalse);
    },
  );

  test(
    'toolchain manager connector materializes unsaved documents by default',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_styio_manager_materializer_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );
      final baseManagers = await createDetectedPlatformManagerBundle();
      final processManager = _RecordingProcessManager(
        stdout:
            '{"severity":"error","code":"styio.manager.materialized",'
            '"message":"manager materialized diagnostic",'
            '"range":{"start":1,"end":5}}\n',
      );
      final platformManagers = PlatformManagerBundle(
        context: baseManagers.context,
        compatibility: baseManagers.compatibility,
        fileSystem: baseManagers.fileSystem,
        shell: baseManagers.shell,
        process: processManager,
        resource: LocalResourceManager(
          facts: ResourceFacts.linuxDebianArm(
            systemTempPath: tempRoot.path,
            homePath: tempRoot.path,
            targetId: baseManagers.context.targetId,
          ),
        ),
        network: baseManagers.network,
        clipboard: baseManagers.clipboard,
        notification: baseManagers.notification,
        localService: baseManagers.localService,
        pty: baseManagers.pty,
      );
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'fake-styio',
            kind: ToolchainKind.languageService,
            displayName: 'Fake Styio',
            executablePath: '/usr/bin/fake-styio',
            metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
          ),
          activate: true,
        );
      await toolchainStore.saveCatalog(
        catalog,
        targetId: platformManagers.context.targetId,
      );
      final manager = ToolchainManager(
        configurationStore: toolchainStore,
        platformManagers: platformManagers,
      );
      final connector = ToolchainManagerStyioServiceConnector(manager: manager);
      const document = StyioServiceDocument(
        documentId: 'fixture://manager-unsaved-materialized',
        text: '#main := () => {}',
        revision: 1,
      );

      final response = await connector.analyzeDocument(document);
      final filePath = processManager.materializedFilePath!;

      expect(response.status, StyioServiceStatus.succeeded);
      expect(response.diagnostics.single.code, 'styio.manager.materialized');
      expect(processManager.requests.single.arguments, contains('--file'));
      expect(processManager.materializedFileContents, document.text);
      expect(File(filePath).existsSync(), isFalse);
    },
  );

  test(
    'platform Styio service analysis driver uses provided toolchain manager',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_styio_platform_driver_manager_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );
      final baseManagers = await createDetectedPlatformManagerBundle();
      final processManager = _RecordingProcessManager(
        stdout:
            '{"severity":"error","code":"styio.driver.manager",'
            '"message":"driver manager diagnostic",'
            '"range":{"start":1,"end":5}}\n',
      );
      final platformManagers = PlatformManagerBundle(
        context: baseManagers.context,
        compatibility: baseManagers.compatibility,
        fileSystem: baseManagers.fileSystem,
        shell: baseManagers.shell,
        process: processManager,
        resource: LocalResourceManager(
          facts: ResourceFacts.linuxDebianArm(
            systemTempPath: tempRoot.path,
            homePath: tempRoot.path,
            targetId: baseManagers.context.targetId,
          ),
        ),
        network: baseManagers.network,
        clipboard: baseManagers.clipboard,
        notification: baseManagers.notification,
        localService: baseManagers.localService,
        pty: baseManagers.pty,
      );
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'fake-styio',
            kind: ToolchainKind.languageService,
            displayName: 'Fake Styio',
            executablePath: '/usr/bin/fake-styio',
            metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
          ),
          activate: true,
        );
      await toolchainStore.saveCatalog(
        catalog,
        targetId: platformManagers.context.targetId,
      );
      final manager = ToolchainManager(
        configurationStore: toolchainStore,
        platformManagers: platformManagers,
      );
      final resultCache = StyioServiceResultCache();
      final driver = await createPlatformStyioServiceAnalysisDriver(
        resultCache: resultCache,
        toolchainManager: manager,
      );
      const document = DocumentState(
        documentId: 'fixture://platform-driver-manager',
        text: '#main := () => {}',
        revision: 1,
      );

      final report = await driver.analyzeDocumentWithReport(document);

      expect(report.response.status, StyioServiceStatus.succeeded);
      expect(report.analysis.diagnostics.single.code, 'styio.driver.manager');
      expect(processManager.requests.single.arguments, contains('--file'));
      expect(processManager.materializedFileContents, document.text);
    },
  );

  test('cached language service filters unsafe service code actions', () {
    const document = DocumentState(
      documentId: 'fixture://unsafe-code-action',
      text: 'value\n',
      revision: 1,
    );
    final cache = StyioServiceResultCache()
      ..store(
        const StyioCliJsonlProtocol().decode(
          document: StyioServiceDocument.fromDocumentState(document),
          stdout: [
            '{"record":"diagnostic","diagnostic":{"severity":"warning",'
                '"code":"styio.demo","message":"demo",'
                '"range":{"start":0,"end":1}}}',
            '{"record":"codeAction","codeAction":{'
                '"label":"Unsafe service edit",'
                '"edits":[{"start":0,"end":99,'
                '"newText":"serviceBad"}]}}',
            '{"record":"codeAction","codeAction":{'
                '"label":"Empty service edit","edits":[]}}',
          ].join('\n'),
          stderr: '',
          exitCode: 0,
          toolchainSucceeded: true,
        ),
      );
    final service = CachedStyioLanguageService(cache: cache);

    final intentionLabels = service
        .intentionsAt(document, 0)
        .map((action) => action.label);
    final diagnostic = service.analyzeDocument(document).diagnostics.single;
    final quickFixLabels = service
        .quickFixesForDiagnostic(document, diagnostic)
        .map((fix) => fix.label);

    expect(intentionLabels, isNot(contains('Unsafe service edit')));
    expect(quickFixLabels, isNot(contains('Unsafe service edit')));
    expect(intentionLabels, isNot(contains('Empty service edit')));
    expect(quickFixLabels, isNot(contains('Empty service edit')));
  });

  test('cached language service filters unsafe service UI payload ranges', () {
    const document = DocumentState(
      documentId: 'fixture://unsafe-ui-payloads',
      text: 'value+1\n',
      revision: 1,
    );
    final cache = StyioServiceResultCache()
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://unsafe-ui-payloads',
          revision: 1,
          completions: <CompletionItem>[
            CompletionItem(
              label: 'unsafeCompletion',
              kind: CompletionItemKind.variable,
              insertText: 'unsafeCompletion',
              replacementRange: SourceRange(start: 0, end: 99),
            ),
          ],
          hovers: <HoverPayload>[
            HoverPayload(
              range: SourceRange(start: -1, end: 99),
              markdown: 'Unsafe service hover',
            ),
          ],
          inlayHints: <InlayHint>[
            InlayHint(
              label: ': unsafe',
              kind: InlayHintKind.type,
              position: 99,
              range: SourceRange(start: 0, end: 99),
            ),
          ],
          parameterInfos: <ParameterInfoPayload>[
            ParameterInfoPayload(
              callableName: 'unsafe',
              signature: 'unsafe(value)',
              parameters: <ParameterInfoParameter>[
                ParameterInfoParameter(
                  name: 'value',
                  range: SourceRange(start: 0, end: 99),
                ),
              ],
              activeParameterIndex: 0,
              invocationRange: SourceRange(start: 0, end: 99),
              callableRange: SourceRange(start: 0, end: 99),
            ),
          ],
        ),
      );
    final service = CachedStyioLanguageService(cache: cache);

    expect(
      service.completeAt(document, 0).map((item) => item.label),
      isNot(contains('unsafeCompletion')),
    );
    expect(
      service.hoverAt(document, 0)?.markdown,
      isNot('Unsafe service hover'),
    );
    expect(
      service.inlayHints(document).map((hint) => hint.label),
      isNot(contains(': unsafe')),
    );
    expect(
      service.parameterInfoAt(document, 0)?.signature,
      isNot('unsafe(value)'),
    );
  });

  test('cached language service filters unsafe service edit plans', () {
    const document = DocumentState(
      documentId: 'fixture://unsafe-edit-plans',
      text: 'value = 1\nvalue\n',
      revision: 1,
    );
    final cache = StyioServiceResultCache()
      ..store(
        const StyioCliJsonlProtocol().decode(
          document: StyioServiceDocument.fromDocumentState(document),
          stdout: [
            '{"record":"formattingEdit","formattingEdit":{'
                '"start":0,"end":99,"newText":"serviceBad"}}',
            '{"record":"symbol","symbol":{"name":"value",'
                '"kind":"variable","nameRange":{"start":0,"end":5},'
                '"declarationRange":{"start":0,"end":9}}}',
            '{"record":"reference","reference":{"name":"value",'
                '"kind":"variable","range":{"start":10,"end":15},'
                '"targetRange":{"start":0,"end":5},"access":"read"}}',
            '{"record":"rename","rename":{"newName":"nextValue",'
                '"target":{"name":"value","kind":"variable",'
                '"nameRange":{"start":0,"end":5},'
                '"declarationRange":{"start":0,"end":9}},'
                '"references":[{"name":"value","kind":"variable",'
                '"range":{"start":10,"end":15},'
                '"targetRange":{"start":0,"end":5}}],'
                '"edits":[{"start":0,"end":99,'
                '"newText":"serviceBad"}],"conflicts":[]}}',
            '{"record":"safeDelete","safeDelete":{"target":{"name":"value",'
                '"kind":"variable","nameRange":{"start":0,"end":5},'
                '"declarationRange":{"start":0,"end":9}},'
                '"references":[{"name":"value","kind":"variable",'
                '"range":{"start":10,"end":15},'
                '"targetRange":{"start":0,"end":5}}],'
                '"edits":[{"start":0,"end":99,'
                '"newText":"serviceBad"}],"conflicts":[]}}',
            '{"record":"inlineVariable","inlineVariable":{'
                '"target":{"name":"value","kind":"variable",'
                '"nameRange":{"start":0,"end":5},'
                '"declarationRange":{"start":0,"end":9}},'
                '"initializerRange":{"start":8,"end":9},'
                '"initializerText":"1",'
                '"references":[{"name":"value","kind":"variable",'
                '"range":{"start":10,"end":15},'
                '"targetRange":{"start":0,"end":5}}],'
                '"edits":[{"start":0,"end":99,'
                '"newText":"serviceBad"}],"conflicts":[]}}',
            '{"record":"introduceVariable","introduceVariable":{'
                '"variableName":"nextValue",'
                '"expressionRange":{"start":10,"end":15},'
                '"expressionText":"value",'
                '"edits":[{"start":0,"end":99,'
                '"newText":"serviceBad"}],"conflicts":[]}}',
            '{"record":"extractFunction","extractFunction":{'
                '"functionName":"readValue",'
                '"selectionRange":{"start":10,"end":15},'
                '"selectedText":"value","parameters":["value"],'
                '"callText":"readValue(value)",'
                '"functionText":"#readValue := () => {\\n  value\\n}\\n",'
                '"edits":[{"start":0,"end":99,'
                '"newText":"serviceBad"}],'
                '"duplicateOccurrences":[{"start":10,"end":15}],'
                '"conflicts":[]}}',
            '{"record":"changeSignature","changeSignature":{'
                '"target":{"name":"value","kind":"function",'
                '"nameRange":{"start":0,"end":5},'
                '"declarationRange":{"start":0,"end":9}},'
                '"originalName":"value","newName":"nextValue",'
                '"originalParameters":[{"name":"x","type":"i64",'
                '"start":1,"end":2}],'
                '"newParameters":[{"originalName":"x","name":"nextX"}],'
                '"references":[{"name":"value","kind":"function",'
                '"range":{"start":10,"end":15},'
                '"targetRange":{"start":0,"end":5}}],'
                '"edits":[{"start":0,"end":99,'
                '"newText":"serviceBad"}],"conflicts":[]}}',
          ].join('\n'),
          stderr: '',
          exitCode: 0,
          toolchainSucceeded: true,
        ),
      );
    final service = CachedStyioLanguageService(cache: cache);

    bool hasUnsafeServiceEdit(List<FormattingEdit> edits) {
      return edits.any(
        (edit) =>
            edit.newText == 'serviceBad' || edit.range.end > document.length,
      );
    }

    expect(hasUnsafeServiceEdit(service.formatDocument(document)), isFalse);
    expect(
      hasUnsafeServiceEdit(
        service.renameAt(document, 10, 'nextValue')?.edits ??
            const <FormattingEdit>[],
      ),
      isFalse,
    );
    expect(
      hasUnsafeServiceEdit(
        service.safeDeleteAt(document, 10)?.edits ?? const <FormattingEdit>[],
      ),
      isFalse,
    );
    expect(
      hasUnsafeServiceEdit(
        service.inlineVariableAt(document, 10)?.edits ??
            const <FormattingEdit>[],
      ),
      isFalse,
    );
    expect(
      hasUnsafeServiceEdit(
        service
                .introduceVariable(
                  document,
                  const SourceRange(start: 10, end: 15),
                  'nextValue',
                )
                ?.edits ??
            const <FormattingEdit>[],
      ),
      isFalse,
    );
    expect(
      hasUnsafeServiceEdit(
        service
                .extractFunction(
                  document,
                  const SourceRange(start: 10, end: 15),
                  'readValue',
                )
                ?.edits ??
            const <FormattingEdit>[],
      ),
      isFalse,
    );
    expect(
      hasUnsafeServiceEdit(
        service
                .changeSignatureAt(
                  document,
                  10,
                  newName: 'nextValue',
                  parameters: const <ChangeSignatureParameterUpdate>[
                    ChangeSignatureParameterUpdate(
                      originalName: 'x',
                      name: 'nextX',
                    ),
                  ],
                )
                ?.edits ??
            const <FormattingEdit>[],
      ),
      isFalse,
    );
  });

  test('toolchain connector exposes health preflight', () async {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'printf-styio',
          kind: ToolchainKind.languageService,
          displayName: 'printf Styio',
          executablePath: '/usr/bin/printf',
          metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
        ),
        activate: true,
      );
    final runtime = ToolchainRuntime(
      catalog: catalog,
      processManager: LocalProcessManager.linuxDebianArmForTest(),
    );
    final connector = ToolchainStyioServiceConnector(runtime: runtime);

    final report = await connector.checkHealth(
      probeArguments: const <String>['styio-health'],
    );

    expect(report.healthy, isTrue);
    expect(report.processResult?.stdout, 'styio-health');
  }, skip: Platform.isWindows ? 'POSIX process fixture.' : false);

  test(
    'toolchain connector runs real Styio CLI when available',
    () async {
      final tempFile = await File(
        '${Directory.systemTemp.path}/vityo_connector_true.styio',
      ).create();
      addTearDown(() => tempFile.deleteSync());
      tempFile.writeAsStringSync('value = 1\nvalue\n');

      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'local-styio',
            kind: ToolchainKind.languageService,
            displayName: 'Local Styio',
            executablePath: '/usr/local/bin/styio',
            metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
          ),
          activate: true,
        );
      final runtime = ToolchainRuntime(
        catalog: catalog,
        processManager: LocalProcessManager.linuxDebianArmForTest(),
      );
      final connector = ToolchainStyioServiceConnector(runtime: runtime);

      final response = await connector.analyzeDocument(
        StyioServiceDocument(
          documentId: tempFile.path,
          text: tempFile.readAsStringSync(),
          revision: 0,
          filePath: tempFile.path,
        ),
      );

      expect(response.status, StyioServiceStatus.succeeded);
      expect(response.diagnostics, isEmpty);
    },
    skip: File('/usr/local/bin/styio').existsSync()
        ? false
        : 'No local styio binary is installed.',
  );
}

class _RecordingProcessManager implements ProcessManager {
  _RecordingProcessManager({this.stdout = ''})
    : facts = ProcessFacts.linuxDebianArm(),
      compatibility = ProcessAdapter(ProcessFacts.linuxDebianArm()).adapt();

  final String stdout;
  final List<ProcessCommandRequest> requests = <ProcessCommandRequest>[];
  String? materializedFilePath;
  String? materializedFileContents;

  @override
  final ProcessFacts facts;

  @override
  final ProcessCompatibility compatibility;

  @override
  ProcessOperationFailure? failureFor(
    ProcessCommandResult result, {
    String operation = 'process.spawn',
    String? recoveryHint,
  }) {
    return null;
  }

  @override
  Future<ProcessCommandResult> run(ProcessCommandRequest request) async {
    requests.add(request);
    final fileArgumentIndex = request.arguments.indexOf('--file');
    if (fileArgumentIndex >= 0 &&
        fileArgumentIndex + 1 < request.arguments.length) {
      materializedFilePath = request.arguments[fileArgumentIndex + 1];
      final materializedFile = File(materializedFilePath!);
      if (materializedFile.existsSync()) {
        materializedFileContents = materializedFile.readAsStringSync();
      }
    }
    return ProcessCommandResult(
      status: ProcessCommandStatus.succeeded,
      executablePath: request.executablePath,
      arguments: request.arguments,
      exitCode: 0,
      stdout: stdout,
      stderr: '',
      duration: Duration.zero,
    );
  }
}

class _RecordingStyioServiceConnector implements StyioServiceConnector {
  _RecordingStyioServiceConnector(this.responseBuilder);

  final StyioServiceResponse Function(StyioServiceDocument document)
  responseBuilder;
  final List<StyioServiceDocument> documents = <StyioServiceDocument>[];

  @override
  Future<StyioServiceResponse> analyzeDocument(
    StyioServiceDocument document,
  ) async {
    documents.add(document);
    return responseBuilder(document);
  }
}

class _FakeStyioServiceConnector implements StyioServiceConnector {
  const _FakeStyioServiceConnector(this.response);

  final StyioServiceResponse response;

  @override
  Future<StyioServiceResponse> analyzeDocument(
    StyioServiceDocument document,
  ) async {
    return response;
  }
}
