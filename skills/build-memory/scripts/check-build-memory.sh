#!/usr/bin/env bash
# check-build-memory.sh — validate a repo's build-memory layout. (BM-VALID-01.)
#
# Read-only. Everything the other skills derive (ADR index, BUILD_INDEX rows, the
# ticket sequence, DEFERRALS ids, the layout) is CHECKED here, never trusted:
# decompose-spec runs it after seeding, implement-spec before its close commit,
# orchestrate-build at every boundary. A failure is a real block.
#
# Usage:
#   check-build-memory.sh [repo_root] [--json PATH] [--now ISO]            tree mode (default)
#   check-build-memory.sh [repo_root] --range BASE..HEAD | --staged | --first-parent SHA
#                         [--json PATH] [--now ISO]                        history mode (check-history.sh)
#   check-build-memory.sh [repo_root] --planning <ledger> [--json PATH]    planning-ledger freshness (V14)
#
# Arguments:
#   repo_root — the repo/worktree to check (default: current git toplevel, else cwd).
#   --json PATH — write the report here (default: a unique mktemp file; the path is the last stdout line).
#   --now ISO   — the clock for the date checks (default: `date -u`; for tests).
#   --range / --staged / --first-parent — history mode: judge only the lines a change adds or removes
#                 (append-only, append position, record dates; BM-HIST-01). Runs check-history.sh, which
#                 delegates to a repo hook docs/build/tools/memory_guard.* when one exists.
#   --planning  — check a synthesize-spec research ledger or a planning ledger (V14, BM-SYNTH-02): updatedAt is
#                 not older than the newest change-log stamp; lastCompleted names the newest done row;
#                 nextUnit is not a done row. Needs no build-memory marker.
#
# Checks (each violation names the file and the rule):
#   - layout: only the named entries at the root of docs/build/; logs/.gitignore present
#   - ticket filenames: grammar (NN[a-z]?_<ID>__<slug>.md) + unique ids (an inserted sub-ticket
#     may share the numeric prefix of another, e.g. 16_P0.15 / 16_P0.15b, as long as the id differs);
#     a legacy filename is accepted when the manifest chain table lists it
#   - manifest <-> files: every chain row has a file; every ticket file has a chain row
#     (companions excepted); every HUMAN/GATE marker is a chain row
#   - Depends on: only points backward (no forward dependency)
#   - skeletons: Kind: skeleton has NO Run: line
#   - DEFERRALS.md: ids unique; a canonical status {OPEN,PARTIAL,DONE,WONTFIX,ACCEPTED-SKELETON}
#     appears as a word in each row's last cell (markdown/prose around it tolerated);
#     no OPEN row scoped to a gate whose readout says PASSED (a readout's `Status:` line,
#     when present, decides); warn: an OPEN/PARTIAL kind-P row lacks owner:/trigger: (rule 5)
#   - ADRs: files <-> generated index (regenerate + diff; an index the pre-0.5.0 parser produced
#     only warns); every ADR has ## Revisit trigger; spec ADR appendix equals the file set when
#     resolvable; an index cell that reads `—` warns (fails for an ADR added after the guards marker)
#   - LEDGER.md: the CURRENT STATE key set present and in order (optional `harness` only between
#     round and updatedAt); nextTicket names a chain row or DONE; every PHASE LOG "done" entry has a
#     BUILD_INDEX row and runs/<ID>.md. The PHASE LOG parser strips `*`/`_`/backtick markup and
#     reports candidates/evaluated; an entry that parses only after stripping markup is judged
#     guarded (older PHASE LOG regions: warn). Exit 3 (vacuous) when done entries exist but fewer
#     than half parse.
#   - CURRENT STATE values (guarded): projectStatus ∈ NOT_STARTED|IN_PROGRESS|BLOCKED|PAUSED|DONE;
#     pauseRequested ∈ true|false; mergePolicy ∈ NONE|OPERATOR|AUTO-BOTTOM-UP; autonomy ∈
#     auto|checkpoint|manual; round an integer; updatedAt ISO-8601 (`<…>`/`(…)` seed placeholders skip)
#   - LEDGER.md budget + shape (BM-LEDGER-08; guarded — warn, or fail under the guards
#     marker): orient region <= 12 KiB (warn > 8 KiB); CURRENT STATE <= 3 KiB, lines <= 256 B, no
#     `| PRIOR`; returnPass an id list; no other line begins with a CURRENT STATE key; the last `## `
#     heading is a PHASE LOG heading; its entries <= 2 KiB (older regions: warn); every repo path
#     named in the orient region exists and no stale token appears (`.agents/scratch`,
#     `gitignored`, `Do not resume until`, + docs/build/tools/record_policy/stale_tokens.txt)
#   - GATE DECISIONS in the 7-column form (header has `kind`; guarded): each row's kind is
#     decision | pre-authorization | confirmation | waiver | correction (BM-GATE-05), and a
#     pre-authorization row carries `expires:` and `voided-by:` (BM-GATE-09). Legacy 6-column
#     tables and bullet-style records are not judged.
#   - warnings: projectStatus DONE without a signed readouts/GATE-ACCEPT.md; a seed ledger
#     (PHASE LOG = the seed entry) whose GATE DECISIONS holds a non-pre-authorization row;
#     nextTicket is not the lowest chain row not yet landed (V2: a row leaves the order only by a
#     gate-cell token superseded-by(…) / superseded-by-split / deferred(…) / unused, or as a HUMAN
#     row; a legacy bare word in the gate cell still skips, with a warning); two or more
#     `repair — close:` entries in the current PHASE LOG region
#     while blockedOn is empty (BM-LEDGER-06); the orient recipe (BM-ORIENT-01) reads > 48 KiB;
#     a record-position date later than the clock (BM-CLOCK-01; `future-ok` exempts); a chain row
#     not under a numbered `### Round <n>` banner (history mode fails added ones)
#   - BUILD_INDEX (warn; history mode fails added rows): every row has its header's column count;
#     seq values unique; no `PR pending`/`TBD` in a row whose run ledger is Closed: (a dated
#     `Closed:` stamp in its header, before the first `##` heading); the live
#     verification value ∈ live-executed|staging|fixture-only|engineered|n-a|gate-pending (legacy `run`)
#   - readouts (BM-INDEX-03): the guard sentence — fail for a readout created after the guards marker,
#     else warn; run ledgers (BM-HARNESS-01): a `Harness:` line — fail for one created after the
#     guards marker, else warn
#   - tests (BM-TEST-01; heuristic warning `living-pin?`): a tracked test file that names a living
#     record file and one of its living keys
#   - REQ coverage (when canonicalSpec + req_id_pattern resolve): every id a ticket cites
#     exists in the spec; every in-scope id has exactly one owner
#   - size + secrets: fixtures >1MB / any file >5MB under docs/build flagged; no secret
#     token shapes in docs/build (incl. reports/digests/) or docs/tickets
#
# Output:
#   Human-readable summary to stdout; the last line names the JSON report path.
#   JSON report (schema build-memory-check/2) to --json PATH or a unique mktemp file:
#   {"schema","tool","input":{"repo","commit","dirty","input_digest"},"buildMemory","guards",
#    "summary":{"violations","warnings","exit"},"counts":{…candidates/evaluated…},
#    "violations":[{check,severity,file,obligation,evidence,message}],"warnings":[…]}
#   input_digest is a sha256 over the sha256 of every file the checker read.
#
# Exit codes (the shared build-script contract):
#   0 — clean (build-memory repo, no violations)
#   1 — violations found
#   2 — not a build-memory repo (no docs/build/README.md marker), --planning file missing, or the
#       JSON report cannot be written
#   3 — vacuous: a check found candidates but could evaluate (almost) none of them — never green
#   (history mode adds 5 — unknown: shallow clone / unresolvable range; see check-history.sh)
#
# Guards marker (BM-COMPAT-06): a line `<!-- build-memory-guards: 1 -->` alone in
# docs/build/README.md turns the guarded checks from warnings into violations.
#
# Read-only: never writes or mutates the repo (only the JSON report).
# Compatible with bash 3.2+ (macOS default). No associative arrays, no mapfile.

set -o pipefail

REPO="" ; JSON="" ; NOW_ARG="" ; PLANNING="" ; HIST=0
HIST_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --json)      JSON="${2:-}"; shift 2 ;;
    --json=*)    JSON="${1#--json=}"; shift ;;
    --now)       NOW_ARG="${2:-}"; shift 2 ;;
    --planning)  PLANNING="${2:-}"; shift 2 ;;
    --range|--first-parent) HIST=1; HIST_ARGS+=("$1" "${2:-}"); shift 2 ;;
    --staged)    HIST=1; HIST_ARGS+=("$1"); shift ;;
    --no-hook)   HIST_ARGS+=("$1"); shift ;;
    -h|--help)   awk 'NR > 1 && !/^#/ {exit} NR > 1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    -*) echo "check-build-memory: unknown argument '$1' (try --help)" >&2; exit 2 ;;
    *)  if [ -z "$REPO" ]; then REPO="$1"; else echo "check-build-memory: unexpected argument '$1'" >&2; exit 2; fi; shift ;;
  esac
done
REPO="${REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
REPO="$(cd "$REPO" 2>/dev/null && pwd || printf '%s' "$REPO")"
MARKER='<!-- build-memory: v2 -->'
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# History mode is a separate script (BM-HIST-01); it has its own report and exit codes.
if [ "$HIST" -eq 1 ]; then
  set -- --repo "$REPO" "${HIST_ARGS[@]}"
  [ -n "$JSON" ] && set -- "$@" --json "$JSON"
  [ -n "$NOW_ARG" ] && set -- "$@" --now "$NOW_ARG"
  exec bash "$SELF_DIR/check-history.sh" "$@"
fi

if [ -z "$JSON" ]; then
  # Unique per-invocation report path — concurrent worktrees never race over one /tmp file.
  # BSD mktemp substitutes only trailing X's, so the template carries no .json suffix.
  JSON="$(mktemp "${TMPDIR:-/tmp}/build-memory-check.XXXXXXXX")" || exit 2
else
  _jd="$(dirname "$JSON")"; [ -d "$_jd" ] || mkdir -p "$_jd" 2>/dev/null || true
fi

_hash_list() {   # stdin: file paths, one per line → one sha256 hex per file, same order (batched)
  if command -v sha256sum >/dev/null 2>&1; then tr '\n' '\0' | xargs -0 sha256sum | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then tr '\n' '\0' | xargs -0 openssl dgst -sha256 | awk '{print $NF}'
  else tr '\n' '\0' | xargs -0 shasum -a 256 | awk '{print $1}'; fi
}
_sha256_stream() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}';
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}';
  else openssl dgst -sha256 | awk '{print $NF}'; fi
}
_json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g'; }
# run_closed < runs/<ID>.md → 0 when the run ledger is closed: its header (the lines before its first `##`
# heading) carries a dated `Closed:` stamp (BM-INDEX-02). A body line such as `- **Closed:** none.` under a
# deferrals section, or an undated placeholder, is not a close. (check-history.sh uses the same rule.)
run_closed() {
  # reads to EOF (no early exit): under pipefail an early exit could SIGPIPE `git show` and read as "open"
  LC_ALL=C awk 'hdr_done { next } /^##+[[:space:]]/ { hdr_done = 1; next } { s = $0; gsub(/[*_`]/, "", s) }
    s ~ /^[[:space:]]*(-[[:space:]]*)?Closed:[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { f = 1; hdr_done = 1 }
    END { exit !f }'
}

# ── The clock (BM-CLOCK-01) ──────────────────────────────────────────────────
NOW_ISO="${NOW_ARG:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
# epoch(<ISO>) in portable awk (no mktime): YYYY-MM-DD[THH:MM[:SS]][Z|±HH[:MM]]; date-only = 00:00Z.
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
'
NOW_EPOCH="$(awk "$CLOCK_AWK"' BEGIN { print epoch(ARGV[1]); ARGV[1] = "" }' "$NOW_ISO")"
NOW_DATE="$(printf '%s' "$NOW_ISO" | cut -c1-10)"
case "$NOW_EPOCH" in ''|-1|*[!0-9]*) echo "check-build-memory: --now '$NOW_ISO' is not an ISO-8601 time" >&2; exit 2 ;; esac

