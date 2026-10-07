#!/usr/bin/env bash
# build.sh — history-mode fixtures (SK-16, B6 §6.2). Builds throw-away git repos from the v2-clean
# fixture, commits each case with GIT_COMMITTER_DATE (the shapes of real SIG commits: c2055d96,
# 307161ee, 305f94d5, 95c8a73f, 7a2ff9fa, 0a715fcc …) and asserts check-history.sh's verdict.
# One passing and one failing case per rule. No network.
#
# Usage:   build.sh            (run-tests.sh calls it)
# Exit codes: 0 — every case behaves; 1 — a case failed.
# Compatible with bash 3.2+ (macOS default). Writes only under its own temp dirs.

set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$(cd "$HERE/.." && pwd)"
SCRIPTS="$(cd "$HERE/../../scripts" && pwd)"
TPL="$(cd "$HERE/../../templates" && pwd)"
CH="$SCRIPTS/check-history.sh"
NOW="2026-09-30T00:00:00Z"
FAIL=0
fail() { printf '  ✗ %s\n' "$*"; FAIL=1; }

commit_at() {   # commit_at <repo> <iso> <msg>
  ( cd "$1" && git add -A && GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" \
      git -c user.email=t@t -c user.name=t commit -qm "$3" ) >/dev/null 2>&1
}
# The base repo: v2-clean + a populated GATE DECISIONS table, a readout, a jsonl record file, an owed
# deferral, a policy-governed db/sqitch.plan — committed at 2026-09-27T12:00:00Z.
BASE_REPO="$(mktemp -d)/repo"
make_base() {
  cp -R "$FIX/v2-clean" "$BASE_REPO"
  local L="$BASE_REPO/docs/build/LEDGER.md"
  awk '{print} /^\|---\|---\|---\|---\|---\|---\|$/ && !d {
        print "| 2026-09-20 | T1 | G1 | budget | \"yes\" (chat) | released |"
        print "| 2026-09-21 | T1 | G1 | scope | \"keep it small\" (chat) | narrowed |"
        print "| 2026-09-22 | T2 | G2 | rights | \"defer\" (chat) | deferred |"; d = 1 }' "$L" > "$L.t" && mv "$L.t" "$L"
  mkdir -p "$BASE_REPO/docs/build/readouts" "$BASE_REPO/docs/build/reports" "$BASE_REPO/db" "$BASE_REPO/docs/build/tools/record_policy"
  sed -e 's/^# <GATE-G<k> | GATE-ACCEPT | HUMAN-H<k>> readout/# GATE-G1 readout/' "$TPL/READOUT.md" > "$BASE_REPO/docs/build/readouts/GATE-G1.md"
  printf '{"id":1,"recorded_at":"2026-09-20T10:00:00Z"}\n{"id":2,"recorded_at":"2026-09-21T10:00:00Z"}\n' > "$BASE_REPO/docs/build/reports/events.jsonl"
  printf '| D-T1-1 | live check | budget gated | GATE-G1 | rerun | fixture | OPEN |\n' >> "$BASE_REPO/docs/tickets/DEFERRALS.md"
  printf 'seed 2026-09-01T00:00:00Z t <t@t> # seed\n' > "$BASE_REPO/db/sqitch.plan"
  printf 'append-only db/sqitch.plan\ndate db/sqitch.plan [0-9]{4}-[0-9]{2}-[0-9]{2}T\n' > "$BASE_REPO/docs/build/tools/record_policy/history.policy"
  ( cd "$BASE_REPO" && git init -q ) && commit_at "$BASE_REPO" 2026-09-27T12:00:00Z base
}
make_base
new_case() { W="$(mktemp -d)/repo"; cp -R "$BASE_REPO" "$W"; L="$W/docs/build/LEDGER.md"; B0="$(git -C "$W" rev-parse HEAD)"; }
edit() { awk "$2" "$1" > "$1.t" && mv "$1.t" "$1"; }
# expect <exit> <label> [keyword…] — run the range check on the case repo
expect() {
  local want="$1" label="$2" out rc kw; shift 2
  out="$(bash "$CH" --repo "$W" --range "$B0..HEAD" --now "$NOW" --no-hook 2>&1)"; rc=$?
  [ "$rc" -eq "$want" ] || { fail "history $label: exit=$rc (want $want)"; printf '%s\n' "$out" | sed 's/^/      /' | head -12; return; }
  for kw in "$@"; do printf '%s' "$out" | grep -qF -- "$kw" || { fail "history $label: output lacks '$kw'"; printf '%s\n' "$out" | sed 's/^/      /' | head -12; }; done
}
pl_entry() { printf -- '- %s — %s\n' "$1" "$2" >> "$L"; }

