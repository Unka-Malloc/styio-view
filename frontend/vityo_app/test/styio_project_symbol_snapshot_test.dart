import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';

void main() {
  test('exposes a stable project symbol snapshot contract', () {
    const service = ProjectStyioLanguageService();
    final analysis = service.analyzeProject(const [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@prices : f64|..2| := {}
load = ||> { <| 42 }

fn blend(left: f64, right: f64, scale: f64 = 1.0): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { styio/core }
@import { lib/runtime }
value = blend(1.0, 2.0)
''',
        revision: 0,
      ),
    ]);

    final snapshot = analysis.symbolSnapshot;

    expect(
      snapshot.importTargetsFor('main.styio'),
      equals(['styio/core', 'lib/runtime']),
    );
    expect(snapshot.resourcesFor('lib/runtime.styio').single.name, 'prices');
    expect(snapshot.resourcesFor('lib/runtime.styio').single.type, 'f64');
    expect(snapshot.tasksFor('lib/runtime.styio').single.name, 'load');
    expect(snapshot.tasksFor('lib/runtime.styio').single.returnType, 'i64');

    final function = snapshot.functionsFor('lib/runtime.styio').single;
    expect(function.name, 'blend');
    expect(function.returnType, 'f64');
    expect(function.requiredParameterCount, 2);
    expect(function.parameterCount, 3);
    expect(function.parameters.last.hasDefault, isTrue);
  });

  test('returns read-only project symbol snapshot lists', () {
    const service = ProjectStyioLanguageService();
    final snapshot = service.analyzeProject(const [
      DocumentState(
        documentId: 'main.styio',
        text: '@import { styio/core }\n',
        revision: 0,
      ),
    ]).symbolSnapshot;

    expect(
      () => snapshot.importTargetsFor('main.styio').add('other'),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot
          .functionsFor('main.styio')
          .add(
            const StyioFunctionSignature(
              name: 'extra',
              returnType: null,
              parameters: [],
            ),
          ),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot
          .resourcesFor('main.styio')
          .add(
            const StyioResourceSymbol(
              name: 'extra',
              type: 'i64',
              range: SourceRange(start: 0, end: 0),
            ),
          ),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot
          .tasksFor('main.styio')
          .add(
            const StyioTaskSymbol(
              name: 'extra',
              returnType: null,
              range: SourceRange(start: 0, end: 0),
            ),
          ),
      throwsUnsupportedError,
    );
  });

  test('does not extract project symbols from strings and comments', () {
    const service = ProjectStyioLanguageService();
    final snapshot = service.analyzeProject(const [
      DocumentState(
        documentId: 'main.styio',
        text: '''
// fn fakeFunction(value: f64): f64 { emit value }
/*
@fakeResource : f64|..2| := {}
fakeTask = ||> { <| 42 }
*/
label = "fn stringFunction(value: f64): f64 { emit value }"
@realResource : f64|..2| := {}
realTask = ||> { <| 42 }

fn realFunction(value: f64): f64 {
  emit value
}
''',
        revision: 0,
      ),
    ]).symbolSnapshot;

    expect(
      snapshot.functionsFor('main.styio').map((symbol) => symbol.name),
      equals(['realFunction']),
    );
    expect(
      snapshot.resourcesFor('main.styio').map((symbol) => symbol.name),
      equals(['realResource']),
    );
    expect(
      snapshot.tasksFor('main.styio').map((symbol) => symbol.name),
      equals(['realTask']),
    );
  });

  test('resolves project symbol definitions visible from a document', () {
    const service = ProjectStyioLanguageService();
    final snapshot = service.analyzeProject(const [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@prices : f64|..2| := {}
load = ||> { <| 42 }

fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
local = 1
''',
        revision: 0,
      ),
    ]).symbolSnapshot;

    expect(
      snapshot
          .definitionsVisibleFrom(documentId: 'main.styio', name: 'blend')
          .single
          .kind,
      StyioProjectSymbolKind.function,
    );
    expect(
      snapshot
          .definitionsVisibleFrom(documentId: 'main.styio', name: 'prices')
          .single
          .type,
      'f64',
    );
    expect(
      snapshot
          .definitionsVisibleFrom(documentId: 'main.styio', name: 'load')
          .single
          .type,
      'i64',
    );
    expect(
      snapshot.definitionsVisibleFrom(
        documentId: 'main.styio',
        name: 'missing',
      ),
      isEmpty,
    );
  });

  test('resolves hash function symbols across project documents', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
#blend := (left, right) => {
  <| left
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
value = blend(1.0, 2.0)
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final analysis = service.analyzeProject(documents);
    final signature = analysis.signatureSnapshot
        .functionsFor('lib/math.styio')
        .single;
    final definitions = service.definitionsAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('blend'),
    );
    final info = service.parameterInfoAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('2.0'),
    );

    expect(signature.name, 'blend');
    expect(signature.parameters.map((parameter) => parameter.name), [
      'left',
      'right',
    ]);
    expect(definitions.single.kind, StyioProjectSymbolKind.function);
    expect(info!.signature, 'blend(left, right)');
    expect(info.activeParameter!.name, 'right');
  });

  test('does not resolve import target path segments as symbols', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn math(value: f64): f64 {
  emit value
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
value = 1
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;
    final importTargetOffset = source.indexOf('math');

    expect(
      service.definitionsAt(
        documents: documents,
        documentId: 'main.styio',
        offset: importTargetOffset,
      ),
      isEmpty,
    );
    expect(
      service.referencesAt(
        documents: documents,
        documentId: 'main.styio',
        offset: importTargetOffset,
      ),
      isEmpty,
    );
    expect(
      service.hoverAt(
        documents: documents,
        documentId: 'main.styio',
        offset: importTargetOffset,
      ),
      isNull,
    );
  });

  test('resolves project definitions at a document offset', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@prices : f64|..2| := {}
load = ||> { <| 42 }

fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
price = 1.0
price -> @prices
value = blend(price, 2.0)
?| load -> result: i64
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final functionDefinitions = service.definitionsAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('blend'),
    );
    final resourceDefinitions = service.definitionsAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('prices'),
    );
    final taskDefinitions = service.definitionsAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('load'),
    );

    expect(functionDefinitions.single.kind, StyioProjectSymbolKind.function);
    expect(functionDefinitions.single.documentId, 'lib/runtime.styio');
    expect(resourceDefinitions.single.kind, StyioProjectSymbolKind.resource);
    expect(taskDefinitions.single.kind, StyioProjectSymbolKind.task);
    expect(
      service.definitionsAt(
        documents: documents,
        documentId: 'missing.styio',
        offset: 0,
      ),
      isEmpty,
    );
  });

  test('provides project hover information from symbol definitions', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@prices : f64|..2| := {}
load = ||> { <| 42 }

fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
value = blend(1.0, 2.0)
price -> @prices
?| load -> result: i64
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final functionHover = service.hoverAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('blend'),
    );
    final resourceHover = service.hoverAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('prices'),
    );
    final taskHover = service.hoverAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('load'),
    );

    expect(functionHover!.label, 'function blend: f64');
    expect(resourceHover!.label, 'resource prices: f64');
    expect(taskHover!.label, 'task load: i64');
    expect(
      service.hoverAt(
        documents: documents,
        documentId: 'main.styio',
        offset: 0,
      ),
      isNull,
    );
  });

  test('provides project completions from visible symbol definitions', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@prices : f64|..2| := {}
load = ||> { <| 42 }

fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
bl
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final blendItems = service.completionsAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('bl') + 2,
    );
    final allItems = service.completionsAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('\nbl') + 1,
    );

    expect(blendItems.map((item) => item.label), equals(['blend']));
    expect(blendItems.single.insertText, 'blend()');
    expect(
      allItems.map((item) => item.label),
      containsAll(['blend', '@prices', 'load']),
    );
  });

  test('provides local import path completions', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math/vector.styio',
        text: 'fn dot(left: f64, right: f64): f64 { emit left + right }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: 'fn load(): i64 { emit 42 }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/r }
