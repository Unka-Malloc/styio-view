import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'module_manifest.dart';

enum ModuleManifestSecurityCode {
  valid,
  missingField,
  invalidIdentifier,
  invalidVersion,
  invalidPermission,
  checksumMismatch,
  signatureMissing,
  signatureInvalid,
  platformUnsupported,
  invalidSchema,
  invalidActivation,
  invalidContribution,
  engineVersionIncompatible,
  channelUnsupported,
}

class ModuleManifestSecurityIssue {
  const ModuleManifestSecurityIssue({
    required this.code,
    required this.message,
    this.field = '',
  });

  final ModuleManifestSecurityCode code;
  final String message;
  final String field;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code.name,
      'field': field,
      'message': message,
    };
  }
}

class ModuleManifestSecurityResult {
  const ModuleManifestSecurityResult({required this.issues});

  final List<ModuleManifestSecurityIssue> issues;

  bool get isValid => issues.isEmpty;

  bool hasCode(ModuleManifestSecurityCode code) {
    return issues.any((issue) => issue.code == code);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'valid': isValid,
      'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
    };
  }
}

class ModuleManifestSecurityPolicy {
  const ModuleManifestSecurityPolicy({
    this.requirePublisher = true,
    this.requireEngineVersion = true,
    this.requireChecksum = true,
    this.requireSignature = true,
    this.requireChannel = true,
    this.requireActivation = false,
    this.allowedPermissions = const <String>{
      'file.read',
      'file.write',
      'process.exec',
      'network',
      'secret.read',
      'module.install',
      'cloud.upload',
      'terminal.interactive',
    },
    this.allowedChannels = const <String>{'stable', 'preview', 'nightly'},
    this.platform = 'any',
    this.currentEngineVersion = '',
  });

  final bool requirePublisher;
  final bool requireEngineVersion;
  final bool requireChecksum;
  final bool requireSignature;
  final bool requireChannel;
  final bool requireActivation;
  final Set<String> allowedPermissions;
  final Set<String> allowedChannels;
  final String platform;
  final String currentEngineVersion;
}

typedef ModuleManifestSignatureVerifier = bool Function({
  required String canonicalManifestJson,
  required String signature,
  String? algorithm,
  String? keyId,
});

enum ModuleManifestSecurityStateStatus { trusted, quarantined, rolledBack }

extension ModuleManifestSecurityStateStatusX
    on ModuleManifestSecurityStateStatus {
  String get wireValue {
    return switch (this) {
      ModuleManifestSecurityStateStatus.trusted => 'trusted',
      ModuleManifestSecurityStateStatus.quarantined => 'quarantined',
      ModuleManifestSecurityStateStatus.rolledBack => 'rolled-back',
    };
  }
}

class ModuleManifestSecurityState {
  const ModuleManifestSecurityState({
    required this.moduleId,
    required this.version,
    required this.status,
    this.rollbackVersion = '',
    this.reason = '',
    this.issues = const <ModuleManifestSecurityIssue>[],
  });

  factory ModuleManifestSecurityState.fromValidation({
    required String moduleId,
    required String version,
    required ModuleManifestSecurityResult result,
    String rollbackVersion = '',
    String reason = '',
  }) {
    return ModuleManifestSecurityState(
      moduleId: moduleId,
      version: version,
      status: result.isValid
          ? ModuleManifestSecurityStateStatus.trusted
          : ModuleManifestSecurityStateStatus.quarantined,
      rollbackVersion: rollbackVersion,
      reason: reason.isNotEmpty
          ? reason
          : result.isValid
          ? 'Module manifest passed security validation.'
          : 'Module manifest failed security validation and is quarantined.',
      issues: result.issues,
    );
  }

  final String moduleId;
  final String version;
  final ModuleManifestSecurityStateStatus status;
  final String rollbackVersion;
  final String reason;
  final List<ModuleManifestSecurityIssue> issues;

  bool get quarantined =>
      status == ModuleManifestSecurityStateStatus.quarantined;
  bool get rolledBack => status == ModuleManifestSecurityStateStatus.rolledBack;
  bool get rollbackAvailable =>
      quarantined && rollbackVersion.trim().isNotEmpty;
  bool get canActivate => status == ModuleManifestSecurityStateStatus.trusted;
  String get activeVersion => rolledBack && rollbackVersion.isNotEmpty
      ? rollbackVersion
      : version;

