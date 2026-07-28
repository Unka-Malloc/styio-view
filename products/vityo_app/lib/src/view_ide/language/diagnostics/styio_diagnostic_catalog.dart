import '../contract/language_contract.dart';

enum StyioDiagnosticPhase {
  lexical,
  syntax,
  resolver,
  type,
  controlFlow,
  resourceTopology,
  taskFlow,
  projectGraph,
  style,
}

class StyioDiagnosticDescriptor {
  const StyioDiagnosticDescriptor({
    required this.code,
    required this.phase,
    required this.severity,
    required this.summary,
    this.hasQuickFix = false,
  });

  final String code;
  final StyioDiagnosticPhase phase;
  final DiagnosticSeverity severity;
  final String summary;
  final bool hasQuickFix;
}

class StyioDiagnosticCatalog {
  const StyioDiagnosticCatalog._();

  static const Map<String, StyioDiagnosticDescriptor>
  _descriptorsByCode = <String, StyioDiagnosticDescriptor>{
    'unknown-token': StyioDiagnosticDescriptor(
      code: 'unknown-token',
      phase: StyioDiagnosticPhase.lexical,
      severity: DiagnosticSeverity.error,
      summary: 'The lexer found a token that is not part of Styio syntax.',
      hasQuickFix: true,
    ),
    'unterminated-string': StyioDiagnosticDescriptor(
      code: 'unterminated-string',
      phase: StyioDiagnosticPhase.lexical,
      severity: DiagnosticSeverity.error,
      summary: 'A string literal reaches the end of input without closing.',
      hasQuickFix: true,
    ),
    'unterminated-block-comment': StyioDiagnosticDescriptor(
      code: 'unterminated-block-comment',
      phase: StyioDiagnosticPhase.lexical,
      severity: DiagnosticSeverity.error,
      summary: 'A block comment reaches the end of input without closing.',
      hasQuickFix: true,
    ),
    'unexpected-closing-brace': StyioDiagnosticDescriptor(
      code: 'unexpected-closing-brace',
      phase: StyioDiagnosticPhase.syntax,
      severity: DiagnosticSeverity.error,
      summary: 'A closing brace does not match an open block.',
      hasQuickFix: true,
    ),
    'unexpected-closing-parenthesis': StyioDiagnosticDescriptor(
      code: 'unexpected-closing-parenthesis',
      phase: StyioDiagnosticPhase.syntax,
      severity: DiagnosticSeverity.error,
      summary: 'A closing parenthesis does not match an open parenthesis.',
      hasQuickFix: true,
    ),
    'unexpected-closing-bracket': StyioDiagnosticDescriptor(
      code: 'unexpected-closing-bracket',
      phase: StyioDiagnosticPhase.syntax,
      severity: DiagnosticSeverity.error,
      summary: 'A closing bracket does not match an open bracket.',
      hasQuickFix: true,
    ),
    'unexpected-closing-delimiter': StyioDiagnosticDescriptor(
      code: 'unexpected-closing-delimiter',
      phase: StyioDiagnosticPhase.syntax,
      severity: DiagnosticSeverity.error,
      summary: 'A closing delimiter does not match an open delimiter.',
      hasQuickFix: true,
    ),
    'unclosed-block': StyioDiagnosticDescriptor(
      code: 'unclosed-block',
      phase: StyioDiagnosticPhase.syntax,
      severity: DiagnosticSeverity.error,
      summary: 'A block starts with `{` but is not closed.',
      hasQuickFix: true,
    ),
    'unclosed-parenthesis': StyioDiagnosticDescriptor(
      code: 'unclosed-parenthesis',
      phase: StyioDiagnosticPhase.syntax,
      severity: DiagnosticSeverity.error,
      summary: 'A parenthesized expression is not closed.',
      hasQuickFix: true,
    ),
    'unclosed-bracket': StyioDiagnosticDescriptor(
      code: 'unclosed-bracket',
      phase: StyioDiagnosticPhase.syntax,
      severity: DiagnosticSeverity.error,
      summary: 'A bracketed expression is not closed.',
      hasQuickFix: true,
    ),
    'unclosed-delimiter': StyioDiagnosticDescriptor(
      code: 'unclosed-delimiter',
      phase: StyioDiagnosticPhase.syntax,
      severity: DiagnosticSeverity.error,
      summary: 'An opening delimiter is not closed.',
      hasQuickFix: true,
    ),
    'missing-assignment': StyioDiagnosticDescriptor(
      code: 'missing-assignment',
      phase: StyioDiagnosticPhase.syntax,
      severity: DiagnosticSeverity.warning,
      summary: 'A variable declaration is missing an assignment.',
      hasQuickFix: true,
    ),
    'duplicate-declaration': StyioDiagnosticDescriptor(
      code: 'duplicate-declaration',
      phase: StyioDiagnosticPhase.resolver,
      severity: DiagnosticSeverity.warning,
      summary: 'A current-file declaration reuses an existing name.',
      hasQuickFix: true,
    ),
    'unresolved-reference': StyioDiagnosticDescriptor(
      code: 'unresolved-reference',
      phase: StyioDiagnosticPhase.resolver,
      severity: DiagnosticSeverity.warning,
      summary: 'An identifier cannot be resolved in the current scope.',
      hasQuickFix: true,
    ),
    'unused-local-symbol': StyioDiagnosticDescriptor(
      code: 'unused-local-symbol',
      phase: StyioDiagnosticPhase.resolver,
      severity: DiagnosticSeverity.warning,
      summary: 'A local symbol is declared but never referenced.',
      hasQuickFix: true,
    ),
    'unused-parameter': StyioDiagnosticDescriptor(
      code: 'unused-parameter',
      phase: StyioDiagnosticPhase.resolver,
      severity: DiagnosticSeverity.warning,
      summary: 'A function parameter is declared but never referenced.',
      hasQuickFix: true,
    ),
    'parameter-shadowing': StyioDiagnosticDescriptor(
      code: 'parameter-shadowing',
      phase: StyioDiagnosticPhase.resolver,
      severity: DiagnosticSeverity.warning,
      summary: 'A local declaration shadows a function parameter.',
      hasQuickFix: true,
    ),
    'redundant-type-annotation': StyioDiagnosticDescriptor(
      code: 'redundant-type-annotation',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.hint,
      summary: 'A local binding repeats the type that Styio already infers.',
      hasQuickFix: true,
    ),
    'redundant-parentheses': StyioDiagnosticDescriptor(
      code: 'redundant-parentheses',
      phase: StyioDiagnosticPhase.syntax,
      severity: DiagnosticSeverity.hint,
      summary: 'Parentheses do not change the Styio expression shape.',
      hasQuickFix: true,
    ),
    'duplicate-function-declaration': StyioDiagnosticDescriptor(
      code: 'duplicate-function-declaration',
      phase: StyioDiagnosticPhase.resolver,
      severity: DiagnosticSeverity.error,
      summary: 'A function name is declared more than once.',
      hasQuickFix: true,
    ),
    'duplicate-parameter-declaration': StyioDiagnosticDescriptor(
      code: 'duplicate-parameter-declaration',
      phase: StyioDiagnosticPhase.resolver,
      severity: DiagnosticSeverity.error,
      summary: 'A function parameter name is declared more than once.',
      hasQuickFix: true,
    ),
    'duplicate-resource-declaration': StyioDiagnosticDescriptor(
      code: 'duplicate-resource-declaration',
      phase: StyioDiagnosticPhase.resourceTopology,
      severity: DiagnosticSeverity.error,
      summary: 'A resource name is declared more than once.',
      hasQuickFix: true,
    ),
    'duplicate-task-declaration': StyioDiagnosticDescriptor(
      code: 'duplicate-task-declaration',
      phase: StyioDiagnosticPhase.taskFlow,
      severity: DiagnosticSeverity.error,
      summary: 'A task name is declared more than once.',
      hasQuickFix: true,
    ),
    'unknown-named-argument': StyioDiagnosticDescriptor(
      code: 'unknown-named-argument',
      phase: StyioDiagnosticPhase.resolver,
      severity: DiagnosticSeverity.warning,
      summary: 'A named call argument does not match any parameter.',
      hasQuickFix: true,
    ),
    'duplicate-named-argument': StyioDiagnosticDescriptor(
      code: 'duplicate-named-argument',
      phase: StyioDiagnosticPhase.resolver,
      severity: DiagnosticSeverity.warning,
      summary: 'A named call argument is supplied more than once.',
      hasQuickFix: true,
    ),
    'missing-call-argument': StyioDiagnosticDescriptor(
      code: 'missing-call-argument',
      phase: StyioDiagnosticPhase.resolver,
      severity: DiagnosticSeverity.warning,
      summary: 'A function call omits a required argument.',
      hasQuickFix: true,
    ),
    'too-many-call-arguments': StyioDiagnosticDescriptor(
      code: 'too-many-call-arguments',
      phase: StyioDiagnosticPhase.resolver,
      severity: DiagnosticSeverity.warning,
      summary: 'A function call supplies more arguments than accepted.',
      hasQuickFix: true,
    ),
    'argument-type-mismatch': StyioDiagnosticDescriptor(
      code: 'argument-type-mismatch',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.warning,
      summary: 'A function call argument does not match the parameter type.',
      hasQuickFix: true,
    ),
    'binary-operator-type-mismatch': StyioDiagnosticDescriptor(
      code: 'binary-operator-type-mismatch',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.warning,
      summary: 'A binary operator is used with incompatible operand types.',
      hasQuickFix: true,
    ),
    'unary-operator-type-mismatch': StyioDiagnosticDescriptor(
      code: 'unary-operator-type-mismatch',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.warning,
      summary: 'A unary operator is used with an incompatible operand type.',
      hasQuickFix: true,
    ),
    'initializer-type-mismatch': StyioDiagnosticDescriptor(
      code: 'initializer-type-mismatch',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.warning,
      summary: 'A typed binding initializer does not match its type.',
      hasQuickFix: true,
    ),
    'assignment-type-mismatch': StyioDiagnosticDescriptor(
      code: 'assignment-type-mismatch',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.warning,
      summary: 'An assignment does not match the binding type.',
      hasQuickFix: true,
    ),
    'condition-type-mismatch': StyioDiagnosticDescriptor(
      code: 'condition-type-mismatch',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.warning,
      summary: 'A condition expression does not evaluate to bool.',
      hasQuickFix: true,
    ),
    'constant-condition': StyioDiagnosticDescriptor(
      code: 'constant-condition',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.warning,
      summary: 'A Styio condition always evaluates to the same value.',
      hasQuickFix: true,
    ),
    'division-by-zero': StyioDiagnosticDescriptor(
      code: 'division-by-zero',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.error,
      summary:
          'A Styio numeric expression uses a constant zero division operand.',
    ),
    'simplifiable-numeric-expression': StyioDiagnosticDescriptor(
      code: 'simplifiable-numeric-expression',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.hint,
      summary: 'A Styio numeric expression contains a neutral operation.',
      hasQuickFix: true,
    ),
    'simplifiable-boolean-negation': StyioDiagnosticDescriptor(
      code: 'simplifiable-boolean-negation',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.hint,
      summary: 'A boolean negation expression can be simplified.',
      hasQuickFix: true,
    ),
    'simplifiable-boolean-comparison': StyioDiagnosticDescriptor(
      code: 'simplifiable-boolean-comparison',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.hint,
      summary: 'A boolean comparison expression can be simplified.',
      hasQuickFix: true,
    ),
    'simplifiable-boolean-expression': StyioDiagnosticDescriptor(
      code: 'simplifiable-boolean-expression',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.hint,
      summary: 'A boolean expression can be simplified.',
      hasQuickFix: true,
    ),
    'simplifiable-negated-comparison': StyioDiagnosticDescriptor(
      code: 'simplifiable-negated-comparison',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.hint,
      summary: 'A negated comparison can use the opposite operator.',
      hasQuickFix: true,
    ),
    'simplifiable-demorgan-expression': StyioDiagnosticDescriptor(
      code: 'simplifiable-demorgan-expression',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.hint,
      summary: 'A negated boolean expression can use De Morgan\'s law.',
      hasQuickFix: true,
    ),
    'return-type-mismatch': StyioDiagnosticDescriptor(
      code: 'return-type-mismatch',
      phase: StyioDiagnosticPhase.type,
      severity: DiagnosticSeverity.warning,
      summary: 'A return expression does not match the function type.',
      hasQuickFix: true,
    ),
    'missing-function-return': StyioDiagnosticDescriptor(
      code: 'missing-function-return',
      phase: StyioDiagnosticPhase.controlFlow,
      severity: DiagnosticSeverity.error,
      summary: 'A typed function can complete without returning a value.',
      hasQuickFix: true,
    ),
    'unreachable-code': StyioDiagnosticDescriptor(
      code: 'unreachable-code',
      phase: StyioDiagnosticPhase.controlFlow,
      severity: DiagnosticSeverity.warning,
      summary: 'A statement appears after a function value return.',
      hasQuickFix: true,
    ),
    'read-only-resource-write': StyioDiagnosticDescriptor(
      code: 'read-only-resource-write',
      phase: StyioDiagnosticPhase.resourceTopology,
      severity: DiagnosticSeverity.error,
      summary: 'A read-only resource is used as a write sink.',
      hasQuickFix: true,
    ),
    'unresolved-resource': StyioDiagnosticDescriptor(
      code: 'unresolved-resource',
      phase: StyioDiagnosticPhase.resourceTopology,
      severity: DiagnosticSeverity.error,
      summary: 'A resource reference has no matching declaration.',
      hasQuickFix: true,
    ),
    'resource-write-type-mismatch': StyioDiagnosticDescriptor(
      code: 'resource-write-type-mismatch',
      phase: StyioDiagnosticPhase.resourceTopology,
      severity: DiagnosticSeverity.error,
      summary: 'A value written to a resource does not match its type.',
      hasQuickFix: true,
    ),
    'unresolved-task-await': StyioDiagnosticDescriptor(
      code: 'unresolved-task-await',
      phase: StyioDiagnosticPhase.taskFlow,
      severity: DiagnosticSeverity.error,
      summary: 'An await expression references no declared Styio task.',
      hasQuickFix: true,
    ),
    'unresolved-task-return-value': StyioDiagnosticDescriptor(
      code: 'unresolved-task-return-value',
      phase: StyioDiagnosticPhase.taskFlow,
      severity: DiagnosticSeverity.error,
      summary: 'A Styio task return expression references an unknown value.',
      hasQuickFix: true,
    ),
    'await-result-type-mismatch': StyioDiagnosticDescriptor(
      code: 'await-result-type-mismatch',
      phase: StyioDiagnosticPhase.taskFlow,
      severity: DiagnosticSeverity.error,
      summary: 'An await binding type does not match the task result.',
      hasQuickFix: true,
    ),
    'await-fallback-type-mismatch': StyioDiagnosticDescriptor(
      code: 'await-fallback-type-mismatch',
      phase: StyioDiagnosticPhase.taskFlow,
      severity: DiagnosticSeverity.error,
      summary: 'An await fallback value does not match the binding type.',
      hasQuickFix: true,
    ),
    'missing-task-return': StyioDiagnosticDescriptor(
      code: 'missing-task-return',
      phase: StyioDiagnosticPhase.taskFlow,
      severity: DiagnosticSeverity.error,
      summary: 'An awaited Styio task does not return a value.',
      hasQuickFix: true,
    ),
    'conditional-task-return': StyioDiagnosticDescriptor(
      code: 'conditional-task-return',
      phase: StyioDiagnosticPhase.taskFlow,
      severity: DiagnosticSeverity.error,
      summary: 'An awaited Styio task only returns from conditional branches.',
      hasQuickFix: true,
    ),
    'missing-task-return-value': StyioDiagnosticDescriptor(
      code: 'missing-task-return-value',
      phase: StyioDiagnosticPhase.taskFlow,
      severity: DiagnosticSeverity.error,
      summary: 'A Styio task return operator has no value.',
      hasQuickFix: true,
    ),
    'invalid-task-return-expression': StyioDiagnosticDescriptor(
      code: 'invalid-task-return-expression',
      phase: StyioDiagnosticPhase.taskFlow,
      severity: DiagnosticSeverity.error,
      summary: 'A Styio task return expression type cannot be inferred.',
      hasQuickFix: true,
    ),
    'conflicting-task-return-context': StyioDiagnosticDescriptor(
      code: 'conflicting-task-return-context',
      phase: StyioDiagnosticPhase.taskFlow,
      severity: DiagnosticSeverity.error,
      summary:
          'A Styio task with incomplete return inference is awaited as '
          'conflicting result types across the project.',
    ),
    'task-return-type-mismatch': StyioDiagnosticDescriptor(
      code: 'task-return-type-mismatch',
      phase: StyioDiagnosticPhase.taskFlow,
      severity: DiagnosticSeverity.error,
      summary: 'A Styio task returns incompatible value types.',
      hasQuickFix: true,
    ),
    'unresolved-import': StyioDiagnosticDescriptor(
      code: 'unresolved-import',
      phase: StyioDiagnosticPhase.projectGraph,
      severity: DiagnosticSeverity.error,
      summary: 'A local import does not resolve to a workspace document.',
      hasQuickFix: true,
    ),
    'ambiguous-imported-symbol': StyioDiagnosticDescriptor(
      code: 'ambiguous-imported-symbol',
      phase: StyioDiagnosticPhase.projectGraph,
      severity: DiagnosticSeverity.error,
      summary: 'Multiple imports provide the same referenced symbol.',
      hasQuickFix: true,
    ),
    'import-cycle': StyioDiagnosticDescriptor(
      code: 'import-cycle',
      phase: StyioDiagnosticPhase.projectGraph,
      severity: DiagnosticSeverity.error,
      summary: 'A local import participates in a cycle.',
      hasQuickFix: true,
    ),
    'unused-import': StyioDiagnosticDescriptor(
      code: 'unused-import',
      phase: StyioDiagnosticPhase.projectGraph,
      severity: DiagnosticSeverity.warning,
      summary: 'A local import provides no used symbols.',
      hasQuickFix: true,
    ),
    'unused-exported-symbol': StyioDiagnosticDescriptor(
      code: 'unused-exported-symbol',
      phase: StyioDiagnosticPhase.projectGraph,
      severity: DiagnosticSeverity.warning,
      summary: 'An exported project symbol has no non-definition references.',
      hasQuickFix: true,
    ),
    'duplicate-import': StyioDiagnosticDescriptor(
      code: 'duplicate-import',
      phase: StyioDiagnosticPhase.style,
      severity: DiagnosticSeverity.warning,
      summary: 'An import target is declared more than once.',
      hasQuickFix: true,
    ),
    'import-block-not-optimized': StyioDiagnosticDescriptor(
      code: 'import-block-not-optimized',
      phase: StyioDiagnosticPhase.style,
      severity: DiagnosticSeverity.hint,
      summary: 'Top-level imports can be sorted and deduplicated.',
      hasQuickFix: true,
    ),
    'todo-comment': StyioDiagnosticDescriptor(
      code: 'todo-comment',
      phase: StyioDiagnosticPhase.style,
      severity: DiagnosticSeverity.hint,
      summary: 'A TODO or FIXME marker is present in source.',
    ),
  };

  static List<StyioDiagnosticDescriptor> get all =>
      List<StyioDiagnosticDescriptor>.unmodifiable(_descriptorsByCode.values);

  static Set<String> get codes =>
      Set<String>.unmodifiable(_descriptorsByCode.keys);

  static StyioDiagnosticDescriptor? descriptorFor(String code) {
    return _descriptorsByCode[code];
  }

  static bool contains(String code) {
    return _descriptorsByCode.containsKey(code);
  }
}