# ── append-only + append position (LEDGER regions) ──────────────────────────
new_case; pl_entry 2026-09-28 "T2 done — demo/t2 · PR #2 · demo/t1 · wire · **Verify:** green · chainTip → demo/t2 · next → DONE"
edit "$L" '{sub(/^nextTicket:[[:space:]]+T2/, "nextTicket:      DONE"); sub(/^updatedAt:.*/, "updatedAt:       2026-09-28T03:00:00Z")} {print}'
printf '| 02 | T2 | ticket | demo/t2 | #2 | demo/t1 | 2026-09-28 | — | none → none | n-a | runs/T2.md#evidence |\n' >> "$W/docs/build/BUILD_INDEX.md"
commit_at "$W" 2026-09-28T03:00:00Z "close T2"; expect 0 "clean close (append at EOF, value update, index row)"

new_case; edit "$L" '!/^\| 2026-09-2[01] /'                       # c2055d96: GATE DECISIONS rows deleted
commit_at "$W" 2026-09-28T03:00:00Z "record gate"; expect 1 "c2055d96 rows removed" "[append-only]" "GATE DECISIONS"

new_case; edit "$L" '{print} /^\|---\|---\|---\|---\|---\|---\|$/ && !d {print "| 2026-09-28 | T2 | G2 | rights | \"go\" (chat) | go |"; d = 1}'
commit_at "$W" 2026-09-28T03:00:00Z "gate"; expect 1 "307161ee top insertion" "[append-position]"

new_case; edit "$L" '{print} /^\| 2026-09-22 / {print "| 2026-09-28 | T2 | G2 | rights | \"go\" (chat) | go |"}'
commit_at "$W" 2026-09-28T03:00:00Z "gate"; expect 0 "gate row appended at the table end"

# ── record dates R1 / R2 / R3 / R5 / R6 ─────────────────────────────────────
new_case; pl_entry 2026-09-29 "T2 done — demo/t2 · PR #2 · summary"     # 305f94d5: entry dated +1 day
printf '| 02 | T2 | ticket | demo/t2 | #2 | demo/t1 | 2026-09-28 | — | — | n-a | runs/T2.md#evidence |\n' >> "$W/docs/build/BUILD_INDEX.md"
commit_at "$W" 2026-09-28T03:00:00Z "close T2"; expect 1 "305f94d5 +1 day" "[R1]" "2026-09-29"

new_case; pl_entry 2026-09-20 "T2 done — demo/t2 · PR #2 · summary"     # back-dated act
commit_at "$W" 2026-09-28T03:00:00Z "close"; expect 1 "R2 back-dated act" "[R2]"
new_case; pl_entry 2026-09-20 "T2 done — demo/t2 · PR #2 · retro: landed 09-20 per git 3f2a1c0 committer time"
commit_at "$W" 2026-09-28T03:00:00Z "close"; expect 0 "R2 back-dated act with retro:"

new_case; printf 'Date: 2026-10-19 (future-ok: scheduled: the publication window opens)\n' >> "$W/docs/build/readouts/GATE-G1.md"
commit_at "$W" 2026-09-28T03:49:00Z "schedule"; expect 0 "R5 inline future-ok"

