class AndroidRuntimePackageArtifact {
  const AndroidRuntimePackageArtifact({
    required this.artifactId,
    required this.sizeBytes,
    this.moduleIds = const <String>[],
  });

  final String artifactId;
  final int sizeBytes;
  final List<String> moduleIds;
}

enum AndroidRuntimePackageBudgetStatus {
  withinBudget,
  overBudget,
  invalidArtifact,
}

class AndroidRuntimePackageBudgetResult {
  const AndroidRuntimePackageBudgetResult({
    required this.status,
    required this.artifact,
    required this.maxBytes,
  });

  final AndroidRuntimePackageBudgetStatus status;
  final AndroidRuntimePackageArtifact artifact;
  final int maxBytes;

  bool get passed => status == AndroidRuntimePackageBudgetStatus.withinBudget;

  int get excessBytes {
    final excess = artifact.sizeBytes - maxBytes;
    return excess > 0 ? excess : 0;
  }
}

class AndroidRuntimePackageBudgetGate {
  const AndroidRuntimePackageBudgetGate({
    this.maxBytes = defaultMaxBytes,
  });

  static const int defaultMaxBytes = 50 * 1024 * 1024;

  final int maxBytes;

  AndroidRuntimePackageBudgetResult evaluate(
    AndroidRuntimePackageArtifact artifact,
  ) {
    if (artifact.artifactId.trim().isEmpty || artifact.sizeBytes < 0) {
      return AndroidRuntimePackageBudgetResult(
        status: AndroidRuntimePackageBudgetStatus.invalidArtifact,
        artifact: artifact,
        maxBytes: maxBytes,
      );
    }
    return AndroidRuntimePackageBudgetResult(
      status: artifact.sizeBytes <= maxBytes
          ? AndroidRuntimePackageBudgetStatus.withinBudget
          : AndroidRuntimePackageBudgetStatus.overBudget,
      artifact: artifact,
      maxBytes: maxBytes,
    );
  }
}
