# Vityo IDE Interaction Quality Bar

**Purpose:** Define the minimum interaction quality baseline that Vityo must maintain to be a credible modern IDE. These are not aspirational targets — they are gated requirements.

**Last updated:** 2026-06-24

**Status:** Active quality baseline

## 1. Editor Input Latency

### 1.1 Typing Latency

- Keystroke to visual update must complete within one frame (≤16ms at 60Hz).
- Visual substitution rendering must not add more than one additional frame of latency.
- When substitution is toggled off, rendering must be strictly faster, not slower.

### 1.2 Large File Policy

- Files up to 5,000 lines must render without perceptible delay.
- Files 5,000–20,000 lines may use viewport-only rendering with scroll-position-aware tokenization.
- Files >20,000 lines must explicitly show a "large file — viewport rendering active" indicator in the status area.
- Syntax highlighting must not degrade to plain text without user-noticeable status change.

### 1.3 Render Slice Budget

- Each render slice (the work done per animation frame) must complete within 8ms on the UI thread.
- If language service results arrive mid-frame, they must be applied in the next frame, not the current one.
- Repaint scope must be limited to changed lines plus one line of context above and below.

## 2. Keyboard Navigation Baseline

### 2.1 Command Palette

- `Ctrl+Shift+P` / `Cmd+Shift+P` opens command palette.
- Arrow keys navigate results; Enter executes; Escape dismisses.
- Typing filters results with visible feedback within one frame.
- Blocked commands show reason in the palette item, not in a separate tooltip only.
- Recent commands appear first when query is empty.

### 2.2 Diagnostics Navigation

- `F8` / `Shift+F8` navigates to next/previous diagnostic in current file.
- Focus lands at the diagnostic's source range in the editor.
- If no diagnostics exist in current file, show a brief "no problems" status.
- Diagnostics panel must be navigable by keyboard: Tab into list, arrow keys to select, Enter to go to source.

### 2.3 Project Explorer

- `Ctrl+Shift+E` / `Cmd+Shift+E` focuses the workspace explorer.
- Arrow keys navigate tree; Enter opens file; F2 renames (when supported).
- Type-ahead selection: typing filenames selects matching tree item.

### 2.4 Runtime Lane Navigation

- `Shift+1` focuses runtime surface.
- Tab/Shift+Tab moves between lane summaries.
- Arrow keys navigate within a lane's event list or graph.
- Filter tokens can be typed without first clicking a filter field.

### 2.5 Agent Panel

- `Shift+2` focuses agent panel.
- Tab order: context summary → input → send button → turn list → permission requests.
- Escape returns focus to editor.
- Permission decisions navigable by keyboard (Tab to button, Enter to decide).

### 2.6 Settings

- `Ctrl+,` / `Cmd+,` opens settings.
- Search field auto-focused on open.
- Section navigation by keyboard (Tab between sections, Enter to expand).
- Settings changes apply immediately where safe; otherwise show Apply/Reset buttons reachable by Tab.

## 3. Focus Model

### 3.1 Focus Visibility

- Focused element must have a visible indicator (outline, background shift, or caret).
- Focus indicator must meet 3:1 contrast ratio against adjacent colors.
- Focus must never be trapped in a hidden or off-screen element.

### 3.2 Focus Restoration

- Closing a panel restores focus to the element that opened it.
- Switching tabs restores the last focus position within that tab.
- After a command executes, focus returns to the editor unless the command explicitly targets another surface.

### 3.3 Focus Trap

- Modal dialogs trap focus within the dialog.
- Panel overlays trap focus within the panel until dismissed.
- No focus trap should persist after the modal/overlay is removed from the tree.

## 4. Screen-Reader / Semantics Baseline

### 4.1 Flutter Semantics

- All interactive elements must expose a `Semantics` label.
- Editor lines must expose line number and content summary.
- Diagnostic markers must expose severity + message.
- Command palette items must expose label + shortcut.
- Status bar items must expose their current value.

### 4.2 Contrast Requirements

- Editor text: ≥4.5:1 contrast ratio against background (AA normal text).
- UI text (labels, buttons, menus): ≥3:1 contrast ratio (AA large text).
- Focus indicators: ≥3:1 against adjacent colors.
- Diagnostic squiggles: distinguishable from text by both color and pattern (not color alone).
- All contrast ratios verified against at least the default Graphite theme.

