#!/usr/bin/env bash
# run-tests.sh — self-test for orchestrate-build's scripts: ci-boundary.sh (SK-01), drive-build.sh's
# status-enum guard, CI gate, --print-prompt (SK-02) and harness line (SK-04), digest.sh (SK-08), a monorepo memory
# root (BM-ROOT-03) and external-state.sh (local bare-repo origins). No network: a stub `gh` (stub-gh.sh) answers
# from canned files and a stub agent CLI (stub-agent.sh) closes one ticket per call.
#
# Usage:   run-tests.sh
# Exit codes: 0 — all cases pass; 1 — a case failed.
# Compatible with bash 3.2+ (macOS default). Writes only under its own temp dirs.

set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd)"
CIB="$SCRIPTS/ci-boundary.sh" ; DRIVE="$SCRIPTS/drive-build.sh"
FAIL=0
# Hermetic: an operator's exported memory-root settings (e.g. a monorepo's BUILD_MEMORY_ROOT) must not leak in.
unset BUILD_MEMORY_ROOT BUILD_MEMORY_TICKETS BUILD_MEMORY_ADR AGENT_SCRATCH_DIR
say()  { printf '%s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; FAIL=1; }
T="$(printf '\t')"

# A stub-gh bin dir first on PATH, plus a fresh canned-answer dir.
BIN="$(mktemp -d)"; cp "$HERE/stub-gh.sh" "$BIN/gh"; chmod +x "$BIN/gh"
STUBPATH="$BIN:$PATH"
newstub() { STUB_GH_DIR="$(mktemp -d)"; export STUB_GH_DIR; }
# check <n> <frame|""> <lines…>  — write canned `gh pr checks` output (one arg per check line)
checks() { local n="$1" k="$2" f; shift 2; f="$STUB_GH_DIR/checks-$n${k:+.$k}"; : > "$f"; for l in "$@"; do printf '%s\n' "$l" >> "$f"; done; }
view() { printf '%s\t%s\t%s\t%s\n' "$2" "${3:-OPEN}" "${4:-main}" "${5:-branch-$1}" > "$STUB_GH_DIR/view-$1"; }
headpr() { printf '%s\n' "$2" > "$STUB_GH_DIR/head-$(printf '%s' "$1" | tr '/' '_')"; }
run_url() { printf 'https://github.com/o/r/actions/runs/%s/job/9' "$1"; }

# A worktree that declares CI (unless told otherwise) with a committed-mode ledger + BUILD_INDEX.
mkrepo() {   # mkrepo [noci]
  local W; W="$(mktemp -d)/repo"; mkdir -p "$W/docs/build/logs" "$W/.github/workflows"; git init -q "$W" 2>/dev/null
  [ "${1:-}" = "noci" ] && rm -rf "$W/.github"
  [ -d "$W/.github/workflows" ] && printf 'on: [pull_request]\n' > "$W/.github/workflows/ci.yml"
  printf '# build memory\n<!-- build-memory: v2 -->\n' > "$W/docs/build/README.md"
  printf '*\n!.gitignore\n' > "$W/docs/build/logs/.gitignore"
  cat > "$W/docs/build/LEDGER.md" <<'EOF'
# Build ledger

## CURRENT STATE

```
projectStatus:   IN_PROGRESS
nextTicket:      T1
lastCompleted:   (none)
blockedOn:       (nothing)
pauseRequested:  false
returnPass:      (none)
manifest:        docs/tickets/00_MANIFEST.md
canonicalSpec:   docs/spec.md
memoryRoot:      docs/build
dispatchTarget:  headless
buildWorktree:   .
buildBranchBase: demo/base
pinnedBaseSha:   0000000
chainTip:        demo/base
benchmarkSet:    N/A
autonomy:        auto
mergePolicy:     OPERATOR
round:           1
updatedAt:       2026-10-01T00:00:00Z
```

## OPEN FINDINGS

(none)

## GATE DECISIONS

| date | ticket | gate | item | answer (verbatim) | consequence | kind |
|---|---|---|---|---|---|---|

## RETURN PASS

| ticket | gates | what the operator must do | re-run line |
|---|---|---|---|

## PHASE LOG — Round 1

- 2026-10-01 — ROUND1 round — fixture seed
EOF
  printf '| seq | ticket | kind | branch | PR | base | landed | ADRs | deferrals opened → closed | live verification | evidence | harness |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n' > "$W/docs/build/BUILD_INDEX.md"
  printf '%s' "$W"
}
setkey() { awk -v k="$2" -v v="$3" '$0 ~ "^" k ":" { printf "%-17s%s\n", k ":", v; next } { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }

# cib <expected exit> <label> <args…> — run ci-boundary with the stub PATH; leaves OUT / LAST / RC.
cib() {
  local want="$1" label="$2"; shift 2
  OUT="$(PATH="$STUBPATH" bash "$CIB" "$@" 2>&1)"; RC=$?
  LAST="$(printf '%s\n' "$OUT" | tail -1)"
  [ "$RC" -eq "$want" ] || { fail "ci-boundary $label: exit=$RC (want $want) — $LAST"; return 1; }
  return 0
}
expect_last() { [ "$LAST" = "$2" ] || fail "ci-boundary $1: last line '$LAST' (want '$2')"; }

# ── ci-boundary.sh ────────────────────────────────────────────────────────────
test_ci_boundary() {
  local W J ok_before=$FAIL
  W="$(mkrepo)"; J="$W/ci.json"

  newstub; view 7 abc1234def
  checks 7 "" "python${T}pass${T}$(run_url 111)${T}${T}CI" "docs${T}pass${T}$(run_url 222)${T}${T}CI"
  cib 0 pass --pr 7 --worktree "$W" --no-wait --json "$J" && expect_last pass "ci: pass #7@abc1234 (python 111; docs 222)"
  grep -q '"schema":"ci-boundary/1"' "$J" && grep -q '"state":"pass"' "$J" && grep -q '"run_id":"111"' "$J" \
    || fail "ci-boundary pass: JSON record missing schema/state/run_id"

  newstub; view 7 abc1234def
  checks 7 "" "python${T}pass${T}$(run_url 111)${T}${T}CI" "web${T}fail${T}$(run_url 333)${T}Process completed with exit code 1${T}CI"
  cib 3 fail --pr 7 --worktree "$W" --no-wait && expect_last fail "blockedOn: CI fail on #7 (web): Process completed with exit code 1 (run 333)"

  newstub; view 7 abc1234def; checks 7 "" "composed${T}cancel${T}$(run_url 444)${T}${T}CI"
  cib 3 cancel --pr 7 --worktree "$W" --no-wait

  newstub; view 7 abc1234def
  checks 7 1 "python${T}pending${T}$(run_url 555)${T}${T}CI"
  checks 7 2 "python${T}pass${T}$(run_url 555)${T}${T}CI"
  cib 0 pending-then-pass --pr 7 --worktree "$W" --interval 1 --max-wait 10 && expect_last pending-then-pass "ci: pass #7@abc1234 (python 555)"
  [ "$(cat "$STUB_GH_DIR/count-7")" = "2" ] || fail "ci-boundary pending-then-pass: $(cat "$STUB_GH_DIR/count-7") reads (want 2)"

  newstub; view 7 abc1234def; checks 7 "" "python${T}pending${T}$(run_url 555)${T}${T}CI"
  cib 4 pending-forever --pr 7 --worktree "$W" --interval 1 --max-wait 2
  case "$LAST" in "blockedOn: CI pending on #7 (python):"*) : ;; *) fail "ci-boundary pending-forever: last line '$LAST'";; esac

  newstub; view 7 abc1234def; checks 7 "" "@nochecks"
  cib 4 no-checks-reported --pr 7 --worktree "$W" --no-wait

  newstub; view 7 abc1234def; checks 7 "" "@error"
  cib 5 checks-unreadable --pr 7 --worktree "$W" --no-wait

  newstub   # no view-7 → gh pr view fails (unknown PR / unauthenticated)
  cib 5 view-unreadable --pr 7 --worktree "$W" --no-wait

  # gh absent while the repo declares CI → unknown, never green
  if PATH=/usr/bin:/bin command -v gh >/dev/null 2>&1; then
    say "  (skip gh-absent: a gh exists in /usr/bin:/bin on this host)"
  else
    OUT="$(PATH=/usr/bin:/bin bash "$CIB" --pr 7 --worktree "$W" --no-wait 2>&1)"; RC=$?
    [ "$RC" -eq 5 ] || fail "ci-boundary gh-absent: exit=$RC (want 5)"
  fi

  # no CI declared → none-declared, exit 0, even without gh
  W2="$(mkrepo noci)"
  OUT="$(PATH=/usr/bin:/bin bash "$CIB" --pr 7 --worktree "$W2" --no-wait 2>&1)"; RC=$?
  [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | tail -1)" = "ci: none-declared (locally-green)" ] \
    || fail "ci-boundary none-declared: exit=$RC last='$(printf '%s\n' "$OUT" | tail -1)'"

  # required set (record_policy/ci_required.txt): missing → pending on one read, fail after a wait;
  # skipped required → fail; a failing non-required check is informational
  mkdir -p "$W/docs/build/tools/record_policy"; printf 'python\nsecurity   # required\n' > "$W/docs/build/tools/record_policy/ci_required.txt"
  newstub; view 7 abc1234def; checks 7 "" "python${T}pass${T}$(run_url 111)${T}${T}CI" "lint${T}fail${T}$(run_url 112)${T}${T}CI"
  cib 4 required-missing-no-wait --pr 7 --worktree "$W" --no-wait
  cib 3 required-missing-after-wait --pr 7 --worktree "$W" --interval 1 --max-wait 1 \
    && expect_last required-missing-after-wait "blockedOn: CI fail on #7 (security): required check missing"
  newstub; view 7 abc1234def; checks 7 "" "python${T}pass${T}$(run_url 111)${T}${T}CI" "security${T}skipping${T}$(run_url 113)${T}${T}CI"
  cib 3 required-skipped --pr 7 --worktree "$W" --no-wait
  newstub; view 7 abc1234def
  checks 7 "" "python${T}pass${T}$(run_url 111)${T}${T}CI" "security${T}pass${T}$(run_url 113)${T}${T}CI" "lint${T}fail${T}$(run_url 112)${T}${T}CI"
  cib 0 non-required-red-ignored --pr 7 --worktree "$W" --no-wait
  rm -rf "$W/docs/build/tools"

  # --stack: a red open ancestor blocks, naming the ancestor; a verbatim waiver row naming #7 + web clears it
  newstub; view 8 bbb8888000 OPEN demo/T1 demo/T2; view 7 aaa7777000 OPEN demo/base demo/T1; headpr demo/T1 7
  checks 8 "" "python${T}pass${T}$(run_url 801)${T}${T}CI"
  checks 7 "" "python${T}pass${T}$(run_url 701)${T}${T}CI" "web${T}fail${T}$(run_url 702)${T}npm ci failed${T}CI"
  cib 0 no-stack-ignores-ancestor --pr 8 --worktree "$W" --no-wait
  cib 3 stack-inherited-red --pr 8 --stack --worktree "$W" --no-wait \
    && expect_last stack-inherited-red "blockedOn: CI fail on #7 (web): npm ci failed (run 702)"
  printf '| 2026-10-01T05:00:00Z | T2 | CI | #7 web | "waive web on #7, the fix lands in T2" (chat) | recorder: #7 web red waived | waiver |\n' > "$W/w.row"
  awk -v row="$(cat "$W/w.row")" '{print} /^\|---\|---\|---\|---\|---\|---\|---\|$/ && !d {print row; d=1}' "$W/docs/build/LEDGER.md" > "$W/L.tmp" && mv "$W/L.tmp" "$W/docs/build/LEDGER.md"
  newstub; view 8 bbb8888000 OPEN demo/T1 demo/T2; view 7 aaa7777000 OPEN demo/base demo/T1; headpr demo/T1 7
  checks 8 "" "python${T}pass${T}$(run_url 801)${T}${T}CI"
  checks 7 "" "python${T}pass${T}$(run_url 701)${T}${T}CI" "web${T}fail${T}$(run_url 702)${T}npm ci failed${T}CI"
  cib 0 stack-waived --pr 8 --stack --ledger "$W/docs/build/LEDGER.md" --worktree "$W" --no-wait \
    && expect_last stack-waived "ci: pass #8@bbb8888 (python 801) · stack: #7 pass · waived: #7 web"
  # …but the waiver names #7 only: the same red on #8 itself still blocks
  newstub; view 8 bbb8888000 OPEN demo/T1 demo/T2; checks 8 "" "web${T}fail${T}$(run_url 803)${T}npm ci failed${T}CI"
  cib 3 waiver-is-per-pr --pr 8 --ledger "$W/docs/build/LEDGER.md" --worktree "$W" --no-wait

  # --ledger --ticket: BUILD_INDEX PR cell; PHASE LOG fallback; marker → chainTip PR; unresolvable → 5
  W3="$(mkrepo)"; L3="$W3/docs/build/LEDGER.md"
  printf '| 1 | T1 | ticket | `demo/T1` | **#7** | demo/base | 2026-10-01 | — | — | n-a | runs/T1.md | x |\n' >> "$W3/docs/build/BUILD_INDEX.md"
  printf -- '- 2026-10-01 — **T2** done — demo/T2 · PR #9 · demo/T1 · second\n' >> "$L3"
  setkey "$L3" chainTip demo/T2
  newstub; view 7 abc7000000; view 9 abc9000000; headpr demo/T2 9; view 11 abc1100000
  # the chainTip fallback applies only to lastCompleted (chainTip is its branch)
  setkey "$L3" lastCompleted T3; setkey "$L3" chainTip demo/T3; headpr demo/T3 11
  checks 11 "" "python${T}pass${T}$(run_url 111)${T}${T}CI"
  cib 0 ledger-chaintip-last --ledger "$L3" --ticket T3 --no-wait && expect_last ledger-chaintip-last "ci: pass #11@abc1100 (python 111)"
  cib 5 ledger-chaintip-not-last --ledger "$L3" --ticket T4 --no-wait
  setkey "$L3" chainTip demo/T2
  checks 7 "" "python${T}pass${T}$(run_url 71)${T}${T}CI"; checks 9 "" "python${T}pass${T}$(run_url 91)${T}${T}CI"
  cib 0 ledger-index --ledger "$L3" --ticket T1 --no-wait && expect_last ledger-index "ci: pass #7@abc7000 (python 71)"
  cib 0 ledger-phaselog --ledger "$L3" --ticket T2 --no-wait && expect_last ledger-phaselog "ci: pass #9@abc9000 (python 91)"
  cib 0 ledger-marker --ledger "$L3" --ticket GATE-G1 --no-wait && expect_last ledger-marker "ci: pass #9@abc9000 (python 91)"
  setkey "$L3" chainTip demo/nowhere
  cib 5 ledger-unresolvable --ledger "$L3" --ticket T5 --no-wait
  cib 0 ledger-marker-no-pr --ledger "$L3" --ticket SETUP --no-wait
  case "$LAST" in "ci: not-applicable"*) : ;; *) fail "ci-boundary ledger-marker-no-pr: last line '$LAST'";; esac

  # repo hook: delegated with --pr <n> --json <path>; its exit code passes through
  mkdir -p "$W3/docs/build/tools"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" > "%s/hook.args"\nexit 4\n' "$W3" > "$W3/docs/build/tools/ci_boundary.sh"
  newstub
  cib 4 repo-hook --pr 7 --worktree "$W3" --json "$W3/h.json"
  [ "$(cat "$W3/hook.args" 2>/dev/null)" = "--pr 7 --json $W3/h.json" ] || fail "ci-boundary repo-hook: args '$(cat "$W3/hook.args" 2>/dev/null)'"
  # 0.5.1 (SEED-02b): --ledger / --interval / --max-wait / --no-wait reach a hook whose file names them; a hook
  # that names none still gets exactly --pr <n> --json <path>, whatever the caller passed
  cib 4 repo-hook-legacy --pr 7 --worktree "$W3" --ledger "$L3" --interval 5 --no-wait --json "$W3/h.json"
  [ "$(cat "$W3/hook.args" 2>/dev/null)" = "--pr 7 --json $W3/h.json" ] || fail "ci-boundary repo-hook-legacy: a hook that names no flag got '$(cat "$W3/hook.args" 2>/dev/null)'"
  printf '#!/usr/bin/env bash\n# usage: ci_boundary.sh --pr N --json P [--ledger PATH] [--interval S] [--max-wait S | --no-wait]\nprintf "%%s\\n" "$*" > "%s/hook.args"\nexit 0\n' "$W3" > "$W3/docs/build/tools/ci_boundary.sh"
  cib 0 repo-hook-no-wait --pr 7 --worktree "$W3" --ledger "$L3" --no-wait --json "$W3/h.json"
  [ "$(cat "$W3/hook.args" 2>/dev/null)" = "--pr 7 --json $W3/h.json --ledger $L3 --no-wait" ] || fail "ci-boundary repo-hook-no-wait: args '$(cat "$W3/hook.args" 2>/dev/null)'"
  cib 0 repo-hook-wait --pr 7 --worktree "$W3" --interval 5 --max-wait 30 --json "$W3/h.json"
  [ "$(cat "$W3/hook.args" 2>/dev/null)" = "--pr 7 --json $W3/h.json --interval 5 --max-wait 30" ] || fail "ci-boundary repo-hook-wait: args '$(cat "$W3/hook.args" 2>/dev/null)'"
  cib 0 repo-hook-defaults --pr 7 --worktree "$W3" --json "$W3/h.json"
  [ "$(cat "$W3/hook.args" 2>/dev/null)" = "--pr 7 --json $W3/h.json" ] || fail "ci-boundary repo-hook-defaults: unrequested flags forwarded '$(cat "$W3/hook.args" 2>/dev/null)'"
  printf '#!/usr/bin/env bash\ncase "$*" in *--max-wait*) : ;; esac\nprintf "%%s\\n" "$*" > "%s/hook.args"\nexit 0\n' "$W3" > "$W3/docs/build/tools/ci_boundary.sh"
  cib 0 repo-hook-max-wait-only --pr 7 --worktree "$W3" --no-wait --json "$W3/h.json"
  [ "$(cat "$W3/hook.args" 2>/dev/null)" = "--pr 7 --json $W3/h.json --max-wait 0" ] || fail "ci-boundary repo-hook-max-wait-only: --no-wait not sent as --max-wait 0: '$(cat "$W3/hook.args" 2>/dev/null)'"
  rm -f "$W3/docs/build/tools/ci_boundary.sh"
  # 0.5.1: an empty description or link never shifts the next field (bash `read` merges adjacent tabs)
  newstub; view 7 abc1234def; checks 7 "" "web${T}fail${T}$(run_url 333)${T}${T}CI"
  cib 3 fail-no-description --pr 7 --worktree "$W" --no-wait && expect_last fail-no-description "blockedOn: CI fail on #7 (web): fail (run 333)"
  newstub; view 7 abc1234def; checks 7 "" "python${T}pass${T}${T}${T}CI"
  cib 0 pass-no-link --pr 7 --worktree "$W" --no-wait --json "$J"
  grep -qF '"name":"python","bucket":"pass","run_id":"","link":"","waived":false' "$J" || fail "ci-boundary pass-no-link: the checks record shifted ($(grep -o '"checks":.*' "$J" | cut -c1-160))"

  # replay: B4's four recorded red heads (#141 36092963615, #165 36312594389, #179 36346856782,
  # #185 36467709050) — each must stop the chain (exit 3)
  local stops=0 pr run
  for pr_run in 141:36092963615 165:36312594389 179:36346856782 185:36467709050; do
    pr="${pr_run%%:*}"; run="${pr_run#*:}"
    newstub; view "$pr" "head${pr}0000"; checks "$pr" "" "web${T}fail${T}$(run_url "$run")${T}recorded red run${T}CI"
    PATH="$STUBPATH" bash "$CIB" --pr "$pr" --worktree "$W" --no-wait >/dev/null 2>&1
    [ $? -eq 3 ] && stops=$((stops + 1))
  done
  [ "$stops" -eq 4 ] || fail "ci-boundary replay: $stops/4 recorded red heads stopped the chain"

  [ "$FAIL" -eq "$ok_before" ] && say "PASS ci-boundary"
}

