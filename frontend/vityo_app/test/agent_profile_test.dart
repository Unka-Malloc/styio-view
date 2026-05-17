import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test(
    'agent prompt profile preserves OpenAI-compatible endpoint contract',
    () {
      final profile = AgentPromptProfile.defaultForPlatform(
        PlatformTarget.macos,
      );
      final decoded = AgentPromptProfile.fromJson(profile.toJson());

      expect(decoded.profileId, 'default-macos');
      expect(decoded.endpoint.protocol, 'openai-compatible');
      expect(decoded.endpoint.route, AgentProviderRoute.desktopLocalBridge);
      expect(decoded.allowsLocalBridge, isTrue);
      expect(
        decoded.contextChannels,
        containsAll(<String>['file', 'selection', 'diagnostics', 'runtime']),
      );
    },
  );

  test('agent provider route keeps iOS cloud-only and Web hosted', () {
    final ios = AgentPromptProfile.defaultForPlatform(PlatformTarget.ios);
    final web = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final android = AgentPromptProfile.defaultForPlatform(
      PlatformTarget.android,
    );

    expect(ios.endpoint.route, AgentProviderRoute.iosCloudOnly);
    expect(ios.allowsLocalBridge, isFalse);
    expect(web.endpoint.route, AgentProviderRoute.webHosted);
    expect(web.endpoint.baseUrl, '/api/styio-agent/v1');
    expect(android.endpoint.route.allowsLocalBridge, isTrue);
  });
}
