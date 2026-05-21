enum AgentProviderKind {
  cloudOpenAICompatible,
  localBridge,
  localOnlyFallback,
}

extension AgentProviderKindX on AgentProviderKind {
  String get wireValue {
    switch (this) {
      case AgentProviderKind.cloudOpenAICompatible:
        return 'cloud_openai_compatible';
      case AgentProviderKind.localBridge:
        return 'local_bridge';
      case AgentProviderKind.localOnlyFallback:
        return 'local_only_fallback';
    }
  }
}
