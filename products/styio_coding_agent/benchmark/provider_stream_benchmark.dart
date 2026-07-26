import 'dart:convert';

import 'package:styio_coding_agent/styio_coding_agent.dart';

void main() {
  const chunkCount = 5000;
  final reducer = ProviderStreamReducer(
    maxBufferedOutputBytes: 64 * 1024,
    maxToolArgumentBytes: 8 * 1024,
  );
  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < chunkCount; index += 1) {
    reducer.add(const ModelTextDelta('x'));
  }
  reducer.add(
    const ModelUsageEvent(
      ModelUsage(inputTokens: 100, outputTokens: chunkCount),
    ),
  );
  reducer.add(const ModelCompleted());
  final receipt = reducer.finish(requestId: 'benchmark', providerId: 'fixture');
  stopwatch.stop();
  final passed =
      receipt.text.length == chunkCount && stopwatch.elapsedMilliseconds < 1000;
  print(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'benchmark': 'provider_stream',
      'passed': passed,
      'chunkCount': chunkCount,
      'elapsedMs': stopwatch.elapsedMilliseconds,
      'outputBytes': receipt.text.length,
    }),
  );
  if (!passed) {
    throw StateError('provider stream benchmark exceeded its budget');
  }
}
