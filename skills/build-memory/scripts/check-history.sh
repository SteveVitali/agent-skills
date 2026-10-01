#!/usr/bin/env bash
# check-history.sh — history mode of the build-memory validator (BM-HIST-01). Read-only.
#
# Tree mode (check-build-memory.sh) can only warn about legacy content it cannot change. History mode
# judges only the lines a CHANGE adds or removes, so a legacy record never fails for what it already
# contains, and a new violation fails the change that makes it:
#   - append-only regions lose no line, and protected tables grow only at their end (append position);
#   - DEFERRALS rows only grow (a status change appends a dated note); readouts change only their
#     `Status:` line; a run ledger already closed (a dated `Closed:` stamp in its header, before the
#     first `##` heading) only gains lines; executed contracts take only an appended `> Amended <date>:` note; landed ADRs
#     take only an appended `Superseded by ADR-NNN` line; `*.jsonl` keep their byte prefix;
#   - the living LEDGER head is replaced only when the removed text is archived byte-for-byte in the
#     same change (living-archived);
#   - BUILD_INDEX rows the change adds have the header's column count, a unique seq and a real PR;
#     chain rows it adds sit under a numbered `### Round <n>` banner and never re-bind an id;
#   - every record date the change adds is not later than its commit (R1), not back-dated more than
#     48 h for an act (R2, unless `≤` / `retro:` / `as-of`), may quote a wrong date only in a
#     correction that also carries the true date (R3), and is exempt only by `future-ok:` or an
#     unexpired allow entry (R5); no commit is later than the clock (R6).
#
# Usage:
#   check-history.sh [--repo DIR] --range BASE..HEAD | --range BASE...HEAD | --staged | --first-parent SHA
#                    [--json PATH] [--now ISO] [--no-hook]
#   check-history.sh [--repo DIR] --replay FROM..TO [--json PATH]   read-only backtest: every first-parent
#                    commit of the range judged on its own (one line per commit; exit 1 if any violates)
#   (also reached as: check-build-memory.sh [repo] --range … | --staged | --first-parent …)
#
#   --range         a PR (base..head; `...` diffs from the merge base) or a boundary (<old chainTip>..<new>).
#   --staged        the index against HEAD, before a commit (implement-spec §6.5); commit time = now.
#   --first-parent  one commit against its first parent (a push to the default branch, incl. merges).
#   --now           the clock (default `date -u`; for tests).
#   --no-hook       ignore a repo hook (tests).
#
# Where it runs: implement-spec §6.5 (`--staged` before the closeout commit); orchestrate-build at every
# boundary (`--range <chainTip before>..<chainTip after>`); CI (`base..head` on pull requests,
# `--first-parent` on pushes); optionally a pre-commit hook.
#
# Repo hook: if docs/build/tools/memory_guard.py (python3), memory_guard.sh (bash) or an executable
#   memory_guard exists, it runs instead as `<hook> all <the same mode args> [--json PATH] [--now ISO]`
#   and its exit code is passed through (the repo's own guard is authoritative for the repo).
# Repo policy: docs/build/tools/record_policy/history.policy, one rule per line. Comments: a line whose
#   first non-blank character is `#`, or a lone `#` after whitespace (followed by whitespace or the end
#   of the line) and the rest of that line — `exempt <path> ### Heading  # why`. A `#` inside a token is
#   kept: `###`/`##` heading marks, `#123`, `C#`, `^#+` in an ERE.
#   append-only <path-glob>                       the whole file only appends at EOF (e.g. db/sqitch.plan)
#   date <path-glob> <ERE>                        lines matching ERE carry a record date (first ISO date/time)
#   allow <path-glob> <expires ISO> <fixed text>  a future date on a line containing the text is allowed
#                                                 until `expires` (an expired entry no longer exempts)
#   exempt <path> <heading text>                  a `##`/`###` region of that file is generated, not judged
#   archive <dir>                                 an extra archive dir for living-archived LEDGER head text
#
# Output: one line per finding, then the JSON report (schema build-memory-history/1) at --json PATH or a
#   unique mktemp file: {schema, input:{repo, mode, base, head, now, policy}, summary:{violations,
#   warnings, exit}, counts:{…}, violations:[{check, severity, file, line, commit, rule, message}], warnings}.
#
# Exit codes (the shared build-script contract): 0 clean · 1 violations · 2 not applicable (no
#   build-memory marker: scratch mode) · 5 unknown — a shallow clone ("set fetch-depth: 0"), an
#   unresolvable range, bad arguments or a report that cannot be written; never treated as green.
#
# Bash 3.2+ and git; awk does the date arithmetic (no GNU date). No associative arrays in bash.

set -o pipefail

REPO="" ; MODE="" ; ARG="" ; JSON="" ; NOW_ARG="" ; NO_HOOK=0
usage() { awk 'NR > 1 && !/^#/ {exit} NR > 1 {sub(/^# ?/, ""); print}' "$0"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)         REPO="${2:-}"; shift 2 ;;
    --range)        MODE=range; ARG="${2:-}"; shift 2 ;;
    --first-parent) MODE=first-parent; ARG="${2:-}"; shift 2 ;;
    --staged)       MODE=staged; shift ;;
    --replay)       MODE=replay; ARG="${2:-}"; shift 2 ;;
    --json)         JSON="${2:-}"; shift 2 ;;
    --now)          NOW_ARG="${2:-}"; shift 2 ;;
    --no-hook)      NO_HOOK=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "check-history: unknown argument '$1' (try --help)" >&2; exit 5 ;;
  esac
done
[ -n "$MODE" ] || { echo "check-history: one of --range, --staged, --first-parent, --replay is required" >&2; exit 5; }
REPO="${REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "check-history: no such repo" >&2; exit 5; }
G() { git -C "$REPO" "$@"; }

if [ ! -f "$REPO/docs/build/README.md" ] || ! grep -qF '<!-- build-memory: v2 -->' "$REPO/docs/build/README.md"; then
  echo "check-history: $REPO is not a build-memory repo (scratch mode) — not applicable."
  exit 2
fi

# Repo hook: the repo's own guard is authoritative.
if [ "$NO_HOOK" -eq 0 ] && [ "$MODE" != replay ]; then
  H="$REPO/docs/build/tools"
  set -- all
  case "$MODE" in range) set -- "$@" --range "$ARG" ;; first-parent) set -- "$@" --first-parent "$ARG" ;; staged) set -- "$@" --staged ;; esac
  [ -n "$JSON" ] && set -- "$@" --json "$JSON"
  [ -n "$NOW_ARG" ] && set -- "$@" --now "$NOW_ARG"
  if [ -f "$H/memory_guard.py" ]; then echo "check-history: delegating to docs/build/tools/memory_guard.py"; ( cd "$REPO" && python3 "$H/memory_guard.py" "$@" ); exit $?; fi
  if [ -f "$H/memory_guard.sh" ]; then echo "check-history: delegating to docs/build/tools/memory_guard.sh"; ( cd "$REPO" && bash "$H/memory_guard.sh" "$@" ); exit $?; fi
  if [ -x "$H/memory_guard" ]; then echo "check-history: delegating to docs/build/tools/memory_guard"; ( cd "$REPO" && "$H/memory_guard" "$@" ); exit $?; fi
fi

