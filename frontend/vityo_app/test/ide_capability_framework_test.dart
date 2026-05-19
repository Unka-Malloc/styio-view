import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('IDE capability framework provides a cross-layer closure manifest', () {
    final snapshot = const VityoIdeCapabilityFramework().snapshot();
    final json = snapshot.toJson();
    final ids = snapshot.entries.map((entry) => entry.id).toSet();
    final entriesById = <String, IdeCapabilityDescriptor>{
      for (final entry in snapshot.entries) entry.id: entry,
    };

    expect(snapshot.version, 'vityo-ide-capability-framework-v1');
    expect(snapshot.entries.length, ids.length);
    expect(ids, contains('service.styio-language'));
    expect(ids, contains('agent.coding-loop'));
    expect(ids, contains('editor.document-model'));
    expect(ids, contains('interaction.search'));
    expect(ids, contains('interaction.source-control'));
    expect(ids, contains('interaction.testing'));
    expect(ids, contains('workspace.edit-application'));
    expect(ids, contains('workspace.diagnostics'));
    expect(ids, contains('runtime.terminal'));
    expect(ids, contains('presentation.problems-panel'));
    expect(ids, contains('presentation.shell'));
    expect(
      entriesById['interaction.search']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('match-level navigation callback'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('file quick open service'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('symbol search service'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('replace preview contract'),
    );
    expect(
      entriesById['presentation.problems-panel']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['presentation.problems-panel']?.summary,
      contains('workspace diagnostics grouping'),
    );
    expect(
      entriesById['workspace.diagnostics']?.status,
      IdeCapabilityStatus.wired,
    );
    expect(
      entriesById['service.semantic-snapshot']?.status,
      IdeCapabilityStatus.wired,
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains('SemanticSnapshotProvider'),
    );
    expect(
      entriesById['workspace.file-explorer']?.summary,
      contains('create, rename, delete, and reveal contracts'),
    );
    expect(
      entriesById['presentation.problems-panel']?.dependencies,
      contains('workspace.diagnostics'),
    );
    expect(
      entriesById['presentation.output-panel']?.summary,
      contains('Output Channels'),
    );
    expect(
      entriesById['interaction.diagnostics']?.dependencies,
      contains('workspace.diagnostics'),
    );
    expect(
      entriesById['runtime.terminal']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['runtime.terminal']?.summary,
      contains('TerminalInteractionController'),
    );
    expect(
      entriesById['interaction.testing']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('TestRunProvider'),
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('TestDiscoveryProvider'),
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('run history'),
    );
    expect(
      entriesById['interaction.testing']?.dependencies,
      contains('runtime.execution'),
    );
    expect(
      entriesById['interaction.source-control']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('staging action contracts'),
    );
    expect(
      entriesById['extension.marketplace']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['extension.marketplace']?.summary,
      contains('enable/disable/trust actions'),
    );
    expect(
      entriesById['interaction.command-palette']?.status,
      IdeCapabilityStatus.wired,
    );
    expect(
      entriesById['interaction.command-palette']?.summary,
      contains('blocked command availability reasons'),
    );
    expect(
      entriesById['interaction.command-palette']?.summary,
      contains('category contribution manifests'),
    );
    expect(
      entriesById['workspace.edit-application']?.status,
      IdeCapabilityStatus.wired,
    );
    expect(
      entriesById['workspace.edit-application']?.summary,
      contains('WorkspaceEditPreview'),
    );
    expect(
      entriesById['workspace.edit-application']?.todo,
      isNot(contains('add preview')),
    );
    expect(
      entriesById['agent.coding-loop']?.dependencies,
      contains('workspace.edit-application'),
    );
    expect(snapshot.missingRequiredCapabilityIds, isEmpty);
    expect(json['missingRequiredCapabilityIds'], isEmpty);
    expect(
      json['requiredCapabilityIds'],
      containsAll(requiredVityoIdeCapabilityIds),
    );
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