new_case; printf 'T2 2026-10-02T12:00:00Z t <t@t> # planned in the future\n' >> "$W/db/sqitch.plan"     # sqitch line planned ahead
commit_at "$W" 2026-09-25T08:09:00Z "plan"; expect 1 "sqitch planned_at in the future (policy date)" "db/sqitch.plan" "[R1]"
new_case; printf 'T2 2026-09-25T08:08:00Z t <t@t> # planned now\n' >> "$W/db/sqitch.plan"
commit_at "$W" 2026-09-25T08:09:00Z "plan"; expect 0 "sqitch planned_at one minute before the commit"
new_case; printf 'top 2026-09-25T08:08:00Z t <t@t>\n' > "$W/db/t"; cat "$W/db/sqitch.plan" >> "$W/db/t"; mv "$W/db/t" "$W/db/sqitch.plan"
commit_at "$W" 2026-09-25T08:09:00Z "plan"; expect 1 "policy append-only file inserted at the top" "[append-position]"

new_case; printf 'allow db/sqitch.plan 2026-09-29T00:00:00Z replay-window\n' >> "$W/docs/build/tools/record_policy/history.policy"
printf 'R1 2026-10-10T03:35:00Z t <t@t> # replay-window\n' >> "$W/db/sqitch.plan"
commit_at "$W" 2026-09-28T03:00:00Z "plan"; expect 1 "expired allow entry no longer exempts" "allow entry expired 2026-09-29T00:00:00Z"
new_case; printf 'allow db/sqitch.plan 2026-10-11T00:00:00Z replay-window\n' >> "$W/docs/build/tools/record_policy/history.policy"
printf 'R1 2026-10-10T03:35:00Z t <t@t> # replay-window\n' >> "$W/db/sqitch.plan"
commit_at "$W" 2026-09-28T03:00:00Z "plan"; expect 0 "unexpired allow entry exempts"

new_case; pl_entry 2026-10-02 "T2 done — demo/t2 · PR #2 · summary"
commit_at "$W" 2026-10-02T03:00:00Z "close"; expect 1 "R6 commit later than the clock" "[R6]"

# ── readouts: append-only except Status:; signing (95c8a73f, 0a715fcc) ───────
RO="docs/build/readouts/GATE-G1.md"
new_case; edit "$W/$RO" '!/an agent must not sign or assume silence is/'                 # 95c8a73f shape
edit "$W/$RO" '{sub(/^Status: PENDING/, "Status: SIGNED")} {print}'
printf 'The gate passes: everything was verified.\nDate: 2026-10-19\n' >> "$W/$RO"
commit_at "$W" 2026-09-28T03:49:00Z "sign"; expect 1 "95c8a73f signing diff" "[readout]" "[R1]"
new_case; edit "$W/$RO" '{sub(/^- <item>.*/, "- [x] budget released")} {print}'                # 0a715fcc: a tick in place
commit_at "$W" 2026-09-28T03:49:00Z "tick"; expect 1 "0a715fcc in-place tick" "[readout]"
new_case; edit "$W/$RO" '{sub(/^Status: PENDING/, "Status: SIGNED")} {print}'
printf 'Operator decision (verbatim, received 2026-09-28T03:40:00Z via chat): "sign it"\n' >> "$W/$RO"
commit_at "$W" 2026-09-28T03:49:00Z "sign"; expect 0 "signing = Status line + appended block"
new_case; printf 'Date correction: the Date 2026-10-19 recorded above is wrong → true ≤ 2026-09-28T03:49Z (git 95c8a73f committer time)\n' >> "$W/$RO"
commit_at "$W" 2026-09-28T04:00:00Z "correct"; expect 0 "R3 correction line carrying the true date"