VIOL="$(mktemp)"; WARN="$(mktemp)"; TMPS="$VIOL $WARN"
trap 'rm -f $TMPS 2>/dev/null' EXIT
newtmp() { local t; t="$(mktemp)"; TMPS="$TMPS $t"; printf '%s' "$t"; }
# diag record: <check>\t<file>\t<obligation>\t<evidence>\t<message>
viol() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "${3:-}" "${4:-}" "${5:-}" "$2" >> "$VIOL"; }
warn() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "${3:-}" "${4:-}" "${5:-}" "$2" >> "$WARN"; }
COUNTS=""   # ,"<check>":{"candidates":n,"evaluated":m}
count() { COUNTS="$COUNTS,\"$1\":{\"candidates\":$2,\"evaluated\":$3}"; }
VACUOUS=0

write_report() {   # write_report <exit> <buildMemory true|false> [guards]
  local ex="$1" bm="$2" nv nw commit dirty digest inset
  nv="$(wc -l < "$VIOL" | tr -d ' ')"; nw="$(wc -l < "$WARN" | tr -d ' ')"
  commit="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"; dirty=false
  if [ -n "$commit" ] && [ -n "$(git -C "$REPO" status --porcelain -- docs/build docs/tickets docs/adr ${PLANNING:+"$PLANNING"} 2>/dev/null)" ]; then dirty=true; fi
  inset="$(newtmp)"
  {
    [ -d "$REPO/docs/build" ] && find "$REPO/docs/build" -type f ! -path '*/logs/*' 2>/dev/null
    [ -d "$REPO/docs/tickets" ] && find "$REPO/docs/tickets" -type f -name '*.md' 2>/dev/null
    [ -d "$REPO/docs/adr" ] && find "$REPO/docs/adr" -type f -name '*.md' 2>/dev/null
    [ -n "${SPEC:-}" ] && [ -f "$SPEC" ] && printf '%s\n' "$SPEC"
    [ -n "${PLAN_FILE:-}" ] && [ -f "$PLAN_FILE" ] && printf '%s\n' "$PLAN_FILE"
    true
  } | sort -u > "$inset"
  digest="$( { [ -s "$inset" ] && _hash_list < "$inset"; } | _sha256_stream)"
  emit_diags() {
    # Split on \037, never on <tab>: tab is IFS whitespace, so `read` would merge adjacent tabs and a
    # diagnostic with an empty file/obligation/evidence field would put its message under the wrong key.
    local first=1 c f o e m
    while IFS="$(printf '\037')" read -r c f o e m; do
      [ -n "$c" ] || continue
      [ "$first" -eq 1 ] || printf ','; first=0
      printf '{"check":"%s","severity":"%s","file":"%s","obligation":"%s","evidence":"%s","message":"%s"}' \
        "$(_json_escape "$c")" "$2" "$(_json_escape "$f")" "$(_json_escape "$o")" "$(_json_escape "$e")" "$(_json_escape "$m")"
    done < <(tr '\t' '\037' < "$1")
  }
  {
    printf '{"schema":"build-memory-check/2","tool":"check-build-memory.sh",'
    printf '"input":{"repo":"%s","commit":"%s","dirty":%s,"input_digest":"%s","now":"%s"},' \
      "$(_json_escape "$REPO")" "$commit" "$dirty" "$digest" "$NOW_ISO"
    printf '"buildMemory":%s,"guards":%s,' "$bm" "${3:-false}"
    printf '"summary":{"violations":%s,"warnings":%s,"exit":%s},' "$nv" "$nw" "$ex"
    printf '"counts":{%s},' "${COUNTS#,}"
    printf '"violations":['; emit_diags "$VIOL" error
    printf '],"warnings":['; emit_diags "$WARN" warning
    printf ']}\n'
  # A report that cannot be written exits 2 — never an exit code without its report.
  } > "$JSON.tmp" && mv "$JSON.tmp" "$JSON" || { rm -f "$JSON.tmp" 2>/dev/null; echo "check-build-memory: cannot write report to $JSON" >&2; exit 2; }
}
human() {   # print the summary + the report path, then exit with $1
  local ex="$1" nv nw
  nv="$(wc -l < "$VIOL" | tr -d ' ')"; nw="$(wc -l < "$WARN" | tr -d ' ')"
  if [ "$nv" -eq 0 ]; then
    echo "  ✓ no violations ($nw warning(s))"
  else
    echo "  ✗ $nv violation(s), $nw warning(s):"
    awk -F'\t' '{printf "    - %s: %s\n", $1, $5}' "$VIOL"
  fi
  [ "$nw" -gt 0 ] && awk -F'\t' '{printf "    ~ %s: %s\n", $1, $5}' "$WARN"
  echo "  JSON: $JSON"
  exit "$ex"
}

