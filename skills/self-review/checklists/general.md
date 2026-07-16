# General Mechanical Checklist

Language-agnostic checks for self-review Pass 1. Every item is binary —
either violated or not. No judgment calls. Apply to every changed file;
repo- and language-specific checklists layer on top of this one.

## Diff Hygiene

- [ ] No leftover debug output (`print`, `console.log`, `println`, `dbg!`, `puts`, temporary logging)
- [ ] No commented-out code blocks introduced
- [ ] No unrelated reformatting churn — the diff contains only the intended change
- [ ] No new `TODO`/`FIXME` without an owner or issue reference; existing ones preserved
- [ ] No accidental files staged (editor swap files, `.DS_Store`, build artifacts, large binaries)

## Safety

- [ ] No secrets, credentials, API keys, or tokens anywhere in the diff
- [ ] No hardcoded environment-specific values (hosts, ports, absolute paths) where config exists
- [ ] Generated files untouched by hand (lockfiles changed only via the package manager; codegen
      output regenerated, not edited)

## Correctness Mechanics

- [ ] All new imports/dependencies declared in the right manifest; unused imports removed
- [ ] New failure modes handled or explicitly propagated — no silently swallowed errors
- [ ] Boundary inputs considered where the change touches them: empty, null/none, zero, max
- [ ] Resource lifecycles closed (files, connections, subscriptions, listeners) on all paths,
      including error paths

## Consistency

- [ ] Naming matches the surrounding module's conventions (casing, prefixes/suffixes, vocabulary)
- [ ] Formatting matches the repo formatter — run it if one exists
- [ ] New files follow the repo's placement/naming conventions and include required headers
      (license, encoding) if the repo uses them

## Completeness

- [ ] Tests updated or added for changed behavior (where the repo has a test culture)
- [ ] Docs/config samples/usage examples updated when flags, env vars, or public API surface changed
- [ ] All call sites updated when a signature, name, or contract changed (search, don't assume)
