class ClangCppVersionFacts {
  const ClangCppVersionFacts({
    required this.version,
    required this.vendor,
    required this.versionLine,
  });

  final String version;
  final String vendor;
  final String versionLine;

  static ClangCppVersionFacts? parse(String output) {
    return parseClangCppVersionOutput(output);
  }

  Map<String, Object?> toMetadata({
    String source = 'clang++ --version',
  }) {
    return <String, Object?>{
      'clangVersion': version,
      'clangVendor': vendor,
      'clangVersionSource': source,
      'clangVersionOutputFirstLine': versionLine,
    };
  }
}

ClangCppVersionFacts? parseClangCppVersionOutput(String? output) {
  if (output == null || output.trim().isEmpty) {
    return null;
  }
  final versionLine = output
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .cast<String?>()
      .firstWhere((line) => line != null, orElse: () => null);
  if (versionLine == null) {
    return null;
  }
  final versionMatch = RegExp(
    r'\bclang version\s+([0-9]+(?:\.[0-9]+)*(?:[-+][A-Za-z0-9_.-]+)?)',
    caseSensitive: false,
  ).firstMatch(versionLine);
  final version = versionMatch?.group(1);
  if (version == null || version.isEmpty) {
    return null;
  }
  return ClangCppVersionFacts(
    version: version,
    vendor: _clangVersionVendor(versionLine),
    versionLine: versionLine,
  );
}

String _clangVersionVendor(String versionLine) {
  final vendorMatch = RegExp(
    r'^([A-Za-z][A-Za-z0-9_.+-]*)\s+clang version\b',
    caseSensitive: false,
  ).firstMatch(versionLine);
  final vendor = vendorMatch?.group(1);
  if (vendor != null && vendor.toLowerCase() != 'clang') {
    return vendor.toLowerCase();
  }
  return 'llvm';
}
