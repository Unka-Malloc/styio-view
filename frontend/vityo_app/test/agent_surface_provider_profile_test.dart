import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_registry.dart';
import 'package:vityo_app/src/agent/agent_provider_route_executor.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/agent/agent_prompt_profile_store.dart';
import 'package:vityo_app/src/view_ide/environment/configuration/configuration.dart';
import 'package:vityo_app/src/view_render/agent/agent_surface.dart';
import 'package:vityo_app/src/view_render/platform/viewport_profile.dart';

Future<void> _tapProfileControl(WidgetTester tester, Finder finder) async {
  tester.testTextInput.hide();
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pump();
  final widget = tester.widget<Widget>(finder);
  if (widget is FilledButton) {
    widget.onPressed?.call();
    return;
  }
  if (widget is GestureDetector) {
    widget.onTap?.call();
    return;
  }
  await tester.tap(finder);
}

void main() {
  testWidgets('agent surface saves provider profile from profile form', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    AgentPromptProfile? savedProfile;
    String? savedBearerToken;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: AgentSurface(
              platformTarget: PlatformTarget.web,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 900,
              ),
              visibleModules: const [],
              adapterCapabilities: const [],
              sessionContext: _context(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {
                savedProfile = profile;
                savedBearerToken = bearerToken;
                controller.mountProvider(
                  profile: profile,
                  adapter: const LocalOnlyAgentProviderAdapter(),
                  message: 'saved',
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-display-name-input')),
      'Cloud Agent',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-base-url-input')),
      'https://agent.example.test/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-model-input')),
      'gpt-test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-fallback-base-url-input')),
      'https://fallback-agent.example.test/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-fallback-model-input')),
      'gpt-fallback-test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-system-prompt-input')),
      'Use Vityo IDE context.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-bearer-token-input')),
      'test-token',
    );
    await _tapProfileControl(
      tester,
      find.byKey(const ValueKey('agent-context-channel-runtime')),
    );
    await _tapProfileControl(
      tester,
      find.byKey(const ValueKey('agent-profile-save-button')),
    );
    await tester.pump();

    expect(savedProfile?.profileId, 'configured-agent');
    expect(savedProfile?.displayName, 'Cloud Agent');
    expect(savedProfile?.endpoint.baseUrl, 'https://agent.example.test/v1');
    expect(savedProfile?.endpoint.model, 'gpt-test');
    expect(savedProfile?.endpoint.requiresCredential, isTrue);
    expect(savedProfile?.fallbackEndpoints, hasLength(1));
    expect(
      savedProfile?.fallbackEndpoints.single.baseUrl,
      'https://fallback-agent.example.test/v1',
    );
    expect(savedProfile?.fallbackEndpoints.single.model, 'gpt-fallback-test');
    expect(savedProfile?.fallbackEndpoints.single.requiresCredential, isTrue);
    expect(savedProfile?.systemPrompt, 'Use Vityo IDE context.');
    expect(savedProfile?.contextChannels, isNot(contains('runtime')));
    expect(savedBearerToken, 'test-token');
  });

  testWidgets(
    'agent surface applies OpenAI Codex Spark preset and preserves contract',
    (tester) async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      AgentPromptProfile? savedProfile;
      String? savedBearerToken;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 900,
              child: AgentSurface(
                platformTarget: PlatformTarget.web,
                viewportProfile: const ViewportProfile(
                  family: ViewportFamily.desktop,
                  width: 1200,
                  height: 900,
                ),
                visibleModules: const [],
                adapterCapabilities: const [],
                sessionContext: _context(),
                codingController: controller,
                onApplyPendingPatch: () async {},
                onSaveProviderProfile: (profile, {bearerToken}) async {
                  savedProfile = profile;
                  savedBearerToken = bearerToken;
                },
              ),
            ),
          ),
        ),
      );

      await _tapProfileControl(
        tester,
        find.byKey(const ValueKey('agent-profile-codex-spark-preset-button')),
      );
      await tester.pump();

      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('agent-profile-display-name-input')),
            )
            .controller
            ?.text,
        'Web OpenAI Codex Spark',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('agent-profile-base-url-input')),
            )
            .controller
            ?.text,
        'https://api.openai.com/v1',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('agent-profile-model-input')),
            )
            .controller
            ?.text,
        'gpt-5.3-codex-spark',
      );
      expect(
        find.textContaining('OpenAI API key or bearer token'),
        findsOneWidget,
      );
      expect(
        find.textContaining('user:agent.provider:openai-api-key'),
        findsOneWidget,
      );
      expect(find.textContaining('does not read Codex OAuth'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('agent-profile-bearer-token-input')),
        'spark-token',
      );
      await _tapProfileControl(
        tester,
        find.byKey(const ValueKey('agent-profile-save-button')),
      );
      await tester.pump();

      expect(savedProfile?.profileId, 'openai-codex-spark-web');
      expect(savedProfile?.endpoint.model, 'gpt-5.3-codex-spark');
      expect(savedProfile?.endpoint.protocol, 'openai-responses');
      expect(savedProfile?.endpoint.reasoningEffort, 'high');
      expect(savedProfile?.endpoint.requiresCredential, isTrue);
      expect(
        savedProfile?.endpoint.credentialReference?.key.namespace,
        'agent.provider',
      );
      expect(
        savedProfile?.endpoint.credentialReference?.key.name,
        'openai-api-key',
      );
      expect(
        savedProfile?.endpoint.credentialReference?.kind,
        CredentialKind.remoteServiceCredential,
      );
      expect(savedBearerToken, 'spark-token');
    },
  );

  testWidgets('agent surface renders provider execution resolution', (
    tester,
  ) async {
    const resolution = AgentProviderExecutionResolution(
      profileId: 'configured-agent',
      status: AgentProviderExecutionResolutionStatus.fallbackReady,
      selectedEndpointIndex: 1,
      endpoints: <AgentProviderEndpointReadiness>[
        AgentProviderEndpointReadiness(
          endpointIndex: 0,
          fallback: false,
          endpoint: AgentProviderEndpoint(
            route: AgentProviderRoute.webHosted,
            baseUrl: 'https://primary-agent.example.test/v1',
            model: 'gpt-primary',
            requiresCredential: true,
          ),
          plan: AgentProviderExecutionPlan(
            routeKind: AgentProviderExecutionRouteKind.cloud,
            providerKind: AgentProviderKind.cloudOpenAICompatible,
            route: AgentProviderRoute.webHosted,
            endpointBaseUrl: 'https://primary-agent.example.test/v1',
          ),
          credentialReadiness: AgentProviderCredentialReadiness.unavailable,
        ),
        AgentProviderEndpointReadiness(
          endpointIndex: 1,
          fallback: true,
          endpoint: AgentProviderEndpoint(
            route: AgentProviderRoute.webHosted,
            baseUrl: 'https://agent.example.test/v1',
            model: 'gpt-cloud',
          ),
          plan: AgentProviderExecutionPlan(
            routeKind: AgentProviderExecutionRouteKind.cloud,
            providerKind: AgentProviderKind.cloudOpenAICompatible,
            route: AgentProviderRoute.webHosted,
            endpointBaseUrl: 'https://agent.example.test/v1',
          ),
          credentialReadiness: AgentProviderCredentialReadiness.available,
        ),
      ],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      providerExecutionResolution: resolution,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: AgentSurface(
              platformTarget: PlatformTarget.web,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 900,
              ),
              visibleModules: const [],
              adapterCapabilities: const [],
              sessionContext: _context(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent-provider-execution-status')),
      findsOneWidget,
    );
    expect(find.text('Execution status: fallback_ready'), findsOneWidget);
    expect(
      find.textContaining(
        'Selected fallback cloud endpoint: https://agent.example.test/v1',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-provider-execution-endpoint-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('agent-provider-execution-credential-guidance'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-provider-execution-endpoint-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-provider-promote-fallback-button')),
      findsOneWidget,
    );

    await _tapProfileControl(
      tester,
      find.byKey(const ValueKey('agent-provider-promote-fallback-button')),
    );
    await tester.pump();

    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('agent-profile-base-url-input')),
          )
          .controller
          ?.text,
      'https://agent.example.test/v1',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('agent-profile-model-input')),
          )
          .controller
          ?.text,
      'gpt-cloud',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('agent-profile-fallback-base-url-input')),
          )
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('agent surface renders coding readiness provider blockers', (
    tester,
  ) async {
    const resolution = AgentProviderExecutionResolution(
      profileId: 'blocked-provider',
      status: AgentProviderExecutionResolutionStatus.blocked,
      endpoints: <AgentProviderEndpointReadiness>[],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      providerExecutionResolution: resolution,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: AgentSurface(
              platformTarget: PlatformTarget.web,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 900,
              ),
              visibleModules: const [],
              adapterCapabilities: const [],
              sessionContext: _context(providerExecutionResolution: resolution),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Execution readiness: blocked'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
          'agent-coding-readiness-issue-agent.provider.route.blocked',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('agent.provider.route.blocked'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-autonomy-policy-status')),
      findsOneWidget,
    );
    expect(find.text('Autonomy policy: blocked'), findsOneWidget);
    expect(
      find.text('Agent coding is blocked by readiness or change review gate.'),
      findsOneWidget,
    );
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send'),
    );
    expect(sendButton.onPressed, isNull);
  });

  testWidgets('agent surface renders provider selection plan', (tester) async {
    const selectionPlan = AgentProviderSelectionPlan(
      status: AgentProviderSelectionStatus.ready,
      route: AgentProviderRoute.webHosted,
      protocol: 'openai-compatible',
      requiresCredential: true,
      credentialReadiness: AgentProviderCredentialReadiness.available,
      executionStatus: AgentProviderExecutionResolutionStatus.ready,
      selectedEndpointIndex: 0,
      selectedProvider: AgentProviderRegistrationManifest(
        providerId: 'cloud',
        displayName: 'Cloud Provider',
        kind: AgentProviderKind.cloudOpenAICompatible,
        priority: 10,
        supportsCodePatch: true,
        supportedRoutes: <String>['web-hosted'],
        supportedProtocols: <String>['openai-compatible'],
        capabilities: <String>['plan', 'code_patch'],
      ),
      candidates: <AgentProviderRegistrationManifest>[
        AgentProviderRegistrationManifest(
          providerId: 'cloud',
          displayName: 'Cloud Provider',
          kind: AgentProviderKind.cloudOpenAICompatible,
          priority: 10,
          supportsCodePatch: true,
          supportedRoutes: <String>['web-hosted'],
          supportedProtocols: <String>['openai-compatible'],
          capabilities: <String>['plan', 'code_patch'],
        ),
      ],
      todo: 'Resolve credential before sending.',
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      providerSelectionPlan: selectionPlan,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: AgentSurface(
              platformTarget: PlatformTarget.web,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 900,
              ),
              visibleModules: const [],
              adapterCapabilities: const [],
              sessionContext: _context(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent-provider-selection-status')),
      findsOneWidget,
    );
    expect(find.text('Provider selection: ready'), findsOneWidget);
    expect(
      find.text('Selected provider Cloud Provider (cloud).'),
      findsOneWidget,
    );
    expect(find.text('Candidate providers: 1'), findsOneWidget);
    expect(find.text('Executable: true'), findsOneWidget);
    expect(find.text('Credential readiness: available'), findsOneWidget);
    expect(find.text('Execution status: ready'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-provider-selection-credential')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-provider-selection-todo')),
      findsOneWidget,
    );
  });

  testWidgets(
    'agent surface rejects provider profile without context channels',
    (tester) async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      var saveCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 900,
              child: AgentSurface(
                platformTarget: PlatformTarget.web,
                viewportProfile: const ViewportProfile(
                  family: ViewportFamily.desktop,
                  width: 1200,
                  height: 900,
                ),
                visibleModules: const [],
                adapterCapabilities: const [],
                sessionContext: _context(),
                codingController: controller,
                onApplyPendingPatch: () async {},
                onSaveProviderProfile: (profile, {bearerToken}) async {
                  saveCalled = true;
                },
              ),
            ),
          ),
        ),
      );

      for (final channel in AgentPromptProfile.defaultContextChannels) {
        await _tapProfileControl(
          tester,
          find.byKey(ValueKey('agent-context-channel-$channel')),
        );
      }
      await _tapProfileControl(
        tester,
        find.byKey(const ValueKey('agent-profile-save-button')),
      );
      await tester.pump();

      expect(saveCalled, isFalse);
      expect(
        find.text('At least one context channel is required.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('agent surface rejects provider profile with invalid base URL', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    var saveCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: AgentSurface(
              platformTarget: PlatformTarget.web,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 900,
              ),
              visibleModules: const [],
              adapterCapabilities: const [],
              sessionContext: _context(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {
                saveCalled = true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-base-url-input')),
      'not a url',
    );
    await _tapProfileControl(
      tester,
      find.byKey(const ValueKey('agent-profile-save-button')),
    );
    await tester.pump();

    expect(saveCalled, isFalse);
    expect(
      find.text('Base URL must be an http(s) URL or root-relative path.'),
      findsOneWidget,
    );
  });

  testWidgets('agent surface accepts root-relative provider base URL', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    AgentPromptProfile? savedProfile;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: AgentSurface(
              platformTarget: PlatformTarget.web,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 900,
              ),
              visibleModules: const [],
              adapterCapabilities: const [],
              sessionContext: _context(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {
                savedProfile = profile;
              },
            ),
          ),
        ),
      ),
    );

    await _tapProfileControl(
      tester,
      find.byKey(const ValueKey('agent-profile-save-button')),
    );
    await tester.pump();

    expect(savedProfile?.endpoint.baseUrl, '/api/styio-agent/v1');
  });

  testWidgets('agent surface redacts provider profile save errors', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: AgentSurface(
              platformTarget: PlatformTarget.web,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 900,
              ),
              visibleModules: const [],
              adapterCapabilities: const [],
              sessionContext: _context(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {
                throw StateError('save failed Bearer secret-token');
              },
            ),
          ),
        ),
      ),
    );

    await _tapProfileControl(
      tester,
      find.byKey(const ValueKey('agent-profile-save-button')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Bearer [redacted]'), findsOneWidget);
    expect(find.textContaining('secret-token'), findsNothing);
  });

  testWidgets('agent surface renders saved provider profiles and mounts by key', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    String? mountedProfileKey;
    const savedProfiles = <AgentPromptProfileManifestEntry>[
      AgentPromptProfileManifestEntry(
        key: 'agent.provider.openai-codex-spark-web',
        profileId: 'openai-codex-spark-web',
        displayName: 'Saved Codex Spark',
        route: 'web-hosted',
        protocol: 'openai-responses',
        model: 'gpt-5.3-codex-spark',
        requiresCredential: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: AgentSurface(
              platformTarget: PlatformTarget.web,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 900,
              ),
              visibleModules: const [],
              adapterCapabilities: const [],
              sessionContext: _context(savedProviderProfiles: savedProfiles),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {},
              onMountSavedProviderProfile: (profileKey) async {
                mountedProfileKey = profileKey;
              },
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent-saved-provider-profiles')),
      findsOneWidget,
    );
    expect(find.text('Saved provider profiles (1)'), findsOneWidget);
    expect(find.text('Saved Codex Spark'), findsOneWidget);
    expect(
      find.text('gpt-5.3-codex-spark / openai-responses / web-hosted'),
      findsOneWidget,
    );
    expect(find.text('credential required'), findsOneWidget);

    await _tapProfileControl(
      tester,
      find.byKey(
        const ValueKey(
          'agent-saved-provider-profile-mount-agent.provider.openai-codex-spark-web',
        ),
      ),
    );
    await tester.pump();

    expect(mountedProfileKey, 'agent.provider.openai-codex-spark-web');
  });

  testWidgets('agent provider profile form follows mounted provider changes', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: AgentSurface(
              platformTarget: PlatformTarget.web,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 900,
              ),
              visibleModules: const [],
              adapterCapabilities: const [],
              sessionContext: _context(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-bearer-token-input')),
      'old-token',
    );
    controller.mountProvider(
      profile: const AgentPromptProfile(
        profileId: 'mounted-cloud',
        displayName: 'Mounted Cloud',
        systemPrompt: 'Mounted prompt.',
        endpoint: AgentProviderEndpoint(
          route: AgentProviderRoute.webHosted,
          baseUrl: 'https://mounted.example.test/v1',
          model: 'mounted-model',
        ),
      ),
      adapter: const LocalOnlyAgentProviderAdapter(),
    );
    await tester.pump();

    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('agent-profile-display-name-input')),
          )
          .controller
          ?.text,
      'Mounted Cloud',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('agent-profile-base-url-input')),
          )
          .controller
          ?.text,
      'https://mounted.example.test/v1',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('agent-profile-model-input')),
          )
          .controller
          ?.text,
      'mounted-model',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('agent-profile-bearer-token-input')),
          )
          .controller
          ?.text,
      '',
    );
  });
}

AgentSessionContext _context({
  Iterable<AgentPromptProfileManifestEntry> savedProviderProfiles =
      const <AgentPromptProfileManifestEntry>[],
  AgentProviderExecutionResolution? providerExecutionResolution,
}) {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: '',
      revision: 0,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
    savedProviderProfiles: savedProviderProfiles,
    providerExecutionResolution: providerExecutionResolution,
  );
}
