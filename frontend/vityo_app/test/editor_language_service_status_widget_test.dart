import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_capability_detector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_runtime.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('editor surface renders language service status', (tester) async {
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://editor-status',
      revision: 1,
      completions: <CompletionItem>[
        CompletionItem(
          label: 'value',
          kind: CompletionItemKind.variable,
          insertText: 'value',
        ),
      ],
    );
    final status = LanguageServiceStatusSurface.fromRuntimeSnapshot(
      StyioServiceRuntimeStatusSnapshot(
        state: StyioServiceRuntimeSessionState.active,
        disposed: false,
        providerManifest: LanguageProviderRegistry<String>().manifest(),
        capabilitySnapshot: const StyioServiceCapabilityDetector().detect(
          response,
        ),
        cacheSnapshot: const StyioServiceResultCacheSnapshot(
          entries: <StyioServiceResultCacheEntry>[],
          lookupHits: 3,
          lookupMisses: 1,
        ),
      ),
    );
    var refreshRequested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: EditorSurface(
              controller: EditorSessionController(
                initialDocument: const DocumentState(
                  documentId: 'fixture://editor-status',
                  text: 'value := 1\nvalue\n',
                  revision: 1,
                ),
                languageService: const LocalStyioLanguageService(),
              ),
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 800,
              ),
              languageServiceStatus: status,
              onRefreshLanguageService: () {
                refreshRequested = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('language-service-status-card')),
      findsOneWidget,
    );
    expect(find.text('StyioService ready'), findsOneWidget);
    expect(find.text('health degraded'), findsOneWidget);
    expect(find.textContaining('missing '), findsWidgets);
    expect(find.text('cache lookups 4'), findsOneWidget);
    expect(find.text('cache hits 3'), findsOneWidget);
    expect(find.text('cache misses 1'), findsOneWidget);
    expect(find.textContaining('completion available'), findsOneWidget);
    final refreshAction = find.byKey(
      const ValueKey('language-service-refresh-action'),
    );
    tester.widget<OutlinedButton>(refreshAction).onPressed!();
    expect(refreshRequested, isTrue);
  });

  testWidgets('editor surface renders unsupported language capability', (
    tester,
  ) async {
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://editor-status-unsupported',
      revision: 1,
      capabilityStates: <String, String>{
        'diagnostics': 'available',
        'completion': 'available',
        'hover': 'unsupported',
      },
    );
    final status = LanguageServiceStatusSurface.fromRuntimeSnapshot(
      StyioServiceRuntimeStatusSnapshot(
        state: StyioServiceRuntimeSessionState.active,
        disposed: false,
        providerManifest: LanguageProviderRegistry<String>().manifest(),
        capabilitySnapshot: const StyioServiceCapabilityDetector().detect(
          response,
          expectedCapabilities: <StyioServiceCapability>[
            StyioServiceCapability.diagnostics,
            StyioServiceCapability.completion,
            StyioServiceCapability.hover,
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: EditorSurface(
              controller: EditorSessionController(
                initialDocument: const DocumentState(
                  documentId: 'fixture://editor-status-unsupported',
                  text: 'value := 1\nvalue\n',
                  revision: 1,
                ),
                languageService: const LocalStyioLanguageService(),
              ),
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 800,
              ),
              languageServiceStatus: status,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('language-service-status-card')),
      findsOneWidget,
    );
    expect(find.textContaining('hover unsupported'), findsOneWidget);
    expect(find.text('health degraded'), findsOneWidget);
    expect(find.text('blocked 1'), findsOneWidget);
  });

  testWidgets('editor surface exposes unavailable language service refresh', (
    tester,
  ) async {
    var refreshRequested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: EditorSurface(
              controller: EditorSessionController(
                initialDocument: const DocumentState(
                  documentId: 'fixture://editor-status-unavailable',
                  text: 'value := 1\nvalue\n',
                  revision: 1,
                ),
                languageService: const LocalStyioLanguageService(),
              ),
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 800,
              ),
              languageServiceStatus: LanguageServiceStatusSurface.unavailable(),
              onRefreshLanguageService: () {
                refreshRequested = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('language-service-status-card')),
      findsOneWidget,
    );
    expect(find.text('StyioService unavailable'), findsOneWidget);

    final refreshAction = find.byKey(
      const ValueKey('language-service-refresh-action'),
    );
    tester.widget<OutlinedButton>(refreshAction).onPressed!();
    expect(refreshRequested, isTrue);
  });
}