# ── Planning-ledger freshness (V14; BM-SYNTH-02) — no build-memory marker needed ──
if [ -n "$PLANNING" ]; then
  case "$PLANNING" in /*) PLAN_FILE="$PLANNING" ;; *) PLAN_FILE="$REPO/$PLANNING" ;; esac
  echo "check-build-memory --planning: $PLAN_FILE"
  if [ ! -f "$PLAN_FILE" ]; then
    viol planning "no planning ledger at $PLANNING" "$PLANNING"; write_report 2 false; human 2
  fi
  pval() { grep -m1 -E "^[[:space:]]*${1}:" "$PLAN_FILE" 2>/dev/null | sed -E "s/^[[:space:]]*${1}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//"; }
  P_UPD="$(pval updatedAt | awk '{print $1}')"; P_LAST="$(pval lastCompleted | awk '{print $1}')"; P_NEXT="$(pval nextUnit | awk '{print $1}')"
  # done rows: tables whose header has `id` and `status` columns; status cell starting with "done".
  P_DONE="$(newtmp)"
  LC_ALL=C awk -F'|' '
    function t(x) { gsub(/[*`]/, "", x); gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
    /^\|/ {
      if ($0 ~ /^\|[-|: ]+\|[[:space:]]*$/) next
      hi = 0; hs = 0
      for (i = 1; i <= NF; i++) { c = tolower(t($i)); if (c == "id") hi = i; if (c == "status") hs = i }
      if (hi && hs) { ic = hi; sc = hs; next }
      if (ic && sc && tolower(t($sc)) ~ /^done/) print t($ic)
      next
    }
    { ic = 0; sc = 0 }' "$PLAN_FILE" | grep -v '^$' | sort -u > "$P_DONE"
  # change-log stamps: bullets under a heading containing "Change log", lead stamp only.
  P_LOG="$(newtmp)"
  LC_ALL=C awk '
    /^#+[[:space:]]/ { inlog = (tolower($0) ~ /change[[:space:]-]*log/); next }
    inlog && /^-[[:space:]]/ {
      s = $0; sub(/^-[[:space:]]*/, "", s); gsub(/[*`]/, "", s)
      if (match(s, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]([T ][0-9][0-9]:[0-9][0-9](:[0-9][0-9])?(Z|[+-][0-9][0-9]:?[0-9][0-9])?)?/))
        print NR "\t" substr(s, RSTART, RLENGTH) "\t" s
    }' "$PLAN_FILE" > "$P_LOG"
  ncl="$(wc -l < "$P_LOG" | tr -d ' ')"; count planning-changelog "$ncl" "$ncl"
  if [ "$ncl" -gt 0 ]; then
    # newest stamp (by time; ties → the later line) and the newest bullet that names a done row
    newest="$(awk -F'\t' "$CLOCK_AWK"'{ e = epoch($2); if (e >= best) { best = e; s = $2; l = $1 } } END { print l "\t" s }' "$P_LOG")"
    n_line="$(printf '%s' "$newest" | cut -f1)"; n_stamp="$(printf '%s' "$newest" | cut -f2)"
    if [ -z "$P_UPD" ]; then
      viol planning "CURRENT STATE has no updatedAt" "$PLANNING"
    else
      stale="$(awk "$CLOCK_AWK"' BEGIN {
          u = ARGV[1]; s = ARGV[2]; ARGV[1] = ""; ARGV[2] = ""
          if (!has_time(u) || !has_time(s)) { print (substr(u, 1, 10) < substr(s, 1, 10)) ? 1 : 0 }
          else print (epoch(u) < epoch(s)) ? 1 : 0 }' "$P_UPD" "$n_stamp")"
      [ "$stale" = "1" ] && viol planning "updatedAt $P_UPD is older than the newest change-log stamp $n_stamp (line $n_line) — set it from \`date -u\` when you write the log line (V14)" "$PLANNING" "updatedAt"
    fi
    fut="$(awk -F'\t' "$CLOCK_AWK"' { e = epoch($2); lim = has_time($2) ? '"$NOW_EPOCH"' + 300 : epoch(substr("'"$NOW_ISO"'", 1, 10)) ; if (e > lim) { n++; if (!f) f = $1 " " $2 } } END { if (n) print n "\t" f }' "$P_LOG")"
    [ -n "$fut" ] && warn clock "$(printf '%s' "$fut" | cut -f1) change-log stamp(s) later than the clock $NOW_ISO (first: line $(printf '%s' "$fut" | cut -f2)) (BM-CLOCK-01)" "$PLANNING"
  fi
  if [ -s "$P_DONE" ]; then
    if [ -z "$P_LAST" ] || ! grep -qxF "$P_LAST" "$P_DONE"; then
      viol planning "lastCompleted '${P_LAST:-<empty>}' is not a done row ($(wc -l < "$P_DONE" | tr -d ' ') row(s) are done) (V14)" "$PLANNING" "lastCompleted"
    elif [ -s "$P_LOG" ]; then
      # the newest change-log bullet (by stamp) that names a done row must name lastCompleted
      named="$(sort -t"$(printf '\t')" -k2,2 -k1,1n "$P_LOG" | awk -F'\t' -v dl="$(tr '\n' ' ' < "$P_DONE")" '
        BEGIN { n = split(dl, D, " "); for (i = 1; i <= n; i++) { R[i] = D[i]; gsub(/\./, "\\.", R[i]) } }
        { ids = ""; for (i = 1; i <= n; i++) { if (D[i] == "") continue
            if (match(" " $3 " ", "[^A-Za-z0-9.]" R[i] "[^A-Za-z0-9]")) ids = ids " " D[i] }
          if (ids != "") last = $1 "\t" ids }
        END { print last }')"
      if [ -n "$named" ] && ! printf ' %s ' "$(printf '%s' "$named" | cut -f2)" | grep -qF " $P_LAST "; then
        viol planning "lastCompleted '$P_LAST' is not the newest done row named in the change log (line $(printf '%s' "$named" | cut -f1) names:$(printf '%s' "$named" | cut -f2)) (V14)" "$PLANNING" "lastCompleted"
      fi
    fi
    [ -n "$P_NEXT" ] && grep -qxF "$P_NEXT" "$P_DONE" && viol planning "nextUnit '$P_NEXT' is already a done row (V14)" "$PLANNING" "nextUnit"
  fi
  ex=0; [ -s "$VIOL" ] && ex=1
  write_report "$ex" false; human "$ex"
fi

BUILD="$REPO/docs/build"
TICKETS="$REPO/docs/tickets"
ADR="$REPO/docs/adr"

# Not a build-memory repo → exit 2 (the two freshness detectors' "nothing to do" convention).
if [ ! -f "$BUILD/README.md" ] || ! grep -qF "$MARKER" "$BUILD/README.md" 2>/dev/null; then
  echo "check-build-memory: $REPO is not a build-memory repo (no docs/build/README.md marker '$MARKER')."
  write_report 2 false
  echo "  JSON: $JSON"
  exit 2
fi

# Guarded rules warn without the guards marker and fail with it (BM-COMPAT-06).
GUARDS=0
grep -qE '^[[:space:]]*<!-- build-memory-guards: 1 -->[[:space:]]*$' "$BUILD/README.md" 2>/dev/null && GUARDS=1
guarded() { if [ "$GUARDS" -eq 1 ]; then viol "$@"; else warn "$@"; fi; }

# "Created after the guards marker": the commit that first added the file is not a strict ancestor of the
# commit that added the marker (same commit or later = new; an uncommitted file is new). Without the marker
# or outside git nothing is new. One `git log` pass caches each file's first-add commit.
IN_GIT=0; git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 && IN_GIT=1
MARKER_C=""; MARKER_STATE=none; ADDS=""; BEFORE=""
if [ "$GUARDS" -eq 1 ] && [ "$IN_GIT" -eq 1 ]; then
  MARKER_C="$(git -C "$REPO" log --format=%H -S'build-memory-guards: 1' -- docs/build/README.md 2>/dev/null | tail -1)"
  if [ -n "$MARKER_C" ]; then
    MARKER_STATE=committed
    BEFORE="$(newtmp)"; git -C "$REPO" rev-list "$MARKER_C" 2>/dev/null | grep -vxF "$MARKER_C" > "$BEFORE"
  else
    MARKER_STATE=uncommitted
  fi
  ADDS="$(newtmp)"
  git -C "$REPO" log --reverse --diff-filter=A --name-only --format='@%H' -- docs/build/runs docs/build/readouts docs/adr 2>/dev/null \
    | awk '/^@/ {c = substr($0, 2); next} NF && !($0 in s) {s[$0] = c; print $0 "\t" c}' > "$ADDS"
fi
created_after_marker() {   # <path relative to REPO> → 0 when new under the guards marker
  [ "$MARKER_STATE" != none ] || return 1
  local c; c="$(awk -F'\t' -v p="$1" '$1 == p {print $2; exit}' "$ADDS")"
  [ -n "$c" ] || return 0                         # not committed yet → new
  [ "$MARKER_STATE" = uncommitted ] && return 1   # committed before the marker was
  grep -qxF "$c" "$BEFORE" && return 1
  return 0
}

# Ticket-id grammar (canonical interpretation of BM-LAYOUT-02; documented in layout.md).
# GATE-ACCEPT is the one named gate marker (the operator's accepted-deviations signature, BM-TAIL-01).
ID_RE='((HUMAN-H|GATE-G)[0-9]+|GATE-ACCEPT|[A-Z]+[0-9]*[a-z]?(\.[0-9]+[a-z]?)?)'
FNAME_RE="^[0-9]{2,3}[a-z]?_${ID_RE}__[a-z0-9-]+\.md$"

# ── LEDGER value reader (never-fail; strips inline comments) ──────────────────
LEDGER="$BUILD/LEDGER.md"
lval() {
  [ -f "$LEDGER" ] || return 0
  grep -m1 -E "^[[:space:]]*${1}:" "$LEDGER" 2>/dev/null \
    | sed -E "s/^[[:space:]]*${1}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//"
}

MANIFEST_REL="$(lval manifest)"; [ -n "$MANIFEST_REL" ] || MANIFEST_REL="docs/tickets/00_MANIFEST.md"
case "$MANIFEST_REL" in /*) MANIFEST="$MANIFEST_REL" ;; *) MANIFEST="$REPO/$MANIFEST_REL" ;; esac

# ── 1. Layout: allowlist at the root of docs/build/ ──────────────────────────
ALLOWED=" README.md LEDGER.md BUILD_INDEX.md runs pr readouts planning reports tools fixtures logs COVERAGE_MATRIX.csv CAPSTONE_GAP_ANALYSIS.md COMPOSED_E2E_REPORT.md CAPSTONE_CLOSURE.md BACKLOG.csv BACKLOG.md TICKET_VS_SPEC.md SPEC_RECONCILIATION_PLAN.md INTEGRATION_PLAN.md OPERATIONAL_READINESS.md "
for entry in "$BUILD"/* "$BUILD"/.[!.]*; do
  [ -e "$entry" ] || continue
  b="$(basename "$entry")"
  case "$ALLOWED" in *" $b "*) : ;; *) viol layout "docs/build/$b is not an allowed build-memory root entry" "docs/build/$b" ;; esac
done
# logs/.gitignore present with the right contents (BM-LAYOUT-03).
if [ ! -f "$BUILD/logs/.gitignore" ]; then
  viol layout "docs/build/logs/.gitignore is missing (must contain '*' and '!.gitignore')" "docs/build/logs/.gitignore"
else
  grep -qE '^\*$' "$BUILD/logs/.gitignore" || warn layout "docs/build/logs/.gitignore should contain a bare '*'" "docs/build/logs/.gitignore"
  grep -qE '^!\.gitignore$' "$BUILD/logs/.gitignore" || warn layout "docs/build/logs/.gitignore should contain '!.gitignore'" "docs/build/logs/.gitignore"
fi

# ── Parse the manifest chain table + companions ──────────────────────────────
CHAIN_FILES="$(newtmp)"     # one filename per chain-table row
CHAIN_ROWS="$(newtmp)"      # <lineno>\t<banner-or-empty>\t<filename>\t<row text>, in table order
COMPANIONS="$(newtmp)"
REQ_PATTERN=""
if [ -f "$MANIFEST" ]; then
  # companions: line (comma-separated filenames).
  grep -m1 -iE '^[[:space:]]*companions:' "$MANIFEST" 2>/dev/null \
    | sed -E 's/^[^:]*:[[:space:]]*//' | tr ',' '\n' \
    | sed -E 's/[`[:space:]]//g' | grep -E '\.md$' >> "$COMPANIONS" || true
  # req_id_pattern: line.
  REQ_PATTERN="$(grep -m1 -iE '^[[:space:]]*req_id_pattern:' "$MANIFEST" 2>/dev/null | sed -E 's/^[^:]*:[[:space:]]*//; s/[`[:space:]]*$//; s/^`//')"
  # Chain rows: table lines inside the "## The chain" section that name a *.md file; the nearest
  # preceding `###` heading is the row's banner (V13).
  LC_ALL=C awk '
    /^##[[:space:]]+The chain/ {inchain=1; banner=""; next}
    inchain && /^##[[:space:]]/ {inchain=0}
    inchain && /^###[[:space:]]/ {banner=$0; next}
    inchain && /^\|/ {
      if (match($0, /[0-9A-Za-z_.-]+\.md/)) print NR "\t" (banner == "" ? "-" : banner) "\t" substr($0, RSTART, RLENGTH) "\t" $0
    }' "$MANIFEST" > "$CHAIN_ROWS"
  cut -f3 "$CHAIN_ROWS" | sort -u >> "$CHAIN_FILES"
fi
# _TEMPLATE.md and DEFERRALS.md are always companions.
printf '%s\n' "_TEMPLATE.md" "DEFERRALS.md" >> "$COMPANIONS"
COMPANIONS_SORTED="$(sort -u "$COMPANIONS")"

is_companion() { printf '%s\n' "$COMPANIONS_SORTED" | grep -qxF "$1"; }
in_chain() { grep -qxF "$1" "$CHAIN_FILES"; }

# ── 2. Ticket files: grammar, unique sequence, marker+chain membership ───────
SEQ_KEYS="$(newtmp)"; ID_SEQ="$(newtmp)"
if [ -d "$TICKETS" ]; then
  for f in "$TICKETS"/*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    [ "$b" = "00_MANIFEST.md" ] && continue
    is_companion "$b" && continue
    if printf '%s' "$b" | grep -qE "$FNAME_RE"; then
      key="$(printf '%s' "$b" | sed -E 's/^([0-9]{2,3}[a-z]?)_.*$/\1/')"
      id="$(printf '%s' "$b" | sed -E "s/^[0-9]{2,3}[a-z]?_(${ID_RE})__.*$/\1/")"
      num="$(printf '%s' "$key" | sed -E 's/[a-z]$//')"
      # Dedup on the ticket ID, not the numeric prefix: a project may legitimately land several
      # inserted sub-tickets under one prefix distinguished by an ID suffix (e.g. 16_P0.15,
      # 16_P0.15b, 16_P0.15c). The real invariant is a unique ID, not a unique NN prefix.
      printf '%s\t%s\n' "$id" "$b" >> "$SEQ_KEYS"
      printf '%s\t%s\t%s\n' "$id" "$num" "$b" >> "$ID_SEQ"
      in_chain "$b" || viol manifest "ticket file $b has no row in the manifest chain table" "docs/tickets/$b" "$id"
    else
      # Legacy filename allowed only if the chain table lists it.
      if in_chain "$b"; then
        id="$(printf '%s' "$b" | sed -E 's/__.*$//; s/^[0-9]*[a-z]?_?//; s/\.md$//')"
        num="$(printf '%s' "$b" | sed -E 's/^([0-9]+).*$/\1/')"
        case "$num" in ''|*[!0-9]*) num=0 ;; esac
        printf '%s\t%s\t%s\n' "$id" "$num" "$b" >> "$ID_SEQ"
      else
        viol filename "ticket file $b does not match the filename grammar and is not a listed chain row" "docs/tickets/$b"
      fi
    fi
  done
  # duplicate ticket ids (the sequence invariant: no two ticket files declare the same id)
  if [ -s "$SEQ_KEYS" ]; then
    cut -f1 "$SEQ_KEYS" | sort | uniq -d | while IFS= read -r dup; do
      [ -n "$dup" ] && viol sequence "duplicate ticket id '$dup' (two ticket files declare the same id)" "docs/tickets" "$dup"
    done
  fi
fi

# every chain-table filename must exist on disk
if [ -s "$CHAIN_FILES" ]; then
  while IFS= read -r cf; do
    [ -n "$cf" ] || continue
    [ "$cf" = "00_MANIFEST.md" ] && continue
    if [ ! -f "$TICKETS/$cf" ]; then
      # could be a docs/build companion (rare); only flag if truly absent
      [ -f "$REPO/$cf" ] || viol manifest "manifest chain row names $cf but no such file exists in docs/tickets/" "$MANIFEST_REL" "" "$cf"
    fi
  done < "$CHAIN_FILES"
fi

# V13: every chain row sits under a numbered `### Round <n>` banner. Tree mode only warns (legacy rows
# cannot be re-bannered under append-only); history mode fails rows a change adds (BM-MANIFEST-01).
if [ -s "$CHAIN_ROWS" ]; then
  nb="$(awk -F'\t' '$2 !~ /^###[[:space:]]+Round[[:space:]]+[0-9]+/ {n++; if (!f) f = $3} END {if (n) print n "\t" f}' "$CHAIN_ROWS")"
  nrows="$(wc -l < "$CHAIN_ROWS" | tr -d ' ')"
  count round-banner "$nrows" "$nrows"
  [ -n "$nb" ] && warn manifest "$(printf '%s' "$nb" | cut -f1) chain row(s) are not under a numbered '### Round <n>' banner (first: $(printf '%s' "$nb" | cut -f2)); new rows go under the current round's banner (BM-MANIFEST-01, V13)" "$MANIFEST_REL"
fi

# ── 3. Depends on (backward only) + 4. skeleton has no run line ──────────────
seq_of_id() { grep -E "^$1	" "$ID_SEQ" 2>/dev/null | head -1 | cut -f2; }   # tab-separated
if [ -d "$TICKETS" ]; then
  for f in "$TICKETS"/*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    [ "$b" = "00_MANIFEST.md" ] && continue
    is_companion "$b" && continue
    my_num="$(grep -E "	$b$" "$ID_SEQ" 2>/dev/null | head -1 | cut -f2)"
    # skeleton check (robust to markdown bold/table cells around Kind: and Run:)
    if grep -qiE 'Kind:[^|]*skeleton' "$f"; then
      if grep -E 'Run:' "$f" | grep -q 'implement-spec'; then
        viol skeleton "skeleton ticket $b carries a Run: line (a skeleton must have no run line)" "docs/tickets/$b"
      fi
    fi
    # depends-on backward check
    dep_line="$(grep -m1 -iE '(^|[|*[:space:]])Depends on:' "$f" | sed -E 's/.*Depends on:[[:space:]]*//; s/`//g')"
    case "$dep_line" in ''|*[Nn]othing*|*[Nn]one*|'—'*|-*) : ;; *)
      # extract candidate ids from the dependency line
      printf '%s' "$dep_line" | grep -oE "$ID_RE" | sort -u | while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        dep_num="$(seq_of_id "$dep")"
        [ -n "$dep_num" ] || continue
        [ -n "$my_num" ] || continue
        if [ "$dep_num" -gt "$my_num" ] 2>/dev/null; then
          viol depends "ticket $b depends on $dep which lands later (forward dependency)" "docs/tickets/$b" "" "$dep"
        fi
      done
    ;; esac
  done
fi

# ── 5. DEFERRALS.md ids unique + valid statuses ──────────────────────────────
DEF="$TICKETS/DEFERRALS.md"
if [ -f "$DEF" ]; then
  DEF_IDS="$(newtmp)"
  # table rows whose first cell is an id like D-<TICKET>-<n>
  grep -E '^\|[[:space:]]*D-' "$DEF" | while IFS= read -r row; do
    id="$(printf '%s' "$row" | sed -E 's/^\|[[:space:]]*//; s/[[:space:]]*\|.*$//')"
    # The status is the first canonical token appearing (as a whole word) in the last cell,
    # tolerating markdown emphasis and status prose (e.g. "**PARTIAL (date):** …" or a migrated
    # cell like "…DONE…; OPEN for a live fixture"). Hyphens are kept so compound words like
    # ROOT-CAUSED don't spuriously match a canonical token.
    lastcell="$(printf '%s' "$row" | sed -E 's/[[:space:]]*\|[[:space:]]*$//' | awk -F'|' '{print $NF}' | tr 'a-z' 'A-Z')"
    toks=" $(printf '%s' "$lastcell" | sed -E 's/[^A-Z-]+/ /g') "
    status=""
    for cand in OPEN PARTIAL DONE WONTFIX ACCEPTED-SKELETON; do
      case "$toks" in *" $cand "*) status="$cand"; break ;; esac
    done
    printf '%s\n' "$id" >> "$DEF_IDS"
    if [ -z "$status" ]; then
      shown="$(printf '%s' "$lastcell" | sed -E 's/^[^A-Za-z]*//; s/[^A-Za-z-].*$//')"
      viol deferrals "DEFERRALS row $id has an invalid (orphan) status '$shown'" "docs/tickets/DEFERRALS.md" "$id"
    fi
  done
  if [ -s "$DEF_IDS" ]; then
    sort "$DEF_IDS" | uniq -d | while IFS= read -r dup; do
      [ -n "$dup" ] && viol deferrals "duplicate DEFERRALS id '$dup'" "docs/tickets/DEFERRALS.md" "$dup"
    done
  fi
  # P (human-prerequisite) rows still owed must be scheduled: owner: + trigger: in
  # `unblocked by` (DEFERRALS rule 5). Warning in tree mode; history mode (check-history.sh) fails
  # such rows ADDED under the guards marker. Header-aware: each table's own `kind` /
  # `unblocked by` columns are located from its `| id | … |` header row.
  LC_ALL=C awk -F'|' '
    function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
    /^\|[[:space:]]*id[[:space:]]*\|/ {
      kc = 0; uc = 0
      for (i = 1; i <= NF; i++) { c = tolower(trim($i)); if (c == "kind") kc = i; if (c == "unblocked by") uc = i }
      next
    }
    /^\|[[:space:]]*D-/ && kc {
      k = $kc; gsub(/[[:space:]*`_]/, "", k); if (k != "P") next
      last = ""; for (i = NF; i >= 1; i--) if (trim($i) != "") { last = $i; break }
      s = toupper(last); gsub(/[^A-Z-]+/, " ", s); s = " " s " "
      if (!index(s, " OPEN ") && !index(s, " PARTIAL ")) next
      cell = uc ? $uc : $0
      if (cell !~ /owner:/ || cell !~ /trigger:/) print trim($2)
    }' "$DEF" 2>/dev/null | while IFS= read -r pid; do
    [ -n "$pid" ] && warn deferrals "DEFERRALS row $pid (kind P, still owed) has no owner:/trigger: in 'unblocked by' (rule 5: human work is scheduled)" "docs/tickets/DEFERRALS.md" "$pid"
  done
  # no OPEN row scoped to a gate whose readout says PASSED. A readout with a `Status:` line
  # (templates/READOUT.md) is judged by that line alone, comments stripped; older readouts
  # by the legacy whole-file match.
  if [ -d "$BUILD/readouts" ]; then
    for ro in "$BUILD"/readouts/GATE-*.md; do
      [ -f "$ro" ] || continue
      ro_passed=0
      ro_status="$(grep -m1 -E '^Status:' "$ro" 2>/dev/null | sed -E 's/<!--.*-->//g')"
      if [ -n "$ro_status" ]; then
        printf '%s' "$ro_status" | grep -qwE 'PASSED' && ro_passed=1
      elif grep -qiE 'verdict:?[[:space:]]*PASSED|^PASSED|\bPASSED\b' "$ro"; then
        ro_passed=1
      fi
      if [ "$ro_passed" -eq 1 ]; then
        g="$(basename "$ro" .md)"   # e.g. GATE-G1
        if grep -E '^\|[[:space:]]*D-' "$DEF" | grep -iE '\bOPEN\b' | grep -qF "$g"; then
          viol deferrals "an OPEN DEFERRALS row references $g whose readout says PASSED" "docs/tickets/DEFERRALS.md" "" "$g"
        fi
      fi
    done
  fi
