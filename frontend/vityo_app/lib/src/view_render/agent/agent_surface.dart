import 'dart:async';

import 'package:flutter/material.dart';

import '../../view_ide/backend_toolchain/adapter_contracts.dart';
import '../../view_ide/agent/agent.dart';
import '../../view_ide/module_host/module_definition.dart';
import '../../view_ide/module_host/module_manifest.dart';
import '../../view_ide/platform/platform_target.dart';
import '../native_tool_result_summary.dart';
import '../platform/viewport_profile.dart';

class AgentSurface extends StatelessWidget {
  const AgentSurface({
    super.key,
    required this.platformTarget,
    required this.viewportProfile,
    required this.visibleModules,
    required this.adapterCapabilities,
    required this.sessionContext,
    required this.codingController,
    required this.onApplyPendingPatch,
    required this.onSaveProviderProfile,
    this.onApplyIdeCommandSuggestion,
  });

  final PlatformTarget platformTarget;
  final ViewportProfile viewportProfile;
  final List<ModuleDefinition> visibleModules;
  final List<AdapterCapabilitySnapshot> adapterCapabilities;
  final AgentSessionContext sessionContext;
  final AgentCodingSessionController codingController;
  final Future<void> Function() onApplyPendingPatch;
  final Future<bool> Function(AgentIdeCommandSuggestion suggestion)?
  onApplyIdeCommandSuggestion;
  final Future<void> Function(AgentPromptProfile profile, {String? bearerToken})
  onSaveProviderProfile;

