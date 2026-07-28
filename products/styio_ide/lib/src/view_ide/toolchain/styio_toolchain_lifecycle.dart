import 'toolchain_catalog.dart';

enum StyioToolchainRole {
  languageService,
  compiler,
  runner,
  formatter,
  testRunner,
}

extension StyioToolchainRoleX on StyioToolchainRole {
  String get wireValue => switch (this) {
    StyioToolchainRole.languageService => 'language-service',
    StyioToolchainRole.compiler => 'compiler',
    StyioToolchainRole.runner => 'runner',
    StyioToolchainRole.formatter => 'formatter',
    StyioToolchainRole.testRunner => 'test-runner',
  };

  ToolchainKind get toolchainKind => switch (this) {
    StyioToolchainRole.languageService => ToolchainKind.languageService,
    StyioToolchainRole.compiler => ToolchainKind.compiler,
    StyioToolchainRole.runner => ToolchainKind.runner,
    StyioToolchainRole.formatter => ToolchainKind.formatter,
    StyioToolchainRole.testRunner => ToolchainKind.testRunner,
  };
}

enum StyioToolchainRoleState { active, available, missing }

enum StyioToolchainLifecycleState { ready, selectable, missing }

class StyioToolchainRoleStatus {
  const StyioToolchainRoleStatus({
    required this.role,
    required this.state,
    required this.required,
    this.activeDescriptor,
    this.candidates = const <ToolchainDescriptor>[],
    this.message,
  });

  final StyioToolchainRole role;
  final StyioToolchainRoleState state;
  final bool required;
  final ToolchainDescriptor? activeDescriptor;
  final List<ToolchainDescriptor> candidates;
  final String? message;

  bool get ready => state == StyioToolchainRoleState.active;
  bool get selectable => state == StyioToolchainRoleState.available;
  bool get missing => state == StyioToolchainRoleState.missing;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'role': role.wireValue,
      'toolchainKind': role.toolchainKind.wireValue,
      'state': state.name,
      'required': required,
      if (activeDescriptor != null)
        'activeDescriptor': activeDescriptor!.toJson(),
      'candidateCount': candidates.length,
      'candidates': candidates
          .map((descriptor) => descriptor.toJson())
          .toList(growable: false),
      if (message != null) 'message': message,
      'ready': ready,
      'selectable': selectable,
      'missing': missing,
    };
  }
}

class StyioToolchainLifecycleReport {
  const StyioToolchainLifecycleReport({
    required this.state,
    required this.roles,
    required this.requiredRoles,
    required this.message,
  });

  final StyioToolchainLifecycleState state;
  final List<StyioToolchainRoleStatus> roles;
  final List<StyioToolchainRole> requiredRoles;
  final String message;

  bool get ready => state == StyioToolchainLifecycleState.ready;
  bool get actionable => state != StyioToolchainLifecycleState.ready;

  List<StyioToolchainRoleStatus> get missingRequiredRoles {
    return roles
        .where((role) => role.required && role.missing)
        .toList(growable: false);
  }

  List<StyioToolchainRoleStatus> get selectableRequiredRoles {
    return roles
        .where((role) => role.required && role.selectable)
        .toList(growable: false);
  }

  StyioToolchainRoleStatus? roleStatus(StyioToolchainRole role) {
    for (final status in roles) {
      if (status.role == role) {
        return status;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state.name,
      'message': message,
      'requiredRoles': requiredRoles
          .map((role) => role.wireValue)
          .toList(growable: false),
      'roleCount': roles.length,
      'missingRequiredRoleCount': missingRequiredRoles.length,
      'selectableRequiredRoleCount': selectableRequiredRoles.length,
      'roles': roles.map((role) => role.toJson()).toList(growable: false),
      'ready': ready,
      'actionable': actionable,
    };
  }
}

class StyioToolchainLifecycleManager {
  const StyioToolchainLifecycleManager({
    required ToolchainCatalog catalog,
    this.roles = StyioToolchainRole.values,
  }) : _catalog = catalog;