fi

# ── 6. ADRs: index match + revisit trigger + spec appendix + parseable cells ──
if [ -d "$ADR" ]; then
  for a in "$ADR"/ADR-*.md; do
    [ -f "$a" ] || continue
    grep -qE '^##[[:space:]]+Revisit trigger' "$a" || viol adr "$(basename "$a") has no '## Revisit trigger' section" "docs/adr/$(basename "$a")"
  done
  if [ -f "$ADR/README.md" ] && [ -f "$SELF_DIR/adr-index.sh" ]; then
    gen="$(newtmp)"
    bash "$SELF_DIR/adr-index.sh" --check "$ADR" > "$gen" 2>/dev/null
    if ! diff -q "$gen" "$ADR/README.md" >/dev/null 2>&1; then
      leg="$(newtmp)"
      bash "$SELF_DIR/adr-index.sh" --check --legacy "$ADR" > "$leg" 2>/dev/null
      if diff -q "$leg" "$ADR/README.md" >/dev/null 2>&1; then
        warn adr "docs/adr/README.md was generated by the pre-0.5.0 parser (titles '# ADR-NNN —', Phase/plain fields read '—'); regenerate it with adr-index.sh (BM-ADR-02)" "docs/adr/README.md"
      else
        viol adr "docs/adr/README.md does not match a fresh adr-index regeneration (hand-edited or stale)" "docs/adr/README.md"
      fi
    fi
    # Every cell the generator could not parse reads `—` (SK-21): warn; fail for an ADR added after
    # the guards marker.
    dash="$(LC_ALL=C awk -F'|' '/^\| \[ADR-/ { for (i = 3; i <= 5; i++) { c = $i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", c); if (c == "—") { f = $2; sub(/.*\(/, "", f); sub(/\).*/, "", f); print f; break } } }' "$gen")"
    nd=0; first=""
    if [ -n "$dash" ]; then
      while IFS= read -r af; do
        [ -n "$af" ] || continue
        if created_after_marker "docs/adr/$af"; then
          viol adr "$af: an ADR index cell reads '—' (title/ticket/status not parseable; BM-ADR-01 header form)" "docs/adr/$af"
        else nd=$((nd + 1)); [ -n "$first" ] || first="$af"; fi
      done <<EOF
$dash
EOF
      [ "$nd" -gt 0 ] && warn adr "$nd ADR index row(s) have a cell reading '—' (first: $first) — the header has no parseable title/Ticket/Phase/Status (BM-ADR-01)" "docs/adr/README.md"
    fi
  fi