# ── a closed run ledger only gains lines (3fd7104) ───────────────────────────
# Closed = a dated `Closed:` stamp in the header (before the first `##`), where implement-spec writes it (0.5.1).
close_t1() {   # close_t1 <header line>: add it under the Spec line and commit it as the new base
  edit "$W/docs/build/runs/T1.md" '{print} /^- \*\*Spec \/ Base/ {print "'"$1"'"}'
  commit_at "$W" 2026-09-27T12:30:00Z "close"; B0="$(git -C "$W" rev-parse HEAD)"
}
rewrite_t1() { edit "$W/docs/build/runs/T1.md" '{sub(/^Seeded the schema; unit test green\. PR #1\./, "Seeded the schema.")} {print}'; }
new_case; close_t1 '- **Closed:** 2026-09-27T11:00:00Z'; rewrite_t1
commit_at "$W" 2026-09-28T03:00:00Z "rewrite"; expect 1 "3fd7104 closed run ledger rewritten" "[append-only]" "runs/T1.md"
new_case; close_t1 '- **Closed:** 2026-09-27T11:00:00Z'
printf '\n> Note 2026-09-28: the PR merged as #1 (git 3f2a1c0).\n' >> "$W/docs/build/runs/T1.md"
commit_at "$W" 2026-09-28T03:00:00Z "note"; expect 0 "closed run ledger with an appended note"
# 0.5.1 (SEED-02a): `- **Closed:** none.` in a body section (deferrals closed) is not a close (the d7cbc68e shape),
# nor is an undated header placeholder
new_case; printf '\n## Deferrals opened / closed\n- **Opened:** none.\n- **Closed:** none.\n' >> "$W/docs/build/runs/T1.md"
commit_at "$W" 2026-09-27T12:30:00Z "ledger"; B0="$(git -C "$W" rev-parse HEAD)"; rewrite_t1
commit_at "$W" 2026-09-28T03:00:00Z "rewrite"; expect 0 "a body 'Closed: none.' line does not close a run ledger"
new_case; close_t1 '- **Closed:** (at close)'; rewrite_t1
commit_at "$W" 2026-09-28T03:00:00Z "rewrite"; expect 0 "an undated Closed: placeholder does not close a run ledger"

# ── 0.5.1: policy comments — a `#` inside a token is kept; a lone ` # ` starts a comment (SEED-02a) ──
POLF="docs/build/tools/record_policy/history.policy"
gen_block() {   # a generated `### RETURN PASS — current` block at the end of RETURN PASS, committed as the new base
  edit "$L" '{print} /^\|---\|---\|---\|---\|$/ {print ""; print "### RETURN PASS — current"; print "- T9 owes the G1 readout"}'
  [ -n "${1:-}" ] && printf '%s\n' "$1" >> "$W/$POLF"
  commit_at "$W" 2026-09-27T12:30:00Z "generated block"; B0="$(git -C "$W" rev-parse HEAD)"
  edit "$L" '{sub(/^- T9 owes the G1 readout$/, "- (nothing owed)")} {print}'; commit_at "$W" 2026-09-28T03:00:00Z "regenerate"
}
new_case; gen_block ''; expect 1 "a generated region without an exempt rule is judged" "[append-only]" "RETURN PASS"
new_case; gen_block 'exempt docs/build/LEDGER.md ### RETURN PASS — current'; expect 0 "exempt with a '###' heading keeps the heading"
new_case; gen_block 'exempt docs/build/LEDGER.md ### RETURN PASS — current   # regenerated by the RETURN PASS tool'; expect 0 "exempt with a '###' heading and a lone ' # ' comment"
new_case; printf 'allow db/sqitch.plan 2026-10-11T00:00:00Z step #7\n' >> "$W/$POLF"
printf 'S8 2026-10-10T03:35:00Z t <t@t> # step #8\n' >> "$W/db/sqitch.plan"
commit_at "$W" 2026-09-28T03:00:00Z "plan"; expect 1 "an allow text keeps its '#7' (step #8 stays judged)" "[R1]"
new_case; printf 'allow db/sqitch.plan 2026-10-11T00:00:00Z step #7\n' >> "$W/$POLF"
printf 'S7 2026-10-10T03:35:00Z t <t@t> # step #7\n' >> "$W/db/sqitch.plan"
commit_at "$W" 2026-09-28T03:00:00Z "plan"; expect 0 "an allow text with '#7' exempts its own line"