# Replay: judge every first-parent commit of FROM..TO on its own (the repo's own guard is not consulted:
# this backtests this script's rules).
if [ "$MODE" = replay ]; then
  case "$ARG" in *..*) : ;; *) echo "check-history: --replay wants FROM..TO" >&2; exit 5 ;; esac
  [ -n "$JSON" ] || JSON="$(mktemp "${TMPDIR:-/tmp}/build-memory-replay.XXXXXXXX")"
  self="$0"; n=0; bad=0; out="$(mktemp)"; trap 'rm -f "$out"' EXIT
  printf '{"schema":"build-memory-replay/1","range":"%s","commits":[' "$ARG" > "$JSON" \
    || { echo "check-history: cannot write report to $JSON — unknown, never green" >&2; exit 5; }
  for c in $(G rev-list --reverse --first-parent "$ARG" 2>/dev/null); do
    n=$((n + 1))
    bash "$self" --repo "$REPO" --first-parent "$c" --no-hook ${NOW_ARG:+--now "$NOW_ARG"} --json "$out.j" > "$out" 2>&1; rc=$?
    rules="$(grep -oE '^    - [a-z-]+ \[[A-Za-z0-9-]+\]' "$out" | sed -E 's/^    - //' | sort | uniq -c | awk '{printf "%s%s×%s", (NR > 1 ? " " : ""), $2 $3, $1}')"
    [ "$rc" -eq 1 ] && bad=$((bad + 1))
    printf '%s %s exit=%s %s\n' "$(G log -1 --format='%h %cI' "$c")" "" "$rc" "$rules"
    [ "$n" -gt 1 ] && printf ',' >> "$JSON"
    printf '{"commit":"%s","exit":%s,"rules":"%s"}' "$c" "$rc" "$rules" >> "$JSON"
  done
  printf '],"judged":%s,"violating":%s}\n' "$n" "$bad" >> "$JSON"
  echo "check-history --replay $ARG: $n commit(s) judged, $bad with violations. JSON: $JSON"
  [ "$bad" -eq 0 ] || exit 1
  exit 0
fi

if [ "$(G rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  echo "check-history: shallow clone — history mode needs the full history (set fetch-depth: 0)." >&2
  exit 5
fi
EMPTY_TREE="$(G hash-object -t tree /dev/null)"
resolve() { G rev-parse --verify -q "$1^{commit}" 2>/dev/null; }
case "$MODE" in
  range)
    case "$ARG" in
      *...*) a="${ARG%%...*}"; b="${ARG##*...}"; HEADC="$(resolve "$b")"; A="$(resolve "$a")"
             [ -n "$A" ] && [ -n "$HEADC" ] && BASE="$(G merge-base "$A" "$HEADC")" ;;
      *..*)  BASE="$(resolve "${ARG%%..*}")"; HEADC="$(resolve "${ARG##*..}")" ;;
      *)     echo "check-history: --range wants BASE..HEAD" >&2; exit 5 ;;
    esac ;;
  first-parent)
    HEADC="$(resolve "$ARG")"; BASE="$(resolve "$ARG^1")"; [ -n "$HEADC" ] && [ -z "$BASE" ] && BASE="$EMPTY_TREE" ;;
  staged)
    BASE="$(resolve HEAD)"; [ -n "$BASE" ] || BASE="$EMPTY_TREE"; HEADC=":index" ;;
esac
if [ -z "${BASE:-}" ] || [ -z "${HEADC:-}" ]; then
  echo "check-history: cannot resolve the change '$MODE ${ARG}' — unknown, never green." >&2; exit 5
fi

if [ -z "$JSON" ]; then JSON="$(mktemp "${TMPDIR:-/tmp}/build-memory-history.XXXXXXXX")" || exit 5
else _jd="$(dirname "$JSON")"; [ -d "$_jd" ] || mkdir -p "$_jd" 2>/dev/null || true; fi

W="$(mktemp -d)"; trap 'rm -rf "$W" 2>/dev/null' EXIT
: > "$W/out"      # findings: V|W \t check \t file \t line \t commit \t rule \t message
: > "$W/dates"    # record dates: path \t line \t class \t text
: > "$W/counts"
NOW_ISO="${NOW_ARG:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

# ── Clock arithmetic (portable awk; no mktime) ──────────────────────────────
CLOCK_AWK='
function dfc(y, m, d,   era, yoe, doy, doe) {
  y -= (m <= 2); era = int((y >= 0 ? y : y - 399) / 400); yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
function epoch(s,   y, mo, d, H, M, S, rest, sg, oh, om, t) {
  if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return -1
  y = substr(s, 1, 4) + 0; mo = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0; H = 0; M = 0; S = 0
  rest = substr(s, 11)
  if (rest ~ /^[T ][0-9][0-9]:[0-9][0-9]/) {
    H = substr(rest, 2, 2) + 0; M = substr(rest, 5, 2) + 0; rest = substr(rest, 7)
    if (rest ~ /^:[0-9][0-9]/) { S = substr(rest, 2, 2) + 0; rest = substr(rest, 4) }
    sub(/^\.[0-9]+/, "", rest)
  }
  t = dfc(y, mo, d) * 86400 + H * 3600 + M * 60 + S
  if (rest ~ /^[+-][0-9][0-9]/) { sg = (substr(rest, 1, 1) == "-") ? -1 : 1; oh = substr(rest, 2, 2) + 0
    om = 0; if (substr(rest, 4) ~ /^:?[0-9][0-9]/) { om = substr(rest, (substr(rest, 4, 1) == ":") ? 5 : 4, 2) + 0 }
    t -= sg * (oh * 3600 + om * 60) }
  return t
}
function has_time(s) { return (s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9][0-9]:[0-9][0-9]/) }
function udate(e,   z, era, doe, yoe, y, doy, mp, d, m) {
  z = int(e / 86400) + 719468; if (e < 0 && e % 86400) z--
  era = int((z >= 0 ? z : z - 146096) / 146097); doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400; doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153); d = doy - int((153 * mp + 2) / 5) + 1; m = mp + (mp < 10 ? 3 : -9)
  return sprintf("%04d-%02d-%02d", y + (m <= 2), m, d)
}
'
NOW_EPOCH="$(awk "$CLOCK_AWK"' BEGIN { print epoch(ARGV[1]); ARGV[1] = "" }' "$NOW_ISO")"
case "$NOW_EPOCH" in ''|-1|*[!0-9]*) echo "check-history: --now '$NOW_ISO' is not an ISO-8601 time" >&2; exit 5 ;; esac

add() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$W/out"; }   # V|W check file line commit rule message
GUARDS=0
grep -qE '^[[:space:]]*<!-- build-memory-guards: 1 -->[[:space:]]*$' "$REPO/docs/build/README.md" && GUARDS=1

# ── Policy ──────────────────────────────────────────────────────────────────
POL="$REPO/docs/build/tools/record_policy/history.policy"
# Comment rule (header): drop `#` lines; cut a lone ` # …` tail; keep a `#` inside a token (`### Heading`, `#123`).
: > "$W/pol"; [ -f "$POL" ] && sed -E '/^[[:space:]]*#/d; s/[[:space:]]+#([[:space:]].*)?$//; s/[[:space:]]+$//; /^[[:space:]]*$/d' "$POL" > "$W/pol"
pol() { awk -v k="$1" '$1 == k' "$W/pol"; }
ARCHIVE_DIRS="docs/build/reports/ledger-archive $(pol archive | awk '{print $2}' | tr '\n' ' ')"
POL_AO="$(pol append-only | awk '{print $2}')"
POL_PATHS="$(pol append-only | awk '{print $2}'; pol date | awk '{print $2}')"

