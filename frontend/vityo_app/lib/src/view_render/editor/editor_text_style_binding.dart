import 'package:flutter/material.dart';

import '../../view_ide/editor/editor_render_layers.dart';
import '../../view_ide/language/language_contract.dart';

class EditorFlutterTextStyleBinding {
  const EditorFlutterTextStyleBinding({required this.semanticThemeBinding});

  factory EditorFlutterTextStyleBinding.foundation() {
    return EditorFlutterTextStyleBinding(
      semanticThemeBinding: EditorSemanticThemeBinding.fromTheme(
        EditorSemanticTheme.foundation(),
      ),
    );
  }

  final EditorSemanticThemeBinding semanticThemeBinding;

  TextStyle styleForToken({
    required TextStyle baseStyle,
    required TokenKind tokenKind,
    required SemanticKind? semanticKind,
    required DiagnosticSeverity? diagnosticSeverity,
  }) {
    var color = _tokenColor(tokenKind);
    var weight = tokenKind == TokenKind.whitespace
        ? FontWeight.w400
        : FontWeight.w500;

    final semanticStyle = semanticKind == null
        ? null
        : semanticThemeBinding.styleForSemanticKind(semanticKind);
    if (semanticStyle != null) {
      color = Color(semanticStyle.foregroundColor);
      weight = _fontWeightFromWire(semanticStyle.fontWeight, fallback: weight);
    }

    var decoration = TextDecoration.none;
    var decorationColor = color;
    var decorationStyle = TextDecorationStyle.solid;

    if (diagnosticSeverity != null) {
      final diagnosticStyle = semanticThemeBinding.styleForDiagnosticSeverity(
        diagnosticSeverity,
      );
      decoration = TextDecoration.underline;
      decorationStyle = TextDecorationStyle.wavy;
      decorationColor = Color(
        diagnosticStyle?.decorationColor ??
            diagnosticStyle?.foregroundColor ??
            _diagnosticColorValue(diagnosticSeverity),
      );
    }

    return baseStyle.copyWith(
      fontFamily: 'monospace',
      color: color,
      fontWeight: weight,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
    );
  }
}

Color _tokenColor(TokenKind tokenKind) {
  return switch (tokenKind) {
    TokenKind.keyword => const Color(0xFF6450A7),
    TokenKind.identifier => const Color(0xFF2C2725),
    TokenKind.number => const Color(0xFF0F7B68),
    TokenKind.string => const Color(0xFFAF5B33),
    TokenKind.comment => const Color(0xFF9A9185),
    TokenKind.operator => const Color(0xFF255A96),
    TokenKind.punctuation => const Color(0xFF6D655E),
    TokenKind.whitespace => const Color(0xFF2C2725),
    TokenKind.unknown => const Color(0xFFCB4D45),
  };
}

int _diagnosticColorValue(DiagnosticSeverity severity) {
  return switch (severity) {
    DiagnosticSeverity.error => 0xFFCB4D45,
    DiagnosticSeverity.warning => 0xFFD5962A,
    DiagnosticSeverity.hint => 0xFF6980B5,
  };
}

FontWeight _fontWeightFromWire(String value, {required FontWeight fallback}) {
  return switch (value) {
    '100' => FontWeight.w100,
    '200' => FontWeight.w200,
    '300' => FontWeight.w300,
    '400' || 'normal' => FontWeight.w400,
    '500' => FontWeight.w500,
    '600' => FontWeight.w600,
    '700' || 'bold' => FontWeight.w700,
    '800' => FontWeight.w800,
    '900' => FontWeight.w900,
    _ => fallback,
  };
}
