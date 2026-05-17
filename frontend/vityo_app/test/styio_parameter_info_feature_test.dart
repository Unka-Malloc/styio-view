import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_parameter_info_feature.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';

void main() {
  DocumentState fixtureDocument() {
    final source = File(
      'test/fixtures/language_service/parameter_info.false.styio',
    ).readAsStringSync();
    return DocumentState(
      documentId: 'fixture://parameter_info',
      text: source,
      revision: 1,
    );
  }

  test('builds local fallback parameter info from fixture', () {
    final document = fixtureDocument();
    final offset = document.text.lastIndexOf('tax)') + 1;

    final info = const StyioParameterInfoFeature().parameterInfoAt(
      document: document,
      offset: offset,
    );

    expect(info?.callableName, 'blend');
    expect(info?.signature, 'fn blend(left: f64, right: f64 = 0.0)');
    expect(info?.activeParameterIndex, 1);
    expect(info?.activeParameter?.name, 'right');
    expect(info?.activeParameter?.defaultValue, '0.0');
    expect(info?.activeParameter?.documentation, 'Tax component to add.');
  });

  test('local language service exposes parameter info feature', () {
    final document = fixtureDocument();
    final offset = document.text.lastIndexOf('price,') + 1;

    final info = const LocalStyioLanguageService().parameterInfoAt(
      document,
      offset,
    );

    expect(info?.callableName, 'blend');
    expect(info?.activeParameterIndex, 0);
    expect(info?.activeParameter?.name, 'left');
  });
}