  ModuleManifestSecurityState markRolledBack({String reason = ''}) {
    return ModuleManifestSecurityState(
      moduleId: moduleId,
      version: version,
      status: ModuleManifestSecurityStateStatus.rolledBack,
      rollbackVersion: rollbackVersion,
      reason: reason.isNotEmpty
          ? reason
          : 'Module activation rolled back to the previous trusted version.',
      issues: issues,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'moduleId': moduleId,
      'version': version,
      'activeVersion': activeVersion,
      'status': status.wireValue,
      'quarantined': quarantined,
      'rollbackAvailable': rollbackAvailable,
      'canActivate': canActivate,
      if (rollbackVersion.isNotEmpty) 'rollbackVersion': rollbackVersion,
      if (reason.isNotEmpty) 'reason': reason,
      if (issues.isNotEmpty)
        'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
    };
  }
}

class ModuleManifestSecurityValidator {
  const ModuleManifestSecurityValidator({
    this.policy = const ModuleManifestSecurityPolicy(),
    this.signatureVerifier,
  });

  final ModuleManifestSecurityPolicy policy;
  final ModuleManifestSignatureVerifier? signatureVerifier;

  ModuleManifestSecurityResult validateJson(
    Map<String, Object?> json, {
    String? canonicalManifestJson,
  }) {
    final issues = <ModuleManifestSecurityIssue>[];
    void requireString(String field) {
      final value = json[field];
      if (value is! String || value.trim().isEmpty) {
        issues.add(
          ModuleManifestSecurityIssue(
            code: ModuleManifestSecurityCode.missingField,
            field: field,
            message: 'Module manifest must declare `$field`.',
          ),
        );
      }
    }

    final manifestId = _stringValue(json['id']) ?? _stringValue(json['moduleId']);
    if (manifestId == null) {
      issues.add(
        const ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.missingField,
          field: 'id',
          message: 'Module manifest must declare `id` or `moduleId`.',
        ),
      );
    }

