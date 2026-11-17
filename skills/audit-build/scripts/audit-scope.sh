#!/usr/bin/env bash
# audit-scope.sh — resolve which landed tickets an audit covers, from the committed build memory.
#
# Usage:
#   audit-scope.sh [--root DIR] --since-last | --last N | --tickets ID[,ID…] | --range BASE..HEAD
#
#   --root DIR    worktree to resolve from (default: the current git toplevel). The memory root is
#                 resolved by build-memory's memory-root.sh when it sits beside this skill; otherwise
#                 it is <root>/docs/build.
#   --since-last  every BUILD_INDEX row after the previous audit's `audited-through` ticket (all rows
#                 if there is no previous audit). This is the default.
#   --last N      the last N BUILD_INDEX rows.
#   --tickets L   exactly these ticket ids, in BUILD_INDEX order. An unknown id is an error.
#   --range B..H  rows whose branch tip is reachable from H but not from B (needs git; rows whose
#                 branch cannot be resolved are listed on stderr and left out).
#
# Output (stdout):
#   # memory-root: <path>
#   # previous-audit: <audit-id | none>
#   # audited-through: <ticket | none>
#   # scope: <the selector>
#   seq<TAB>ticket<TAB>branch<TAB>pr<TAB>base<TAB>landed<TAB>harness
#   … one row per in-scope ticket. A column the index lacks prints as "-".
#
# The previous audit is the newest docs/build/reports/audits/*.md (excluding *.plan.md) by file name,
# which starts with `date -u +%F`. Its front matter must carry `audit-id:` and `audited-through:`.
#
# Exit codes: 0 resolved (the scope may be empty) · 1 usage · 2 unknown ticket id or missing BUILD_INDEX.
# Read-only. Compatible with bash 3.2+ (macOS default).

set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="" ; SEL="since-last" ; ARG=""
usage() { awk 'NR > 1 && !/^#/ {exit} NR > 1 {sub(/^# ?/, ""); print}' "$0"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --root)       ROOT="$2"; shift 2 ;;
    --since-last) SEL="since-last"; shift ;;
    --last)       SEL="last"; ARG="$2"; shift 2 ;;
    --tickets)    SEL="tickets"; ARG="$2"; shift 2 ;;
    --range)      SEL="range"; ARG="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "audit-scope: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(cd "$ROOT" && pwd)" || { echo "audit-scope: no such root" >&2; exit 1; }
case "$SEL" in
  last) case "$ARG" in ''|*[!0-9]*) echo "audit-scope: --last needs a number" >&2; exit 1 ;; esac ;;
  tickets|range) [ -n "$ARG" ] || { echo "audit-scope: --$SEL needs a value" >&2; exit 1; } ;;
esac

MR=""
if [ -x "$HERE/../../build-memory/scripts/memory-root.sh" ] || [ -f "$HERE/../../build-memory/scripts/memory-root.sh" ]; then
  MR="$(bash "$HERE/../../build-memory/scripts/memory-root.sh" "$ROOT" 2>/dev/null | sed -n 's/^root=//p')"
fi
[ -n "$MR" ] || MR="$ROOT/docs/build"
IDX="$MR/BUILD_INDEX.md"
[ -f "$IDX" ] || { echo "audit-scope: no BUILD_INDEX at $IDX" >&2; exit 2; }

# Previous audit (newest dated report, excluding plans).
PREV="none" ; THROUGH="none"
LAST_REPORT=""
if [ -d "$MR/reports/audits" ]; then
  for f in "$MR"/reports/audits/*.md; do
    [ -f "$f" ] || continue
    case "$f" in *.plan.md) continue ;; esac
    LAST_REPORT="$f"     # glob order is lexical, and names start with the date
  done
fi
if [ -n "$LAST_REPORT" ]; then
  v="$(sed -n 's/^audit-id:[[:space:]]*//p' "$LAST_REPORT" | head -1 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
  [ -n "$v" ] && PREV="$v"
  v="$(sed -n 's/^audited-through:[[:space:]]*//p' "$LAST_REPORT" | head -1 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
  [ -n "$v" ] && THROUGH="$v"
fi

# All BUILD_INDEX rows as TSV, header-aware (columns are found by header name).
ROWS="$(awk -F'|' '
  function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
  /^\|/ {
    if (!hdr) {
      for (i = 2; i < NF; i++) { h = tolower(trim($i)); col[h] = i }
      if (("seq" in col) && ("ticket" in col)) hdr = 1; else delete col
      next
    }
    if ($0 ~ /^\|[ \t:|-]+\|[ \t]*$/) next
    s = trim($(col["seq"])); t = trim($(col["ticket"]))
    if (s == "" || t == "" || tolower(s) == "seq") next
    printf "%s\t%s", s, t
    n = split("branch pr base landed harness", want, " ")
    for (j = 1; j <= n; j++) { v = (want[j] in col) ? trim($(col[want[j]])) : ""; printf "\t%s", (v == "" ? "-" : v) }
    printf "\n"
  }' "$IDX")"

select_rows() {
  case "$SEL" in
    since-last)
      if [ "$THROUGH" = "none" ]; then printf '%s\n' "$ROWS"
      else printf '%s\n' "$ROWS" | awk -F'\t' -v t="$THROUGH" 'seen {print} $2 == t {seen = 1} END {if (!seen) exit 3}'
      fi ;;
    last)    printf '%s\n' "$ROWS" | tail -n "$ARG" ;;
    tickets)
      printf '%s\n' "$ROWS" | awk -F'\t' -v l="$ARG" '
        BEGIN { n = split(l, a, ","); for (i = 1; i <= n; i++) { gsub(/[ \t]/, "", a[i]); if (a[i] != "") want[a[i]] = 1 } }
        ($2 in want) { print; got[$2] = 1 }
        END { for (k in want) if (!(k in got)) { print "audit-scope: unknown ticket id: " k > "/dev/stderr"; bad = 1 } if (bad) exit 2 }' ;;
    range)
      B="${ARG%%..*}"; H="${ARG##*..}"
      printf '%s\n' "$ROWS" | while IFS="$(printf '\t')" read -r s t br pr ba la ha; do
        [ -n "$t" ] || continue
        sha="$(git -C "$ROOT" rev-parse -q --verify "$br^{commit}" 2>/dev/null || git -C "$ROOT" rev-parse -q --verify "origin/$br^{commit}" 2>/dev/null)"
        if [ -z "$sha" ]; then echo "audit-scope: cannot resolve branch for $t ($br); left out" >&2; continue; fi
        if git -C "$ROOT" merge-base --is-ancestor "$sha" "$H" 2>/dev/null && ! git -C "$ROOT" merge-base --is-ancestor "$sha" "$B" 2>/dev/null; then
          printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "$t" "$br" "$pr" "$ba" "$la" "$ha"
        fi
      done ;;
  esac
}

OUT="$(select_rows)"; rc=$?
if [ "$SEL" = "since-last" ] && [ $rc -eq 3 ]; then
  echo "audit-scope: previous audit's audited-through ($THROUGH) is not in BUILD_INDEX" >&2; exit 2
fi
[ $rc -eq 2 ] && exit 2

printf '# memory-root: %s\n# previous-audit: %s\n# audited-through: %s\n# scope: %s%s\n' "$MR" "$PREV" "$THROUGH" "$SEL" "${ARG:+=$ARG}"
printf 'seq\tticket\tbranch\tpr\tbase\tlanded\tharness\n'
[ -n "$OUT" ] && printf '%s\n' "$OUT" | sed '/^$/d'
exit 0