# ── 0.5.1: the report keeps each field under its own key; an unwritable report is unknown (SEED-02c) ──
new_case; edit "$L" '!/^\| 2026-09-20 /'; commit_at "$W" 2026-09-28T03:00:00Z "drop a gate row"
bash "$CH" --repo "$W" --range "$B0..HEAD" --now "$NOW" --no-hook --json "$W/h.json" >/dev/null 2>&1
{ grep -qF '"commit":"","rule":"append-only","message":"line ' "$W/h.json" && ! grep -q '"message":""' "$W/h.json"; } \
  || fail "history report: an empty commit shifted rule/message ($(grep -o '"violations":.*' "$W/h.json" | cut -c1-160))"
bash "$CH" --repo "$W" --range "$B0..HEAD" --now "$NOW" --no-hook --json /dev/null/nope/h.json >/dev/null 2>&1; rc=$?
[ "$rc" -eq 5 ] || fail "history report: an unwritable --json path exit=$rc (want 5)"

# ── jsonl byte prefix (7a2ff9fa) ────────────────────────────────────────────
J="$W/docs/build/reports/events.jsonl"
new_case; J="$W/docs/build/reports/events.jsonl"; edit "$J" '{sub(/"id":1/, "\"id\":1,\"note\":\"x\"")} {print}'
commit_at "$W" 2026-09-28T03:00:00Z "rewrite"; expect 1 "7a2ff9fa jsonl rewrite" "[prefix]"
new_case; J="$W/docs/build/reports/events.jsonl"; printf '{"id":3,"recorded_at":"2026-09-28T02:59:00Z"}\n' >> "$J"
commit_at "$W" 2026-09-28T03:00:00Z "append"; expect 0 "jsonl append"

# ── living-archived LEDGER head ─────────────────────────────────────────────
mk_archive() {   # mk_archive <one-byte-off 0|1>
  mkdir -p "$W/docs/build/reports/ledger-archive"
  awk '/^> \*\*OPERATING MODE/ {f = 1} f && /^## CURRENT STATE/ {exit} f' "$L" > "$W/docs/build/reports/ledger-archive/head-R01.txt"
  [ "$1" = 1 ] && edit "$W/docs/build/reports/ledger-archive/head-R01.txt" '{sub(/Fresh session/, "Fresh  session")} {print}'
  edit "$L" '/^> \*\*OPERATING MODE/ {skip = 1} skip && /^## CURRENT STATE/ {skip = 0; print "<!-- Archived OPERATING MODE (Round 1) → docs/build/reports/ledger-archive/head-R01.txt -->"; print "> **OPERATING MODE — Round 2.** Orient with BM-ORIENT-01."; print ""} !skip'
}
new_case; mk_archive 0; commit_at "$W" 2026-09-28T03:00:00Z "rotate head"; expect 0 "living-archived, byte-identical archive"
new_case; mk_archive 1; commit_at "$W" 2026-09-28T03:00:00Z "rotate head"; expect 1 "living-archived, archive one byte off" "[living-archived]"
new_case; edit "$L" '!/^> \*\*OPERATING MODE/'; commit_at "$W" 2026-09-28T03:00:00Z "edit head"; expect 1 "head text removed without an archive" "[living-archived]"

