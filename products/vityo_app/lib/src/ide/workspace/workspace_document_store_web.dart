import 'package:shared_preferences/shared_preferences.dart';

import 'workspace_document_store_types.dart';

Future<WorkspaceDocumentStore> createPlatformWorkspaceDocumentStore() async {
  final preferences = await SharedPreferences.getInstance();
  return SharedPreferencesWorkspaceDocumentStore(preferences);
}
