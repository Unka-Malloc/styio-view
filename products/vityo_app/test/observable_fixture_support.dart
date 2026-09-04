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

String observableTopologyFixturePath(String relative) {
  return [
    'test',
    'fixtures',
    'observable_topology',
    ...relative.split('/'),
  ].join(Platform.pathSeparator);
}

String readObservableFixture(String name) {
  return File(observableFixturePath(name)).readAsStringSync();
}

List<int> readObservableFixtureBytes(String name) {
  return File(observableFixturePath(name)).readAsBytesSync();
}

String readObservableTopologyFixture(String relative) {
  return File(observableTopologyFixturePath(relative)).readAsStringSync();
}

List<int> readObservableTopologyFixtureBytes(String relative) {
  return File(observableTopologyFixturePath(relative)).readAsBytesSync();
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

ObservableSnapshot decodeNamedTopologySnapshot(String relative) {
  final result = decodeObservableSnapshotBytes(
    readObservableTopologyFixtureBytes(relative),
  );
  if (result.snapshot == null) {
    throw StateError('$relative must decode: ${result.failure?.detail}');
  }
  return result.snapshot!;
}

ObservableDeltaEnvelope decodeNamedTopologyDelta(String relative) {
  final result = decodeObservableDeltaBytes(
    readObservableTopologyFixtureBytes(relative),
  );
  if (result.envelope == null) {
    throw StateError('$relative must decode: ${result.failure?.detail}');
  }
  return result.envelope!;
}
