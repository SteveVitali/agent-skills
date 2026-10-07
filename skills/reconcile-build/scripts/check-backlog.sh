#!/usr/bin/env bash
# check-backlog.sh — verify a build's BACKLOG.csv is complete, non-duplicating and verdict-aware. (BM-RECON-01.)
#
# The backlog's contract: every owed thing lands in EXACTLY ONE row's `sources` cell, and that home is live
# while the thing is owed. This script gathers the owed-thing ids from the committed build memory and checks
# each appears exactly once, that its home row is not `closed` while the source is still owed, that bl_ids
# are unique and statuses valid, and that the coverage matrix's verdicts are consistent with DEFERRALS
# (BM-VERDICT-01). It prints the two sums and compares them with CAP.3's headline.
#
# Usage:
#   check-backlog.sh [backlog_csv] [build_dir] [tickets_dir] [--json PATH] [--allow-empty]
#
# Arguments (all optional):
#   backlog_csv  — the backlog (default: docs/build/BACKLOG.csv)
#   build_dir    — docs/build (default: the backlog's own directory)
#   tickets_dir  — docs/tickets (default: <build_dir>/../tickets)
#   --json PATH  — the report (default: a unique mktemp file; the path is printed)
#   --allow-empty — accept a gather of 0 expected ids as complete (a build that genuinely owes nothing)
#   The ADR directory is <build_dir>/../adr, resolved to an absolute path (so build_dir `.` works from
#   docs/build). Run from docs/build as `check-backlog.sh BACKLOG.csv`, the defaults find everything.
#
# Sources gathered (id-bearing), by BM-VERDICT-01:
#   - DEFERRALS.md rows whose status is OPEN or PARTIAL                 (ids D-<TICKET>-<n>)
#   - COVERAGE_MATRIX.csv rows whose verdict is PARTIAL, MISSING or AT-RISK-INTEGRATION (the id column)
#     · MET-ENGINEERED(D-…;…) is covered by its owed-leg D-rows (gathered above); each must be OPEN/PARTIAL,
#       else the issue `stale-met-engineered`
#     · WAIVED(ADR-nnn) is covered by that ADR's revisit-trigger row; a missing ADR is the issue `waiver-adr`
#     · MET-DIFFERENTLY(ADR-…) is not gathered (its ADR is); MET and N/A-RATIONALE are not gathered
#     · a MET row that cites an OPEN/PARTIAL D-row is the issue `met-with-owed-leg`
#   - docs/adr/ADR-*.md                                                  (ids ADR-NNN; each has a revisit trigger)
#   (OPEN FINDINGS and register rows have no stable ids; they are a reviewer check, reported as a reminder.)
#   The matrix is read with a quote-aware CSV reader (a `"…"` cell may hold commas); verdict parameters are
#   `;`-separated (a legacy `,` inside the parentheses is tolerated).
#
# Checks:
#   - every gathered source id appears in exactly one BACKLOG.csv `sources` cell (0 = dropped; >1 = double-tracked)
#   - home liveness: a still-owed source's row is not `closed` (`home-closed`)
#   - bl_id column is unique; status column ∈ {open, closed, accepted}
#   - the two sums (engineering closed = MET + MET-DIFFERENTLY + MET-ENGINEERED; requirement satisfied =
#     MET + MET-DIFFERENTLY) recomputed from the matrix equal CAPSTONE_CLOSURE.md's headline when it states them
#   - OPERATIONAL_READINESS.md carries no TBD
#   - inputs: tickets_dir holds DEFERRALS.md; a build_dir other than the backlog's own directory is an
#     issue when the backlog's directory holds the build records (COVERAGE_MATRIX.csv or LEDGER.md) —
#     the usual sign of a wrong build_dir (`inputs`)
#
# DEFERRALS statuses are read by the LEADING status of the row's last cell (markup such as `**OPEN**`
# stripped): its first word when canonical, else the earliest canonical status in capitals, else the
# earliest in any case — "DONE 2026-09-20 — was: OPEN" is DONE (the rule check-build-memory.sh uses).
# CSV files are read quote-aware (a quoted cell may hold commas or doubled quotes); CRLF line endings
# are tolerated in every input.
#
# An empty gather is never green (BL-79): when no expected id is gathered — the usual cause is a wrong
# build_dir / tickets_dir, not a build that owes nothing — the script prints "0 expected sources —
# refusing to call this complete" and exits 3. Pass --allow-empty when the build truly owes nothing.
#
# Output: human summary to stdout; JSON (backlog-check/2) to --json PATH or a unique temp file
# (`"vacuous":true` on an empty gather).
# Exit codes: 0 — complete + consistent · 1 — issues found · 2 — no backlog file (or a named directory
# is missing) · 3 — vacuous: 0 expected ids gathered (never green; see --allow-empty).
# Read-only. Compatible with bash 3.2+ (macOS default). No associative arrays, no mapfile.

