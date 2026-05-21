import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';

void main() {
  test('agent tool call result context reports truncated output facts', () {
    final context = AgentToolCallResultContext.fromDispatchResult(
      const AgentToolCallDispatchResult.success(
        callId: 'call-large-read',
        toolId: 'readWorkspaceFile',
        output: '0123456789abcdef',
      ),
      createdAt: DateTime.utc(2026, 5, 22),
      outputLimit: 10,
    );
    final json = context.toJson();

    expect(context.outputTruncated, isTrue);
    expect(context.outputOriginalLength, 16);
    expect(context.outputLimit, 10);
    expect(context.outputOmittedLength, 6);
    expect(context.output, startsWith('0123456789'));
    expect(
      context.output,
      contains('[tool output truncated: 6 char(s) omitted]'),
    );
    expect(json['outputTruncated'], isTrue);
    expect(json['outputOriginalLength'], 16);
    expect(json['outputLimit'], 10);
    expect(json['outputOmittedLength'], 6);
  });
}
