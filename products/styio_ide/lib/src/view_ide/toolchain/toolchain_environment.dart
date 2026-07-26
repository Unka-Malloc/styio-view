import '../environment/configuration/environment_variable_configuration.dart';
import '../environment/system_compatibility/platform_context/platform_context_model.dart';

class ToolchainEnvironmentBuilder {
  const ToolchainEnvironmentBuilder({
    this.resolver = const EnvironmentVariableResolver(),
    this.inheritedEnvironment = const <String, String>{},
    this.pathSeparator = ':',
  });

  factory ToolchainEnvironmentBuilder.fromPlatformContext(
    PlatformContextSnapshot context, {
    EnvironmentVariableResolver resolver = const EnvironmentVariableResolver(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
  }) {
    return ToolchainEnvironmentBuilder(
      resolver: resolver,
      inheritedEnvironment: inheritedEnvironment,
      pathSeparator: pathListSeparatorForPlatformContext(context),
    );
  }

  final EnvironmentVariableResolver resolver;
  final Map<String, String> inheritedEnvironment;
  final String pathSeparator;

  static String pathListSeparatorForPlatformContext(
    PlatformContextSnapshot context,
  ) {
    return context.environmentPathListSeparator;
  }

  Map<String, String> build({
    Iterable<EnvironmentVariableOverlay> overlays =
        const <EnvironmentVariableOverlay>[],
    Map<String, String> runtimeOverrides = const <String, String>{},
  }) {
    return resolver.resolve(
      inherited: inheritedEnvironment,
      overlays: overlays,
      runtimeOverrides: runtimeOverrides,
      pathSeparator: pathSeparator,
    );
  }
}