# ── Content accessors ───────────────────────────────────────────────────────
at_base() { [ "$BASE" = "$EMPTY_TREE" ] && return 0; G show "$BASE:$1" 2>/dev/null; }
at_head() { if [ "$MODE" = staged ]; then G show ":$1" 2>/dev/null; else G show "$HEADC:$1" 2>/dev/null; fi; }
head_files() { if [ "$MODE" = staged ]; then G ls-files -- "$1"; else G ls-tree -r --name-only "$HEADC" -- "$1"; fi; }
gdiff() {   # gdiff <options…> -- <paths…>
  local opts=() ; while [ $# -gt 0 ] && [ "$1" != "--" ]; do opts+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  if [ "$MODE" = staged ]; then G diff --cached --no-renames --no-color ${opts[@]+"${opts[@]}"} "$BASE" -- "$@"
  else G diff --no-renames --no-color ${opts[@]+"${opts[@]}"} "$BASE" "$HEADC" -- "$@"; fi
}

# Changed files under docs/ plus the policy paths (status \t path).
PATHSPEC="docs"
gdiff --name-status -- $PATHSPEC 2>/dev/null > "$W/changed"
if [ -n "$POL_PATHS" ]; then
  for g in $POL_PATHS; do gdiff --name-status -- ":(glob)$g" 2>/dev/null; done >> "$W/changed"
fi
sort -u -k2 "$W/changed" -o "$W/changed"

MANIFEST_REL="docs/tickets/00_MANIFEST.md"
LEDGER_REL="docs/build/LEDGER.md"

# Executed contracts: tickets whose id has a BUILD_INDEX row at BASE.
at_base docs/build/BUILD_INDEX.md > "$W/bi.base"
LC_ALL=C awk -F'|' '/^\|/ { for (i = 2; i < NF; i++) { c = $i; gsub(/[*`]/, "", c); gsub(/^[[:space:]]+|[[:space:]]+$/, "", c); sub(/[[:space:]].*$/, "", c); if (c ~ /^[A-Z][A-Z0-9.a-z-]*$/) print c } }' "$W/bi.base" | sort -u > "$W/executed"

# The -U0 diff of one path as records:  R \t <base line> \t <text>   |   A \t <head line> \t <insert-after base line> \t <text>
diffrecs() {
  # A last line that only gained its end-of-line ("\ No newline at end of file") is not a change.
  gdiff -U0 -- "$1" 2>/dev/null | LC_ALL=C awk '
    /^@@ / {
      h = $0; sub(/^@@ -/, "", h); split(h, P, " "); split(P[1], B, ","); s = P[2]; sub(/^\+/, "", s); split(s, N, ",")
      a = B[1] + 0; b = (B[2] == "") ? 1 : B[2] + 0; c = N[1] + 0
      ins = (b == 0) ? a : a + b - 1; rl = a; al = c; inhunk = 1; next }
    !inhunk { next }
    /^\\ / { if (lastk == "R") noeol = lastn; next }
    /^-/ { n++; K[n] = "R"; T[n] = substr($0, 2); O[n] = "R\t" rl "\t" T[n]; rl++; lastk = "R"; lastn = n; next }
    /^\+/ { n++; K[n] = "A"; T[n] = substr($0, 2); O[n] = "A\t" al "\t" ins "\t" T[n]; al++; lastk = "A"; lastn = n
            if (noeol && T[noeol] == T[n]) { drop[noeol] = 1; drop[n] = 1; noeol = 0 } next }
    END { for (i = 1; i <= n; i++) if (!drop[i]) print O[i] }'
}
blank() { case "$1" in *[![:space:]]*) return 1 ;; esac; return 0; }
norm() { sed -E 's/\\(.)/\1/g; s/[[:space:]]+/ /g; s/^ //; s/ $//'; }
# run_closed < run ledger → 0 when its header (the lines before its first `##` heading) carries a dated `Closed:`
# stamp (BM-INDEX-02). `- **Closed:** none.` in a body section, or an undated placeholder, is not a close.
run_closed() {
  # reads to EOF (no early exit): under pipefail an early exit could SIGPIPE `git show` and read as "open"
  LC_ALL=C awk 'hdr_done { next } /^##+[[:space:]]/ { hdr_done = 1; next } { s = $0; gsub(/[*_`]/, "", s) }
    s ~ /^[[:space:]]*(-[[:space:]]*)?Closed:[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { f = 1; hdr_done = 1 }
    END { exit !f }'
}

# ── Region map of a markdown file: one line per region —  idx \t start \t end \t lastNonBlank \t level \t heading
regions() {
  LC_ALL=C awk '
    function close_r() { if (n) { E[n] = NR - 1; } }
    /^##+[[:space:]]/ { lvl = match($0, /[^#]/) - 1; if (lvl == 2) { close_r(); n++; S[n] = NR; Hd[n] = $0; L[n] = 2; LN[n] = NR } }
    n && $0 !~ /^[[:space:]]*$/ { LN[n] = NR }
    END { if (n) E[n] = NR; for (i = 1; i <= n; i++) print i "\t" S[i] "\t" E[i] "\t" LN[i] "\t" L[i] "\t" Hd[i] }' "$1"
}
# Sub-regions (###) for exempt spans: start \t end \t heading
subregions() {
  LC_ALL=C awk '/^##+[[:space:]]/ { if (n) { E[n] = NR - 1 } n++; S[n] = NR; Hd[n] = $0 } END { if (n) E[n] = NR; for (i = 1; i <= n; i++) print S[i] "\t" E[i] "\t" Hd[i] }' "$1"
}

CAND_LINES=0
judge_append_only_file() {   # <path> <recs> <checkname> — no removed line (whitespace/escape-equivalent moves allowed)
  awk -F'\t' '$1 == "A" {print $4}' "$2" | norm | sort > "$W/added.norm"
  awk -F'\t' '$1 == "R" {print $2 "\t" $3}' "$2" | while IFS="$(printf '\t')" read -r ln txt; do
    t="$(printf '%s' "$txt" | norm)"
    [ -z "$t" ] && continue
    grep -qxF -- "$t" "$W/added.norm" && continue
    add V "$3" "$1" "$ln" "" append-only "line $ln removed or rewritten: '$(printf '%s' "$txt" | cut -c1-80)' — protected records change only by appending; a correction is a new dated entry naming the sha and line (BM-HIST-01)"
  done
}
moved_text() { grep -qxF -- "$(printf '%s' "$1" | norm)" "$W/removed.norm" 2>/dev/null; }

# ── Per-file judgement ──────────────────────────────────────────────────────
while IFS="$(printf '\t')" read -r st path; do
  [ -n "$path" ] || continue
  R="$W/recs"; diffrecs "$path" > "$R"
  n_r="$(grep -c '^R' "$R")"; n_a="$(grep -c '^A' "$R")"; CAND_LINES=$((CAND_LINES + n_r + n_a))
  awk -F'\t' '$1 == "R" {print $3}' "$R" | norm | sort > "$W/removed.norm"
  base_name="$(basename "$path")"
  cls=""
  case "$path" in
    "$LEDGER_REL") cls=ledger ;;
    docs/tickets/DEFERRALS.md) cls=deferrals ;;
    docs/build/readouts/_TEMPLATE.md) cls="" ;;
    docs/build/readouts/*.md) cls=readout ;;
    docs/build/BUILD_INDEX.md) cls=index ;;
    "$MANIFEST_REL") cls=manifest ;;
    docs/build/reports/digests/*.md) cls=digest ;;
    docs/build/*.jsonl|docs/build/*/*.jsonl|docs/build/*/*/*.jsonl|docs/build/*/*/*/*.jsonl) cls=jsonl ;;
    docs/build/runs/*.md|docs/build/pr/*.md) cls=runpr ;;
    docs/adr/ADR-*.md) cls=adr ;;
    docs/research-ledger.md|docs/build/planning/*.md|docs/build/planning/*/*.md) cls=planning ;;
    docs/tickets/*.md)
      tid="$(printf '%s' "$base_name" | sed -E 's/^[0-9]{2,3}[a-z]?_//; s/__.*$//; s/\.md$//')"
      grep -qxF "$tid" "$W/executed" && cls=contract ;;
  esac
  for g in $POL_AO; do case "$path" in $g) cls=policy-ao ;; esac; done
  # deletions of protected files
  if [ "$st" = "D" ] && [ -n "$cls" ] && [ "$cls" != planning ] && [ "$cls" != runpr ]; then
    add V append-only "$path" 0 "" deleted "a protected build record was deleted — records are corrected by appending, never removed (BM-HIST-01)"; continue
  fi
  case "$cls" in
    ledger)
      at_base "$path" > "$W/base"; at_head "$path" > "$W/head"
      regions "$W/base" > "$W/reg"
      subregions "$W/base" > "$W/sub.base"
      # living head = lines before `## OPEN FINDINGS` (else before the first `## ` other than CURRENT STATE)
      HEAD_END="$(awk '/^##[[:space:]]+OPEN FINDINGS/ {print NR - 1; exit}' "$W/base")"
      [ -n "$HEAD_END" ] || HEAD_END="$(awk '/^##[[:space:]]/ && !/^##[[:space:]]+CURRENT STATE/ {print NR - 1; exit}' "$W/base")"
      [ -n "$HEAD_END" ] || HEAD_END=0
      pol exempt | awk -v p="$path" '$2 == p && sub(/^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "") {print}' > "$W/exempt"
      # exempt spans at BASE (by heading text prefix)
      : > "$W/exspan"
      while IFS= read -r eh; do awk -F'\t' -v h="$eh" 'index($3, h) {print $1 "\t" $2}' "$W/sub.base" >> "$W/exspan"; done < "$W/exempt"
      # removed lines
      LC_ALL=C awk -F'\t' -v he="$HEAD_END" -v regf="$W/reg" -v exf="$W/exspan" '
        BEGIN { while ((getline l < regf) > 0) { split(l, x, "\t"); n++; S[n] = x[2]; E[n] = x[3]; LN[n] = x[4]; Hd[n] = x[6] }
                while ((getline l < exf) > 0) { split(l, x, "\t"); m++; XS[m] = x[1]; XE[m] = x[2] } }
        function reg(L,   i) { for (i = n; i >= 1; i--) if (S[i] <= L) return i; return 0 }
        function ex(L,   i) { for (i = 1; i <= m; i++) if (L >= XS[i] && L <= XE[i]) return 1; return 0 }
        function pos(h) { return (h ~ /^##[[:space:]]+(GATE DECISIONS|PHASE LOG|OPEN FINDINGS|RETURN PASS)/) }
        $1 == "R" { L = $2; if (ex(L)) next
          if (L <= he) { print "HEADRM\t" L "\t" $3; next }
          print "RM\t" L "\t" Hd[reg(L)] "\t" $3; next }
        $1 == "A" { a = $3; if (ex(a)) next
          if (a <= he) next
          r = reg(a); if (!r) next
          if (pos(Hd[r]) && a < LN[r]) print "MID\t" $2 "\t" Hd[r] "\t" LN[r] "\t" $4 }' "$R" > "$W/lj"
      awk -F'\t' '$1 == "A" {print $4}' "$R" | norm | sort > "$W/added.norm.all"
      awk -F'\t' '$1 == "RM" {print $2 "\t" $3 "\t" $4}' "$W/lj" > "$W/rm"
      while IFS="$(printf '\t')" read -r ln hd txt; do
        t="$(printf '%s' "$txt" | norm)"; [ -n "$t" ] || continue
        grep -qxF -- "$t" "$W/added.norm.all" && continue
        add V append-only "$path" "$ln" "" append-only "line $ln in '$(printf '%s' "$hd" | cut -c1-40)' removed or rewritten: '$(printf '%s' "$txt" | cut -c1-80)' — this region only appends; a correction is a new dated entry (BM-HIST-01)"
      done < "$W/rm"
      awk -F'\t' '$1 == "MID"' "$W/lj" | while IFS="$(printf '\t')" read -r k ln hd last txt; do
        moved_text "$txt" && continue
        add V append-position "$path" "$ln" "" append-position "line $ln was inserted inside '$(printf '%s' "$hd" | cut -c1-40)' (before its last entry at base line $last) — new entries go only after the region's last line (BM-LEDGER-06, BM-HIST-01)"
      done
      # living-archived head: a removed head line other than a CURRENT STATE key line (a value update)
      # or a blank line must be archived byte-for-byte in this change, with a pointer left behind.
      awk -F'\t' '$1 == "HEADRM" {print $2 "\t" $3}' "$W/lj" > "$W/headrm"
      if [ -s "$W/headrm" ]; then
        : > "$W/archive"; archs=""
        for d in $ARCHIVE_DIRS; do
          awk -F'\t' -v d="$d/" 'index($2, d) == 1 && $1 != "D" {print $2}' "$W/changed" | while IFS= read -r af; do at_head "$af"; done >> "$W/archive"
          archs="$archs $(awk -F'\t' -v d="$d/" 'index($2, d) == 1 && $1 != "D" {print $2}' "$W/changed" | tr '\n' ' ')"
        done
        nmiss=0; narch=0; first=""
        while IFS="$(printf '\t')" read -r ln txt; do
          blank "$txt" && continue
          printf '%s' "$txt" | grep -qE '^[[:space:]]*(projectStatus|nextTicket|lastCompleted|blockedOn|pauseRequested|returnPass|manifest|canonicalSpec|memoryRoot|dispatchTarget|buildWorktree|buildBranchBase|pinnedBaseSha|chainTip|benchmarkSet|autonomy|mergePolicy|round|harness|updatedAt):' && continue
          if grep -qxF -- "$txt" "$W/archive" 2>/dev/null; then narch=$((narch + 1)); continue; fi
          nmiss=$((nmiss + 1)); [ -n "$first" ] || first="$ln"
        done < "$W/headrm"
        if [ "$nmiss" -gt 0 ]; then
          add V living-archived "$path" "$first" "" living-archived "$nmiss removed LEDGER head line(s) (first: base line $first) are not archived byte-for-byte under ${ARCHIVE_DIRS%% *}/ in this change — archive the replaced text with a sha256 pointer comment (BM-LEDGER-08)"
        else
          ptr=0; for af in $archs; do grep -qF "$(basename "$af")" "$W/head" && ptr=1; done
          [ "$narch" -gt 0 ] && [ "$ptr" -eq 0 ] && add V living-archived "$path" 1 "" pointer "the LEDGER head was archived but no pointer comment names the archive file (BM-LEDGER-08)"
        fi
      fi
      # record dates in added lines (HEAD regions): PHASE LOG lead dates, GATE DECISIONS col 1, updatedAt
      awk -F'\t' '$1 == "A" {print $2}' "$R" > "$W/alines"
      LC_ALL=C awk -v af="$W/alines" -v p="$path" '
        BEGIN { while ((getline l < af) > 0) A[l] = 1 }
        /^##[[:space:]]/ { pl = ($0 ~ /^##[[:space:]]+PHASE LOG/); gd = ($0 ~ /^##[[:space:]]+GATE DECISIONS/); next }
        !(NR in A) { next }
        pl && /^-[[:space:]]/ { s = $0; gsub(/[*_`]/, "", s); if (match(s, /^-[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) print p "\t" NR "\tact\t" substr(s, RSTART + RLENGTH - 10, 10) "\t" $0; next }
        gd && /^\|/ { split($0, C, "|"); if (match(C[2], /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]([T ][0-9][0-9]:[0-9][0-9](:[0-9][0-9])?(Z|[+-][0-9][0-9]:?[0-9][0-9])?)?/)) print p "\t" NR "\tact\t" substr(C[2], RSTART, RLENGTH) "\t" $0; next }
        /^[[:space:]]*updatedAt:/ { s = $0; sub(/^[[:space:]]*updatedAt:[[:space:]]*/, "", s); if (match(s, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]([T ][0-9][0-9]:[0-9][0-9](:[0-9][0-9])?(Z|[+-][0-9][0-9]:?[0-9][0-9])?)?/)) print p "\t" NR "\tact\t" substr(s, RSTART, RLENGTH) "\t" $0 }' "$W/head" >> "$W/dates"
      ;;
    deferrals)
      at_head "$path" > "$W/head"
      # row-annotate: a D-row only grows; a change of its status token appends a dated note
      awk -F'\t' '$1 == "A" {print $2 "\t" $4}' "$R" > "$W/arows"
      awk -F'\t' '$1 == "R" {print $2 "\t" $3}' "$R" | while IFS="$(printf '\t')" read -r ln txt; do
        if printf '%s' "$txt" | grep -qE '^\|[[:space:]]*D-'; then
          id="$(printf '%s' "$txt" | sed -E 's/^\|[[:space:]]*//; s/[[:space:]]*\|.*$//')"
          new="$(awk -F'\t' -v id="$id" '{ r = $2; sub(/^\|[[:space:]]*/, "", r); sub(/[[:space:]]*\|.*$/, "", r); if (r == id) { print $2; exit } }' "$W/arows")"
          if [ -z "$new" ]; then add V row-annotate "$path" "$ln" "" removed "DEFERRALS row $id was removed — never delete a row (BM-DEFER-01)"; continue; fi
          # Grown, not rewritten: every old cell's text survives in the same cell (the last cell's leading
          # status token aside); a changed leading status carries a date the old row did not have.
          verdict="$(OLDROW="$txt" NEWROW="$new" LC_ALL=C awk '
            function nz(x) { gsub(/[*`]/, "", x); gsub(/[[:space:]]+/, " ", x); sub(/^ /, "", x); sub(/ $/, "", x); return x }
            function cells(r, C,   u) { u = r; sub(/^[[:space:]]*\|/, "", u); sub(/\|[[:space:]]*$/, "", u); return split(u, C, "|") }
            function lead(c,   x) { x = toupper(nz(c)); if (match(x, /^(OPEN|PARTIAL|DONE|WONTFIX|ACCEPTED-SKELETON)/)) return substr(x, 1, RLENGTH); return "" }
            function rest(c,   x) { x = nz(c); sub(/^(OPEN|PARTIAL|DONE|WONTFIX|ACCEPTED-SKELETON|open|partial|done|wontfix)[[:space:]]*/, "", x); return x }
            BEGIN { o = ENVIRON["OLDROW"]; n = ENVIRON["NEWROW"]; no = cells(o, O); nn = cells(n, N); bad = 0
              for (i = 1; i < no; i++) if (index(nz(N[i]), nz(O[i])) == 0) bad = 1
              if (index(nz(N[nn]), rest(O[no])) == 0) bad = 1
              if (bad) { print "rewritten"; exit }
              if (lead(O[no]) != lead(N[nn])) {
                s = n; nd = 0; while (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) { if (!index(o, substr(s, RSTART, RLENGTH))) nd = 1; s = substr(s, RSTART + RLENGTH) }
                print (nd ? "flip" : "flip-undated"); exit }
              print "grown" }')"
          case "$verdict" in
            rewritten) add V row-annotate "$path" "$ln" "" rewritten "DEFERRALS row $id was rewritten, not grown — keep every cell's text and add the note (BM-DEFER-01, BM-HIST-01)"; continue ;;
            flip-undated) add V row-annotate "$path" "$ln" "" status-date "DEFERRALS row $id changed status without a dated note (\`date -u +%F\` + evidence) (BM-DEFER-01)" ;;
          esac
          grown="$new"
          hl="$(awk -F'\t' -v id="$id" '{ r = $2; sub(/^\|[[:space:]]*/, "", r); sub(/[[:space:]]*\|.*$/, "", r); if (r == id) { print $1; exit } }' "$W/arows")"
          printf '%s' "$grown" | grep -oE '(OPEN|PARTIAL|DONE|WONTFIX|ACCEPTED-SKELETON|DEFERRED-AGAIN)[^0-9|]{0,12}[0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}$' \
            | while IFS= read -r d; do case "$txt" in *"$d"*) continue ;; esac; printf '%s\t%s\tact\t%s\t%s\n' "$path" "$hl" "$d" "$new" >> "$W/dates"; done
          printf '%s\n' "$id" >> "$W/def.changed"
        else
          t="$(printf '%s' "$txt" | norm)"; [ -n "$t" ] || continue
          awk -F'\t' '{print $2}' "$W/arows" | norm | grep -qxF -- "$t" && continue
          add V append-only "$path" "$ln" "" append-only "DEFERRALS line $ln removed or rewritten — the header and rules only gain lines (BM-DEFER-01)"
        fi
      done
      # rows ADDED (new ids): status dates; under the guards marker an owed P row must be scheduled (rule 5)
      LC_ALL=C awk -F'|' -v af="$W/arows" -v chg="$W/def.changed" -v p="$path" '
        function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
        BEGIN { while ((getline l < af) > 0) { split(l, x, "\t"); A[x[1]] = 1 } while ((getline l < chg) > 0) C[l] = 1 }
        /^\|[[:space:]]*id[[:space:]]*\|/ { kc = uc = 0; for (i = 1; i <= NF; i++) { c = tolower(trim($i)); if (c == "kind") kc = i; if (c == "unblocked by") uc = i } next }
        !(NR in A) || !/^\|[[:space:]]*D-/ { next }
        { id = trim($2); if (id in C) next
          s = $0; while (match(s, /(OPEN|PARTIAL|DONE|WONTFIX|ACCEPTED-SKELETON|DEFERRED-AGAIN)[^0-9|]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) { print "D\t" p "\t" NR "\tact\t" substr(s, RSTART + RLENGTH - 10, 10) "\t" $0; s = substr(s, RSTART + RLENGTH) }
          if (kc) { k = $kc; gsub(/[[:space:]*`_]/, "", k)
            if (k == "P") { last = ""; for (i = NF; i >= 1; i--) if (trim($i) != "") { last = $i; break }
              u = toupper(last); if (u ~ /OPEN|PARTIAL/) { cell = uc ? $uc : $0; if (cell !~ /owner:/ || cell !~ /trigger:/) print "P\t" id "\t" NR } } } }' "$W/head" > "$W/defadd"
      awk -F'\t' '$1 == "D" {print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6}' "$W/defadd" >> "$W/dates"
      awk -F'\t' '$1 == "P"' "$W/defadd" | while IFS="$(printf '\t')" read -r k id ln; do
        if [ "$GUARDS" -eq 1 ]; then sev=V; else sev=W; fi
        add "$sev" deferrals "$path" "$ln" "" rule-5 "DEFERRALS row $id (kind P, owed) was added without owner:/trigger: in 'unblocked by' — human work is scheduled (rule 5)"
      done
      rm -f "$W/def.changed"
      ;;
    readout)
      if [ "$st" != "A" ]; then
        nrS="$(awk -F'\t' '$1 == "R" && $3 ~ /^Status:/' "$R" | wc -l | tr -d ' ')"
        naS="$(awk -F'\t' '$1 == "A" && $4 ~ /^Status:/' "$R" | wc -l | tr -d ' ')"
        awk -F'\t' '$1 == "R" && $3 !~ /^Status:/ {print $2 "\t" $3}' "$R" | while IFS="$(printf '\t')" read -r ln txt; do
          t="$(printf '%s' "$txt" | norm)"; [ -n "$t" ] || continue
          add V append-only "$path" "$ln" "" readout "readout line $ln removed or rewritten ('$(printf '%s' "$txt" | cut -c1-60)') — a readout is append-only except its single Status: line; signing appends a Signature block (BM-INDEX-03, BM-GATE-08)"
        done
        { [ "$nrS" -le 1 ] && [ "$naS" -le 1 ]; } || add V append-only "$path" 0 "" readout "readout changed more than one Status: line (BM-INDEX-03)"
      fi
      at_head "$path" > "$W/head"; awk -F'\t' '$1 == "A" {print $2}' "$R" > "$W/alines"
      LC_ALL=C awk -v af="$W/alines" -v p="$path" '
        BEGIN { while ((getline l < af) > 0) A[l] = 1 }
        (NR in A) && /(^|[^A-Za-z])(Date|[Rr]eceived|[Ss]igned|[Cc]onfirm[a-z]*|GATE DECISIONS row)/ {
          s = $0; while (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]([T ][0-9][0-9]:[0-9][0-9](:[0-9][0-9])?(Z|[+-][0-9][0-9]:?[0-9][0-9])?)?/)) {
            print p "\t" NR "\tact\t" substr(s, RSTART, RLENGTH) "\t" $0; s = substr(s, RSTART + RLENGTH) } }' "$W/head" >> "$W/dates"
      ;;
    index)
      judge_append_only_file "$path" "$R" append-only
      at_head "$path" > "$W/head"; awk -F'\t' '$1 == "A" {print $2}' "$R" > "$W/alines"
      LC_ALL=C awk -v af="$W/alines" -v p="$path" '
        function t(x) { gsub(/[*`]/, "", x); gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
        function ncells(s,   u) { u = s; gsub(/\\\|/, "", u); sub(/^[[:space:]]*\|/, "", u); sub(/\|[[:space:]]*$/, "", u); return split(u, _x, "|") }
        function issep(x) { return x ~ /^\|[-|: ]+\|[[:space:]]*$/ }
        function sethdr(h,   u, m, i, c) { hn = ncells(h); sc = pc = dc = 0; u = h; gsub(/\\\|/, "", u); m = split(u, H, "|")
          for (i = 1; i <= m; i++) { c = tolower(t(H[i])); if (c == "seq" || c == "#") sc = i; if (c == "pr") pc = i; if (c == "landed") dc = i }; have = 1 }
        function data(r, nr,   u, s) {
          u = r; gsub(/\\\|/, "", u); split(u, C, "|"); s = sc ? t(C[sc]) : ""
          if (!(nr in A)) { if (s != "") seen[s] = nr; return }
          if (ncells(r) != hn) print "V\tindex\t" p "\t" nr "\t\tcolumns\tadded BUILD_INDEX row has " ncells(r) " cells, the header has " hn " — escape a | inside a cell as \\| (BM-INDEX-01)"
          if (s != "" && (s in seen)) print "V\tindex\t" p "\t" nr "\t\tseq\tadded BUILD_INDEX row reuses seq " s " (first at line " seen[s] ") (BM-INDEX-01)"
          if (s != "") seen[s] = nr
          if (pc && t(C[pc]) ~ /[Pp]ending|TBD/) print "V\tindex\t" p "\t" nr "\t\tpr\tadded BUILD_INDEX row has no real PR (\x27" t(C[pc]) "\x27) — the worker closes after the PR exists (BM-INDEX-01)"
          if (dc && match(C[dc], /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) print "D\t" p "\t" nr "\tact\t" substr(C[dc], RSTART, RLENGTH) "\t" r }
        BEGIN { while ((getline l < af) > 0) A[l] = 1 }
        { if (pend != "") { if (issep($0)) { sethdr(pend); delete seen; pend = ""; next } if (have) data(pend, pnr); pend = "" }
          if (issep($0)) next
          if ($0 ~ /^\|/) { pend = $0; pnr = NR } }
        END { if (pend != "" && have) data(pend, pnr) }' "$W/head" > "$W/ix"
      awk -F'\t' '$1 == "V"' "$W/ix" >> "$W/out"
      awk -F'\t' '$1 == "D" {print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6}' "$W/ix" >> "$W/dates"
      ;;
    manifest)
      at_base "$path" > "$W/base"; at_head "$path" > "$W/head"
      # append-only sections: Spec amendments applied, Plan extensions
      LC_ALL=C awk -F'\t' -v bf="$W/base" '
        BEGIN { while ((getline l < bf) > 0) { n++; if (l ~ /^##[[:space:]]/) cur = (l ~ /^##[[:space:]]+(Spec amendments applied|Plan extensions)/) ? l : ""; S[n] = cur } }
        $1 == "R" && S[$2] != "" && $3 !~ /^[[:space:]]*$/ { print $2 "\t" S[$2] "\t" $3 }' "$R" | while IFS="$(printf '\t')" read -r ln sec txt; do
          awk -F'\t' '$1 == "A" {print $4}' "$R" | norm | grep -qxF -- "$(printf '%s' "$txt" | norm)" && continue
          add V append-only "$path" "$ln" "" append-only "manifest line $ln in '$sec' removed or rewritten — that section only appends (BM-MANIFEST-01)"
        done
      # chain rows: ids never re-bind to another slug; NEW rows sit under a numbered `### Round <n>` banner (V13)
      chain() { LC_ALL=C awk '/^##[[:space:]]+The chain/ {f = 1; b = ""; next} f && /^##[[:space:]]/ {f = 0} f && /^###[[:space:]]/ {b = $0; next}
                  f && /^\|/ && match($0, /[0-9A-Za-z_.-]+\.md/) { print NR "\t" substr($0, RSTART, RLENGTH) "\t" (b == "" ? "-" : b) }' "$1"; }
      chain "$W/base" > "$W/ch.base"; chain "$W/head" > "$W/ch.head"
      awk -F'\t' '$1 == "A" {print $2}' "$R" > "$W/alines"
      awk -F'\t' -v af="$W/alines" -v bf="$W/ch.base" -v p="$path" '
        function idof(f,   x) { x = f; sub(/^[0-9][0-9]*[a-z]?_/, "", x); sub(/\.md$/, "", x); if (index(x, "__")) { sl = substr(x, index(x, "__") + 2); x = substr(x, 1, index(x, "__") - 1) } else sl = ""; return x }
        BEGIN { while ((getline l < af) > 0) A[l] = 1; while ((getline l < bf) > 0) { split(l, x, "\t"); F[x[2]] = 1; id = idof(x[2]); SL[id] = sl } }
        ($1 in A) && !($2 in F) {
          id = idof($2)
          if ((id in SL) && SL[id] != sl) print "V\tmanifest\t" p "\t" $1 "\t\tid-registry\tchain id " id " re-bound from slug \x27" SL[id] "\x27 to \x27" sl "\x27 — an id never binds to another file (BM-MANIFEST-03)"
          if ($3 !~ /^###[[:space:]]+Round[[:space:]]+[0-9]+/) print "V\tmanifest\t" p "\t" $1 "\t\tround-banner\tnew chain row " $2 " is not under a numbered \x27### Round <n>\x27 banner (BM-MANIFEST-01, V13)" }' "$W/ch.head" >> "$W/out"
      LC_ALL=C awk -v af="$W/alines" -v p="$path" '
        BEGIN { while ((getline l < af) > 0) A[l] = 1 }
        /^##[[:space:]]/ { s = ($0 ~ /^##[[:space:]]+(Spec amendments applied|Plan extensions)/); next }
        s && (NR in A) && match($0, /^[-|][[:space:]|*]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) { print p "\t" NR "\tact\t" substr($0, RSTART + RLENGTH - 10, 10) "\t" $0 }' "$W/head" >> "$W/dates"
      ;;
    contract|adr|policy-ao)
      [ "$cls" = adr ] && [ "$st" = "A" ] && {
        at_head "$path" | awk -v p="$path" '/^##[[:space:]]/ {exit} /^[[:space:]]*(-[[:space:]]*)?(\*\*)?Date:/ && match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) { print p "\t" NR "\tact\t" substr($0, RSTART, RLENGTH) "\t" $0; exit }' >> "$W/dates"
        continue; }
      at_base "$path" > "$W/base"
      lastnb="$(awk 'NF {n = NR} END {print n + 0}' "$W/base")"
      awk -F'\t' '$1 == "R" {print $2 "\t" $3}' "$R" | while IFS="$(printf '\t')" read -r ln txt; do
        case "$cls" in contract) what="an executed contract is frozen; amend it with an appended '> Amended <date -u +%F>:' note (BM-TICKET-04)" ;;
                       adr) what="a landed ADR is frozen; only an appended 'Superseded by ADR-NNN (<date -u +%F>)' line is allowed (BM-ADR-01)" ;;
                       *) what="this file only appends at EOF (record_policy/history.policy)" ;; esac
        add V frozen "$path" "$ln" "" frozen "line $ln removed or rewritten — $what"
      done
      first_added=1
      awk -F'\t' '$1 == "A" {print $2 "\t" $3 "\t" $4}' "$R" | while IFS="$(printf '\t')" read -r hl ins txt; do
        if [ "$ins" -lt "$lastnb" ]; then add V frozen "$path" "$hl" "" append-position "line $hl inserted before the end of a frozen/append-only file — append at EOF (BM-HIST-01)"; continue; fi
        blank "$txt" && continue
        case "$cls" in
          contract)
            printf '%s' "$txt" | grep -qE '^>' || add V frozen "$path" "$hl" "" amendment "added line $hl is not part of a '> Amended <date -u +%F>:' note (BM-TICKET-04)"
            if printf '%s' "$txt" | grep -qE '^>[[:space:]]*Amended'; then
              d="$(printf '%s' "$txt" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
              [ -n "$d" ] && printf '%s\t%s\tact\t%s\t%s\n' "$path" "$hl" "$d" "$txt" >> "$W/dates"
            fi ;;
          adr)
            if printf '%s' "$txt" | grep -qE 'Superseded by ADR-[0-9]+'; then
              sup="$(printf '%s' "$txt" | grep -oE 'ADR-[0-9]+' | head -1)"
              head_files docs/adr | grep -qE "^docs/adr/${sup}-" \
                || add V frozen "$path" "$hl" "" superseded-by "the superseding $sup does not exist (BM-ADR-01)"
              d="$(printf '%s' "$txt" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
              [ -n "$d" ] && printf '%s\t%s\tact\t%s\t%s\n' "$path" "$hl" "$d" "$txt" >> "$W/dates"
            else
              add V frozen "$path" "$hl" "" frozen "added line $hl changes a landed ADR — only a 'Superseded by ADR-NNN (<date -u +%F>)' line may be appended (BM-ADR-01)"
            fi ;;
        esac
      done
      ;;
    jsonl)
      at_base "$path" > "$W/base"; at_head "$path" > "$W/head"
      bs="$(wc -c < "$W/base" | tr -d ' ')"
      if [ "$bs" -gt 0 ] && ! head -c "$bs" "$W/head" | cmp -s - "$W/base"; then
        add V prefix "$path" 0 "" prefix "$path no longer starts with its previous $bs bytes — a .jsonl record file only appends (BM-HIST-01)"
      fi
      awk -F'\t' '$1 == "A" {print $2 "\t" $4}' "$R" | while IFS="$(printf '\t')" read -r hl txt; do
        d="$(printf '%s' "$txt" | grep -oE '"recorded_at"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/')"
        [ -n "$d" ] && printf '%s\t%s\tact\t%s\t%s\n' "$path" "$hl" "$d" "$txt" >> "$W/dates"
      done
      ;;
    digest)
      judge_append_only_file "$path" "$R" append-only
      awk -F'\t' '$1 == "A" && $4 ~ /^##[[:space:]]+[0-9]/ {print $2 "\t" $4}' "$R" | while IFS="$(printf '\t')" read -r hl txt; do
        d="$(printf '%s' "$txt" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9:]+Z)?' | head -1)"
        printf '%s\t%s\tact\t%s\t%s\n' "$path" "$hl" "$d" "$txt" >> "$W/dates"
      done
      ;;
    runpr)
      # a run ledger that was already closed at the base only gains lines (one honest closeout, BM-INDEX-02)
      case "$path" in docs/build/runs/*)
        at_base "$path" | run_closed && judge_append_only_file "$path" "$R" append-only ;;
      esac
      awk -F'\t' '$1 == "A" {print $2 "\t" $4}' "$R" | while IFS="$(printf '\t')" read -r hl txt; do
        printf '%s' "$txt" | grep -qE '^[[:space:]]*(-[[:space:]]*)?(\*\*)?(Date|Started|Closed|Landed|Recorded)(\*\*)?:' || continue
        d="$(printf '%s' "$txt" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}:?[0-9]{2})?)?' | head -1)"
        [ -n "$d" ] && printf '%s\t%s\tact\t%s\t%s\n' "$path" "$hl" "$d" "$txt" >> "$W/dates"
      done
      ;;
    planning)
      at_head "$path" > "$W/head"; awk -F'\t' '$1 == "A" {print $2}' "$R" > "$W/alines"
      LC_ALL=C awk -v af="$W/alines" -v p="$path" '
        BEGIN { while ((getline l < af) > 0) A[l] = 1 }
        /^#+[[:space:]]/ { cl = (tolower($0) ~ /change[[:space:]-]*log/); next }
        !(NR in A) { next }
        cl && /^-[[:space:]]/ { s = $0; gsub(/[*`]/, "", s); if (match(s, /^-[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]([T ][0-9][0-9]:[0-9][0-9](:[0-9][0-9])?(Z|[+-][0-9][0-9]:?[0-9][0-9])?)?/)) { d = substr(s, RSTART, RLENGTH); sub(/^-[[:space:]]*/, "", d); print p "\t" NR "\tact\t" d "\t" $0 } ; next }
        /^[[:space:]]*updatedAt:/ { s = $0; sub(/^[[:space:]]*updatedAt:[[:space:]]*/, "", s); if (match(s, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]([T ][0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z?)?/)) print p "\t" NR "\tact\t" substr(s, RSTART, RLENGTH) "\t" $0 }' "$W/head" >> "$W/dates"
      ;;
  esac
  # repo policy: extra record positions
  pol date | while read -r _k g ere; do
    case "$path" in $g) awk -F'\t' '$1 == "A" {print $2 "\t" $4}' "$R" | while IFS="$(printf '\t')" read -r hl txt; do
        printf '%s' "$txt" | grep -qE -- "$ere" || continue
        d="$(printf '%s' "$txt" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}:?[0-9]{2})?)?' | head -1)"
        [ -n "$d" ] && printf '%s\t%s\tact\t%s\t%s\n' "$path" "$hl" "$d" "$txt" >> "$W/dates"
      done ;; esac
  done
