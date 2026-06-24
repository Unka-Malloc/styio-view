import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';

String styioLanguageFixture(String path) {
  return File('test/fixtures/styio_language/$path').readAsStringSync();
}

String applyEdits(String text, Iterable<FormattingEdit> edits) {
  final ordered = edits.toList()
    ..sort((left, right) => right.range.start.compareTo(left.range.start));
  var result = text;
  for (final edit in ordered) {
    result =
        result.substring(0, edit.range.start) +
        edit.newText +
        result.substring(edit.range.end);
  }
  return result;
}

bool formattingEditsConflictForTest(FormattingEdit left, FormattingEdit right) {
  final leftIsInsertion = left.range.start == left.range.end;
  final rightIsInsertion = right.range.start == right.range.end;
  if (leftIsInsertion && rightIsInsertion) {
    return left.range.start == right.range.start;
  }
  if (leftIsInsertion) {
    return right.range.start <= left.range.start &&
        left.range.start <= right.range.end;
  }
  if (rightIsInsertion) {
    return left.range.start <= right.range.start &&
        right.range.start <= left.range.end;
  }
  return left.range.start < right.range.end &&
      right.range.start < left.range.end;
}

void main() {
  test('normalizes formatting edits for workspace-safe application', () {
    final edits = normalizeFormattingEditsForDocument(
      documentLength: 6,
      edits: const <FormattingEdit>[
        FormattingEdit(range: SourceRange(start: -1, end: 1), newText: 'X'),
        FormattingEdit(range: SourceRange(start: 1, end: 3), newText: 'Y'),
        FormattingEdit(range: SourceRange(start: 2, end: 4), newText: 'Z'),
        FormattingEdit(range: SourceRange(start: 4, end: 6), newText: 'Q'),
        FormattingEdit(range: SourceRange(start: 8, end: 9), newText: 'R'),
      ],
    );

    expect(edits.map((edit) => edit.newText), <String>['Y', 'Q']);
  });

  test('previews workspace fixes with normalized document edits', () {
    const fix = StyioProjectWorkspaceFix(
      label: 'Preview workspace fix',
      detail: 'Preview safe edits only.',
      editsByDocument: <String, List<FormattingEdit>>{
        'main.styio': <FormattingEdit>[
          FormattingEdit(range: SourceRange(start: 1, end: 3), newText: 'Y'),
          FormattingEdit(range: SourceRange(start: 2, end: 4), newText: 'Z'),
          FormattingEdit(range: SourceRange(start: 4, end: 6), newText: 'Q'),
        ],
        'missing.styio': <FormattingEdit>[
          FormattingEdit(range: SourceRange(start: 0, end: 1), newText: 'X'),
        ],
      },
    );
    const documents = <DocumentState>[
      DocumentState(documentId: 'main.styio', text: 'abcdef', revision: 0),
    ];

    final preview = fix.preview(documents);

    expect(preview.label, 'Preview workspace fix');
    expect(preview.detail, 'Preview safe edits only.');
    expect(preview.hasChanges, isTrue);
    expect(preview.documents, hasLength(1));
    expect(preview.documents.single.documentId, 'main.styio');
    expect(preview.documents.single.beforeText, 'abcdef');
    expect(preview.documents.single.afterText, 'aYdQ');
    expect(preview.documents.single.edits.map((edit) => edit.newText), <String>[
      'Y',
      'Q',
    ]);
  });

  test(
    'applies workspace fixes through the same normalized preview contract',
    () {
      const fix = StyioProjectWorkspaceFix(
        label: 'Apply workspace fix',
        editsByDocument: <String, List<FormattingEdit>>{
          'main.styio': <FormattingEdit>[
            FormattingEdit(range: SourceRange(start: 1, end: 3), newText: 'Y'),
            FormattingEdit(range: SourceRange(start: 2, end: 4), newText: 'Z'),
            FormattingEdit(range: SourceRange(start: 4, end: 6), newText: 'Q'),
          ],
          'unchanged.styio': <FormattingEdit>[
            FormattingEdit(range: SourceRange(start: 9, end: 10), newText: 'X'),
          ],
        },
      );
      const documents = <DocumentState>[
        DocumentState(documentId: 'main.styio', text: 'abcdef', revision: 2),
        DocumentState(documentId: 'unchanged.styio', text: 'abc', revision: 4),
      ];

      final applied = fix.apply(documents);

      expect(applied, hasLength(2));
      expect(applied[0].text, 'aYdQ');
      expect(applied[0].revision, 3);
      expect(applied[1], same(documents[1]));
    },
  );

  test(
    'default project document service bridges current local analysis and current project diagnostics',
    () {
      const service = ProjectStyioLanguageService();
      const document = DocumentState(
        documentId: 'main.styio',
        text: '''
value = 1
value
fn broken() {
  let stream
''',
        revision: 0,
      );

      final analysis = service.analyzeProject(const <DocumentState>[document]);
      final documentAnalysis = analysis.documentAnalyses['main.styio']!;
      final codes = documentAnalysis.diagnostics.map(
        (diagnostic) => diagnostic.code,
      );

      expect(
        documentAnalysis.inlayHints.map((hint) => hint.label),
        contains(': i64'),
      );
      expect(codes, contains('missing-assignment'));
    },
  );

  test('resolves imported current-file symbols across workspace documents', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
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
@import { lib/math }
price = 1.0
tax = 0.5
value = blend(price, tax)
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final mainCodes = analysis
        .diagnosticsFor('main.styio')
        .map((diagnostic) => diagnostic.diagnostic.code);

    expect(mainCodes, isNot(contains('unresolved-reference')));
    expect(mainCodes, isNot(contains('unresolved-import')));
  });

  test('exposes project function signature snapshot', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn blend(left: f64, right: f64, scale: f64 = 1.0): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
    ];

    final signatures = service
        .analyzeProject(documents)
        .signatureSnapshot
        .functionsFor('lib/math.styio');

    expect(signatures, hasLength(1));
    expect(signatures.single.name, 'blend');
    expect(signatures.single.returnType, 'f64');
    expect(signatures.single.requiredParameterCount, 2);
    expect(signatures.single.parameterCount, 3);
    expect(signatures.single.parameters.last.hasDefault, isTrue);
  });

  test('exposes project import targets in symbol snapshot', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { styio/core }
@import { lib/math }
@prices : f64|..2| := {}
load = ||> { <| 1 }
value = 1
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);

    expect(
      analysis.symbolSnapshot.importTargetsFor('main.styio'),
      equals(['styio/core', 'lib/math']),
    );
    expect(
      analysis.symbolSnapshot.resourcesFor('main.styio').single.name,
      'prices',
    );
    expect(
      analysis.symbolSnapshot.resourcesFor('main.styio').single.type,
      'f64',
    );
    expect(analysis.symbolSnapshot.tasksFor('main.styio').single.name, 'load');
    expect(analysis.symbolSnapshot.functionsFor('missing.styio'), isEmpty);
  });

  test('reports unresolved local imports', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/missing }
value = 1
''',
        revision: 0,
      ),
    ];

    final diagnostics = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio');

    expect(
      diagnostics.map((diagnostic) => diagnostic.diagnostic.code),
      contains('unresolved-import'),
    );
    expect(
      diagnostics
          .singleWhere(
            (diagnostic) => diagnostic.diagnostic.code == 'unresolved-import',
          )
          .diagnostic
          .message,
      contains('lib/missing'),
    );
    final unresolved = diagnostics.singleWhere(
      (diagnostic) => diagnostic.diagnostic.code == 'unresolved-import',
    );
    final fix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: unresolved,
        )
        .single;

    expect(fix.label, 'Remove unresolved import');
    expect(applyEdits(documents.single.text, fix.edits), '''
