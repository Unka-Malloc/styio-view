/// Editor transaction boundary.
///
/// Undo/redo snapshots and language-action edits still live inside the editor
/// controller. New mutation semantics should be extracted here before they are
/// exposed to render widgets.
library;