# ── DEFERRALS row-annotate + rule 5 ─────────────────────────────────────────
D="$W/docs/tickets/DEFERRALS.md"
new_case; D="$W/docs/tickets/DEFERRALS.md"; edit "$D" '{sub(/\| OPEN \|$/, "| DONE 2026-09-28 (rerun green, PR #3) — was: OPEN |")} {print}'
commit_at "$W" 2026-09-28T03:00:00Z "flip"; expect 0 "deferral flipped: new status first, dated, old text kept"
new_case; D="$W/docs/tickets/DEFERRALS.md"; edit "$D" '{sub(/\| OPEN \|$/, "| OPEN — re-confirmed 2026-09-28: still gated |")} {print}'
commit_at "$W" 2026-09-28T03:00:00Z "annotate"; expect 0 "deferral annotated (status kept)"
new_case; D="$W/docs/tickets/DEFERRALS.md"; edit "$D" '{sub(/\| live check \|/, "| live probe |")} {print}'
commit_at "$W" 2026-09-28T03:00:00Z "flip"; expect 1 "deferral cell rewritten in place" "[rewritten]"
new_case; D="$W/docs/tickets/DEFERRALS.md"; edit "$D" '{sub(/\| OPEN \|$/, "| DONE (rerun green) — was: OPEN |")} {print}'
commit_at "$W" 2026-09-28T03:00:00Z "flip"; expect 1 "deferral status flipped without a date" "[status-date]"
new_case; D="$W/docs/tickets/DEFERRALS.md"; edit "$D" '{sub(/\| OPEN \|$/, "| DONE 2026-09-20 (rerun green) — was: OPEN |")} {print}'
commit_at "$W" 2026-09-28T03:00:00Z "flip"; expect 1 "deferral flip back-dated 8 days" "[R2]"
new_case; D="$W/docs/tickets/DEFERRALS.md"; edit "$D" '!/^\| D-T1-1 /'
commit_at "$W" 2026-09-28T03:00:00Z "drop"; expect 1 "deferral row deleted" "[removed]"
add_p_table() { printf '\n| id | item | why deferred | unblocked by | how to verify | proxy now | kind | status |\n|---|---|---|---|---|---|---|---|\n| D-T2-9 | sign the contract | operator only | the operator | readout | none | P | OPEN |\n' >> "$W/docs/tickets/DEFERRALS.md"; }
new_case; add_p_table; commit_at "$W" 2026-09-28T03:00:00Z "owe"; expect 0 "unscheduled P row added without the guards marker (warning)" "~ deferrals [rule-5]"
new_case; add_p_table; printf '<!-- build-memory-guards: 1 -->\n' >> "$W/docs/build/README.md"
commit_at "$W" 2026-09-28T03:00:00Z "owe"; expect 1 "unscheduled P row added under the guards marker" "[rule-5]"
# BL-61: the leading status decides — a DONE P row whose kept history says OPEN is not owed
new_case; printf '\n| id | item | why deferred | unblocked by | how to verify | proxy now | kind | status |\n|---|---|---|---|---|---|---|---|\n| D-T2-9 | sign the contract | operator only | the operator | readout | none | P | DONE 2026-09-28 (signed) — was: OPEN |\n' >> "$W/docs/tickets/DEFERRALS.md"
printf '<!-- build-memory-guards: 1 -->\n' >> "$W/docs/build/README.md"
commit_at "$W" 2026-09-28T03:00:00Z "done"; expect 0 "a DONE P row whose history names OPEN (BL-61)"

# ── BUILD_INDEX added rows ──────────────────────────────────────────────────
new_case; printf '| 02 | T2 | ticket | demo/t2 | PR pending | demo/t1 | 2026-09-28 | — | — | n-a | runs/T2.md |\n' >> "$W/docs/build/BUILD_INDEX.md"
commit_at "$W" 2026-09-28T03:00:00Z "index"; expect 1 "index row with PR pending" "[pr]"
new_case; printf '| 01 | T2 | ticket | demo/t2 | #2 | demo/t1 | 2026-09-28 | — | a|b | n-a | runs/T2.md |\n' >> "$W/docs/build/BUILD_INDEX.md"
commit_at "$W" 2026-09-28T03:00:00Z "index"; expect 1 "index row: unescaped | and reused seq" "[columns]" "[seq]"
new_case; edit "$W/docs/build/BUILD_INDEX.md" '{sub(/\| n-a \| runs\/T1.md#evidence \|/, "| run | runs/T1.md#evidence |")} {print}'
commit_at "$W" 2026-09-28T03:00:00Z "index"; expect 1 "landed index row rewritten" "[append-only]"