    for (final field in <String>[
      'version',
      'entrypoint',
      'distributionPolicyRef',
    ]) {
      requireString(field);
    }
    if (policy.requirePublisher) {
      requireString('publisher');
    }
    final engineConstraint = _engineConstraint(json);
    if (policy.requireEngineVersion && engineConstraint == null) {
      issues.add(
        const ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.missingField,
          field: 'engine',
          message: 'Module manifest must declare an engine version constraint.',
        ),
      );
    }

    if (manifestId != null &&
        !_stableIdentifierPattern.hasMatch(manifestId)) {
      issues.add(
        ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.invalidIdentifier,
          field: json.containsKey('id') ? 'id' : 'moduleId',
          message: 'Module id must be a stable lowercase identifier.',
        ),
      );
    }
    final publisher = json['publisher'];
    if (publisher is String &&
        !_publisherIdentifierPattern.hasMatch(publisher.trim())) {
      issues.add(
        const ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.invalidIdentifier,
          field: 'publisher',
          message: 'Publisher must be a stable lowercase identifier.',
        ),
      );
    }
    final version = json['version'];
    if (version is String && _Semver.tryParse(version) == null) {
      issues.add(
        const ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.invalidVersion,
          field: 'version',
          message: 'Module version must be semver.',
        ),
      );
    }

    if (engineConstraint != null) {
      final engineCheck = policy.currentEngineVersion.trim().isEmpty
          ? _engineConstraintIsValid(engineConstraint)
          : _engineConstraintSatisfied(
              constraint: engineConstraint,
              currentVersion: policy.currentEngineVersion,
            );
      if (engineCheck == null) {
        issues.add(
          const ModuleManifestSecurityIssue(
            code: ModuleManifestSecurityCode.invalidVersion,
            field: 'engine',
            message: 'Engine version constraint must use semver bounds.',
          ),
        );
      } else if (!engineCheck) {
        issues.add(
          ModuleManifestSecurityIssue(
            code: ModuleManifestSecurityCode.engineVersionIncompatible,
            field: 'engine',
            message:
                'Module requires engine `$engineConstraint`, but current engine '
                'is `${policy.currentEngineVersion}`.',
          ),
        );
      }
    }

    final activation = _activationValue(json);
    if (policy.requireActivation && activation == null) {
      issues.add(
        const ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.missingField,
          field: 'activation',
          message: 'Module manifest must declare activation events.',
        ),
      );
    }
    _validateActivation(activation, issues);
    _validateContributions(json, issues);

    final permissions = _validatedStringList(
      json['permissions'],
      field: 'permissions',
      issues: issues,
      code: ModuleManifestSecurityCode.invalidPermission,
      message: 'Module permissions must be a list of non-empty strings.',
    );
    for (final permission in permissions) {
      if (!policy.allowedPermissions.contains(permission)) {
        issues.add(
          ModuleManifestSecurityIssue(
            code: ModuleManifestSecurityCode.invalidPermission,
            field: 'permissions',
            message: 'Permission `$permission` is not allowed by policy.',
          ),
        );
      }
    }

    final platforms = _platformList(json, issues);
    if (platforms.isNotEmpty &&
        policy.platform != 'any' &&
        !platforms.contains('any') &&
        !platforms.contains(policy.platform)) {
      issues.add(
        ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.platformUnsupported,
          field: 'platforms',
          message: 'Module does not support `${policy.platform}`.',
        ),
      );
    }

    final channel = _stringValue(json['channel']);
    if (policy.requireChannel && channel == null) {
      issues.add(
        const ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.missingField,
          field: 'channel',
          message: 'Module manifest must declare a release channel.',
        ),
      );
    } else if (channel != null &&
        policy.allowedChannels.isNotEmpty &&
        !policy.allowedChannels.contains(channel)) {
      issues.add(
        ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.channelUnsupported,
          field: 'channel',
          message: 'Module channel `$channel` is not allowed by policy.',
        ),
      );
    }

    final checksum = json['checksum'];
    if (policy.requireChecksum &&
        (checksum is! String || !checksum.startsWith('sha256:'))) {
      issues.add(
        const ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.missingField,
          field: 'checksum',
          message: 'Module manifest must declare a sha256 checksum.',
        ),
      );
    } else if (checksum is String &&
        checksum.startsWith('sha256:') &&
        !_checksumVerifier.verify(
          canonicalManifestJson: canonicalManifestJson ??
              canonicalModuleManifestJson(json),
          checksum: checksum,
        )) {
      issues.add(
        const ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.checksumMismatch,
          field: 'checksum',
          message: 'Module manifest checksum does not match the payload.',
        ),
      );
    }

    final signature = _signaturePayload(json['signature']);
    if (policy.requireSignature && signature == null) {
      issues.add(
        const ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.signatureMissing,
          field: 'signature',
          message: 'Module manifest must declare a signature.',
        ),
      );
    } else if (signature != null && signatureVerifier != null) {
      final verified = _verifySignature(
        signature: signature,
        canonicalManifestJson:
            canonicalManifestJson ?? canonicalModuleManifestJson(json),
      );
      if (!verified) {
        issues.add(
          const ModuleManifestSecurityIssue(
            code: ModuleManifestSecurityCode.signatureInvalid,
            field: 'signature',
            message: 'Module manifest signature verification failed.',
          ),
        );
      }
    }

    return ModuleManifestSecurityResult(issues: List.unmodifiable(issues));
  }

  ModuleManifestSecurityResult validateModule(
    ModuleManifest manifest, {
    bool strictSupplyChain = false,
    String? canonicalManifestJson,
  }) {
    final json = <String, Object?>{
      'id': manifest.moduleId,
      'moduleId': manifest.moduleId,
      'version': manifest.version,
      'entrypoint': manifest.entrypoint,
      'distributionPolicyRef': manifest.distributionPolicyRef,
      ...manifest.extensionMetadata,
      if (manifest.extensionActivationEvents.isNotEmpty)
        'activation': manifest.extensionActivationEvents,
      if (manifest.extensionContributions.isNotEmpty)
        'contributions': manifest.extensionContributions,
    };
    return ModuleManifestSecurityValidator(
      policy: strictSupplyChain
          ? policy
          : ModuleManifestSecurityPolicy(
              requirePublisher: false,
              requireEngineVersion: false,
              requireChecksum: false,
              requireSignature: false,
              requireChannel: false,
              requireActivation: false,
              allowedPermissions: policy.allowedPermissions,
              allowedChannels: policy.allowedChannels,
              platform: policy.platform,
              currentEngineVersion: policy.currentEngineVersion,
            ),
      signatureVerifier: signatureVerifier,
    ).validateJson(json, canonicalManifestJson: canonicalManifestJson);
  }

  bool _verifySignature({
    required _ModuleManifestSignaturePayload signature,
    required String canonicalManifestJson,
  }) {
    try {
      return signatureVerifier!(
        canonicalManifestJson: canonicalManifestJson,
        signature: signature.signature,
        algorithm: signature.algorithm,
        keyId: signature.keyId,
      );
    } on Object {
      return false;
    }
  }
}

class ModuleChecksumVerifier {
  const ModuleChecksumVerifier();

  bool verify({
    required String canonicalManifestJson,
    required String checksum,
  }) {
    if (!checksum.startsWith('sha256:')) {
      return false;
    }
    final digest = sha256.convert(utf8.encode(canonicalManifestJson));
    return checksum == 'sha256:$digest';
  }
}

