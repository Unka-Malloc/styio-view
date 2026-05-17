# User Service

**Purpose:** Document the `docs/design/service/user-service/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

User Service is an optional Service Layer service. Vityo must remain usable without login, cloud profile sync, or any remote identity provider.

## 1. Position

```text
App Shell Surface
        |
        v
Interaction Layer
        |
        v
Service Layer
        |
        +--> User Service (optional)
        |
        +--> Styio Service Adapter
        |
        +--> Remote Service Adapters
        v
Environment Layer
```

The former top-level User Layer is not a required runtime layer. User-facing UI remains in the app shell surface, while identity, profile, and sync behavior are handled as an optional service.

## 2. Core Rule

Vityo must support two modes:

| Mode | Login Required | Expected Behavior |
|---|---:|---|
| Local-only mode | No | Editor, workspace, syntax service, file management, shell/execution, settings, and local profile state remain available. |
| Signed-in mode | Optional | Adds remote profile sync, account identity, device continuity, and cloud-backed preferences if configured. |

Login must never become a prerequisite for the basic IDE loop.

## 3. Responsibilities

| Component | Responsibility |
|---|---|
| Local Profile Store | Keeps local user preferences, recent workspace metadata, UI state, and non-sensitive local identity labels. |
| Optional Login Adapter | Connects to an identity provider only when the user enables sign-in. |
| Profile Sync Adapter | Synchronizes supported profile/configuration data when a remote account is active. |
| Session State Reporter | Reports signed-in, signed-out, degraded, or unavailable states to UI surfaces. |
| Privacy Boundary Writer | Defines which data may leave the local machine and which data is local-only. |
| User Service DataStore Owner | Owns persistence keys and migration policy for user-service data. |

## 4. Non-Responsibilities

| Capability | Owner |
|---|---|
| Editor UI, panels, popups, and onboarding screens | App Shell Surface and Appearance Layer |
| Command routing and editor interactions | Interaction Layer |
| Styio syntax, semantic facts, and language features | Styio Service Adapter and StyioService |
| Toolchain installation and discovery | Toolchain |
| Environment variables and app configuration files | Configuration |
| File persistence primitives | File System Manager and DataStore API |

## 5. Dependency Direction

```text
User Service
        |
        +--> DataStore API
        |
        +--> Configuration readers
        |
        +--> Remote identity/sync provider when enabled
        |
        v
App Shell Surface consumes only service status and user-visible commands.
```

The module may depend on DataStore and Configuration. DataStore must not depend on the User Service.

## 6. Fallback Policy

| Failure | Required Behavior |
|---|---|
| Login provider unavailable | Continue in local-only mode and report optional-service degradation. |
| Profile sync failed | Keep local profile active and expose retry/recovery state. |
| Remote account signed out | Preserve local workspace and editor state. |
| Privacy contract missing | Disable remote sync and continue locally. |

## 7. Current Implementation Target

Target implementation path:

```text
frontend/vityo_app/lib/src/view_ide/service/user_service/
  local_profile/
  optional_login/
  profile_sync_adapter/
  session_state/
  privacy_boundary_writer/
```

Current profile-related implementation anchors may remain elsewhere until migration, but new user-service behavior should be added through this module boundary.
