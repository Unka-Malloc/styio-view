enum StyioServiceCapability {
  analysis,
  syntax,
  diagnostics,
  completion,
  hover,
  semanticTokens,
  formatting,
  semanticBlocks,
  inlayHints,
  documentSymbols,
  references,
  definition,
  codeActions,
  rename,
  safeDelete,
  inlineVariable,
  introduceVariable,
  extractFunction,
  changeSignature,
  parameterInfo,
  surround,
}

extension StyioServiceCapabilityX on StyioServiceCapability {
  String get wireValue => switch (this) {
    StyioServiceCapability.analysis => 'analysis',
    StyioServiceCapability.syntax => 'syntax',
    StyioServiceCapability.diagnostics => 'diagnostics',
    StyioServiceCapability.completion => 'completion',
    StyioServiceCapability.hover => 'hover',
    StyioServiceCapability.semanticTokens => 'semantic-tokens',
    StyioServiceCapability.formatting => 'formatting',
    StyioServiceCapability.semanticBlocks => 'semantic-blocks',
    StyioServiceCapability.inlayHints => 'inlay-hints',
    StyioServiceCapability.documentSymbols => 'document-symbols',
    StyioServiceCapability.references => 'references',
    StyioServiceCapability.definition => 'definition',
    StyioServiceCapability.codeActions => 'code-actions',
    StyioServiceCapability.rename => 'rename',
    StyioServiceCapability.safeDelete => 'safe-delete',
    StyioServiceCapability.inlineVariable => 'inline-variable',
    StyioServiceCapability.introduceVariable => 'introduce-variable',
    StyioServiceCapability.extractFunction => 'extract-function',
    StyioServiceCapability.changeSignature => 'change-signature',
    StyioServiceCapability.parameterInfo => 'parameter-info',
    StyioServiceCapability.surround => 'surround',
  };
}

StyioServiceCapability? styioServiceCapabilityFromWireValue(String value) {
  final normalized = _normalizedStyioServiceCapabilityKey(value);
  if (normalized.isEmpty) {
    return null;
  }
  for (final capability in StyioServiceCapability.values) {
    if (_normalizedStyioServiceCapabilityKey(capability.wireValue) ==
            normalized ||
        _normalizedStyioServiceCapabilityKey(capability.name) == normalized) {
      return capability;
    }
  }
  return null;
}

String normalizeStyioServiceCapabilityKey(String value) {
  return styioServiceCapabilityFromWireValue(value)?.wireValue ?? value.trim();
}

String? lookupStyioServiceCapabilityValue(
  Map<String, String> values,
  StyioServiceCapability capability,
) {
  return values[capability.wireValue] ??
      values[capability.name] ??
      _lookupNormalizedStyioServiceCapabilityValue(values, capability);
}

String? _lookupNormalizedStyioServiceCapabilityValue(
  Map<String, String> values,
  StyioServiceCapability capability,
) {
  for (final entry in values.entries) {
    if (styioServiceCapabilityFromWireValue(entry.key) == capability) {
      return entry.value;
    }
  }
  return null;
}

String _normalizedStyioServiceCapabilityKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