value = 1
''');
  });

  test('suggests close workspace import targets for unresolved imports', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: 'fn blend(left: f64, right: f64): f64 { emit left + right }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/mat }
value = 1
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final unresolved = analysis
        .diagnosticsFor('main.styio')
        .singleWhere(
          (diagnostic) => diagnostic.diagnostic.code == 'unresolved-import',
        );
    final fixes = service.quickFixesForProjectDiagnostic(
      documents: documents,
      diagnostic: unresolved,
      analysis: analysis,
    );
    final changeFix = fixes.singleWhere(
      (fix) => fix.label == 'Change import to `lib/math`',
    );

    expect(
      fixes.map((fix) => fix.label),
      containsAll(['Remove unresolved import', 'Change import to `lib/math`']),
    );
    expect(applyEdits(documents.last.text, changeFix.edits), '''
@import { lib/math }
value = 1
''');

    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Clean up project imports');

    expect(
      applyEdits(
        documents.last.text,
        workspaceFix.editsByDocument['main.styio']!,
      ),
      '''
value = 1
''',
    );
  });

  test('offers missing import quick fixes for unresolved project symbols', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: 'fn blend(left: f64, right: f64): f64 { emit left + right }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
price = 1.0
value = blend(price, 2.0)
''',
        revision: 0,
      ),
    ];

    final diagnostic = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio')
        .singleWhere(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'unresolved-reference' &&
              documents.last.text.substring(
                    diagnostic.diagnostic.range.start,
                    diagnostic.diagnostic.range.end,
                  ) ==
                  'blend',
        );
    final fixes = service.quickFixesForProjectDiagnostic(
      documents: documents,
      diagnostic: diagnostic,
    );
    final fix = fixes.singleWhere(
      (fix) => fix.label == 'Import `blend` from lib/math',
    );

    expect(fix.label, 'Import `blend` from lib/math');
    expect(applyEdits(documents.last.text, fix.edits), '''
@import { lib/math }
price = 1.0
value = blend(price, 2.0)
''');
    expect(fixes.map((fix) => fix.label), contains('Create function `blend`'));
  });

  test('preserves current-file quick fixes through project diagnostics', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'main.styio',
        text: '''
price = 1
tax = 2
total = calculate(price, tax)
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final unresolved = analysis
        .diagnosticsFor('main.styio')
        .singleWhere(
          (diagnostic) => diagnostic.diagnostic.code == 'unresolved-reference',
        );
    final fixes = service.quickFixesForProjectDiagnostic(
      documents: documents,
      diagnostic: unresolved,
      analysis: analysis,
    );

    expect(fixes.map((fix) => fix.label), [
      'Create function `calculate`',
      'Create local binding `calculate`',
    ]);
  });

  test(
    'offers missing import quick fixes for unresolved resources and tasks',
    () {
      const service = ProjectStyioLanguageService();
      const documents = [
        DocumentState(
          documentId: 'lib/runtime.styio',
          text: '''
@prices : f64|..2| := {}
load = ||> { <| 42 }
''',
          revision: 0,
        ),
        DocumentState(
          documentId: 'main.styio',
          text: '''
price = 1.0
price -> @prices
?| load -> result: i64
''',
          revision: 0,
        ),
      ];

      final analysis = service.analyzeProject(documents);
      final resource = analysis
          .diagnosticsFor('main.styio')
          .singleWhere(
            (diagnostic) => diagnostic.diagnostic.code == 'unresolved-resource',
          );
      final task = analysis
          .diagnosticsFor('main.styio')
          .singleWhere(
            (diagnostic) =>
                diagnostic.diagnostic.code == 'unresolved-task-await',
          );
      final resourceFix = service
          .quickFixesForProjectDiagnostic(
            documents: documents,
            diagnostic: resource,
            analysis: analysis,
          )
          .singleWhere(
            (fix) => fix.label == 'Import `prices` from lib/runtime',
          );
      final resourceFixes = service.quickFixesForProjectDiagnostic(
        documents: documents,
        diagnostic: resource,
        analysis: analysis,
      );
      final taskFix = service
          .quickFixesForProjectDiagnostic(
            documents: documents,
            diagnostic: task,
            analysis: analysis,
          )
          .singleWhere((fix) => fix.label == 'Import `load` from lib/runtime');
      final taskFixes = service.quickFixesForProjectDiagnostic(
        documents: documents,
        diagnostic: task,
        analysis: analysis,
      );

      expect(resourceFix.label, 'Import `prices` from lib/runtime');
      expect(taskFix.label, 'Import `load` from lib/runtime');
      expect(
        resourceFixes.map((fix) => fix.label),
        contains('Create resource `@prices`'),
      );
      expect(taskFixes.map((fix) => fix.label), contains('Create task `load`'));
      expect(applyEdits(documents.last.text, resourceFix.edits), '''
@import { lib/runtime }
price = 1.0
price -> @prices
?| load -> result: i64
''');
      expect(applyEdits(documents.last.text, taskFix.edits), '''
@import { lib/runtime }
price = 1.0
price -> @prices
?| load -> result: i64
''');
    },
  );

  test('fixes unresolved imported task return values from await context', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
load = ||> {
  <| value
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
?| load -> result: i64
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final diagnostic = analysis
        .diagnosticsFor('lib/runtime.styio')
        .singleWhere(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'unresolved-task-return-value',
        );
    final fix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: diagnostic,
          analysis: analysis,
        )
        .single;

    expect(fix.label, 'Create imported task local binding `value`');
    expect(applyEdits(documents.first.text, fix.edits), '''
load = ||> {
  value = 0
  <| value
}
''');

    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Fix project type mismatches');

    expect(
      applyEdits(
        documents.first.text,
        workspaceFix.editsByDocument['lib/runtime.styio']!,
      ),
      '''
load = ||> {
  value = 0
  <| value
}
''',
    );
  });

  test('fixes empty imported task returns from await context', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
load = ||> {
  <|
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
?| load -> result: i64
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final diagnostic = analysis
        .diagnosticsFor('lib/runtime.styio')
        .singleWhere(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'missing-task-return-value',
        );
    final mainCodes = analysis
        .diagnosticsFor('main.styio')
        .map((diagnostic) => diagnostic.diagnostic.code);
    final fix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: diagnostic,
          analysis: analysis,
        )
        .single;

    expect(mainCodes, isNot(contains('missing-task-return')));
    expect(fix.label, 'Insert imported task return expression');
    expect(applyEdits(documents.first.text, fix.edits), '''
load = ||> {
  <| 0
}
''');

    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Fix project type mismatches');

    expect(
      applyEdits(
        documents.first.text,
        workspaceFix.editsByDocument['lib/runtime.styio']!,
      ),
      '''
load = ||> {
  <| 0
}
''',
    );
  });

  test('reports conflicting imported task return context types', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
load = ||> {
  <|
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main_a.styio',
        text: '''
@import { lib/runtime }
?| load -> count: i64
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main_b.styio',
        text: '''
@import { lib/runtime }
?| load -> label: string
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final conflict = analysis
        .diagnosticsFor('lib/runtime.styio')
        .singleWhere(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'conflicting-task-return-context',
        );
    final missing = analysis
        .diagnosticsFor('lib/runtime.styio')
        .singleWhere(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'missing-task-return-value',
        );

    expect(conflict.diagnostic.message, contains('`i64`'));
    expect(conflict.diagnostic.message, contains('`string`'));
    expect(
      service.quickFixesForProjectDiagnostic(
        documents: documents,
        diagnostic: missing,
        analysis: analysis,
      ),
      isEmpty,
    );
    expect(
      service.workspaceQuickFixesForProjectDiagnostics(
        documents: documents,
        diagnostics: analysis.diagnostics,
        analysis: analysis,
      ),
      isEmpty,
    );
  });

  test('blocks workspace missing-return fixes for conflicting await types', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
load = ||> {
  step = 1
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main_a.styio',
        text: '''
@import { lib/runtime }
?| load -> count: i64
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main_b.styio',
        text: '''
@import { lib/runtime }
?| load -> label: string
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final conflict = analysis
        .diagnosticsFor('lib/runtime.styio')
        .singleWhere(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'conflicting-task-return-context',
        );

    expect(conflict.diagnostic.message, contains('`i64`'));
    expect(conflict.diagnostic.message, contains('`string`'));
    expect(
      analysis
          .diagnosticsFor('main_a.styio')
          .map((diagnostic) => diagnostic.diagnostic.code),
      contains('missing-task-return'),
    );
    expect(
      analysis
          .diagnosticsFor('main_b.styio')
          .map((diagnostic) => diagnostic.diagnostic.code),
      contains('missing-task-return'),
    );
    expect(
      service.workspaceQuickFixesForProjectDiagnostics(
        documents: documents,
        diagnostics: analysis.diagnostics,
        analysis: analysis,
      ),
      isEmpty,
    );
  });

  test('reports conflicting conditional imported task return contexts', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
load = ||> {
  ready = false
  when ready -> <| 1
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main_a.styio',
        text: '''
@import { lib/runtime }
?| load -> count: i64
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main_b.styio',
        text: '''
@import { lib/runtime }
?| load -> label: string
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final conflict = analysis
        .diagnosticsFor('lib/runtime.styio')
        .singleWhere(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'conflicting-task-return-context',
        );

    expect(conflict.diagnostic.message, contains('`i64`'));
    expect(conflict.diagnostic.message, contains('`string`'));
    expect(
      analysis
          .diagnosticsFor('main_a.styio')
          .map((diagnostic) => diagnostic.diagnostic.code),
      contains('conditional-task-return'),
    );
    expect(
      analysis
          .diagnosticsFor('main_b.styio')
          .map((diagnostic) => diagnostic.diagnostic.code),
      contains('conditional-task-return'),
    );
    expect(
      service.workspaceQuickFixesForProjectDiagnostics(
        documents: documents,
        diagnostics: analysis.diagnostics,
        analysis: analysis,
      ),
      isEmpty,
    );
  });

  test('reports ambiguous imported symbols', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/a.styio',
        text: 'fn calibrate(value: f64): f64 { emit value }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/b.styio',
        text: 'fn calibrate(value: f64): f64 { emit value }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/a }
@import { lib/b }
price = 1.0
value = calibrate(price)
''',
        revision: 0,
      ),
    ];

    final diagnostics = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio');

    expect(
      diagnostics.map((diagnostic) => diagnostic.diagnostic.code),
      contains('ambiguous-imported-symbol'),
    );
  });

  test('offers safe import removal fixes for ambiguous project symbols', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/a.styio',
        text: 'fn calibrate(value: f64): f64 { emit value }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/b.styio',
        text: 'fn calibrate(value: f64): f64 { emit value }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/a }
@import { lib/b }
price = 1.0
value = calibrate(price)
''',
        revision: 0,
      ),
    ];

    final ambiguous = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio')
        .singleWhere(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'ambiguous-imported-symbol',
        );
    final fixes = service.quickFixesForProjectDiagnostic(
      documents: documents,
      diagnostic: ambiguous,
    );
    final removeA = fixes.singleWhere(
      (fix) => fix.label == 'Remove import `lib/a`',
    );

    expect(
      fixes.map((fix) => fix.label),
      containsAll(['Remove import `lib/a`', 'Remove import `lib/b`']),
    );
    expect(applyEdits(documents.last.text, removeA.edits), '''
@import { lib/b }
price = 1.0
value = calibrate(price)
''');
  });

  test('checks imported function call arity', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn blend(left: f64, right: f64, scale: f64 = 1.0): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
price = 1.0
tax = 0.5
missing = blend(price)
extra = blend(price, tax, 1.0, 2.0)
''',
        revision: 0,
      ),
    ];

    final codes = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio')
        .map((diagnostic) => diagnostic.diagnostic.code);

    expect(codes, contains('missing-call-argument'));
    expect(codes, contains('too-many-call-arguments'));
    final analysis = service.analyzeProject(documents);
    final diagnostics = analysis.diagnosticsFor('main.styio');
    final missing = diagnostics.singleWhere(
      (diagnostic) => diagnostic.diagnostic.code == 'missing-call-argument',
    );
    final extra = diagnostics.singleWhere(
      (diagnostic) => diagnostic.diagnostic.code == 'too-many-call-arguments',
    );
    final missingFix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: missing,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Insert missing argument');
    final extraFix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: extra,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Remove extra argument');

    expect(applyEdits(documents.last.text, missingFix.edits), '''
@import { lib/math }
price = 1.0
tax = 0.5
missing = blend(price, 0.0)
extra = blend(price, tax, 1.0, 2.0)
''');
    expect(applyEdits(documents.last.text, extraFix.edits), '''
@import { lib/math }
price = 1.0
tax = 0.5
missing = blend(price)
extra = blend(price, tax, 1.0)
''');
    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Fix imported function calls');

    expect(
      applyEdits(
        documents.last.text,
        workspaceFix.editsByDocument['main.styio']!,
      ),
      '''
@import { lib/math }
price = 1.0
tax = 0.5
missing = blend(price, 0.0)
extra = blend(price, tax, 1.0)
''',
    );
  });

  test('checks imported function named arguments', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
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
@import { lib/math }
price = 1.0
tax = 0.5
unknown = blend(left: price, rigth: tax)
duplicate = blend(left: price, left: tax)
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final diagnostics = analysis.diagnosticsFor('main.styio');
    final codes = diagnostics.map((diagnostic) => diagnostic.diagnostic.code);

    expect(codes, contains('unknown-named-argument'));
    expect(codes, contains('duplicate-named-argument'));
    expect(codes, contains('missing-call-argument'));
    final unknown = diagnostics.singleWhere(
      (diagnostic) => diagnostic.diagnostic.code == 'unknown-named-argument',
    );
    final duplicate = diagnostics.singleWhere(
      (diagnostic) => diagnostic.diagnostic.code == 'duplicate-named-argument',
    );
    final unknownFix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: unknown,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Change argument name to `right`');
    final duplicateFix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: duplicate,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Remove duplicate `left` argument');

    expect(applyEdits(documents.last.text, unknownFix.edits), '''
@import { lib/math }
price = 1.0
tax = 0.5
unknown = blend(left: price, right: tax)
duplicate = blend(left: price, left: tax)
''');
    expect(applyEdits(documents.last.text, duplicateFix.edits), '''
@import { lib/math }
price = 1.0
tax = 0.5
unknown = blend(left: price, rigth: tax)
duplicate = blend(left: price)
''');
    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Fix imported function calls');

    expect(
      applyEdits(
        documents.last.text,
        workspaceFix.editsByDocument['main.styio']!,
      ),
      '''
@import { lib/math }
price = 1.0
tax = 0.5
unknown = blend(left: price, right: tax)
duplicate = blend(left: price)
''',
    );
  });

  test('provides project parameter info for imported function calls', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn blend(left: f64, right: f64, scale: f64 = 1.0): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
price = 1.0
tax = 0.5
value = blend(price, tax)
named = blend(scale: tax, left: price, right: tax)
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final positionalInfo = service.parameterInfoAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('tax)'),
    );
    final namedInfo = service.parameterInfoAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('tax, left'),
    );

    expect(positionalInfo!.callableName, 'blend');
    expect(
      positionalInfo.signature,
      'blend(left: f64, right: f64, scale: f64 = ...): f64',
    );
    expect(positionalInfo.activeParameter!.name, 'right');
    expect(namedInfo!.activeParameter!.name, 'scale');
  });

  test('does not guess parameter info for ambiguous imported calls', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/a.styio',
        text: 'fn blend(left: f64): f64 { emit left }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/b.styio',
        text: 'fn blend(label: string): string { emit label }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/a }
@import { lib/b }
value = blend(1.0)
''',
        revision: 0,
      ),
    ];
    final source = documents[2].text;

    final info = service.parameterInfoAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('1.0'),
    );

    expect(info, isNull);
  });

  test('uses innermost project call for parameter info', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}

fn render(value: f64): string {
  emit "value"
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
price = 1.0
tax = 0.5
label = render(blend(price, tax))
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final innerInfo = service.parameterInfoAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('tax))'),
    );

    expect(innerInfo!.callableName, 'blend');
    expect(innerInfo.activeParameter!.name, 'right');
  });

  test('provides project named argument completions', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn blend(left: f64, right: f64, scale: f64 = 1.0): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
price = 1.0
tax = 0.5
value = blend(left: price, r)
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final items = service.namedArgumentCompletionsAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('r)') + 1,
    );

    expect(items.map((item) => item.label), equals(['right:']));
    expect(items.single.insertText, 'right: ');
    expect(items.single.detail, contains('f64'));
    expect(items.single.replacementRange!.start, source.indexOf('r)'));
  });

  test('does not guess named argument completions for ambiguous imports', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/a.styio',
        text: 'fn blend(left: f64): f64 { emit left }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/b.styio',
        text: 'fn blend(label: string): string { emit label }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/a }
@import { lib/b }
value = blend(l)
''',
        revision: 0,
      ),
    ];
    final source = documents[2].text;

    final items = service.namedArgumentCompletionsAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('l)') + 1,
    );

    expect(items, isEmpty);
  });

  test('provides project parameter name inlay hints', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
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
@import { lib/math }
price = 1.0
tax = 0.5
value = blend(price, tax)
named = blend(left: price, tax)
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;

    final hints = service.inlayHintsFor(
      documents: documents,
      documentId: 'main.styio',
    );

    expect(hints.map((hint) => hint.label), ['left:', 'right:', 'right:']);
    expect(hints.first.kind, InlayHintKind.parameter);
    expect(hints.first.position, source.indexOf('price, tax'));
  });

  test('does not guess parameter inlay hints for ambiguous imports', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/a.styio',
        text: 'fn blend(left: f64): f64 { emit left }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/b.styio',
        text: 'fn blend(label: string): string { emit label }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/a }
@import { lib/b }
value = blend(1.0)
''',
        revision: 0,
      ),
    ];

    final hints = service.inlayHintsFor(
      documents: documents,
      documentId: 'main.styio',
    );

    expect(hints, isEmpty);
  });

  test('checks imported function argument types from local values', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
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
@import { lib/math }
price = 1.0
label = "bad"
value = blend(price, label)
''',
        revision: 0,
      ),
    ];

    final diagnostics = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio');
    final mismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.diagnostic.code == 'argument-type-mismatch',
    );
    final fix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: mismatch,
        )
        .single;

    expect(mismatch.diagnostic.message, contains('right'));
    expect(mismatch.diagnostic.message, contains('f64'));
    expect(mismatch.diagnostic.message, contains('string'));
    expect(fix.label, 'Change argument to f64 literal');
    expect(applyEdits(documents.last.text, fix.edits), '''
@import { lib/math }
price = 1.0
label = "bad"
value = blend(price, 0.0)
''');
    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: diagnostics,
        )
        .singleWhere((fix) => fix.label == 'Fix project type mismatches');

    expect(
      applyEdits(
        documents.last.text,
        workspaceFix.editsByDocument['main.styio']!,
      ),
      '''
@import { lib/math }
price = 1.0
label = "bad"
value = blend(price, 0.0)
''',
    );
  });

  test('uses imported function return types in project type diagnostics', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}

