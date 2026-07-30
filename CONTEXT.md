# Vityo Domain Glossary

**Purpose:** Freeze the product and dependency vocabulary used by this repository.

**Last updated:** 2026-07-28

## Terms

### Vityo

The sole product and repository identity owned here, positioned as the
agent-native IDE for Styio. Application names, package names, installer
identities, release artifacts, product plans, and user-visible copy derive
their identity from Vityo.

Vityo remains a complete IDE when no Agent is installed. Its Agent Workbench
connects to first-party or compatible Agent runtimes through the versioned
Vityo Agent Protocol; the IDE does not own model-provider integration or Agent
execution orchestration.

### Styio

An external programming language, compiler, and toolchain ecosystem consumed by
Vityo. Styio names language files, language semantics, compiler/toolchain facts,
and Styio-owned integration contracts; it does not name this product.

### StyioService / `styio_lspd`

The external Styio-owned language service consumed by Vityo through an explicit
adapter boundary. Its identity remains Styio-owned and must not be used as a
Vityo product, package, installer, or release identity.

### Vityo Coding Agent

The first-party, independently executable companion Agent runtime for Vityo.
It may be launched by Vityo or another compatible client. It owns
model/provider routing, context selection, tools, policy, coding loops,
durable sessions, and multi-Agent coordination, and communicates through the
versioned Vityo Agent Protocol.

It is an independent engineering delivery track, not a second Vityo product
identity.

### Vityo Agent Protocol

The pure, versioned wire contract shared by Vityo and compatible Agents. It is
not a product and contains no IDE presentation or Agent orchestration.

## Naming Invariant

Dependency integration may add Styio-owned service and toolchain terms, but it
must never rename Vityo or create a second product identity. A future product
rename requires an explicit owner decision and an atomic repository-wide
migration.