fi
# spec ADR appendix == file set (BM-ADR-04, when resolvable)
SPEC_REL="$(lval canonicalSpec)"
if [ -n "$SPEC_REL" ]; then
  case "$SPEC_REL" in /*) SPEC="$SPEC_REL" ;; *) SPEC="$REPO/$SPEC_REL" ;; esac
  if [ -f "$SPEC" ] && grep -qiE 'ADR (appendix|index)|Appendix [A-Z][^\n]*ADR' "$SPEC"; then
    spec_adrs="$(grep -oE 'ADR-[0-9]{3}' "$SPEC" | sort -u)"
    file_adrs="$(ls "$ADR" 2>/dev/null | grep -oE '^ADR-[0-9]{3}' | sort -u)"
    if [ -n "$spec_adrs" ] && [ "$spec_adrs" != "$file_adrs" ]; then
      warn adr "spec ADR appendix and docs/adr/ file set differ (BM-ADR-04)" "$SPEC_REL"
    fi
  fi
fi

# ── BUILD_INDEX scan (used by 7 and 7c) ──────────────────────────────────────
# One record per finding: cols|seq|pr|vocab|landed|tk  <lineno>  <detail>. A table's header is the row
# just above a separator line; rows after a heading or blank line continue the last header
# (a long index split by round headings), until a new header appears.
BI="$BUILD/BUILD_INDEX.md"
BIX="$(newtmp)"
if [ -f "$BI" ]; then
  LC_ALL=C awk -v now="$NOW_DATE" '
    function t(x) { gsub(/[*`]/, "", x); gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
    function ncells(s,   u) { u = s; gsub(/\\\|/, "", u); sub(/^[[:space:]]*\|/, "", u); sub(/\|[[:space:]]*$/, "", u); return split(u, _x, "|") }
    function issep(x) { return x ~ /^\|[-|: ]+\|[[:space:]]*$/ }
    function sethdr(h,   u, m, i, c) {
      hn = ncells(h); sc = tc = pc = lc = dc = 0; u = h; gsub(/\\\|/, "", u); m = split(u, H, "|")
      for (i = 1; i <= m; i++) { c = tolower(t(H[i]))
        if (c == "seq" || c == "#") sc = i; if (c == "ticket") tc = i; if (c == "pr") pc = i
        if (c == "landed") dc = i; if (c ~ /^live verification/) lc = i }
      have = 1; delete seen
    }
    function data(r, nr,   u, s, v, d, k) {
      rows++
      if (ncells(r) != hn) print "cols\t" nr "\t" ncells(r) "/" hn
      u = r; gsub(/\\\|/, "", u); split(u, C, "|")
      if (tc) { k = t(C[tc]); sub(/[[:space:]].*$/, "", k); if (k != "") print "tk\t" nr "\t" k }
      if (sc) { s = t(C[sc]); if (s != "" && s != "—" && s != "-") { if (seen[s]++) print "seq\t" nr "\t" s } }
      if (pc && tc && t(C[pc]) ~ /[Pp]ending|TBD/) print "pr\t" nr "\t" k
      if (lc) { v = tolower(t(C[lc])); sub(/[[:space:](;,].*$/, "", v)
        if (v !~ /^(live-executed|staging|fixture-only|engineered|n-a|n\/a|gate-pending|run)$/) print "vocab\t" nr "\t" v }
      if (dc && match(C[dc], /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) { d = substr(C[dc], RSTART, RLENGTH); if (d > now && r !~ /future-ok/) print "landed\t" nr "\t" d }
    }
    {
      if (pend != "") { if (issep($0)) { sethdr(pend); pend = ""; next } if (have) data(pend, pnr); pend = "" }
      if (issep($0)) next
      if ($0 ~ /^\|/) { pend = $0; pnr = NR }
    }
    END { if (pend != "" && have) data(pend, pnr); print "rows\t0\t" rows + 0 }' "$BI" > "$BIX"
fi

# ── 7. LEDGER key order + values + nextTicket + PHASE LOG done coverage ──────
EXPECTED_KEYS="projectStatus nextTicket lastCompleted blockedOn pauseRequested returnPass manifest canonicalSpec memoryRoot dispatchTarget buildWorktree buildBranchBase pinnedBaseSha chainTip benchmarkSet autonomy mergePolicy round updatedAt"
# The optional `harness` key (BM-LEDGER-02) is accepted only in its slot, between round and updatedAt.
EXPECTED_KEYS_H="$(printf '%s' "$EXPECTED_KEYS" | sed -E 's/ round updatedAt$/ round harness updatedAt/')"
in_index() {   # <id> → 0 when a BUILD_INDEX row's ticket cell starts with the id, or a cell is exactly it
  local re; re="$(printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g')"
  [ -f "$BI" ] || return 1
  awk -F'\t' '$1 == "tk" {print $3}' "$BIX" | grep -qxF "$1" && return 0
  grep -qE "\|[[:space:]]*[*\`]*${re}[*\`]*[[:space:]]*\|" "$BI"
}
if [ -f "$LEDGER" ]; then
  # keys inside the CURRENT STATE fenced block, in file order
  got="$(awk '
    /^##[[:space:]]+CURRENT STATE/ {inblk=1; next}
    inblk && /^##[[:space:]]/ {inblk=0}
    inblk && /^[[:space:]]*[A-Za-z][A-Za-z0-9]*:([[:space:]]|$)/ {
      line=$0; sub(/^[[:space:]]*/,"",line); sub(/:.*/,"",line); print line
    }
  ' "$LEDGER" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  exp="$(printf '%s' "$EXPECTED_KEYS" | sed -E 's/[[:space:]]+/ /g')"
  if [ "$got" != "$exp" ] && [ "$got" != "$EXPECTED_KEYS_H" ]; then
    viol ledger "LEDGER.md CURRENT STATE keys are missing or out of order (expected: $exp; optional 'harness' only between round and updatedAt)" "docs/build/LEDGER.md"
  fi
  # CURRENT STATE values (BM-LEDGER-02 vocabularies; guarded). The first token is judged, so a
  # trailing comment still works; an uninstantiated seed placeholder (`<…>` / `(…)`) is skipped.
  vcheck() {   # vcheck <key> <ERE for the first token> <expected text>
    local v t; v="$(lval "$1")"; t="$(printf '%s' "$v" | awk '{print $1}')"
    case "$t" in ''|'<'*|'('*) return 0 ;; esac
    printf '%s' "$t" | grep -qE "^($2)\$" || guarded ledger-value "LEDGER.md CURRENT STATE $1 '$t' is not $3 (BM-LEDGER-02)" "docs/build/LEDGER.md" "$1"
  }
  vcheck projectStatus 'NOT_STARTED|IN_PROGRESS|BLOCKED|PAUSED|DONE' 'one of NOT_STARTED | IN_PROGRESS | BLOCKED | PAUSED | DONE'
  vcheck pauseRequested 'true|false' 'true | false'
  vcheck mergePolicy 'NONE|OPERATOR|AUTO-BOTTOM-UP' 'one of NONE | OPERATOR | AUTO-BOTTOM-UP'
  vcheck autonomy 'auto|checkpoint|manual' 'one of auto | checkpoint | manual'
  vcheck round '[0-9]+' 'an integer'
  vcheck updatedAt '[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?(Z|[+-][0-9]{2}(:?[0-9]{2})?)?)?' 'an ISO-8601 date or time from `date -u`'

  nt="$(lval nextTicket)"
  if [ -n "$nt" ] && [ "$nt" != "DONE" ] && [ "$nt" != "SETUP" ]; then
    # must name a chain row — by exact id (ID_SEQ) or as the _<ID>__ segment of a chain filename.
    nt_re="$(printf '%s' "$nt" | sed 's/[.[\*^$]/\\&/g')"
    if [ -s "$ID_SEQ" ] && ! grep -qE "^${nt_re}$(printf '\t')" "$ID_SEQ" && ! grep -qE "_${nt_re}__" "$CHAIN_FILES"; then
      warn ledger "LEDGER nextTicket '$nt' does not name a known chain row or DONE" "docs/build/LEDGER.md" "nextTicket" "$nt"
    fi
  fi

  # PHASE LOG entries (multi-line aware), one record per bullet:
  #   <lineno>\t<region#>\t<is-last-region>\t<markup 0|1>\t<id or "">\t<head is done 0|1>\t<lead date>\t<head text>
  # The id is the first token after the first "—"; markup (`*`, `_`, backticks) is stripped before
  # parsing and flagged. Without any PHASE LOG heading the whole file is read (legacy ledgers).
  PL="$(newtmp)"
  has_pl=0; grep -qE '^##[[:space:]]+PHASE LOG' "$LEDGER" && has_pl=1
  IDRE="^${ID_RE}" LC_ALL=C awk -v haspl="$has_pl" '
    /^##[[:space:]]/ { inlog = (!haspl) || ($0 ~ /^##[[:space:]]+PHASE LOG/ && $0 !~ /^##[[:space:]]+PHASE LOG[[:space:]]+INDEX/); if (inlog) region++; next }
    (inlog || !haspl) && /^-[[:space:]]/ {
      raw = $0; s = raw; gsub(/[*_`]/, "", s); mk = (s != raw)
      lead = ""; if (match(s, /^-[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) { lead = substr(s, RSTART, RLENGTH); sub(/^-[[:space:]]*/, "", lead) }
      id = ""; head = ""; isdone = 0
      p = index(s, "—")
      if (lead != "" && p) {
        rest = substr(s, p + length("—")); sub(/^[[:space:]]+/, "", rest)
        q = index(rest, " — "); head = q ? substr(rest, 1, q - 1) : rest
        if (match(rest, ENVIRON["IDRE"])) { id = substr(rest, RSTART, RLENGTH); nx = substr(rest, RLENGTH + 1, 1); if (nx != "" && nx !~ /[[:space:]:,(]/) id = "" }
        isdone = (head ~ /(^|[^A-Za-z-])done([^A-Za-z-]|$)/)
      } else if (s ~ /(^|[^A-Za-z-])done([^A-Za-z-]|$)/) { head = s; isdone = 1 }
      print NR "\t" (region + 0) "\t" "R" "\t" mk "\t" id "\t" isdone "\t" lead "\t" head
    }' "$LEDGER" > "$PL.raw"
  lastreg="$(awk -F'\t' '{r = $2} END {print r + 0}' "$PL.raw")"
  awk -F'\t' -v OFS='\t' -v L="$lastreg" '{ $3 = ($2 == L) ? 1 : 0; print }' "$PL.raw" > "$PL"; rm -f "$PL.raw"
  # PHASE LOG "done" entries -> a BUILD_INDEX row + an evidence file (runs/<ID>.md or pr/<ID>.md).
  # An entry that parses only after stripping markup is the legacy (pre-BM-LEDGER-06) shape: judged
  # guarded in the current region and as a warning in older regions; a canonical entry fails as before.
  cand="$(awk -F'\t' '$6 == 1' "$PL" | wc -l | tr -d ' ')"
  eval_n="$(awk -F'\t' '$6 == 1 && $5 != ""' "$PL" | wc -l | tr -d ' ')"
  count phase-log-done "$cand" "$eval_n"
  if [ "$cand" -gt 0 ] && { [ "$eval_n" -eq 0 ] || [ $((eval_n * 2)) -lt "$cand" ]; }; then
    VACUOUS=1
    viol vacuous "LEDGER.md: $cand PHASE LOG 'done' entr(y/ies) but only $eval_n parse to a ticket id — the done ↔ BUILD_INDEX check would pass vacuously; write entries as '- <date -u +%F> — <ID> done — …' (BM-LEDGER-06)" "docs/build/LEDGER.md"
  fi
  awk -F'\t' '$6 == 1 && $5 != "" {print $1 "\t" $3 "\t" $4 "\t" $5}' "$PL" | while IFS="$(printf '\t')" read -r ln islast mk tid; do
    case "$tid" in SETUP|CAPSTONE|DONE|ROUND|ROUND[0-9]*) continue ;; esac
    report=viol
    if [ "$mk" = "1" ]; then if [ "$islast" = "1" ]; then report=guarded; else report=warn; fi; fi
    if [ -f "$BI" ] && ! in_index "$tid"; then
      $report index "PHASE LOG marks $tid done (line $ln) but BUILD_INDEX.md has no row for it" "docs/build/BUILD_INDEX.md" "$tid"
    fi
    if [ ! -f "$BUILD/runs/$tid.md" ] && [ ! -f "$BUILD/pr/$tid.md" ]; then
      $report index "PHASE LOG marks $tid done (line $ln) but neither docs/build/runs/$tid.md nor pr/$tid.md exists (no evidence file)" "docs/build/LEDGER.md" "$tid"
    fi
  done

  # nextTicket is the lowest chain row not landed (V2; warn). A row leaves the order only by an explicit
  # token in its gate cell (the row's last cell — the manifest's `gate` column): `superseded-by(<ids>)`,
  # `superseded-by-split`, `deferred(<D-id>)` or the word `unused`; HUMAN rows never block code tickets
  # (BM-TICKET-05). Skip words in the title, slug or scope ("the deferred parser layers", `drop-unused-…`)
  # never take a row out of the order. Legacy: a bare word in the gate cell (superseded, deferred, skipped,
  # withdrawn, dropped) still skips, with a warning naming the token to write instead.
  if [ -n "$nt" ] && [ "$nt" != "SETUP" ] && [ -s "$CHAIN_ROWS" ]; then
    LANDED="$(newtmp)"
    awk -F'\t' '$5 != "" && ($6 == 1 || $8 ~ /(^|[^A-Za-z-])(gate|PASSED|SIGNED|SKIPPED|skipped|split|superseded)([^A-Za-z-]|$)/) {print $5}' "$PL" >> "$LANDED"
    awk -F'\t' '$1 == "tk" {print $3}' "$BIX" >> "$LANDED"
    printf '%s\n' "$(lval returnPass)" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' >> "$LANDED"
    # <file> \t <skip: token | legacy:<word> | prose:<word> | -> per chain row, in table order
    SKIPS="$(newtmp)"
    LC_ALL=C awk -F'\t' '
      function word(s,   w) { if (!match(s, /(^|[^a-z])(superseded|deferred|unused|skipped|withdrawn|dropped)([^a-z]|$)/)) return ""
        w = substr(s, RSTART, RLENGTH); gsub(/[^a-z]/, "", w); return w }
      { u = $4; gsub(/\\\|/, "", u); sub(/^[[:space:]]*\|/, "", u); sub(/\|[[:space:]]*$/, "", u); n = split(u, C, "|")
        g = tolower(n ? C[n] : ""); r = tolower(u); k = "-"
        if (g ~ /superseded-by\(|superseded-by-split|deferred\(/ || g ~ /(^|[^a-z])unused([^a-z]|$)/) k = "token"
        else if (word(g) != "") k = "legacy:" word(g)
        else if (word(r) != "") k = "prose:" word(r)
        print $3 "\t" k }' "$CHAIN_ROWS" > "$SKIPS"
    want="" ; want_k="" ; legacy=""
    while IFS="$(printf '\t')" read -r cf sk; do
      rid="$(printf '%s' "$cf" | sed -E "s/^[0-9]{2,3}[a-z]?_(${ID_RE})__.*$/\1/")"
      [ "$rid" = "$cf" ] && rid="$(printf '%s' "$cf" | sed -E 's/__.*$//; s/^[0-9]*[a-z]?_?//; s/\.md$//')"
      [ "$sk" = token ] && continue
      case "$rid" in HUMAN-H*) continue ;; esac
      grep -qxF "$rid" "$LANDED" && continue
      case "$sk" in legacy:*) legacy="$legacy${legacy:+, }$rid ('${sk#legacy:}')"; continue ;; esac
      want="$rid"; want_k="$sk"; break
    done < "$SKIPS"
    [ -n "$want" ] || want="DONE"
    if [ -n "$legacy" ]; then
      warn manifest "chain row(s) $legacy are out of the nextTicket order only by a bare word in the gate cell — write superseded-by(<ids>), superseded-by-split, deferred(<D-id>) or unused there (V2)" "$MANIFEST_REL"
    fi
    if [ "$nt" != "$want" ]; then
      hint=""
      case "$want_k" in prose:*) hint=" — row $want says '${want_k#prose:}' outside its gate cell; only a gate-cell token takes a row out of the order" ;; esac
      warn ledger "LEDGER nextTicket '$nt' is not the lowest chain row that has not landed ('$want'; superseded-by/deferred/unused gate-cell tokens and HUMAN rows skipped)$hint" "docs/build/LEDGER.md" "nextTicket" "$want"
    fi
  fi

  # Close discipline (SK-05): a second `repair — close:` entry in the current round must set
  # blockedOn (the worker close protocol is broken; fix the worker, not the symptom).
  nrep="$(awk -F'\t' '$3 == 1 && $8 ~ /^[^ ]+ repair$/' "$PL" | while IFS="$(printf '\t')" read -r ln _r _l _m _i _d _ld _h; do sed -n "${ln}p" "$LEDGER"; done | grep -cE '— *[^ ]+ repair — *close:' )"
  bo="$(lval blockedOn)"
  case "$bo" in ''|'(nothing)'|nothing|none|'(none)') bo_empty=1 ;; *) bo_empty=0 ;; esac
  if [ "${nrep:-0}" -ge 2 ] && [ "$bo_empty" -eq 1 ]; then
    warn ledger "LEDGER.md: $nrep 'repair — close:' entries in the current PHASE LOG region but blockedOn is empty — a second close repair in a round sets 'blockedOn: worker close protocol broken (<ids>)' (BM-LEDGER-06)" "docs/build/LEDGER.md"
  fi
fi

# ── 7b. LEDGER budget + shape (BM-LEDGER-06/08, guarded) + tail/seed warnings ──
if [ -f "$LEDGER" ]; then
  # Orient region: line 1 up to (not including) the first "## OPEN FINDINGS" heading.
  head_b="$(LC_ALL=C awk '/^##[[:space:]]+OPEN FINDINGS/ {exit} {print}' "$LEDGER" | wc -c | tr -d ' ')"
  case "$head_b" in ''|*[!0-9]*) head_b=0 ;; esac
  if [ "$head_b" -gt 12288 ]; then
    guarded ledger-budget "LEDGER.md orient region (line 1 → ## OPEN FINDINGS) is $head_b B, over the 12 KiB budget (BM-LEDGER-08)" "docs/build/LEDGER.md"
  elif [ "$head_b" -gt 8192 ]; then
    warn ledger-budget "LEDGER.md orient region is $head_b B, above the 8 KiB warning level (budget 12 KiB, BM-LEDGER-08)" "docs/build/LEDGER.md"
  fi
  cs_b="$(LC_ALL=C awk '/^##[[:space:]]+CURRENT STATE/ {f=1} f && /^##[[:space:]]/ && !/CURRENT STATE/ {exit} f' "$LEDGER" | wc -c | tr -d ' ')"
  [ "${cs_b:-0}" -gt 3072 ] 2>/dev/null && guarded ledger-budget "LEDGER.md CURRENT STATE section is $cs_b B, over the 3 KiB budget (values only, BM-LEDGER-08)" "docs/build/LEDGER.md"
  # CURRENT STATE: values only — each key line <= 256 B, no `| PRIOR` history.
  LC_ALL=C awk -v keys=" $EXPECTED_KEYS harness " '
    /^##[[:space:]]+CURRENT STATE/ {inblk=1; next}
    inblk && /^##[[:space:]]/ {inblk=0}
    inblk && /^[[:space:]]*[A-Za-z][A-Za-z0-9]*:([[:space:]]|$)/ {
      k=$0; sub(/^[[:space:]]*/,"",k); sub(/:.*/,"",k)
      if (index(keys, " " k " ")) print k "\t" length($0) "\t" ($0 ~ /\|[[:space:]]*\**PRIOR/ ? 1 : 0)
    }' "$LEDGER" | while IFS="$(printf '\t')" read -r k len prior; do
    [ -n "$k" ] || continue
    [ "$len" -gt 256 ] 2>/dev/null && guarded ledger-budget "LEDGER.md CURRENT STATE '$k' line is $len B (> 256 B; values only, BM-LEDGER-08)" "docs/build/LEDGER.md" "$k"
    [ "$prior" = "1" ] && guarded ledger-budget "LEDGER.md CURRENT STATE '$k' carries '| PRIOR' history (values only; git + PHASE LOG carry history, BM-LEDGER-08)" "docs/build/LEDGER.md" "$k"
  done
  # returnPass is a comma-separated id list (or "(none)").
  rp="$(lval returnPass)"
  case "$rp" in ''|'(none)'|none|'(nothing)') : ;; *)
    printf '%s' "$rp" | grep -qE "^${ID_RE}([[:space:]]*,[[:space:]]*${ID_RE})*$" \
      || guarded ledger-budget "LEDGER.md returnPass is not a comma-separated ticket-id list (BM-LEDGER-08)" "docs/build/LEDGER.md" "returnPass" ;;
  esac
  # No line outside CURRENT STATE begins with a CURRENT STATE key name (readers take the first match).
  dupk="$(LC_ALL=C awk -v keys=" $EXPECTED_KEYS harness " '
    /^##[[:space:]]+CURRENT STATE/ {inblk=1; next}
    inblk && /^##[[:space:]]/ {inblk=0}
    !inblk && /^[[:space:]]*[A-Za-z][A-Za-z0-9]*:/ {
      k=$0; sub(/^[[:space:]]*/,"",k); sub(/:.*/,"",k)
      if (index(keys, " " k " ")) { n++; if (n == 1) first = NR " (" k ")" }
    }
    END { if (n) print n "\t" first }' "$LEDGER")"
  if [ -n "$dupk" ]; then
    guarded ledger-budget "LEDGER.md: $(printf '%s' "$dupk" | cut -f1) line(s) outside CURRENT STATE begin with a CURRENT STATE key name (first: line $(printf '%s' "$dupk" | cut -f2)) (BM-LEDGER-08)" "docs/build/LEDGER.md"
  fi
  # Stale orient text (V3): every repo path named (in backticks) in the orient region, and the
  # manifest / canonicalSpec / memoryRoot values, exist; no stale token appears. Guarded.
  ORIENT="$(newtmp)"; LC_ALL=C awk '/^##[[:space:]]+OPEN FINDINGS/ {exit} {print}' "$LEDGER" > "$ORIENT"
  missing=""; nmiss=0
  { grep -oE '`[^`[:space:]]+`' "$ORIENT" | tr -d '`'; lval manifest; lval canonicalSpec; lval memoryRoot; } 2>/dev/null \
    | sed -E 's/[#:][^/]*$//; s/[.,;)]+$//' | sort -u | while IFS= read -r p; do
      case "$p" in ''|/*|~*|-*|*'://'*|*'<'*|*'>'*|*'{'*|*'}'*|*'*'*|*'$'*|*'='*|*'…'*) continue ;; esac
      case "$p" in */*) : ;; *) continue ;; esac
      printf '%s' "$p" | grep -qE '(\.[A-Za-z0-9]{1,5}|/)$' || continue
      [ -e "$REPO/$p" ] || [ -e "$BUILD/$p" ] || printf '%s\n' "$p"
    done > "$ORIENT.miss"
  nmiss="$(grep -c . "$ORIENT.miss" 2>/dev/null)"; nmiss="${nmiss:-0}"
  [ "$nmiss" -gt 0 ] && guarded ledger-stale "LEDGER.md orient region names $nmiss repo path(s) that do not exist ($(head -3 "$ORIENT.miss" | tr '\n' ' ' | sed 's/ $//; s/ /, /g')) — stale orient text (BM-ORIENT-01, V3)" "docs/build/LEDGER.md"
  rm -f "$ORIENT.miss"
  # Defaults + the repo's record_policy/stale_tokens.txt (one token per line; `!token` retires a default).
  STALE_TOK="$(newtmp)"; printf '%s\n' '.agents/scratch' 'gitignored' 'Do not resume until' > "$STALE_TOK"
  if [ -f "$BUILD/tools/record_policy/stale_tokens.txt" ]; then
    sed -E 's/[[:space:]]+#.*$//; /^[[:space:]]*(#|$)/d' "$BUILD/tools/record_policy/stale_tokens.txt" > "$STALE_TOK.repo"
    grep -v '^!' "$STALE_TOK.repo" >> "$STALE_TOK"
    sed -n 's/^!//p' "$STALE_TOK.repo" | while IFS= read -r off; do grep -vxF -- "$off" "$STALE_TOK" > "$STALE_TOK.t"; mv "$STALE_TOK.t" "$STALE_TOK"; done
    rm -f "$STALE_TOK.repo"
  fi
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    tl="$(grep -nF -- "$tok" "$ORIENT" | head -1 | cut -d: -f1)"
    [ -n "$tl" ] && guarded ledger-stale "LEDGER.md orient region (line $tl) carries the stale token '$tok' — supersede it in OPERATING MODE, archive the old text (BM-ORIENT-01, V3)" "docs/build/LEDGER.md" "" "$tok"
  done < "$STALE_TOK"

  # One append target: the last "## " heading is a PHASE LOG heading (BM-LEDGER-06).
  last_h="$(grep -E '^##[[:space:]]' "$LEDGER" | tail -1)"
  if grep -qE '^##[[:space:]]+PHASE LOG' "$LEDGER"; then
    if ! printf '%s' "$last_h" | grep -qE '^##[[:space:]]+PHASE LOG([[:space:]]|$)' \
       || printf '%s' "$last_h" | grep -qE '^##[[:space:]]+PHASE LOG[[:space:]]+INDEX'; then
      guarded ledger-budget "LEDGER.md: the last region is '$last_h', not a PHASE LOG heading — new entries go only at the end of the file (BM-LEDGER-06)" "docs/build/LEDGER.md"
    fi
  fi
  # PHASE LOG entries <= 2 KiB: guarded in the last (current) PHASE LOG region; a warning in older regions.
  # Also counts the entries (seed check) and measures the last three (the orient probe).
  plog="$(LC_ALL=C awk '
    function flush() { if (cur) { if (sz > 2048) { ov++; ovl[ov] = cur; ovr[ov] = region }; k++; last[k % 3] = sz } cur = 0; sz = 0 }
    /^##[[:space:]]/ { flush(); inlog = ($0 ~ /^##[[:space:]]+PHASE LOG/ && $0 !~ /^##[[:space:]]+PHASE LOG[[:space:]]+INDEX/); if (inlog) { region++; k = 0; delete last } ; next }
    inlog && /^- / { flush(); cur = NR; sz = length($0) + 1; entries++; next }
    inlog && cur && /^[[:space:]]*$/ { flush(); next }
    inlog && cur { sz += length($0) + 1; next }
    END {
      flush()
      for (i = 1; i <= ov; i++) {
        if (ovr[i] == region) { nl++; if (nl <= 5) ll = ll " " ovl[i] } else { no++; if (no <= 5) lo = lo " " ovl[i] }
      }
      print entries + 0 "\t" nl + 0 "\t" ll "\t" no + 0 "\t" lo "\t" (last[0] + last[1] + last[2])
    }' "$LEDGER")"
  pl_entries="$(printf '%s' "$plog" | cut -f1)"
  pl_nl="$(printf '%s' "$plog" | cut -f2)"; pl_no="$(printf '%s' "$plog" | cut -f4)"; last3_b="$(printf '%s' "$plog" | cut -f6)"
  [ "${pl_nl:-0}" -gt 0 ] && guarded ledger-budget "LEDGER.md: $pl_nl PHASE LOG entr(y/ies) in the current region exceed 2 KiB (BM-LEDGER-06; lines:$(printf '%s' "$plog" | cut -f3))" "docs/build/LEDGER.md"
  [ "${pl_no:-0}" -gt 0 ] && warn ledger-budget "LEDGER.md: $pl_no PHASE LOG entr(y/ies) in older regions exceed 2 KiB (legacy; lines:$(printf '%s' "$plog" | cut -f5))" "docs/build/LEDGER.md"
  # Orient probe (BM-ORIENT-01, V11): head + current RETURN PASS + last three PHASE LOG entries + the
  # next row's manifest line + its contract header ≤ 48 KiB (warn).
  if grep -qE '^###[[:space:]]+RETURN PASS[[:space:]]+—[[:space:]]+current' "$LEDGER"; then
    rp_b="$(LC_ALL=C awk '/^###[[:space:]]+RETURN PASS[[:space:]]+—[[:space:]]+current/ {f=1; print; next} f && /^##/ {exit} f' "$LEDGER" | wc -c | tr -d ' ')"
  else
    rp_b="$(LC_ALL=C awk '/^##[[:space:]]+RETURN PASS/ {f=1; print; next} f && /^##[[:space:]]/ {exit} f' "$LEDGER" | wc -c | tr -d ' ')"
  fi
  nt_b=0; nt="$(lval nextTicket)"
  if [ -n "$nt" ] && [ -s "$CHAIN_ROWS" ]; then
    ntf="$(grep -E "_$(printf '%s' "$nt" | sed 's/[.[\*^$]/\\&/g')__" "$CHAIN_FILES" | head -1)"
    if [ -n "$ntf" ]; then
      nt_b="$(grep -F "$ntf" "$MANIFEST" | wc -c | tr -d ' ')"
      [ -f "$TICKETS/$ntf" ] && nt_b=$((nt_b + $(LC_ALL=C awk '/^##[[:space:]]/ {exit} {print}' "$TICKETS/$ntf" | wc -c | tr -d ' ')))
    fi
  fi
  orient_b=$((head_b + ${rp_b:-0} + ${last3_b:-0} + nt_b))
  count orient-bytes "$orient_b" "$orient_b"
  [ "$orient_b" -gt 49152 ] && warn ledger-budget "orient recipe reads $orient_b B (> 48 KiB: head $head_b · RETURN PASS ${rp_b:-0} · last 3 entries ${last3_b:-0} · next row $nt_b) (BM-ORIENT-01, V11)" "docs/build/LEDGER.md"

  # GATE DECISIONS rows in the 7-column form (BM-GATE-05, -09; guarded). Header-aware: a table row
  # with a `consequence` cell is a header; the table is 7-column iff that header also has `kind`.
  LC_ALL=C awk -F'|' '
    function bare(x) { gsub(/[[:space:]`*]/, "", x); return x }
    /^##[[:space:]]/ { ingd = ($0 ~ /^##[[:space:]]+GATE DECISIONS/); kc = 0; next }
    ingd && /^\|/ {
      if ($0 ~ /^\|[-|: ]+\|[[:space:]]*$/) next
      hk = 0; hc = 0
      for (i = 1; i <= NF; i++) { c = tolower(bare($i)); if (c == "kind") hk = i; if (c == "consequence") hc = i }
      if (hc) { kc = hk; next }
      if (!kc) next
      k = bare($kc)
      if (k !~ /^(decision|pre-authorization|confirmation|waiver|correction)$/) { print NR "\tkind\t" k; next }
      if (k == "pre-authorization" && ($0 !~ /expires:/ || $0 !~ /voided-by:/)) print NR "\tpreauth\t"
    }' "$LEDGER" | while IFS="$(printf '\t')" read -r gln gwhat gval; do
    case "$gwhat" in
      kind)    guarded gate "LEDGER.md line $gln: GATE DECISIONS kind '${gval:-<empty>}' is not one of decision | pre-authorization | confirmation | waiver | correction (BM-GATE-05)" "docs/build/LEDGER.md" ;;
      preauth) guarded gate "LEDGER.md line $gln: a pre-authorization row lacks expires: and/or voided-by: (scoped pre-authorization, BM-GATE-09)" "docs/build/LEDGER.md" ;;
    esac
  done
  # Pre-answered gate? A seed ledger (only the seed PHASE LOG entry) has no GATE DECISIONS
  # rows except operator pre-authorizations (decompose-spec never answers a gate).
  if [ "${pl_entries:-0}" -le 1 ]; then
    gd_rows="$(LC_ALL=C awk -F'|' '
      /^##[[:space:]]/ { ingd = ($0 ~ /^##[[:space:]]+GATE DECISIONS/); hdr = 0; next }
      ingd && /^\|/ {
        if (!hdr) { hdr = 1; next }
        if ($0 ~ /^\|[-|: ]+\|[[:space:]]*$/) next
        if ($0 ~ /^\|[[:space:]]*date[[:space:]]*\|/) next
        last = ""; for (i = NF; i >= 1; i--) { c = $i; gsub(/[[:space:]`*]/, "", c); if (c != "") { last = c; break } }
        if (last != "pre-authorization") n++
      }
      END { print n + 0 }' "$LEDGER")"
    [ "${gd_rows:-0}" -gt 0 ] && warn gate "LEDGER.md is a seed (PHASE LOG holds only the seed entry) but GATE DECISIONS has $gd_rows non-pre-authorization row(s) — pre-answered gate?" "docs/build/LEDGER.md"
  fi
  # DONE requires a signed GATE-ACCEPT readout (BM-TAIL-03).
  ps="$(lval projectStatus | awk '{print $1}')"
  if [ "$ps" = "DONE" ]; then
    ga="$BUILD/readouts/GATE-ACCEPT.md"; ga_signed=0
    if [ -f "$ga" ]; then
      ga_status="$(grep -m1 -E '^Status:' "$ga" 2>/dev/null | sed -E 's/<!--.*-->//g')"
      if [ -n "$ga_status" ]; then
        printf '%s' "$ga_status" | grep -qwE 'SIGNED|PASSED' && ga_signed=1
      elif grep -qiE 'verdict:?[[:space:]]*\**PASSED|^PASSED' "$ga"; then
        ga_signed=1
      fi
    fi
    [ "$ga_signed" -eq 1 ] || warn tail "projectStatus is DONE but docs/build/readouts/GATE-ACCEPT.md is missing or not signed (BM-TAIL-03)" "docs/build/readouts/GATE-ACCEPT.md"
  fi
fi

# ── 7c. BUILD_INDEX rows (BM-INDEX-01; warn — history mode fails added rows) ──
#   column count = the header's; unique seq; no `PR pending`/`TBD` once the run ledger is Closed:;
#   the live-verification vocabulary (SK-11); `landed` dates not later than the clock.
if [ -f "$BI" ]; then
  bi_rows="$(awk -F'\t' '$1 == "rows" {print $3}' "$BIX")"; count build-index-rows "${bi_rows:-0}" "${bi_rows:-0}"
  agg() {   # agg <kind> <message prefix>
    local n f; n="$(awk -F'\t' -v k="$1" '$1 == k' "$BIX" | wc -l | tr -d ' ')"
    [ "$n" -gt 0 ] || return 0
    f="$(awk -F'\t' -v k="$1" '$1 == k {print "line " $2 " (" $3 ")"; exit}' "$BIX")"
    warn index "BUILD_INDEX.md: $n $2 (first: $f)" "docs/build/BUILD_INDEX.md"
  }
  agg cols "row(s) do not have the header's column count — an unescaped '|' in a cell? (BM-INDEX-01)"
  agg seq "duplicate seq value(s) (BM-INDEX-01)"
  agg vocab "live-verification value(s) outside live-executed | staging | fixture-only | engineered | n-a | gate-pending (legacy: run) (BM-INDEX-01, BM-STATUS-01)"
  agg landed "landed date(s) later than the clock $NOW_DATE (BM-CLOCK-01)"
  awk -F'\t' '$1 == "pr" {print $2 "\t" $3}' "$BIX" | while IFS="$(printf '\t')" read -r ln tid; do
    [ -f "$BUILD/runs/$tid.md" ] && run_closed < "$BUILD/runs/$tid.md" \
      && warn index "BUILD_INDEX.md line $ln: $tid still reads 'PR pending' but runs/$tid.md is Closed: — the PR cell is the real #<n> (BM-INDEX-01)" "docs/build/BUILD_INDEX.md" "$tid"
  done
fi

# ── 7d. The clock in tree mode (BM-CLOCK-01; warn — history mode fails added lines) ──
if [ -f "$LEDGER" ]; then
  fut_pl="$(awk -F'\t' -v now="$NOW_DATE" '$7 != "" && $7 > now {n++; if (!f) f = "line " $1 " " $7} END {if (n) print n "\t" f}' "$PL")"
  if [ -n "$fut_pl" ]; then
    # entries carrying future-ok are legitimate
    fut_pl="$(awk -F'\t' -v now="$NOW_DATE" '$7 != "" && $7 > now {print $1 " " $7}' "$PL" | while read -r ln d; do sed -n "${ln}p" "$LEDGER" | grep -q 'future-ok' || printf '%s %s\n' "$ln" "$d"; done | awk 'NR == 1 {f = "line " $1 " " $2} {n++} END {if (n) print n "\t" f}')"
    [ -n "$fut_pl" ] && warn clock "LEDGER.md: $(printf '%s' "$fut_pl" | cut -f1) PHASE LOG lead date(s) later than the clock $NOW_DATE (first: $(printf '%s' "$fut_pl" | cut -f2)) — record dates come from \`date -u\` (BM-CLOCK-01)" "docs/build/LEDGER.md"
  fi
  fut_g="$(LC_ALL=C awk -F'|' "$CLOCK_AWK"' /^##[[:space:]]/ {g = ($0 ~ /^##[[:space:]]+GATE DECISIONS/); next}
    g && /^\|/ && $0 !~ /future-ok/ && match($2, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]([T ][0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z?)?/) {
      d = substr($2, RSTART, RLENGTH); bad = has_time(d) ? (epoch(d) > '"$NOW_EPOCH"' + 300) : (d > "'"$NOW_DATE"'")
      if (bad) { n++; if (!f) f = "line " NR " " d } }
    END { if (n) print n "\t" f }' "$LEDGER")"
  [ -n "$fut_g" ] && warn clock "LEDGER.md: $(printf '%s' "$fut_g" | cut -f1) GATE DECISIONS date(s) later than the clock $NOW_ISO (first: $(printf '%s' "$fut_g" | cut -f2)) (BM-CLOCK-01)" "docs/build/LEDGER.md"
  upd="$(lval updatedAt | awk '{print $1}')"
  case "$upd" in [0-9][0-9][0-9][0-9]-*)
    if awk "$CLOCK_AWK"' BEGIN { d = ARGV[1]; ARGV[1] = ""; exit !(has_time(d) ? (epoch(d) > '"$NOW_EPOCH"' + 300) : (substr(d, 1, 10) > "'"$NOW_DATE"'")) }' "$upd"; then
      warn clock "LEDGER.md updatedAt $upd is later than the clock $NOW_ISO (BM-CLOCK-01)" "docs/build/LEDGER.md" "updatedAt"
    fi ;;
  esac
fi
if [ -f "$DEF" ]; then
  fut_d="$(LC_ALL=C awk -v now="$NOW_DATE" '/^\|[[:space:]]*D-/ && $0 !~ /future-ok/ {
      s = $0; while (match(s, /(OPEN|PARTIAL|DONE|WONTFIX|ACCEPTED-SKELETON|DEFERRED-AGAIN)[^0-9|]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) {
        d = substr(s, RSTART + RLENGTH - 10, 10); if (d > now) { n++; if (!f) f = "line " NR " " d }; s = substr(s, RSTART + RLENGTH) } }
    END { if (n) print n "\t" f }' "$DEF")"
  [ -n "$fut_d" ] && warn clock "DEFERRALS.md: $(printf '%s' "$fut_d" | cut -f1) status date(s) later than the clock $NOW_DATE (first: $(printf '%s' "$fut_d" | cut -f2)) (BM-CLOCK-01)" "docs/tickets/DEFERRALS.md"
fi
if [ -d "$BUILD/runs" ]; then
  fut_r="$(for r in "$BUILD"/runs/*.md; do [ -f "$r" ] || continue
      awk -v now="$NOW_DATE" -v fn="$(basename "$r")" 'NR > 40 {exit} /^[[:space:]]*(-[[:space:]]*)?(\*\*)?(Started|Closed|Date):/ && $0 !~ /future-ok/ && match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) {
        d = substr($0, RSTART, RLENGTH); if (d > now) { print fn ":" NR " " d; exit } }' "$r"; done | awk 'NR == 1 {f = $0} {n++} END {if (n) print n "\t" f}')"
  [ -n "$fut_r" ] && warn clock "runs/: $(printf '%s' "$fut_r" | cut -f1) run ledger(s) carry a Started/Closed/Date stamp later than the clock $NOW_DATE (first: $(printf '%s' "$fut_r" | cut -f2)) (BM-CLOCK-01)" "docs/build/runs"
fi

# ── 7e. Readouts carry the guard sentence (BM-INDEX-03); run ledgers carry Harness: (BM-HARNESS-01) ──
GUARD_SENT='an agent must not sign or assume silence is approval'
if [ -d "$BUILD/readouts" ]; then
  nro=0; nmiss=0; firstm=""
  for ro in "$BUILD"/readouts/*.md; do
    [ -f "$ro" ] || continue
    b="$(basename "$ro")"; [ "$b" = "_TEMPLATE.md" ] && continue
    nro=$((nro + 1))
    tr '\n' ' ' < "$ro" | sed -E 's/[[:space:]>]+/ /g' | grep -qiF "$GUARD_SENT" && continue
    if created_after_marker "docs/build/readouts/$b"; then
      viol readout "readouts/$b lacks the guard sentence (\"An operator or authorized human record supplies the decision; an agent must not sign or assume silence is approval.\") (BM-INDEX-03)" "docs/build/readouts/$b"
    else nmiss=$((nmiss + 1)); [ -n "$firstm" ] || firstm="$b"; fi
  done
  count readout-guard "$nro" "$nro"
  [ "$nmiss" -gt 0 ] && warn readout "$nmiss readout(s) predate the guard sentence (first: $firstm); readouts created after the guards marker must carry it (BM-INDEX-03)" "docs/build/readouts"
fi
if [ -d "$BUILD/runs" ]; then
  nrun=0; nmiss=0; firstm=""
  for r in "$BUILD"/runs/*.md; do
    [ -f "$r" ] || continue
    b="$(basename "$r")"; nrun=$((nrun + 1))
    grep -qE '^[[:space:]]*(-[[:space:]]*)?(\*\*)?Harness:' "$r" && continue
    if created_after_marker "docs/build/runs/$b"; then
      viol harness "runs/$b has no 'Harness: <harness>/<model-id>/<tier>' header line (BM-HARNESS-01)" "docs/build/runs/$b"
    else nmiss=$((nmiss + 1)); [ -n "$firstm" ] || firstm="$b"; fi
  done
  count run-harness "$nrun" "$nrun"
  [ "$nmiss" -gt 0 ] && warn harness "$nmiss run ledger(s) have no 'Harness:' header line (first: $firstm); new run ledgers must name harness/model/tier (BM-HARNESS-01)" "docs/build/runs"
fi

# ── 8. REQ coverage (only when spec + pattern resolve) ───────────────────────
if [ -n "$REQ_PATTERN" ] && [ -n "${SPEC:-}" ] && [ -f "${SPEC:-/nonexistent}" ]; then
  spec_ids="$(grep -oE "$REQ_PATTERN" "$SPEC" 2>/dev/null | sort -u)"
  if [ -d "$TICKETS" ] && [ -n "$spec_ids" ]; then
    for f in "$TICKETS"/*.md; do
      [ -f "$f" ] || continue
      b="$(basename "$f")"; [ "$b" = "00_MANIFEST.md" ] && continue; is_companion "$b" && continue
      grep -oE "$REQ_PATTERN" "$f" 2>/dev/null | sort -u | while IFS= read -r rid; do
        [ -n "$rid" ] || continue
        printf '%s\n' "$spec_ids" | grep -qxF "$rid" || warn reqcov "ticket $b cites $rid which is not in the spec" "docs/tickets/$b" "" "$rid"
      done
    done
  fi
fi

# ── 8b. Tests assert invariants, not living records (BM-TEST-01; heuristic warning) ──
# A tracked test file that names a living record file AND one of its living keys/counts.
if [ "$IN_GIT" -eq 1 ]; then
  LIVING_FILES='LEDGER\.md|BUILD_INDEX\.md|DEFERRALS\.md|COVERAGE_MATRIX\.csv'
  LIVING_KEYS='nextTicket|lastCompleted|projectStatus|chainTip|returnPass|EXPECTED_ROWS'
  git -C "$REPO" ls-files 2>/dev/null \
    | grep -E '(^|/)(tests?|__tests__|spec)/|(^|/)test_[^/]*\.[a-z]+$|_test\.[a-z]+$|\.(test|spec)\.[jt]sx?$' \
    | grep -vE '^docs/(build|tickets)/' | while IFS= read -r tf; do
      [ -f "$REPO/$tf" ] || continue
      grep -qE "$LIVING_FILES" "$REPO/$tf" 2>/dev/null || continue
      hit="$(grep -nE "$LIVING_KEYS" "$REPO/$tf" 2>/dev/null | head -1 | cut -d: -f1)"
      [ -n "$hit" ] && warn 'living-pin?' "$tf:$hit reads a living build record and names a living key — tests assert invariants, never the current value of a living record (BM-TEST-01)" "$tf"
    done
fi

# ── 9. size + secret checks ──────────────────────────────────────────────────
if [ -d "$BUILD" ]; then
  find "$BUILD" -type f ! -path '*/logs/*' -size +5120k 2>/dev/null | while IFS= read -r f; do
    rel="$(printf '%s' "$f" | sed "s#$REPO/##")"; warn size "$rel exceeds 5 MB" "$rel"
  done
  find "$BUILD" -type f -path '*/fixtures/*' -size +1024k 2>/dev/null | while IFS= read -r f; do
    rel="$(printf '%s' "$f" | sed "s#$REPO/##")"; warn size "fixture $rel exceeds 1 MB" "$rel"
  done
fi
SECRET_RE='AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{36}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-'
for scan in "$BUILD" "$TICKETS"; do
  [ -d "$scan" ] || continue
  hits="$(grep -rlE --exclude-dir=logs "$SECRET_RE" "$scan" 2>/dev/null | grep -v '/logs/' || true)"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | while IFS= read -r h; do
      [ -n "$h" ] && viol secret "$(printf '%s' "$h" | sed "s#$REPO/##") contains a secret-shaped token" "$(printf '%s' "$h" | sed "s#$REPO/##")"
    done
  fi
done

# ── Report + JSON ────────────────────────────────────────────────────────────
NV="$(wc -l < "$VIOL" | tr -d ' ')"
EXIT_CODE=0; [ "$NV" -eq 0 ] || EXIT_CODE=1; [ "$VACUOUS" -eq 1 ] && EXIT_CODE=3
write_report "$EXIT_CODE" true "$([ "$GUARDS" -eq 1 ] && echo true || echo false)"
echo "check-build-memory: $REPO$([ "$GUARDS" -eq 1 ] && echo ' (guards marker: on)')"
[ "$VACUOUS" -eq 1 ] && echo "  ! vacuous: a check found candidates it could not evaluate (exit 3)"
human "$EXIT_CODE"
