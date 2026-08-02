import 'ide_fact_provider.dart';

abstract interface class RevisionBoundIdeFactReader {
  Future<RevisionedIdeFacts> read(
    IdeFactQuery query,
    int expectedWorkspaceRevision,
  );
}

final class UserFacingIdeFactReader implements RevisionBoundIdeFactReader {
  const UserFacingIdeFactReader(this._provider);

  final IdeFactProvider _provider;

  @override
  Future<RevisionedIdeFacts> read(
    IdeFactQuery query,
    int expectedWorkspaceRevision,
  ) {
    return _provider.read(query, expectedWorkspaceRevision);
  }
}
