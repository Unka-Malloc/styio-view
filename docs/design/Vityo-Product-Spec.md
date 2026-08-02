# Vityo Product Spec

**Purpose:** Serve as the product-level source of truth for Vityo's positioning, hierarchy, users, invariants, capability domains, platform strategy, and acceptance boundary.

**Last updated:** 2026-07-30

**Status:** Current

## 1. Product Positioning

**Vityo is the agent-native IDE for Styio.**

Vityo is a desktop-first developer environment for people building streaming, stateful, and
resource-topology software with Styio. It brings source editing, authoritative language and compiler
facts, build/test/run workflows, runtime observation, and reviewable Agent collaboration into one
trustworthy workbench.

Generic editors can display Styio source, terminals can invoke its tools, and detached chat clients
can suggest code. Those separate tools do not share one revisioned view of the source, compiler
truth, runtime state, permissions, proposed changes, and validation receipts. Vityo's differentiator
is that these facts and controls are first-class parts of the same product:

1. Styio source and semantic structures remain authoritative and inspectable.
2. Compiler, test, execution, and runtime results are typed facts rather than inferred success.
3. Agent plans, tool activity, permissions, change sets, and validation receipts are visible and
   controllable inside the workbench.
4. Agent-originated edits enter only through the IDE-owned, revision-bound workspace transaction
   path.
5. Missing capabilities remain explicit degraded or blocked states; Vityo never invents compiler,
   runtime, or Agent success.

## 2. Product Hierarchy

| Name | Role | Product status |
|---|---|---|
| **Vityo** | The user-facing Styio agent-native IDE and sole product identity owned by this repository. | Product |
| **Vityo Coding Agent** | The first-party, independently executable companion Agent runtime. Vityo and other compatible clients may launch it through the versioned Agent protocol. | Companion runtime |
| **Vityo Agent Protocol** | The pure, versioned wire contract shared by the IDE and compatible Agents. | Shared contract, not a product |
| **Styio** | The external language, compiler, language service, and toolchain ecosystem consumed by Vityo. | External dependency |

The IDE and companion runtime have separate engineering delivery tracks because they are
independently testable and releasable. That engineering separation does not create a second Vityo
product identity.

## 3. Users and Jobs

### 3.1 Primary users

Styio developers building programs whose streaming, state, concurrency, and resource-topology
behavior benefits from language-aware editing and observable execution.

Their primary job is:

> Change a Styio program, understand the language and compiler facts, prove it through tests and
> execution, observe what happened at runtime, and collaborate with an Agent without losing control
> of the workspace.

### 3.2 Secondary users

1. Styio language designers and core contributors validating new language and toolchain behavior.
2. Teams that need durable, reviewable Agent-assisted work against controlled Styio workspaces.
3. Users who move between local desktop execution and capability-declared hosted execution.

Needing generic AI chat, a general-purpose text editor, or a model-hosting frontend alone does not
make someone a primary Vityo user.

## 4. Launch Promise

The first independently acceptable product is the desktop Vityo IDE on Windows, macOS, and Linux.
It must prove both of these loops on one source revision:

### 4.1 Trustworthy Styio developer loop

```text
edit -> analyze -> test -> run -> observe
```

The user can complete the loop without an Agent. Every transition produces source-bound facts,
structured receipts, or an explicit unavailable/blocked state.

### 4.2 Reviewable Agent loop

```text
goal -> plan -> approved tools -> proposed changes -> review -> validation receipt
```

At least one compatible Agent can run as a supervised workbench task. The user can inspect its plan
and activity, answer permission requests, steer or cancel it, review its changes, and inspect
validation results. The Agent cannot mutate IDE-owned files directly or authorize its own effects.

Mobile interaction, hosted workspaces, full module distribution, visual theme authoring, and
additional runtime visualizations remain valid product directions, but they do not dilute or replace
this launch promise.

## 5. Non-goals

1. Vityo is not a VS Code skin, a theme pack, or a clone of a generic IDE shell.
2. Vityo is not a general-purpose, every-language IDE at launch.
3. Vityo is not a standalone chat client, and the Agent Workbench is not an embedded chat tab.
4. The IDE does not own model-provider integration, model inference, prompt orchestration, tool
   loops, durable Agent sessions, or multi-Agent scheduling.
5. The IDE does not connect directly to OpenAI-compatible or other model endpoints. Those concerns
   belong to an Agent runtime.