set -o pipefail

JSON=""; POS=(); ALLOW_EMPTY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON="${2:-}"; shift 2 ;;
    --allow-empty) ALLOW_EMPTY=1; shift ;;
    -h|--help) awk 'NR > 1 && !/^#/ {exit} NR > 1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    *) POS+=("$1"); shift ;;
  esac
done
CSV="${POS[0]:-docs/build/BACKLOG.csv}"
BUILD="${POS[1]:-$(dirname "$CSV")}"
TICKETS="${POS[2]:-$BUILD/../tickets}"
[ -n "$JSON" ] || JSON="$(mktemp "${TMPDIR:-/tmp}/backlog-check.XXXXXXXX")" || exit 2

absent() { echo "check-backlog: $1"; printf '{"schema":"backlog-check/2","backlog":"%s","present":false}\n' "$CSV" > "$JSON"; echo "  JSON: $JSON"; exit 2; }
[ -d "$CSV" ] && absent "$CSV is a directory, not the backlog CSV (pass docs/build/BACKLOG.csv)"
[ -f "$CSV" ] || absent "no backlog at $CSV"
[ -d "$BUILD" ] || absent "no build directory at $BUILD"
[ -d "$TICKETS" ] || absent "no tickets directory at $TICKETS"
BUILD_ABS="$(cd "$BUILD" && pwd)"; CSV_DIR_ABS="$(cd "$(dirname "$CSV")" && pwd)"
ADR_DIR="$(dirname "$BUILD_ABS")/adr"

W="$(mktemp -d)"; trap 'rm -rf "$W" 2>/dev/null' EXIT
ISSUES="$W/issues"; EXPECTED="$W/expected"; SOURCES="$W/sources"; : > "$ISSUES"; : > "$EXPECTED"; : > "$SOURCES"
issue() { printf '%s\t%s\n' "$1" "$2" >> "$ISSUES"; }

# inputs: the directories must be the ones the backlog belongs to (BL-79)
[ -f "$TICKETS/DEFERRALS.md" ] || issue inputs "no DEFERRALS.md in tickets_dir $TICKETS — wrong tickets_dir? (no deferral was gathered)"
if [ "$BUILD_ABS" != "$CSV_DIR_ABS" ] && { [ -f "$CSV_DIR_ABS/COVERAGE_MATRIX.csv" ] || [ -f "$CSV_DIR_ABS/LEDGER.md" ]; }; then
  issue inputs "build_dir $BUILD is not the backlog's directory $(dirname "$CSV"), which holds the build records — wrong build_dir? (pass $(dirname "$CSV"))"
fi

# Quote-aware CSV → tab-separated (a cell's own tabs become spaces; doubled quotes unescaped).
CSV_AWK='
function csv(line, F,   n, i, c, q, cell) {
  n = 0; cell = ""; q = 0
  for (i = 1; i <= length(line); i++) {
    c = substr(line, i, 1)
    if (q) { if (c == "\"") { if (substr(line, i + 1, 1) == "\"") { cell = cell "\""; i++ } else q = 0 } else cell = cell c }
    else if (c == "\"") q = 1
    else if (c == ",") { F[++n] = cell; cell = "" }
    else cell = cell c
  }
  F[++n] = cell; return n
}
function trim(x) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", x); return x }
'