## 5. Theme Requirements

### 5.1 Coverage

Every surface must respond to theme changes:
- IDE shell (sidebar, status bar, title bar)
- Editor text area (background, text, line numbers, gutters)
- Semantic blocks (function bodies, state blocks, resource blocks)
- Visual substitution glyphs (arrow, pipe, block markers)
- Diagnostics (error/warning/hint squiggle colors, inline feedback)
- Runtime surface (lane backgrounds, event cards, graph nodes)
- Agent panel (turn bubbles, permission cards, context summary)
- Focus/selection/caret (selection highlight, caret color, find-match highlight)

### 5.2 Narrow Viewport

- At viewport width < 600px, sidebar collapses to overlay.
- At viewport width < 400px, bottom panels stack vertically with drag-to-resize handles.
- Font size must not drop below 12px for editor text, 11px for UI labels.
- Touch targets must be ≥44px in both dimensions on mobile viewports.

## 6. No-Overflow Layout Rule

### 6.1 Rule

**No child component may visually overflow its parent container.** If space is insufficient, the component must:
1. Reflow (wrap text, stack elements vertically)
2. Enable internal scrolling (`overflow: scroll` equivalent)
3. Truncate with ellipsis and tooltip
4. Reduce information density (show summary with expand)

### 6.2 Verification

- Every container must be testable for overflow.
- CI must include at least one widget test that renders a container at minimum supported width and asserts no overflow.
- Narrow viewport (360px width, mobile minimum) must not produce horizontal scrollbars on primary content.

## 7. Narrow Viewport Behavior

### 7.1 Breakpoints

| Width | Behavior |
|---|---|
| ≥900px | Full desktop layout: sidebar + editor + optional right panel |
| 600–899px | Collapsed sidebar (icons only); editor full width; bottom panels |
| 360–599px | Sidebar as overlay; editor full width; bottom panels stacked; reduced font |
| <360px | Sidebar as overlay; editor full width; single bottom panel at a time; minimal chrome |

### 7.2 Mobile-specific

- Touch targets ≥44px.
- No hover-dependent interactions; long-press substitutes where needed.
- Keyboard shortcuts documented for external keyboard users.
- On-screen keyboard must not obscure the editor caret; viewport must scroll to keep caret visible.

## 8. Performance Non-Regression

### 8.1 Startup

- Cold startup to interactive editor: target ≤3 seconds on desktop, ≤5 seconds on mobile.
- Warm startup (already-installed modules): target ≤1.5 seconds.

### 8.2 Memory

- Idle memory (one file open, no run): ≤150 MB on desktop.
- After opening 20 files and running once: ≤300 MB.
- Closing all files except one must return toward idle baseline.

### 8.3 No Telemetry

- Vityo must never ship telemetry, usage tracking, or analytics in the product binary.
- Local-only metrics (frame times, memory) for developer use must be opt-in and never leave the device.
- The `telemetry-free audit label` on commands means exactly that: no command execution data leaves the device.

## 9. Validation

### 9.1 Automated

- At least one widget test proving keyboard navigation for a core action (command palette, diagnostics nav, or explorer nav).
- At least one widget test proving no container overflow at minimum viewport width.
- Contrast ratio check script for the default theme (can be a simple color-math unit test).

### 9.2 Manual

- Keyboard-only walkthrough of: open file → navigate diagnostics → run → view runtime → open agent → return to editor.
- Narrow viewport (360px) visual check on each platform family.
- Screen-reader check on at least one platform.

## 10. References

- [Vityo-Product-Spec.md](./Vityo-Product-Spec.md) — Product invariants including no-overflow rule
- [Vityo-IDE-Benchmark-Matrix.md](./Vityo-IDE-Benchmark-Matrix.md) — Performance/interaction benchmark rows
- [Vityo-IDE-Capability-Maturity.md](./Vityo-IDE-Capability-Maturity.md) — Maturity assessment for interaction capabilities
- [../specs/HANDWRITTEN-WEB-IDE-ENGINEERING-HANDBOOK.md](../specs/HANDWRITTEN-WEB-IDE-ENGINEERING-HANDBOOK.md) — Prototype interaction design decisions