value = 1
''',
        revision: 0,
      ),
    ];
    final source = documents[2].text;

    final items = service.completionsAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('lib/r') + 'lib/r'.length,
    );

    expect(items.map((item) => item.label), equals(['lib/runtime']));
    expect(items.single.insertText, 'lib/runtime');
    expect(items.single.detail, 'workspace import');
    expect(items.single.replacementRange!.start, source.indexOf('lib/r'));
    expect(items.single.replacementRange!.end, source.indexOf('lib/r') + 5);
  });

  test('finds project references from a symbol offset', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@prices : f64|..2| := {}
load = ||> { <| 42 }

fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
price = 1.0
price -> @prices
value = blend(price, 2.0)
?| load -> result: i64
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final functionReferences = service.referencesAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('blend'),
    );
    final resourceReferences = service.referencesAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('prices'),
    );
    final taskReferences = service.referencesAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('load'),
    );

    expect(functionReferences, hasLength(2));
    expect(
      functionReferences.where((reference) => reference.isDefinition),
      hasLength(1),
    );
    expect(resourceReferences, hasLength(2));
    expect(taskReferences, hasLength(2));
    expect(
      service.referencesAt(
        documents: documents,
        documentId: 'main.styio',
        offset: source.indexOf('price'),
      ),
      isEmpty,
    );
  });

  test('does not count invisible same-name symbols as project references', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
value = blend(1.0, 2.0)
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'unrelated.styio',
        text: '''
