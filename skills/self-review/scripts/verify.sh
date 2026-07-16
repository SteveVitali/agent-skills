#!/usr/bin/env bash
# verify.sh — generic mechanical verification for the current repo.
#
# Discovers and runs the repo's build/test/lint checks. Resolution order:
#   1. $VERIFY_CMD                     — explicit command, run verbatim
#   2. Repo verification entry points  — ./scripts/verify.sh, ./bin/verify,
#                                        `make verify`, `make check`
#   3. Toolchain inference             — standard build/test/lint per detected
#                                        toolchain (npm/pnpm/yarn, cargo, go,
#                                        pytest, gradle, maven, mix)
#
# Output is context-efficient: one line per passing check, full output on
# failure (intended for agent consumption).
#
# Exit codes:
#   0 — all checks passed
#   1 — at least one check failed
#   2 — nothing could be discovered/inferred (caller must derive the repo's
#       verification commands from its docs/build files and run them directly)
#
# Notes:
#   - Bazel repos are detected but NOT run wholesale (building //... is
#     usually infeasible); this script exits 2 with a hint instead.
#   - Compatible with bash 3.2+ (macOS default). No `set -e`: we continue
#     after individual failures to report all results.
#
# Known limitations (callers should compensate where they matter):
#   - Monorepo workspaces: only ROOT-level manifests/scripts are inferred.
#     npm/pnpm/yarn workspaces, Cargo workspace members, and Go multi-module
#     layouts are exercised only insofar as their root scripts fan out.
#   - Gradle without a checked-in ./gradlew wrapper is skipped (no global
#     `gradle` invocation — version mismatch risk outweighs coverage).
#   - No changed-files scoping: detected checks run repo-wide. The --against
#     flag is reserved but UNIMPLEMENTED; for diff-scoped verification use a
#     repo-provided changed-files → targets mapper instead.

set -o pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

PASSED=0
FAILURES=0
RAN_ANY=false

# run_check <label> <command...>  — run in repo root, one line on pass,
# full output on failure.
run_check() {
  local label="$1"; shift
  local tmp_file
  tmp_file=$(mktemp)
  RAN_ANY=true
  if (cd "$REPO_ROOT" && "$@") > "$tmp_file" 2>&1; then
    printf '✓ %s\n' "$label"
    PASSED=$((PASSED + 1))
  else
    printf '✗ %s FAILED\n' "$label"
    cat "$tmp_file"
    FAILURES=$((FAILURES + 1))
  fi
  rm -f "$tmp_file"
}

finish() {
  echo ""
  if [ "$RAN_ANY" = false ]; then
    echo "VERIFY: nothing to run."
    exit 2
  fi
  if [ "$FAILURES" -eq 0 ]; then
    echo "VERIFY: ✓ All ${PASSED} check(s) passed"
    exit 0
  else
    echo "VERIFY: ✗ ${FAILURES} of $((PASSED + FAILURES)) check(s) FAILED"
    exit 1
  fi
}

# ── 1. Explicit command ──────────────────────────────────────────────────────
if [ -n "${VERIFY_CMD:-}" ]; then
  echo "VERIFY: using \$VERIFY_CMD"
  run_check "\$VERIFY_CMD" bash -c "$VERIFY_CMD"
  finish
fi

# ── 2. Repo-provided entry points ────────────────────────────────────────────
for candidate in "scripts/verify.sh" "bin/verify" ".dev/evaluators/verify.sh"; do
  target="$REPO_ROOT/$candidate"
  # Skip if the candidate resolves to this very script (avoid recursion).
  if [ -x "$target" ] && [ "$(cd "$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")" != "$SELF" ]; then
    echo "VERIFY: using repo entry point $candidate"
    run_check "$candidate" "$target"
    finish
  fi
done

if [ -f "$REPO_ROOT/Makefile" ]; then
  for mk_target in verify check; do
    if grep -qE "^${mk_target}[[:space:]]*:" "$REPO_ROOT/Makefile" 2>/dev/null; then
      echo "VERIFY: using make ${mk_target}"
      run_check "make ${mk_target}" make "$mk_target"
      finish
    fi
  done
fi

# ── 3. Toolchain inference ───────────────────────────────────────────────────
echo "VERIFY: inferring checks from detected toolchains"
echo ""

# Bazel: detected but never run wholesale.
if [ -f "$REPO_ROOT/WORKSPACE" ] || [ -f "$REPO_ROOT/MODULE.bazel" ] || [ -f "$REPO_ROOT/WORKSPACE.bazel" ]; then
  echo "⚠ Bazel workspace detected: targeted invocation required."
  echo "  Derive the affected targets (e.g. from a changed-files → targets mapper or the"
  echo "  repo's docs) and run 'bazel build/test <targets>' directly."
  BAZEL_ONLY=true
else
  BAZEL_ONLY=false
fi

# Node (npm / pnpm / yarn) — run package.json scripts that exist.
if [ -f "$REPO_ROOT/package.json" ]; then
  PKG_RUNNER="npm"
  [ -f "$REPO_ROOT/pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1 && PKG_RUNNER="pnpm"
  [ -f "$REPO_ROOT/yarn.lock" ] && command -v yarn >/dev/null 2>&1 && PKG_RUNNER="yarn"
  for script in build lint typecheck test; do
    if grep -qE "\"${script}\"[[:space:]]*:" "$REPO_ROOT/package.json" 2>/dev/null; then
      run_check "${PKG_RUNNER} run ${script}" "$PKG_RUNNER" run "$script"
    fi
  done
fi

# Rust
if [ -f "$REPO_ROOT/Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then
  run_check "cargo build" cargo build --quiet
  run_check "cargo test" cargo test --quiet
  command -v cargo-clippy >/dev/null 2>&1 && run_check "cargo clippy" cargo clippy --quiet -- -D warnings
fi

# Go
if [ -f "$REPO_ROOT/go.mod" ] && command -v go >/dev/null 2>&1; then
  run_check "go build ./..." go build ./...
  run_check "go vet ./..." go vet ./...
  run_check "go test ./..." go test ./...
fi

# Python (pytest)
if [ -f "$REPO_ROOT/pyproject.toml" ] || [ -f "$REPO_ROOT/setup.py" ] || [ -f "$REPO_ROOT/setup.cfg" ]; then
  if command -v pytest >/dev/null 2>&1 && { [ -d "$REPO_ROOT/tests" ] || [ -d "$REPO_ROOT/test" ] || grep -q pytest "$REPO_ROOT/pyproject.toml" 2>/dev/null; }; then
    run_check "pytest" pytest -q
  fi
fi

# JVM (Gradle / Maven)
if [ -f "$REPO_ROOT/gradlew" ]; then
  run_check "./gradlew build" ./gradlew build --quiet
elif [ -f "$REPO_ROOT/pom.xml" ] && command -v mvn >/dev/null 2>&1; then
  run_check "mvn test" mvn -q test
fi

# Elixir
if [ -f "$REPO_ROOT/mix.exs" ] && command -v mix >/dev/null 2>&1; then
  run_check "mix test" mix test
fi

if [ "$RAN_ANY" = false ] && [ "$BAZEL_ONLY" = true ]; then
  exit 2
fi

finish
