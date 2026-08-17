import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

import '../../view_ide/language/contract/language_contract.dart';
import '../workspace/workspace_search_service.dart';
import 'vityod_client.dart';

final class VityodWorkspaceTextSearchProvider
    implements WorkspaceTextSearchProvider {
  VityodWorkspaceTextSearchProvider({required VityodClient client})
    : _client = client;

  final VityodClient _client;
  var _sequence = 0;

  @override
  Future<WorkspaceSearchResult> search({
    required String workspaceId,
    required String query,
    int maxMatches = 1000,
  }) async {
    if (query.isEmpty || maxMatches <= 0) {
      return const WorkspaceSearchResult(matches: <WorkspaceSearchMatch>[]);
    }
    final matches = <WorkspaceSearchMatch>[];
    var cursor = 0;
    var truncated = false;
    while (matches.length < maxMatches) {
      final pageLimit = (maxMatches - matches.length).clamp(1, 250);
      final response = await _client.request(
        method: 'workspace.search',
        idempotencyKey: 'workspace-search-${++_sequence}',
        workspaceId: workspaceId,
        params: <String, Object?>{
          'query': query,
          'cursor': cursor,
          'limit': pageLimit,
        },
      );
      _throwIfError(response);
      final rawMatches = response.params['matches'];
      if (rawMatches is! List) {
        throw const VityodWorkspaceSearchFailure('invalid_search_response');
      }
      for (final raw in rawMatches) {
        if (raw is! Map) {
          throw const VityodWorkspaceSearchFailure('invalid_search_response');
        }
        final value = Map<String, Object?>.from(raw);
        final relativePath = _requiredString(value, 'relativePath');
        final line = _requiredInt(value, 'line');
        final start = _requiredInt(value, 'startOffset');
        final end = _requiredInt(value, 'endOffset');
        final text = _requiredString(value, 'text');
        final lineText = _requiredString(value, 'lineText');
        if (line < 1 || start < 0 || end < start) {
          throw const VityodWorkspaceSearchFailure('invalid_search_response');
        }
        matches.add(
          WorkspaceSearchMatch(
            documentId: relativePath,
            range: SourceRange(start: start, end: end),
            text: text,
            lineNumber: line,
            lineText: lineText,
          ),
        );
      }
      final next = response.params['nextCursor'];
      if (next == null) break;
      if (next is! int || next <= cursor) {
        throw const VityodWorkspaceSearchFailure('invalid_search_response');
      }
      cursor = next;
      if (matches.length >= maxMatches) truncated = true;
    }
    return WorkspaceSearchResult(
      matches: List<WorkspaceSearchMatch>.unmodifiable(matches),
      truncated: truncated,
    );
  }
}

final class VityodWorkspaceSearchFailure implements Exception {
  const VityodWorkspaceSearchFailure(this.code);

  final String code;

  @override
  String toString() => 'VityodWorkspaceSearchFailure($code)';
}

void _throwIfError(VityodControlEnvelope response) {
  if (!response.method.endsWith('.error')) return;
  final code = response.params['errorCode'];
  throw VityodWorkspaceSearchFailure(
    code is String ? code : 'workspace_search_failed',
  );
}

String _requiredString(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is String) return result;
  throw const VityodWorkspaceSearchFailure('invalid_search_response');
}

int _requiredInt(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is int) return result;
  throw const VityodWorkspaceSearchFailure('invalid_search_response');
}