# ── drive-build.sh ────────────────────────────────────────────────────────────
# drive <expected exit> <label> <repo> [extra args…] — leaves OUT / RC / CALLS (agent invocations)
drive() {
  local want="$1" label="$2" W="$3"; shift 3
  rm -f "$W/docs/build/LEDGER.md.agent-calls"
  OUT="$(STUB_LEDGER="$W/docs/build/LEDGER.md" PATH="$STUBPATH" bash "$DRIVE" --ledger "$W/docs/build/LEDGER.md" \
         --agent-cmd "bash $HERE/stub-agent.sh" --worktree "$W" --ci-interval 1 --ci-max-wait 0 --max-iters 6 "$@" 2>&1)"; RC=$?
  CALLS=0; [ -f "$W/docs/build/LEDGER.md.agent-calls" ] && CALLS="$(cat "$W/docs/build/LEDGER.md.agent-calls")"
  [ "$RC" -eq "$want" ] || { fail "drive-build $label: exit=$RC (want $want)"; printf '%s\n' "$OUT" | tail -5 | sed 's/^/      /'; return 1; }
  return 0
}
expect_calls() { [ "$CALLS" = "$2" ] || fail "drive-build $1: $CALLS agent dispatch(es) (want $2)"; }
green_stack() { newstub; view 7 aaa7000000 OPEN demo/base demo/T1; view 8 bbb8000000 OPEN demo/T1 demo/T2; headpr demo/T1 7
  checks 7 "" "python${T}pass${T}$(run_url 71)${T}${T}CI"; checks 8 "" "python${T}pass${T}$(run_url 81)${T}${T}CI"; }