  @override
  Widget build(BuildContext context) {
    final agentModules = visibleModules
        .where(
          (module) => switch (module.manifest.slot) {
            ModuleSlot.agentSurface || ModuleSlot.cloudRuntime => true,
            _ => false,
          },
        )
        .toList(growable: false);
    final providerRoute = _providerRouteForPlatform(platformTarget);

    return Card(
      key: ValueKey('agent-surface-${viewportProfile.label.toLowerCase()}'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Agent Surface',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '${platformTarget.label} agent route aligned to the ${viewportProfile.label.toLowerCase()} shell.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              _AgentProviderProfileSection(
                controller: codingController,
                onSaveProviderProfile: onSaveProviderProfile,
              ),
              const SizedBox(height: 14),
              if (viewportProfile.isMobile) ...[
                _AgentSection(
                  title: 'Provider Route',
                  body:
                      '$providerRoute. Mobile and narrow Web keep the same provider contract, but compress the presentation into a single vertical stack.',
                  accent: const Color(0xFFE1E8F5),
                ),
                const SizedBox(height: 12),
                const _AgentSection(
                  title: 'Context Injection',
                  body:
                      'Current file, selection, diagnostics, and runtime context stay as separate injection channels for M6.',
                  accent: Color(0xFFEDE6D9),
                ),
                const SizedBox(height: 12),
                _AgentContextSection(context: sessionContext),
                const SizedBox(height: 12),
                _AgentSkillSection(context: sessionContext),
                const SizedBox(height: 12),
                _AgentPromptSection(
                  platformTarget: platformTarget,
                  controller: codingController,
                  sessionContext: sessionContext,
                  onApplyPendingPatch: onApplyPendingPatch,
                  onApplyIdeCommandSuggestion: onApplyIdeCommandSuggestion,
                ),
                const SizedBox(height: 12),
                _AdapterSection(adapterCapabilities: adapterCapabilities),
                const SizedBox(height: 12),
                _AgentModuleSection(modules: agentModules),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _AgentSection(
                        title: 'Provider Route',
                        body:
                            '$providerRoute. Desktop and wide Web keep the prompt/profile surface adjacent to runtime panels while sharing the same adapter contract.',
                        accent: const Color(0xFFE1E8F5),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: _AgentSection(
                        title: 'Context Injection',
                        body:
                            'Current file, selection, diagnostics, and runtime context remain independent channels so agent prompts do not collapse language-service boundaries.',
                        accent: Color(0xFFEDE6D9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _AgentContextSection(context: sessionContext),
                const SizedBox(height: 14),
                _AgentSkillSection(context: sessionContext),
                const SizedBox(height: 14),
                _AgentPromptSection(
                  platformTarget: platformTarget,
                  controller: codingController,
                  sessionContext: sessionContext,
                  onApplyPendingPatch: onApplyPendingPatch,
                  onApplyIdeCommandSuggestion: onApplyIdeCommandSuggestion,
                ),
                const SizedBox(height: 14),
                _AdapterSection(adapterCapabilities: adapterCapabilities),
                const SizedBox(height: 14),
                _AgentModuleSection(modules: agentModules),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentProviderProfileSection extends StatefulWidget {
  const _AgentProviderProfileSection({
    required this.controller,
    required this.onSaveProviderProfile,
  });

  final AgentCodingSessionController controller;
  final Future<void> Function(AgentPromptProfile profile, {String? bearerToken})
  onSaveProviderProfile;

  @override
  State<_AgentProviderProfileSection> createState() =>
      _AgentProviderProfileSectionState();
}

class _AgentProviderProfileSectionState
    extends State<_AgentProviderProfileSection> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _systemPromptController;
  late final TextEditingController _bearerTokenController;
  late Set<String> _contextChannels;
  late String _profileSignature;
  String? _failureSignature;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.profile;
    _displayNameController = TextEditingController(text: profile.displayName);
    _baseUrlController = TextEditingController(text: profile.endpoint.baseUrl);
    _modelController = TextEditingController(text: profile.endpoint.model);
    _systemPromptController = TextEditingController(text: profile.systemPrompt);
    _bearerTokenController = TextEditingController();
    _contextChannels = profile.contextChannels.toSet();
    _profileSignature = _profileSignatureFor(profile);
    _failureSignature = _failureSignatureFor(
      widget.controller.lastProviderFailure,
    );
    widget.controller.addListener(_syncFromController);
  }

  @override
  void didUpdateWidget(covariant _AgentProviderProfileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
      _setProfileFields(widget.controller.profile);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _displayNameController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _systemPromptController.dispose();
    _bearerTokenController.dispose();
    super.dispose();
  }

  void _syncFromController() {
    final profile = widget.controller.profile;
    final profileSignature = _profileSignatureFor(profile);
    final failureSignature = _failureSignatureFor(
      widget.controller.lastProviderFailure,
    );
    if (_profileSignature == profileSignature &&
        _failureSignature == failureSignature) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (_profileSignature != profileSignature) {
        _setProfileFields(profile);
        _errorMessage = null;
      }
      _failureSignature = failureSignature;
    });
  }

  void _setProfileFields(AgentPromptProfile profile) {
    _profileSignature = _profileSignatureFor(profile);
    _displayNameController.text = profile.displayName;
    _baseUrlController.text = profile.endpoint.baseUrl;
    _modelController.text = profile.endpoint.model;
    _systemPromptController.text = profile.systemPrompt;
    _bearerTokenController.clear();
    _contextChannels = profile.contextChannels.toSet();
  }

  String _profileSignatureFor(AgentPromptProfile profile) {
    return [
      profile.profileId,
      profile.displayName,
      profile.endpoint.baseUrl,
      profile.endpoint.model,
      profile.systemPrompt,
      ...profile.contextChannels,
    ].join('\n');
  }

  String? _failureSignatureFor(AgentProviderTransportException? failure) {
    if (failure == null) {
      return null;
    }
    return [
      failure.kind.name,
      failure.statusCode?.toString() ?? '',
      failure.message,
      failure.recoveryHint ?? '',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providerFailure = widget.controller.lastProviderFailure;
    return Container(
      key: const ValueKey('agent-provider-profile-section'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEF2),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Provider Profile', style: theme.textTheme.titleMedium),
          if (providerFailure != null) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('agent-provider-reconfiguration-guidance'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.28),
                ),
              ),
              child: Text(
                'Provider reconfiguration recommended: ${providerFailure.kind.name}. Review base URL, model, and bearer token, then save this provider profile.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('agent-profile-save-button'),
            onPressed: _saving ? null : _saveProfile,
            child: Text(_saving ? 'Saving...' : 'Save Provider Profile'),
          ),
          const SizedBox(height: 10),
          Text('Context channels', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final channel in AgentPromptProfile.defaultContextChannels)
                SizedBox(
                  width: 220,
                  child: GestureDetector(
                    key: ValueKey('agent-context-channel-$channel'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _saving
                        ? null
                        : () {
                            final selected = !_contextChannels.contains(
                              channel,
                            );
                            setState(() {
                              if (selected) {
                                _contextChannels.add(channel);
                              } else {
                                _contextChannels.remove(channel);
                              }
                            });
                          },
                    child: AbsorbPointer(
                      child: FilterChip(
                        label: Text(channel),
                        selected: _contextChannels.contains(channel),
                        onSelected: _saving ? null : (_) {},
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-display-name-input'),
            controller: _displayNameController,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-base-url-input'),
            controller: _baseUrlController,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'OpenAI-compatible base URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-model-input'),
            controller: _modelController,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Model',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-system-prompt-input'),
            controller: _systemPromptController,
            enabled: !_saving,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'System prompt',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-bearer-token-input'),
            controller: _bearerTokenController,
            enabled: !_saving,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Bearer token (optional)',
              helperText:
                  'Stored in Credential DataStore, not in profile JSON.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    if (baseUrl.isEmpty || model.isEmpty) {
      setState(() {
        _errorMessage = 'Base URL and model are required.';
      });
      return;
    }
    final endpointUri = Uri.tryParse(baseUrl);
    final isRootRelativePath =
        baseUrl.startsWith('/') && !baseUrl.startsWith('//');
    final isHttpUrl =
        endpointUri != null &&
        endpointUri.hasScheme &&
        (endpointUri.scheme == 'http' || endpointUri.scheme == 'https');
    if (!isRootRelativePath && !isHttpUrl) {
      setState(() {
        _errorMessage =
            'Base URL must be an http(s) URL or root-relative path.';
      });
      return;
    }
    if (_contextChannels.isEmpty) {
      setState(() {
        _errorMessage = 'At least one context channel is required.';
      });
      return;
    }

    final current = widget.controller.profile;
    final profile = AgentPromptProfile(
      profileId: current.profileId.startsWith('default-')
          ? 'configured-agent'
          : current.profileId,
      displayName: _displayNameController.text.trim().isEmpty
          ? 'Configured Agent'
          : _displayNameController.text.trim(),
      systemPrompt: _systemPromptController.text.trim().isEmpty
          ? current.systemPrompt
          : _systemPromptController.text.trim(),
      endpoint: AgentProviderEndpoint(
        route: current.endpoint.route,
        baseUrl: baseUrl,
        model: model,
        apiKeyEnvironmentName: current.endpoint.apiKeyEnvironmentName,
        protocol: current.endpoint.protocol,
        credentialReference: current.endpoint.credentialReference,
      ),
      contextChannels: _contextChannels.toList(growable: false),
    );

    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await widget.onSaveProviderProfile(
        profile,
        bearerToken: _bearerTokenController.text,
      );
      _bearerTokenController.clear();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = sanitizeAgentError(error.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}

Set<String> _registeredAgentCommandIds(AgentCommandCatalogContext commands) {
  return <String>{
    for (final command in commands.persistenceCommands) command.id,
    for (final command in commands.diagnosticCommands) command.id,
    for (final command in commands.languageServiceCommands) command.id,
    for (final command in commands.navigationCommands) command.id,
    for (final command in commands.refactorCommands) command.id,
    for (final command in commands.nativeToolCommands) command.id,
    for (final command in commands.debugCommands) command.id,
  };
}

Map<String, _AgentCommandReadinessStatus> _commandReadinessById(
  AgentCommandCatalogContext commands,
) {
  return <String, _AgentCommandReadinessStatus>{
    for (final readiness in commands.nativeToolCommandReadiness)
      readiness.commandId: _AgentCommandReadinessStatus(
        ready: readiness.ready,
        reason: readiness.reason,
        requiredCommandId: readiness.requiredCommandId,
      ),
    for (final readiness in commands.debugCommandReadiness)
      readiness.commandId: _AgentCommandReadinessStatus(
        ready: readiness.ready,
        reason: readiness.reason,
        requiredCommandId: readiness.requiredCommandId,
      ),
  };
}

class _AgentCommandReadinessStatus {
  const _AgentCommandReadinessStatus({
    required this.ready,
    required this.reason,
    this.requiredCommandId,
  });

  final bool ready;
  final String reason;
  final String? requiredCommandId;
}

class _AgentIdeCommandSuggestionRow extends StatelessWidget {
  const _AgentIdeCommandSuggestionRow({
    required this.command,
    required this.registered,
    required this.readiness,
    required this.requiredCommandRegistered,
    required this.applying,
    required this.onApply,
    required this.onApplyRequiredCommand,
  });

  final AgentIdeCommandSuggestion command;
  final bool registered;
  final _AgentCommandReadinessStatus? readiness;
  final bool requiredCommandRegistered;
  final bool applying;
  final VoidCallback? onApply;
  final VoidCallback? onApplyRequiredCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commandReady = readiness?.ready ?? true;
    final requiredCommandId = readiness?.requiredCommandId;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${command.commandId}${command.input == null ? '' : ' · input ${command.input}'}${command.reason.isEmpty ? '' : ' · ${command.reason}'}',
          style: theme.textTheme.bodySmall,
        ),
        if (!registered)
          Text(
            'Unsupported command',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (!commandReady)
          Text(
            'Command not ready: ${readiness!.reason}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (onApply != null)
          OutlinedButton(
            key: ValueKey('agent-apply-command-${command.commandId}'),
            onPressed: applying ? null : onApply,
            child: Text(applying ? 'Applying Command...' : 'Apply Command'),
          ),
        if (!commandReady &&
            requiredCommandId != null &&
            requiredCommandRegistered &&
            onApplyRequiredCommand != null)
          OutlinedButton(
            key: ValueKey(
              'agent-apply-required-command-${command.commandId}-$requiredCommandId',
            ),
            onPressed: applying ? null : onApplyRequiredCommand,
            child: Text(
              applying ? 'Applying Command...' : 'Apply Required Command',
            ),
          ),
      ],
    );
  }
}

class _AgentPromptSection extends StatefulWidget {
  const _AgentPromptSection({
    required this.platformTarget,
    required this.controller,
    required this.sessionContext,
    required this.onApplyPendingPatch,
    this.onApplyIdeCommandSuggestion,
  });

  final PlatformTarget platformTarget;
  final AgentCodingSessionController controller;
  final AgentSessionContext sessionContext;
  final Future<void> Function() onApplyPendingPatch;
  final Future<bool> Function(AgentIdeCommandSuggestion suggestion)?
  onApplyIdeCommandSuggestion;

  @override
  State<_AgentPromptSection> createState() => _AgentPromptSectionState();
}

class _AgentPromptSectionState extends State<_AgentPromptSection> {
  late final TextEditingController _promptController;
  bool _applyingPatch = false;
  bool _applyingIdeCommand = false;
  String? _lastCommandApplicationMessage;
  AgentIdeCommandSuggestion? _lastRetryableCommandSuggestion;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(
      text: widget.controller.draftPrompt,
    );
    widget.controller.addListener(_syncPromptFromController);
  }

  @override
  void didUpdateWidget(covariant _AgentPromptSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncPromptFromController);
      widget.controller.addListener(_syncPromptFromController);
      _setPromptText(widget.controller.draftPrompt);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncPromptFromController);
    _promptController.dispose();
    super.dispose();
  }

  void _syncPromptFromController() {
    final draftPrompt = widget.controller.draftPrompt;
    if (_promptController.text == draftPrompt) {
      return;
    }
    _setPromptText(draftPrompt);
  }

  void _setPromptText(String value) {
    _promptController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _applyPendingPatch() async {
    if (_applyingPatch) {
      return;
    }
    setState(() {
      _applyingPatch = true;
    });
    try {
      await widget.onApplyPendingPatch();
    } on Object catch (error) {
      widget.controller.recordPatchApplicationError(error);
    } finally {
      if (mounted) {
        setState(() {
          _applyingPatch = false;
        });
      }
    }
  }

  Future<void> _applyIdeCommandSuggestion(
    AgentIdeCommandSuggestion command,
  ) async {
    if (_applyingIdeCommand) {
      return;
    }
    final callback = widget.onApplyIdeCommandSuggestion;
    if (callback == null) {
      return;
    }
    setState(() {
      _applyingIdeCommand = true;
      if (command.prerequisiteForCommandId == null) {
        _lastRetryableCommandSuggestion = null;
      }
    });
    try {
      final applied = await callback(command);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastCommandApplicationMessage = applied
            ? _appliedIdeCommandMessage(command)
            : 'Command ${command.commandId} was not applied.';
        _lastRetryableCommandSuggestion =
            applied && command.prerequisiteForCommandId != null
            ? AgentIdeCommandSuggestion(
                commandId: command.prerequisiteForCommandId!,
                reason: 'Retry after ${command.commandId}.',
              )
            : null;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastCommandApplicationMessage = 'Command ${command.commandId} failed.';
        _lastRetryableCommandSuggestion = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _applyingIdeCommand = false;
        });
      }
    }
  }

  String _appliedIdeCommandMessage(AgentIdeCommandSuggestion command) {
    final prerequisiteForCommandId = command.prerequisiteForCommandId;
    if (prerequisiteForCommandId == null) {
      return 'Command ${command.commandId} applied.';
    }
    return 'Command ${command.commandId} applied. '
        '$prerequisiteForCommandId may now be retried.';
  }

  AgentRequestAttachment _activeDocumentAttachment() {
    final document = widget.sessionContext.document;
    return AgentRequestAttachment(
      attachmentId:
          'document:${document.documentId}:${document.revision}:${document.textStart}:${document.textEnd}',
      kind: 'document',
      name: document.documentId.isEmpty
          ? 'active document'
          : document.documentId,
      content: document.text,
      metadata: <String, Object?>{
        'documentId': document.documentId,
        'revision': document.revision,
        'textStart': document.textStart,
        'textEnd': document.textEnd,
      },
    );
  }

  AgentRequestAttachment _selectionAttachment() {
    final document = widget.sessionContext.document;
    final selection = widget.sessionContext.selection;
    return AgentRequestAttachment(
      attachmentId:
          'selection:${document.documentId}:${document.revision}:${selection.start}:${selection.end}',
      kind: 'selection',
      name: document.documentId.isEmpty
          ? 'active selection'
          : '${document.documentId} selection',
      content: selection.selectedText,
      metadata: <String, Object?>{
        'documentId': document.documentId,
        'revision': document.revision,
        'selectionStart': selection.start,
        'selectionEnd': selection.end,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final controller = widget.controller;
        final response = controller.lastResponse;
        final responseText = response?.contentParts
            .map((part) => part.text)
            .where((text) => text.isNotEmpty)
            .join('\n\n');
        final commandSuggestions =
            response?.contentParts
                .map((part) => part.ideCommand)
                .whereType<AgentIdeCommandSuggestion>()
                .toList(growable: false) ??
            const <AgentIdeCommandSuggestion>[];
        final registeredCommandIds = _registeredAgentCommandIds(
          widget.sessionContext.commands,
        );
        final commandReadiness = _commandReadinessById(
          widget.sessionContext.commands,
        );
        final recentCommandResults =
            widget.sessionContext.commands.recentResults;
        final patch = controller.pendingPatch;
        final patchResult = controller.lastPatchApplicationResult;
        final inactiveDirtyPatchTargets = patch == null
            ? const <String>[]
            : _inactiveDirtyPatchTargets(patch, widget.sessionContext);
        final activeFileOperationTargets = patch == null
            ? const <String>[]
            : _activeFileOperationTargets(patch, widget.sessionContext);
        final conversationTurns = controller.conversationTurns;
        final attachments = controller.attachments;
        final applyingPatch = _applyingPatch || controller.applyingPatch;
        final canApplyPendingPatch =
            !applyingPatch &&
            inactiveDirtyPatchTargets.isEmpty &&
            activeFileOperationTargets.isEmpty;
        final canAttachActiveDocument =
            !controller.sending &&
            !applyingPatch &&
            widget.sessionContext.document.text.trim().isNotEmpty;
        final selectedText = widget.sessionContext.selection.selectedText;
        final canAttachSelection =
            !controller.sending &&
            !applyingPatch &&
            selectedText.trim().isNotEmpty;
        final canClearConversationState =
            conversationTurns.isNotEmpty ||
            response != null ||
            patchResult != null ||
            controller.lastError != null ||
            controller.lastProviderFailure != null;

        return Container(
          key: const ValueKey('agent-prompt-section'),
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF1E9D8),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Coding Agent', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(controller.profile.displayName)),
                  Chip(label: Text(controller.providerKind.wireValue)),
                  Chip(label: Text(controller.adapter.adapterId)),
                  Chip(
                    label: Text(
                      controller.providerSupportsCodePatch
                          ? 'code patch'
                          : 'text only',
                    ),
                  ),
                ],
              ),
              if (controller.providerMountMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  controller.providerMountMessage!,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('agent-prompt-input'),
                controller: _promptController,
                minLines: 2,
                maxLines: 5,
                enabled: !controller.sending,
                decoration: const InputDecoration(
                  labelText: 'Prompt',
                  hintText:
                      'Ask the agent to explain, edit, or refactor the current context.',
                  border: OutlineInputBorder(),
                ),
                onChanged: controller.updatePrompt,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const ValueKey('agent-attach-active-document-button'),
                    onPressed: canAttachActiveDocument
                        ? () => controller.addAttachment(
                            _activeDocumentAttachment(),
                          )
                        : null,
                    child: const Text('Attach Active File'),
                  ),
                  if (!widget.sessionContext.selection.isCollapsed)
                    OutlinedButton(
                      key: const ValueKey('agent-attach-selection-button'),
                      onPressed: canAttachSelection
                          ? () =>
                                controller.addAttachment(_selectionAttachment())
                          : null,
                      child: const Text('Attach Selection'),
                    ),
                ],
              ),
              if (attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Attachments', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final attachment in attachments)
                      Chip(
                        label: Text('${attachment.name} · ${attachment.kind}'),
                        onDeleted: controller.sending
                            ? null
                            : () => controller.removeAttachment(
                                attachment.attachmentId,
                              ),
                        deleteButtonTooltipMessage: 'Remove ${attachment.name}',
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton(
                    onPressed: controller.canSend && !applyingPatch
                        ? () => unawaited(controller.sendPrompt())
                        : null,
                    child: Text(controller.sending ? 'Sending...' : 'Send'),
                  ),
                  if (controller.sending)
                    OutlinedButton(
                      onPressed: controller.cancelActiveRequest,
                      child: const Text('Cancel'),
                    ),
                  if (patch != null) ...[
                    FilledButton.tonal(
                      onPressed: canApplyPendingPatch
                          ? () => unawaited(_applyPendingPatch())
                          : null,
                      child: Text(
                        applyingPatch ? 'Applying Patch...' : 'Apply Patch',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: applyingPatch
                          ? null
                          : controller.clearPendingPatch,
                      child: const Text('Dismiss Patch'),
                    ),
                  ],
                  if (canClearConversationState)
                    OutlinedButton(
                      onPressed: applyingPatch
                          ? null
                          : controller.clearConversation,
                      child: const Text('Clear Conversation'),
                    ),
                ],
              ),
              if (conversationTurns.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Conversation', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final turn
                    in conversationTurns.length > 4
                        ? conversationTurns.sublist(
                            conversationTurns.length - 4,
                          )
                        : conversationTurns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${turn.role.wireValue}: ${turn.text}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              if (controller.lastError != null) ...[
                const SizedBox(height: 10),
                Text(
                  controller.lastError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                if (controller.lastProviderFailure != null) ...[
                  _AgentProviderFailureDetails(
                    failure: controller.lastProviderFailure!,
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton(
                    key: const ValueKey('agent-provider-retry-button'),
                    onPressed: controller.canSend
                        ? () => unawaited(controller.sendPrompt())
                        : null,
                    child: const Text('Retry Provider Request'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('agent-provider-local-fallback-button'),
                    onPressed: controller.sending || applyingPatch
                        ? null
                        : () => controller.mountProvider(
                            profile: AgentPromptProfile.defaultForPlatform(
                              widget.platformTarget,
                            ),
                            adapter: const LocalOnlyAgentProviderAdapter(),
                            message:
                                'Cloud agent provider disabled; using local fallback.',
                          ),
                    child: const Text('Use Local Fallback'),
                  ),
                ],
              ],
              if (responseText != null && responseText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(responseText, style: theme.textTheme.bodySmall),
              ],
              if (commandSuggestions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Suggested IDE Commands',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                for (final command in commandSuggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Builder(
                      builder: (context) {
                        final readiness = commandReadiness[command.commandId];
                        final requiredCommandId = readiness?.requiredCommandId;
                        return _AgentIdeCommandSuggestionRow(
                          command: command,
                          registered: registeredCommandIds.contains(
                            command.commandId,
                          ),
                          readiness: readiness,
                          requiredCommandRegistered:
                              requiredCommandId != null &&
                              registeredCommandIds.contains(requiredCommandId),
                          applying: _applyingIdeCommand,
                          onApply:
                              widget.onApplyIdeCommandSuggestion == null ||
                                  readiness?.ready == false
                              ? null
                              : () => unawaited(
                                  _applyIdeCommandSuggestion(command),
                                ),
                          onApplyRequiredCommand:
                              widget.onApplyIdeCommandSuggestion == null ||
                                  requiredCommandId == null ||
                                  !registeredCommandIds.contains(
                                    requiredCommandId,
                                  )
                              ? null
                              : () => unawaited(
                                  _applyIdeCommandSuggestion(
                                    AgentIdeCommandSuggestion(
                                      commandId: requiredCommandId,
                                      prerequisiteForCommandId:
                                          command.commandId,
                                      reason:
                                          'Required before ${command.commandId}.',
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
              ],
              if (_lastCommandApplicationMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  _lastCommandApplicationMessage!,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_lastRetryableCommandSuggestion != null) ...[
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  key: ValueKey(
                    'agent-retry-original-command-'
                    '${_lastRetryableCommandSuggestion!.commandId}',
                  ),
                  onPressed: _applyingIdeCommand
                      ? null
                      : () => unawaited(
                          _applyIdeCommandSuggestion(
                            _lastRetryableCommandSuggestion!,
                          ),
                        ),
                  icon: const Icon(Icons.replay),
                  label: const Text('Retry Original Command'),
                ),
              ],
              if (recentCommandResults.isNotEmpty) ...[
                const SizedBox(height: 10),
                _AgentRecentIdeCommandsSection(
                  results: recentCommandResults,
                  registeredCommandIds: registeredCommandIds,
                  commandReadiness: commandReadiness,
                  applying: _applyingIdeCommand,
                  onRetry: widget.onApplyIdeCommandSuggestion == null
                      ? null
                      : (result) => unawaited(
                          _applyIdeCommandSuggestion(
                            AgentIdeCommandSuggestion(
                              commandId: result.commandId,
                              input: result.input,
                              reason: 'Retry recent ${result.commandId}.',
                            ),
                          ),
                        ),
                  onApplyRequiredCommand:
                      widget.onApplyIdeCommandSuggestion == null
                      ? null
                      : (result, requiredCommandId) => unawaited(
                          _applyIdeCommandSuggestion(
                            AgentIdeCommandSuggestion(
                              commandId: requiredCommandId,
                              prerequisiteForCommandId: result.commandId,
                              reason:
                                  'Required before retrying ${result.commandId}.',
                            ),
                          ),
                        ),
                ),
              ],
              if (patch != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Pending patch: ${patch.summary} (${patch.edits.length} edit(s))',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'Patch ${patch.patchId}${patch.baseRevision == null ? '' : ' · base rev ${patch.baseRevision}'}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                for (final edit in patch.edits.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${edit.operation.wireValue} ${edit.documentId}:${edit.start}-${edit.end} -> ${edit.replacementText.length} char(s)',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (patch.edits.length > 5)
                  Text(
                    '+ ${patch.edits.length - 5} more edit(s) hidden from preview',
                    style: theme.textTheme.bodySmall,
                  ),
                if (inactiveDirtyPatchTargets.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Patch blocked: dirty inactive files ${_documentListSummary(inactiveDirtyPatchTargets)}. Switch to those files and save or discard local changes first.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (activeFileOperationTargets.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Patch blocked: file create/delete targets the active document ${_documentListSummary(activeFileOperationTargets)}. Use replace edits for the active editor document.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
              if (patchResult != null) ...[
                const SizedBox(height: 10),
                Text(patchResult.message, style: theme.textTheme.bodySmall),
                if (patchResult.appliedDocumentIds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Changed files: ${_documentListSummary(patchResult.appliedDocumentIds)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (patchResult.createdDocumentIds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Created files: ${_documentListSummary(patchResult.createdDocumentIds)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (patchResult.deletedDocumentIds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Deleted files: ${_documentListSummary(patchResult.deletedDocumentIds)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

String _documentListSummary(List<String> documentIds) {
  final visibleDocumentIds = documentIds.take(5).join(', ');
  final hiddenCount = documentIds.length - 5;
  if (hiddenCount <= 0) {
    return visibleDocumentIds;
  }
  return '$visibleDocumentIds, + $hiddenCount more';
}

List<String> _inactiveDirtyPatchTargets(
  AgentCodePatch patch,
  AgentSessionContext context,
) {
  final activeDocumentIds = <String>{
    context.document.documentId,
    context.workspace.activeFilePath,
  };
  final dirtyDocumentIds = context.workspace.dirtyDocumentIds.toSet();
  final targets = <String>[];
  for (final edit in patch.edits) {
    if (activeDocumentIds.contains(edit.documentId) ||
        !dirtyDocumentIds.contains(edit.documentId) ||
        targets.contains(edit.documentId)) {
      continue;
    }
    targets.add(edit.documentId);
  }
  return targets;
}

List<String> _activeFileOperationTargets(
  AgentCodePatch patch,
  AgentSessionContext context,
) {
  final activeDocumentIds = <String>{
    context.document.documentId,
    context.workspace.activeFilePath,
  };
  final targets = <String>[];
  for (final edit in patch.edits) {
    if (edit.operation == AgentCodePatchEditOperation.replace ||
        !activeDocumentIds.contains(edit.documentId) ||
        targets.contains(edit.documentId)) {
      continue;
    }
    targets.add(edit.documentId);
  }
  return targets;
}

class _AgentProviderFailureDetails extends StatelessWidget {
  const _AgentProviderFailureDetails({required this.failure});

  final AgentProviderTransportException failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle =
        theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ) ??
        TextStyle(color: theme.colorScheme.onErrorContainer);
    return Container(
      key: const ValueKey('agent-provider-failure-details'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: DefaultTextStyle(
        style: textStyle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Provider failure kind: ${failure.kind.name}'),
            if (failure.statusCode != null)
              Text('HTTP status: ${failure.statusCode}'),
            if (failure.recoveryHint != null)
              Text('Recovery: ${failure.recoveryHint}'),
          ],
        ),
      ),
    );
  }
}

class _AgentRecentIdeCommandsSection extends StatelessWidget {
  const _AgentRecentIdeCommandsSection({
    required this.results,
    required this.registeredCommandIds,
    required this.commandReadiness,
    required this.applying,
    this.onRetry,
    this.onApplyRequiredCommand,
  });

  final List<AgentCommandResultContext> results;
  final Set<String> registeredCommandIds;
  final Map<String, _AgentCommandReadinessStatus> commandReadiness;
  final bool applying;
  final void Function(AgentCommandResultContext result)? onRetry;
  final void Function(
    AgentCommandResultContext result,
    String requiredCommandId,
  )?
  onApplyRequiredCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleResults = results.take(5).toList(growable: false);
    return Column(
      key: const ValueKey('agent-recent-ide-commands-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent IDE Commands', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        for (var index = 0; index < visibleResults.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Builder(
              builder: (context) {
                final result = visibleResults[index];
                final readiness = commandReadiness[result.commandId];
                final commandReady = readiness?.ready ?? true;
                final requiredCommandId = readiness?.requiredCommandId;
                final metadataSummary = nativeToolMetadataSummaryText(
                  result.metadata,
                );
                return Column(
                  key: ValueKey(
                    'agent-recent-ide-command-${result.commandId}-$index',
                  ),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${result.commandId} · '
                            '${result.applied ? 'applied' : 'not applied'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (onRetry != null &&
                            commandReady &&
                            registeredCommandIds.contains(result.commandId))
                          OutlinedButton(
                            key: ValueKey(
                              'agent-retry-recent-command-'
                              '${result.commandId}-$index',
                            ),
                            onPressed: applying ? null : () => onRetry!(result),
                            child: const Text('Retry Command'),
                          ),
                        if (!commandReady &&
                            requiredCommandId != null &&
                            registeredCommandIds.contains(requiredCommandId) &&
                            onApplyRequiredCommand != null)
                          OutlinedButton(
                            key: ValueKey(
                              'agent-retry-recent-required-command-'
                              '${result.commandId}-$requiredCommandId-$index',
                            ),
                            onPressed: applying
                                ? null
                                : () => onApplyRequiredCommand!(
                                    result,
                                    requiredCommandId,
                                  ),
                            child: const Text('Apply Required Command'),
                          ),
                      ],
                    ),
                    if (!commandReady)
                      Text(
                        'Retry not ready: ${readiness!.reason}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    if (result.completedAt != null)
                      Text(
                        'Completed ${result.completedAt!.toUtc().toIso8601String()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (result.message.isNotEmpty)
                      Text(
                        result.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (metadataSummary != null)
                      Text(
                        metadataSummary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        if (results.length > visibleResults.length)
          Text(
            '+ ${results.length - visibleResults.length} older command(s)',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _AgentContextSection extends StatelessWidget {
  const _AgentContextSection({required this.context});

  final AgentSessionContext context;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionContext = this.context;
    final selectedText = sessionContext.selection.selectedText;
    final resolvedElement = sessionContext.language.resolvedElement;
    final resolvedReference = sessionContext.language.resolvedReference;
    final languageFactLabel = _agentLanguageFactLabel(
      resolvedElement: resolvedElement,
      resolvedReference: resolvedReference,
      semanticSpanCount: sessionContext.language.semanticSpanCount,
    );
    final selectionLabel = sessionContext.selection.isCollapsed
        ? 'caret ${sessionContext.selection.start}'
        : 'selection ${sessionContext.selection.start}-${sessionContext.selection.end}';
    final runtimeLabel = sessionContext.runtime.hasSession
        ? '${sessionContext.runtime.kind} ${sessionContext.runtime.status}'
        : 'no runtime session';

    return Container(
      key: const ValueKey('agent-session-context-section'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0E5),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('IDE Context', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(sessionContext.document.documentId)),
              Chip(label: Text('rev ${sessionContext.document.revision}')),
              Chip(label: Text(sessionContext.workspace.activeFilePath)),
              Chip(
                label: Text(
                  '${sessionContext.workspace.fileCount} workspace file(s)',
                ),
              ),
              Chip(label: Text(selectionLabel)),
              if (languageFactLabel != null)
                Chip(label: Text(languageFactLabel)),
              Chip(
                label: Text(
                  '${sessionContext.diagnostics.length} diagnostic(s)',
                ),
              ),
              Chip(label: Text(runtimeLabel)),
            ],
          ),
          if (selectedText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              sessionContext.selection.selectedTextTruncated
                  ? '$selectedText...'
                  : selectedText,
              style: theme.textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

String? _agentLanguageFactLabel({
  required AgentResolvedElementContext? resolvedElement,
  required AgentResolvedReferenceContext? resolvedReference,
  required int semanticSpanCount,
}) {
  final parts = <String>[];
  if (resolvedElement != null) {
    parts.add('resolved ${resolvedElement.name}/${resolvedElement.kind}');
  }
  if (resolvedReference != null) {
    parts.add('ref ${resolvedReference.access}');
  }
  if (semanticSpanCount > 0) {
    parts.add('$semanticSpanCount semantic');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

class _AgentSkillSection extends StatelessWidget {
  const _AgentSkillSection({required this.context});

  final AgentSessionContext context;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skills = this.context.skills;
    final activeSkillIds = skills.activeSkillIds.toSet();
    final activeSkills = skills.skills
        .where((skill) => activeSkillIds.contains(skill.skillId))
        .toList(growable: false);

    return Container(
      key: const ValueKey('agent-active-skills-section'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFEDE8F1),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Active Coding Skills', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '${skills.activeSkillCount} active / ${skills.skillCount} available skills',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (activeSkills.isEmpty)
            Text(
              'No workspace-activated coding skills are available for this context.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final skill in activeSkills.take(8))
                  Tooltip(
                    message: skill.skillId,
                    child: Chip(
                      key: ValueKey('agent-active-skill-${skill.skillId}'),
                      label: Text(skill.title),
                    ),
                  ),
              ],
            ),
          if (activeSkills.length > 8) ...[
            const SizedBox(height: 8),
            Text(
              '+ ${activeSkills.length - 8} more active skill(s)',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (skills.activationReasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final skill in activeSkills.take(3))
              if ((skills.activationReasons[skill.skillId] ?? const <String>[])
                  .isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${skill.title}: ${skills.activationReasons[skill.skillId]!.join(' ')}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _AgentSection extends StatelessWidget {
  const _AgentSection({
    required this.title,
    required this.body,
    required this.accent,
  });

  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AdapterSection extends StatelessWidget {
  const _AdapterSection({required this.adapterCapabilities});

  final List<AdapterCapabilitySnapshot> adapterCapabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF6),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Adapter Routes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final snapshot in adapterCapabilities)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '${snapshot.adapterKind.label}: language ${snapshot.languageService.level.label}, execution ${snapshot.execution.level.label}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _AgentModuleSection extends StatelessWidget {
  const _AgentModuleSection({required this.modules});

  final List<ModuleDefinition> modules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2E9),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mounted Adapters And Slots',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (modules.isEmpty)
            Text(
              'No agent adapter modules are visible for this target.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: modules
                  .map(
                    (module) => Chip(label: Text(module.manifest.displayName)),
                  )
                  .toList(growable: false),
            ),
          const SizedBox(height: 12),
          Text(
            'Local agent runtime stays external; iOS keeps the cloud route as the compliance floor.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _providerRouteForPlatform(PlatformTarget platformTarget) {
  switch (platformTarget) {
    case PlatformTarget.ios:
      return 'Cloud-only OpenAI-compatible provider route';
    case PlatformTarget.web:
      return 'Hosted provider route with cloud profile sync';
    case PlatformTarget.android:
      return 'Cloud provider route with optional local bridge slot';
    case PlatformTarget.windows:
    case PlatformTarget.linux:
    case PlatformTarget.macos:
      return 'Desktop provider route with local bridge reservation';
    case PlatformTarget.unknown:
      return 'Provider route pending platform resolution';
  }
}
