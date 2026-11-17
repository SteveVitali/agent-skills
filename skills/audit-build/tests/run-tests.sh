#!/usr/bin/env bash
# run-tests.sh — self-test for audit-build's scripts:
#   audit-scope.sh  — since-last / last / tickets / range selection, the previous-audit read, errors.
#   audit-stats.py  — Q1 with Wilson intervals, precision, mutation kill rate, duplicate-subset kappa
#                     and Lincoln–Petersen, input validation; schema ↔ script enum consistency.
# No network. Writes only under its own temp dirs.
#
# Usage:   run-tests.sh
# Exit codes: 0 — all cases pass; 1 — a case failed.
# Compatible with bash 3.2+ (macOS default); needs git and python3.

set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCOPE="$HERE/../scripts/audit-scope.sh"
STATS="$HERE/../scripts/audit-stats.py"
SCHEMA="$HERE/../templates/finding.schema.json"
FAIL=0
say()  { printf '%s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; FAIL=1; }
ok()   { printf '  ✓ %s\n' "$*"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

tickets_of() { grep -v '^#' | awk -F'\t' 'NR > 1 {printf "%s ", $2}' | sed 's/ $//'; }

# A build-memory tree: four landed tickets, each on its own branch.
mkrepo() {   # mkrepo <dir>
  local D="$1"; mkdir -p "$D/docs/build/reports/audits"
  git -C "$D" init -q -b main 2>/dev/null || { git -C "$D" init -q; git -C "$D" checkout -q -b main; }
  git -C "$D" config user.email t@example.invalid; git -C "$D" config user.name t
  printf '<!-- build-memory: v2 -->\n# build\n' > "$D/docs/build/README.md"
  git -C "$D" add -A; git -C "$D" commit -q -m base
  local i
  for i in 1 2 3 4; do
    git -C "$D" checkout -q -b "b-t$i"; echo "$i" > "$D/f$i"; git -C "$D" add -A; git -C "$D" commit -q -m "t$i"
  done
  git -C "$D" checkout -q main; git -C "$D" merge -q --ff-only b-t4
  cat > "$D/docs/build/BUILD_INDEX.md" <<'EOF'
# BUILD_INDEX

| seq | ticket | kind | branch | PR | base | landed | ADRs | deferrals | live verification | evidence | harness |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | T1 | ticket | b-t1 | #1 | main | 2026-11-01 | — | — | fixture-only | runs/T1.md | impl/a |
| 2 | T2 | ticket | b-t2 | #2 | b-t1 | 2026-11-02 | — | — | fixture-only | runs/T2.md | impl/a |
| 3 | T3 | ticket | b-t3 | #3 | b-t2 | 2026-11-03 | — | — | fixture-only | runs/T3.md | impl/b |
| 4 | T4 | ticket | b-t4 | #4 | b-t3 | 2026-11-04 | — | — | fixture-only | runs/T4.md | impl/b |
EOF
}

say "audit-scope.sh"
R="$T/repo"; mkrepo "$R"
out="$(bash "$SCOPE" --root "$R" --since-last)"; [ "$(printf '%s\n' "$out" | tickets_of)" = "T1 T2 T3 T4" ] && ok "since-last with no previous audit = all rows" || fail "since-last/no-audit: $out"
printf '%s\n' "$out" | grep -q '^# previous-audit: none$' && ok "no previous audit reported as none" || fail "previous-audit none: $out"
printf '%s\n' "$out" | grep -q $'^seq\tticket\tbranch\tpr\tbase\tlanded\tharness$' && ok "TSV header" || fail "header"
printf -- '---\naudit-id: A20261102-abc1234\nmode: audit   # audit | evaluate\naudited-through: T2\n---\n' > "$R/docs/build/reports/audits/2026-11-02_A20261102-abc1234.md"
printf '# plan\naudited-through: T4\n' > "$R/docs/build/reports/audits/2026-11-05_E1.plan.md"
out="$(bash "$SCOPE" --root "$R")"; [ "$(printf '%s\n' "$out" | tickets_of)" = "T3 T4" ] && ok "since-last (default) after audited-through T2; plans ignored" || fail "since-last: $out"
printf '%s\n' "$out" | grep -q '^# previous-audit: A20261102-abc1234$' && ok "previous audit id parsed (comment stripped)" || fail "prev id: $out"
out="$(bash "$SCOPE" --root "$R" --last 2)"; [ "$(printf '%s\n' "$out" | tickets_of)" = "T3 T4" ] && ok "--last 2" || fail "last: $out"
out="$(bash "$SCOPE" --root "$R" --tickets T4,T1)"; [ "$(printf '%s\n' "$out" | tickets_of)" = "T1 T4" ] && ok "--tickets keeps BUILD_INDEX order" || fail "tickets: $out"
printf '%s\n' "$out" | grep -q $'^4\tT4\tb-t4\t#4\tb-t3\t2026-11-04\timpl/b$' && ok "row columns by header name" || fail "row: $out"
bash "$SCOPE" --root "$R" --tickets T1,T9 >/dev/null 2>&1; [ $? -eq 2 ] && ok "unknown ticket id → exit 2" || fail "unknown id exit"
out="$(bash "$SCOPE" --root "$R" --range b-t2..main 2>/dev/null)"; [ "$(printf '%s\n' "$out" | tickets_of)" = "T3 T4" ] && ok "--range b-t2..main" || fail "range: $out"
printf -- '---\naudit-id: A20261106-def5678\naudited-through: T7\n---\n' > "$R/docs/build/reports/audits/2026-11-06_A20261106-def5678.md"
bash "$SCOPE" --root "$R" >/dev/null 2>&1; [ $? -eq 2 ] && ok "audited-through not in BUILD_INDEX → exit 2" || fail "bad through exit"
rm "$R/docs/build/reports/audits/2026-11-06_A20261106-def5678.md"
bash "$SCOPE" --root "$R" --last x >/dev/null 2>&1; [ $? -eq 1 ] && ok "bad --last → exit 1" || fail "usage exit"
mkdir -p "$T/empty"; bash "$SCOPE" --root "$T/empty" >/dev/null 2>&1; [ $? -eq 2 ] && ok "missing BUILD_INDEX → exit 2" || fail "missing index exit"

say "audit-stats.py"
A="$T/audits"; mkdir -p "$A"
printf 'ticket\timplementer\tstratum\taudit_round\tauditor\tblind_guess\ttokens\n' > "$A/2026-11-07_A1.tickets.tsv"
printf 'T1\timpl/b\tconsumer\t1\taud/x\timpl-b:low\t1000\nT1\timpl/b\tconsumer\t2\taud/y\t-\t900\nT2\timpl/b\tconsumer\t1\taud/x\t-\t800\nT3\timpl/b\tconsumer\t1\taud/x\t-\t700\nT4\timpl/a\tprimitive\t1\taud/x\t-\t1200\n' >> "$A/2026-11-07_A1.tickets.tsv"
cat > "$A/2026-11-07_A1.findings.jsonl" <<'EOF'
{"id":"F1","audit_id":"A1","audit_round":1,"ticket":"T1","severity":"major","category":"boundary","origin":"implementer","claim":"x","evidence":{"location":"a:1","reproduction":"r"},"verdict":"confirmed"}
{"id":"F2","audit_id":"A1","audit_round":2,"ticket":"T1","severity":"major","category":"boundary","origin":"implementer","claim":"x","evidence":{"location":"a:1","reproduction":"r"},"verdict":"confirmed","duplicate_of":"F1"}
{"id":"F3","audit_id":"A1","audit_round":1,"ticket":"T2","severity":"major","severity_adjusted":"minor","category":"claims","origin":"in-ticket-review","claim":"y","evidence":{"location":"b:2","reproduction":"r"},"verdict":"confirmed"}
{"id":"F4","audit_id":"A1","audit_round":1,"ticket":"T3","severity":"blocker","category":"security","claim":"z","evidence":{"location":"c:3","reproduction":"r"},"verdict":"refuted"}
EOF
printf 'ticket\tsite\tkilled\nT1\ta:1\t1\nT2\tb:2\t1\nT3\tc:3\t1\nT3\tc:9\t0\n' > "$A/2026-11-07_A1.mutations.tsv"
J="$(python3 -I "$STATS" "$A" --json)"; rc=$?
[ $rc -eq 0 ] && ok "stats exit 0" || fail "stats rc=$rc"
chk() {   # chk <python expr over r> <label>
  printf '%s' "$J" | python3 -I -c "import json,sys; r=json.load(sys.stdin); sys.exit(0 if ($1) else 1)" && ok "$2" || fail "$2"
}
chk 'any(q["implementer"]=="impl/b" and q["stratum"]=="consumer" and q["k"]==1 and q["n"]==3 for q in r["q1"])' "Q1 k/n = 1/3 (round 1 only; adjusted minor and refuted blocker excluded)"
chk 'any(q["n"]==3 and q["wilson95"]==[0.061,0.792] for q in r["q1"])' "Wilson 95% for 1/3 = [0.061, 0.792]"
chk 'any(q["n"]==3 and q["mutation_kill_rate"]==0.75 for q in r["q1"])' "mutation kill rate 3/4"
chk 'r["precision"]["overall"]==0.75' "auditor precision 3 confirmed / 4 decided"
chk 'r["duplicates"]["tickets"]==1 and r["duplicates"]["matched"]==1 and r["duplicates"]["overlap"]==1.0 and r["duplicates"]["lincoln_petersen_total"]==1.0' "duplicate subset: matched, overlap, Lincoln–Petersen"
chk 'r["duplicates"]["kappa_major_plus"]==1.0' "kappa on one agreeing pair"
chk 'any(q["implementer"]=="impl/a" and q["k"]==0 and q["n"]==1 for q in r["q1"])' "clean ticket counts in the denominator"
python3 -I "$STATS" "$A" | grep -q '^## Q1' && ok "markdown render" || fail "render"
python3 -I "$STATS" "$A" --audit OTHER >/dev/null 2>&1; [ $? -eq 2 ] && ok "--audit filter with no match → exit 2" || fail "filter exit"
echo '{"id":"F9","audit_id":"A1","ticket":"T1","severity":"huge","category":"boundary","claim":"x","evidence":{},"verdict":""}' >> "$A/2026-11-07_A1.findings.jsonl"
python3 -I "$STATS" "$A" >/dev/null 2>&1; [ $? -eq 1 ] && ok "invalid finding → exit 1" || fail "invalid exit"

say "schema ↔ script consistency"
python3 -I - "$SCHEMA" "$STATS" <<'EOF' && ok "schema enums match audit-stats.py" || fail "schema/script enum mismatch"
import json, sys, ast
s = json.load(open(sys.argv[1]))["properties"]
src = open(sys.argv[2]).read(); tree = ast.parse(src)
vals = {n.targets[0].id: ast.literal_eval(n.value) for n in tree.body
        if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name) and n.targets[0].id in ("SEVERITIES", "CATEGORIES", "VERDICTS")}
assert set(vals["SEVERITIES"]) == set(s["severity"]["enum"])
assert set(vals["CATEGORIES"]) == set(s["category"]["enum"])
assert set(vals["VERDICTS"]) == set(s["verdict"]["enum"])
EOF

[ $FAIL -eq 0 ] && say "audit-build tests: all passed" || say "audit-build tests: FAILED"
exit $FAIL
