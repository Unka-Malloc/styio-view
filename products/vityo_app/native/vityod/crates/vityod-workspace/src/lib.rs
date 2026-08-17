use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs;
use std::io::{Read, Write};
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;
use std::time::UNIX_EPOCH;

const MAXIMUM_FILE_BYTES: u64 = 512 * 1024;
const MAXIMUM_LIST_ENTRIES: usize = 50_000;
const MAXIMUM_WATCH_EVENTS: usize = 1_024;
const MAXIMUM_INDEXED_FILES: usize = 10_000;
const MAXIMUM_INDEXED_TEXT_BYTES: usize = 32 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentChange {
    pub relative_path: String,
    pub expected_document_revision: u64,
    pub contents: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommitReceipt {
    pub workspace_revision: u64,
    pub document_revisions: HashMap<String, u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct DocumentState {
    revision: u64,
    contents: String,
}

#[derive(Debug, Default)]
pub struct WorkspaceActor {
    revision: u64,
    documents: HashMap<String, DocumentState>,
}

impl WorkspaceActor {
    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn seed(&mut self, path: &str, contents: &str) -> Result<(), WorkspaceError> {
        validate_relative_path(path)?;
        self.documents.insert(
            path.to_owned(),
            DocumentState {
                revision: 0,
                contents: contents.to_owned(),
            },
        );
        Ok(())
    }

    pub fn commit(
        &mut self,
        expected_workspace_revision: u64,
        changes: Vec<DocumentChange>,
    ) -> Result<CommitReceipt, WorkspaceError> {
        if expected_workspace_revision != self.revision {
            return Err(WorkspaceError::WorkspaceConflict {
                expected: expected_workspace_revision,
                actual: self.revision,
            });
        }
        if changes.is_empty() {
            return Err(WorkspaceError::EmptyTransaction);
        }
        for change in &changes {
            validate_relative_path(&change.relative_path)?;
            let actual = self
                .documents
                .get(&change.relative_path)
                .map_or(0, |state| state.revision);
            if actual != change.expected_document_revision {
                return Err(WorkspaceError::DocumentConflict {
                    path: change.relative_path.clone(),
                    expected: change.expected_document_revision,
                    actual,
                });
            }
        }
        self.revision += 1;
        let mut revisions = HashMap::with_capacity(changes.len());
        for change in changes {
            let state = self
                .documents
                .entry(change.relative_path.clone())
                .or_insert(DocumentState {
                    revision: 0,
                    contents: String::new(),
                });
            state.revision += 1;
            state.contents = change.contents;
            revisions.insert(change.relative_path, state.revision);
        }
        Ok(CommitReceipt {
            workspace_revision: self.revision,
            document_revisions: revisions,
        })
    }

    pub fn read(&self, relative_path: &str) -> Result<(&str, u64), WorkspaceError> {
        validate_relative_path(relative_path)?;
        let document = self
            .documents
            .get(relative_path)
            .ok_or_else(|| WorkspaceError::DocumentMissing(relative_path.to_owned()))?;
        Ok((&document.contents, document.revision))
    }

    pub fn search(&self, query: &str, limit: usize) -> Vec<SearchMatch> {
        if query.is_empty() || limit == 0 {
            return Vec::new();
        }
        let mut paths: Vec<&String> = self.documents.keys().collect();
        paths.sort_unstable();
        let mut matches = Vec::with_capacity(limit.min(32));
        let query_utf16_length = query.encode_utf16().count();
        for path in paths {
            let contents = &self.documents[path].contents;
            let mut line_utf16_offset = 0_usize;
            for (line_index, segment) in contents.split_inclusive('\n').enumerate() {
                let line_without_newline = segment.strip_suffix('\n').unwrap_or(segment);
                let line = line_without_newline
                    .strip_suffix('\r')
                    .unwrap_or(line_without_newline);
                for (column, _) in line.match_indices(query) {
                    let column_utf16 = line[..column].encode_utf16().count();
                    let start_offset = line_utf16_offset + column_utf16;
                    matches.push(SearchMatch {
                        relative_path: path.clone(),
                        line: line_index + 1,
                        column: column_utf16 + 1,
                        start_offset,
                        end_offset: start_offset + query_utf16_length,
                        text: query.to_owned(),
                        line_text: line.to_owned(),
                    });
                    if matches.len() == limit {
                        return matches;
                    }
                }
                line_utf16_offset += segment.encode_utf16().count();
            }
        }
        matches
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchMatch {
    pub relative_path: String,
    pub line: usize,
    pub column: usize,
    pub start_offset: usize,
    pub end_offset: usize,
    pub text: String,
    pub line_text: String,
}

pub fn validate_relative_path(value: &str) -> Result<(), WorkspaceError> {
    let path = Path::new(value);
    if value.is_empty()
        || path.components().any(|component| {
            matches!(
                component,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return Err(WorkspaceError::PathEscape(value.to_owned()));
    }
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WorkspaceError {
    EmptyTransaction,
    PathEscape(String),
    DocumentMissing(String),
    WorkspaceConflict {
        expected: u64,
        actual: u64,
    },
    DocumentConflict {
        path: String,
        expected: u64,
        actual: u64,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileKind {
    File,
    Directory,
    Link,
    NotFound,
    Other,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileEntry {
    pub relative_path: String,
    pub kind: FileKind,
    pub size: u64,
    pub modified_unix_millis: Option<u64>,
    pub modified_unix_nanos: Option<u128>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileEventKind {
    Created,
    Modified,
    Deleted,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileEvent {
    pub kind: FileEventKind,
    pub relative_path: String,
    pub is_directory: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WatchPoll {
    pub events: Vec<FileEvent>,
    pub overflowed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PagedSearchResult {
    pub matches: Vec<SearchMatch>,
    pub next_cursor: Option<usize>,
    pub skipped_large_files: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct EntryFingerprint {
    kind: FileKind,
    size: u64,
    modified_unix_nanos: Option<u128>,
}

#[derive(Debug)]
struct WatchState {
    scope_id: String,
    relative_path: String,
    recursive: bool,
    snapshot: HashMap<String, EntryFingerprint>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SearchFingerprint {
    size: u64,
    modified_unix_nanos: Option<u128>,
}

#[derive(Debug, Clone)]
struct IndexedTextFile {
    fingerprint: SearchFingerprint,
    contents: Arc<str>,
}

#[derive(Debug, Default)]
struct SearchIndexState {
    files: BTreeMap<String, IndexedTextFile>,
    total_bytes: usize,
    disk_reads: usize,
    cache_hits: usize,
}

#[derive(Debug, Default)]
pub struct WorkspaceFileService {
    scopes: HashMap<String, PathBuf>,
    watchers: HashMap<String, WatchState>,
    search_indexes: RefCell<HashMap<String, SearchIndexState>>,
}

impl WorkspaceFileService {
    pub fn has_scope(&self, scope_id: &str) -> bool {
        self.scopes.contains_key(scope_id)
    }

    pub fn scope_root(&self, scope_id: &str) -> Result<PathBuf, FileServiceError> {
        Ok(self.scope(scope_id)?.to_path_buf())
    }

    pub fn open_scope(&mut self, scope_id: &str, root: &Path) -> Result<(), FileServiceError> {
        if !valid_identifier(scope_id) || !root.is_absolute() {
            return Err(FileServiceError::InvalidRequest);
        }
        let root = root
            .canonicalize()
            .map_err(|_| FileServiceError::RootUnavailable)?;
        if !root.is_dir() {
            return Err(FileServiceError::RootUnavailable);
        }
        self.watchers.retain(|_, watch| watch.scope_id != scope_id);
        self.search_indexes.borrow_mut().remove(scope_id);
        self.scopes.insert(scope_id.to_owned(), root);
        Ok(())
    }

    pub fn close_scope(&mut self, scope_id: &str) -> Result<(), FileServiceError> {
        if self.scopes.remove(scope_id).is_none() {
            return Err(FileServiceError::UnknownScope);
        }
        self.watchers.retain(|_, watch| watch.scope_id != scope_id);
        self.search_indexes.borrow_mut().remove(scope_id);
        Ok(())
    }

    pub fn stat(&self, scope_id: &str, relative_path: &str) -> Result<FileEntry, FileServiceError> {
        let target = self.resolve_target(scope_id, relative_path)?;
        let metadata = match fs::symlink_metadata(&target) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(FileEntry {
                    relative_path: normalize_relative(relative_path)?
                        .to_string_lossy()
                        .into_owned(),
                    kind: FileKind::NotFound,
                    size: 0,
                    modified_unix_millis: None,
                    modified_unix_nanos: None,
                });
            }
            Err(_) => return Err(FileServiceError::Io),
        };
        if metadata.file_type().is_symlink() {
            self.resolve_existing(scope_id, relative_path)?;
        }
        entry_for(relative_path, &metadata)
    }

    pub fn read(&self, scope_id: &str, relative_path: &str) -> Result<Vec<u8>, FileServiceError> {
        let target = self.resolve_existing(scope_id, relative_path)?;
        let metadata = fs::metadata(&target).map_err(map_io_error)?;
        if !metadata.is_file() {
            return Err(FileServiceError::NotFile);
        }
        if metadata.len() > MAXIMUM_FILE_BYTES {
            return Err(FileServiceError::CapacityExceeded);
        }
        let mut file = fs::File::open(target).map_err(map_io_error)?;
        let mut contents = Vec::with_capacity(metadata.len() as usize);
        file.read_to_end(&mut contents)
            .map_err(|_| FileServiceError::Io)?;
        Ok(contents)
    }

    pub fn write(
        &self,
        scope_id: &str,
        relative_path: &str,
        contents: &[u8],
        create_parents: bool,
        atomic: bool,
    ) -> Result<(), FileServiceError> {
        if contents.len() as u64 > MAXIMUM_FILE_BYTES {
            return Err(FileServiceError::CapacityExceeded);
        }
        let target = self.resolve_target(scope_id, relative_path)?;
        let parent = target.parent().ok_or(FileServiceError::InvalidPath)?;
        if create_parents {
            fs::create_dir_all(parent).map_err(map_io_error)?;
            self.ensure_within_scope(scope_id, parent)?;
            sync_directory_chain(parent, self.scope(scope_id)?)?;
        } else {
            self.ensure_within_scope(scope_id, parent)?;
        }
        if atomic {
            let file_name = target
                .file_name()
                .and_then(|name| name.to_str())
                .ok_or(FileServiceError::InvalidPath)?;
            let temporary = parent.join(format!(".{file_name}.vityo-write"));
            let mut file = fs::OpenOptions::new()
                .create_new(true)
                .write(true)
                .open(&temporary)
                .map_err(map_io_error)?;
            let write_result = file
                .write_all(contents)
                .and_then(|()| file.sync_all())
                .and_then(|()| fs::rename(&temporary, &target));
            if write_result.is_err() {
                let _ = fs::remove_file(&temporary);
                return Err(FileServiceError::Io);
            }
            sync_parent(parent)?;
            self.invalidate_search_path(scope_id, relative_path);
            return Ok(());
        }
        let mut file = fs::File::create(target).map_err(map_io_error)?;
        file.write_all(contents).map_err(|_| FileServiceError::Io)?;
        file.sync_all().map_err(|_| FileServiceError::Io)?;
        self.invalidate_search_path(scope_id, relative_path);
        Ok(())
    }

    pub fn create_directory(
        &self,
        scope_id: &str,
        relative_path: &str,
        recursive: bool,
    ) -> Result<(), FileServiceError> {
        let target = self.resolve_target(scope_id, relative_path)?;
        let result = if recursive {
            fs::create_dir_all(&target)
        } else {
            fs::create_dir(&target)
        };
        result.map_err(map_io_error)?;
        self.ensure_within_scope(scope_id, &target)
    }

    pub fn delete(
        &self,
        scope_id: &str,
        relative_path: &str,
        recursive: bool,
    ) -> Result<(), FileServiceError> {
        let normalized = normalize_relative(relative_path)?;
        if normalized.as_os_str().is_empty() || normalized == Path::new(".") {
            return Err(FileServiceError::RootMutationDenied);
        }
        let target = match self.resolve_existing(scope_id, relative_path) {
            Ok(target) => target,
            Err(FileServiceError::NotFound) => return Ok(()),
            Err(error) => return Err(error),
        };
        let metadata = fs::symlink_metadata(&target).map_err(map_io_error)?;
        if metadata.is_dir() {
            if recursive {
                fs::remove_dir_all(&target)
            } else {
                fs::remove_dir(&target)
            }
        } else {
            fs::remove_file(&target)
        }
        .map_err(map_io_error)?;
        let parent = target.parent().ok_or(FileServiceError::InvalidPath)?;
        sync_parent(parent)?;
        self.invalidate_search_path(scope_id, relative_path);
        Ok(())
    }

    pub fn copy(
        &self,
        scope_id: &str,
        source_relative_path: &str,
        target_relative_path: &str,
        overwrite: bool,
    ) -> Result<(), FileServiceError> {
        let source = self.resolve_existing(scope_id, source_relative_path)?;
        let target = self.resolve_target(scope_id, target_relative_path)?;
        prepare_target(&target, overwrite)?;
        copy_entity(&source, &target)?;
        self.ensure_within_scope(scope_id, &target)?;
        self.invalidate_search_path(scope_id, target_relative_path);
        Ok(())
    }

    pub fn move_entity(
        &self,
        scope_id: &str,
        source_relative_path: &str,
        target_relative_path: &str,
        overwrite: bool,
    ) -> Result<(), FileServiceError> {
        let source = self.resolve_existing(scope_id, source_relative_path)?;
        let target = self.resolve_target(scope_id, target_relative_path)?;
        prepare_target(&target, overwrite)?;
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent).map_err(map_io_error)?;
            self.ensure_within_scope(scope_id, parent)?;
            sync_directory_chain(parent, self.scope(scope_id)?)?;
        }
        let source_parent = source
            .parent()
            .ok_or(FileServiceError::InvalidPath)?
            .to_path_buf();
        let target_parent = target
            .parent()
            .ok_or(FileServiceError::InvalidPath)?
            .to_path_buf();
        fs::rename(source, target).map_err(map_io_error)?;
        sync_parent(&source_parent)?;
        if target_parent != source_parent {
            sync_parent(&target_parent)?;
        }
        self.invalidate_search_path(scope_id, source_relative_path);
        self.invalidate_search_path(scope_id, target_relative_path);
        Ok(())
    }

    pub fn list(
        &self,
        scope_id: &str,
        relative_path: &str,
        recursive: bool,
    ) -> Result<Vec<FileEntry>, FileServiceError> {
        let root = self.resolve_existing(scope_id, relative_path)?;
        if !root.is_dir() {
            return Err(FileServiceError::NotDirectory);
        }
        let scope_root = self.scope(scope_id)?;
        let mut entries = Vec::new();
        collect_entries(scope_root, &root, recursive, &mut entries)?;
        entries.sort_unstable_by(|left, right| left.relative_path.cmp(&right.relative_path));
        Ok(entries)
    }

    pub fn set_executable(
        &self,
        scope_id: &str,
        relative_path: &str,
        executable: bool,
    ) -> Result<(), FileServiceError> {
        let target = self.resolve_existing(scope_id, relative_path)?;
        set_executable(&target, executable)
    }

    pub fn is_executable(
        &self,
        scope_id: &str,
        relative_path: &str,
    ) -> Result<bool, FileServiceError> {
        let target = self.resolve_existing(scope_id, relative_path)?;
        is_executable(&target)
    }

    pub fn start_watch(
        &mut self,
        watch_id: &str,
        scope_id: &str,
        relative_path: &str,
        recursive: bool,
    ) -> Result<(), FileServiceError> {
        if !valid_identifier(watch_id) || self.watchers.contains_key(watch_id) {
            return Err(FileServiceError::InvalidRequest);
        }
        let snapshot = self.snapshot(scope_id, relative_path, recursive)?;
        self.watchers.insert(
            watch_id.to_owned(),
            WatchState {
                scope_id: scope_id.to_owned(),
                relative_path: relative_path.to_owned(),
                recursive,
                snapshot,
            },
        );
        Ok(())
    }

    pub fn poll_watch(&mut self, watch_id: &str) -> Result<WatchPoll, FileServiceError> {
        let watch = self
            .watchers
            .get(watch_id)
            .ok_or(FileServiceError::UnknownWatch)?;
        let next = self.snapshot(&watch.scope_id, &watch.relative_path, watch.recursive)?;
        let mut events = diff_snapshots(&watch.snapshot, &next);
        let overflowed = events.len() > MAXIMUM_WATCH_EVENTS;
        if overflowed {
            events.clear();
        }
        if overflowed {
            self.search_indexes.borrow_mut().remove(&watch.scope_id);
        } else {
            for event in &events {
                self.invalidate_search_path(&watch.scope_id, &event.relative_path);
            }
        }
        self.watchers
            .get_mut(watch_id)
            .expect("watch remains registered")
            .snapshot = next;
        Ok(WatchPoll { events, overflowed })
    }

    pub fn stop_watch(&mut self, watch_id: &str) -> Result<(), FileServiceError> {
        self.watchers
            .remove(watch_id)
            .map(|_| ())
            .ok_or(FileServiceError::UnknownWatch)
    }

    pub fn search(
        &self,
        scope_id: &str,
        query: &str,
        cursor: usize,
        limit: usize,
    ) -> Result<PagedSearchResult, FileServiceError> {
        if query.is_empty() || query.len() > 1_024 || limit == 0 || limit > 1_000 {
            return Err(FileServiceError::InvalidRequest);
        }
        let entries = self.list(scope_id, ".", true)?;
        let live_paths = entries
            .iter()
            .filter(|entry| entry.kind == FileKind::File)
            .map(|entry| entry.relative_path.as_str())
            .collect::<HashSet<_>>();
        if let Some(index) = self.search_indexes.borrow_mut().get_mut(scope_id) {
            index.files.retain(|path, indexed| {
                if live_paths.contains(path.as_str()) {
                    true
                } else {
                    index.total_bytes = index.total_bytes.saturating_sub(indexed.contents.len());
                    false
                }
            });
        }
        let mut matched = 0_usize;
        let mut matches = Vec::with_capacity(limit.min(64));
        let mut skipped_large_files = 0_usize;
        let mut has_more = false;
        let query_utf16_length = query.encode_utf16().count();
        'files: for entry in entries {
            if entry.kind != FileKind::File {
                continue;
            }
            if entry.size > MAXIMUM_FILE_BYTES {
                skipped_large_files += 1;
                continue;
            }
            let Some(contents) = self.indexed_text(scope_id, &entry)? else {
                continue;
            };
            let mut line_utf16_offset = 0_usize;
            for (line_index, segment) in contents.split_inclusive('\n').enumerate() {
                let line_without_newline = segment.strip_suffix('\n').unwrap_or(segment);
                let line = line_without_newline
                    .strip_suffix('\r')
                    .unwrap_or(line_without_newline);
                for (column, _) in line.match_indices(query) {
                    if matched < cursor {
                        matched += 1;
                        continue;
                    }
                    if matches.len() == limit {
                        has_more = true;
                        break 'files;
                    }
                    let column_utf16 = line[..column].encode_utf16().count();
                    let start_offset = line_utf16_offset + column_utf16;
                    matches.push(SearchMatch {
                        relative_path: entry.relative_path.clone(),
                        line: line_index + 1,
                        column: column_utf16 + 1,
                        start_offset,
                        end_offset: start_offset + query_utf16_length,
                        text: query.to_owned(),
                        line_text: line.to_owned(),
                    });
                    matched += 1;
                }
                line_utf16_offset += segment.encode_utf16().count();
            }
        }
        Ok(PagedSearchResult {
            next_cursor: has_more.then_some(cursor + matches.len()),
            matches,
            skipped_large_files,
        })
    }

    fn indexed_text(
        &self,
        scope_id: &str,
        entry: &FileEntry,
    ) -> Result<Option<Arc<str>>, FileServiceError> {
        let fingerprint = SearchFingerprint {
            size: entry.size,
            modified_unix_nanos: entry.modified_unix_nanos,
        };
        let cached = {
            let mut indexes = self.search_indexes.borrow_mut();
            let index = indexes.entry(scope_id.to_owned()).or_default();
            match index.files.get(&entry.relative_path) {
                Some(indexed) if indexed.fingerprint == fingerprint => {
                    index.cache_hits += 1;
                    Some(indexed.contents.clone())
                }
                _ => None,
            }
        };
        if cached.is_some() {
            return Ok(cached);
        }

        let bytes = self.read(scope_id, &entry.relative_path)?;
        let Ok(text) = String::from_utf8(bytes) else {
            self.invalidate_search_path(scope_id, &entry.relative_path);
            return Ok(None);
        };
        let contents: Arc<str> = Arc::from(text);
        let mut indexes = self.search_indexes.borrow_mut();
        let index = indexes.entry(scope_id.to_owned()).or_default();
        index.disk_reads += 1;
        if let Some(previous) = index.files.remove(&entry.relative_path) {
            index.total_bytes = index.total_bytes.saturating_sub(previous.contents.len());
        }
        if index.files.len() < MAXIMUM_INDEXED_FILES
            && index.total_bytes.saturating_add(contents.len()) <= MAXIMUM_INDEXED_TEXT_BYTES
        {
            index.total_bytes += contents.len();
            index.files.insert(
                entry.relative_path.clone(),
                IndexedTextFile {
                    fingerprint,
                    contents: contents.clone(),
                },
            );
        }
        Ok(Some(contents))
    }

    fn invalidate_search_path(&self, scope_id: &str, relative_path: &str) {
        let Ok(relative) = normalize_relative(relative_path) else {
            return;
        };
        let path = relative.to_string_lossy();
        let mut indexes = self.search_indexes.borrow_mut();
        let Some(index) = indexes.get_mut(scope_id) else {
            return;
        };
        if path.is_empty() || path == "." {
            index.files.clear();
            index.total_bytes = 0;
            return;
        }
        let prefix = format!("{path}/");
        index.files.retain(|candidate, indexed| {
            if candidate == path.as_ref() || candidate.starts_with(&prefix) {
                index.total_bytes = index.total_bytes.saturating_sub(indexed.contents.len());
                false
            } else {
                true
            }
        });
    }

    fn scope(&self, scope_id: &str) -> Result<&Path, FileServiceError> {
        self.scopes
            .get(scope_id)
            .map(PathBuf::as_path)
            .ok_or(FileServiceError::UnknownScope)
    }

    fn resolve_existing(
        &self,
        scope_id: &str,
        relative_path: &str,
    ) -> Result<PathBuf, FileServiceError> {
        let root = self.scope(scope_id)?;
        let relative = normalize_relative(relative_path)?;
        let target = root.join(relative);
        let canonical = target.canonicalize().map_err(map_io_error)?;
        if !canonical.starts_with(root) {
            return Err(FileServiceError::RootEscape);
        }
        Ok(canonical)
    }

    fn resolve_target(
        &self,
        scope_id: &str,
        relative_path: &str,
    ) -> Result<PathBuf, FileServiceError> {
        let root = self.scope(scope_id)?;
        let relative = normalize_relative(relative_path)?;
        let target = root.join(relative);
        let mut ancestor = target.as_path();
        while fs::symlink_metadata(ancestor).is_err() {
            ancestor = ancestor.parent().ok_or(FileServiceError::InvalidPath)?;
        }
        let canonical_ancestor = ancestor.canonicalize().map_err(map_io_error)?;
        if !canonical_ancestor.starts_with(root) {
            return Err(FileServiceError::RootEscape);
        }
        if fs::symlink_metadata(&target).is_ok() {
            let canonical_target = target.canonicalize().map_err(map_io_error)?;
            if !canonical_target.starts_with(root) {
                return Err(FileServiceError::RootEscape);
            }
        }
        Ok(target)
    }

    fn ensure_within_scope(&self, scope_id: &str, path: &Path) -> Result<(), FileServiceError> {
        let root = self.scope(scope_id)?;
        let canonical = path.canonicalize().map_err(map_io_error)?;
        if canonical.starts_with(root) {
            Ok(())
        } else {
            Err(FileServiceError::RootEscape)
        }
    }

    fn snapshot(
        &self,
        scope_id: &str,
        relative_path: &str,
        recursive: bool,
    ) -> Result<HashMap<String, EntryFingerprint>, FileServiceError> {
        Ok(self
            .list(scope_id, relative_path, recursive)?
            .into_iter()
            .map(|entry| {
                (
                    entry.relative_path,
                    EntryFingerprint {
                        kind: entry.kind,
                        size: entry.size,
                        modified_unix_nanos: entry.modified_unix_nanos,
                    },
                )
            })
            .collect())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileServiceError {
    InvalidRequest,
    InvalidPath,
    UnknownScope,
    UnknownWatch,
    RootUnavailable,
    RootEscape,
    RootMutationDenied,
    NotFound,
    NotFile,
    NotDirectory,
    AlreadyExists,
    CapacityExceeded,
    Unsupported,
    Io,
}

fn valid_identifier(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 256
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
}

fn normalize_relative(value: &str) -> Result<PathBuf, FileServiceError> {
    if value.is_empty() {
        return Ok(PathBuf::from("."));
    }
    let path = Path::new(value);
    if path.is_absolute()
        || path.components().any(|component| {
            matches!(
                component,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return Err(FileServiceError::RootEscape);
    }
    Ok(path.to_path_buf())
}

fn entry_for(relative_path: &str, metadata: &fs::Metadata) -> Result<FileEntry, FileServiceError> {
    let file_type = metadata.file_type();
    let kind = if file_type.is_file() {
        FileKind::File
    } else if file_type.is_dir() {
        FileKind::Directory
    } else if file_type.is_symlink() {
        FileKind::Link
    } else {
        FileKind::Other
    };
    Ok(FileEntry {
        relative_path: normalize_relative(relative_path)?
            .to_string_lossy()
            .into_owned(),
        kind,
        size: metadata.len(),
        modified_unix_millis: metadata
            .modified()
            .ok()
            .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
            .and_then(|duration| duration.as_millis().try_into().ok()),
        modified_unix_nanos: metadata
            .modified()
            .ok()
            .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
            .map(|duration| duration.as_nanos()),
    })
}

fn collect_entries(
    scope_root: &Path,
    directory: &Path,
    recursive: bool,
    entries: &mut Vec<FileEntry>,
) -> Result<(), FileServiceError> {
    let mut children = fs::read_dir(directory)
        .map_err(map_io_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| FileServiceError::Io)?;
    children.sort_unstable_by_key(fs::DirEntry::file_name);
    for child in children {
        if entries.len() >= MAXIMUM_LIST_ENTRIES {
            return Err(FileServiceError::CapacityExceeded);
        }
        let path = child.path();
        let metadata = fs::symlink_metadata(&path).map_err(map_io_error)?;
        if !metadata.file_type().is_symlink() {
            let canonical = path.canonicalize().map_err(map_io_error)?;
            if !canonical.starts_with(scope_root) {
                return Err(FileServiceError::RootEscape);
            }
        }
        let relative = path
            .strip_prefix(scope_root)
            .map_err(|_| FileServiceError::RootEscape)?
            .to_string_lossy()
            .into_owned();
        entries.push(entry_for(&relative, &metadata)?);
        if recursive && metadata.is_dir() && !metadata.file_type().is_symlink() {
            collect_entries(scope_root, &path, true, entries)?;
        }
    }
    Ok(())
}

fn prepare_target(target: &Path, overwrite: bool) -> Result<(), FileServiceError> {
    let Ok(metadata) = fs::symlink_metadata(target) else {
        return Ok(());
    };
    if !overwrite {
        return Err(FileServiceError::AlreadyExists);
    }
    if metadata.is_dir() {
        fs::remove_dir_all(target)
    } else {
        fs::remove_file(target)
    }
    .map_err(map_io_error)
}

fn copy_entity(source: &Path, target: &Path) -> Result<(), FileServiceError> {
    let metadata = fs::symlink_metadata(source).map_err(map_io_error)?;
    if metadata.file_type().is_symlink() {
        return Err(FileServiceError::Unsupported);
    }
    if metadata.is_dir() {
        fs::create_dir_all(target).map_err(map_io_error)?;
        let mut children = fs::read_dir(source)
            .map_err(map_io_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| FileServiceError::Io)?;
        children.sort_unstable_by_key(fs::DirEntry::file_name);
        for child in children {
            copy_entity(&child.path(), &target.join(child.file_name()))?;
        }
        return Ok(());
    }
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(map_io_error)?;
    }
    fs::copy(source, target).map(|_| ()).map_err(map_io_error)
}

fn diff_snapshots(
    previous: &HashMap<String, EntryFingerprint>,
    next: &HashMap<String, EntryFingerprint>,
) -> Vec<FileEvent> {
    let all_paths = previous
        .keys()
        .chain(next.keys())
        .cloned()
        .collect::<HashSet<_>>();
    let mut paths = all_paths.into_iter().collect::<Vec<_>>();
    paths.sort_unstable();
    let mut events = Vec::new();
    for path in paths {
        match (previous.get(&path), next.get(&path)) {
            (None, Some(current)) => events.push(FileEvent {
                kind: FileEventKind::Created,
                relative_path: path,
                is_directory: current.kind == FileKind::Directory,
            }),
            (Some(previous), Some(current)) if previous != current => events.push(FileEvent {
                kind: FileEventKind::Modified,
                relative_path: path,
                is_directory: current.kind == FileKind::Directory,
            }),
            (Some(previous), None) => events.push(FileEvent {
                kind: FileEventKind::Deleted,
                relative_path: path,
                is_directory: previous.kind == FileKind::Directory,
            }),
            _ => {}
        }
    }
    events
}

fn map_io_error(error: std::io::Error) -> FileServiceError {
    match error.kind() {
        std::io::ErrorKind::NotFound => FileServiceError::NotFound,
        std::io::ErrorKind::AlreadyExists => FileServiceError::AlreadyExists,
        _ => FileServiceError::Io,
    }
}

#[cfg(unix)]
fn set_executable(path: &Path, executable: bool) -> Result<(), FileServiceError> {
    use std::os::unix::fs::PermissionsExt;
    let metadata = fs::metadata(path).map_err(map_io_error)?;
    let mut permissions = metadata.permissions();
    let mode = permissions.mode();
    permissions.set_mode(if executable {
        mode | 0o100
    } else {
        mode & !0o100
    });
    fs::set_permissions(path, permissions).map_err(map_io_error)
}

#[cfg(unix)]
fn is_executable(path: &Path) -> Result<bool, FileServiceError> {
    use std::os::unix::fs::PermissionsExt;
    let metadata = fs::metadata(path).map_err(map_io_error)?;
    Ok(metadata.is_file() && metadata.permissions().mode() & 0o100 != 0)
}

#[cfg(windows)]
fn set_executable(_path: &Path, _executable: bool) -> Result<(), FileServiceError> {
    Ok(())
}

#[cfg(windows)]
fn is_executable(path: &Path) -> Result<bool, FileServiceError> {
    Ok(fs::metadata(path).map_err(map_io_error)?.is_file())
}

#[cfg(not(any(unix, windows)))]
fn set_executable(_path: &Path, _executable: bool) -> Result<(), FileServiceError> {
    Err(FileServiceError::Unsupported)
}

#[cfg(not(any(unix, windows)))]
fn is_executable(_path: &Path) -> Result<bool, FileServiceError> {
    Err(FileServiceError::Unsupported)
}

fn sync_parent(parent: &Path) -> Result<(), FileServiceError> {
    #[cfg(unix)]
    {
        fs::File::open(parent)
            .and_then(|directory| directory.sync_all())
            .map_err(|_| FileServiceError::Io)?;
    }
    let _ = parent;
    Ok(())
}

fn sync_directory_chain(directory: &Path, root: &Path) -> Result<(), FileServiceError> {
    let mut current = Some(directory);
    while let Some(path) = current {
        sync_parent(path)?;
        if path == root {
            break;
        }
        current = path.parent();
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TestDirectory(PathBuf);

    impl TestDirectory {
        fn new(label: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "vityod-workspace-{label}-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .expect("clock is after epoch")
                    .as_nanos()
            ));
            fs::create_dir(&path).expect("test directory is created");
            Self(path)
        }
    }

    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn transaction_is_revision_bound_and_atomic() {
        let mut actor = WorkspaceActor::default();
        actor.seed("lib/main.styio", "before").unwrap();
        let receipt = actor
            .commit(
                0,
                vec![DocumentChange {
                    relative_path: "lib/main.styio".into(),
                    expected_document_revision: 0,
                    contents: "after".into(),
                }],
            )
            .unwrap();
        assert_eq!(receipt.workspace_revision, 1);
        assert!(matches!(
            actor.commit(
                0,
                vec![DocumentChange {
                    relative_path: "lib/main.styio".into(),
                    expected_document_revision: 1,
                    contents: "stale".into(),
                }]
            ),
            Err(WorkspaceError::WorkspaceConflict { .. })
        ));
    }

    #[test]
    fn path_escape_fails_before_effect() {
        let mut actor = WorkspaceActor::default();
        assert!(matches!(
            actor.commit(
                0,
                vec![DocumentChange {
                    relative_path: "../secret".into(),
                    expected_document_revision: 0,
                    contents: "no".into(),
                }]
            ),
            Err(WorkspaceError::PathEscape(_))
        ));
        assert_eq!(actor.revision(), 0);
    }

    #[test]
    fn search_is_deterministic_and_bounded() {
        let mut actor = WorkspaceActor::default();
        actor.seed("b.styio", "needle\nneedle").unwrap();
        actor.seed("a.styio", "needle").unwrap();
        let matches = actor.search("needle", 2);
        assert_eq!(matches.len(), 2);
        assert_eq!(matches[0].relative_path, "a.styio");
        assert_eq!(matches[1].relative_path, "b.styio");
    }

    #[test]
    fn search_reports_utf16_offsets_and_line_text() {
        let mut actor = WorkspaceActor::default();
        actor.seed("unicode.styio", "😀needle\r\nnext").unwrap();
        let matches = actor.search("needle", 1);
        assert_eq!(matches.len(), 1);
        assert_eq!(matches[0].line, 1);
        assert_eq!(matches[0].column, 3);
        assert_eq!(matches[0].start_offset, 2);
        assert_eq!(matches[0].end_offset, 8);
        assert_eq!(matches[0].text, "needle");
        assert_eq!(matches[0].line_text, "😀needle");
    }

    #[test]
    fn file_scope_is_revision_ready_and_search_is_paged() {
        let root = TestDirectory::new("file-service");
        let mut service = WorkspaceFileService::default();
        service.open_scope("workspace", &root.0).unwrap();
        service
            .write("workspace", "src/a.styio", b"needle\nneedle", true, true)
            .unwrap();
        service
            .write("workspace", "src/b.styio", b"needle", true, true)
            .unwrap();

        assert_eq!(
            service.read("workspace", "src/a.styio").unwrap(),
            b"needle\nneedle"
        );
        let first = service.search("workspace", "needle", 0, 2).unwrap();
        assert_eq!(first.matches.len(), 2);
        assert_eq!(first.next_cursor, Some(2));
        let second = service
            .search("workspace", "needle", first.next_cursor.unwrap(), 2)
            .unwrap();
        assert_eq!(second.matches.len(), 1);
        assert_eq!(second.matches[0].relative_path, "src/b.styio");
        assert_eq!(second.next_cursor, None);

        let indexed_before = service
            .search_indexes
            .borrow()
            .get("workspace")
            .map(|index| index.disk_reads)
            .unwrap();
        service.search("workspace", "needle", 0, 100).unwrap();
        let indexed_after_reuse = service
            .search_indexes
            .borrow()
            .get("workspace")
            .map(|index| index.disk_reads)
            .unwrap();
        assert_eq!(indexed_after_reuse, indexed_before);

        service
            .write("workspace", "src/a.styio", b"needle changed", true, true)
            .unwrap();
        service.search("workspace", "needle", 0, 100).unwrap();
        let indexed_after_invalidation = service
            .search_indexes
            .borrow()
            .get("workspace")
            .map(|index| index.disk_reads)
            .unwrap();
        assert_eq!(indexed_after_invalidation, indexed_before + 1);
    }

    #[test]
    fn watch_reports_bounded_snapshot_changes() {
        let root = TestDirectory::new("watch");
        let mut service = WorkspaceFileService::default();
        service.open_scope("workspace", &root.0).unwrap();
        service
            .start_watch("watch-1", "workspace", ".", true)
            .unwrap();
        service
            .write("workspace", "created.styio", b"content", true, true)
            .unwrap();
        let created = service.poll_watch("watch-1").unwrap();
        assert!(!created.overflowed);
        assert_eq!(created.events.len(), 1);
        assert_eq!(created.events[0].kind, FileEventKind::Created);
        service.delete("workspace", "created.styio", false).unwrap();
        let deleted = service.poll_watch("watch-1").unwrap();
        assert_eq!(deleted.events.len(), 1);
        assert_eq!(deleted.events[0].kind, FileEventKind::Deleted);
    }

    #[cfg(unix)]
    #[test]
    fn symlink_escape_is_rejected_at_use_time() {
        use std::os::unix::fs::symlink;

        let root = TestDirectory::new("root");
        let outside = TestDirectory::new("outside");
        fs::write(outside.0.join("private.txt"), b"private").unwrap();
        symlink(&outside.0, root.0.join("escape")).unwrap();
        let mut service = WorkspaceFileService::default();
        service.open_scope("workspace", &root.0).unwrap();

        let entries = service.list("workspace", ".", false).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].relative_path, "escape");
        assert_eq!(entries[0].kind, FileKind::Link);

        assert_eq!(
            service.read("workspace", "escape/private.txt"),
            Err(FileServiceError::RootEscape)
        );
    }
}