fn blend(value: string): string {
  emit value
}
label = blend("local")
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final references = service.referencesAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('blend'),
    );

    expect(references, hasLength(2));
    expect(
      references.map((reference) => reference.documentId),
      isNot(contains('unrelated.styio')),
    );
  });

  test('ignores symbol names inside strings and comments', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
// blend is mentioned in a line comment.
/*
 * blend is mentioned in a block comment.
 */
label = "blend is mentioned in a string"
value = blend(1.0, 2.0)
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final references = service.referencesAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('blend(1.0'),
    );

    expect(references, hasLength(2));
    expect(
      service.definitionsAt(
        documents: documents,
        documentId: 'main.styio',
        offset: source.indexOf('// blend') + 3,
      ),
      isEmpty,
    );
    expect(
      service.hoverAt(
        documents: documents,
        documentId: 'main.styio',
        offset: source.indexOf('"blend') + 1,
      ),
      isNull,
    );
  });

  test(
    'does not count same-name function parameters as project references',
    () {
      const service = ProjectStyioLanguageService();
      const documents = [
        DocumentState(
          documentId: 'lib/runtime.styio',
          text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
          revision: 0,
        ),
        DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/runtime }
value = blend(1.0, 2.0)

fn local(blend: string): string {
  emit blend
}
''',
          revision: 0,
        ),
      ];
      final source = documents[1].text;

      final references = service.referencesAt(
        documents: documents,
        documentId: 'main.styio',
        offset: source.indexOf('blend(1.0'),
      );

      expect(references, hasLength(2));
      expect(
        references.where((reference) => reference.documentId == 'main.styio'),
        hasLength(1),
      );
    },
  );

  test('does not count local bindings as project references', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
value = blend(1.0, 2.0)
blend = "local"
label = blend
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final references = service.referencesAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('blend(1.0'),
    );

    expect(references, hasLength(2));
    expect(
      references.where((reference) => reference.documentId == 'main.styio'),
      hasLength(1),
    );
  });

  test('previews safe project renames from references', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@prices : f64|..2| := {}

fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
price = 1.0
value = blend(price, 2.0)
price -> @prices
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final functionPreview = service.renamePreviewAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('blend'),
      newName: 'mix',
    );
    final invalidPreview = service.renamePreviewAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('blend'),
      newName: '1bad',
    );

    expect(functionPreview!.oldName, 'blend');
    expect(functionPreview.newName, 'mix');
    expect(functionPreview.editCount, 2);
    expect(functionPreview.editsByDocument.keys, contains('lib/runtime.styio'));
    expect(functionPreview.editsByDocument.keys, contains('main.styio'));
    expect(invalidPreview!.hasConflict, isTrue);
    expect(invalidPreview.conflict, contains('not a valid'));
  });

  test('reports project rename conflicts for visible symbols', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}

fn mix(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
value = blend(1.0, 2.0)
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final conflict = service.renamePreviewAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('blend'),
      newName: 'mix',
    );

    expect(conflict!.hasConflict, isTrue);
    expect(conflict.oldName, 'blend');
    expect(conflict.newName, 'mix');
    expect(conflict.editCount, 0);
    expect(conflict.conflict, contains('conflicts'));
  });

  test('reports project rename conflicts from affected documents', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/other.styio',
        text: '''
fn mix(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
@import { lib/other }
value = blend(1.0, 2.0)
''',
        revision: 0,
      ),
    ];
    final runtimeSource = documents[0].text;

    final conflict = service.renamePreviewAt(
      documents: documents,
      documentId: 'lib/runtime.styio',
      offset: runtimeSource.indexOf('blend'),
      newName: 'mix',
    );

    expect(conflict!.hasConflict, isTrue);
    expect(conflict.oldName, 'blend');
    expect(conflict.newName, 'mix');
    expect(conflict.editCount, 0);
    expect(conflict.conflict, contains('conflicts'));
  });
}
