class StyioSyntaxContract {
  const StyioSyntaxContract({
    required this.id,
    required this.version,
    required this.delimiterPairs,
    required this.reportUnknownTokens,
    required this.reportUnterminatedStrings,
    required this.reportUnterminatedBlockComments,
  });

  static const current = StyioSyntaxContract(
    id: 'vityo-ide-syntax',
    version: '2026.05.ide',
    delimiterPairs: {'(': ')', '[': ']', '{': '}'},
    reportUnknownTokens: true,
    reportUnterminatedStrings: true,
    reportUnterminatedBlockComments: true,
  );

  final String id;
  final String version;
  final Map<String, String> delimiterPairs;
  final bool reportUnknownTokens;
  final bool reportUnterminatedStrings;
  final bool reportUnterminatedBlockComments;

  factory StyioSyntaxContract.fromJson(Map<String, dynamic> json) {
    final diagnostics = json['diagnostics'] is Map<String, dynamic>
        ? json['diagnostics'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final delimiterPairs = json['delimiterPairs'] is Map<String, dynamic>
        ? (json['delimiterPairs'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(key, '$value'),
          )
        : StyioSyntaxContract.current.delimiterPairs;

    return StyioSyntaxContract(
      id: json['id'] as String? ?? StyioSyntaxContract.current.id,
      version:
          json['version'] as String? ?? StyioSyntaxContract.current.version,
      delimiterPairs: delimiterPairs,
      reportUnknownTokens:
          diagnostics['unknownToken'] as bool? ??
          StyioSyntaxContract.current.reportUnknownTokens,
      reportUnterminatedStrings:
          diagnostics['unterminatedString'] as bool? ??
          StyioSyntaxContract.current.reportUnterminatedStrings,
      reportUnterminatedBlockComments:
          diagnostics['unterminatedBlockComment'] as bool? ??
          StyioSyntaxContract.current.reportUnterminatedBlockComments,
    );
  }
}