String canonicalModuleManifestJson(Map<String, Object?> json) {
  return jsonEncode(_canonicalJsonValue(json, omitSupplyChainFields: true));
}

const ModuleChecksumVerifier _checksumVerifier = ModuleChecksumVerifier();

final RegExp _stableIdentifierPattern = RegExp(
  r'^[a-z0-9][a-z0-9._-]{1,127}$',
);
final RegExp _publisherIdentifierPattern = RegExp(
  r'^[a-z0-9][a-z0-9._-]{0,127}$',
);
final RegExp _activationEventPattern = RegExp(r'^[A-Za-z0-9_.:-]+$');

String? _stringValue(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _engineConstraint(Map<String, Object?> json) {
  final engine = json['engine'];
  if (engine is String) {
    return _stringValue(engine);
  }
  if (engine is Map) {
    return _stringValue(engine['vityo']) ??
        _stringValue(engine['version']) ??
        _stringValue(engine['constraint']);
  }
  return _stringValue(json['engineVersion']);
}

List<String> _validatedStringList(
  Object? value, {
  required String field,
  required List<ModuleManifestSecurityIssue> issues,
  required ModuleManifestSecurityCode code,
  required String message,
}) {
  if (value == null) {
    return const <String>[];
  }
  if (value is! List) {
    issues.add(
      ModuleManifestSecurityIssue(
        code: code,
        field: field,
        message: message,
      ),
    );
    return const <String>[];
  }
  final items = <String>[];
  for (final item in value) {
    final text = _stringValue(item);
    if (text == null) {
      issues.add(
        ModuleManifestSecurityIssue(
          code: code,
          field: field,
          message: message,
        ),
      );
      continue;
    }
    items.add(text);
  }
  return List<String>.unmodifiable(items);
}

void _validateActivation(
  Object? activation,
  List<ModuleManifestSecurityIssue> issues,
) {
  if (activation == null) {
    return;
  }
  final events = _validatedStringList(
    activation,
    field: 'activation',
    issues: issues,
    code: ModuleManifestSecurityCode.invalidActivation,
    message: 'Activation events must be a list of non-empty strings.',
  );
  for (final event in events) {
    if (!_activationEventPattern.hasMatch(event)) {
      issues.add(
        ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.invalidActivation,
          field: 'activation',
          message: 'Activation event `$event` is not a valid event id.',
        ),
      );
    }
  }
}

Object? _activationValue(Map<String, Object?> json) {
  final extension = json['extension'];
  if (json.containsKey('activation')) {
    return json['activation'];
  }
  if (json.containsKey('activationEvents')) {
    return json['activationEvents'];
  }
  if (extension is Map) {
    return extension['activationEvents'];
  }
  return null;
}

void _validateContributions(
  Map<String, Object?> json,
  List<ModuleManifestSecurityIssue> issues,
) {
  final contributions = _contributionsValue(json);
  if (contributions == null) {
    return;
  }
  if (contributions is! List) {
    issues.add(
      const ModuleManifestSecurityIssue(
        code: ModuleManifestSecurityCode.invalidContribution,
        field: 'contributions',
        message: 'Contributions must be a list of JSON objects.',
      ),
    );
    return;
  }
  for (final contribution in contributions) {
    if (contribution is! Map) {
      issues.add(
        const ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.invalidContribution,
          field: 'contributions',
          message: 'Contribution entries must be JSON objects.',
        ),
      );
      continue;
    }
    final kind = _stringValue(contribution['kind']);
    final id = _stringValue(contribution['id']);
    final target = _stringValue(contribution['target']);
    if (kind == null || id == null || target == null) {
      issues.add(
        const ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.invalidContribution,
          field: 'contributions',
          message: 'Contribution entries must declare kind, id, and target.',
        ),
      );
    } else if (!_stableIdentifierPattern.hasMatch(id)) {
      issues.add(
        ModuleManifestSecurityIssue(
          code: ModuleManifestSecurityCode.invalidContribution,
          field: 'contributions',
          message: 'Contribution id `$id` is not a stable identifier.',
        ),
      );
    }
  }
}

Object? _contributionsValue(Map<String, Object?> json) {
  final extension = json['extension'];
  if (json.containsKey('contributions')) {
    return json['contributions'];
  }
  if (extension is Map) {
    return extension['contributions'];
  }
  return null;
}

