import 'dart:async';
import 'dart:convert';
import 'dart:io';

final _pendingPrompts = <String, _PendingPrompt>{};
final _permissionToSession = <String, String>{};
var _sessionSequence = 0;
var _permissionSequence = 0;
var _effectCount = 0;

Future<void> main(List<String> arguments) async {
  final mode = arguments.singleOrNull ?? 'normal';
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final decoded = jsonDecode(line) as Map<String, Object?>;
    final id = decoded['id'];
    final method = decoded['method'];
    if (method == null && id != null) {
      _handleClientResponse(decoded);
      continue;
    }
    if (method == 'initialize') {
      if (mode == 'crash') {
        exitCode = 17;
        return;
      }
      if (mode == 'malformed') {
        stdout.writeln('{"jsonrpc":"2.0","id":');
        continue;
      }
      if (mode == 'oversized') {
        stdout.writeln(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': id,
            'result': <String, Object?>{
              'padding': List<String>.filled(70 * 1024, 'x').join(),
            },
          }),
        );
        continue;
      }
      _success(id, <String, Object?>{
        'protocolVersion': mode == 'unsupported' ? 99 : 1,
        'agentInfo': <String, Object?>{
          'name': 'vityo-fake-agent',
          'version': '1.0.0',
        },
        'agentCapabilities': <String, Object?>{
          'loadSession': true,
          'promptCapabilities': <String, Object?>{
            'image': false,
            'audio': false,
            'embeddedContext': true,
          },
          '_meta': <String, Object?>{
            'vityo.dev': <String, Object?>{
              'extensions': <String>[
                '_vityo.dev/test/write',
                '_vityo.dev/test/status',
                '_vityo.dev/workspace-change-proposal',
              ],
            },
          },
        },
        'authMethods': const <Object?>[],
        '_meta': <String, Object?>{
          'vityo.test/privateEnvironmentVisible': Platform.environment
              .containsKey('VITYO_ACCEPTANCE_PRIVATE'),
        },
      });
      continue;
    }
    if (method == 'session/new') {
      _sessionSequence += 1;
      _success(id, <String, Object?>{
        'sessionId': mode == 'reused-session'
            ? 'session-1'
            : 'session-$_sessionSequence',
      });
      continue;
    }
    if (method == 'session/load') {
      final params =
          decoded['params'] as Map<String, Object?>? ??
          const <String, Object?>{};
      _notification('session/update', <String, Object?>{
        'sessionId': params['sessionId'],
        'update': <String, Object?>{
          'sessionUpdate': 'agent_message_chunk',
          'content': <String, Object?>{
            'type': 'text',
            'text': 'replayed-session-history',
          },
        },
      });
      _success(id, null);
      continue;
    }
    if (method == 'session/prompt') {
      _handlePrompt(id, decoded, mode);
      continue;
    }
    if (method == 'session/cancel') {
      final params =
          decoded['params'] as Map<String, Object?>? ??
          const <String, Object?>{};
      _cancel(params['sessionId'] as String);
      continue;
    }
    if (method == '_vityo.dev/test/write') {
      _effectCount += 1;
      _success(id, <String, Object?>{'written': true});
      continue;
    }
    if (method == '_vityo.dev/test/status') {
      _success(id, <String, Object?>{'effectCount': _effectCount});
      continue;
    }
    if (method == '_vityo.dev/shutdown') {
      return;
    }
    _error(id, -32601, 'method not found');
  }
}