6. An Agent is not required to launch Vityo or complete the trustworthy Styio developer loop.
7. Vityo does not reimplement Styio language, compiler, package, registry, or deployment truth.
8. Compatibility with arbitrary third-party plugin ecosystems is not a launch goal.
9. iOS does not promise unrestricted local JIT or unsupported executable module behavior.
10. Desktop, mobile, and Web do not need identical interaction or execution strategies.

## 6. Core Terms

| Term | Definition |
|---|---|
| **Source Buffer** | The canonical Styio source text edited and saved by the user. |
| **Visual Substitution** | Display-only rendering of source tokens such as `->` or `|>`; it never changes the Source Buffer. |
| **Semantic Block Surface** | A parser/typecheck-driven visual container for language structures such as functions, states, or resource blocks. |
| **Minimal Compilable Unit** | The smallest legal unit in the current context that can be compiled or run. |
| **Runtime Surface** | The workbench area that renders ordered execution facts, state graphs, thread lanes, diagnostics, and logs. |
| **Runtime Event Protocol** | The ordered machine contract that drives runtime visualization. |
| **Agent Workbench** | The IDE capability that presents Agent tasks, sessions, plans, activity, permissions, changes, artifacts, and validation receipts. |
| **Agent Panel** | A concrete UI surface that may display part of the Agent Workbench; it is not the Agent runtime or the product definition. |
| **Agent Client** | The IDE-owned process/protocol client that discovers, launches, supervises, reconnects to, and communicates with compatible Agents. |
| **Compatible Agent** | An Agent implementation that negotiates and follows the supported versioned session boundary. |
| **Vityo Coding Agent** | Vityo's first-party companion runtime for model/provider routing, context selection, tools, policy, coding loops, durable sessions, and multi-Agent execution. |
| **Workspace Transaction** | The IDE-owned preview/commit/rollback boundary for revisioned changes, including Agent proposals. |
| **Local Runtime** | A device-local Styio compiler and execution environment. |
| **Hosted Workspace** | A remotely hosted workspace used by clients that cannot or should not own the local execution path. |
| **Core Module** | An inseparable part of the Vityo shell, editor, or trusted workbench. |
| **Optional Module** | A capability-declared module that may be installed, disabled, updated, or removed per platform. |
| **Capability Matrix** | The declared availability and visibility of a capability for a platform or product route. |

## 7. Product Invariants

### 7.1 Source and language truth

1. The canonical representation of every user file is the original Styio source text.
2. Visual substitutions and semantic surfaces never silently rewrite source.
3. Copy, search, diff, diagnostics, and workspace edits remain bound to Source Buffer positions.
4. Structural rendering is driven by language or structural facts, not fragile regex guesses.
5. Token and semantic facts drive highlighting; linters provide diagnostics, fixes, and hints.
6. Formatting and completion enter the editor as explicit edits or candidates.
7. Styio remains the source of language, compiler, toolchain, and runtime truth.

### 7.2 Truthful execution and observation

1. Save, completion of a minimal compilable unit, or an explicit command may trigger compilation
   according to user-configurable policy.
2. The platform-equivalent of `Ctrl+Enter` runs the current legal unit or selected target.
3. Runtime visualization is a first-class capability, not an ornamental debug panel.
4. Runtime views consume only declared, ordered runtime events.
5. Unsupported semantics remain unavailable or degraded; the UI never guesses a runtime graph.
6. Desktop local execution is the launch path. Hosted execution remains capability-declared.

### 7.3 Agent-native ownership

1. Vityo remains independently useful when no Agent is installed or connected.
2. Agent sessions are first-class, long-running workbench tasks rather than detached chat turns.
3. Vityo may connect to Vityo Coding Agent or another compatible Agent through the versioned
   process/protocol boundary.
4. The IDE owns Source Buffers, document/workspace revisions, language and execution facts,
   permission presentation, change review, and workspace transaction commits.
5. Agent runtimes own model/provider integration, context selection, tool execution, effect policy,
   coding-loop orchestration, durable session state, and multi-Agent coordination.
6. The IDE never imports Agent runtime implementation and the Agent runtime never imports Vityo or
   Flutter implementation.
7. The Agent cannot write IDE-owned files directly. It proposes revision-bound change sets.
8. Permission requests, changes, and validation results remain visible until explicitly resolved.
9. Model output and tool output are untrusted inputs; they cannot widen roots, permissions,
   credentials, network access, or execution capabilities.
10. Unknown protocol versions or capabilities fail closed with a useful diagnostic.

### 7.4 Platform and extension behavior