# ── DEFERRALS: every D-row's status (the leading status of the last cell; markup stripped) ──
DEF="$TICKETS/DEFERRALS.md"; : > "$W/dstat"
DEF_STATUS_AWK='
function defstat(c,   s, n, i, R, u, C) {
  C = "^(OPEN|PARTIAL|DONE|WONTFIX|ACCEPTED-SKELETON)$"
  s = c; gsub(/[*_`]/, "", s); n = split(s, R, /[^A-Za-z-]+/)
  for (i = 1; i <= n; i++) if (R[i] ~ /[A-Za-z]/) { u = toupper(R[i]); if (u ~ C) return u; break }
  for (i = 1; i <= n; i++) if (R[i] ~ C) return R[i]
  for (i = 1; i <= n; i++) { u = toupper(R[i]); if (u ~ C) return u }
  return ""
}'
if [ -f "$DEF" ]; then
  tr -d '\r' < "$DEF" | grep -E '^\|[[:space:]]*D-' | LC_ALL=C awk -F'|' "$DEF_STATUS_AWK"'{
      id = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      last = ""; for (i = NF; i >= 1; i--) { c = $i; gsub(/[[:space:]]/, "", c); if (c != "") { last = $i; break } }
      print id "\t" defstat(last) }' > "$W/dstat"
  awk -F'\t' '$2 == "OPEN" || $2 == "PARTIAL" {print $1}' "$W/dstat" >> "$EXPECTED"
fi
dstatus() { awk -F'\t' -v id="$1" '$1 == id {print $2; exit}' "$W/dstat"; }

# ── ADRs (revisit triggers; a superseded ADR's trigger is no longer live) ──
: > "$W/adrs"; : > "$W/adrs.live"
if [ -d "$ADR_DIR" ]; then
  for f in "$ADR_DIR"/ADR-*.md; do
    [ -f "$f" ] || continue
    id="$(basename "$f" | grep -oE '^ADR-[0-9]+')"; [ -n "$id" ] || continue
    printf '%s\n' "$id" >> "$W/adrs"
    grep -qiE '^[^#]*superseded by ADR-[0-9]+' "$f" || printf '%s\n' "$id" >> "$W/adrs.live"
  done
  sort -u "$W/adrs" -o "$W/adrs"; cat "$W/adrs" >> "$EXPECTED"
fi

# ── Coverage matrix: verdict-aware gather + consistency + the two sums ───────
MATRIX="$BUILD/COVERAGE_MATRIX.csv"; SUM_E=""; SUM_R=""; NREQ=0
if [ -f "$MATRIX" ]; then
  LC_ALL=C awk "$CSV_AWK"'
    NR == 1 { n = csv($0, H); for (i = 1; i <= n; i++) { h = tolower(trim(H[i])); if (h == "id") ic = i; if (h == "verdict") vc = i; if (h == "owed_legs") oc = i }
              if (!ic) ic = 1; if (!vc) vc = 5; next }
    /^#/ || /^[[:space:]]*$/ { next }
    { n = csv($0, F); id = trim(F[ic]); v = trim(F[vc]); if (id == "") next
      name = v; params = ""; if (index(v, "(")) { name = substr(v, 1, index(v, "(") - 1); params = substr(v, index(v, "(") + 1); sub(/\).*$/, "", params) }
      name = toupper(trim(name)); gsub(/[ ;,]+/, ";", params)
      legs = params; if (oc && trim(F[oc]) != "") { legs = trim(F[oc]); gsub(/[ ;,]+/, ";", legs) }
      # every D-id the row cites anywhere (for the MET check)
      row = $0; cited = ""; while (match(row, /D-[A-Za-z0-9.]+-[0-9]+/)) { cited = cited ";" substr(row, RSTART, RLENGTH); row = substr(row, RSTART + RLENGTH) }
      # a field is never empty (bash `read` collapses consecutive tabs): "-" stands for none
      print id "\t" (name == "" ? "-" : name) "\t" (params == "" ? "-" : params) "\t" (legs == "" ? "-" : legs) "\t" (cited == "" ? "-" : cited) }' "$MATRIX" > "$W/matrix"
  while IFS="$(printf '\t')" read -r id name params legs cited; do
    [ "$params" = "-" ] && params=""; [ "$legs" = "-" ] && legs=""; [ "$cited" = "-" ] && cited=""
    case "$name" in
      PARTIAL|MISSING|AT-RISK-INTEGRATION) printf '%s\n' "$id" >> "$EXPECTED" ;;
      MET-ENGINEERED)
        [ -n "$legs" ] || issue stale-met-engineered "$id is MET-ENGINEERED but names no owed-leg D-row (BM-VERDICT-01)"
        for d in $(printf '%s' "$legs" | tr ';' ' '); do
          case "$d" in D-*) : ;; *) continue ;; esac
          st="$(dstatus "$d")"
          case "$st" in OPEN|PARTIAL) : ;;
            *) issue stale-met-engineered "$id is MET-ENGINEERED($d) but $d is ${st:-absent from DEFERRALS.md} — re-verdict (up to MET when every leg is DONE at its layer) (BM-VERDICT-01)" ;; esac
        done ;;
      WAIVED)
        a="$(printf '%s' "$params" | grep -oE 'ADR-[0-9]+' | head -1)"
        if [ -z "$a" ]; then issue waiver-adr "$id is WAIVED without an ADR id (BM-VERDICT-01)"
        else grep -qxF "$a" "$W/adrs" || issue waiver-adr "$id is WAIVED($a) but $a does not exist (BM-VERDICT-01)"; fi ;;
      MET)
        for d in $(printf '%s' "$cited" | tr ';' ' '); do
          st="$(dstatus "$d")"
          case "$st" in OPEN|PARTIAL) issue met-with-owed-leg "$id is MET but cites $d, which is $st — MET-ENGINEERED($d) until the leg is done (BM-VERDICT-01)" ;; esac
        done ;;
      MET-DIFFERENTLY|N/A-RATIONALE) : ;;
      *) issue verdict "$id has verdict '$name', outside BM-VERDICT-01" ;;
    esac
  done < "$W/matrix"
  SUMS="$(awk -F'\t' '{ n++; v = $2
      if (v == "MET") m++; else if (v == "MET-DIFFERENTLY") md++; else if (v == "MET-ENGINEERED") me++; else if (v == "N/A-RATIONALE") na++ }
      END { print m + md + me "\t" m + md "\t" n - na }' "$W/matrix")"
  SUM_E="$(printf '%s' "$SUMS" | cut -f1)"; SUM_R="$(printf '%s' "$SUMS" | cut -f2)"; NREQ="$(printf '%s' "$SUMS" | cut -f3)"
  CLOS="$BUILD/CAPSTONE_CLOSURE.md"
  if [ -f "$CLOS" ]; then
    he="$(tr '\n' ' ' < "$CLOS" | grep -oiE 'engineering closed[^0-9]{0,40}[0-9]+' | head -1 | grep -oE '[0-9]+$')"
    hr="$(tr '\n' ' ' < "$CLOS" | grep -oiE 'requirement satisfied[^0-9]{0,40}[0-9]+' | head -1 | grep -oE '[0-9]+$')"
    [ -n "$he" ] && [ "$he" != "$SUM_E" ] && issue two-sums "CAPSTONE_CLOSURE.md says engineering closed = $he; the matrix gives $SUM_E (MET + MET-DIFFERENTLY + MET-ENGINEERED)"
    [ -n "$hr" ] && [ "$hr" != "$SUM_R" ] && issue two-sums "CAPSTONE_CLOSURE.md says requirement satisfied = $hr; the matrix gives $SUM_R (MET + MET-DIFFERENTLY — MET-ENGINEERED is never counted as MET)"
  fi
fi
sort -u "$EXPECTED" -o "$EXPECTED"
grep -v '^$' "$EXPECTED" > "$W/e.t"; mv "$W/e.t" "$EXPECTED"

# ── The backlog: sources cells, bl_id, status ────────────────────────────────
# CSV columns: bl_id, title, type, sources, req_ids, package, blocks, landing, gate, size, status
LC_ALL=C awk "$CSV_AWK"'
  NR == 1 { n = csv($0, H); for (i = 1; i <= n; i++) { h = tolower(trim(H[i])); if (h == "bl_id") bc = i; if (h == "sources") sc = i; if (h == "status") tc = i }
            if (!bc) bc = 1; if (!sc) sc = 4; next }
  /^#/ || /^[[:space:]]*$/ { next }
  { n = csv($0, F); b = trim(F[bc]); if (b == "") next; st = tolower(trim(tc ? F[tc] : F[n])); src = F[sc]; gsub(/\t/, " ", src)
    print b "\t" (st == "" ? "-" : st) "\t" (src == "" ? "-" : src) }' "$CSV" > "$W/rows"
cut -f1 "$W/rows" | sort | uniq -d | while IFS= read -r d; do [ -n "$d" ] && issue blid "duplicate bl_id \"$d\""; done
while IFS="$(printf '\t')" read -r blid st src; do
  case " open closed accepted " in *" $st "*) : ;; *) issue status "$blid has invalid status \"$st\"" ;; esac
  # split the sources cell on space/semicolon/plus/comma and record each id with its row's status
  printf '%s' "$src" | tr ' ;+,' '\n\n\n\n' | sed -E 's/[^A-Za-z0-9._-]//g' | grep -E '.' | while IFS= read -r s; do
    printf '%s\t%s\t%s\n' "$s" "$blid" "$st"; done >> "$SOURCES"
done < "$W/rows"

# every expected id appears exactly once; a still-owed source's home is not closed
if [ -s "$EXPECTED" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    n="$(awk -F'\t' -v id="$id" '$1 == id' "$SOURCES" | wc -l | tr -d ' ')"
    if [ "$n" -eq 0 ]; then issue missing "$id is owed but appears in no backlog sources cell"
    elif [ "$n" -gt 1 ]; then issue duplicate "$id appears in $n backlog rows (must be exactly one)"
    else
      home="$(awk -F'\t' -v id="$id" '$1 == id {print $2 "\t" $3; exit}' "$SOURCES")"
      if [ "$(printf '%s' "$home" | cut -f2)" = "closed" ]; then
        live=1
        case "$id" in ADR-*) grep -qxF "$id" "$W/adrs.live" || live=0 ;; esac
        [ "$live" -eq 1 ] && issue home-closed "$id is still owed but its home $(printf '%s' "$home" | cut -f1) is closed — reopen the row or close the source first"
      fi
    fi
  done < "$EXPECTED"
fi

# readiness: no TBD
READY="$BUILD/OPERATIONAL_READINESS.md"
if [ -f "$READY" ] && grep -qwE 'TBD' "$READY"; then
  issue readiness "OPERATIONAL_READINESS.md carries TBD (line $(grep -nwE 'TBD' "$READY" | head -1 | cut -d: -f1)) — an unknown is a backlog row with a landing"
fi

NI="$(wc -l < "$ISSUES" | tr -d ' ')"; NE="$(wc -l < "$EXPECTED" | tr -d ' ')"
VAC=false; [ "$NE" -eq 0 ] && [ "$ALLOW_EMPTY" -eq 0 ] && VAC=true
{
  printf '{"schema":"backlog-check/2","backlog":"%s","expectedSources":%s,"vacuous":%s,' "$CSV" "$NE" "$VAC"
  printf '"sums":{"requirements":%s,"engineeringClosed":%s,"requirementSatisfied":%s},"issues":[' "${NREQ:-0}" "${SUM_E:-null}" "${SUM_R:-null}"
  first=1
  while IFS="$(printf '\t')" read -r k m; do
    [ -n "$k" ] || continue; [ "$first" -eq 1 ] || printf ','; first=0
    em="$(printf '%s' "$m" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf '{"kind":"%s","message":"%s"}' "$k" "$em"
  done < "$ISSUES"
  printf ']}\n'
} > "$JSON"

echo "check-backlog: $CSV (expected sources: $NE)"
[ -n "$SUM_E" ] && echo "  sums: engineering closed $SUM_E / $NREQ · requirement satisfied $SUM_R / $NREQ (MET-ENGINEERED is never counted as MET)"
if [ "$VAC" = true ]; then
  echo "  ✗ 0 expected sources — refusing to call this complete: nothing was gathered from $TICKETS/DEFERRALS.md, $BUILD/COVERAGE_MATRIX.csv or $ADR_DIR (wrong build_dir / tickets_dir? pass docs/build/BACKLOG.csv docs/build docs/tickets, or --allow-empty if the build truly owes nothing)"
  [ "$NI" -eq 0 ] || { echo "  ✗ $NI issue(s):"; sed -E 's/\t/: /' "$ISSUES" | sed 's/^/    - /'; }
  echo "  JSON: $JSON"
  exit 3
fi
if [ "$NI" -eq 0 ]; then
  echo "  ✓ complete + non-duplicating + verdict-consistent"
  echo "  ~ reminder: OPEN FINDINGS and spec-register deferred rows have no ids — confirm by eye."
  echo "  JSON: $JSON"
  exit 0
fi
echo "  ✗ $NI issue(s):"; sed -E 's/\t/: /' "$ISSUES" | sed 's/^/    - /'
echo "  JSON: $JSON"
exit 1
