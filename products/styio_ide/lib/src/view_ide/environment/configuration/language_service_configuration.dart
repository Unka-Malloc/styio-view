class LanguageServiceConfiguration {
  const LanguageServiceConfiguration({this.allowLocalFallback = true});

  final bool allowLocalFallback;

  factory LanguageServiceConfiguration.fromJson(Map<String, Object?> json) {
    return LanguageServiceConfiguration(
      allowLocalFallback: json['allowLocalFallback'] as bool? ?? true,
    );
  }

  LanguageServiceConfiguration copyWith({bool? allowLocalFallback}) {
    return LanguageServiceConfiguration(
      allowLocalFallback: allowLocalFallback ?? this.allowLocalFallback,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': 1,
      'allowLocalFallback': allowLocalFallback,
    };
  }
}
