#!/usr/bin/env bash
# check-backlog.sh — verify a build's BACKLOG.csv is complete and non-duplicating. (BM-RECON-01.)
#
# The backlog's contract: every owed thing lands in EXACTLY ONE row's `sources` cell. This script gathers the
# owed-thing ids from the committed build memory and checks each appears exactly once in the backlog, that
# bl_ids are unique, and that statuses are valid.
#
# Usage:
#   check-backlog.sh [backlog_csv] [build_dir] [tickets_dir]
#
# Arguments (all optional; sensible defaults relative to cwd):
#   backlog_csv  — the backlog (default: docs/build/BACKLOG.csv)
#   build_dir    — docs/build (default: docs/build)
#   tickets_dir  — docs/tickets (default: docs/tickets)
#
# Sources gathered (id-bearing):
#   - DEFERRALS.md rows with status OPEN or PARTIAL          (ids D-<TICKET>-<n>)
#   - COVERAGE_MATRIX.csv rows whose verdict is not MET       (the id column)
#   - docs/adr/ADR-*.md                                       (ids ADR-NNN; each has a revisit trigger)
#   (OPEN FINDINGS and register rows have no stable ids; they are a reviewer check, reported as a reminder.)
#
# Checks:
#   - every gathered source id appears in exactly one BACKLOG.csv `sources` cell (0 = dropped; >1 = double-tracked)
#   - bl_id column is unique
#   - status column ∈ {open, closed, accepted}
#
# Output: human summary to stdout; JSON to /tmp/backlog-check.json.
# Exit codes: 0 — complete + non-duplicating · 1 — gaps found · 2 — no backlog file.
# Read-only. Compatible with bash 3.2+ (macOS default). No associative arrays, no mapfile.

set -o pipefail

CSV="${1:-docs/build/BACKLOG.csv}"
BUILD="${2:-docs/build}"
TICKETS="${3:-docs/tickets}"
ADR_DIR="$(dirname "$BUILD")/adr"
JSON="/tmp/backlog-check.json"

[ -f "$CSV" ] || { echo "check-backlog: no backlog at $CSV"; printf '{"backlog":"%s","present":false}\n' "$CSV" > "$JSON"; exit 2; }

ISSUES="$(mktemp)"; EXPECTED="$(mktemp)"; SOURCES="$(mktemp)"
trap 'rm -f "$ISSUES" "$EXPECTED" "$SOURCES" 2>/dev/null' EXIT

# ── Gather expected source ids ───────────────────────────────────────────────
DEF="$TICKETS/DEFERRALS.md"
if [ -f "$DEF" ]; then
  grep -E '^\|[[:space:]]*D-' "$DEF" | while IFS= read -r row; do
    status="$(printf '%s' "$row" | sed -E 's/[[:space:]]*\|[[:space:]]*$//' | awk -F'|' '{print $NF}' | tr 'a-z' 'A-Z' | tr -d ' ')"
    case "$status" in
      OPEN*|PARTIAL*) printf '%s\n' "$row" | sed -E 's/^\|[[:space:]]*//; s/[[:space:]]*\|.*$//' >> "$EXPECTED" ;;
    esac
  done
fi
MATRIX="$BUILD/COVERAGE_MATRIX.csv"
if [ -f "$MATRIX" ]; then
  # verdict is column 5 (id,level,spec_section,class,verdict,...)
  awk -F',' 'NR>1 && $1 !~ /^#/ && $5 !~ /(^|[[:space:]])MET([[:space:]]|$)/ && $5 !~ /N\/A/ {gsub(/^[ \t]+|[ \t]+$/,"",$1); if($1!="") print $1}' "$MATRIX" >> "$EXPECTED"
fi
if [ -d "$ADR_DIR" ]; then
  ls "$ADR_DIR" 2>/dev/null | grep -oE '^ADR-[0-9]+' | sort -u >> "$EXPECTED"
fi
sort -u "$EXPECTED" -o "$EXPECTED"

# ── Extract the backlog's sources cells + bl_id/status columns ───────────────
# CSV columns: bl_id, title, type, sources, req_ids, package, blocks, landing, gate, size, status
BLIDS="$(mktemp)"; trap 'rm -f "$ISSUES" "$EXPECTED" "$SOURCES" "$BLIDS" 2>/dev/null' EXIT
awk -F',' 'NR>1 && $1 !~ /^#/ {print}' "$CSV" | while IFS= read -r line; do
  blid="$(printf '%s' "$line" | awk -F',' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); print $1}')"
  [ -n "$blid" ] || continue
  printf '%s\n' "$blid" >> "$BLIDS"
  src="$(printf '%s' "$line" | awk -F',' '{print $4}')"
  status="$(printf '%s' "$line" | awk -F',' '{gsub(/^[ \t]+|[ \t]+$/,"",$NF); print $NF}' | tr 'A-Z' 'a-z')"
  case " open closed accepted " in *" $status "*) : ;; *) printf 'status\t%s has invalid status "%s"\n' "$blid" "$status" >> "$ISSUES" ;; esac
  # split the sources cell on space/semicolon/plus and record each id
  printf '%s' "$src" | tr ' ;+' '\n\n\n' | sed -E 's/[^A-Za-z0-9._-]//g' | grep -E '.' >> "$SOURCES"
done

# bl_id uniqueness
if [ -s "$BLIDS" ]; then
  sort "$BLIDS" | uniq -d | while IFS= read -r d; do [ -n "$d" ] && printf 'blid\tduplicate bl_id "%s"\n' "$d" >> "$ISSUES"; done
fi

# every expected id appears exactly once in the sources
if [ -s "$EXPECTED" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    n="$(grep -Fxc "$id" "$SOURCES" 2>/dev/null)" ; n="${n:-0}"   # grep -c prints 0 on no match (exit 1 ignored)
    if [ "$n" -eq 0 ]; then printf 'missing\t%s is owed but appears in no backlog sources cell\n' "$id" >> "$ISSUES"
    elif [ "$n" -gt 1 ]; then printf 'duplicate\t%s appears in %s backlog rows (must be exactly one)\n' "$id" "$n" >> "$ISSUES"; fi
  done < "$EXPECTED"
fi

NI="$(wc -l < "$ISSUES" | tr -d ' ')"; NE="$(wc -l < "$EXPECTED" | tr -d ' ')"
{
  printf '{"backlog":"%s","expectedSources":%s,"issues":[' "$CSV" "$NE"
  first=1
  while IFS="$(printf '\t')" read -r k m; do
    [ -n "$k" ] || continue; [ "$first" -eq 1 ] || printf ','; first=0
    em="$(printf '%s' "$m" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf '{"kind":"%s","message":"%s"}' "$k" "$em"
  done < "$ISSUES"
  printf ']}\n'
} > "$JSON"

echo "check-backlog: $CSV (expected sources: $NE)"
if [ "$NI" -eq 0 ]; then
  echo "  ✓ complete + non-duplicating"
  echo "  ~ reminder: OPEN FINDINGS and spec-register deferred rows have no ids — confirm by eye."
  exit 0
fi
echo "  ✗ $NI issue(s):"; sed -E 's/\t/: /' "$ISSUES" | sed 's/^/    - /'
exit 1
