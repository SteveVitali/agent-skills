#!/usr/bin/env bash
# run-tests.sh — self-test for reconcile-build's scripts: check-backlog.sh (SK-23: verdict-aware gather,
# home liveness, the two sums, quote-aware CSV) and merge-dryrun.sh --ci (SK-24: the PR graph's check
# state). No network: orchestrate-build's stub `gh` answers from canned files.
#
# Usage:   run-tests.sh
# Exit codes: 0 — all cases pass; 1 — a case failed.
# Compatible with bash 3.2+ (macOS default). Writes only under its own temp dirs.

set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd)"
STUB_GH="$(cd "$HERE/../../orchestrate-build/tests" && pwd)/stub-gh.sh"
FAIL=0
say()  { printf '%s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; FAIL=1; }

# A build-memory tree with all eight verdicts × the D-row states (OPEN, PARTIAL, DONE).
mkbuild() {   # mkbuild <dir> [full]   (full = also the inconsistent rows)
  local D="$1"; mkdir -p "$D/docs/build" "$D/docs/tickets" "$D/docs/adr"
  cat > "$D/docs/tickets/DEFERRALS.md" <<'EOF'
| id | item | why deferred | unblocked by | how to verify | proxy now | status |
|---|---|---|---|---|---|---|
| D-T1-1 | live leg of R-3 | budget | operator go | rerun | fixture | OPEN |
| D-T1-2 | live leg of R-9 | budget | operator go | rerun | fixture | DONE 2026-09-20 (rerun green) — was: OPEN |
| D-T1-3 | staging leg of R-11 | infra | infra | rerun | fixture | PARTIAL |
| D-T1-4 | docs follow-up | time | T9 | read | none | OPEN |
EOF
  printf '# ADR-001: Different mechanism\n\n## Revisit trigger\nx\n' > "$D/docs/adr/ADR-001-different.md"
  printf '# ADR-002: Waive R-7\n\n## Revisit trigger\nwhen asked\n' > "$D/docs/adr/ADR-002-waive.md"
  cat > "$D/docs/build/COVERAGE_MATRIX.csv" <<'EOF'
id,level,spec_section,class,verdict,evidence,owning_tickets,tests,adrs,routing,note,required_domain,achieved_domain,owed_legs,accepted_scope
R-1,MUST,1,x,MET,a.py:1,T1,t1,,,,engineered,engineered,,
R-2,MUST,1,x,MET-DIFFERENTLY(ADR-001),a.py:2,T1,,ADR-001,,,engineered,engineered,,
R-3,MUST,1,x,MET-ENGINEERED(D-T1-1),a.py:3,T1,,,,,live-executed,fixture-verified,D-T1-1,
R-4,MUST,1,x,PARTIAL,a.py:4,T1,,,T9,,,,,
R-5,MUST,1,x,MISSING,,T1,,,T9,,,,,
R-6,MUST,1,x,AT-RISK-INTEGRATION,a.py:6,T1,,,T9,,,,,
R-7,MUST,1,x,WAIVED(ADR-002),,T1,,ADR-002,accepted,,,,,
R-8,RATIONALE,1,x,N/A-RATIONALE,,,,,,,,,,
R-11,MUST,1,x,"MET-ENGINEERED(D-T1-1, D-T1-3)",a.py:11,T1,,,,"two legs, one partial",staging-verified,engineered,"D-T1-1;D-T1-3",
EOF
  if [ "${2:-}" = full ]; then
    cat >> "$D/docs/build/COVERAGE_MATRIX.csv" <<'EOF'
R-9,MUST,1,x,MET-ENGINEERED(D-T1-2),a.py:9,T1,,,,,live-executed,engineered,D-T1-2,
R-10,MUST,1,x,MET,a.py:10,T1,,,,"cites D-T1-1, still owed",,,,
R-12,MUST,1,x,WAIVED(ADR-009),,T1,,,accepted,,,,,
EOF
  fi
  cat > "$D/docs/build/BACKLOG.csv" <<'EOF'
bl_id,title,type,sources,req_ids,package,blocks,landing,gate,size,status
BL-01,live legs,deferred-feature,D-T1-1 D-T1-3,R-3,x,—,T9,—,S,open
BL-02,docs,docs-drift,D-T1-4,—,x,—,T9,—,S,open
BL-03,"unbuilt, partly",defect,R-4;R-5;R-6,R-4,x,—,T9,—,M,open
BL-04,triggers,process,ADR-001+ADR-002,—,x,—,round 2,—,S,accepted
EOF
  printf '# Capstone closure\n\n**engineering closed: 4** of 8 · **requirement satisfied: 2** of 8\n' > "$D/docs/build/CAPSTONE_CLOSURE.md"
}
cb() { OUT="$(cd "$1" && bash "$SCRIPTS/check-backlog.sh" docs/build/BACKLOG.csv docs/build docs/tickets --json "$1/r.json" 2>&1)"; RC=$?; }

test_check_backlog() {
  local D ok_before=$FAIL
  # clean: MET-DIFFERENTLY is not demanded; MET-ENGINEERED is covered by its OPEN/PARTIAL legs; the
  # quoted verdict with a comma stays one cell; the sums recompute and match CAP.3's headline
  D="$(mktemp -d)"; mkbuild "$D"; cb "$D"
  [ "$RC" -eq 0 ] || { fail "check-backlog clean: exit=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /'; }
  printf '%s' "$OUT" | grep -qF "engineering closed 4 / 8 · requirement satisfied 2 / 8" || fail "check-backlog clean: sums line missing or wrong"
  printf '%s' "$OUT" | grep -qF "R-2 is owed" && fail "check-backlog clean: MET-DIFFERENTLY R-2 demanded as an owed source"
  printf '%s' "$OUT" | grep -qE "R-11|R-3 is owed" && fail "check-backlog clean: a MET-ENGINEERED row gathered by its own id or mis-split"
  grep -q '"engineeringClosed":4' "$D/r.json" || fail "check-backlog clean: JSON sums missing"
  # a backlog that already homed a MET-DIFFERENTLY id still passes (relaxation back to the contract)
  sed -e 's/^BL-04,triggers,process,ADR-001+ADR-002/BL-04,triggers,process,ADR-001+ADR-002+R-2/' "$D/docs/build/BACKLOG.csv" > "$D/b.t" && mv "$D/b.t" "$D/docs/build/BACKLOG.csv"
  cb "$D"; [ "$RC" -eq 0 ] || fail "check-backlog: a homed MET-DIFFERENTLY id now fails (exit=$RC)"

  # inconsistent: each issue kind
  D="$(mktemp -d)"; mkbuild "$D" full
  sed -e 's/^BL-02,docs,docs-drift,D-T1-4,—,x,—,T9,—,S,open/BL-02,docs,docs-drift,D-T1-4,—,x,—,T9,—,S,closed/' "$D/docs/build/BACKLOG.csv" > "$D/b.t" && mv "$D/b.t" "$D/docs/build/BACKLOG.csv"
  printf '# Readiness\n- step 1 — ticket: T9 — proof: TBD\n' > "$D/docs/build/OPERATIONAL_READINESS.md"
  cb "$D"
  [ "$RC" -eq 1 ] || fail "check-backlog inconsistent: exit=$RC (want 1)"
  for kw in "stale-met-engineered: R-9 is MET-ENGINEERED(D-T1-2) but D-T1-2 is DONE" "met-with-owed-leg: R-10 is MET but cites D-T1-1" \
            "waiver-adr: R-12 is WAIVED(ADR-009) but ADR-009 does not exist" "home-closed: D-T1-4 is still owed but its home BL-02 is closed" \
            "two-sums: CAPSTONE_CLOSURE.md says engineering closed = 4; the matrix gives 6" "readiness: OPERATIONAL_READINESS.md carries TBD"; do
    printf '%s' "$OUT" | grep -qF "$kw" || fail "check-backlog inconsistent: output lacks '$kw'"
  done
  # a dropped source and a double-tracked one
  D="$(mktemp -d)"; mkbuild "$D"
  printf 'BL-05,again,defect,R-4,—,x,—,T9,—,S,open\n' >> "$D/docs/build/BACKLOG.csv"
  sed -e '/^BL-02,/d' "$D/docs/build/BACKLOG.csv" > "$D/b.t" && mv "$D/b.t" "$D/docs/build/BACKLOG.csv"
  cb "$D"
  printf '%s' "$OUT" | grep -qF "missing: D-T1-4 is owed but appears in no backlog sources cell" || fail "check-backlog: dropped source not reported"
  printf '%s' "$OUT" | grep -qF "duplicate: R-4 appears in 2 backlog rows" || fail "check-backlog: double-tracked source not reported"
  [ "$FAIL" -eq "$ok_before" ] && say "PASS check-backlog"
}

test_merge_dryrun_ci() {
  local R BIN ok_before=$FAIL T; T="$(printf '\t')"
  R="$(mktemp -d)/repo"; mkdir -p "$R/.github/workflows"; printf 'on: [pull_request]\n' > "$R/.github/workflows/ci.yml"
  ( cd "$R" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm base && git branch -M main \
    && git checkout -qb b1 && printf 'a\n' > a && git add a && git -c user.email=t@t -c user.name=t commit -qm b1 \
    && git checkout -qb b2 && printf 'b\n' > b && git add b && git -c user.email=t@t -c user.name=t commit -qm b2 && git checkout -q main ) >/dev/null 2>&1
  BIN="$(mktemp -d)"; cp "$STUB_GH" "$BIN/gh"; chmod +x "$BIN/gh"
  STUB_GH_DIR="$(mktemp -d)"; export STUB_GH_DIR
  printf '7\n' > "$STUB_GH_DIR/head-b1"; printf '8\n' > "$STUB_GH_DIR/head-b2"
  printf 'aaa7000000\tOPEN\tmain\tb1\n' > "$STUB_GH_DIR/view-7"; printf 'bbb8000000\tOPEN\tb1\tb2\n' > "$STUB_GH_DIR/view-8"
  printf 'web%sfail%shttps://github.com/o/r/actions/runs/72/job/9%stests failed%sCI\n' "$T" "$T" "$T" "$T" > "$STUB_GH_DIR/checks-7"
  printf 'python%spass%shttps://github.com/o/r/actions/runs/81/job/9%s%sCI\n' "$T" "$T" "$T" "$T" > "$STUB_GH_DIR/checks-8"
  OUT="$(cd "$R" && PATH="$BIN:$PATH" bash "$SCRIPTS/merge-dryrun.sh" --ci main b1 b2 2>&1)"; RC=$?
  [ "$RC" -eq 0 ] || fail "merge-dryrun --ci: exit=$RC (a red PR is reported, not an error)"
  printf '%s' "$OUT" | grep -qF "b1 — clean · CI: FAIL — blockedOn: CI fail on #7 (web): tests failed (run 72)" || { fail "merge-dryrun --ci: no failing-check line for the red PR"; printf '%s\n' "$OUT" | sed 's/^/      /'; }
  printf '%s' "$OUT" | grep -qF "b2 — clean · CI: pass — ci: pass #8@bbb8000 (python 81)" || fail "merge-dryrun --ci: the green PR is not reported as pass"
  printf '%s' "$OUT" | grep -qE "CI read at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z" || fail "merge-dryrun --ci: no date -u of the read"
  printf '%s' "$OUT" | grep -qF "1 red PR(s)" || fail "merge-dryrun --ci: summary does not count the red PR"
  # without gh the state is unknown and the dry-run still completes
  if ! PATH=/usr/bin:/bin command -v gh >/dev/null 2>&1; then
    OUT="$(cd "$R" && PATH=/usr/bin:/bin bash "$SCRIPTS/merge-dryrun.sh" --ci main b1 2>&1)"; RC=$?
    { [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF "CI: unknown — gh absent"; } || fail "merge-dryrun --ci without gh: exit=$RC"
  fi
  [ "$FAIL" -eq "$ok_before" ] && say "PASS merge-dryrun-ci"
}

say "reconcile-build self-test"
test_check_backlog
test_merge_dryrun_ci
if [ "$FAIL" -eq 0 ]; then say "ALL PASS"; exit 0; fi
say "FAILURES above"; exit 1
