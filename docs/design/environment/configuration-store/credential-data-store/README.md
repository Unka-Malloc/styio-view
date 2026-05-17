# Credential DataStore

**Purpose:** Document the `docs/design/environment/configuration-store/credential-data-store/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`Credential DataStore` belongs to Configuration. It is the storage boundary for tokens, registry credentials, remote-service credentials, and other secret values that must not be mixed into ordinary configuration files.

## 1. Position

```text
Configuration / Credential DataStore
  -> stores secret values behind a credential key

Configuration / ordinary settings
  -> stores CredentialReference only
  -> never stores raw secret values
```

## 2. Responsibility

| Responsibility | Meaning |
|---|---|
| Secret value ownership | Own token and credential values. |
| Credential reference | Provide stable keys that ordinary settings can reference. |
| Redacted metadata | Expose display-safe metadata without leaking secret values. |
| Backend replacement | Allow future OS keychain, encrypted store, remote vault, or hosted secret backend. |
| Scope separation | Separate user, workspace, toolchain, and service credentials. |

## 3. Non-Responsibilities

| Not Owned Here | Owner |
|---|---|
| Network authentication flow | Network or service connector. |
| Registry protocol | Toolchain or package manager. |
| Plain product settings | Configuration store. |
| UI for credential editing | Interaction / Appearance. |
| OS keychain compatibility | Future Platform Manager credential backend, if direct OS integration is needed. |

## 4. Data Rule

Ordinary configuration may store this:

```text
CredentialReference
  key
  kind
  displayName
```

The Configuration Store must round-trip `CredentialReference` values exactly. A setting may persist credential references beside ordinary non-secret values, and loading that setting must restore the reference key, kind, scope, target id, and display name so callers can resolve the real secret through `CredentialDataStore`.

Ordinary configuration must not store this:

```text
secretValue
rawToken
password
privateKey
```

## 5. Runtime Contract

```text
CredentialDataStore
  write(record)
  read(key)
  delete(key)
  list(scope)
  snapshot()
```

`snapshot()` must return redacted metadata only. It must be safe to show in logs, settings pages, and diagnostics panels.

## 6. Current Implementation

Current implementations:

```text
InMemoryCredentialDataStore
FoundationCredentialDataStore
```

`InMemoryCredentialDataStore` is for runtime wiring and tests.

`FoundationCredentialDataStore` persists credential records through Foundation DataStore as a dedicated credential state family. It is not ordinary Configuration Store data, and ordinary settings still store only `CredentialReference`.

Current persistence path:

```text
FoundationCredentialDataStore
  -> FoundationDataStoreOwner
    -> namespace: configuration.credentials
    -> FoundationDataStore
```

The owner boundary prevents credential persistence from writing arbitrary Foundation DataStore namespaces. This keeps credential records inside Configuration ownership while still reusing Foundation persistence mechanics.

Credential writes and deletes use Foundation's transaction-backed `editJson`
path so multiple credential updates do not reimplement load-modify-save behavior
outside the DataStore owner boundary. The explicit `keep` decision prevents
missing-credential deletes from rewriting persisted state. Snapshots expose
`CredentialMetadata` only and must never include `secretValue`.

This backend is a local Vityo credential backend, not a system keychain. Future OS keychain, encrypted store, remote vault, or hosted secret backend can replace it behind the same `CredentialDataStore` contract.

Do not implement credential persistence as a normal plaintext configuration setting.
