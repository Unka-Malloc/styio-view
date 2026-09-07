import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart' hide TextRange;
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

import '../benchmark/fixture_generator.dart';

final Map<int, RenderedEditorFixture> _fixtureCache =
    <int, RenderedEditorFixture>{};

const _profileEnabled = bool.fromEnvironment('VITYO_RENDERED_INPUT_PROFILE');
const _writeBaselineEnabled = bool.fromEnvironment(
  'VITYO_WRITE_RENDERED_INPUT_BASELINE',
);

RenderedEditorFixture _cachedFixture(int lineCount) {
  return _fixtureCache.putIfAbsent(
    lineCount,
    () => FixtureGenerator(
      config: FixtureConfig(lineCount: lineCount),
    ).generateRenderedEditorFixture(),
  );
}

/// Rendered profile evidence for REQ-INPUT-004 on a declared desktop host.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'measures rendered editor input lanes',
    (tester) async {
      final platformFamily = _detectPlatformFamily();
      if (!platformFamily.startsWith('desktop-')) {
        return;
      }

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const harness = EditorRenderedInputProfileHarness();
      const viewportWidth = 1200;
      const viewportHeight = 800;
      final viewportLineLimit =
          EditorRenderedInputSampleProtocol.viewportLineCap(
            viewportLineCapacity:
                (720 / EditorSurfaceProfileFacts.lineHeightPixels).ceil(),
            overscanLineCount: EditorSurfaceProfileFacts.overscanLineCount,
            hardCap: EditorSurfaceProfileFacts.maxRenderedPreviewLines,
          );

      final measurements = <EditorRenderedInputLaneMeasurements>[];

      for (final lineCount
          in EditorRenderedInputProfileHarness.fixtureLineCounts) {
        final fixture = _cachedFixture(lineCount);

        for (final substitution in <bool>[false, true]) {
          final controller = EditorSessionController(
            initialDocument: DocumentState(
              documentId: 'profile-$lineCount.styio',
              text: fixture.text,
              revision: 0,
            ),
            languageService: const LocalStyioLanguageService(),
          );
          controller.setGlyphSubstitutionEnabled(substitution);
          addTearDown(controller.dispose);

          await tester.pumpWidget(_harness(controller));
          await tester.pump();
          await _focusSource(tester);

          for (final operation
              in EditorRenderedInputProfileHarness.operations) {
            if (operation == EditorRenderedInputOperation.multiCursorMovement) {
              _ensureMultiCursor(controller);
              await tester.pump();
            }
            measurements.add(
              await _measureLane(
                tester: tester,
                controller: controller,
                fixture: fixture,
                operation: operation,
                glyphSubstitutionEnabled: substitution,
                viewportLineLimit: viewportLineLimit,
              ),
            );
          }
        }
      }

      final receipt = harness.buildProfileReceipt(
        platformFamily: platformFamily,
        measurements: measurements,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
      );

      if (_writeBaselineEnabled) {
        final repoRoot = _repositoryRoot();
        harness.writeBaselineFiles(
          receipt: receipt,
          jsonPath: '$repoRoot/docs/review/performance-baseline.json',
          markdownPath: '$repoRoot/docs/review/performance-baseline.md',
          jsonProjection: 'docs/review/performance-baseline.json',
        );
      }

      expect(receipt.lanes, hasLength(measurements.length));
      for (final lane in receipt.lanes) {
        expect(
          lane.evidenceKind,
          EditorPerformanceEvidenceKind.renderedProfile,
        );
        expect(lane.warmupCount, 10);
        expect(lane.sampleCount, 40);
        expect(lane.correlatedFrameCount, 40);
        expect(lane.renderedLineCount, lessThanOrEqualTo(viewportLineLimit));
      }
      expect(
        harness.receiptPassesGate(receipt),
        isTrue,
        reason: _profileFailureSummary(harness, receipt),
      );
      expect(receipt.status, 'passed');
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: !_profileEnabled,
  );
}

String _profileFailureSummary(
  EditorRenderedInputProfileHarness harness,
  EditorRenderedInputProfileReceipt receipt,
) {
  final failures = <String>[];
  for (final lane in receipt.lanes) {
    final result = harness.gate.evaluateRendered(lane);
    if (!result.passed) {
      failures.add(
        '${lane.fixtureLineCount}/${lane.operation.label}/'
        '${lane.glyphSubstitutionEnabled ? 'on' : 'off'}:'
        '${result.status.name}',
      );
    }
  }
  return failures.isEmpty
      ? 'A substitution-delta lane exceeded its budget.'
      : failures.join(', ');
}

