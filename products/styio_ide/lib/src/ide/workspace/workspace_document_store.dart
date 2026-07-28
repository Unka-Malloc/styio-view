import 'workspace_document_store_types.dart';
import 'workspace_document_store_web.dart'
    if (dart.library.io) 'workspace_document_store_io.dart'
    as platform_store;

export 'workspace_document_store_types.dart';
export 'hosted_workspace_document_store.dart';
export 'hosted_workspace_file_system_provider.dart';

Future<WorkspaceDocumentStore> createWorkspaceDocumentStore() {
  return platform_store.createPlatformWorkspaceDocumentStore();
}
