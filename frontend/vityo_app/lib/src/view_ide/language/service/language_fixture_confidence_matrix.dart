import 'dart:async';

import '../../environment/system_compatibility/file_system/file_system_manager.dart';
import '../../toolchain/toolchain_resolver.dart';
import '../../toolchain/toolchain_runtime.dart';
import '../contract/language_contract.dart';
import 'styio_service_connector.dart';

enum LanguageFixtureExpectation {
  pass,
  fail,
  missing,
}

enum LanguageFixtureActualResult {
  pass,
  fail,
}

enum LanguageFixtureConfidenceClass {
  truePositive,
  falseNegative,
  trueNegative,
  falsePositive,
  unlabeled,
}

class LanguageFixtureConfidenceEntry {
  const LanguageFixtureConfidenceEntry({
    required this.path,
    required this.expectation,
    required this.actualResult,
    required this.matrixClass,
  });

  final String path;
  final LanguageFixtureExpectation expectation;
  final LanguageFixtureActualResult actualResult;
  final LanguageFixtureConfidenceClass matrixClass;

  bool get gatePassed =>
      matrixClass == LanguageFixtureConfidenceClass.truePositive ||
      matrixClass == LanguageFixtureConfidenceClass.trueNegative;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'expectation': expectation.name,
      'actualResult': actualResult.name,
      'matrixClass': matrixClass.name,
      'gatePassed': gatePassed,
    };
  }
}

class LanguageFixtureConfidenceMatrix {
  LanguageFixtureConfidenceMatrix({
    required Iterable<LanguageFixtureConfidenceEntry> entries,
  }) : entries = List.unmodifiable(entries);

  final List<LanguageFixtureConfidenceEntry> entries;

  bool get gatePassed => entries.every((entry) => entry.gatePassed);

  List<LanguageFixtureConfidenceEntry> get failures {
    return entries
        .where((entry) => !entry.gatePassed)
        .toList(growable: false);
  }

