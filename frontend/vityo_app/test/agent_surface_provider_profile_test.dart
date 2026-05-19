import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_route_executor.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
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
    expect(savedProfile?.systemPrompt, 'Use Vityo IDE context.');
    expect(savedProfile?.contextChannels, isNot(contains('runtime')));
    expect(savedBearerToken, 'test-token');
  });

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
            route: AgentProviderRoute.desktopLocalBridge,
            baseUrl: 'http://127.0.0.1:11434/v1',
            model: 'gpt-local',
          ),
          plan: AgentProviderExecutionPlan(
            routeKind: AgentProviderExecutionRouteKind.blocked,
            providerKind: AgentProviderKind.localOnlyFallback,
            route: AgentProviderRoute.desktopLocalBridge,
            endpointBaseUrl: 'http://127.0.0.1:11434/v1',
            blockReason:
                AgentProviderExecutionBlockReason.localBridgeUnavailable,
          ),
          credentialReadiness: AgentProviderCredentialReadiness.notReferenced,
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
      find.byKey(const ValueKey('agent-provider-execution-endpoint-1')),
      findsOneWidget,
    );
  });

  testWidgets('agent surface rejects provider profile without context channels', (
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
    expect(find.text('At least one context channel is required.'), findsOneWidget);
  });

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
      tester.widget<TextFormField>(
        find.byKey(const ValueKey('agent-profile-display-name-input')),
      ).controller?.text,
      'Mounted Cloud',
    );
    expect(
      tester.widget<TextFormField>(
        find.byKey(const ValueKey('agent-profile-base-url-input')),
      ).controller?.text,
      'https://mounted.example.test/v1',
    );
    expect(
      tester.widget<TextFormField>(
        find.byKey(const ValueKey('agent-profile-model-input')),
      ).controller?.text,
      'mounted-model',
    );
    expect(
      tester.widget<TextFormField>(
        find.byKey(const ValueKey('agent-profile-bearer-token-input')),
      ).controller?.text,
      '',
    );
  });
}

AgentSessionContext _context() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: '',
      revision: 0,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
  );
}