test_drive_build() {
  local W ok_before=$FAIL
  W="$(mkrepo)"; green_stack
  drive 0 green-to-done "$W" && expect_calls green-to-done 2
  [ -f "$W/docs/build/logs/drive-build/ci-T1.json" ] || fail "drive-build green-to-done: no ci-T1.json record"

  W="$(mkrepo)"; green_stack; checks 7 "" "web${T}fail${T}$(run_url 72)${T}tests failed${T}CI"
  drive 2 red-stops-after-one "$W" && expect_calls red-stops-after-one 1
  printf '%s' "$OUT" | grep -qF "CI not green for T1" || fail "drive-build red-stops-after-one: no 'CI not green' message"
  # restart on the same red ledger: refuses before any dispatch
  drive 2 restart-on-red "$W" && expect_calls restart-on-red 0

  W="$(mkrepo)"; green_stack; checks 7 "" "python${T}pending${T}$(run_url 73)${T}${T}CI"
  drive 2 pending-past-wait "$W" && expect_calls pending-past-wait 1

  W="$(mkrepo)"; green_stack; setkey "$W/docs/build/LEDGER.md" projectStatus IN-PROGRESS
  drive 2 off-enum-status "$W" && expect_calls off-enum-status 0
  printf '%s' "$OUT" | grep -qF "not in the BM-LEDGER-02 enum" || fail "drive-build off-enum-status: message missing"

  W="$(mkrepo noci)"; newstub
  drive 0 no-ci-declared "$W" && expect_calls no-ci-declared 2

  W="$(mkrepo)"; green_stack
  STUB_AGENT_MODE=gate drive 0 gate-pending "$W" && expect_calls gate-pending 1
  printf '%s' "$OUT" | grep -qF "gate pending on 'T1'" || fail "drive-build gate-pending: message missing"

  W="$(mkrepo)"; green_stack; checks 7 "" "web${T}fail${T}$(run_url 72)${T}tests failed${T}CI"
  drive 0 no-ci-gate "$W" --no-ci-gate && expect_calls no-ci-gate 2
  printf '%s' "$OUT" | grep -qF "ci-gate=OFF (explicit opt-out --no-ci-gate)" || fail "drive-build no-ci-gate: opt-out not printed in the header"

  # --print-prompt: the manual tier gets the same checks, then the prompt; nothing dispatched
  W="$(mkrepo)"; green_stack; setkey "$W/docs/build/LEDGER.md" lastCompleted T1; setkey "$W/docs/build/LEDGER.md" nextTicket T2
  printf '| 1 | T1 | ticket | demo/T1 | #7 | demo/base | 2026-10-01 | — | — | n-a | runs/T1.md | x |\n' >> "$W/docs/build/BUILD_INDEX.md"
  drive 0 print-prompt "$W" --print-prompt && expect_calls print-prompt 0
  for kw in "('T2')" '`date -u` at that moment' 'Harness: <harness>/<model-id>/manual' 'the operator starts the next fresh session'; do
    printf '%s' "$OUT" | grep -qF "$kw" || fail "drive-build print-prompt: prompt lacks '$kw'"
  done
  checks 7 "" "web${T}fail${T}$(run_url 72)${T}tests failed${T}CI"; rm -f "$STUB_GH_DIR"/count-*
  drive 2 print-prompt-red "$W" --print-prompt && expect_calls print-prompt-red 0
  printf '%s' "$OUT" | grep -qF "date -u" && fail "drive-build print-prompt-red: printed a prompt past a red PR"

  # the headless prompt carries the same clock and harness sentences (the stub agent ignores its prompt,
  # so read the transcript drive-build logged for the unit)
  W="$(mkrepo)"; green_stack
  drive 0 headless-prompt "$W"
  for kw in '`date -u` at that moment' 'Harness: <harness>/<model-id>/headless' 'this external loop drives continuation'; do
    grep -qF "$kw" "$W/docs/build/LEDGER.md.prompt" 2>/dev/null || fail "drive-build headless-prompt: prompt lacks '$kw'"
  done

  # SK-04: the prompt names the ledger's recorded harness and what a different one means
  W="$(mkrepo)"; green_stack; setkey "$W/docs/build/LEDGER.md" lastCompleted T1; setkey "$W/docs/build/LEDGER.md" nextTicket T2
  awk '/^updatedAt:/ {print "harness:         claude-code/claude-opus-5-5/headless"} {print}' "$W/docs/build/LEDGER.md" > "$W/l.t" && mv "$W/l.t" "$W/docs/build/LEDGER.md"
  printf '| 1 | T1 | ticket | demo/T1 | #7 | demo/base | 2026-10-01 | — | — | n-a | runs/T1.md | x |\n' >> "$W/docs/build/BUILD_INDEX.md"
  drive 0 harness-prompt "$W" --print-prompt
  for kw in "harness(ledger)=claude-code/claude-opus-5-5/headless" "harness:\` reads 'claude-code/claude-opus-5-5/headless'" \
            "you are a harness switch (BM-HARNESS-01)" "record a PHASE LOG \`harness-switch\` entry quoting them, or stop and ask" \
            "write the operator digest (orchestrate-build §4, scripts/digest.sh)"; do
    printf '%s' "$OUT" | grep -qF -- "$kw" || fail "drive-build harness-prompt: lacks '$kw'"
  done

  # other --skill ledgers (research rows, no PRs) default to no CI gate
  W="$(mkrepo)"; newstub; setkey "$W/docs/build/LEDGER.md" lastCompleted A1
  drive 3 non-build-skill "$W" --skill synthesize-spec --max-iters 1 && expect_calls non-build-skill 1
  printf '%s' "$OUT" | grep -qF "ci-gate=off (--skill synthesize-spec" || fail "drive-build non-build-skill: gate note missing"

  [ "$FAIL" -eq "$ok_before" ] && say "PASS drive-build"
}

