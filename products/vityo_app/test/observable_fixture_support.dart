import 'dart:io';

import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

String observableFixturePath(String name) {
  return [
    'test',
    'fixtures',
    'observable_static_snapshot',
    'v1',
    name,
  ].join(Platform.pathSeparator);
}

String readObservableFixture(String name) {
  return File(observableFixturePath(name)).readAsStringSync();
}

List<int> readObservableFixtureBytes(String name) {
  return File(observableFixturePath(name)).readAsBytesSync();
}

ObservableSnapshot decodeCanonicalFixture() {
  return decodeNamedObservableFixture('canonical.json');
}

ObservableSnapshot decodeAuthoredCanonicalFixture() {
  return decodeNamedObservableFixture('vityo-authored-canonical.json');
}

ObservableSnapshot decodeNamedObservableFixture(String name) {
  final result = decodeObservableSnapshotJson(readObservableFixture(name));
  if (result.snapshot == null) {
    throw StateError('$name must decode: ${result.failure?.detail}');
  }
  return result.snapshot!;
}