done < "$W/changed"

# ── Record dates (R1, R2, R3, R5) and the commit clock (R6) ─────────────────
# Each added line takes the committer time of the last commit in the range that added it.
: > "$W/times"
HEAD_T="$NOW_EPOCH"; HEAD_L="$NOW_ISO"; HEAD_SHA="staged"
if [ "$MODE" != staged ]; then
  HEAD_T="$(G log -1 --format=%ct "$HEADC")"; HEAD_L="$(G log -1 --format=%cI "$HEADC")"; HEAD_SHA="$(G rev-parse --short "$HEADC")"
  RANGE="$HEADC"; [ "$BASE" != "$EMPTY_TREE" ] && RANGE="$BASE..$HEADC"
  G log --reverse -p --no-renames --no-color -U0 --format='@@C %h %ct %cI' "$RANGE" -- docs $POL_PATHS 2>/dev/null | LC_ALL=C awk '
    /^@@C / { sha = $2; ct = $3; ci = $4; next }
    /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); next }
    /^\+/ && f != "" { print f "\t" sha "\t" ct "\t" ci "\t" substr($0, 2) }' > "$W/times"
  G log --format='%h %ct %cI' "$RANGE" 2>/dev/null | while read -r sha ct ci; do
    [ "$ct" -gt $((NOW_EPOCH + 300)) ] 2>/dev/null && add V commit-clock "-" 0 "$sha" R6 "commit $sha is dated $ci, later than the clock $NOW_ISO + 5 min — fix the committer clock (BM-CLOCK-01)"
  done
