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
  ToolGrantRegistry({this.maxGrants = 256}) {
    if (maxGrants <= 0) {
      throw ArgumentError.value(maxGrants, 'maxGrants', 'must be positive');
    }
  }

  final int maxGrants;
  final Map<String, ListQueue<ToolPermissionGrant>> _grants =
      <String, ListQueue<ToolPermissionGrant>>{};
  int _grantCount = 0;

  void grant(ToolPermissionGrant grant) {
    if (grant.id.trim().isEmpty ||
        grant.id.length > 256 ||
        grant.sessionId.trim().isEmpty ||
        grant.sessionId.length > 256 ||
        grant.toolName.trim().isEmpty ||
        grant.toolName.length > 128 ||
        grant.risks.isEmpty) {
      throw ArgumentError('grant identifiers and risks are required');
    }
    if (_grantCount >= maxGrants) {
      throw StateError('tool grant limit was reached');
    }
    _grants
        .putIfAbsent(_key(grant.sessionId, grant.toolName), ListQueue.new)
        .addLast(grant);
    _grantCount += 1;
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
        _grantCount -= 1;
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
      _grantCount -= 1;
    }
    if (queue.isEmpty) {
      _grants.remove(_key(sessionId, toolName));
    }
    return true;
  }

  void revokeSession(String sessionId) {
    final keys = _grants.keys
        .where((key) => key.startsWith('$sessionId\u0000'))
        .toList(growable: false);
    for (final key in keys) {
      _grantCount -= _grants.remove(key)?.length ?? 0;
    }
  }
}

final class McpPayloadSanitizer {
  const McpPayloadSanitizer() : sensitiveValues = const <String>{};

  McpPayloadSanitizer.withSensitiveValues(Set<String> sensitiveValues)
    : sensitiveValues = Set<String>.unmodifiable(sensitiveValues);

  static const _sensitiveKeys = <String>{
    'authorization',
    'proxyauthorization',
    'cookie',
    'setcookie',
    'token',
    'accesstoken',
    'refreshtoken',
    'apikey',
    'authtoken',
    'clientsecret',
    'password',
    'secret',
    'credential',
    'privatekey',
    'sessionkey',
  };
  static final RegExp _authorization = RegExp(
    r'\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _credentialAssignment = RegExp(
    r'((?:access[_-]?token|refresh[_-]?token|api[_-]?key|password|secret|credential)=)[^&\s]+',
    caseSensitive: false,
  );
  static final RegExp _nonAlphanumeric = RegExp('[^a-z0-9]');
  static const int _maxNestingDepth = 64;
  static const int _maxCollectionItems = 4096;
  static const String _redacted = '[REDACTED]';

  final Set<String> sensitiveValues;

  bool containsCredentialInput(Object? value) => _containsCredentialInput(
    value,
    depth: 0,
    visiting: HashSet<Object>.identity(),
  );

  bool _containsCredentialInput(
    Object? value, {
    required int depth,
    required Set<Object> visiting,
  }) {
    if (depth > _maxNestingDepth) {
      return true;
    }
    if (value is Map<Object?, Object?>) {
      if (value.length > _maxCollectionItems || !visiting.add(value)) {
        return true;
      }
      for (final entry in value.entries) {
        if (_isSensitiveKey(entry.key.toString()) ||
            _containsCredentialInput(
              entry.value,
              depth: depth + 1,
              visiting: visiting,
            )) {
          visiting.remove(value);
          return true;
        }
      }
      visiting.remove(value);
      return false;
    }
    if (value is Iterable<Object?>) {
      if (!visiting.add(value)) {
        return true;
      }
      var count = 0;
      for (final item in value) {
        count += 1;
        if (count > _maxCollectionItems ||
            _containsCredentialInput(
              item,
              depth: depth + 1,
              visiting: visiting,
            )) {
          visiting.remove(value);
          return true;
        }
      }
      visiting.remove(value);
      return false;
    }
    if (value is String) {
      return _authorization.hasMatch(value) ||
          _credentialAssignment.hasMatch(value) ||
          sensitiveValues.any(
            (secret) => secret.isNotEmpty && value.contains(secret),
          );
    }
    return false;
  }

  Object? sanitize(Object? value) =>
      _sanitize(value, depth: 0, visiting: HashSet<Object>.identity());

  Object? _sanitize(
    Object? value, {
    required int depth,
    required Set<Object> visiting,
  }) {
    if (depth > _maxNestingDepth) {
      return _redacted;
    }
    if (value is Map<Object?, Object?>) {
      if (!visiting.add(value)) {
        return _redacted;
      }
      if (value.length > _maxCollectionItems) {
        visiting.remove(value);
        return const <String, Object?>{'_sanitization': _redacted};
      }
      final sanitized = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        sanitized[key] = _isSensitiveKey(key)
            ? _redacted
            : _sanitize(entry.value, depth: depth + 1, visiting: visiting);
      }
      visiting.remove(value);
      return sanitized;
    }
    if (value is Iterable<Object?>) {
      if (!visiting.add(value)) {
        return _redacted;
      }
      final sanitized = <Object?>[];
      for (final item in value) {
        if (sanitized.length >= _maxCollectionItems) {
          visiting.remove(value);
          return const <Object?>[_redacted];
        }
        sanitized.add(_sanitize(item, depth: depth + 1, visiting: visiting));
      }
      visiting.remove(value);
      return List<Object?>.unmodifiable(sanitized);
    }
    if (value is String) {
      var sanitized = value.replaceAll(_authorization, '[REDACTED]');
      sanitized = sanitized.replaceAllMapped(
        _credentialAssignment,
        (match) => '${match.group(1)}[REDACTED]',
      );
      for (final secret in sensitiveValues) {
        if (secret.isNotEmpty) {
          sanitized = sanitized.replaceAll(secret, '[REDACTED]');
        }
      }
      return sanitized;
    }
    return value;
  }

  static bool _isSensitiveKey(String value) {
    final normalized = value.toLowerCase().replaceAll(_nonAlphanumeric, '');
    return _sensitiveKeys.contains(normalized);
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
  ToolSecurityPolicy({
    required this.grants,
    required this.auditLog,
    required this.sanitizer,
    required this.maxResultBytes,
  }) {
    if (maxResultBytes < 512 || maxResultBytes > 16 * 1024 * 1024) {
      throw ArgumentError.value(
        maxResultBytes,
        'maxResultBytes',
        'must be between 512 bytes and 16 MiB',
      );
    }
  }

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
