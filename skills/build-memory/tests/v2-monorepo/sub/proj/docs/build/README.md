# Build memory

<!-- build-memory: v2 -->

The committed record of what happened during this build. The layout contract is
`skills/build-memory/layout.md`; this directory is the memory root resolved by
`memory-root.sh` in committed mode. Fixture for `check-build-memory.sh` (monorepo case: this memory root is `sub/proj/docs/build`, selected by `BUILD_MEMORY_ROOT`; the ledger names toplevel-relative paths).
