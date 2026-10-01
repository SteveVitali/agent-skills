#!/usr/bin/env bash
# run-tests.sh — self-test for orchestrate-build's scripts: ci-boundary.sh (SK-01), drive-build.sh's
# status-enum guard, CI gate, --print-prompt (SK-02) and harness line (SK-04), and digest.sh (SK-08). No network: a stub `gh` (stub-gh.sh) answers
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

say "orchestrate-build self-test"
test_ci_boundary
test_drive_build
test_digest

if [ "$FAIL" -eq 0 ]; then
  say "ALL PASS"
  exit 0
fi
say "FAILURES above"
exit 1
