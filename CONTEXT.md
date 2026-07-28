# Vityo Domain Glossary

**Purpose:** Freeze the product and dependency vocabulary used by this repository.

**Last updated:** 2026-07-28

## Terms

### Vityo

The sole product and repository identity owned here. Application names, package
names, installer identities, release artifacts, product plans, user-visible
copy, and Vityo-owned components must derive their identity from Vityo.

### Styio

An external programming language, compiler, and toolchain ecosystem consumed by
Vityo. Styio names language files, language semantics, compiler/toolchain facts,
and Styio-owned integration contracts; it does not name this product.

### StyioService / `styio_lspd`

The external Styio-owned language service consumed by Vityo through an explicit
adapter boundary. Its identity remains Styio-owned and must not be used as a
Vityo product, package, installer, or release identity.

### Vityo Coding Agent

A Vityo-owned coding-agent runtime. It is an independently testable Vityo
component and communicates with the Vityo application through a versioned
Vityo-owned protocol package.

## Naming Invariant

Dependency integration may add Styio-owned service and toolchain terms, but it
must never rename Vityo or create a second product identity. A future product
rename requires an explicit owner decision and an atomic repository-wide
migration.
