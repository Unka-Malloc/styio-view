/// Benchmark Runner
///
/// Runs all ALG-01 through ALG-10 benchmarks and outputs JSON results.
library;

import 'dart:convert';
import 'dart:io';

import 'alg01_piece_table_benchmark.dart';
import 'alg02_line_index_benchmark.dart';
import 'alg03_decorations_benchmark.dart';
import 'alg04_snapshots_benchmark.dart';
import 'alg05_workspace_graph_benchmark.dart';
import 'alg06_language_cache_benchmark.dart';
import 'alg07_runtime_events_benchmark.dart';
import 'alg08_ai_context_benchmark.dart';
import 'alg09_watcher_benchmark.dart';
import 'alg10_virtualization_benchmark.dart';

Map<String, dynamic> runAllBenchmarks() {
  final allResults = <String, List<Map<String, dynamic>>>{
    'alg01_piece_table': runAlg01Benchmarks(),
    'alg02_line_index': runAlg02Benchmarks(),
    'alg03_decorations': runAlg03Benchmarks(),
    'alg04_snapshots': runAlg04Benchmarks(),
    'alg05_workspace_graph': runAlg05Benchmarks(),
    'alg06_language_cache': runAlg06Benchmarks(),
    'alg07_runtime_events': runAlg07Benchmarks(),
    'alg08_ai_context': runAlg08Benchmarks(),
    'alg09_watcher': runAlg09Benchmarks(),
    'alg10_virtualization': runAlg10Benchmarks(),
  };

  return {
    'timestamp': DateTime.now().toIso8601String(),
    'platform': Platform.operatingSystem,
    'results': allResults,
  };
}

void main() {
  print('Vityo Nightly Benchmark Suite');
  print('==============================');
  print('');

  final results = runAllBenchmarks();

  final jsonOutput = const JsonEncoder.withIndent('  ').convert(results);
  print(jsonOutput);

  // Write results to file
  final file = File('benchmark_results.json');
  file.writeAsStringSync(jsonOutput);
  print('');
  print('Results written to benchmark_results.json');
}