# ── manifest: round banner (V13), id registry, append-only sections ─────────
M="docs/tickets/00_MANIFEST.md"
new_case; edit "$W/$M" '{print} /02_T2__wire-consumers.md/ {print "| 3 | `03_T3__report.md` | report | ticket | report | — |"}'
printf '# T3\n' > "$W/docs/tickets/03_T3__report.md"
commit_at "$W" 2026-09-28T03:00:00Z "insert"; expect 1 "new chain row without a round banner (V13)" "[round-banner]"
new_case; printf '\n### Round 2 — 2026-09-28 · reporting\n\n| # | file | phase | kind | scope | gate |\n|---|---|---|---|---|---|\n| 3 | `03_T3__report.md` | report | ticket | report | — |\n' > "$W/r2.tmp"
edit "$W/$M" '{print} /02_T2__wire-consumers.md/ {while ((getline l < "'"$W/r2.tmp"'") > 0) print l}'
printf '# T3\n' > "$W/docs/tickets/03_T3__report.md"; rm -f "$W/r2.tmp"
commit_at "$W" 2026-09-28T03:00:00Z "extend"; expect 0 "new chain rows under a numbered round banner"
new_case; edit "$W/$M" '{print} /02_T2__wire-consumers.md/ {print "### Round 2 — 2026-09-28 · x"; print "| 3 | `03_T1__other-thing.md` | x | ticket | x | — |"}'
printf '# T1 again\n' > "$W/docs/tickets/03_T1__other-thing.md"
commit_at "$W" 2026-09-28T03:00:00Z "rebind"; expect 1 "chain id re-bound to another slug" "[id-registry]"

# ── frozen: executed contracts, landed ADRs ─────────────────────────────────
C1="$W/docs/tickets/01_T1__seed-schema.md"
new_case; C1="$W/docs/tickets/01_T1__seed-schema.md"; edit "$C1" '{sub(/^## Goal/, "## Goal (revised)")} {print}'
commit_at "$W" 2026-09-28T03:00:00Z "edit contract"; expect 1 "executed contract edited" "[frozen]"
new_case; C1="$W/docs/tickets/01_T1__seed-schema.md"; printf '\n> Amended 2026-09-28: the schema field is renamed — see the manifest amendment line.\n' >> "$C1"
commit_at "$W" 2026-09-28T03:00:00Z "amend"; expect 0 "executed contract amended by an appended note"
A1="docs/adr/ADR-001-seed-schema-shape.md"
new_case; edit "$W/$A1" '{sub(/^The build needs/, "The build wants")} {print}'
commit_at "$W" 2026-09-28T03:00:00Z "adr"; expect 1 "landed ADR edited" "[frozen]"
new_case; printf '\nStatus: Superseded by ADR-009 (2026-09-28)\n' >> "$W/$A1"
commit_at "$W" 2026-09-28T03:00:00Z "adr"; expect 1 "superseded by a missing ADR" "[superseded-by]"
new_case; sed -e 's/ADR-001: Seed schema shape/ADR-002: Reshape/' "$W/$A1" > "$W/docs/adr/ADR-002-reshape.md"
edit "$W/docs/adr/ADR-002-reshape.md" '{sub(/^- \*\*Date:\*\* .*/, "- **Date:** 2026-09-28")} {print}'
printf '\nStatus: Superseded by ADR-002 (2026-09-28)\n' >> "$W/$A1"
commit_at "$W" 2026-09-28T03:00:00Z "adr"; expect 0 "ADR superseded by an appended line"