/// Stable editor-surface facts mirrored for viewport-cap computation.
abstract final class EditorSurfaceProfileFacts {
  static const double lineHeightPixels = 34;
  static const int overscanLineCount = 8;
  static const int maxRenderedPreviewLines = 400;
}

Future<EditorRenderedInputLaneMeasurements> _measureLane({
  required WidgetTester tester,
  required EditorSessionController controller,
  required RenderedEditorFixture fixture,
  required EditorRenderedInputOperation operation,
  required bool glyphSubstitutionEnabled,
  required int viewportLineLimit,
}) async {
  final context = _LaneMeasureContext(
    tester: tester,
    controller: controller,
    fixture: fixture,
  );

  final warmups = <int>[];
  final measured = <int>[];
  final renderedCounts = <int>[];

  for (var index = 0; index < 50; index += 1) {
    await context.reset(operation);
    final stopwatch = Stopwatch()..start();
    await context.perform(operation, index);
    await tester.pump();
    stopwatch.stop();

    final micros = stopwatch.elapsedMicroseconds;
    final rendered = _countRenderedLines(tester);
    if (index < 10) {
      warmups.add(micros);
    } else {
      measured.add(micros);
      renderedCounts.add(rendered);
    }
  }

  return EditorRenderedInputLaneMeasurements(
    fixtureLineCount: fixture.lineCount,
    fixtureFingerprint: fixture.fingerprint,
    operation: operation,
    glyphSubstitutionEnabled: glyphSubstitutionEnabled,
    warmupLatencyMicros: warmups,
    measuredLatencyMicros: measured,
    renderedLineCounts: renderedCounts,
    viewportLineLimit: viewportLineLimit,
    operationSeed: fixture.lineCount,
  );
}

final class _LaneMeasureContext {
  _LaneMeasureContext({
    required this.tester,
    required this.controller,
    required this.fixture,
  });

  final WidgetTester tester;
  final EditorSessionController controller;
  final RenderedEditorFixture fixture;

  Future<void> perform(
    EditorRenderedInputOperation operation,
    int sampleIndex,
  ) async {
    switch (operation) {
      case EditorRenderedInputOperation.typing:
        _commitRemoteReplacement('x');
      case EditorRenderedInputOperation.compositionUpdate:
        tester.testTextInput.updateEditingValue(
          _replaceRemoteSelection(
            _currentRemoteEditingValue(),
            '候',
            composing: true,
          ),
        );
      case EditorRenderedInputOperation.compositionCommit:
        tester.testTextInput.updateEditingValue(
          _replaceRemoteSelection(
            _currentRemoteEditingValue(),
            '字',
            composing: false,
          ),
        );
      case EditorRenderedInputOperation.multiCursorMovement:
        _moveAllCursorsHorizontally(1);
      case EditorRenderedInputOperation.rectangularProjection:
        _projectSampleRectangle(sampleIndex);
      case EditorRenderedInputOperation.viewportMovement:
        await tester.drag(
          _sourceScrollable(),
          Offset(0, sampleIndex.isEven ? -34 : 34),
        );
    }
  }

  Future<void> reset(EditorRenderedInputOperation operation) async {
    switch (operation) {
      case EditorRenderedInputOperation.typing:
      case EditorRenderedInputOperation.compositionCommit:
        if (controller.historyController.undoDepth > 0) {
          controller.undo();
        }
      case EditorRenderedInputOperation.compositionUpdate:
        if (_currentRemoteEditingValue().composing.isValid) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
      case EditorRenderedInputOperation.multiCursorMovement:
        _ensureMultiCursor(controller);
      case EditorRenderedInputOperation.rectangularProjection:
        controller.selectCollapsed(
          controller.document.offsetForLineColumn(line: 0, column: 0),
        );
      case EditorRenderedInputOperation.viewportMovement:
        await tester.drag(_sourceScrollable(), const Offset(0, 34));
    }
  }