fn render(label: string): string {
  emit label
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
price = 1.0
tax = 0.5
total = blend(price, tax)
badInit: i64 = blend(price, tax)
badArg = render(total)
''',
        revision: 0,
      ),
    ];

    final diagnostics = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio');
    final codes = diagnostics.map((diagnostic) => diagnostic.diagnostic.code);

    expect(codes, contains('initializer-type-mismatch'));
    expect(codes, contains('argument-type-mismatch'));
    expect(
      diagnostics
          .singleWhere(
            (diagnostic) =>
                diagnostic.diagnostic.code == 'initializer-type-mismatch',
          )
          .diagnostic
          .message,
      contains('f64'),
    );
    expect(
      diagnostics
          .singleWhere(
            (diagnostic) =>
                diagnostic.diagnostic.code == 'argument-type-mismatch',
          )
          .diagnostic
          .message,
      contains('f64'),
    );
  });

  test('uses imported hash function return types in project diagnostics', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/hash_math.styio',
        text: '''
#answer := () => {
  <| 42
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/hash_math }
badInit: string = answer()
''',
        revision: 0,
      ),
    ];

    final diagnostics = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio');
    final mismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.diagnostic.code == 'initializer-type-mismatch',
    );

    expect(mismatch.diagnostic.message, contains('i64'));
    expect(mismatch.diagnostic.message, contains('string'));
  });

  test('uses nested imported call return types in argument diagnostics', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}

fn render(label: string): string {
  emit label
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
price = 1.0
tax = 0.5
bad = render(blend(price, tax))
''',
        revision: 0,
      ),
    ];

    final diagnostics = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio');
    final mismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.diagnostic.code == 'argument-type-mismatch',
    );

    expect(mismatch.diagnostic.message, contains('label'));
    expect(mismatch.diagnostic.message, contains('string'));
    expect(mismatch.diagnostic.message, contains('f64'));
  });

  test('resolves imported resources and tasks through symbol snapshot', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@prices : f64|..2| := {}
load = ||> { <| 42 }
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
price = 1.0
price -> @prices
?| load -> result: i64
''',
        revision: 0,
      ),
    ];

    final codes = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio')
        .map((diagnostic) => diagnostic.diagnostic.code);

    expect(codes, isNot(contains('unresolved-resource')));
    expect(codes, isNot(contains('unresolved-task-await')));
  });

  test('ignores imported calls and awaits inside strings and comments', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}

load = ||> { <| 42 }
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
price = 1.0
tax = 0.5
// missing = blend(price)
/*
bad = blend(price)
?| load -> badResult: string
*/
label = "blend(price)"
value = blend(price, tax)
?| load -> result: i64
''',
        revision: 0,
      ),
    ];

    final codes = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio')
        .map((diagnostic) => diagnostic.diagnostic.code);

    expect(codes, isNot(contains('missing-call-argument')));
    expect(codes, isNot(contains('await-result-type-mismatch')));
  });

  test('checks imported resource and task result types', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@prices : f64|..2| := {}
load = ||> { <| "ready" }
count = ||> { <| 42 }
empty = ||> {
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
label = "bad"
label -> @prices
?| load -> result: i64
?| count -> fallbackResult: i64 | "missing"
?| empty -> emptyResult: i64 | 0
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final diagnostics = analysis.diagnosticsFor('main.styio');
    final codes = diagnostics.map((diagnostic) => diagnostic.diagnostic.code);

    expect(codes, contains('resource-write-type-mismatch'));
    expect(codes, contains('await-result-type-mismatch'));
    expect(codes, contains('await-fallback-type-mismatch'));
    expect(codes, contains('missing-task-return'));
    final resourceMismatch = diagnostics.singleWhere(
      (diagnostic) =>
          diagnostic.diagnostic.code == 'resource-write-type-mismatch',
    );
    final awaitMismatch = diagnostics.singleWhere(
      (diagnostic) =>
          diagnostic.diagnostic.code == 'await-result-type-mismatch',
    );
    final fallbackMismatch = diagnostics.singleWhere(
      (diagnostic) =>
          diagnostic.diagnostic.code == 'await-fallback-type-mismatch',
    );
    final resourceFix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: resourceMismatch,
          analysis: analysis,
        )
        .single;
    final awaitFix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: awaitMismatch,
          analysis: analysis,
        )
        .single;
    final fallbackFix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: fallbackMismatch,
          analysis: analysis,
        )
        .single;

    expect(resourceFix.label, 'Change resource write value to f64 literal');
    expect(awaitFix.label, 'Change await binding type to string');
    expect(fallbackFix.label, 'Change await fallback to i64 literal');
    expect(applyEdits(documents.last.text, resourceFix.edits), '''
@import { lib/runtime }
label = "bad"
0.0 -> @prices
?| load -> result: i64
?| count -> fallbackResult: i64 | "missing"
?| empty -> emptyResult: i64 | 0
''');
    expect(applyEdits(documents.last.text, awaitFix.edits), '''
@import { lib/runtime }
label = "bad"
label -> @prices
?| load -> result: string
?| count -> fallbackResult: i64 | "missing"
?| empty -> emptyResult: i64 | 0
''');
    expect(applyEdits(documents.last.text, fallbackFix.edits), '''
@import { lib/runtime }
label = "bad"
label -> @prices
?| load -> result: i64
?| count -> fallbackResult: i64 | 0
?| empty -> emptyResult: i64 | 0
''');
    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Fix project type mismatches');

    expect(
      applyEdits(
        documents.last.text,
        workspaceFix.editsByDocument['main.styio']!,
      ),
      '''
@import { lib/runtime }
label = "bad"
0.0 -> @prices
?| load -> result: string
?| count -> fallbackResult: i64 | 0
?| empty -> emptyResult: i64 | 0
''',
    );
    expect(
      applyEdits(
        documents.first.text,
        workspaceFix.editsByDocument['lib/runtime.styio']!,
      ),
      '''
@prices : f64|..2| := {}
load = ||> { <| "ready" }
count = ||> { <| 42 }
empty = ||> {
  <| 0
}
''',
    );
  });

  test('uses imported task local return types in project diagnostics', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
load = ||> {
  value = 42
  <| value // ok
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
?| load -> result: i64 | 0
''',
        revision: 0,
      ),
    ];

    final codes = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio')
        .map((diagnostic) => diagnostic.diagnostic.code);

    expect(codes, isNot(contains('missing-task-return')));
    expect(codes, isNot(contains('await-result-type-mismatch')));
    expect(codes, isNot(contains('await-fallback-type-mismatch')));
  });

  test(
    'uses imported task function call return types in project diagnostics',
    () {
      const service = ProjectStyioLanguageService();
      const documents = [
        DocumentState(
          documentId: 'lib/runtime.styio',
          text: '''
fn makeCount(): i64 {
  emit 42
}
load = ||> {
  <| makeCount()
}
''',
          revision: 0,
        ),
        DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/runtime }
?| load -> result: i64 | 0
''',
          revision: 0,
        ),
      ];

      final codes = service
          .analyzeProject(documents)
          .diagnosticsFor('main.styio')
          .map((diagnostic) => diagnostic.diagnostic.code);

      expect(codes, isNot(contains('missing-task-return')));
      expect(codes, isNot(contains('await-result-type-mismatch')));
      expect(codes, isNot(contains('await-fallback-type-mismatch')));
    },
  );

  test('uses transitive imported function returns in task diagnostics', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn makeCount(): i64 {
  emit 42
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@import { lib/math }
load = ||> {
  <| makeCount()
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
?| load -> result: i64 | 0
''',
        revision: 0,
      ),
    ];

    final codes = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio')
        .map((diagnostic) => diagnostic.diagnostic.code);

    expect(codes, isNot(contains('missing-task-return')));
    expect(codes, isNot(contains('await-result-type-mismatch')));
    expect(codes, isNot(contains('await-fallback-type-mismatch')));
  });

  test('uses later imported task return types after unresolved returns', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
load = ||> {
  <| missing
  value = 42
  <| value
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
?| load -> result: i64 | 0
''',
        revision: 0,
      ),
    ];

    final codes = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio')
        .map((diagnostic) => diagnostic.diagnostic.code);

    expect(codes, isNot(contains('missing-task-return')));
    expect(codes, isNot(contains('await-result-type-mismatch')));
  });

  test(
    'reports ambiguous imported resources and tasks without type guessing',
    () {
      const service = ProjectStyioLanguageService();
      const documents = [
        DocumentState(
          documentId: 'lib/a.styio',
          text: '''
@prices : f64|..2| := {}
load = ||> { <| 42 }
''',
          revision: 0,
        ),
        DocumentState(
          documentId: 'lib/b.styio',
          text: '''
@prices : string|..2| := {}
load = ||> { <| "ready" }
''',
          revision: 0,
        ),
        DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/a }
@import { lib/b }
price = 1.0
price -> @prices
?| load -> result: i64
''',
          revision: 0,
        ),
      ];

      final analysis = service.analyzeProject(documents);
      final diagnostics = analysis.diagnosticsFor('main.styio');
      final codes = diagnostics
          .map((diagnostic) => diagnostic.diagnostic.code)
          .toList(growable: false);
      final ambiguousDiagnostics = diagnostics
          .where(
            (diagnostic) =>
                diagnostic.diagnostic.code == 'ambiguous-imported-symbol',
          )
          .toList(growable: false);

      expect(
        codes.where((code) => code == 'ambiguous-imported-symbol'),
        hasLength(2),
      );
      expect(codes, isNot(contains('resource-write-type-mismatch')));
      expect(codes, isNot(contains('await-result-type-mismatch')));
      for (final diagnostic in ambiguousDiagnostics) {
        final fixes = service.quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: diagnostic,
          analysis: analysis,
        );

        expect(
          fixes.map((fix) => fix.label),
          containsAll(['Remove import `lib/a`', 'Remove import `lib/b`']),
        );
      }
    },
  );

  test('keeps ambiguous import fixes only when other used exports survive', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/a.styio',
        text: '''
fn calibrate(value: f64): f64 { emit value }
fn format(value: f64): string { emit "value" }
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/b.styio',
        text: 'fn calibrate(value: f64): f64 { emit value }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/a }
@import { lib/b }
price = 1.0
value = calibrate(price)
label = format(price)
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final ambiguous = analysis
        .diagnosticsFor('main.styio')
        .singleWhere(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'ambiguous-imported-symbol',
        );
    final fixes = service.quickFixesForProjectDiagnostic(
      documents: documents,
      diagnostic: ambiguous,
      analysis: analysis,
    );

    expect(fixes.map((fix) => fix.label), ['Remove import `lib/b`']);
    expect(applyEdits(documents.last.text, fixes.single.edits), '''
@import { lib/a }
price = 1.0
value = calibrate(price)
label = format(price)
''');
  });

  test('reports cyclic local imports', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/a.styio',
        text: '''
@import { lib/b }
fn a(value: f64): f64 { emit value }
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/b.styio',
        text: '''
@import { lib/a }
fn b(value: f64): f64 { emit value }
''',
        revision: 0,
      ),
    ];

    final diagnostics = service.analyzeProject(documents).diagnostics;

    expect(
      diagnostics.map((diagnostic) => diagnostic.diagnostic.code),
      contains('import-cycle'),
    );
    final cycle = diagnostics.firstWhere(
      (diagnostic) => diagnostic.diagnostic.code == 'import-cycle',
    );
    final fix = service
        .quickFixesForProjectDiagnostic(documents: documents, diagnostic: cycle)
        .single;
    final cycleDocument = documents.singleWhere(
      (document) => document.documentId == cycle.documentId,
    );
    final fixedText = applyEdits(cycleDocument.text, fix.edits);

    expect(fix.label, 'Remove cyclic import');
    expect(fixedText, isNot(contains('@import')));
    expect(fixedText, contains('fn '));
  });

  test('offers deterministic workspace import cleanup fixes', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/a.styio',
        text: '''
@import { lib/b }
fn a(value: f64): f64 { emit value }
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/b.styio',
        text: '''
@import { lib/a }
fn b(value: f64): f64 { emit value }
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/missing }
value = 1
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final fix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
        )
        .singleWhere((fix) => fix.label == 'Clean up project imports');

    expect(fix.label, 'Clean up project imports');
    expect(
      fix.editsByDocument.keys,
      containsAll(['lib/a.styio', 'lib/b.styio', 'main.styio']),
    );
    expect(
      applyEdits(documents.first.text, fix.editsByDocument['lib/a.styio']!),
      '''
fn a(value: f64): f64 { emit value }
''',
    );
    expect(
      applyEdits(documents.last.text, fix.editsByDocument['main.styio']!),
      '''
value = 1
''',
    );
  });

  test('reports unused local imports', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: 'fn blend(left: f64, right: f64): f64 { emit left + right }\n',
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

    final diagnostics = service
        .analyzeProject(documents)
        .diagnosticsFor('main.styio');

    expect(
      diagnostics.map((diagnostic) => diagnostic.diagnostic.code),
      contains('unused-import'),
    );
    final unused = diagnostics.singleWhere(
      (diagnostic) => diagnostic.diagnostic.code == 'unused-import',
    );
    final fix = service
        .quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: unused,
        )
        .single;

    expect(fix.label, 'Remove unused import');
    expect(applyEdits(documents.last.text, fix.edits), '''
value = 1
''');
    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: diagnostics,
        )
        .single;

    expect(workspaceFix.label, 'Clean up project imports');
    expect(
      applyEdits(
        documents.last.text,
        workspaceFix.editsByDocument['main.styio']!,
      ),
      '''
value = 1
''',
    );
  });

  test('reports exported project symbols with no references', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@usedPrices : f64|..2| := {}
@unusedPrices : f64|..2| := {}
usedTask = ||> { <| 42 }
unusedTask = ||> { <| 42 }

fn usedBlend(left: f64, right: f64): f64 {
  emit left + right
}

fn unusedBlend(left: f64, right: f64): f64 {
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
price -> @usedPrices
value = usedBlend(price, 2.0)
?| usedTask -> result: i64
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final diagnostics = analysis
        .diagnosticsFor('lib/runtime.styio')
        .where(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'unused-exported-symbol',
        )
        .toList(growable: false);
    final messages = diagnostics.map(
      (diagnostic) => diagnostic.diagnostic.message,
    );

    expect(diagnostics, hasLength(3));
    expect(messages, contains(contains('unusedPrices')));
    expect(messages, contains(contains('unusedTask')));
    expect(messages, contains(contains('unusedBlend')));

    final fixes = [
      for (final diagnostic in diagnostics)
        service
            .quickFixesForProjectDiagnostic(
              documents: documents,
              diagnostic: diagnostic,
            )
            .single,
    ];
    final cleaned = applyEdits(
      documents.first.text,
      fixes.expand((fix) => fix.edits),
    );

    expect(fixes.map((fix) => fix.label).toSet(), {
      'Remove unused exported symbol',
    });
    expect(cleaned, contains('@usedPrices'));
    expect(cleaned, contains('usedTask'));
    expect(cleaned, contains('usedBlend'));
    expect(cleaned, isNot(contains('unusedPrices')));
    expect(cleaned, isNot(contains('unusedTask')));
    expect(cleaned, isNot(contains('unusedBlend')));

    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .single;

    expect(workspaceFix.label, 'Remove unused exported symbols');
    expect(workspaceFix.detail, contains('no project references'));
    expect(workspaceFix.editsByDocument.keys, ['lib/runtime.styio']);
    expect(
      applyEdits(
        documents.first.text,
        workspaceFix.editsByDocument['lib/runtime.styio']!,
      ),
      cleaned,
    );
  });

  test(
    'keeps workspace import cleanup separate from exported symbol cleanup',
    () {
      const service = ProjectStyioLanguageService();
      const documents = [
        DocumentState(
          documentId: 'lib/math.styio',
          text:
              'fn unusedBlend(left: f64, right: f64): f64 { emit left + right }\n',
          revision: 0,
        ),
        DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/missing }
value = 1
''',
          revision: 0,
        ),
      ];

      final analysis = service.analyzeProject(documents);
      final fixes = service.workspaceQuickFixesForProjectDiagnostics(
        documents: documents,
        diagnostics: analysis.diagnostics,
        analysis: analysis,
      );

      expect(fixes.map((fix) => fix.label), [
        'Clean up project imports',
        'Remove unused exported symbols',
      ]);
      expect(fixes[0].editsByDocument.keys, ['main.styio']);
      expect(fixes[1].editsByDocument.keys, ['lib/math.styio']);
      expect(
        applyEdits(
          documents.last.text,
          fixes[0].editsByDocument['main.styio']!,
        ),
        '''
value = 1
''',
      );
      expect(
        applyEdits(
          documents.first.text,
          fixes[1].editsByDocument['lib/math.styio']!,
        ),
        '',
      );
    },
  );

  test('offers workspace cleanup for duplicate and unsorted imports', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { styio/io }
@import { styio/core }
@import { styio/io }
value = 1
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/sorted.styio',
        text: '''
@import { styio/io }
@import { styio/core }
ready = true
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final fix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Clean up project imports');

    expect(
      applyEdits(documents.first.text, fix.editsByDocument['main.styio']!),
      '''
@import { styio/core }
@import { styio/io }
value = 1
''',
    );
    expect(
      applyEdits(documents.last.text, fix.editsByDocument['lib/sorted.styio']!),
      '''
@import { styio/core }
@import { styio/io }
ready = true
''',
    );
  });

  test('offers workspace cleanup for duplicate runtime declarations', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@prices : f64|..2| := {}
@prices : string|..2| := {}
load = ||> { <| 1 }
load = ||> {
  <| 2
}
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final fix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere(
          (fix) => fix.label == 'Remove duplicate Styio runtime declarations',
        );

    expect(
      applyEdits(
        documents.single.text,
        fix.editsByDocument['lib/runtime.styio']!,
      ),
      '''
@prices : f64|..2| := {}
load = ||> { <| 1 }
''',
    );
  });

  test('offers workspace cleanup for read-only resource writes', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'main.styio',
        text: '''
price = 1
price -> @stdin
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final fix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Remove invalid resource writes');

    expect(
      applyEdits(documents.single.text, fix.editsByDocument['main.styio']!),
      '''
price = 1
''',
    );
  });

  test('offers workspace cleanup for unreachable code', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn stop(value: f64): f64 {
  emit value
  next = value + 1.0
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
load = ||> {
  <| 1
  next = 2
}
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final fix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Remove unreachable project code');

    expect(
      applyEdits(documents.first.text, fix.editsByDocument['lib/math.styio']!),
      '''
fn stop(value: f64): f64 {
  emit value
}
''',
    );
    expect(
      applyEdits(documents.last.text, fix.editsByDocument['main.styio']!),
      '''
load = ||> {
  <| 1
}
''',
    );
  });

  test('offers workspace cleanup for redundant syntax', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'main.styio',
        text: '''
price: f64 = 12.5
ready = true
label = (ready)
label -> @stdout
price -> @stdout
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/counts.styio',
        text: '''
count: i64 = 3
value = (count)
count -> @stdout
value -> @stdout
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final fix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Clean up redundant project syntax');

    expect(
      applyEdits(documents.first.text, fix.editsByDocument['main.styio']!),
      '''
price = 12.5
ready = true
label = ready
label -> @stdout
price -> @stdout
''',
    );
    expect(
      applyEdits(documents.last.text, fix.editsByDocument['lib/counts.styio']!),
      '''
count = 3
value = count
count -> @stdout
value -> @stdout
''',
    );
  });

  test('offers workspace simplification for project expressions', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'main.styio',
        text: '''
total = 42
next = total + 0
ready = true
when !true -> state never
when ready == true -> state ready
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/flags.styio',
        text: '''
ready = true
blocked = false
when ready && true -> state ready
when !(ready && blocked) -> state open
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final fix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Simplify project expressions');

    expect(
      applyEdits(documents.first.text, fix.editsByDocument['main.styio']!),
      '''
total = 42
next = total
ready = true
when false -> state never
when ready -> state ready
''',
    );
    expect(
      applyEdits(documents.last.text, fix.editsByDocument['lib/flags.styio']!),
      '''
ready = true
blocked = false
when ready -> state ready
when !ready || !blocked -> state open
''',
    );
  });

  test('keeps workspace expression simplification edits non-overlapping', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'main.styio',
        text: '''
ready = true
when !(ready && true) -> state complex
when ready == true -> state direct
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final expressionDiagnostics = analysis
        .diagnosticsFor('main.styio')
        .where(
          (diagnostic) =>
              diagnostic.diagnostic.code.startsWith('simplifiable-'),
        );
    final fix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Simplify project expressions');
    final edits = fix.editsByDocument['main.styio']!;

    expect(expressionDiagnostics.length, greaterThan(1));
    for (var left = 0; left < edits.length; left += 1) {
      for (var right = left + 1; right < edits.length; right += 1) {
        expect(
          formattingEditsConflictForTest(edits[left], edits[right]),
          isFalse,
        );
      }
    }
  });

  test('offers workspace type fixes for missing hash function returns', () {
    const service = ProjectStyioLanguageService();
    final documents = [
      DocumentState(
        documentId: 'main.styio',
        text: styioLanguageFixture(
          'workspace_missing_hash_returns/main.false.styio',
        ),
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/counts.styio',
        text: styioLanguageFixture(
          'workspace_missing_hash_returns/lib/counts.false.styio',
        ),
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final fix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Fix project type mismatches');

    expect(
      applyEdits(documents.first.text, fix.editsByDocument['main.styio']!),
      styioLanguageFixture(
        'workspace_missing_hash_returns/expected/main.expected.false.styio',
      ),
    );
    expect(
      applyEdits(documents.last.text, fix.editsByDocument['lib/counts.styio']!),
      styioLanguageFixture(
        'workspace_missing_hash_returns/expected/lib/counts.expected.false.styio',
      ),
    );
  });

  test('does not count import target paths as exported symbol references', () {
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

    final diagnostics = service
        .analyzeProject(documents)
        .diagnosticsFor('lib/math.styio')
        .where(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'unused-exported-symbol',
        )
        .toList(growable: false);

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.diagnostic.message, contains('math'));
  });

  test('reuses project analysis when producing project quick fixes', () {
    final documentService = _CountingStyioLanguageService();
    final service = ProjectStyioLanguageService(
      documentService: documentService,
    );
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: 'fn blend(left: f64, right: f64): f64 { emit left + right }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
price = 1.0
total = blend(price, 2.0)
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final unresolved = analysis
        .diagnosticsFor('main.styio')
        .singleWhere(
          (diagnostic) =>
              diagnostic.diagnostic.code == 'unresolved-reference' &&
              documents.last.text.substring(
                    diagnostic.diagnostic.range.start,
                    diagnostic.diagnostic.range.end,
                  ) ==
                  'blend',
        );
    final fixes = service.quickFixesForProjectDiagnostic(
      documents: documents,
      diagnostic: unresolved,
      analysis: analysis,
    );

    expect(
      fixes.map((fix) => fix.label),
      contains('Import `blend` from lib/math'),
    );
    expect(
      documentService.analyzedDocuments,
      equals(['lib/math.styio:0', 'main.styio:0']),
    );
  });

  test('reuses cached document analyses until revision or text changes', () {
    final documentService = _CountingStyioLanguageService();
    final cache = StyioProjectAnalysisCache();
    final service = ProjectStyioLanguageService(
      documentService: documentService,
      analysisCache: cache,
    );
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: 'fn blend(left: f64, right: f64): f64 { emit left + right }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
price = 1.0
tax = 0.5
total = blend(price, tax)
''',
        revision: 0,
      ),
    ];

    service.analyzeProject(documents);
    service.analyzeProject(documents);

    expect(
      documentService.analyzedDocuments,
      equals(['lib/math.styio:0', 'main.styio:0']),
    );
    expect(cache.documentCount, 2);
    expect(cache.projectIndexCount, 2);
    expect(cache.projectIndexCacheMisses, 2);
    expect(cache.projectIndexCacheHits, 2);

    service.analyzeProject(const [
      DocumentState(
        documentId: 'lib/math.styio',
        text: 'fn blend(left: f64, right: f64): f64 { emit left + right }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
price = 1.0
tax = 0.5
total = blend(price, tax)
next = blend(total, tax)
''',
        revision: 1,
      ),
    ]);

    expect(
      documentService.analyzedDocuments,
      equals(['lib/math.styio:0', 'main.styio:0', 'main.styio:1']),
    );
    expect(cache.projectIndexCount, 2);
    expect(cache.projectIndexCacheMisses, 3);
    expect(cache.projectIndexCacheHits, 3);
  });

  test('reuses project indexes across a larger workspace', () {
    final cache = StyioProjectAnalysisCache();
    final service = ProjectStyioLanguageService(analysisCache: cache);
    final libraries = [
      for (var index = 0; index < 32; index += 1)
        DocumentState(
          documentId: 'lib/pkg_$index.styio',
          text: 'fn fn$index(value: f64): f64 { emit value }\n',
          revision: 0,
        ),
    ];
    final documents = [
      ...libraries,
      const DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/pkg_0 }
value = fn0(1.0)
''',
        revision: 0,
      ),
    ];

    service.analyzeProject(documents);
    service.analyzeProject(documents);

    expect(cache.projectIndexCount, documents.length);
    expect(cache.projectIndexCacheMisses, documents.length);
    expect(cache.projectIndexCacheHits, documents.length);

    final changedDocuments = [...documents];
    changedDocuments[7] = const DocumentState(
      documentId: 'lib/pkg_7.styio',
      text: 'fn fn7(value: f64): f64 { emit value + 1.0 }\n',
      revision: 1,
    );
    service.analyzeProject(changedDocuments);

    expect(cache.projectIndexCount, documents.length);
    expect(cache.projectIndexCacheMisses, documents.length + 1);
    expect(cache.projectIndexCacheHits, documents.length * 2 - 1);
  });

  test('reports imported conditional task returns', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
load = ||> {
  ready = false
  when ready -> <| 1
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
?| load -> result: i64
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final mainCodes = analysis
        .diagnosticsFor('main.styio')
        .map((diagnostic) => diagnostic.diagnostic.code);

    expect(mainCodes, contains('conditional-task-return'));
    expect(mainCodes, isNot(contains('missing-task-return')));
    expect(mainCodes, isNot(contains('await-result-type-mismatch')));

    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Fix project type mismatches');

    expect(
      applyEdits(
        documents.first.text,
        workspaceFix.editsByDocument['lib/runtime.styio']!,
      ),
      '''
load = ||> {
  ready = false
  when ready -> <| 1
  <| 0
}
''',
    );
  });

  test(
    'uses imported task binary return expressions in project diagnostics',
    () {
      const service = ProjectStyioLanguageService();
      const documents = [
        DocumentState(
          documentId: 'lib/runtime.styio',
          text: '''
load = ||> {
  count = 41
  <| (count + 1)
}
ready = ||> {
  count = 41
  <| count > 0 && true
}
ratio = ||> {
  value = 10.0
  <| value / 2
}
either = ||> {
  count = 41
  <| (count > 0) || false
}
''',
          revision: 0,
        ),
        DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/runtime }
?| load -> result: i64
?| ready -> ok: bool
?| ratio -> scaled: f64
?| either -> selected: bool
''',
          revision: 0,
        ),
      ];

      final codes = service
          .analyzeProject(documents)
          .diagnosticsFor('main.styio')
          .map((diagnostic) => diagnostic.diagnostic.code);

      expect(codes, isNot(contains('missing-task-return')));
      expect(codes, isNot(contains('await-result-type-mismatch')));
    },
  );

  test('reports imported task invalid return expressions', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
load = ||> {
  count = 1
  <| count && true
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
?| load -> ok: bool
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final mainCodes = analysis
        .diagnosticsFor('main.styio')
        .map((diagnostic) => diagnostic.diagnostic.code);

    expect(mainCodes, contains('invalid-task-return-expression'));
    expect(mainCodes, isNot(contains('missing-task-return')));

    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Fix project type mismatches');

    expect(
      applyEdits(
        documents.first.text,
        workspaceFix.editsByDocument['lib/runtime.styio']!,
      ),
      '''
load = ||> {
  count = 1
  <| false
}
''',
    );
  });

  test('includes local invalid task return expressions in workspace fixes', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'main.styio',
        text: '''
load = ||> {
  count = 1
  <| count && true
}
?| load -> ok: bool
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    final workspaceFix = service
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        )
        .singleWhere((fix) => fix.label == 'Fix project type mismatches');

    expect(
      applyEdits(
        documents.single.text,
        workspaceFix.editsByDocument['main.styio']!,
      ),
      '''
load = ||> {
  count = 1
  <| false
}
?| load -> ok: bool
''',
    );
  });

  test(
    'blocks imported invalid task return fixes for conflicting await types',
    () {
      const service = ProjectStyioLanguageService();
      const documents = [
        DocumentState(
          documentId: 'lib/runtime.styio',
          text: '''
load = ||> {
  count = 1
  <| count && true
}
''',
          revision: 0,
        ),
        DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/runtime }
?| load -> ok: bool
''',
          revision: 0,
        ),
        DocumentState(
          documentId: 'metrics.styio',
          text: '''
@import { lib/runtime }
?| load -> result: i64
''',
          revision: 0,
        ),
      ];

      final analysis = service.analyzeProject(documents);

      expect(
        analysis
            .diagnosticsFor('main.styio')
            .map((diagnostic) => diagnostic.diagnostic.code),
        contains('invalid-task-return-expression'),
      );
      expect(
        analysis
            .diagnosticsFor('metrics.styio')
            .map((diagnostic) => diagnostic.diagnostic.code),
        contains('invalid-task-return-expression'),
      );
      expect(
        service
            .workspaceQuickFixesForProjectDiagnostics(
              documents: documents,
              diagnostics: analysis.diagnostics,
              analysis: analysis,
            )
            .where((fix) => fix.label == 'Fix project type mismatches'),
        isEmpty,
      );
    },
  );

  test(
    'infers imported task return types from constant true guarded returns',
    () {
      const service = ProjectStyioLanguageService();
      const documents = [
        DocumentState(
          documentId: 'lib/runtime.styio',
          text: '''
fn makeCount(): i64 {
  emit 1
}
load = ||> {
  when true && !false -> <| makeCount()
}
''',
          revision: 0,
        ),
        DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/runtime }
?| load -> result: i64
''',
          revision: 0,
        ),
      ];

      final mainCodes = service
          .analyzeProject(documents)
          .diagnosticsFor('main.styio')
          .map((diagnostic) => diagnostic.diagnostic.code);

      expect(mainCodes, isNot(contains('missing-task-return')));
      expect(mainCodes, isNot(contains('await-result-type-mismatch')));
    },
  );

  test('handles zero-parameter project calls in parameter info', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
fn tick(): i64 {
  emit 1
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
value = tick()
''',
        revision: 0,
      ),
    ];
    final source = documents.last.text;

    final info = service.parameterInfoAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('tick()') + 'tick('.length,
    );

    expect(info!.callableName, 'tick');
    expect(info.parameters, isEmpty);
    expect(info.activeParameterIndex, -1);
    expect(info.activeParameter, isNull);
  });

  test('parses nested and quoted project named argument completion segments', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn blend(left: f64, right: f64, scale: string = "1"): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
value = blend(left: (1.0 + 2.0), scale: "fast,slow", ri)
''',
        revision: 0,
      ),
    ];
    final source = documents.last.text;

    final items = service.namedArgumentCompletionsAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('ri)') + 2,
    );

    expect(items.map((item) => item.label), ['right:']);
    expect(items.single.replacementRange!.start, source.indexOf('ri)'));
  });

  test('orders tied imported argument and import target suggestions', () {
    const service = ProjectStyioLanguageService();
    const argumentDocuments = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: '''
fn blend(abc: f64, abd: f64): f64 {
  emit abc + abd
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
value = blend(abe: 1.0, abd: 2.0)
''',
        revision: 0,
      ),
    ];
    final argumentAnalysis = service.analyzeProject(argumentDocuments);
    final unknownArgument = argumentAnalysis
        .diagnosticsFor('main.styio')
        .singleWhere(
          (diagnostic) => diagnostic.diagnostic.code == 'unknown-named-argument',
        );

    final argumentFix = service
        .quickFixesForProjectDiagnostic(
          documents: argumentDocuments,
          diagnostic: unknownArgument,
          analysis: argumentAnalysis,
        )
        .singleWhere((fix) => fix.label.startsWith('Change argument name'));

    expect(argumentFix.label, 'Change argument name to `abc`');

    const importDocuments = [
      DocumentState(
        documentId: 'lib/bat.styio',
        text: 'value = 1\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/cat.styio',
        text: 'value = 2\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/mat }
value = 1
''',
        revision: 0,
      ),
    ];
    final importAnalysis = service.analyzeProject(importDocuments);
    final unresolvedImport = importAnalysis
        .diagnosticsFor('main.styio')
        .singleWhere(
          (diagnostic) => diagnostic.diagnostic.code == 'unresolved-import',
        );

    final importFixLabels = service
        .quickFixesForProjectDiagnostic(
          documents: importDocuments,
          diagnostic: unresolvedImport,
          analysis: importAnalysis,
        )
        .map((fix) => fix.label)
        .where((label) => label.startsWith('Change import'))
        .toList(growable: false);

    expect(importFixLabels, [
      'Change import to `lib/bat`',
      'Change import to `lib/cat`',
    ]);
  });

  test('project analysis cache clears document and project index entries', () {
    final cache = StyioProjectAnalysisCache();
    final service = ProjectStyioLanguageService(analysisCache: cache);
    const documents = [
      DocumentState(
        documentId: 'main.styio',
        text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}
value = blend(1.0, 2.0)
''',
        revision: 0,
      ),
    ];

    service.analyzeProject(documents);
    service.analyzeProject(documents);

    expect(cache.documentCount, 1);
    expect(cache.projectIndexCount, 1);
    expect(cache.projectIndexCacheHits, greaterThan(0));

    cache.clear();

    expect(cache.documentCount, 0);
    expect(cache.projectIndexCount, 0);
    expect(cache.projectIndexCacheHits, 0);
    expect(cache.projectIndexCacheMisses, 0);
  });
}

class _CountingStyioLanguageService extends SimpleStyioLanguageService {
  final List<String> analyzedDocuments = <String>[];

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    analyzedDocuments.add('${document.documentId}:${document.revision}');
    return super.analyzeDocument(document);
  }
}
