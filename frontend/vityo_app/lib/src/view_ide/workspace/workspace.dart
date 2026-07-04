export 'workspace_controller.dart';
export 'workspace_breadcrumbs.dart';
export 'workspace_code_lens.dart';
export 'workspace_declaration.dart';
export 'workspace_definition.dart';
export 'workspace_document_highlights.dart';
export 'workspace_document_links.dart';
export 'workspace_call_hierarchy.dart';
export 'workspace_code_actions.dart';
export 'hosted_backend_retry_executor.dart';
export 'hosted_workspace_lifecycle.dart';
export 'workspace_document_store.dart';
export 'workspace_navigation_history.dart';
export 'workspace_outline.dart';
export 'workspace_implementation.dart';
export 'workspace_document_store_types.dart';
export 'workspace_problems.dart';
// workspace_quick_open.dart excluded from barrel: duplicate WorkspaceQuickOpenService
// (canonical version in workspace_search_service.dart); import directly if needed.
// workspace_symbol_search.dart excluded from barrel: duplicate
// WorkspaceSymbolSearchService (canonical version in workspace_search_service.dart);
// import directly if needed.
export 'workspace_reference_search.dart';
export 'workspace_rename.dart';
export 'workspace_search.dart';
export 'workspace_type_definition.dart';
export 'workspace_type_hierarchy.dart';
export 'workspace_search_service.dart';
export 'workspace_search_history_store.dart';
export 'workspace_file_operations.dart';
export 'workspace_file_command_router.dart';
export 'workspace_file_explorer_controller.dart';
export 'workspace_file_explorer_state_store.dart';
export 'vfs.dart';
export 'workspace_file_index.dart';
export 'source_control_status.dart';
export 'source_control_status_controller.dart';
export 'source_control_commit_draft_store.dart';
export 'source_control_diff_session_store.dart';
export 'workspace_edit.dart';
export 'workspace_diagnostics.dart';
export 'workspace_diagnostics_controller.dart';
export 'workspace_diagnostics_filter_store.dart';
export 'hosted_workspace_document_store.dart';
export 'hosted_workspace_file_system_provider.dart';
export 'source_control_adapter.dart'
    hide SourceControlProviderKind; // duplicated in source_control_status.dart
export 'workspace_document_store_io.dart'
    hide
        createPlatformWorkspaceDocumentStore; // duplicated in workspace_document_store_web.dart
export 'workspace_document_store_web.dart';
