import 'workspace_document_store_types.dart';
import '../local_service/vityod_client.dart';
import 'workspace_document_store_web.dart'
    if (dart.library.io) 'workspace_document_store_io.dart'
    as platform_store;

export 'workspace_document_store_types.dart';
export 'hosted_workspace_document_store.dart';
export 'hosted_workspace_file_system_provider.dart';

Future<WorkspaceDocumentStore> createWorkspaceDocumentStore({
  VityodClient? vityodClient,
  String? workspaceId,
  String? workspaceRoot,
}) {
  return platform_store.createPlatformWorkspaceDocumentStore(
    vityodClient: vityodClient,
    workspaceId: workspaceId,
    workspaceRoot: workspaceRoot,
  );
}