1. Desktop, Android, iOS, and Web share the document model, language contracts, and capability
   vocabulary while allowing platform-specific presentation and execution.
2. Unsupported capabilities do not expose misleading UI entry points.
3. Optional modules are governed by manifests, capability matrices, and staged activation.
4. Module updates do not replace a mounted module until the declared activation boundary.
5. Login, profile sync, and remote identity are optional services, not prerequisites.
6. A future provider-neutral general profile must remain fully usable without
   `ProfileSyncAdapter`; no general profile runtime is currently claimed.
7. Child components must preserve container integrity through layout, scrolling, folding, or bounds.

## 8. Capability Domains

### 8.1 Editor and language services

Vityo owns the document model, cursor and selection semantics, undo/redo, source-fidelity rendering,
visual substitution, semantic block surfaces, desktop/mobile input adaptation, workspace navigation,
and application of revisioned language edits.

Styio-owned services provide lexical, semantic, diagnostic, completion, hover, formatting,
reference, refactor, compile, and runtime facts through explicit adapters. Unavailable facts produce
capability gaps, not local guesses presented as authoritative results.

### 8.2 Developer loop

The workbench exposes project graph, dependency, toolchain, build, test, run, debug, terminal,
deployment, and runtime-event lanes through typed adapters and receipts. The same revision-bound
facts are available to the user and to authorized Agent sessions.

### 8.3 Runtime observation

The Runtime Surface renders only registered event families and declared feature entries. It may show
state graphs, directed execution summaries, thread lanes, diagnostics, stdout/stderr, and logs. An
incomplete visualization is acceptable when its supported subset is explicit; fabricated semantics
are not.

### 8.4 Agent Workbench

The Agent Workbench provides:

1. multiple task/session views with explicit lifecycle state;
2. streamed turns, plans, steps, tool activity, artifacts, and usage;
3. persistent permission and elicitation requests;
4. steer, cancel, retry, reconnect, and Agent-switch controls;
5. revision-bound diff preview, conflict reporting, apply/reject/revert, and receipts;
6. bounded context export with provenance, sensitivity, revision, and truncation metadata;
7. protocol capability negotiation and explicit degraded states.

Model selection, provider credentials, model request shapes, tool-loop execution, and multi-Agent
scheduling belong to the connected Agent runtime, not the IDE.

### 8.5 Personalization, modules, and hosted routes

Themes, local profiles, optional profile sync, module lifecycle, staged updates, mobile-specific
interaction, hosted workspaces, cloud execution, and export/retention UX remain supported capability
domains. They are secondary to the desktop launch promise and must preserve the same truthfulness,
security, and capability-declaration invariants.

## 9. Platform Strategy

| Platform | Product route | Styio compile/run | Agent route | Release priority |
|---|---|---|---|---|
| Windows / macOS / Linux | Native Flutter desktop IDE | Local-first; hosted route optional | Supervised local or remote compatible Agent through the versioned protocol | Launch |
| Android | Native mobile interaction | Local-first when supported; hosted fallback | Compatible Agent connection subject to platform capability policy | Post-launch |
| iOS | Native mobile interaction | Hosted execution; no unrestricted local compiler module | Remote compatible Agent through an iOS-safe transport | Last mobile release |
| Web | Hosted-workspace client | Hosted workspace and execution | Remote compatible Agent | Post-launch |

Each desktop platform has its own package, signing, install, smoke, update, and release receipt.
Failure on one platform does not invalidate another platform's independently proven artifact.

## 10. Quality and Acceptance

1. Editing remains responsive and visual substitution preserves source-position semantics.
2. Language, compiler, test, run, and runtime facts are attributable to a source revision.
3. Missing or heuristic capabilities are visible and never reported as successful.
4. The IDE starts and completes the developer loop with no Agent available.
5. Agent plans, permissions, tool activity, changes, and validation receipts remain reviewable.
6. Stale Agent changes fail without partial mutation.
7. Agent and IDE failures are isolated; one failed session cannot take down the editor or a sibling
   session.
8. Secrets are resolved only at the intended execution boundary and are redacted from UI, logs,
   protocol payloads, context, and receipts.
9. Mobile interaction is designed for mobile rather than scaled from desktop.
10. Hosted-workspace export, retention, closure, and deletion behavior is explicit and recoverable.

The launch positioning is accepted only when a representative Styio workspace completes both the
trustworthy developer loop and the reviewable Agent loop described in Section 4. Documentation,
mock-only success, or a green default CI run without the required product evidence does not prove
that launch promise.
