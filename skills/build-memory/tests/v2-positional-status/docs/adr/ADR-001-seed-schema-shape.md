# ADR-001: Seed schema shape

- **Status:** Accepted
- **Date:** 2026-09-09
- **Ticket:** T1
- **Requirement ids:** BM-DEMO-01
- **Spec:** §1

## Context
The build needs a schema before any consumer can read it.

## Decision
Seed a single flat schema file, additive-only.

## Consequences
Consumers can rely on a stable shape; back-compat when empty.

## Alternatives considered
A nested schema — rejected as premature.

## Revisit trigger
Revisit if a second consumer needs a shape T1 did not anticipate.