  void _commitRemoteReplacement(String replacement) {
    tester.testTextInput.updateEditingValue(
      _replaceRemoteSelection(
        _currentRemoteEditingValue(),
        replacement,
        composing: false,
      ),
    );
  }

  void _moveAllCursorsHorizontally(int delta) {
    final documentLength = controller.document.length;
    final moved = controller.selectionSet.selections
        .map((selection) {
          final next = (selection.extentOffset + delta).clamp(
            0,
            documentLength,
          );
          return SelectionState.collapsed(
            next,
            affinity: selection.extentAffinity,
            desiredVisualX: selection.desiredVisualX,
          );
        })
        .toList(growable: false);
    controller.selectSelections(
      moved,
      primaryIndex: controller.selectionSet.primaryIndex,
    );
  }

  void _projectSampleRectangle(int sampleIndex) {
    final document = controller.document;
    final startLine = sampleIndex.isEven ? 0 : 4;
    final lines = <EditorRectangularLineProjection>[
      for (var offset = 0; offset < 3; offset += 1)
        EditorRectangularLineProjection(
          lineIndex: startLine + offset,
          left: EditorCaretPosition(
            offset: document.offsetForLineColumn(
              line: startLine + offset,
              column: 2,
            ),
          ),
          right: EditorCaretPosition(
            offset: document.offsetForLineColumn(
              line: startLine + offset,
              column: 6,
            ),
          ),
        ),
    ];
    controller.selectionController.projectRectangle(
      lines: lines,
      primaryLineIndex: startLine,
      horizontalDirection: EditorRectangleHorizontalDirection.leftToRight,
      documentLength: document.length,
    );
  }

  TextEditingValue _currentRemoteEditingValue() => _remoteEditingValue(tester);
}

Finder _sourceScrollable() {
  return find.descendant(
    of: find.byKey(const ValueKey('source-buffer-scroll')),
    matching: find.byType(Scrollable),
  );
}

int _countRenderedLines(WidgetTester tester) {
  return find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('source-line-');
      }, skipOffstage: false)
      .evaluate()
      .length;
}

String _detectPlatformFamily() {
  if (Platform.isMacOS) return 'desktop-macos';
  if (Platform.isWindows) return 'desktop-windows';
  if (Platform.isLinux) return 'desktop-linux';
  return 'unsupported';
}

String _repositoryRoot() {
  var current = Directory.current;
  while (!File(
    '${current.path}/products/vityo_app/pubspec.yaml',
  ).existsSync()) {
    if (current.parent.path == current.path) {
      return Directory.current.path;
    }
    current = current.parent;
  }
  return current.path;
}

Widget _harness(EditorSessionController controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1200,
        height: 800,
        child: EditorSurface(
          controller: controller,
          viewportProfile: const ViewportProfile(
            family: ViewportFamily.desktop,
            width: 1200,
            height: 800,
          ),
        ),
      ),
    ),
  );
}

Future<void> _focusSource(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('source-buffer-surface')));
  await tester.pump();
  await tester.pump();
}

void _ensureMultiCursor(EditorSessionController controller) {
  final document = controller.document;
  final offsets = <int>[
    document.offsetForLineColumn(line: 0, column: 0),
    document.offsetForLineColumn(line: 2, column: 4),
    document.offsetForLineColumn(line: 4, column: 8),
  ];
  controller.selectSelections(
    offsets.map(SelectionState.collapsed).toList(growable: false),
    primaryIndex: 0,
  );
}

TextEditingValue _remoteEditingValue(WidgetTester tester) {
  final state = tester.testTextInput.editingState;
  expect(state, isNotNull, reason: 'the editor must publish editing state');
  return TextEditingValue(
    text: state!['text'] as String,
    selection: TextSelection(
      baseOffset: state['selectionBase'] as int,
      extentOffset: state['selectionExtent'] as int,
    ),
    composing: TextRange(
      start: state['composingBase'] as int,
      end: state['composingExtent'] as int,
    ),
  );
}

TextEditingValue _replaceRemoteSelection(
  TextEditingValue current,
  String replacement, {
  required bool composing,
}) {
  final start = current.selection.start;
  final end = current.selection.end;
  final nextText = current.text.replaceRange(start, end, replacement);
  final nextOffset = start + replacement.length;
  return TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextOffset),
    composing: composing
        ? TextRange(start: start, end: nextOffset)
        : TextRange.empty,
  );
}
