import 'dart:collection';
import 'dart:convert';

import 'ide_tool_catalog.dart';

enum ToolGrantScope { once, session, workspace, policy }

enum ToolAuditOutcome { allowed, denied, succeeded, failed }

final class ToolPermissionGrant {
  ToolPermissionGrant({
    required this.id,
    required this.sessionId,
    required this.toolName,
    required Set<IdeToolRisk> risks,
    required this.scope,
    this.rootId,
    this.expiresAt,
  }) : risks = Set<IdeToolRisk>.unmodifiable(risks);

  final String id;
  final String sessionId;
  final String toolName;
  final Set<IdeToolRisk> risks;
  final ToolGrantScope scope;
  final String? rootId;
  final DateTime? expiresAt;
}

final class ToolGrantRegistry {
  final Map<String, ListQueue<ToolPermissionGrant>> _grants =
      <String, ListQueue<ToolPermissionGrant>>{};

  void grant(ToolPermissionGrant grant) {
    if (grant.id.trim().isEmpty ||
        grant.sessionId.trim().isEmpty ||
        grant.toolName.trim().isEmpty ||
        grant.risks.isEmpty) {
      throw ArgumentError('grant identifiers and risks are required');
    }
    _grants
        .putIfAbsent(_key(grant.sessionId, grant.toolName), ListQueue.new)
        .addLast(grant);
  }

  bool consume({
    required String sessionId,
    required String toolName,
    required Set<IdeToolRisk> risks,
    String? rootId,
    DateTime? now,
  }) {
    final queue = _grants[_key(sessionId, toolName)];
    if (queue == null) {
      return false;
    }
    final effectiveNow = now ?? DateTime.now().toUtc();
    ToolPermissionGrant? selected;
    for (final grant in queue.toList(growable: false)) {
      if (grant.expiresAt != null && !grant.expiresAt!.isAfter(effectiveNow)) {
        queue.remove(grant);
        continue;
      }
      if (!grant.risks.containsAll(risks)) {
        continue;
      }
      if (grant.rootId != null && grant.rootId != rootId) {
        continue;
      }
      selected = grant;
      break;
    }
    if (selected == null) {
      return false;
    }
    if (selected.scope == ToolGrantScope.once) {
      queue.remove(selected);
    }
    if (queue.isEmpty) {
      _grants.remove(_key(sessionId, toolName));
    }
    return true;
  }

  void revokeSession(String sessionId) {
    _grants.removeWhere((key, _) => key.startsWith('$sessionId\u0000'));
  }
}

final class McpPayloadSanitizer {
  const McpPayloadSanitizer({this.sensitiveValues = const <String>{}});

  static const _sensitiveKeys = <String>{
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'token',
    'access_token',
    'refresh_token',
    'api_key',
    'apikey',
    'password',
    'secret',
    'credential',
  };
  static final RegExp _bearer = RegExp(
    r'\bBearer\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );

  final Set<String> sensitiveValues;

  bool containsCredentialInput(Object? value) {
    if (value is Map<Object?, Object?>) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (_sensitiveKeys.contains(key) ||
            containsCredentialInput(entry.value)) {
          return true;
        }
      }
      return false;
    }
    if (value is Iterable<Object?>) {
      return value.any(containsCredentialInput);
    }
    if (value is String) {
      return _bearer.hasMatch(value) ||
          sensitiveValues.any(
            (secret) => secret.isNotEmpty && value.contains(secret),
          );
    }
    return false;
  }

  Object? sanitize(Object? value) {
    if (value is Map<Object?, Object?>) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString():
              _sensitiveKeys.contains(entry.key.toString().toLowerCase())
              ? '[REDACTED]'
              : sanitize(entry.value),
      };
    }
    if (value is Iterable<Object?>) {
      return value.map(sanitize).toList(growable: false);
    }
    if (value is String) {
      var sanitized = value.replaceAll(_bearer, '[REDACTED]');
      for (final secret in sensitiveValues) {
        if (secret.isNotEmpty) {
          sanitized = sanitized.replaceAll(secret, '[REDACTED]');
        }
      }
      return sanitized;
    }
    return value;
  }
}