  Map<String, int> get summary {
    final counts = <String, int>{
      'total': entries.length,
      'passed': entries.where((entry) => entry.gatePassed).length,
      'failed': failures.length,
      for (final matrixClass in LanguageFixtureConfidenceClass.values)
        matrixClass.name: 0,
    };
    for (final entry in entries) {
      counts[entry.matrixClass.name] =
          (counts[entry.matrixClass.name] ?? 0) + 1;
    }
    return Map<String, int>.unmodifiable(counts);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'gatePassed': gatePassed,
      'summary': summary,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

typedef LanguageFixtureValidator =
    FutureOr<LanguageFixtureActualResult> Function(String path);

typedef LanguageFixtureTextLoader = FutureOr<String> Function(String path);

class LanguageFixtureFileCollector {
  const LanguageFixtureFileCollector({
    required FileSystemManager fileSystemManager,
    this.recursive = true,
  }) : _fileSystemManager = fileSystemManager;

  final FileSystemManager _fileSystemManager;
  final bool recursive;

  Future<List<String>> collect({required Iterable<String> roots}) async {
    final paths = <String>{};
    for (final root in roots) {
      final snapshot = await _fileSystemManager.stat(root);
      if (snapshot.isFile) {
        _addFixturePath(paths, snapshot);
        continue;
      }
      if (!snapshot.isDirectory) {
        continue;
      }
      final snapshots = await _fileSystemManager.list(
        snapshot.normalizedPath,
        recursive: recursive,
      );
      for (final child in snapshots) {
        if (child.isFile) {
          _addFixturePath(paths, child);
        }
      }
    }
    return paths.toList(growable: false)..sort();
  }

  void _addFixturePath(
    Set<String> paths,
    FileSystemEntitySnapshot snapshot,
  ) {
    if (snapshot.normalizedPath.endsWith('.styio')) {
      paths.add(snapshot.normalizedPath);
    }
  }
}

class LanguageFixtureFileSystemTextLoader {
  const LanguageFixtureFileSystemTextLoader({
    required FileSystemManager fileSystemManager,
  }) : _fileSystemManager = fileSystemManager;

  final FileSystemManager _fileSystemManager;

  Future<String> load(String path) {
    return _fileSystemManager.readText(path);
  }
}

class StyioServiceFixtureValidator {
  const StyioServiceFixtureValidator({
    required StyioServiceConnector connector,
    required LanguageFixtureTextLoader textLoader,
    this.revision = 0,
  }) : _connector = connector,
       _textLoader = textLoader;

  final StyioServiceConnector _connector;
  final LanguageFixtureTextLoader _textLoader;
  final int revision;

  Future<LanguageFixtureActualResult> validate(String path) async {
    final response = await _connector.analyzeDocument(
      StyioServiceDocument(
        documentId: path,
        text: await _textLoader(path),
        revision: revision,
        filePath: path,
      ),
    );
    if (!response.succeeded) {
      return LanguageFixtureActualResult.fail;
    }
    final hasErrorDiagnostic = response.diagnostics.any(
      (diagnostic) => diagnostic.severity == DiagnosticSeverity.error,
    );
    return hasErrorDiagnostic
      ? LanguageFixtureActualResult.fail
      : LanguageFixtureActualResult.pass;
  }
}

class LanguageFixtureGateRunner {
  const LanguageFixtureGateRunner({
    required LanguageFixtureFileCollector collector,
    required LanguageFixtureValidator validate,
    this.builder = const LanguageFixtureConfidenceMatrixBuilder(),
  }) : _collector = collector,
       _validate = validate;

  final LanguageFixtureFileCollector _collector;
  final LanguageFixtureValidator _validate;
  final LanguageFixtureConfidenceMatrixBuilder builder;

  Future<LanguageFixtureConfidenceMatrix> run({
    required Iterable<String> roots,
  }) async {
    final fixturePaths = await _collector.collect(roots: roots);
    return builder.build(fixturePaths: fixturePaths, validate: _validate);
  }
}

class StyioServiceFixtureGate {
  const StyioServiceFixtureGate({
    required FileSystemManager fileSystemManager,
    required StyioServiceConnector connector,
    this.revision = 0,
    this.recursive = true,
    this.builder = const LanguageFixtureConfidenceMatrixBuilder(),
  }) : _fileSystemManager = fileSystemManager,
       _connector = connector;

  factory StyioServiceFixtureGate.fromToolchainRuntime({
    required FileSystemManager fileSystemManager,
    required ToolchainRuntime runtime,
    StyioCliJsonlProtocol protocol = const StyioCliJsonlProtocol(),
    ToolchainRequirement? requirement,
    Duration timeout = const Duration(seconds: 10),
    int revision = 0,
    bool recursive = true,
    LanguageFixtureConfidenceMatrixBuilder builder =
        const LanguageFixtureConfidenceMatrixBuilder(),
  }) {
    return StyioServiceFixtureGate(
      fileSystemManager: fileSystemManager,
      connector: ToolchainStyioServiceConnector(
        runtime: runtime,
        protocol: protocol,
        requirement: requirement,
        timeout: timeout,
      ),
      revision: revision,
      recursive: recursive,
      builder: builder,
    );
  }

  final FileSystemManager _fileSystemManager;
  final StyioServiceConnector _connector;
  final int revision;
  final bool recursive;
  final LanguageFixtureConfidenceMatrixBuilder builder;

  Future<LanguageFixtureConfidenceMatrix> run({
    required Iterable<String> roots,
  }) {
    final textLoader = LanguageFixtureFileSystemTextLoader(
      fileSystemManager: _fileSystemManager,
    );
    final validator = StyioServiceFixtureValidator(
      connector: _connector,
      textLoader: textLoader.load,
      revision: revision,
    );
    return LanguageFixtureGateRunner(
      collector: LanguageFixtureFileCollector(
        fileSystemManager: _fileSystemManager,
        recursive: recursive,
      ),
      validate: validator.validate,
      builder: builder,
    ).run(roots: roots);
  }
}

class LanguageFixtureConfidenceMatrixBuilder {
  const LanguageFixtureConfidenceMatrixBuilder();

  Future<LanguageFixtureConfidenceMatrix> build({
    required Iterable<String> fixturePaths,
    required LanguageFixtureValidator validate,
  }) async {
    final entries = <LanguageFixtureConfidenceEntry>[];
    for (final path in fixturePaths) {
      final expectation = expectationForPath(path);
      final actualResult = await validate(path);
      entries.add(
        LanguageFixtureConfidenceEntry(
          path: path,
          expectation: expectation,
          actualResult: actualResult,
          matrixClass: classify(
            expectation: expectation,
            actualResult: actualResult,
          ),
        ),
      );
    }
    return LanguageFixtureConfidenceMatrix(entries: entries);
  }

  LanguageFixtureExpectation expectationForPath(String path) {
    if (path.endsWith('.true.styio')) {
      return LanguageFixtureExpectation.pass;
    }
    if (path.endsWith('.false.styio')) {
      return LanguageFixtureExpectation.fail;
    }
    return LanguageFixtureExpectation.missing;
  }

  LanguageFixtureConfidenceClass classify({
    required LanguageFixtureExpectation expectation,
    required LanguageFixtureActualResult actualResult,
  }) {
    return switch ((expectation, actualResult)) {
      (LanguageFixtureExpectation.pass, LanguageFixtureActualResult.pass) =>
        LanguageFixtureConfidenceClass.truePositive,
      (LanguageFixtureExpectation.pass, LanguageFixtureActualResult.fail) =>
        LanguageFixtureConfidenceClass.falseNegative,
      (LanguageFixtureExpectation.fail, LanguageFixtureActualResult.fail) =>
        LanguageFixtureConfidenceClass.trueNegative,
      (LanguageFixtureExpectation.fail, LanguageFixtureActualResult.pass) =>
        LanguageFixtureConfidenceClass.falsePositive,
      (LanguageFixtureExpectation.missing, _) =>
        LanguageFixtureConfidenceClass.unlabeled,
    };
  }
}
