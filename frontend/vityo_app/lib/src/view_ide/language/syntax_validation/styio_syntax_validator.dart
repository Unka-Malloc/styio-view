import '../contract/language_contract.dart';
import 'styio_syntax_contract.dart';

class StyioSyntaxValidator {
  const StyioSyntaxValidator({
    this.contract = StyioSyntaxContract.current,
  });

  final StyioSyntaxContract contract;

  StyioSyntaxValidationReport validateWithReport({
    required String documentId,
    required String source,
    required List<TokenSpan> tokens,
  }) {
    final diagnostics = validate(source: source, tokens: tokens);
    return StyioSyntaxValidationReport(
      documentId: documentId,
      contractId: contract.id,
      contractVersion: contract.version,
      diagnostics: diagnostics,
      fallback: true,
    );
  }

  List<Diagnostic> validate({
    required String source,
    required List<TokenSpan> tokens,
  }) {
    return [
      ..._lexicalDiagnostics(source, tokens),
      ..._delimiterDiagnostics(tokens),
    ];
  }

  List<Diagnostic> _lexicalDiagnostics(
    String source,
    List<TokenSpan> tokens,
  ) {
    final diagnostics = <Diagnostic>[];
    for (final token in tokens) {
      if (contract.reportUnknownTokens && token.kind == TokenKind.unknown) {
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'unknown-token',
            message: 'Token `${token.lexeme}` is not valid Styio syntax.',
            range: token.range,
          ),
        );
      }
      if (contract.reportUnterminatedStrings &&
          token.kind == TokenKind.string &&
          _isUnterminatedString(token)) {
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'unterminated-string',
            message: 'String literal is missing a closing quote.',
            range: token.range,
          ),
        );
      }
    }

    final blockCommentStart = contract.reportUnterminatedBlockComments
        ? _unterminatedBlockCommentStart(source)
        : null;
    if (blockCommentStart != null) {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'unterminated-block-comment',
          message: 'Block comment is missing a closing `*/`.',
          range: SourceRange(start: blockCommentStart, end: source.length),
        ),
      );
    }
    return diagnostics;
  }

  List<Diagnostic> _delimiterDiagnostics(List<TokenSpan> tokens) {
    final diagnostics = <Diagnostic>[];
    final stack = <_DelimiterFrame>[];
    final closingToOpening = {
      for (final entry in contract.delimiterPairs.entries)
        entry.value: entry.key,
    };

    for (final token in tokens) {
      if (token.kind == TokenKind.string || token.kind == TokenKind.comment) {
        continue;
      }
      if (contract.delimiterPairs.containsKey(token.lexeme)) {
        stack.add(_DelimiterFrame(token: token));
        continue;
      }
      final expectedOpening = closingToOpening[token.lexeme];
      if (expectedOpening == null) {
        continue;
      }
      if (stack.isEmpty || stack.last.token.lexeme != expectedOpening) {
        diagnostics.add(_unexpectedClosingDiagnostic(token));
        continue;
      }
      stack.removeLast();
    }

    for (final frame in stack.reversed) {
      diagnostics.add(_unclosedOpeningDiagnostic(frame));
    }
    return diagnostics;
  }

  bool _isUnterminatedString(TokenSpan token) {
    if (token.lexeme.length < 2) {
      return true;
    }
    final opening = token.lexeme[0];
    if (opening != '"' && opening != "'") {
      return true;
    }
    return token.lexeme[token.lexeme.length - 1] != opening;
  }

  int? _unterminatedBlockCommentStart(String source) {
    var index = 0;
    while (index + 1 < source.length) {
      final pair = source.substring(index, index + 2);
      if (pair == '/*') {
        final end = source.indexOf('*/', index + 2);
        if (end < 0) {
          return index;
        }
        index = end + 2;
        continue;
      }
      if (pair == '//') {
        final newline = source.indexOf('\n', index + 2);
        if (newline < 0) {
          return null;
        }
        index = newline + 1;
        continue;
      }
      index += 1;
    }
    return null;
  }

  Diagnostic _unexpectedClosingDiagnostic(TokenSpan token) {
    switch (token.lexeme) {
      case '}':
        return Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'unexpected-closing-brace',
          message: 'Closing brace has no matching opening brace.',
          range: token.range,
        );
      case ')':
        return Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'unexpected-closing-parenthesis',
          message: 'Closing parenthesis has no matching opening parenthesis.',
          range: token.range,
        );
      case ']':
        return Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'unexpected-closing-bracket',
          message: 'Closing bracket has no matching opening bracket.',
          range: token.range,
        );
    }
    return Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'unexpected-closing-delimiter',
      message: 'Closing delimiter has no matching opening delimiter.',
      range: token.range,
    );
  }

  Diagnostic _unclosedOpeningDiagnostic(_DelimiterFrame frame) {
    switch (frame.token.lexeme) {
      case '{':
        return Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'unclosed-block',
          message: 'Block is missing a closing `}`.',
          range: frame.token.range,
        );
      case '(':
        return Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'unclosed-parenthesis',
          message: 'Parenthesis is missing a closing `)`.',
          range: frame.token.range,
        );
      case '[':
        return Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'unclosed-bracket',
          message: 'Bracket is missing a closing `]`.',
          range: frame.token.range,
        );
    }
    return Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'unclosed-delimiter',
      message: 'Opening delimiter is missing a closing delimiter.',
      range: frame.token.range,
    );
  }
}

class _DelimiterFrame {
  const _DelimiterFrame({required this.token});

  final TokenSpan token;
}

class StyioSyntaxValidationReport {
  const StyioSyntaxValidationReport({
    required this.documentId,
    required this.contractId,
    required this.contractVersion,
    required this.diagnostics,
    required this.fallback,
  });

  final String documentId;
  final String contractId;
  final String contractVersion;
  final List<Diagnostic> diagnostics;
  final bool fallback;

  bool get valid => diagnostics.isEmpty;
  int get diagnosticCount => diagnostics.length;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'contractId': contractId,
      'contractVersion': contractVersion,
      'source': fallback ? 'vityo-ide-syntax-contract' : 'styio-service',
      'fallback': fallback,
      'valid': valid,
      'diagnosticCount': diagnosticCount,
      'diagnostics': diagnostics
          .map(_diagnosticToJson)
          .toList(growable: false),
    };
  }

  static Map<String, Object?> _diagnosticToJson(Diagnostic diagnostic) {
    return <String, Object?>{
      'severity': diagnostic.severity.name,
      'code': diagnostic.code,
      'message': diagnostic.message,
      'range': <String, int>{
        'start': diagnostic.range.start,
        'end': diagnostic.range.end,
      },
    };
  }
}