# ── digest.sh (SK-08) ─────────────────────────────────────────────────────────
test_digest() {
  local W ok_before=$FAIL DG="$SCRIPTS/digest.sh" day
  W="$(mkrepo)"; green_stack; checks 7 "" "web${T}fail${T}$(run_url 72)${T}tests failed${T}CI"
  setkey "$W/docs/build/LEDGER.md" lastCompleted T2; setkey "$W/docs/build/LEDGER.md" nextTicket T3
  awk '/^updatedAt:/ {print "harness:         devin-desktop/swe-2-high/manual"} {print}' "$W/docs/build/LEDGER.md" > "$W/l.t" && mv "$W/l.t" "$W/docs/build/LEDGER.md"
  printf '| 1 | T1 | ticket | demo/T1 | #7 | demo/base | 2026-10-01 | — | — | n-a | runs/T1.md | x |\n| 2 | T2 | ticket | demo/T2 | #8 | demo/T1 | 2026-10-01 | — | — | n-a | runs/T2.md | x |\n' >> "$W/docs/build/BUILD_INDEX.md"
  printf '7\tdemo/T1\n8\tdemo/T2\n31\tsomeone-else/side\n' > "$STUB_GH_DIR/list-open"
  printf '12\tHotfix the deploy script\t2026-09-30T22:10:00Z\tocto-other\tmain\n' > "$STUB_GH_DIR/list-merged"
  mkdir -p "$W/docs/tickets"; printf '| id | item | why deferred | unblocked by | how to verify | proxy now | kind | status |\n|---|---|---|---|---|---|---|---|\n| D-T1-9 | sign the venue contract | operator only | owner: the operator · trigger: 2026-10-08 | readout | none | P | OPEN |\n' > "$W/docs/tickets/DEFERRALS.md"
  OUT="$(PATH="$STUBPATH" bash "$DG" --ledger "$W/docs/build/LEDGER.md" --trigger wave --write \
        --spend "\$41.20 this wave (billing export read 2026-10-01T06:00Z)" --usage "6 runs; median 180k, max 240k tokens; no usage-limit event" 2>&1)"; RC=$?
  [ "$RC" -eq 0 ] || { fail "digest: exit=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /' | tail -20; }
  for kw in "operator digest (wave)" "**Harness:** devin-desktop/swe-2-high/manual" "#7 (T1) — RED — blockedOn: CI fail on #7 (web): tests failed (run 72)" \
            "#8 (T2) — pass — ci: pass #8@" '#12 "Hotfix the deploy script" → main, merged by octo-other at 2026-09-30T22:10:00Z' \
            "D-T1-9 — sign the venue contract — owner: the operator — trigger: 2026-10-08" "**Spend:** infrastructure \$41.20 this wave" \
            "agent usage 6 runs; median 180k" "exposed: no" "**Production anomalies read this session:** not reported by the session"; do
    printf '%s' "$OUT" | grep -qF -- "$kw" || fail "digest: lacks '$kw'"
  done
  printf '%s' "$OUT" | grep -qF "#31" && fail "digest: listed an open PR that is not a chain row as a chain PR"
  day="$(ls "$W/docs/build/reports/digests/" 2>/dev/null | head -1)"
  [ -n "$day" ] && grep -qF "#7 (T1) — RED" "$W/docs/build/reports/digests/$day" || fail "digest: --write did not append to reports/digests/<date>.md"
  printf '%s' "$day" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$' || fail "digest: file name '$day' is not <date -u +%F>.md"
  # a second digest appends (never rewrites) and lists merges since the first one
  PATH="$STUBPATH" bash "$DG" --ledger "$W/docs/build/LEDGER.md" --trigger pause --write >/dev/null 2>&1
  [ "$(grep -c '^## ' "$W/docs/build/reports/digests/$day")" = "2" ] || fail "digest: the second digest did not append"
  grep -qF "search merged:>=" "$STUB_GH_DIR/calls" || fail "digest: merges were not read since the previous digest"
  # the validator's secret scan covers reports/, and a digest never carries a token-shaped string
  bash "$HERE/../../build-memory/scripts/check-build-memory.sh" "$W" >/dev/null 2>&1
  grep -rE 'ghp_[A-Za-z0-9]{36}' "$W/docs/build/reports" >/dev/null && fail "digest: a token-shaped string was written"
  printf '13\tleak ghp_%s\t2026-10-01T01:00:00Z\tocto\tmain\n' "abcdefghijklmnopqrstuvwxyz0123456789" > "$STUB_GH_DIR/list-merged"
  OUT="$(PATH="$STUBPATH" bash "$DG" --ledger "$W/docs/build/LEDGER.md" --write --since 2026-01-01T00:00:00Z 2>&1)"; RC=$?
  { [ "$RC" -eq 3 ] && [ "$(grep -c '^## ' "$W/docs/build/reports/digests/$day")" = "2" ]; } || fail "digest: a secret-shaped token was not refused (exit=$RC)"
  OUT="$(PATH="$STUBPATH" bash "$DG" --ledger "$W/docs/build/LEDGER.md" --exposed yes --since 2026-10-01T02:00:00Z 2>&1)"; RC=$?
  { [ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -qF "exposed: yes — stop for rotation"; } || fail "digest: --exposed yes did not stop (exit=$RC)"
  # gh absent: the GitHub lines read unknown, never green
  if ! PATH=/usr/bin:/bin command -v gh >/dev/null 2>&1; then
    OUT="$(PATH=/usr/bin:/bin bash "$DG" --ledger "$W/docs/build/LEDGER.md" 2>&1)"
    printf '%s' "$OUT" | grep -qF "**CI of open chain PRs:** unknown (gh absent) — never treated as green" || fail "digest: gh absent not reported as unknown"
  fi
  [ "$FAIL" -eq "$ok_before" ] && say "PASS digest"
}

# ── monorepo memory root (0.5.4, BM-ROOT-03): the ledger lives in sub/proj/docs/build ─────────────
mkmono() {   # mkmono [noci] — mkrepo with its docs/ moved under sub/proj (the CI files stay at the toplevel)
  local W; W="$(mkrepo "${1:-}")"; mkdir -p "$W/sub/proj"; mv "$W/docs" "$W/sub/proj/docs"; printf '%s' "$W"
}
test_monorepo() {
  local W L F ok_before=$FAIL DG="$SCRIPTS/digest.sh" A B
  # ci-boundary: the required set and the repo hook are read under the ledger's own memory root
  W="$(mkmono)"; L="$W/sub/proj/docs/build/LEDGER.md"; green_stack
  checks 7 "" "python${T}pass${T}$(run_url 71)${T}${T}CI" "web${T}fail${T}$(run_url 72)${T}flaky${T}CI"
  mkdir -p "$W/sub/proj/docs/build/tools/record_policy"; printf 'python\n' > "$W/sub/proj/docs/build/tools/record_policy/ci_required.txt"
  cib 0 "monorepo required set" --pr 7 --ledger "$L" --no-wait && \
    { printf '%s' "$LAST" | grep -qF "ci: pass #7@" || fail "ci-boundary monorepo required set: last line '$LAST'"; }
  printf '#!/usr/bin/env bash\nexit 0\n' > "$W/sub/proj/docs/build/tools/ci_boundary.sh"
  cib 0 "monorepo hook" --pr 7 --ledger "$L" --no-wait && \
    { printf '%s' "$OUT" | grep -qF "delegating to the repo hook sub/proj/docs/build/tools/ci_boundary.sh" || fail "ci-boundary monorepo hook: not delegated"; }
  rm -f "$W/sub/proj/docs/build/tools/ci_boundary.sh"
  ( cd "$W" && BUILD_MEMORY_ROOT=sub/proj/docs/build PATH="$STUBPATH" bash "$CIB" --pr 7 --no-wait >/dev/null 2>&1 ) \
    || fail "ci-boundary monorepo: BUILD_MEMORY_ROOT (no --ledger) did not find the required set"

  # digest: the validator runs on the subproject (same verdict as the flat layout) and DEFERRALS is read there
  for v in flat mono; do
    if [ "$v" = flat ]; then W="$(mkrepo)"; F="$W/docs"; else W="$(mkmono)"; F="$W/sub/proj/docs"; fi
    newstub; mkdir -p "$F/tickets"
    printf '| id | item | why deferred | unblocked by | how to verify | proxy now | kind | status |\n|---|---|---|---|---|---|---|---|\n| D-T1-9 | sign the venue contract | operator only | owner: the operator · trigger: 2026-10-08 | readout | none | P | OPEN |\n' > "$F/tickets/DEFERRALS.md"
    OUT="$(PATH="$STUBPATH" bash "$DG" --ledger "$F/build/LEDGER.md" 2>&1)"
    printf '%s' "$OUT" | grep -qF "D-T1-9 — sign the venue contract" || fail "digest $v: DEFERRALS row not read"
    if [ "$v" = flat ]; then A="$(printf '%s\n' "$OUT" | grep -F '**Validator:**')"; else B="$(printf '%s\n' "$OUT" | grep -F '**Validator:**')"; fi
  done
  [ -n "$A" ] && [ "$A" = "$B" ] || fail "digest monorepo: validator line '$B' differs from the flat layout's '$A'"
  printf '%s' "$B" | grep -qF "exit 2" && fail "digest monorepo: the validator did not find the subproject memory root"

  # drive-build: the subproject root is exported to every unit and named in the prompt; the flat prompt is unchanged
  W="$(mkmono)"; L="$W/sub/proj/docs/build/LEDGER.md"; green_stack
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${BUILD_MEMORY_ROOT:-<unset>}" >> "%s/env.seen"\nexec bash "%s/stub-agent.sh" "$@"\n' "$W" "$HERE" > "$W/agent.sh"
  OUT="$(STUB_LEDGER="$L" PATH="$STUBPATH" bash "$DRIVE" --ledger "$L" --agent-cmd "bash $W/agent.sh" --worktree "$W" \
         --ci-interval 1 --ci-max-wait 0 --max-iters 6 2>&1)" || fail "drive-build monorepo: exit=$? — $(printf '%s' "$OUT" | tail -1)"
  [ "$(sort -u "$W/env.seen" 2>/dev/null)" = "sub/proj/docs/build" ] || fail "drive-build monorepo: units saw BUILD_MEMORY_ROOT='$(sort -u "$W/env.seen" 2>/dev/null | tr '\n' ' ')'"
  printf '%s' "$OUT" | grep -qF "memory root=sub/proj/docs/build (BUILD_MEMORY_ROOT, exported to every unit)" || fail "drive-build monorepo: header lacks the memory root"
  grep -qF "The build memory root is 'sub/proj/docs/build'" "$L.prompt" 2>/dev/null || fail "drive-build monorepo: prompt does not name the memory root"
  W="$(mkrepo)"; green_stack; drive 0 flat-prompt "$W"
  grep -qF "The build memory root is" "$W/docs/build/LEDGER.md.prompt" && fail "drive-build: the flat-layout prompt changed"
  [ "$FAIL" -eq "$ok_before" ] && say "PASS monorepo"
}

# ── external-state.sh: what moved outside the loop, and the ext:merge-in-order operating rule ─────
gx() { git -c user.email=op@x -c user.name=operator "$@" >/dev/null 2>&1; }
xs() {   # xs <expected exit> <label> [keyword…] — run external-state on $X (worktree) / $XL (ledger)
  local want="$1" label="$2" kw; shift 2
  OUT="$(PATH="$STUBPATH" bash "$SCRIPTS/external-state.sh" --ledger "$XL" --worktree "$X" --now 2026-11-11T12:00:00Z 2>&1)"; RC=$?
  [ "$RC" -eq "$want" ] || { fail "external-state $label: exit=$RC (want $want) — $(printf '%s' "$OUT" | tail -1)"; return; }
  for kw in "$@"; do printf '%s' "$OUT" | grep -qF -- "$kw" || fail "external-state $label: output lacks '$kw' — $(printf '%s' "$OUT" | tail -1)"; done
}
mkchain() {   # a bare origin, the build clone $X (main → demo/T1 → demo/T2, pushed), an operator clone $OP, a ledger $XL
  local D; D="$(mktemp -d)"; git init -q --bare "$D/origin.git"; git -C "$D/origin.git" symbolic-ref HEAD refs/heads/main
  X="$D/build"; gx clone "$D/origin.git" "$X"; ( cd "$X" && git checkout -q -b main && echo base > f && gx add f && gx commit -m base && gx push -u origin main )
  ( cd "$X" && git checkout -q -b demo/T1 && echo t1 > t1 && gx add t1 && gx commit -m T1 && git checkout -q -b demo/T2 && echo t2 > t2 && gx add t2 && gx commit -m T2 \
    && gx push origin demo/T1 demo/T2 && gx remote set-head origin main )
  OP="$D/op"; gx clone "$D/origin.git" "$OP"
  mkdir -p "$D/mem"; XL="$D/mem/LEDGER.md"
  printf '# Build ledger\n\n## CURRENT STATE\n\n```\nlastCompleted:   T2\nchainTip:        demo/T2\npinnedBaseSha:   %s\nmergePolicy:     OPERATOR\n```\n\n## GATE DECISIONS\n\n| date | ticket | gate | item | answer (verbatim) | consequence | kind |\n|---|---|---|---|---|---|---|\n\n## PHASE LOG — Round 1\n' "$(git -C "$X" rev-parse main)" > "$XL"
  printf '| seq | ticket | kind | branch | PR | base |\n|---|---|---|---|---|---|\n| 1 | T1 | ticket | demo/T1 | #7 | main |\n| 2 | T2 | ticket | demo/T2 | #8 | demo/T1 |\n' > "$D/mem/BUILD_INDEX.md"
  newstub   # the stub gh answers only the view-<n> files a case writes; otherwise git alone decides
}
botrow() {   # botrow <author-ERE list> [paths] — append an ext:bot-commits pre-authorization row
  awk -v a="$1" -v p="${2:-}" '{print} /^\|---\|---\|---\|---\|---\|---\|---\|$/ {print "| 2026-11-11T10:00:00Z | * | external | ext:bot-commits " a " | \"the formatter bot may push to chain branches\" (chat) | accepted shapes only" (p != "" ? " · paths: " p : "") " · expires: GATE-ACCEPT · voided-by: a bot commit that changes behaviour | pre-authorization |"}' "$XL" > "$XL.t" && mv "$XL.t" "$XL"
}
botgit() { env GIT_AUTHOR_NAME=ci-format-bot GIT_AUTHOR_EMAIL=ci-format-bot@example.invalid GIT_COMMITTER_NAME=ci-format-bot GIT_COMMITTER_EMAIL=ci-format-bot@example.invalid git "$@" >/dev/null 2>&1; }
preauth() {   # preauth <expires> — append the operator's ext:merge-in-order pre-authorization row
  awk -v e="$1" '{print} /^\|---\|---\|---\|---\|---\|---\|---\|$/ {print "| 2026-11-11T10:00:00Z | * | external | ext:merge-in-order | \"merge the chain bottom-up yourself is fine, I will do it\" (chat) | operator merges chain PRs in order, then rebases or merges main into the rest · expires: " e " · voided-by: an out-of-order merge | pre-authorization |"}' "$XL" > "$XL.t" && mv "$XL.t" "$XL"
}
test_external_state() {
  local ok_before=$FAIL
  mkchain; xs 0 clean "external: clean"
  ( cd "$OP" && echo other > other && gx add other && gx commit -m "someone else's work" && gx push origin main ); gx -C "$X" fetch -q origin
  xs 0 default-advanced "default-advanced" "external: informational"
  # (a) the operator merges the bottom chain PR (merge commit) — a block without the rule, expected with it
  ( cd "$OP" && gx fetch origin && gx merge --no-ff -m "Merge PR #7" origin/demo/T1 && gx push origin main ); gx -C "$X" fetch -q origin
  xs 3 merged-unauthorized "chain-merged(T1)" "blockedOn: external — chain-merged" "no live ext:merge-in-order pre-authorization"
  newstub; OUT="$(PATH="$STUBPATH" bash "$SCRIPTS/digest.sh" --ledger "$XL" --worktree "$X" 2>&1)"
  printf '%s' "$OUT" | grep -qF "chain descends from it: NO — an off-stack merge or a rebase: a blockedOn for the operator — blockedOn: external — chain-merged(T1)" \
    || fail "external-state: the digest's default-branch line lacks the blockedOn event"
  preauth GATE-ACCEPT; xs 0 merged-preauthorized "external: expected — chain-merged" "ext:merge-in-order, expires GATE-ACCEPT"
  newstub; OUT="$(PATH="$STUBPATH" bash "$SCRIPTS/digest.sh" --ledger "$XL" --worktree "$X" 2>&1)"
  printf '%s' "$OUT" | grep -qF "chain descends from it: NO — external: expected — chain-merged(T1)" \
    || fail "external-state: the digest's default-branch line does not read expected under the rule"
  sed -i.b 's/^mergePolicy:     OPERATOR/mergePolicy:     NONE/' "$XL"; xs 3 merged-policy-none "mergePolicy is 'NONE'"
  sed -i.b 's/^mergePolicy:     NONE/mergePolicy:     OPERATOR/' "$XL"
  sed -i.b 's/expires: GATE-ACCEPT/expires: T2/' "$XL"; xs 3 merged-expired "expired: T2 has landed"
  sed -i.b 's/expires: T2/expires: 2026-11-10/' "$XL"; xs 3 merged-date-expired "expired 2026-11-10"
  sed -i.b 's/expires: 2026-11-10/expires: GATE-ACCEPT/' "$XL"
  # ... then rebases the rest onto main and force-pushes: patch-equivalent → expected; the build syncs → clean
  ( cd "$OP" && gx fetch origin && git checkout -q -b demo/T2 origin/demo/T2 && gx rebase origin/main && gx push -f origin demo/T2 ); gx -C "$X" fetch -q origin
  xs 0 rebased-preauthorized "rebased-onto-default(demo/T2)" "external: expected"
  ( cd "$X" && git checkout -q demo/T2 && git reset -q --keep origin/demo/T2 ); xs 0 synced "external: clean"
  # (b) a foreign commit on the remote chain branch — a block even under the rule
  ( cd "$OP" && echo bot > bot && gx add bot && gx commit -m "style: format" && gx push origin demo/T2 ); gx -C "$X" fetch -q origin
  xs 3 foreign "foreign-commits(demo/T2:" "operator" "blockedOn: external — foreign-commits(demo/T2: "
  newstub; OUT="$(PATH="$STUBPATH" bash "$SCRIPTS/digest.sh" --ledger "$XL" --worktree "$X" 2>&1)"
  printf '%s' "$OUT" | grep -qF "chain descends from it: yes — blockedOn: external — foreign-commits(demo/T2: " \
    || fail "external-state: the digest's default-branch line does not carry the foreign-commit block"
  # the operator merges main into the chain branch instead of rebasing: expected under the rule
  mkchain; preauth GATE-ACCEPT
  ( cd "$OP" && echo other > other && gx add other && gx commit -m other && gx push origin main && git checkout -q -b demo/T2 origin/demo/T2 \
    && gx merge --no-ff -m "Merge main" origin/main && gx push origin demo/T2 ); gx -C "$X" fetch -q origin
  xs 0 default-merged-in "default-merged-in(demo/T2)" "external: expected"

  # squash merges (git only): the "(#7)" subject + patch-id, then a rebase --onto that drops T1's commits
  mkchain
  ( cd "$OP" && gx fetch origin && gx merge --squash origin/demo/T1 && gx commit -m "T1 work (#7)" && gx push origin main ); gx -C "$X" fetch -q origin
  xs 3 squash-unauthorized "chain-merged(T1)" "squash" "(#7) + patch-id" "no live ext:merge-in-order"
  preauth GATE-ACCEPT; xs 0 squash-preauthorized "external: expected — chain-merged(T1)"
  ( cd "$OP" && git checkout -q -b demo/T2 origin/demo/T2 && gx rebase --onto origin/main origin/demo/T1 demo/T2 && gx push -f origin demo/T2 ); gx -C "$X" fetch -q origin
  xs 0 squash-rebase-onto "rebased-onto-default(demo/T2)" "external: expected"
  printf '%s' "$OUT" | grep -qF "foreign-rewrite" && fail "external-state squash-rebase-onto: the merged row's dropped commits read as a foreign rewrite"
  ( cd "$X" && git checkout -q demo/T2 && git reset -q --keep origin/demo/T2 ); xs 0 squash-synced "external: clean"
  ( cd "$OP" && git checkout -q main && echo more > more && gx add more && gx commit -m "other work (#99)" && gx push origin main ); gx -C "$X" fetch -q origin
  xs 0 squash-integrated "default-advanced"
  # a squash, then the operator merges main into the remaining branch instead of rebasing it
  mkchain; preauth GATE-ACCEPT
  ( cd "$OP" && gx fetch origin && gx merge --squash origin/demo/T1 && gx commit -m "T1 work (#7)" && gx push origin main \
    && git checkout -q -b demo/T2 origin/demo/T2 && gx merge --no-ff -m "Merge main" origin/main && gx push origin demo/T2 ); gx -C "$X" fetch -q origin
  xs 0 squash-main-merge "chain-merged(T1)" "default-merged-in(demo/T2)" "external: expected"
  # a squash whose subject carries no PR number: the patch-id alone recognizes it
  mkchain
  ( cd "$OP" && gx fetch origin && gx merge --squash origin/demo/T1 && gx commit -m "Land the first ticket" && gx push origin main ); gx -C "$X" fetch -q origin
  xs 3 squash-patch-id "chain-merged(T1)" "(patch-id)"
  # a squash that is not a bottom prefix (T2's row merged, T1's not) is partial
  mkchain
  ( cd "$OP" && gx fetch origin && echo unrelated > u && gx add u && gx commit -m "unrelated (#8)" && gx push origin main ); gx -C "$X" fetch -q origin
  preauth GATE-ACCEPT; xs 3 squash-out-of-order "chain-merged-partial"

  # gh: PR state and retargets (stub gh answers view-<n> as tab-separated state, mergeCommit, base, head, headOid, mergedAt)
  mkchain
  ( cd "$OP" && gx fetch origin && gx merge --squash origin/demo/T1 && gx commit -m "Land T1" && gx push origin main ); gx -C "$X" fetch -q origin
  printf 'MERGED\t%s\tmain\tdemo/T1\t%s\t2026-11-11T09:00:00Z\n' "$(git -C "$X" rev-parse origin/main)" "$(git -C "$X" rev-parse demo/T1)" > "$STUB_GH_DIR/view-7"
  printf 'OPEN\t\tmain\tdemo/T2\t%s\t\n' "$(git -C "$X" rev-parse demo/T2)" > "$STUB_GH_DIR/view-8"
  xs 3 gh-unauthorized "chain-merged(T1)" "gh: #7 merged" "retargeted(#8: demo/T1 → main)"
  preauth GATE-ACCEPT; xs 0 gh-preauthorized "external: expected — chain-merged(T1); retargeted(#8"
  grep -qF "pr view 7 --json state,mergedAt,mergeCommit,headRefName,headRefOid,baseRefName" "$STUB_GH_DIR/calls" || fail "external-state gh: PR state not read with the documented fields"
  printf 'OPEN\t\trelease\tdemo/T2\t%s\t\n' "$(git -C "$X" rev-parse demo/T2)" > "$STUB_GH_DIR/view-8"
  xs 3 gh-retarget-elsewhere "retargeted(#8: demo/T1 → release)" "blockedOn: external"
  OUT="$(PATH="$STUBPATH" bash "$SCRIPTS/external-state.sh" --ledger "$XL" --worktree "$X" --no-gh 2>&1)"
  printf '%s' "$OUT" | grep -qF "gh disabled (--no-gh)" || fail "external-state --no-gh: not stated"

  # ext:bot-commits: a matching author's whitespace-only commit, merge of main, or allow-listed path is expected;
  # without the row, or for a behaviour change, it is a foreign commit
  mkchain
  ( cd "$OP" && gx fetch origin && git checkout -q -b demo/T2 origin/demo/T2 && printf 't2\n\n' > t2 && botgit add t2 && botgit commit -m "style: format" && gx push origin demo/T2 ); gx -C "$X" fetch -q origin
  xs 3 bot-unauthorized "foreign-commits(demo/T2:" "ci-format-bot"
  botrow ci-format-bot; xs 0 bot-whitespace "bot-commits(demo/T2:" "(whitespace-only)" "external: expected" "ext:bot-commits ci-format-bot"
  ( cd "$OP" && echo t3 > t2 && botgit add t2 && botgit commit -m "style: format" && gx push origin demo/T2 ); gx -C "$X" fetch -q origin
  xs 3 bot-semantic "foreign-commits(demo/T2:"
  mkchain; botrow 'ci-format-bot@example\.invalid'
  ( cd "$OP" && echo other > other && gx add other && gx commit -m other && gx push origin main && git checkout -q -b demo/T2 origin/demo/T2 \
    && botgit merge --no-ff -m "Merge main" origin/main && gx push origin demo/T2 ); gx -C "$X" fetch -q origin
  xs 0 bot-merge-of-main "(merge-of-default)" "external: expected"
  printf '%s' "$OUT" | grep -qF "default-merged-in" && fail "external-state bot-merge-of-main: a bot's main-merge also needed ext:merge-in-order"
  mkchain; botrow ci-format-bot '*.md'
  ( cd "$OP" && gx fetch origin && git checkout -q -b demo/T2 origin/demo/T2 && echo "# notes" > NOTES.md && botgit add NOTES.md && botgit commit -m "docs: regenerate" && gx push origin demo/T2 ); gx -C "$X" fetch -q origin
  xs 0 bot-paths "(paths-allowlisted)" "external: expected"
  [ "$FAIL" -eq "$ok_before" ] && say "PASS external-state"
}

say "orchestrate-build self-test"
test_ci_boundary
test_drive_build
test_digest
test_monorepo
test_external_state

if [ "$FAIL" -eq 0 ]; then
  say "ALL PASS"
  exit 0
fi
say "FAILURES above"
exit 1