final class ToolAuditReceipt {
  ToolAuditReceipt({
    required this.id,
    required this.sessionId,
    required this.toolName,
    required this.outcome,
    required this.code,
    required Set<IdeToolRisk> risks,
    required this.rootRevision,
    required this.workspaceRevision,
    required this.provenance,
  }) : risks = Set<IdeToolRisk>.unmodifiable(risks);

  final String id;
  final String sessionId;
  final String toolName;
  final ToolAuditOutcome outcome;
  final String code;
  final Set<IdeToolRisk> risks;
  final int rootRevision;
  final int workspaceRevision;
  final String provenance;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'sessionId': sessionId,
    'toolName': toolName,
    'outcome': outcome.name,
    'code': code,
    'risks': risks.map((risk) => risk.name).toList(growable: false)..sort(),
    'rootRevision': rootRevision,
    'workspaceRevision': workspaceRevision,
    'provenance': provenance,
  };
}

final class ToolAuditLog {
  ToolAuditLog({required this.maxEntries}) {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
  }

  final int maxEntries;
  final ListQueue<ToolAuditReceipt> _receipts = ListQueue<ToolAuditReceipt>();
  int _sequence = 0;

  List<ToolAuditReceipt> get receipts =>
      List<ToolAuditReceipt>.unmodifiable(_receipts);

  ToolAuditReceipt add({
    required String sessionId,
    required String toolName,
    required ToolAuditOutcome outcome,
    required String code,
    required Set<IdeToolRisk> risks,
    required int rootRevision,
    required int workspaceRevision,
    required String provenance,
  }) {
    _sequence += 1;
    final receipt = ToolAuditReceipt(
      id: 'tool-audit-$_sequence',
      sessionId: sessionId,
      toolName: toolName,
      outcome: outcome,
      code: code,
      risks: risks,
      rootRevision: rootRevision,
      workspaceRevision: workspaceRevision,
      provenance: provenance,
    );
    if (_receipts.length == maxEntries) {
      _receipts.removeFirst();
    }
    _receipts.addLast(receipt);
    return receipt;
  }

  void discardLast(ToolAuditReceipt receipt) {
    if (_receipts.isNotEmpty && identical(_receipts.last, receipt)) {
      _receipts.removeLast();
    }
  }
}

final class ToolAuthorization {
  const ToolAuthorization({required this.allowed, required this.code});

  final bool allowed;
  final String code;
}

final class ToolSecurityPolicy {
  const ToolSecurityPolicy({
    required this.grants,
    required this.auditLog,
    required this.sanitizer,
    required this.maxResultBytes,
  });

  final ToolGrantRegistry grants;
  final ToolAuditLog auditLog;
  final McpPayloadSanitizer sanitizer;
  final int maxResultBytes;

  ToolAuthorization authorize({
    required String sessionId,
    required IdeToolDescriptor descriptor,
    required Map<String, Object?> arguments,
    String? rootId,
  }) {
    if (sanitizer.containsCredentialInput(arguments)) {
      return const ToolAuthorization(
        allowed: false,
        code: 'credential_passthrough_denied',
      );
    }
    final protectedRisks = descriptor.risks.difference(const <IdeToolRisk>{
      IdeToolRisk.readOnly,
    });
    if (protectedRisks.isEmpty) {
      return const ToolAuthorization(allowed: true, code: 'allowed');
    }
    final granted = grants.consume(
      sessionId: sessionId,
      toolName: descriptor.name,
      risks: protectedRisks,
      rootId: rootId,
    );
    return ToolAuthorization(
      allowed: granted,
      code: granted ? 'allowed' : 'permission_required',
    );
  }

  bool resultWithinLimit(Object? value) =>
      utf8.encode(jsonEncode(value)).length <= maxResultBytes;
}

String _key(String sessionId, String toolName) => '$sessionId\u0000$toolName';
