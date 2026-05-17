# App Shell Surface

**Purpose:** Document the `docs/design/appearance/app-shell-surface/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

App Shell Surface is an Appearance Layer concern. It absorbs the former product-ui/product-surface idea without creating a separate product UI layer.

## 1. Position

```text
Appearance Layer
  app-shell-surface/
    onboarding/
    recovery_surface/
    capability_status/
    account_entry/
```

The app shell is a visible composition surface. It shows entry points, status, recovery guidance, and high-level navigation, but it does not own IDE capabilities.

## 2. Responsibilities

| Component | Responsibility |
|---|---|
| Onboarding Surface | Presents first-run and project-welcome flows. |
| Recovery Surface | Displays degraded states and recovery guidance produced by lower layers. |
| Capability Status Surface | Displays capability, fallback, and unsupported-runtime status. |
| Account Entry Surface | Presents optional login/profile/sync entry points. Account behavior lives in the User Service. |
| Shell Composition Surface | Arranges top-level panes, routes, and user-visible entry points. |

## 3. Non-Responsibilities

| Capability | Owner |
|---|---|
| Login, account state, local profile, and profile sync | Service Layer / User Service |
| Editor commands and controller state | Interaction Layer |
| Editor drawing, theme mapping, and visual primitives | Appearance Layer renderer modules |
| File system, process, platform, and DataStore primitives | Environment Layer |
| Styio syntax, semantic facts, diagnostics, and completion | Service Layer / Styio Service Adapter |

## 4. Implementation Target

```text
frontend/vityo_app/lib/src/view_render/app_shell/
  onboarding/
  recovery_surface/
  capability_status/
  account_entry/
  shell_composition/
```

No `product-ui/` or `product_surface/` directory should be introduced. Visible product surfaces belong to `view_render/app_shell`, while functional behavior stays in `view_ide` modules.
