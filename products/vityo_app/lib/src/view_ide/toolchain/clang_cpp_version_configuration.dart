enum CppLanguageStandard {
  cpp14(cmakeValue: '14', compilerFlag: '-std=c++14'),
  cpp17(cmakeValue: '17', compilerFlag: '-std=c++17'),
  cpp20(cmakeValue: '20', compilerFlag: '-std=c++20'),
  cpp23(cmakeValue: '23', compilerFlag: '-std=c++23'),
  cpp26(cmakeValue: '26', compilerFlag: '-std=c++26');

  const CppLanguageStandard({
    required this.cmakeValue,
    required this.compilerFlag,
  });

  final String cmakeValue;
  final String compilerFlag;

  static CppLanguageStandard? fromWireValue(Object? value) {
    final normalized = _stringValue(value);
    if (normalized == null) {
      return null;
    }
    for (final standard in CppLanguageStandard.values) {
      if (standard.cmakeValue == normalized ||
          standard.compilerFlag == normalized ||
          standard.name == normalized ||
          'c++${standard.cmakeValue}' == normalized) {
        return standard;
      }
    }
    return null;
  }
}

class ClangCppVersionPreference {
  const ClangCppVersionPreference({
    this.versionId,
    this.cppStandard = CppLanguageStandard.cpp20,
  });

  factory ClangCppVersionPreference.fromJson(Map<String, Object?> json) {
    return ClangCppVersionPreference(
      versionId: _stringValue(json['versionId']),
      cppStandard:
          CppLanguageStandard.fromWireValue(json['cppStandard']) ??
          CppLanguageStandard.cpp20,
    );
  }

  final String? versionId;
  final CppLanguageStandard cppStandard;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (versionId != null) 'versionId': versionId,
      'cppStandard': cppStandard.cmakeValue,
      'cppCompilerFlag': cppStandard.compilerFlag,
    };
  }
}

String? _stringValue(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