void _handlePrompt(Object? id, Map<String, Object?> message, String mode) {
  final params =
      message['params'] as Map<String, Object?>? ?? const <String, Object?>{};
  final sessionId = params['sessionId'] as String;
  final prompt = params['prompt'] as List<Object?>? ?? const <Object?>[];
  final firstBlock =
      prompt.firstOrNull as Map<String, Object?>? ?? const <String, Object?>{};
  final text = firstBlock['text'] as String? ?? '';
  _notification('session/update', <String, Object?>{
    'sessionId': sessionId,
    'update': <String, Object?>{
      'sessionUpdate': 'agent_message_chunk',
      'content': <String, Object?>{'type': 'text', 'text': 'chunk:$text'},
    },
  });
  _pendingPrompts[sessionId] = _PendingPrompt(id: id, text: text);

  if (text == 'wait') {
    return;
  }
  if (text == 'capabilities') {
    _notification('_vityo.dev/capabilities_changed', <String, Object?>{
      'capabilities': <String>['loadSession', '_vityo.dev/test/status'],
    });
    _pendingPrompts.remove(sessionId);
    _success(id, <String, Object?>{'stopReason': 'end_turn'});
    return;
  }

  _permissionSequence += 1;
  final permissionId = 'permission-$_permissionSequence';
  _permissionToSession[permissionId] = sessionId;
  _request(permissionId, 'session/request_permission', <String, Object?>{
    'sessionId': sessionId,
    'toolCall': <String, Object?>{
      'toolCallId': 'tool-$permissionId',
      'title': 'Use deterministic fixture tool',
      'kind': 'other',
    },
    'options': <Map<String, Object?>>[
      <String, Object?>{
        'optionId': 'allow-once-$permissionId',
        'name': 'Allow once',
        'kind': 'allow_once',
      },
      <String, Object?>{
        'optionId': 'reject-once-$permissionId',
        'name': 'Reject',
        'kind': 'reject_once',
      },
    ],
  });
  if (mode == 'crash-with-permission') {
    Timer(const Duration(milliseconds: 100), () => exit(23));
  }
}

void _handleClientResponse(Map<String, Object?> response) {
  final permissionId = response['id'].toString();
  final sessionId = _permissionToSession.remove(permissionId);
  if (sessionId == null) {
    return;
  }
  final pending = _pendingPrompts.remove(sessionId);
  if (pending == null) {
    return;
  }
  final result =
      response['result'] as Map<String, Object?>? ?? const <String, Object?>{};
  final outcome =
      result['outcome'] as Map<String, Object?>? ?? const <String, Object?>{};
  if (outcome['outcome'] != 'selected' ||
      outcome['optionId'] != 'allow-once-$permissionId') {
    _success(pending.id, <String, Object?>{'stopReason': 'refusal'});
    return;
  }
  _notification('session/update', <String, Object?>{
    'sessionId': sessionId,
    'update': <String, Object?>{
      'sessionUpdate': 'agent_message_chunk',
      'content': <String, Object?>{
        'type': 'text',
        'text': 'approved:${pending.text}',
      },
    },
  });
  if (pending.text == 'propose-change') {
    _notification('_vityo.dev/workspace-change-proposal', <String, Object?>{
      'sessionId': sessionId,
      'proposal': <String, Object?>{
        'id': 'change-$sessionId',
        'baseWorkspaceRevision': 0,
        'resources': <Object?>[
          <String, Object?>{
            'resourceId': 'file',
            'baseDocumentRevision': 0,
            'edits': <Object?>[
              <String, Object?>{'start': 0, 'end': 6, 'replacement': 'after'},
            ],
          },
        ],
      },
    });
  }
  _success(pending.id, <String, Object?>{'stopReason': 'end_turn'});
}

void _cancel(String sessionId) {
  _permissionToSession.removeWhere((_, owner) => owner == sessionId);
  final pending = _pendingPrompts.remove(sessionId);
  if (pending == null) {
    return;
  }
  _notification('session/update', <String, Object?>{
    'sessionId': sessionId,
    'update': <String, Object?>{'sessionUpdate': 'cancelled'},
  });
  _success(pending.id, <String, Object?>{'stopReason': 'cancelled'});
}

void _request(Object id, String method, Map<String, Object?> params) {
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    }),
  );
}

void _notification(String method, Map<String, Object?> params) {
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    }),
  );
}

void _success(Object? id, Object? result) {
  stdout.writeln(
    jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result}),
  );
}

void _error(Object? id, int code, String message) {
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, Object?>{'code': code, 'message': message},
    }),
  );
}

final class _PendingPrompt {
  const _PendingPrompt({required this.id, required this.text});

  final Object? id;
  final String text;
}
