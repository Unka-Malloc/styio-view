import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/language_contract.dart';
import 'package:vityo_app/src/view_ide/services/symbol_index/symbol_index.dart';

void main() {
  test('workspace SymbolIndex supports prefix and reference queries', () {
    const index = SymbolIndex();
    final snapshot = index.build(_loadSymbolFixtureDocuments());

    final computeMatches = snapshot.queryPrefix('compute');
    expect(computeMatches.map((symbol) => symbol.name), <String>[
      'computeTotal',
    ]);
    expect(computeMatches.single.kind, SymbolKind.function);

    final computeReferences = snapshot.referencesForSymbol(
      computeMatches.single.id,
    );
    expect(computeReferences.length, 2);
    expect(
      computeReferences.any(
        (reference) =>
            reference.filePath == 'core.styio' && reference.isDeclaration,
      ),
      isTrue,
    );
    expect(
      computeReferences.any(
        (reference) =>
            reference.filePath == 'app.styio' &&
            !reference.isDeclaration &&
            reference.access == ReferenceAccess.read,
      ),
      isTrue,
    );

    final resultMatches = snapshot.queryPrefix('res');
    expect(resultMatches.single.name, 'result');
    expect(snapshot.referencesForName('result'), hasLength(2));
  });
}

List<SymbolIndexDocument> _loadSymbolFixtureDocuments() {
  final root = Directory('test/fixtures/symbol_index');
  return root
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.styio'))
      .map(
        (file) => SymbolIndexDocument(
          path: file.uri.pathSegments.last,
          source: file.readAsStringSync(),
        ),
      )
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
}

