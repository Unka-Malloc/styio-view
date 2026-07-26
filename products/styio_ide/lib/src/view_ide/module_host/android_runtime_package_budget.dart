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
  const AndroidRuntimePackageBudgetGate({this.maxBytes = defaultMaxBytes});

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

/// Combined validation result for Android runtime package size and capability route.
enum AndroidRuntimeCapabilityRouteStatus {
  /// Package within budget and a viable local execution route exists.
  packageReadyRouteLive,

  /// Package within budget but the local execution route is blocked or has no
  /// fallback; the product should warn the user.
  packageReadyRouteBlocked,

  /// Package exceeds budget regardless of capability route.
  packageOverBudget,

  /// Package exceeds budget, but a cloud fallback route exists.
  packageOverBudgetWithFallback,

  /// Package artifact is invalid (missing id or negative size).
  invalidInput,
}

/// Combined validation that checks an Android runtime package budget result
/// together with whether a viable capability route exists for local-first
/// execution. This ensures product tests validate both dimensions at once.
class AndroidRuntimeCapabilityRouteJointGate {
  const AndroidRuntimeCapabilityRouteJointGate();

  AndroidRuntimeCapabilityRouteStatus evaluate({
    required AndroidRuntimePackageBudgetResult budgetResult,
    required bool hasLocalExecutionRoute,
    required bool hasCloudFallbackRoute,
  }) {
    if (!budgetResult.passed &&
        budgetResult.status ==
            AndroidRuntimePackageBudgetStatus.invalidArtifact) {
      return AndroidRuntimeCapabilityRouteStatus.invalidInput;
    }

    if (!budgetResult.passed) {
      // Package is over budget. If a cloud fallback exists, this is still
      // problematic but less blocking.
      return hasCloudFallbackRoute
          ? AndroidRuntimeCapabilityRouteStatus.packageOverBudgetWithFallback
          : AndroidRuntimeCapabilityRouteStatus.packageOverBudget;
    }

    // Package within budget; now check capability route.
    if (hasLocalExecutionRoute) {
      return AndroidRuntimeCapabilityRouteStatus.packageReadyRouteLive;
    }

    return AndroidRuntimeCapabilityRouteStatus.packageReadyRouteBlocked;
  }
}
