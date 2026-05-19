import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('IDE capability framework provides a cross-layer closure manifest', () {
    final snapshot = const VityoIdeCapabilityFramework().snapshot();
    final json = snapshot.toJson();
    final ids = snapshot.entries.map((entry) => entry.id).toSet();

    expect(snapshot.version, 'vityo-ide-capability-framework-v1');
    expect(snapshot.entries.length, ids.length);
    expect(ids, contains('service.styio-language'));
    expect(ids, contains('agent.coding-loop'));
    expect(ids, contains('editor.document-model'));
    expect(ids, contains('presentation.shell'));
    expect(snapshot.entriesForLayer(IdeCapabilityLayer.agent), isNotEmpty);
    expect(snapshot.entriesForLayer(IdeCapabilityLayer.service), isNotEmpty);
    expect(
      snapshot.entriesForLayer(IdeCapabilityLayer.environment),
      isNotEmpty,
    );
    expect(snapshot.followUps, isNotEmpty);
    expect(
      snapshot.followUps.every((entry) => entry.todo.startsWith('TODO:')),
      isTrue,
    );
    expect(json['entryCount'], snapshot.entries.length);
    expect(
      (json['statusCounts']! as Map<String, Object?>)['scaffolded'],
      greaterThan(0),
    );
    expect(
      (json['layerCounts']! as Map<String, Object?>)['agent'],
      greaterThanOrEqualTo(2),
    );
  });
}