# ── modes and exits ─────────────────────────────────────────────────────────
new_case; edit "$L" '{print} /^\|---\|---\|---\|---\|---\|---\|$/ && !d {print "| 2026-09-28 | T2 | G2 | x | \"go\" | go |"; d = 1}'
( cd "$W" && git add -A ) >/dev/null 2>&1
out="$(bash "$CH" --repo "$W" --staged --now "$NOW" --no-hook 2>&1)"; rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "[append-position]"; } || fail "history --staged top insertion: exit=$rc"
new_case; ( cd "$W" && git checkout -qb side ) >/dev/null 2>&1; pl_entry 2026-09-28 "T2 done — demo/t2 · PR #2 · side"
printf '| 02 | T2 | ticket | demo/t2 | #2 | demo/t1 | 2026-09-28 | — | — | n-a | runs/T2.md#evidence |\n' >> "$W/docs/build/BUILD_INDEX.md"
commit_at "$W" 2026-09-28T03:00:00Z "side"; ( cd "$W" && git checkout -q - && GIT_COMMITTER_DATE=2026-09-28T04:00:00Z GIT_AUTHOR_DATE=2026-09-28T04:00:00Z git -c user.email=t@t -c user.name=t merge -q --no-ff -m merge side ) >/dev/null 2>&1
out="$(bash "$CH" --repo "$W" --first-parent HEAD --now "$NOW" --no-hook 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || { fail "history --first-parent merge: exit=$rc"; printf '%s\n' "$out" | sed 's/^/      /' | head -8; }
S="$(mktemp -d)/repo"; mkdir -p "$S"; ( cd "$S" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m x ) >/dev/null 2>&1
bash "$CH" --repo "$S" --range HEAD..HEAD --no-hook >/dev/null 2>&1; [ $? -eq 2 ] || fail "history scratch repo: not exit 2"
SH="$(mktemp -d)/sh"; git clone -q --depth 1 "file://$BASE_REPO" "$SH" >/dev/null 2>&1
bash "$CH" --repo "$SH" --range HEAD..HEAD --no-hook >/dev/null 2>&1; [ $? -eq 5 ] || fail "history shallow clone: not exit 5"
new_case; bash "$CH" --repo "$W" --range nosuch..HEAD --no-hook >/dev/null 2>&1; [ $? -eq 5 ] || fail "history unresolvable range: not exit 5"
new_case; printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" > "%s/hook.args"\nexit 4\n' "$W" > "$W/docs/build/tools/memory_guard.sh"
bash "$CH" --repo "$W" --range "$B0..HEAD" >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 4 ] && [ "$(cat "$W/hook.args")" = "all --range $B0..HEAD" ]; } || fail "history repo hook: exit=$rc args='$(cat "$W/hook.args" 2>/dev/null)'"
# --replay judges every first-parent commit on its own: a clean close, then a deletion
new_case; pl_entry 2026-09-28 "T2 done — demo/t2 · PR #2 · s"
printf '| 02 | T2 | ticket | demo/t2 | #2 | demo/t1 | 2026-09-28 | — | — | n-a | runs/T2.md#evidence |\n' >> "$W/docs/build/BUILD_INDEX.md"
commit_at "$W" 2026-09-28T03:00:00Z "close T2"; edit "$L" '!/^\| 2026-09-20 /'; commit_at "$W" 2026-09-28T04:00:00Z "drop a gate row"
out="$(bash "$CH" --repo "$W" --replay "$B0..HEAD" --now "$NOW" 2>&1)"; rc=$?
{ [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c ' exit=0 *$')" = "1" ] && printf '%s' "$out" | grep -qF "exit=1 append-only[append-only]×1" \
  && printf '%s' "$out" | grep -qF "2 commit(s) judged, 1 with violations"; } || { fail "history --replay: exit=$rc"; printf '%s\n' "$out" | sed 's/^/      /'; }
# reached through check-build-memory.sh too
new_case; pl_entry 2026-09-29 "T2 done — demo/t2 · PR #2 · s"; commit_at "$W" 2026-09-28T03:00:00Z "c"
bash "$SCRIPTS/check-build-memory.sh" "$W" --range "$B0..HEAD" --now "$NOW" --no-hook >/dev/null 2>&1; [ $? -eq 1 ] || fail "check-build-memory --range does not reach history mode"

[ "$FAIL" -eq 0 ] && echo "PASS history"
exit "$FAIL"