  static const List<StyioToolchainRole> defaultRequiredRoles =
      <StyioToolchainRole>[
        StyioToolchainRole.languageService,
        StyioToolchainRole.compiler,
        StyioToolchainRole.runner,
      ];

  final ToolchainCatalog _catalog;
  final List<StyioToolchainRole> roles;

  StyioToolchainLifecycleReport inspect({
    List<StyioToolchainRole> requiredRoles = defaultRequiredRoles,
  }) {
    final roleStatuses = roles
        .map(
          (role) =>
              _statusForRole(role, required: requiredRoles.contains(role)),
        )
        .toList(growable: false);
    final requiredStatuses = roleStatuses
        .where((status) => status.required)
        .toList(growable: false);
    final missingRequired = requiredStatuses
        .where((status) => status.missing)
        .toList(growable: false);
    final selectableRequired = requiredStatuses
        .where((status) => status.selectable)
        .toList(growable: false);
    if (missingRequired.isNotEmpty) {
      return StyioToolchainLifecycleReport(
        state: StyioToolchainLifecycleState.missing,
        roles: roleStatuses,
        requiredRoles: requiredRoles,
        message:
            'Styio toolchain is missing required roles: '
            '${missingRequired.map((status) => status.role.wireValue).join(', ')}.',
      );
    }
    if (selectableRequired.isNotEmpty) {
      return StyioToolchainLifecycleReport(
        state: StyioToolchainLifecycleState.selectable,
        roles: roleStatuses,
        requiredRoles: requiredRoles,
        message:
            'Styio toolchain has selectable roles that are not active: '
            '${selectableRequired.map((status) => status.role.wireValue).join(', ')}.',
      );
    }
    return StyioToolchainLifecycleReport(
      state: StyioToolchainLifecycleState.ready,
      roles: roleStatuses,
      requiredRoles: requiredRoles,
      message: 'Styio toolchain lifecycle is ready.',
    );
  }

  StyioToolchainLifecycleReport activateBestAvailable({
    List<StyioToolchainRole> requiredRoles = defaultRequiredRoles,
  }) {
    for (final role in requiredRoles) {
      final status = _statusForRole(role, required: true);
      if (status.ready || status.candidates.isEmpty) {
        continue;
      }
      _catalog.activate(status.candidates.first.id);
    }
    return inspect(requiredRoles: requiredRoles);
  }

  StyioToolchainRoleStatus _statusForRole(
    StyioToolchainRole role, {
    required bool required,
  }) {
    final active = _catalog.active(role.toolchainKind);
    final styioActive = active != null && _descriptorLooksLikeStyio(active)
        ? active
        : null;
    final candidates = _catalog
        .list(kind: role.toolchainKind)
        .where(_descriptorLooksLikeStyio)
        .toList(growable: false);
    if (styioActive != null) {
      return StyioToolchainRoleStatus(
        role: role,
        state: StyioToolchainRoleState.active,
        required: required,
        activeDescriptor: styioActive,
        candidates: candidates,
        message: 'Styio ${role.wireValue} is active.',
      );
    }
    if (candidates.isNotEmpty) {
      return StyioToolchainRoleStatus(
        role: role,
        state: StyioToolchainRoleState.available,
        required: required,
        candidates: candidates,
        message: 'Styio ${role.wireValue} is available but not active.',
      );
    }
    return StyioToolchainRoleStatus(
      role: role,
      state: StyioToolchainRoleState.missing,
      required: required,
      message: 'Styio ${role.wireValue} is missing.',
    );
  }
}

bool _descriptorLooksLikeStyio(ToolchainDescriptor descriptor) {
  final explicitLanguage = _metadataString(descriptor.metadata, 'language');
  final toolFamily = _metadataString(descriptor.metadata, 'toolFamily');
  final product = _metadataString(descriptor.metadata, 'product');
  if (_isStyioToken(explicitLanguage) ||
      _isStyioToken(toolFamily) ||
      _isStyioToken(product)) {
    return true;
  }
  return _isStyioToken(descriptor.id) || _isStyioToken(descriptor.displayName);
}

bool _isStyioToken(String? value) {
  return value != null && value.toLowerCase().contains('styio');
}

String? _metadataString(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}