fi
pol allow > "$W/allow"
NDATES="$(wc -l < "$W/dates" | tr -d ' ')"
LC_ALL=C awk -F'\t' "$CLOCK_AWK"'
  BEGIN { now = '"$NOW_EPOCH"'; nowiso = "'"$NOW_ISO"'"
          while ((getline l < "'"$W/times"'") > 0) { split(l, x, "\t"); k = x[1] SUBSEP substr(l, length(x[1] x[2] x[3] x[4]) + 5); T[k] = x[3]; CI[k] = x[4]; SH[k] = x[2] }
          na = 0; while ((getline l < "'"$W/allow"'") > 0) { na++; n = split(l, y, " "); AG[na] = y[2]; AE[na] = y[3]; s = ""; for (i = 4; i <= n; i++) s = s (i > 4 ? " " : "") y[i]; AS[na] = s } }
  function globre(g,   r) { r = g; gsub(/\./, "\\.", r); gsub(/\*/, ".*", r); gsub(/\?/, ".", r); return "^" r "$" }
  function ok1(d, ct, cl) { return has_time(d) ? (epoch(d) <= (ct < now ? ct : now) + 300) : (substr(d, 1, 10) <= (udate(ct) > substr(cl, 1, 10) ? udate(ct) : substr(cl, 1, 10))) }
  function ok2(d, ct) { return has_time(d) ? (epoch(d) >= ct - 172800) : (substr(d, 1, 10) >= udate(ct - 172800)) }
  {
    p = $1; ln = $2; cls = $3; d = $4; txt = $5; k = p SUBSEP txt
    if (k in T) { ct = T[k]; cl = CI[k]; sh = SH[k] } else { ct = '"$HEAD_T"'; cl = "'"$HEAD_L"'"; sh = "'"$HEAD_SHA"'" }
    if (epoch(d) < 0) { print "V\trecord-dates\t" p "\t" ln "\t" sh "\tR1\tunparseable record date \x27" d "\x27"; next }
    ev++
    exempt = (txt ~ /future-ok:/); expired = ""
    for (i = 1; i <= na; i++) if (p ~ globre(AG[i]) && index(txt, AS[i])) { if (now <= epoch(AE[i])) exempt = 1; else expired = AE[i] }
    if (!exempt && !ok1(d, ct, cl)) {
      corr = 0
      if (tolower(txt) ~ /correct|date correction|→ *true|recorded .* → /) { s = txt
        while (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]([T ][0-9][0-9]:[0-9][0-9](:[0-9][0-9])?(Z|[+-][0-9][0-9]:?[0-9][0-9])?)?/)) {
          o = substr(s, RSTART, RLENGTH); if (o != d && ok1(o, ct, cl)) corr = 1; s = substr(s, RSTART + RLENGTH) } }
      if (!corr) print "V\trecord-dates\t" p "\t" ln "\t" sh "\tR1\trecord date " d " is later than its commit (" cl ")" (expired != "" ? "; its allow entry expired " expired : "") " — write the time from `date -u` at recording; a scheduled or real-world value is marked `future-ok: <class>: <reason>` (BM-CLOCK-01)"
    }
    if (cls == "act" && txt !~ /≤|retro:|as-of/ && !ok2(d, ct))
      print "V\trecord-dates\t" p "\t" ln "\t" sh "\tR2\tact date " d " is more than 48 h before its commit (" cl ") — a late recording says `retro: <evidence>` or `as-of <sha|#PR>` (BM-CLOCK-01)"
  }
  END { print "C\trecord-dates\t" NR "\t" ev + 0 > "/dev/stderr" }' "$W/dates" >> "$W/out" 2>> "$W/counts"
