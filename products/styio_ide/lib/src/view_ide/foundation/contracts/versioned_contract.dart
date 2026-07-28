/// Foundation helper for versioned public contract models.
///
/// Every public contract type that crosses the Vityo machine boundary
/// (fromJson + toJson) must include:
///   - `schemaVersion` (default 1)
///   - `extensions` map to preserve unknown fields across schema evolution
///
/// This helper provides:
///   - [vityoContractSchemaVersion] — canonical schema version constant
///   - [collectUnknownFields] — extract fields not in the known-key set
library;

/// Canonical schema version for Vityo public contracts.
const int vityoContractSchemaVersion = 1;

/// Collects unknown fields from [json] by excluding [knownKeys].
///
/// Unknown fields are preserved in the `extensions` map so that
/// forward-compatible consumers can round-trip data they don't yet
/// understand.
///
/// Example:
/// ```dart
/// static const _knownKeys = {'schemaVersion', 'name', 'value'};
///
/// factory MyPayload.fromJson(Map<String, Object?> json) {
///   return MyPayload(
///     schemaVersion: json['schemaVersion'] as int? ?? vityoContractSchemaVersion,
///     extensions: collectUnknownFields(json, _knownKeys),
///     name: json['name'] as String? ?? '',
///     value: json['value'] as int? ?? 0,
///   );
/// }
/// ```
Map<String, Object?> collectUnknownFields(
  Map<String, Object?> json,
  Set<String> knownKeys,
) {
  return {
    for (final entry in json.entries)
      if (!knownKeys.contains(entry.key)) entry.key: entry.value,
  };
}
