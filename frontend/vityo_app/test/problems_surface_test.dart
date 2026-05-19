import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/problems/problems.dart';

void main() {
  testWidgets('problems surface renders diagnostics and selects entries', (
    tester,
  ) async {
    Diagnostic? selectedDiagnostic;
    const diagnostics = <Diagnostic>[
      Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'syntax-error',
        message: 'Unexpected token.',
        range: SourceRange(start: 0, end: 5),
      ),
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'unused-value',
        message: 'Unused value.',
        range: SourceRange(start: 6, end: 11),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProblemsSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            documentId: 'src/main.styio',
            diagnostics: diagnostics,
            onSelectDiagnostic: (diagnostic) {
              selectedDiagnostic = diagnostic;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('problems-surface')), findsOneWidget);
    expect(find.text('Problems'), findsOneWidget);
    expect(find.text('document src/main.styio'), findsOneWidget);
    expect(find.text('total 2'), findsOneWidget);
    expect(find.text('error 1'), findsOneWidget);
    expect(find.text('warning 1'), findsOneWidget);
    expect(find.text('Unexpected token.'), findsOneWidget);
    expect(find.text('Unused value.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('problems-diagnostic-syntax-error')),
    );
    await tester.pump();

    expect(selectedDiagnostic?.code, 'syntax-error');
  });
}
