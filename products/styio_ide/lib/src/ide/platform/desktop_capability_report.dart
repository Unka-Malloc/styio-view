import 'dart:collection';

final class DesktopCapabilityReport {
  DesktopCapabilityReport({
    required this.platform,
    required this.commit,
    required this.sourceFingerprint,
    required this.artifactVerified,
    required this.launched,
    required this.workspaceOpened,
    required Map<String, String> capabilities,
  }) : capabilities = UnmodifiableMapView<String, String>(
         Map<String, String>.of(capabilities),
       ) {
    if (!RegExp(r'^[0-9a-f]{40,64}$').hasMatch(commit)) {
      throw ArgumentError.value(commit, 'commit', 'invalid source commit');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceFingerprint)) {
      throw ArgumentError.value(
        sourceFingerprint,
        'sourceFingerprint',
        'invalid source fingerprint',
      );
    }
  }

  final String platform;
  final String commit;
  final String sourceFingerprint;
  final bool artifactVerified;
  final bool launched;
  final bool workspaceOpened;
  final Map<String, String> capabilities;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': 1,
    'platform': platform,
    'commit': commit,
    'source_fingerprint': sourceFingerprint,
    'artifact_verified': artifactVerified,
    'launched': launched,
    'workspace_opened': workspaceOpened,
    'capabilities': capabilities,
  };
}
