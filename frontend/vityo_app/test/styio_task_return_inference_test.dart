import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/semantic/styio_task_return_inference.dart';

void main() {
  test('scans task returns with comments, local values, and guarded arrows', () {
    const analyzer = StyioTaskReturnInference();
    const body = '''
  label = "http://styio.local"
  count = makeCount() // keep trailing comment out of the expression
  when ready -> <| "guarded"
  <| count // stable task return
  <|
  <| missing
''';

    final scan = analyzer.scan(
      body: body,
      bodyStartOffset: 50,
      functionReturnTypes: const {'makeCount': 'i64'},
    );

    expect(scan.values.map((value) => value.type), ['i64']);
    expect(
      body.substring(
        scan.values.single.range.start - 50,
        scan.values.single.range.end - 50,
      ),
      'count',
    );
    expect(scan.missingValueRanges.single.start, 50 + body.indexOf('<|\n'));
    expect(scan.conditionalValueRanges, hasLength(1));
    expect(scan.conditionalValues.map((value) => value.type), ['string']);
    expect(scan.unresolvedValues.single.expression, 'missing');
  });

  test('treats constant true guarded task returns as stable returns', () {
    const analyzer = StyioTaskReturnInference();
    const body = '''
  when (true && !false) -> <| makeCount()
''';

    final scan = analyzer.scan(
      body: body,
      functionReturnTypes: const {'makeCount': 'i64'},
    );

    expect(scan.values.map((value) => value.type), ['i64']);
    expect(scan.conditionalValueRanges, isEmpty);
    expect(scan.conditionalValues, isEmpty);
    expect(scan.missingValueRanges, isEmpty);
    expect(scan.unresolvedValues, isEmpty);
  });

  test('infers numeric and boolean binary task return expressions', () {
    const analyzer = StyioTaskReturnInference();
    const body = '''
  count = 41
  ratio = 1.5
  ready = true
  <| count + 1
  <| ratio + count
  <| count > 0
  <| (count + 1)
  <| !(count > 0)
  <| -count
  <| ratio / 2
  <| ready && count > 0
  <| (count > 0) || false
''';

    final scan = analyzer.scan(body: body);

    expect(
      scan.values.map((value) => value.type),
      ['i64', 'f64', 'bool', 'i64', 'bool', 'i64', 'f64', 'bool', 'bool'],
    );
    expect(scan.missingValueRanges, isEmpty);
    expect(scan.unresolvedValues, isEmpty);
  });

  test('tracks invalid complex task return expressions', () {
    const analyzer = StyioTaskReturnInference();
    const body = '''
  count = 1
  <| count && true
''';

    final scan = analyzer.scan(body: body);

    expect(scan.values, isEmpty);
    expect(scan.unresolvedValues, isEmpty);
    expect(scan.invalidExpressions.single.expression, 'count && true');
  });
}