printf 'C\tappend-only\t%s\t%s\n' "$CAND_LINES" "$CAND_LINES" >> "$W/counts"

# ── Report ──────────────────────────────────────────────────────────────────
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
NV="$(awk -F'\t' '$1 == "V"' "$W/out" | wc -l | tr -d ' ')"; NW="$(awk -F'\t' '$1 == "W"' "$W/out" | wc -l | tr -d ' ')"
EX=0; [ "$NV" -gt 0 ] && EX=1
diags() {   # split on \037, never <tab>: `read` merges adjacent tabs, so an empty commit would shift rule/message
  local first=1
  awk -F'\t' -v k="$1" '$1 == k' "$W/out" | tr '\t' '\037' | while IFS="$(printf '\037')" read -r _k c f l sh r m; do
    [ "$first" -eq 1 ] || printf ','; first=0
    printf '{"check":"%s","severity":"%s","file":"%s","line":%s,"commit":"%s","rule":"%s","message":"%s"}' \
      "$(esc "$c")" "$2" "$(esc "$f")" "${l:-0}" "$(esc "$sh")" "$(esc "$r")" "$(esc "$m")"
  done
}
{
  printf '{"schema":"build-memory-history/1","tool":"check-history.sh",'
  printf '"input":{"repo":"%s","mode":"%s","base":"%s","head":"%s","now":"%s","policy":%s,"guards":%s},' \
    "$(esc "$REPO")" "$MODE" "$BASE" "$( [ "$MODE" = staged ] && echo index || echo "$HEADC")" "$NOW_ISO" "$([ -f "$POL" ] && echo true || echo false)" "$([ "$GUARDS" -eq 1 ] && echo true || echo false)"
  printf '"summary":{"violations":%s,"warnings":%s,"exit":%s},"counts":{' "$NV" "$NW" "$EX"
  awk -F'\t' 'BEGIN {f = 1} $1 == "C" { if (!f) printf ","; f = 0; printf "\"%s\":{\"candidates\":%s,\"evaluated\":%s}", $2, $3, $4 }' "$W/counts"
  printf '},"violations":['; diags V error; printf '],"warnings":['; diags W warning; printf ']}\n'
} > "$JSON.tmp" && mv "$JSON.tmp" "$JSON" || { rm -f "$JSON.tmp" 2>/dev/null; echo "check-history: cannot write report to $JSON — unknown, never green" >&2; exit 5; }

echo "check-history: $MODE ${ARG:-} ($(printf '%.12s' "$BASE")..$( [ "$MODE" = staged ] && echo index || printf '%.12s' "$HEADC")) in $REPO"
if [ "$NV" -eq 0 ]; then echo "  ✓ no violations ($NW warning(s); $NDATES record date(s), $CAND_LINES changed protected line(s) judged)"
else echo "  ✗ $NV violation(s), $NW warning(s):"; fi
awk -F'\t' '$1 == "V" {printf "    - %s [%s] %s:%s%s: %s\n", $2, $6, $3, $4, ($5 != "" ? " @" $5 : ""), $7}' "$W/out"
awk -F'\t' '$1 == "W" {printf "    ~ %s [%s] %s:%s: %s\n", $2, $6, $3, $4, $7}' "$W/out"
echo "  JSON: $JSON"
exit "$EX"
