use std::collections::{HashMap, VecDeque};
use std::path::Path;

use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};

const CURRENT_SCHEMA_VERSION: i64 = 7;

type CommitResponseBuilder<'a> =
    dyn Fn(&DurableCommitReceipt) -> Result<Vec<u8>, DurableStateError> + 'a;
type DeleteResponseBuilder<'a> =
    dyn Fn(Option<&DurableCommitReceipt>, u64) -> Result<Vec<u8>, DurableStateError> + 'a;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventRecord<T> {
    pub cursor: u64,
    pub value: T,
}

#[derive(Debug)]
pub struct BoundedEventJournal<T> {
    capacity: usize,
    next_cursor: u64,
    events: VecDeque<EventRecord<T>>,
}

impl<T: Clone> BoundedEventJournal<T> {
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "journal capacity must be positive");
        Self {
            capacity,
            next_cursor: 1,
            events: VecDeque::with_capacity(capacity),
        }
    }

    pub fn push(&mut self, value: T) -> EventRecord<T> {
        let record = EventRecord {
            cursor: self.next_cursor,
            value,
        };
        self.next_cursor += 1;
        if self.events.len() == self.capacity {
            self.events.pop_front();
        }
        self.events.push_back(record.clone());
        record
    }

    pub fn resume_after(&self, cursor: u64) -> Result<Vec<EventRecord<T>>, ResumeGap> {
        if let Some(first) = self.events.front()
            && cursor.saturating_add(1) < first.cursor
        {
            return Err(ResumeGap {
                requested_cursor: cursor,
                oldest_available_cursor: first.cursor,
            });
        }
        Ok(self
            .events
            .iter()
            .filter(|event| event.cursor > cursor)
            .cloned()
            .collect())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResumeGap {
    pub requested_cursor: u64,
    pub oldest_available_cursor: u64,
}

#[derive(Debug, Default)]
pub struct IdempotencyStore<T> {
    receipts: HashMap<String, T>,
}

impl<T: Clone> IdempotencyStore<T> {
    pub fn get(&self, key: &str) -> Option<T> {
        self.receipts.get(key).cloned()
    }

    pub fn insert_once(&mut self, key: String, receipt: T) -> T {
        self.receipts.entry(key).or_insert(receipt).clone()
    }
}

#[derive(Debug)]
pub struct DurableStateStore {
    connection: Connection,
    event_capacity: usize,
}

impl DurableStateStore {
    pub fn open(path: &Path, event_capacity: usize) -> Result<Self, DurableStateError> {
        if event_capacity == 0 {
            return Err(DurableStateError::InvalidEventCapacity);
        }
        let connection = Connection::open(path)?;
        Self::configure(connection, event_capacity)
    }

    pub fn open_in_memory(event_capacity: usize) -> Result<Self, DurableStateError> {
        if event_capacity == 0 {
            return Err(DurableStateError::InvalidEventCapacity);
        }
        let connection = Connection::open_in_memory()?;
        Self::configure(connection, event_capacity)
    }

    fn configure(connection: Connection, event_capacity: usize) -> Result<Self, DurableStateError> {
        connection.pragma_update(None, "journal_mode", "WAL")?;
        connection.pragma_update(None, "synchronous", "FULL")?;
        connection.pragma_update(None, "foreign_keys", true)?;
        connection.busy_timeout(std::time::Duration::from_secs(5))?;

        let mut store = Self {
            connection,
            event_capacity,
        };
        store.migrate()?;
        store.verify_integrity()?;
        Ok(store)
    }

    fn migrate(&mut self) -> Result<(), DurableStateError> {
        let version: i64 = self
            .connection
            .pragma_query_value(None, "user_version", |row| row.get(0))?;
        if version > CURRENT_SCHEMA_VERSION {
            return Err(DurableStateError::UnsupportedSchemaVersion {
                found: version,
                supported: CURRENT_SCHEMA_VERSION,
            });
        }
        if version == CURRENT_SCHEMA_VERSION {
            return Ok(());
        }

        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        transaction.execute_batch(
            "CREATE TABLE IF NOT EXISTS workspace_state (
                 singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                 revision INTEGER NOT NULL CHECK (revision >= 0)
             );
             CREATE TABLE IF NOT EXISTS event_journal (
                 cursor INTEGER PRIMARY KEY AUTOINCREMENT,
                 kind TEXT NOT NULL,
                 workspace_revision INTEGER NOT NULL CHECK (workspace_revision >= 0),
                 payload BLOB NOT NULL
             );
             CREATE TABLE IF NOT EXISTS idempotency_receipts (
                 idempotency_key TEXT PRIMARY KEY,
                 committed_cursor INTEGER,
                 response BLOB NOT NULL
             );
             CREATE TABLE IF NOT EXISTS workspace_documents (
                 relative_path TEXT PRIMARY KEY,
                 revision INTEGER NOT NULL CHECK (revision >= 0),
                 contents BLOB NOT NULL,
                 encoding TEXT
             );
             CREATE TABLE IF NOT EXISTS agent_sessions (
                 session_id TEXT PRIMARY KEY,
                 workspace_id TEXT NOT NULL,
                 workspace_revision INTEGER NOT NULL CHECK (workspace_revision >= 0),
                 revoked INTEGER NOT NULL DEFAULT 0 CHECK (revoked IN (0, 1))
             );
             CREATE TABLE IF NOT EXISTS agent_session_capabilities (
                 session_id TEXT NOT NULL REFERENCES agent_sessions(session_id) ON DELETE CASCADE,
                 capability TEXT NOT NULL,
                 PRIMARY KEY(session_id, capability)
             );
             CREATE TABLE IF NOT EXISTS agent_session_events (
                 session_id TEXT NOT NULL REFERENCES agent_sessions(session_id) ON DELETE CASCADE,
                 sequence INTEGER NOT NULL CHECK (sequence > 0),
                 kind TEXT NOT NULL,
                 PRIMARY KEY(session_id, sequence)
             );",
        )?;
        if version == 2 {
            transaction.execute(
                "ALTER TABLE workspace_documents ADD COLUMN encoding TEXT",
                [],
            )?;
        }
        if version < 5 {
            transaction.execute(
                "INSERT OR IGNORE INTO workspace_state(singleton, revision) VALUES (1, 0)",
                [],
            )?;
            transaction.execute_batch(
                "ALTER TABLE workspace_state RENAME TO workspace_state_v4;
                 CREATE TABLE workspace_state (
                     workspace_id TEXT PRIMARY KEY,
                     revision INTEGER NOT NULL CHECK (revision >= 0)
                 );
                 INSERT INTO workspace_state(workspace_id, revision)
                     SELECT 'default', revision FROM workspace_state_v4 WHERE singleton = 1;
                 DROP TABLE workspace_state_v4;
                 ALTER TABLE workspace_documents RENAME TO workspace_documents_v4;
                 CREATE TABLE workspace_documents (
                     workspace_id TEXT NOT NULL,
                     relative_path TEXT NOT NULL,
                     revision INTEGER NOT NULL CHECK (revision >= 0),
                     contents BLOB NOT NULL,
                     encoding TEXT,
                     PRIMARY KEY(workspace_id, relative_path),
                     FOREIGN KEY(workspace_id) REFERENCES workspace_state(workspace_id)
                         ON DELETE CASCADE
                 );
                 INSERT INTO workspace_documents(
                     workspace_id, relative_path, revision, contents, encoding
                 ) SELECT 'default', relative_path, revision, contents, encoding
                   FROM workspace_documents_v4;
                 DROP TABLE workspace_documents_v4;",
            )?;
        }
        transaction.execute_batch(
            "CREATE TABLE IF NOT EXISTS workspace_fs_transactions (
                 transaction_id TEXT PRIMARY KEY,
                 workspace_id TEXT NOT NULL,
                 expected_workspace_revision INTEGER NOT NULL CHECK (expected_workspace_revision >= 0),
                 recovery_payload BLOB NOT NULL,
                 FOREIGN KEY(workspace_id) REFERENCES workspace_state(workspace_id)
                     ON DELETE CASCADE
             );
             CREATE TABLE IF NOT EXISTS dirty_buffers (
                 workspace_id TEXT NOT NULL,
                 document_id TEXT NOT NULL,
                 revision INTEGER NOT NULL CHECK (revision >= 0),
                 contents TEXT NOT NULL,
                 PRIMARY KEY(workspace_id, document_id),
                 FOREIGN KEY(workspace_id) REFERENCES workspace_state(workspace_id)
                     ON DELETE CASCADE
             );",
        )?;
        transaction.pragma_update(None, "user_version", CURRENT_SCHEMA_VERSION)?;
        transaction.commit()?;
        Ok(())
    }

    pub fn verify_integrity(&self) -> Result<(), DurableStateError> {
        let result: String =
            self.connection
                .pragma_query_value(None, "integrity_check", |row| row.get(0))?;
        if result == "ok" {
            Ok(())
        } else {
            Err(DurableStateError::IntegrityCheckFailed)
        }
    }

    pub fn workspace_revision(&self, workspace_id: &str) -> Result<u64, DurableStateError> {
        self.ensure_workspace(workspace_id)?;
        let value: i64 = self.connection.query_row(
            "SELECT revision FROM workspace_state WHERE workspace_id = ?1",
            [workspace_id],
            |row| row.get(0),
        )?;
        u64::try_from(value).map_err(|_| DurableStateError::NumericOverflow)
    }

    pub fn set_workspace_revision(
        &mut self,
        workspace_id: &str,
        revision: u64,
    ) -> Result<(), DurableStateError> {
        self.ensure_workspace(workspace_id)?;
        let revision = i64::try_from(revision).map_err(|_| DurableStateError::NumericOverflow)?;
        let current: i64 = self.connection.query_row(
            "SELECT revision FROM workspace_state WHERE workspace_id = ?1",
            [workspace_id],
            |row| row.get(0),
        )?;
        if revision < current {
            return Err(DurableStateError::RevisionRegression {
                current: current as u64,
                proposed: revision as u64,
            });
        }
        self.connection.execute(
            "UPDATE workspace_state SET revision = ?1 WHERE workspace_id = ?2",
            params![revision, workspace_id],
        )?;
        Ok(())
    }

    pub fn prepare_workspace_fs_transaction(
        &mut self,
        transaction_id: &str,
        workspace_id: &str,
        expected_workspace_revision: u64,
        recovery_payload: &[u8],
    ) -> Result<(), DurableStateError> {
        if transaction_id.is_empty() || transaction_id.len() > 128 || recovery_payload.is_empty() {
            return Err(DurableStateError::InvalidFsTransaction);
        }
        if workspace_id.is_empty() || workspace_id.len() > 256 {
            return Err(DurableStateError::InvalidWorkspaceId);
        }
        let expected = i64::try_from(expected_workspace_revision)
            .map_err(|_| DurableStateError::NumericOverflow)?;
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        transaction.execute(
            "INSERT OR IGNORE INTO workspace_state(workspace_id, revision) VALUES (?1, 0)",
            [workspace_id],
        )?;
        let actual: i64 = transaction.query_row(
            "SELECT revision FROM workspace_state WHERE workspace_id = ?1",
            [workspace_id],
            |row| row.get(0),
        )?;
        if actual != expected {
            return Err(DurableStateError::WorkspaceConflict {
                expected: expected_workspace_revision,
                actual: actual as u64,
            });
        }
        transaction.execute(
            "INSERT INTO workspace_fs_transactions(
                 transaction_id, workspace_id, expected_workspace_revision, recovery_payload
             ) VALUES (?1, ?2, ?3, ?4)",
            params![transaction_id, workspace_id, expected, recovery_payload],
        )?;
        transaction.commit()?;
        Ok(())
    }

    pub fn pending_workspace_fs_transactions(
        &self,
        workspace_id: &str,
    ) -> Result<Vec<PendingWorkspaceFsTransaction>, DurableStateError> {
        let mut statement = self.connection.prepare(
            "SELECT transaction_id, expected_workspace_revision, recovery_payload
             FROM workspace_fs_transactions WHERE workspace_id = ?1
             ORDER BY transaction_id ASC",
        )?;
        let rows = statement.query_map([workspace_id], |row| {
            Ok(PendingWorkspaceFsTransaction {
                transaction_id: row.get(0)?,
                workspace_id: workspace_id.to_owned(),
                expected_workspace_revision: row.get::<_, i64>(1)? as u64,
                recovery_payload: row.get(2)?,
            })
        })?;
        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    pub fn discard_workspace_fs_transaction(
        &mut self,
        transaction_id: &str,
        workspace_id: &str,
    ) -> Result<(), DurableStateError> {
        let removed = self.connection.execute(
            "DELETE FROM workspace_fs_transactions
             WHERE transaction_id = ?1 AND workspace_id = ?2",
            params![transaction_id, workspace_id],
        )?;
        if removed != 1 {
            return Err(DurableStateError::MissingFsTransaction);
        }
        Ok(())
    }

    fn ensure_workspace(&self, workspace_id: &str) -> Result<(), DurableStateError> {
        if workspace_id.is_empty() || workspace_id.len() > 256 {
            return Err(DurableStateError::InvalidWorkspaceId);
        }
        self.connection.execute(
            "INSERT OR IGNORE INTO workspace_state(workspace_id, revision) VALUES (?1, 0)",
            [workspace_id],
        )?;
        Ok(())
    }

    pub fn read_document(
        &self,
        workspace_id: &str,
        relative_path: &str,
    ) -> Result<Option<DurableDocumentRecord>, DurableStateError> {
        self.ensure_workspace(workspace_id)?;
        self.connection
            .query_row(
                "SELECT relative_path, revision, contents, encoding
                 FROM workspace_documents
                 WHERE workspace_id = ?1 AND relative_path = ?2",
                params![workspace_id, relative_path],
                |row| {
                    Ok(DurableDocumentRecord {
                        relative_path: row.get(0)?,
                        revision: row.get::<_, i64>(1)? as u64,
                        contents: row.get(2)?,
                        encoding: row.get(3)?,
                    })
                },
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn import_document_if_missing(
        &self,
        workspace_id: &str,
        relative_path: &str,
        contents: &[u8],
        encoding: Option<&str>,
    ) -> Result<(), DurableStateError> {
        self.ensure_workspace(workspace_id)?;
        self.connection.execute(
            "INSERT OR IGNORE INTO workspace_documents(
                 workspace_id, relative_path, revision, contents, encoding
             ) VALUES (?1, ?2, 0, ?3, ?4)",
            params![workspace_id, relative_path, contents, encoding],
        )?;
        Ok(())
    }

    pub fn list_documents(
        &self,
        workspace_id: &str,
    ) -> Result<Vec<DurableDocumentRecord>, DurableStateError> {
        self.ensure_workspace(workspace_id)?;
        let mut statement = self.connection.prepare(
            "SELECT relative_path, revision, contents, encoding
             FROM workspace_documents WHERE workspace_id = ?1
             ORDER BY relative_path ASC",
        )?;
        let rows = statement.query_map([workspace_id], |row| {
            Ok(DurableDocumentRecord {
                relative_path: row.get(0)?,
                revision: row.get::<_, i64>(1)? as u64,
                contents: row.get(2)?,
                encoding: row.get(3)?,
            })
        })?;
        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    pub fn apply_buffer_delta(
        &mut self,
        workspace_id: &str,
        document_id: &str,
        base_revision: u64,
        target_revision: u64,
        start_offset: usize,
        deleted_length: usize,
        inserted_text: &str,
    ) -> Result<DurableDirtyBufferRecord, DurableStateError> {
        if workspace_id.is_empty()
            || workspace_id.len() > 256
            || document_id.is_empty()
            || document_id.len() > 4096
            || inserted_text.len() > 1024 * 1024
            || target_revision != base_revision.saturating_add(1)
        {
            return Err(DurableStateError::InvalidBufferDelta);
        }
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        transaction.execute(
            "INSERT OR IGNORE INTO workspace_state(workspace_id, revision) VALUES (?1, 0)",
            [workspace_id],
        )?;
        let workspace_revision: i64 = transaction.query_row(
            "SELECT revision FROM workspace_state WHERE workspace_id = ?1",
            [workspace_id],
            |row| row.get(0),
        )?;
        let existing: Option<(i64, String)> = transaction
            .query_row(
                "SELECT revision, contents FROM dirty_buffers
                 WHERE workspace_id = ?1 AND document_id = ?2",
                params![workspace_id, document_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()?;
        let (actual_revision, contents) = existing.unwrap_or((0, String::new()));
        if actual_revision as u64 != base_revision {
            return Err(DurableStateError::BufferConflict {
                document_id: document_id.to_owned(),
                expected: base_revision,
                actual: actual_revision as u64,
            });
        }
        let start_byte = utf16_offset_to_byte(&contents, start_offset)
            .ok_or(DurableStateError::InvalidBufferDelta)?;
        let end_offset = start_offset
            .checked_add(deleted_length)
            .ok_or(DurableStateError::InvalidBufferDelta)?;
        let end_byte = utf16_offset_to_byte(&contents, end_offset)
            .ok_or(DurableStateError::InvalidBufferDelta)?;
        let mut next =
            String::with_capacity(contents.len() - (end_byte - start_byte) + inserted_text.len());
        next.push_str(&contents[..start_byte]);
        next.push_str(inserted_text);
        next.push_str(&contents[end_byte..]);
        if next.len() > 8 * 1024 * 1024 {
            return Err(DurableStateError::InvalidBufferDelta);
        }
        let target_revision_i64 =
            i64::try_from(target_revision).map_err(|_| DurableStateError::NumericOverflow)?;
        transaction.execute(
            "INSERT INTO dirty_buffers(workspace_id, document_id, revision, contents)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(workspace_id, document_id) DO UPDATE SET
               revision = excluded.revision,
               contents = excluded.contents",
            params![workspace_id, document_id, target_revision_i64, &next],
        )?;
        let payload = format!("{document_id}\u{1f}{target_revision}");
        transaction.execute(
            "INSERT INTO event_journal(kind, workspace_revision, payload)
             VALUES ('buffer.delta.acknowledged', ?1, ?2)",
            params![workspace_revision, payload.as_bytes()],
        )?;
        let cursor = transaction.last_insert_rowid();
        let oldest_to_keep = cursor.saturating_sub(self.event_capacity as i64 - 1);
        transaction.execute(
            "DELETE FROM event_journal WHERE cursor < ?1",
            [oldest_to_keep],
        )?;
        transaction.commit()?;
        Ok(DurableDirtyBufferRecord {
            document_id: document_id.to_owned(),
            revision: target_revision,
            contents: next,
        })
    }

    pub fn list_dirty_buffers(
        &self,
        workspace_id: &str,
    ) -> Result<Vec<DurableDirtyBufferRecord>, DurableStateError> {
        self.ensure_workspace(workspace_id)?;
        let mut statement = self.connection.prepare(
            "SELECT document_id, revision, contents FROM dirty_buffers
             WHERE workspace_id = ?1 ORDER BY document_id ASC",
        )?;
        let rows = statement.query_map([workspace_id], |row| {
            Ok(DurableDirtyBufferRecord {
                document_id: row.get(0)?,
                revision: row.get::<_, i64>(1)? as u64,
                contents: row.get(2)?,
            })
        })?;
        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    pub fn commit_documents(
        &mut self,
        workspace_id: &str,
        expected_workspace_revision: u64,
        changes: &[DurableDocumentChange],
        event_payload: &[u8],
    ) -> Result<DurableCommitReceipt, DurableStateError> {
        self.commit_documents_internal(
            workspace_id,
            expected_workspace_revision,
            changes,
            event_payload,
            None,
            None,
        )
        .map(|(receipt, _)| receipt)
    }

    pub fn commit_documents_with_receipt(
        &mut self,
        workspace_id: &str,
        expected_workspace_revision: u64,
        changes: &[DurableDocumentChange],
        event_payload: &[u8],
        idempotency_key: &str,
        build_response: &dyn Fn(&DurableCommitReceipt) -> Result<Vec<u8>, DurableStateError>,
    ) -> Result<(DurableCommitReceipt, Vec<u8>), DurableStateError> {
        if idempotency_key.is_empty() {
            return Err(DurableStateError::InvalidIdempotencyKey);
        }
        self.commit_documents_internal(
            workspace_id,
            expected_workspace_revision,
            changes,
            event_payload,
            Some((idempotency_key, build_response)),
            None,
        )
        .map(|(receipt, response)| (receipt, response.expect("receipt builder provided")))
    }

    pub fn commit_documents_with_receipt_and_fs_transaction(
        &mut self,
        workspace_id: &str,
        expected_workspace_revision: u64,
        changes: &[DurableDocumentChange],
        event_payload: &[u8],
        binding: DurableFsTransactionBinding<'_>,
        build_response: &CommitResponseBuilder<'_>,
    ) -> Result<(DurableCommitReceipt, Vec<u8>), DurableStateError> {
        if binding.idempotency_key.is_empty() {
            return Err(DurableStateError::InvalidIdempotencyKey);
        }
        self.commit_documents_internal(
            workspace_id,
            expected_workspace_revision,
            changes,
            event_payload,
            Some((binding.idempotency_key, build_response)),
            Some(binding.transaction_id),
        )
        .map(|(receipt, response)| (receipt, response.expect("receipt builder provided")))
    }

    fn commit_documents_internal(
        &mut self,
        workspace_id: &str,
        expected_workspace_revision: u64,
        changes: &[DurableDocumentChange],
        event_payload: &[u8],
        receipt: Option<(&str, &CommitResponseBuilder<'_>)>,
        fs_transaction_id: Option<&str>,
    ) -> Result<(DurableCommitReceipt, Option<Vec<u8>>), DurableStateError> {
        if changes.is_empty() {
            return Err(DurableStateError::EmptyTransaction);
        }
        if workspace_id.is_empty() || workspace_id.len() > 256 {
            return Err(DurableStateError::InvalidWorkspaceId);
        }
        let expected_workspace_revision = i64::try_from(expected_workspace_revision)
            .map_err(|_| DurableStateError::NumericOverflow)?;
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        transaction.execute(
            "INSERT OR IGNORE INTO workspace_state(workspace_id, revision) VALUES (?1, 0)",
            [workspace_id],
        )?;
        let actual_workspace_revision: i64 = transaction.query_row(
            "SELECT revision FROM workspace_state WHERE workspace_id = ?1",
            [workspace_id],
            |row| row.get(0),
        )?;
        if actual_workspace_revision != expected_workspace_revision {
            return Err(DurableStateError::WorkspaceConflict {
                expected: expected_workspace_revision as u64,
                actual: actual_workspace_revision as u64,
            });
        }
        for change in changes {
            let actual: Option<i64> = transaction
                .query_row(
                    "SELECT revision FROM workspace_documents
                     WHERE workspace_id = ?1 AND relative_path = ?2",
                    params![workspace_id, &change.relative_path],
                    |row| row.get(0),
                )
                .optional()?;
            let actual = actual.unwrap_or(0) as u64;
            if actual != change.expected_document_revision {
                return Err(DurableStateError::DocumentConflict {
                    path: change.relative_path.clone(),
                    expected: change.expected_document_revision,
                    actual,
                });
            }
        }
        let next_workspace_revision = actual_workspace_revision
            .checked_add(1)
            .ok_or(DurableStateError::NumericOverflow)?;
        let mut document_revisions = HashMap::with_capacity(changes.len());
        for change in changes {
            let next_document_revision = change
                .expected_document_revision
                .checked_add(1)
                .ok_or(DurableStateError::NumericOverflow)?;
            let next_document_revision_i64 = i64::try_from(next_document_revision)
                .map_err(|_| DurableStateError::NumericOverflow)?;
            transaction.execute(
                "INSERT INTO workspace_documents(
                     workspace_id, relative_path, revision, contents, encoding
                 ) VALUES (?1, ?2, ?3, ?4, ?5)
                 ON CONFLICT(workspace_id, relative_path) DO UPDATE SET
                   revision = excluded.revision,
                   contents = excluded.contents,
                   encoding = excluded.encoding",
                params![
                    workspace_id,
                    change.relative_path,
                    next_document_revision_i64,
                    change.contents,
                    change.encoding,
                ],
            )?;
            document_revisions.insert(change.relative_path.clone(), next_document_revision);
        }
        transaction.execute(
            "UPDATE workspace_state SET revision = ?1 WHERE workspace_id = ?2",
            params![next_workspace_revision, workspace_id],
        )?;
        transaction.execute(
            "INSERT INTO event_journal(kind, workspace_revision, payload)
             VALUES ('workspace.transaction.committed', ?1, ?2)",
            params![next_workspace_revision, event_payload],
        )?;
        let event_cursor = transaction.last_insert_rowid();
        let oldest_to_keep = event_cursor.saturating_sub(self.event_capacity as i64 - 1);
        transaction.execute(
            "DELETE FROM event_journal WHERE cursor < ?1",
            [oldest_to_keep],
        )?;
        let commit_receipt = DurableCommitReceipt {
            workspace_revision: next_workspace_revision as u64,
            document_revisions,
            event_cursor: event_cursor as u64,
        };
        let encoded_response = if let Some((idempotency_key, build_response)) = receipt {
            let encoded = build_response(&commit_receipt)?;
            transaction.execute(
                "INSERT INTO idempotency_receipts(idempotency_key, committed_cursor, response)
                 VALUES (?1, ?2, ?3)",
                params![idempotency_key, event_cursor, encoded],
            )?;
            Some(encoded)
        } else {
            None
        };
        complete_fs_transaction(&transaction, workspace_id, fs_transaction_id)?;
        transaction.commit()?;
        Ok((commit_receipt, encoded_response))
    }

    pub fn delete_document(
        &mut self,
        workspace_id: &str,
        expected_workspace_revision: u64,
        relative_path: &str,
        expected_document_revision: u64,
    ) -> Result<Option<DurableCommitReceipt>, DurableStateError> {
        self.delete_document_internal(
            workspace_id,
            expected_workspace_revision,
            relative_path,
            expected_document_revision,
            None,
            None,
        )
        .map(|(receipt, _)| receipt)
    }

    pub fn delete_document_with_receipt(
        &mut self,
        workspace_id: &str,
        expected_workspace_revision: u64,
        relative_path: &str,
        expected_document_revision: u64,
        idempotency_key: &str,
        build_response: &DeleteResponseBuilder<'_>,
    ) -> Result<(Option<DurableCommitReceipt>, Vec<u8>), DurableStateError> {
        if idempotency_key.is_empty() {
            return Err(DurableStateError::InvalidIdempotencyKey);
        }
        self.delete_document_internal(
            workspace_id,
            expected_workspace_revision,
            relative_path,
            expected_document_revision,
            Some((idempotency_key, build_response)),
            None,
        )
        .map(|(receipt, response)| (receipt, response.expect("receipt builder provided")))
    }

    pub fn delete_document_with_receipt_and_fs_transaction(
        &mut self,
        workspace_id: &str,
        expected_workspace_revision: u64,
        relative_path: &str,
        expected_document_revision: u64,
        binding: DurableFsTransactionBinding<'_>,
        build_response: &DeleteResponseBuilder<'_>,
    ) -> Result<(Option<DurableCommitReceipt>, Vec<u8>), DurableStateError> {
        if binding.idempotency_key.is_empty() {
            return Err(DurableStateError::InvalidIdempotencyKey);
        }
        self.delete_document_internal(
            workspace_id,
            expected_workspace_revision,
            relative_path,
            expected_document_revision,
            Some((binding.idempotency_key, build_response)),
            Some(binding.transaction_id),
        )
        .map(|(receipt, response)| (receipt, response.expect("receipt builder provided")))
    }

    fn delete_document_internal(
        &mut self,
        workspace_id: &str,
        expected_workspace_revision: u64,
        relative_path: &str,
        expected_document_revision: u64,
        receipt: Option<(&str, &DeleteResponseBuilder<'_>)>,
        fs_transaction_id: Option<&str>,
    ) -> Result<(Option<DurableCommitReceipt>, Option<Vec<u8>>), DurableStateError> {
        if workspace_id.is_empty() || workspace_id.len() > 256 {
            return Err(DurableStateError::InvalidWorkspaceId);
        }
        let expected_workspace_revision = i64::try_from(expected_workspace_revision)
            .map_err(|_| DurableStateError::NumericOverflow)?;
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        transaction.execute(
            "INSERT OR IGNORE INTO workspace_state(workspace_id, revision) VALUES (?1, 0)",
            [workspace_id],
        )?;
        let actual_workspace_revision: i64 = transaction.query_row(
            "SELECT revision FROM workspace_state WHERE workspace_id = ?1",
            [workspace_id],
            |row| row.get(0),
        )?;
        if actual_workspace_revision != expected_workspace_revision {
            return Err(DurableStateError::WorkspaceConflict {
                expected: expected_workspace_revision as u64,
                actual: actual_workspace_revision as u64,
            });
        }
        let actual_document_revision: Option<i64> = transaction
            .query_row(
                "SELECT revision FROM workspace_documents
                 WHERE workspace_id = ?1 AND relative_path = ?2",
                params![workspace_id, relative_path],
                |row| row.get(0),
            )
            .optional()?;
        let Some(actual_document_revision) = actual_document_revision else {
            let encoded_response = if let Some((idempotency_key, build_response)) = receipt {
                let encoded = build_response(None, actual_workspace_revision as u64)?;
                transaction.execute(
                    "INSERT INTO idempotency_receipts(idempotency_key, committed_cursor, response)
                     VALUES (?1, NULL, ?2)",
                    params![idempotency_key, encoded],
                )?;
                Some(encoded)
            } else {
                None
            };
            complete_fs_transaction(&transaction, workspace_id, fs_transaction_id)?;
            transaction.commit()?;
            return Ok((None, encoded_response));
        };
        if actual_document_revision as u64 != expected_document_revision {
            return Err(DurableStateError::DocumentConflict {
                path: relative_path.to_owned(),
                expected: expected_document_revision,
                actual: actual_document_revision as u64,
            });
        }
        let next_workspace_revision = actual_workspace_revision
            .checked_add(1)
            .ok_or(DurableStateError::NumericOverflow)?;
        transaction.execute(
            "DELETE FROM workspace_documents
             WHERE workspace_id = ?1 AND relative_path = ?2",
            params![workspace_id, relative_path],
        )?;
        transaction.execute(
            "UPDATE workspace_state SET revision = ?1 WHERE workspace_id = ?2",
            params![next_workspace_revision, workspace_id],
        )?;
        transaction.execute(
            "INSERT INTO event_journal(kind, workspace_revision, payload)
             VALUES ('workspace.document.deleted', ?1, ?2)",
            params![next_workspace_revision, relative_path.as_bytes()],
        )?;
        let event_cursor = transaction.last_insert_rowid();
        let commit_receipt = DurableCommitReceipt {
            workspace_revision: next_workspace_revision as u64,
            document_revisions: HashMap::new(),
            event_cursor: event_cursor as u64,
        };
        let encoded_response = if let Some((idempotency_key, build_response)) = receipt {
            let encoded = build_response(Some(&commit_receipt), next_workspace_revision as u64)?;
            transaction.execute(
                "INSERT INTO idempotency_receipts(idempotency_key, committed_cursor, response)
                 VALUES (?1, ?2, ?3)",
                params![idempotency_key, event_cursor, encoded],
            )?;
            Some(encoded)
        } else {
            None
        };
        complete_fs_transaction(&transaction, workspace_id, fs_transaction_id)?;
        transaction.commit()?;
        Ok((Some(commit_receipt), encoded_response))
    }

    pub fn rename_document_with_receipt_and_fs_transaction(
        &mut self,
        workspace_id: &str,
        rename: DurableRenameDocument<'_>,
        binding: DurableFsTransactionBinding<'_>,
        build_response: &CommitResponseBuilder<'_>,
    ) -> Result<(DurableCommitReceipt, Vec<u8>), DurableStateError> {
        if binding.idempotency_key.is_empty()
            || rename.source_relative_path == rename.target_relative_path
        {
            return Err(DurableStateError::InvalidFsTransaction);
        }
        let expected_workspace_revision = i64::try_from(rename.expected_workspace_revision)
            .map_err(|_| DurableStateError::NumericOverflow)?;
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let actual_workspace_revision: i64 = transaction.query_row(
            "SELECT revision FROM workspace_state WHERE workspace_id = ?1",
            [workspace_id],
            |row| row.get(0),
        )?;
        if actual_workspace_revision != expected_workspace_revision {
            return Err(DurableStateError::WorkspaceConflict {
                expected: rename.expected_workspace_revision,
                actual: actual_workspace_revision as u64,
            });
        }
        let source: Option<(i64, Vec<u8>, Option<String>)> = transaction
            .query_row(
                "SELECT revision, contents, encoding FROM workspace_documents
                 WHERE workspace_id = ?1 AND relative_path = ?2",
                params![workspace_id, rename.source_relative_path],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .optional()?;
        let Some((actual_source_revision, contents, encoding)) = source else {
            return Err(DurableStateError::DocumentConflict {
                path: rename.source_relative_path.to_owned(),
                expected: rename.expected_source_revision,
                actual: 0,
            });
        };
        if actual_source_revision as u64 != rename.expected_source_revision {
            return Err(DurableStateError::DocumentConflict {
                path: rename.source_relative_path.to_owned(),
                expected: rename.expected_source_revision,
                actual: actual_source_revision as u64,
            });
        }
        let actual_target_revision: Option<i64> = transaction
            .query_row(
                "SELECT revision FROM workspace_documents
                 WHERE workspace_id = ?1 AND relative_path = ?2",
                params![workspace_id, rename.target_relative_path],
                |row| row.get(0),
            )
            .optional()?;
        if actual_target_revision.unwrap_or(0) as u64 != rename.expected_target_revision {
            return Err(DurableStateError::DocumentConflict {
                path: rename.target_relative_path.to_owned(),
                expected: rename.expected_target_revision,
                actual: actual_target_revision.unwrap_or(0) as u64,
            });
        }
        let next_workspace_revision = actual_workspace_revision
            .checked_add(1)
            .ok_or(DurableStateError::NumericOverflow)?;
        let next_target_revision = rename
            .expected_target_revision
            .checked_add(1)
            .ok_or(DurableStateError::NumericOverflow)?;
        transaction.execute(
            "DELETE FROM workspace_documents
             WHERE workspace_id = ?1 AND relative_path = ?2",
            params![workspace_id, rename.source_relative_path],
        )?;
        transaction.execute(
            "INSERT INTO workspace_documents(
                 workspace_id, relative_path, revision, contents, encoding
             ) VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(workspace_id, relative_path) DO UPDATE SET
               revision = excluded.revision,
               contents = excluded.contents,
               encoding = excluded.encoding",
            params![
                workspace_id,
                rename.target_relative_path,
                i64::try_from(next_target_revision)
                    .map_err(|_| DurableStateError::NumericOverflow)?,
                contents,
                encoding,
            ],
        )?;
        transaction.execute(
            "UPDATE workspace_state SET revision = ?1 WHERE workspace_id = ?2",
            params![next_workspace_revision, workspace_id],
        )?;
        transaction.execute(
            "INSERT INTO event_journal(kind, workspace_revision, payload)
             VALUES ('workspace.document.renamed', ?1, ?2)",
            params![
                next_workspace_revision,
                rename.target_relative_path.as_bytes()
            ],
        )?;
        let event_cursor = transaction.last_insert_rowid();
        let oldest_to_keep = event_cursor.saturating_sub(self.event_capacity as i64 - 1);
        transaction.execute(
            "DELETE FROM event_journal WHERE cursor < ?1",
            [oldest_to_keep],
        )?;
        let receipt = DurableCommitReceipt {
            workspace_revision: next_workspace_revision as u64,
            document_revisions: HashMap::from([(
                rename.target_relative_path.to_owned(),
                next_target_revision,
            )]),
            event_cursor: event_cursor as u64,
        };
        let encoded = build_response(&receipt)?;
        transaction.execute(
            "INSERT INTO idempotency_receipts(idempotency_key, committed_cursor, response)
             VALUES (?1, ?2, ?3)",
            params![binding.idempotency_key, event_cursor, encoded],
        )?;
        complete_fs_transaction(&transaction, workspace_id, Some(binding.transaction_id))?;
        transaction.commit()?;
        Ok((receipt, encoded))
    }

    pub fn append_event(
        &mut self,
        kind: &str,
        workspace_revision: u64,
        payload: &[u8],
    ) -> Result<EventRecord<Vec<u8>>, DurableStateError> {
        if kind.is_empty() {
            return Err(DurableStateError::InvalidEventKind);
        }
        let revision =
            i64::try_from(workspace_revision).map_err(|_| DurableStateError::NumericOverflow)?;
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        transaction.execute(
            "INSERT INTO event_journal(kind, workspace_revision, payload) VALUES (?1, ?2, ?3)",
            params![kind, revision, payload],
        )?;
        let cursor = transaction.last_insert_rowid();
        let oldest_to_keep = cursor.saturating_sub(self.event_capacity as i64 - 1);
        transaction.execute(
            "DELETE FROM event_journal WHERE cursor < ?1",
            [oldest_to_keep],
        )?;
        transaction.commit()?;
        Ok(EventRecord {
            cursor: u64::try_from(cursor).map_err(|_| DurableStateError::NumericOverflow)?,
            value: payload.to_vec(),
        })
    }

    pub fn resume_events_after(
        &self,
        cursor: u64,
    ) -> Result<Vec<DurableEventRecord>, DurableStateError> {
        let cursor_i64 = i64::try_from(cursor).map_err(|_| DurableStateError::NumericOverflow)?;
        let oldest: Option<i64> =
            self.connection
                .query_row("SELECT MIN(cursor) FROM event_journal", [], |row| {
                    row.get(0)
                })?;
        if let Some(oldest) = oldest
            && cursor_i64.saturating_add(1) < oldest
        {
            return Err(DurableStateError::ResumeGap(ResumeGap {
                requested_cursor: cursor,
                oldest_available_cursor: oldest as u64,
            }));
        }
        let mut statement = self.connection.prepare(
            "SELECT cursor, kind, workspace_revision, payload
             FROM event_journal WHERE cursor > ?1 ORDER BY cursor ASC",
        )?;
        let rows = statement.query_map([cursor_i64], |row| {
            Ok(DurableEventRecord {
                cursor: row.get::<_, i64>(0)? as u64,
                kind: row.get(1)?,
                workspace_revision: row.get::<_, i64>(2)? as u64,
                payload: row.get(3)?,
            })
        })?;
        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    pub fn latest_event_cursor(&self) -> Result<u64, DurableStateError> {
        let cursor: i64 = self.connection.query_row(
            "SELECT COALESCE(MAX(cursor), 0) FROM event_journal",
            [],
            |row| row.get(0),
        )?;
        u64::try_from(cursor).map_err(|_| DurableStateError::NumericOverflow)
    }

    pub fn upsert_agent_session(
        &mut self,
        session_id: &str,
        workspace_id: &str,
        workspace_revision: u64,
        capabilities: &[String],
    ) -> Result<(), DurableStateError> {
        if session_id.is_empty()
            || workspace_id.is_empty()
            || capabilities.is_empty()
            || capabilities
                .iter()
                .any(|value| value.is_empty() || value.len() > 1024)
        {
            return Err(DurableStateError::InvalidAgentSession);
        }
        let workspace_revision =
            i64::try_from(workspace_revision).map_err(|_| DurableStateError::NumericOverflow)?;
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        transaction.execute(
            "INSERT INTO agent_sessions(session_id, workspace_id, workspace_revision, revoked)
             VALUES (?1, ?2, ?3, 0)
             ON CONFLICT(session_id) DO UPDATE SET
               workspace_id = excluded.workspace_id,
               workspace_revision = excluded.workspace_revision,
               revoked = 0",
            params![session_id, workspace_id, workspace_revision],
        )?;
        transaction.execute(
            "DELETE FROM agent_session_capabilities WHERE session_id = ?1",
            [session_id],
        )?;
        for capability in capabilities {
            transaction.execute(
                "INSERT INTO agent_session_capabilities(session_id, capability)
                 VALUES (?1, ?2)",
                params![session_id, capability],
            )?;
        }
        transaction.commit()?;
        Ok(())
    }

    pub fn revoke_agent_session(&mut self, session_id: &str) -> Result<(), DurableStateError> {
        if session_id.is_empty() {
            return Err(DurableStateError::InvalidAgentSession);
        }
        self.connection.execute(
            "UPDATE agent_sessions SET revoked = 1 WHERE session_id = ?1",
            [session_id],
        )?;
        Ok(())
    }

    pub fn list_agent_sessions(&self) -> Result<Vec<DurableAgentSessionRecord>, DurableStateError> {
        let mut statement = self.connection.prepare(
            "SELECT session_id, workspace_id, workspace_revision, revoked
             FROM agent_sessions ORDER BY session_id ASC",
        )?;
        let sessions = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, bool>(3)?,
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        drop(statement);
        sessions
            .into_iter()
            .map(|(session_id, workspace_id, workspace_revision, revoked)| {
                let mut capabilities = self.connection.prepare(
                    "SELECT capability FROM agent_session_capabilities
                     WHERE session_id = ?1 ORDER BY capability ASC",
                )?;
                let capabilities = capabilities
                    .query_map([&session_id], |row| row.get(0))?
                    .collect::<Result<Vec<String>, _>>()?;
                Ok(DurableAgentSessionRecord {
                    session_id,
                    workspace_id,
                    workspace_revision: u64::try_from(workspace_revision)
                        .map_err(|_| DurableStateError::NumericOverflow)?,
                    capabilities,
                    revoked,
                })
            })
            .collect()
    }

    pub fn append_agent_session_event(
        &mut self,
        session_id: &str,
        kind: &str,
    ) -> Result<DurableAgentEventRecord, DurableStateError> {
        if session_id.is_empty() || kind.is_empty() || kind.len() > 4096 {
            return Err(DurableStateError::InvalidEventKind);
        }
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let exists: bool = transaction.query_row(
            "SELECT EXISTS(SELECT 1 FROM agent_sessions WHERE session_id = ?1)",
            [session_id],
            |row| row.get(0),
        )?;
        if !exists {
            return Err(DurableStateError::InvalidAgentSession);
        }
        let sequence: i64 = transaction.query_row(
            "SELECT COALESCE(MAX(sequence), 0) + 1
             FROM agent_session_events WHERE session_id = ?1",
            [session_id],
            |row| row.get(0),
        )?;
        transaction.execute(
            "INSERT INTO agent_session_events(session_id, sequence, kind)
             VALUES (?1, ?2, ?3)",
            params![session_id, sequence, kind],
        )?;
        let oldest_to_keep = sequence.saturating_sub(self.event_capacity as i64 - 1);
        transaction.execute(
            "DELETE FROM agent_session_events
             WHERE session_id = ?1 AND sequence < ?2",
            params![session_id, oldest_to_keep],
        )?;
        transaction.commit()?;
        Ok(DurableAgentEventRecord {
            sequence: sequence as u64,
            kind: kind.to_owned(),
        })
    }

    pub fn resume_agent_session_events(
        &self,
        session_id: &str,
        after_sequence: u64,
    ) -> Result<Vec<DurableAgentEventRecord>, DurableStateError> {
        let after_sequence =
            i64::try_from(after_sequence).map_err(|_| DurableStateError::NumericOverflow)?;
        let oldest: Option<i64> = self.connection.query_row(
            "SELECT MIN(sequence) FROM agent_session_events WHERE session_id = ?1",
            [session_id],
            |row| row.get(0),
        )?;
        if let Some(oldest) = oldest
            && after_sequence.saturating_add(1) < oldest
        {
            return Err(DurableStateError::ResumeGap(ResumeGap {
                requested_cursor: after_sequence as u64,
                oldest_available_cursor: oldest as u64,
            }));
        }
        let mut statement = self.connection.prepare(
            "SELECT sequence, kind FROM agent_session_events
             WHERE session_id = ?1 AND sequence > ?2 ORDER BY sequence ASC",
        )?;
        let rows = statement.query_map(params![session_id, after_sequence], |row| {
            Ok(DurableAgentEventRecord {
                sequence: row.get::<_, i64>(0)? as u64,
                kind: row.get(1)?,
            })
        })?;
        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    pub fn record_receipt_once(
        &mut self,
        key: &str,
        committed_cursor: Option<u64>,
        response: &[u8],
    ) -> Result<Vec<u8>, DurableStateError> {
        if key.is_empty() {
            return Err(DurableStateError::InvalidIdempotencyKey);
        }
        let existing: Option<Vec<u8>> = self
            .connection
            .query_row(
                "SELECT response FROM idempotency_receipts WHERE idempotency_key = ?1",
                [key],
                |row| row.get(0),
            )
            .optional()?;
        if let Some(existing) = existing {
            return Ok(existing);
        }
        let committed_cursor = committed_cursor
            .map(i64::try_from)
            .transpose()
            .map_err(|_| DurableStateError::NumericOverflow)?;
        self.connection.execute(
            "INSERT INTO idempotency_receipts(idempotency_key, committed_cursor, response)
             VALUES (?1, ?2, ?3)",
            params![key, committed_cursor, response],
        )?;
        Ok(response.to_vec())
    }

    pub fn receipt(&self, key: &str) -> Result<Option<Vec<u8>>, DurableStateError> {
        if key.is_empty() {
            return Err(DurableStateError::InvalidIdempotencyKey);
        }
        self.connection
            .query_row(
                "SELECT response FROM idempotency_receipts WHERE idempotency_key = ?1",
                [key],
                |row| row.get(0),
            )
            .optional()
            .map_err(Into::into)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DurableEventRecord {
    pub cursor: u64,
    pub kind: String,
    pub workspace_revision: u64,
    pub payload: Vec<u8>,
}

fn complete_fs_transaction(
    transaction: &rusqlite::Transaction<'_>,
    workspace_id: &str,
    transaction_id: Option<&str>,
) -> Result<(), DurableStateError> {
    let Some(transaction_id) = transaction_id else {
        return Ok(());
    };
    let removed = transaction.execute(
        "DELETE FROM workspace_fs_transactions
         WHERE transaction_id = ?1 AND workspace_id = ?2",
        params![transaction_id, workspace_id],
    )?;
    if removed != 1 {
        return Err(DurableStateError::MissingFsTransaction);
    }
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DurableDocumentRecord {
    pub relative_path: String,
    pub revision: u64,
    pub contents: Vec<u8>,
    pub encoding: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DurableDirtyBufferRecord {
    pub document_id: String,
    pub revision: u64,
    pub contents: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DurableDocumentChange {
    pub relative_path: String,
    pub expected_document_revision: u64,
    pub contents: Vec<u8>,
    pub encoding: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DurableCommitReceipt {
    pub workspace_revision: u64,
    pub document_revisions: HashMap<String, u64>,
    pub event_cursor: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PendingWorkspaceFsTransaction {
    pub transaction_id: String,
    pub workspace_id: String,
    pub expected_workspace_revision: u64,
    pub recovery_payload: Vec<u8>,
}

#[derive(Debug, Clone, Copy)]
pub struct DurableFsTransactionBinding<'a> {
    pub idempotency_key: &'a str,
    pub transaction_id: &'a str,
}

#[derive(Debug, Clone, Copy)]
pub struct DurableRenameDocument<'a> {
    pub expected_workspace_revision: u64,
    pub source_relative_path: &'a str,
    pub expected_source_revision: u64,
    pub target_relative_path: &'a str,
    pub expected_target_revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DurableAgentSessionRecord {
    pub session_id: String,
    pub workspace_id: String,
    pub workspace_revision: u64,
    pub capabilities: Vec<String>,
    pub revoked: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DurableAgentEventRecord {
    pub sequence: u64,
    pub kind: String,
}

fn utf16_offset_to_byte(value: &str, offset: usize) -> Option<usize> {
    if offset == 0 {
        return Some(0);
    }
    let mut utf16_offset = 0;
    for (byte_offset, character) in value.char_indices() {
        if utf16_offset == offset {
            return Some(byte_offset);
        }
        utf16_offset += character.len_utf16();
        if utf16_offset > offset {
            return None;
        }
    }
    (utf16_offset == offset).then_some(value.len())
}

#[derive(Debug)]
pub enum DurableStateError {
    Sqlite(rusqlite::Error),
    InvalidEventCapacity,
    InvalidEventKind,
    InvalidIdempotencyKey,
    InvalidWorkspaceId,
    InvalidFsTransaction,
    MissingFsTransaction,
    InvalidAgentSession,
    InvalidBufferDelta,
    EmptyTransaction,
    IntegrityCheckFailed,
    NumericOverflow,
    ResumeGap(ResumeGap),
    RevisionRegression {
        current: u64,
        proposed: u64,
    },
    WorkspaceConflict {
        expected: u64,
        actual: u64,
    },
    DocumentConflict {
        path: String,
        expected: u64,
        actual: u64,
    },
    BufferConflict {
        document_id: String,
        expected: u64,
        actual: u64,
    },
    UnsupportedSchemaVersion {
        found: i64,
        supported: i64,
    },
}

impl From<rusqlite::Error> for DurableStateError {
    fn from(value: rusqlite::Error) -> Self {
        Self::Sqlite(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounded_journal_reports_pruned_cursor_gap() {
        let mut journal = BoundedEventJournal::new(2);
        journal.push("one");
        journal.push("two");
        journal.push("three");
        assert_eq!(journal.resume_after(1).unwrap().len(), 2);
        assert_eq!(
            journal.resume_after(0).unwrap_err().oldest_available_cursor,
            2
        );
    }

    #[test]
    fn idempotency_store_returns_original_receipt() {
        let mut store = IdempotencyStore::default();
        assert_eq!(store.insert_once("same".into(), 1), 1);
        assert_eq!(store.insert_once("same".into(), 2), 1);
    }

    #[test]
    fn dirty_buffer_deltas_are_utf16_revisioned_and_durable() {
        let mut store = DurableStateStore::open_in_memory(8).unwrap();
        let first = store
            .apply_buffer_delta("workspace", "main", 0, 1, 0, 0, "a😀b")
            .unwrap();
        assert_eq!(first.contents, "a😀b");
        let second = store
            .apply_buffer_delta("workspace", "main", 1, 2, 1, 2, "z")
            .unwrap();
        assert_eq!(second.contents, "azb");
        assert!(matches!(
            store.apply_buffer_delta("workspace", "main", 1, 2, 0, 0, "stale"),
            Err(DurableStateError::BufferConflict { .. })
        ));
        assert_eq!(
            store.list_dirty_buffers("workspace").unwrap(),
            vec![DurableDirtyBufferRecord {
                document_id: "main".into(),
                revision: 2,
                contents: "azb".into(),
            }]
        );
        let events = store.resume_events_after(0).unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(events.last().unwrap().kind, "buffer.delta.acknowledged");
        assert!(
            !events
                .last()
                .unwrap()
                .payload
                .windows(3)
                .any(|value| value == b"azb")
        );
    }

    #[test]
    fn durable_store_reopens_with_revision_events_and_original_receipt() {
        let path = std::env::temp_dir().join(format!(
            "vityod-kernel-{}-{}.sqlite3",
            std::process::id(),
            std::thread::current().name().unwrap_or("test")
        ));
        let _ = std::fs::remove_file(&path);
        {
            let mut store = DurableStateStore::open(&path, 4).unwrap();
            store.set_workspace_revision("default", 7).unwrap();
            let event = store
                .append_event("workspace.changed", 7, b"event")
                .unwrap();
            assert_eq!(event.cursor, 1);
            assert_eq!(
                store
                    .record_receipt_once("effect-1", Some(event.cursor), b"first")
                    .unwrap(),
                b"first"
            );
        }
        {
            let mut reopened = DurableStateStore::open(&path, 4).unwrap();
            assert_eq!(reopened.workspace_revision("default").unwrap(), 7);
            assert_eq!(
                reopened.resume_events_after(0).unwrap()[0].payload,
                b"event"
            );
            assert_eq!(
                reopened
                    .record_receipt_once("effect-1", Some(1), b"duplicate")
                    .unwrap(),
                b"first"
            );
            assert_eq!(
                reopened.receipt("effect-1").unwrap(),
                Some(b"first".to_vec())
            );
            reopened.verify_integrity().unwrap();
        }
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(path.with_extension("sqlite3-shm"));
        let _ = std::fs::remove_file(path.with_extension("sqlite3-wal"));
    }

    #[test]
    fn version_four_workspace_state_migrates_without_content_loss() {
        let path = std::env::temp_dir().join(format!(
            "vityod-kernel-migration-{}.sqlite3",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        {
            let connection = Connection::open(&path).unwrap();
            connection
                .execute_batch(
                    "CREATE TABLE workspace_state (
                         singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                         revision INTEGER NOT NULL CHECK (revision >= 0)
                     );
                     INSERT INTO workspace_state(singleton, revision) VALUES (1, 3);
                     CREATE TABLE workspace_documents (
                         relative_path TEXT PRIMARY KEY,
                         revision INTEGER NOT NULL CHECK (revision >= 0),
                         contents BLOB NOT NULL,
                         encoding TEXT
                     );
                     INSERT INTO workspace_documents(relative_path, revision, contents, encoding)
                         VALUES ('src/main.styio', 2, X'707265736572766564', 'utf-8');
                     PRAGMA user_version = 4;",
                )
                .unwrap();
        }
        let store = DurableStateStore::open(&path, 8).unwrap();
        assert_eq!(store.workspace_revision("default").unwrap(), 3);
        assert_eq!(
            store
                .read_document("default", "src/main.styio")
                .unwrap()
                .unwrap()
                .contents,
            b"preserved"
        );
        drop(store);
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(path.with_extension("sqlite3-shm"));
        let _ = std::fs::remove_file(path.with_extension("sqlite3-wal"));
    }

    #[test]
    fn version_five_adds_recovery_journal_without_changing_workspace_state() {
        let path = std::env::temp_dir().join(format!(
            "vityod-kernel-v5-migration-{}.sqlite3",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        {
            let connection = Connection::open(&path).unwrap();
            connection
                .execute_batch(
                    "CREATE TABLE workspace_state (
                         workspace_id TEXT PRIMARY KEY,
                         revision INTEGER NOT NULL CHECK (revision >= 0)
                     );
                     INSERT INTO workspace_state(workspace_id, revision)
                         VALUES ('workspace', 9);
                     CREATE TABLE workspace_documents (
                         workspace_id TEXT NOT NULL,
                         relative_path TEXT NOT NULL,
                         revision INTEGER NOT NULL CHECK (revision >= 0),
                         contents BLOB NOT NULL,
                         encoding TEXT,
                         PRIMARY KEY(workspace_id, relative_path),
                         FOREIGN KEY(workspace_id) REFERENCES workspace_state(workspace_id)
                             ON DELETE CASCADE
                     );
                     PRAGMA user_version = 5;",
                )
                .unwrap();
        }
        let mut store = DurableStateStore::open(&path, 8).unwrap();
        assert_eq!(store.workspace_revision("workspace").unwrap(), 9);
        store
            .prepare_workspace_fs_transaction("v5-tx", "workspace", 9, b"recovery")
            .unwrap();
        assert_eq!(
            store
                .pending_workspace_fs_transactions("workspace")
                .unwrap()[0]
                .transaction_id,
            "v5-tx"
        );
        drop(store);
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(path.with_extension("sqlite3-shm"));
        let _ = std::fs::remove_file(path.with_extension("sqlite3-wal"));
    }

    #[test]
    fn version_six_adds_dirty_buffers_without_losing_recovery_journal() {
        let path = std::env::temp_dir().join(format!(
            "vityod-kernel-v6-migration-{}.sqlite3",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        {
            let connection = Connection::open(&path).unwrap();
            connection
                .execute_batch(
                    "CREATE TABLE workspace_state (
                         workspace_id TEXT PRIMARY KEY,
                         revision INTEGER NOT NULL CHECK (revision >= 0)
                     );
                     INSERT INTO workspace_state(workspace_id, revision)
                         VALUES ('workspace', 9);
                     CREATE TABLE workspace_fs_transactions (
                         transaction_id TEXT PRIMARY KEY,
                         workspace_id TEXT NOT NULL,
                         expected_workspace_revision INTEGER NOT NULL CHECK (expected_workspace_revision >= 0),
                         recovery_payload BLOB NOT NULL,
                         FOREIGN KEY(workspace_id) REFERENCES workspace_state(workspace_id)
                             ON DELETE CASCADE
                     );
                     INSERT INTO workspace_fs_transactions(
                         transaction_id, workspace_id, expected_workspace_revision, recovery_payload
                     ) VALUES ('pending', 'workspace', 9, X'7265636F76657279');
                     PRAGMA user_version = 6;",
                )
                .unwrap();
        }
        let mut store = DurableStateStore::open(&path, 8).unwrap();
        assert_eq!(store.workspace_revision("workspace").unwrap(), 9);
        assert_eq!(
            store
                .pending_workspace_fs_transactions("workspace")
                .unwrap()[0]
                .transaction_id,
            "pending"
        );
        store
            .apply_buffer_delta("workspace", "main", 0, 1, 0, 0, "preserved")
            .unwrap();
        assert_eq!(
            store.list_dirty_buffers("workspace").unwrap()[0].contents,
            "preserved"
        );
        drop(store);
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(path.with_extension("sqlite3-shm"));
        let _ = std::fs::remove_file(path.with_extension("sqlite3-wal"));
    }

    #[test]
    fn durable_store_bounds_events_and_reports_pruned_cursor() {
        let mut store = DurableStateStore::open_in_memory(2).unwrap();
        store.append_event("one", 0, b"1").unwrap();
        store.append_event("two", 0, b"2").unwrap();
        store.append_event("three", 0, b"3").unwrap();
        assert!(matches!(
            store.resume_events_after(0),
            Err(DurableStateError::ResumeGap(ResumeGap {
                oldest_available_cursor: 2,
                ..
            }))
        ));
        assert_eq!(store.resume_events_after(1).unwrap().len(), 2);
    }

    #[test]
    fn durable_store_refuses_revision_regression() {
        let mut store = DurableStateStore::open_in_memory(2).unwrap();
        store.set_workspace_revision("default", 2).unwrap();
        assert!(matches!(
            store.set_workspace_revision("default", 1),
            Err(DurableStateError::RevisionRegression {
                current: 2,
                proposed: 1
            })
        ));
    }

    #[test]
    fn durable_workspace_transaction_is_atomic_and_reopenable() {
        let mut store = DurableStateStore::open_in_memory(4).unwrap();
        let receipt = store
            .commit_documents(
                "default",
                0,
                &[DurableDocumentChange {
                    relative_path: "lib/main.styio".into(),
                    expected_document_revision: 0,
                    contents: b"first".to_vec(),
                    encoding: Some("utf-8-bom".into()),
                }],
                b"committed",
            )
            .unwrap();
        assert_eq!(receipt.workspace_revision, 1);
        assert_eq!(receipt.document_revisions["lib/main.styio"], 1);
        assert_eq!(
            store
                .read_document("default", "lib/main.styio")
                .unwrap()
                .unwrap()
                .contents,
            b"first"
        );
        assert_eq!(
            store
                .read_document("default", "lib/main.styio")
                .unwrap()
                .unwrap()
                .encoding
                .as_deref(),
            Some("utf-8-bom")
        );
        assert!(matches!(
            store.commit_documents(
                "default",
                0,
                &[DurableDocumentChange {
                    relative_path: "lib/main.styio".into(),
                    expected_document_revision: 1,
                    contents: b"stale".to_vec(),
                    encoding: None,
                }],
                b"stale",
            ),
            Err(DurableStateError::WorkspaceConflict { .. })
        ));
        assert_eq!(
            store
                .read_document("default", "lib/main.styio")
                .unwrap()
                .unwrap()
                .contents,
            b"first"
        );
    }

    #[test]
    fn durable_documents_and_revisions_are_workspace_scoped() {
        let mut store = DurableStateStore::open_in_memory(8).unwrap();
        for (workspace_id, contents) in [
            ("workspace-a", b"alpha".as_slice()),
            ("workspace-b", b"beta".as_slice()),
        ] {
            store
                .commit_documents(
                    workspace_id,
                    0,
                    &[DurableDocumentChange {
                        relative_path: "src/main.styio".into(),
                        expected_document_revision: 0,
                        contents: contents.to_vec(),
                        encoding: Some("utf-8".into()),
                    }],
                    b"commit",
                )
                .unwrap();
        }

        assert_eq!(store.workspace_revision("workspace-a").unwrap(), 1);
        assert_eq!(store.workspace_revision("workspace-b").unwrap(), 1);
        assert_eq!(
            store
                .read_document("workspace-a", "src/main.styio")
                .unwrap()
                .unwrap()
                .contents,
            b"alpha"
        );
        assert_eq!(
            store
                .read_document("workspace-b", "src/main.styio")
                .unwrap()
                .unwrap()
                .contents,
            b"beta"
        );
    }

    #[test]
    fn filesystem_journal_is_cleared_in_the_same_commit_as_documents() {
        let mut store = DurableStateStore::open_in_memory(8).unwrap();
        store
            .prepare_workspace_fs_transaction("tx-write", "workspace", 0, b"recovery")
            .unwrap();
        let (receipt, response) = store
            .commit_documents_with_receipt_and_fs_transaction(
                "workspace",
                0,
                &[DurableDocumentChange {
                    relative_path: "src/main.styio".into(),
                    expected_document_revision: 0,
                    contents: b"committed".to_vec(),
                    encoding: Some("utf-8".into()),
                }],
                b"commit",
                DurableFsTransactionBinding {
                    idempotency_key: "receipt-write",
                    transaction_id: "tx-write",
                },
                &|receipt| Ok(receipt.workspace_revision.to_string().into_bytes()),
            )
            .unwrap();
        assert_eq!(receipt.workspace_revision, 1);
        assert_eq!(response, b"1");
        assert!(
            store
                .pending_workspace_fs_transactions("workspace")
                .unwrap()
                .is_empty()
        );
        assert_eq!(
            store
                .read_document("workspace", "src/main.styio")
                .unwrap()
                .unwrap()
                .contents,
            b"committed"
        );
    }

    #[test]
    fn failed_durable_commit_leaves_filesystem_journal_for_recovery() {
        let mut store = DurableStateStore::open_in_memory(8).unwrap();
        store
            .prepare_workspace_fs_transaction("tx-conflict", "workspace", 0, b"rollback")
            .unwrap();
        store.set_workspace_revision("workspace", 1).unwrap();
        assert!(matches!(
            store.commit_documents_with_receipt_and_fs_transaction(
                "workspace",
                0,
                &[DurableDocumentChange {
                    relative_path: "main.styio".into(),
                    expected_document_revision: 0,
                    contents: b"no".to_vec(),
                    encoding: None,
                }],
                b"conflict",
                DurableFsTransactionBinding {
                    idempotency_key: "receipt-conflict",
                    transaction_id: "tx-conflict",
                },
                &|_| Ok(b"no".to_vec()),
            ),
            Err(DurableStateError::WorkspaceConflict { .. })
        ));
        assert_eq!(
            store
                .pending_workspace_fs_transactions("workspace")
                .unwrap()[0]
                .recovery_payload,
            b"rollback"
        );
    }

    #[test]
    fn rename_commits_source_target_revision_and_journal_atomically() {
        let mut store = DurableStateStore::open_in_memory(8).unwrap();
        store
            .import_document_if_missing("workspace", "old.styio", b"source", Some("utf-8"))
            .unwrap();
        store
            .prepare_workspace_fs_transaction("tx-rename", "workspace", 0, b"rename")
            .unwrap();
        let (receipt, _) = store
            .rename_document_with_receipt_and_fs_transaction(
                "workspace",
                DurableRenameDocument {
                    expected_workspace_revision: 0,
                    source_relative_path: "old.styio",
                    expected_source_revision: 0,
                    target_relative_path: "new.styio",
                    expected_target_revision: 0,
                },
                DurableFsTransactionBinding {
                    idempotency_key: "receipt-rename",
                    transaction_id: "tx-rename",
                },
                &|_| Ok(b"renamed".to_vec()),
            )
            .unwrap();
        assert_eq!(receipt.workspace_revision, 1);
        assert!(
            store
                .read_document("workspace", "old.styio")
                .unwrap()
                .is_none()
        );
        assert_eq!(
            store
                .read_document("workspace", "new.styio")
                .unwrap()
                .unwrap()
                .contents,
            b"source"
        );
        assert!(
            store
                .pending_workspace_fs_transactions("workspace")
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn delete_commits_revision_and_clears_filesystem_journal_atomically() {
        let mut store = DurableStateStore::open_in_memory(8).unwrap();
        store
            .import_document_if_missing("workspace", "remove.styio", b"remove", Some("utf-8"))
            .unwrap();
        store
            .prepare_workspace_fs_transaction("tx-delete", "workspace", 0, b"delete")
            .unwrap();
        let (receipt, _) = store
            .delete_document_with_receipt_and_fs_transaction(
                "workspace",
                0,
                "remove.styio",
                0,
                DurableFsTransactionBinding {
                    idempotency_key: "receipt-delete",
                    transaction_id: "tx-delete",
                },
                &|_, revision| Ok(revision.to_string().into_bytes()),
            )
            .unwrap();
        assert_eq!(receipt.unwrap().workspace_revision, 1);
        assert!(
            store
                .read_document("workspace", "remove.styio")
                .unwrap()
                .is_none()
        );
        assert!(
            store
                .pending_workspace_fs_transactions("workspace")
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn durable_agent_projection_resumes_and_revokes() {
        let mut store = DurableStateStore::open_in_memory(2).unwrap();
        store
            .upsert_agent_session(
                "agent-session",
                "workspace",
                3,
                &["workspace.read".into(), "workspace.proposeEdit".into()],
            )
            .unwrap();
        store
            .append_agent_session_event("agent-session", "started")
            .unwrap();
        store
            .append_agent_session_event("agent-session", "permission.requested")
            .unwrap();
        store
            .append_agent_session_event("agent-session", "permission.denied")
            .unwrap();
        assert!(matches!(
            store.resume_agent_session_events("agent-session", 0),
            Err(DurableStateError::ResumeGap(_))
        ));
        assert_eq!(
            store
                .resume_agent_session_events("agent-session", 1)
                .unwrap()
                .len(),
            2
        );
        store.revoke_agent_session("agent-session").unwrap();
        let session = store.list_agent_sessions().unwrap().remove(0);
        assert!(session.revoked);
        assert_eq!(session.workspace_revision, 3);
        assert_eq!(session.capabilities.len(), 2);
    }
}