List<String> _platformList(
  Map<String, Object?> json,
  List<ModuleManifestSecurityIssue> issues,
) {
  if (json.containsKey('platforms')) {
    return _validatedStringList(
      json['platforms'],
      field: 'platforms',
      issues: issues,
      code: ModuleManifestSecurityCode.platformUnsupported,
      message: 'Platforms must be a list of non-empty strings.',
    );
  }
  final platform = _stringValue(json['platform']);
  return platform == null ? const <String>[] : <String>[platform];
}

_ModuleManifestSignaturePayload? _signaturePayload(Object? value) {
  if (value is String) {
    final signature = _stringValue(value);
    return signature == null
        ? null
        : _ModuleManifestSignaturePayload(signature: signature);
  }
  if (value is Map) {
    final signature = _stringValue(value['signature']) ??
        _stringValue(value['signatureBase64']) ??
        _stringValue(value['value']);
    if (signature == null) {
      return null;
    }
    return _ModuleManifestSignaturePayload(
      signature: signature,
      algorithm: _stringValue(value['algorithm']),
      keyId: _stringValue(value['keyId']),
    );
  }
  return null;
}

Object? _canonicalJsonValue(
  Object? value, {
  bool omitSupplyChainFields = false,
}) {
  if (value is Map) {
    final map = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (omitSupplyChainFields &&
          (key == 'checksum' || key == 'signature')) {
        continue;
      }
      map[key] = _canonicalJsonValue(entry.value);
    }
    return map;
  }
  if (value is Iterable) {
    return value
        .map((entry) => _canonicalJsonValue(entry))
        .toList(growable: false);
  }
  return value;
}

bool? _engineConstraintIsValid(String constraint) {
  final normalized = constraint.trim();
  if (normalized == '*' || normalized.toLowerCase() == 'any') {
    return true;
  }
  final tokens = normalized
      .split(RegExp(r'[,\s]+'))
      .where((token) => token.isNotEmpty);
  if (tokens.isEmpty) {
    return null;
  }
  for (final token in tokens) {
    if (token.startsWith('^')) {
      if (_Semver.tryParse(token.substring(1)) == null) {
        return null;
      }
      continue;
    }
    final match = RegExp(r'^(>=|<=|>|<|=)?(.+)$').firstMatch(token);
    if (match == null || _Semver.tryParse(match.group(2) ?? '') == null) {
      return null;
    }
  }
  return true;
}

bool? _engineConstraintSatisfied({
  required String constraint,
  required String currentVersion,
}) {
  final current = _Semver.tryParse(currentVersion);
  if (current == null) {
    return null;
  }
  final normalized = constraint.trim();
  if (normalized == '*' || normalized.toLowerCase() == 'any') {
    return true;
  }
  final tokens = normalized
      .split(RegExp(r'[,\s]+'))
      .where((token) => token.isNotEmpty);
  if (tokens.isEmpty) {
    return null;
  }
  for (final token in tokens) {
    final satisfied = _satisfiesToken(current, token);
    if (satisfied == null || !satisfied) {
      return satisfied;
    }
  }
  return true;
}

bool? _satisfiesToken(_Semver current, String token) {
  if (token.startsWith('^')) {
    final base = _Semver.tryParse(token.substring(1));
    if (base == null) {
      return null;
    }
    final upper = base.major == 0
        ? _Semver(base.major, base.minor + 1, 0)
        : _Semver(base.major + 1, 0, 0);
    return current.compareTo(base) >= 0 && current.compareTo(upper) < 0;
  }
  final match = RegExp(r'^(>=|<=|>|<|=)?(.+)$').firstMatch(token);
  if (match == null) {
    return null;
  }
  final operator = match.group(1) ?? '=';
  final target = _Semver.tryParse(match.group(2) ?? '');
  if (target == null) {
    return null;
  }
  final comparison = current.compareTo(target);
  return switch (operator) {
    '>=' => comparison >= 0,
    '<=' => comparison <= 0,
    '>' => comparison > 0,
    '<' => comparison < 0,
    '=' => comparison == 0,
    _ => null,
  };
}

class _ModuleManifestSignaturePayload {
  const _ModuleManifestSignaturePayload({
    required this.signature,
    this.algorithm,
    this.keyId,
  });

  final String signature;
  final String? algorithm;
  final String? keyId;
}

class _Semver implements Comparable<_Semver> {
  const _Semver(this.major, this.minor, this.patch);

  static _Semver? tryParse(String value) {
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    return _Semver(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(_Semver other) {
    final majorComparison = major.compareTo(other.major);
    if (majorComparison != 0) {
      return majorComparison;
    }
    final minorComparison = minor.compareTo(other.minor);
    if (minorComparison != 0) {
      return minorComparison;
    }
    return patch.compareTo(other.patch);
  }
}
