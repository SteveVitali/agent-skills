#!/usr/bin/env bash
# ci-boundary.sh — read the CI truth at a ticket boundary (BM-CI-01). Read-only.
#
# Reads the checks of a PR at its current head (and, with --stack, of every still-open ancestor PR
# in the stack) and reports pass / fail / pending / unknown. orchestrate-build runs it at every
# ticket boundary (§2.1, §2.3 step 4), implement-spec after its push (§6.5 step 0), and
# drive-build.sh before every dispatch. A red, pending or unreadable result is never green.
#
# Usage:
#   ci-boundary.sh --pr <n> [--stack] [--json PATH] [--worktree DIR] [--ledger PATH]
#                  [--interval S] [--max-wait S | --no-wait]
#   ci-boundary.sh --ledger PATH [--ticket ID] [--stack] [--json PATH] [...]
#
#   --pr        The PR to read (`123` or `#123`).
#   --ledger    The build ledger. Without --pr the PR is resolved from it: the --ticket's
#               BUILD_INDEX.md row (its PR cell), else that ticket's PHASE LOG "done" entry
#               (`PR #n`), else — when the ticket is lastCompleted — the open PR whose head is the
#               ledger's chainTip. Its GATE DECISIONS
#               `waiver` rows are honoured (below); its buildWorktree is the default --worktree.
#   --ticket    The ticket whose PR to read (with --ledger). SETUP or a marker id (HUMAN-H<k>,
#               GATE-G<k>, GATE-ACCEPT) reads the chainTip PR; none open → not applicable (exit 0).
#   --stack     Also read every still-open ancestor PR: the open PR whose head is this PR's base,
#               repeated until the base is not the head of an open PR.
#   --json      Write the ci-boundary/1 record here (default: a unique mktemp file; path printed).
#   --worktree  Where git/gh run and where CI files and the repo hook are looked up (default: the
#               ledger's buildWorktree when it is an existing directory, else the ledger's repo,
#               else the current git toplevel).
#   --interval  Poll interval in seconds while checks are pending (default 60).
#   --max-wait  Bounded wait for pending checks, in seconds (default 2700). --no-wait = one read.
#
# Required set: <worktree>/docs/build/tools/record_policy/ci_required.txt (one check name per line,
#   `#` comments) when present — each listed check must be reported and pass (missing or skipped
#   is a failure once the wait ends; other checks are informational); otherwise every check
#   reported on the head must pass (a skipped check is neutral; zero reported checks is pending).
# Waiver: a 7-column GATE DECISIONS row in --ledger whose kind is `waiver` and which names `#<n>`
#   and the check waives that failing check on PR <n> only (the operator's words, verbatim —
#   BM-GATE-05). An inherited red that reappears on a descendant PR needs that PR named too.
# Repo hook: if <worktree>/docs/build/tools/ci_boundary.py, ci_boundary.sh or an executable
#   ci_boundary exists, it runs instead with `--pr <n> --json <path>` and its exit code is passed
#   through (it owns the required set, the stack and the wait). The caller's `--ledger PATH`,
#   `--interval S`, and `--max-wait S` / `--no-wait` are forwarded when given AND the hook's file
#   names that flag (its usage text or argument parser) — a hook that names none gets exactly
#   `--pr <n> --json <path>`. `--no-wait` falls back to `--max-wait 0` (and `--max-wait 0` to
#   `--no-wait`) when the hook names only the other one.
# No CI declared (no .github/workflows/*.y*ml, .gitlab-ci.yml, .circleci/config.yml,
#   azure-pipelines.yml, bitbucket-pipelines.yml, .travis.yml, Jenkinsfile, .buildkite/, hook or
#   ci_required.txt): exit 0, state none-declared — record `ci: none-declared (locally-green)`.
#
# Output: the last stdout line is the one to record —
#   pass        → ci: pass #<n>@<sha7> (<check> <run-id>; …)[ · stack: #a #b pass]
#   not green   → blockedOn: CI <fail|pending|unknown> on #<n> (<check>): <first failing line>
#   and a ci-boundary/1 JSON record {schema, pr, head_sha, state, read_at, required, stack[],
#   checks[], line, exit} at --json.
#
# Exit codes (the shared build-script contract): 0 pass, none-declared or not applicable ·
#   1 usage · 3 fail, cancelled, or a required check missing or skipped · 4 still pending after the
#   bounded wait · 5 unknown (gh absent or unauthenticated, PR unresolvable, checks unreadable —
#   never treated as green).
#
# Needs bash 3.2+, git, and gh (JSON is shaped with gh's built-in --jq; no jq binary). Writes only
# the JSON record. No associative arrays, no mapfile.

set -uo pipefail

PR="" ; LEDGER="" ; TICKET="" ; STACK=0 ; JSON="" ; WT="" ; INTERVAL=60 ; MAX_WAIT=2700
INTERVAL_GIVEN=0 ; WAIT_GIVEN=""   # what the caller set explicitly — only that is forwarded to a repo hook

usage() { awk 'NR > 1 && !/^#/ {exit} NR > 1 {sub(/^# ?/, ""); print}' "$0"; }   # the header only
die_usage() { echo "ci-boundary.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)       PR="${2:-}"; shift 2 ;;
    --ledger)   LEDGER="${2:-}"; shift 2 ;;
    --ticket)   TICKET="${2:-}"; shift 2 ;;
    --stack)    STACK=1; shift ;;
    --json)     JSON="${2:-}"; shift 2 ;;
    --worktree) WT="${2:-}"; shift 2 ;;
    --interval) INTERVAL="${2:-}"; INTERVAL_GIVEN=1; shift 2 ;;
    --max-wait) MAX_WAIT="${2:-}"; WAIT_GIVEN=max; shift 2 ;;
    --no-wait)  MAX_WAIT=0; WAIT_GIVEN=none; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) die_usage "unknown arg: $1 (try --help)" ;;
  esac
done

TAB="$(printf '\t')"
PR="${PR#\#}"
case "$PR" in ''|*[!0-9]*) [ -z "$PR" ] || die_usage "--pr must be a number" ;; esac
case "$INTERVAL" in ''|*[!0-9]*) die_usage "--interval must be a whole number of seconds" ;; esac
case "$MAX_WAIT" in ''|*[!0-9]*) die_usage "--max-wait must be a whole number of seconds" ;; esac
[ -n "$PR" ] || [ -n "$LEDGER" ] || die_usage "--pr <n> or --ledger <path> required"
# A wait needs a non-zero interval (never a busy loop).
[ "$MAX_WAIT" -gt 0 ] && [ "$INTERVAL" -lt 1 ] && INTERVAL=1
if [ -n "$LEDGER" ]; then
  [ -f "$LEDGER" ] || die_usage "--ledger $LEDGER does not exist"
  LEDGER="$(cd "$(dirname "$LEDGER")" && pwd)/$(basename "$LEDGER")"
fi
if [ -z "$JSON" ]; then
  JSON="$(mktemp "${TMPDIR:-/tmp}/ci-boundary.XXXXXX")" || die_usage "cannot create a temp file"
else
  case "$JSON" in /*) : ;; *) JSON="$(pwd)/$JSON" ;; esac
fi

# Never-fail ledger reader (first token of the value; inline comments stripped).
lval() {
  [ -n "$LEDGER" ] || return 0
  grep -m1 -E "^[[:space:]]*${1}:" "$LEDGER" 2>/dev/null \
    | sed -E "s/^[[:space:]]*${1}:[[:space:]]*//; s/[[:space:]]*#.*$//" | awk '{print $1}'
}

# ── Worktree ──────────────────────────────────────────────────────────────────
if [ -z "$WT" ] && [ -n "$LEDGER" ]; then
  bw="$(lval buildWorktree)"
  case "$bw" in /*) [ -d "$bw" ] && WT="$bw" ;; esac
  [ -n "$WT" ] || WT="$(git -C "$(dirname "$LEDGER")" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$WT" ] || case "$LEDGER" in */docs/build/LEDGER.md) WT="${LEDGER%/docs/build/LEDGER.md}" ;; esac
fi
[ -n "$WT" ] || WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$WT" 2>/dev/null || die_usage "--worktree $WT is not a directory"

POLICY="docs/build/tools/record_policy/ci_required.txt"
HOOK=""
for h in docs/build/tools/ci_boundary.py docs/build/tools/ci_boundary.sh docs/build/tools/ci_boundary; do
  if [ -f "$h" ]; then HOOK="$h"; break; fi
done

# ── Helpers ───────────────────────────────────────────────────────────────────
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
jstr() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\t\r\n' '   ')"; }

# emit <state> <exit> <line> — write the JSON record, print the line, exit.
CHECKS="$(mktemp)" ; PRS="$(mktemp)" ; WAIVERS="$(mktemp)" ; REQUIRED="$(mktemp)"
trap 'rm -f "$CHECKS" "$PRS" "$WAIVERS" "$REQUIRED" "$CHECKS".* 2>/dev/null' EXIT
HEAD_SHA=""
emit() {
  local state="$1" code="$2" line="$3" first p sha prstate st n b l w req
  {
    printf '{"schema":"ci-boundary/1","pr":%s,"head_sha":%s,"state":%s,"read_at":%s,' \
      "${PR:-null}" "$(jstr "$HEAD_SHA")" "$(jstr "$state")" "$(jstr "$(now)")"
    if [ -s "$REQUIRED" ]; then
      printf '"required":['; first=1
      while IFS= read -r req; do [ "$first" -eq 1 ] || printf ','; first=0; jstr "$req"; done < "$REQUIRED"
      printf '],'
    else
      printf '"required":null,'
    fi
    printf '"stack":['; first=1
    while IFS="$(printf '\t')" read -r p sha prstate st; do
      [ -n "$p" ] || continue
      [ "$first" -eq 1 ] || printf ','; first=0
      printf '{"pr":%s,"head_sha":%s,"pr_state":%s,"state":%s}' "$p" "$(jstr "$sha")" "$(jstr "$prstate")" "$(jstr "$st")"
    done < "$PRS"
    printf '],"checks":['; first=1
    # \037, not <tab>: `read` merges adjacent tabs, so an empty link would shift `waived` into it
    while IFS="$(printf '\037')" read -r p n b l w; do
      [ -n "$p" ] || continue
      [ "$first" -eq 1 ] || printf ','; first=0
      printf '{"pr":%s,"name":%s,"bucket":%s,"run_id":%s,"link":%s,"waived":%s}' "$p" "$(jstr "$n")" "$(jstr "$b")" \
        "$(jstr "$(printf '%s' "$l" | sed -nE 's#.*/actions/runs/([0-9]+).*#\1#p')")" "$(jstr "$l")" "${w:-false}"
    done < <(tr '\t' '\037' < "$CHECKS")
    printf '],"line":%s,"exit":%s}\n' "$(jstr "$line")" "$code"
  } > "$JSON"
  echo "ci-boundary: record → $JSON"
  printf '%s\n' "$line"
  exit "$code"
}

is_marker() { printf '%s' "$1" | grep -qE '^(SETUP|HUMAN-H[0-9]+|GATE-G[0-9]+|GATE-ACCEPT|\(none\)|none)$'; }

ci_declared() {
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do [ -f "$f" ] && return 0; done
  for f in .gitlab-ci.yml .circleci/config.yml azure-pipelines.yml bitbucket-pipelines.yml .travis.yml Jenkinsfile "$POLICY"; do
    [ -f "$f" ] && return 0
  done
  [ -d .buildkite ] && return 0
  return 1
}

# ── 1. No CI declared → none-declared (the caller records locally-green) ──────
if [ -z "$HOOK" ] && ! ci_declared; then
  emit "none-declared" 0 "ci: none-declared (locally-green)"
fi

# ── 2. Resolve the PR ─────────────────────────────────────────────────────────
have_gh() { command -v gh >/dev/null 2>&1; }
pr_from_index() {   # BUILD_INDEX.md row for $1 → its PR cell (header-aware), last matching row
  local idx; idx="$(dirname "$LEDGER")/BUILD_INDEX.md"
  [ -f "$idx" ] || return 0
  LC_ALL=C awk -F'|' -v t="$1" '
    function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
    function bare(x) { gsub(/[[:space:]`*_]/, "", x); return x }
    /^\|/ {
      tc = 0; pc = 0
      for (i = 1; i <= NF; i++) { c = tolower(trim($i)); if (c == "ticket") tc = i; if (c == "pr") pc = i }
      if (tc && pc) { TC = tc; PC = pc; next }
    }
    /^\|/ && TC && bare($TC) == t {
      cell = $PC
      if (match(cell, /\/pull\/[0-9]+/)) { v = substr(cell, RSTART + 6, RLENGTH - 6) }
      else if (match(cell, /#[0-9]+/)) { v = substr(cell, RSTART + 1, RLENGTH - 1) }
    }
    END { if (v != "") print v }' "$idx"
}
pr_from_phaselog() {   # last PHASE LOG "done" entry for $1 → `PR #n` / `/pull/n`
  local t_re; t_re="$(printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g')"
  grep -E "^-[[:space:]]" "$LEDGER" 2>/dev/null | sed -E 's/[*_`]//g' \
    | grep -E "—[[:space:]]*${t_re}[[:space:]]+done([[:space:]]|$)" | tail -1 \
    | grep -oE 'PR #[0-9]+|/pull/[0-9]+' | head -1 | grep -oE '[0-9]+'
}
pr_from_head() {   # the open PR whose head branch is $1
  have_gh || return 0
  gh pr list --head "$1" --state open --json number --jq '.[0].number // empty' 2>/dev/null | head -1
}

if [ -z "$PR" ]; then
  tip="$(lval chainTip)"
  case "$tip" in ''|'('*) tip="" ;; esac
  if [ -n "$TICKET" ] && ! is_marker "$TICKET"; then
    PR="$(pr_from_index "$TICKET")"
    [ -n "$PR" ] || PR="$(pr_from_phaselog "$TICKET")"
    # chainTip is the branch of lastCompleted only: never use it for another ticket.
    [ -n "$PR" ] || { [ -n "$tip" ] && [ "$TICKET" = "$(lval lastCompleted)" ] && PR="$(pr_from_head "$tip")"; }
    [ -n "$PR" ] || emit "unknown" 5 "blockedOn: CI unknown on ${TICKET} (no PR): no PR found for ${TICKET} in BUILD_INDEX, the PHASE LOG or the chainTip ${tip:-(unset)}"
  else
    [ -n "$tip" ] && PR="$(pr_from_head "$tip")"
    if [ -z "$PR" ]; then
      have_gh || emit "unknown" 5 "blockedOn: CI unknown on ${TICKET:-chainTip} (gh): gh is not installed — cannot read the chainTip PR"
      emit "not-applicable" 0 "ci: not-applicable (${TICKET:-chainTip}: no open PR at chainTip ${tip:-(unset)})"
    fi
  fi
fi
PR="${PR#\#}"

# ── 3. Repo hook → delegate, pass the exit code through ──────────────────────
if [ -n "$HOOK" ]; then
  # The hook contract is `--pr <n> --json <path>`; an optional flag goes along only when the caller gave it
  # and the hook's file names it (a hook written before these flags never receives one it would reject).
  hook_names() { grep -qaE -- "(^|[^A-Za-z0-9_-])$1([^A-Za-z0-9_-]|\$)" "$HOOK" 2>/dev/null; }
  HARGS=(--pr "$PR" --json "$JSON")
  if [ -n "$LEDGER" ] && hook_names --ledger; then HARGS+=(--ledger "$LEDGER"); fi
  if [ "$INTERVAL_GIVEN" -eq 1 ] && hook_names --interval; then HARGS+=(--interval "$INTERVAL"); fi
  case "$WAIT_GIVEN" in
    none) if hook_names --no-wait; then HARGS+=(--no-wait); elif hook_names --max-wait; then HARGS+=(--max-wait 0); fi ;;
    max)  if hook_names --max-wait; then HARGS+=(--max-wait "$MAX_WAIT")
          elif [ "$MAX_WAIT" -eq 0 ] && hook_names --no-wait; then HARGS+=(--no-wait); fi ;;
  esac
  echo "ci-boundary: delegating to the repo hook $HOOK (${HARGS[*]})"
  case "$HOOK" in
    *.py) python3 "$HOOK" "${HARGS[@]}" ;;
    *.sh) bash "$HOOK" "${HARGS[@]}" ;;
    *)    "./$HOOK" "${HARGS[@]}" ;;
  esac
  exit $?
fi

# ── 4. Read with gh ───────────────────────────────────────────────────────────
have_gh || emit "unknown" 5 "blockedOn: CI unknown on #$PR (gh): gh is not installed, but the repo declares CI"

if [ -f "$POLICY" ]; then
  sed -E 's/#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//' "$POLICY" | grep -v '^$' > "$REQUIRED"
fi
# Waivers: 7-column GATE DECISIONS rows (header ends in `kind`) whose kind is `waiver`.
if [ -n "$LEDGER" ]; then
  LC_ALL=C awk -F'|' '
    /^##[[:space:]]/ { ingd = ($0 ~ /^##[[:space:]]+GATE DECISIONS/); hk = 0; next }
    ingd && /^\|/ {
      last = ""; for (i = NF; i >= 1; i--) { c = $i; gsub(/[[:space:]`*]/, "", c); if (c != "") { last = c; break } }
      if (last == "kind") { hk = 1; next }          # a 7-column header
      if (last == "consequence") { hk = 0; next }   # a legacy 6-column header
      if (hk && last == "waiver") print
    }' "$LEDGER" > "$WAIVERS" 2>/dev/null
fi
waived() {   # waived <pr> <check name>
  [ -s "$WAIVERS" ] || return 1
  local n_re; n_re="$(printf '%s' "$2" | sed 's/[][\.*^$/+?(){}|]/\\&/g')"
  grep -E "#$1([^0-9]|$)" "$WAIVERS" | grep -qE "(^|[^A-Za-z0-9_-])${n_re}([^A-Za-z0-9_-]|$)"
}

# The PR set: this PR, then (with --stack) each open PR whose head is the previous one's base.
# PRS rows: pr \t head_sha \t pr_state \t state (state filled by the polls).
view_pr() {   # view_pr <n> → "sha \t state \t base \t head" or nonzero
  gh pr view "$1" --json headRefOid,state,baseRefName,headRefName \
    --jq '[.headRefOid, .state, .baseRefName, .headRefName] | @tsv' 2>/dev/null
}
v="$(view_pr "$PR")" || v=""
[ -n "$v" ] || emit "unknown" 5 "blockedOn: CI unknown on #$PR (gh): gh pr view #$PR failed (not found, unauthenticated or offline)"
HEAD_SHA="$(printf '%s' "$v" | cut -f1)"
printf '%s\t%s\t%s\t%s\n' "$PR" "$HEAD_SHA" "$(printf '%s' "$v" | cut -f2)" "pending" >> "$PRS"
if [ "$STACK" -eq 1 ]; then
  base="$(printf '%s' "$v" | cut -f3)" ; hops=0
  while [ -n "$base" ] && [ "$hops" -lt 200 ]; do
    hops=$((hops + 1))
    anc="$(pr_from_head "$base")"
    [ -n "$anc" ] || break
    cut -f1 "$PRS" | grep -qxF "$anc" && break
    av="$(view_pr "$anc")" || av=""
    [ -n "$av" ] || emit "unknown" 5 "blockedOn: CI unknown on #$anc (gh): gh pr view #$anc failed (stack ancestor of #$PR)"
    printf '%s\t%s\t%s\t%s\n' "$anc" "$(printf '%s' "$av" | cut -f1)" "$(printf '%s' "$av" | cut -f2)" "pending" >> "$PRS"
    base="$(printf '%s' "$av" | cut -f3)"
  done
fi

# Read one PR's checks into $CHECKS.<n> and print its state + first-failure detail:
#   "pass" | "fail\t<check>\t<detail>" | "pending\t<check>\t<detail>" | "unknown\t-\t<detail>"
read_pr() {
  local n="$1" final="$2" out err rc name bucket link desc wf run
  err="$(mktemp)"
  out="$(gh pr checks "$n" --json name,bucket,link,description,workflow \
         --jq '.[] | [.name, .bucket, .link, (.description // ""), (.workflow // "")] | @tsv' 2>"$err")"; rc=$?
  : > "$CHECKS.$n"
  if [ -z "$out" ] && [ "$rc" -ne 0 ] && ! grep -qi 'no checks reported' "$err"; then
    printf 'unknown\t-\t%s\n' "gh pr checks #$n failed: $(head -1 "$err")"; rm -f "$err"; return
  fi
  rm -f "$err"
  local fail_l="" pend_l="" seen=0
  # \037, not <tab>: an empty link or description must not shift the next field into it
  while IFS="$(printf '\037')" read -r name bucket link desc wf; do
    [ -n "$name" ] || continue
    seen=1
    local w=false
    case "$bucket" in fail|cancel) waived "$n" "$name" && w=true ;; esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$name" "$bucket" "$link" "$w" >> "$CHECKS.$n"
    if [ -s "$REQUIRED" ]; then grep -qxF "$name" "$REQUIRED" || continue; fi
    case "$bucket" in
      pass) : ;;
      fail|cancel)
        if [ "$w" != true ] && [ -z "$fail_l" ]; then
          run="$(printf '%s' "$link" | sed -nE 's#.*/actions/runs/([0-9]+).*#\1#p')"
          fail_l="${name}${TAB}$(printf '%s' "${desc:-$bucket}" | cut -c1-120)${run:+ (run $run)}"
        fi ;;
      skipping) if [ -s "$REQUIRED" ] && [ -z "$fail_l" ]; then fail_l="${name}${TAB}required check skipped"; fi ;;
      *) [ -n "$pend_l" ] || pend_l="${name}${TAB}$(printf '%s' "${desc:-pending}" | cut -c1-120)" ;;
    esac
  done <<EOF
$(printf '%s\n' "$out" | tr '\t' '\037')
EOF
  if [ -s "$REQUIRED" ]; then
    local r
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      cut -f2 "$CHECKS.$n" | grep -qxF "$r" && continue
      # Missing once a real wait has ended is a failure; on a single read (--no-wait) it is pending.
      if [ "$final" -eq 1 ] && [ "$MAX_WAIT" -gt 0 ]; then [ -n "$fail_l" ] || fail_l="${r}${TAB}required check missing"
      else [ -n "$pend_l" ] || pend_l="${r}${TAB}required check not reported yet"; fi
    done < "$REQUIRED"
  fi
  if [ -n "$fail_l" ]; then printf 'fail\t%s\n' "$fail_l"
  elif [ -n "$pend_l" ]; then printf 'pending\t%s\n' "$pend_l"
  elif [ "$seen" -eq 0 ]; then printf 'pending\t-\tno checks reported yet\n'
  else printf 'pass\n'; fi
}

START=$SECONDS
while :; do
  final=0; [ $((SECONDS - START + INTERVAL)) -gt "$MAX_WAIT" ] && final=1
  fail_pr="" fail_d="" pend_pr="" pend_d="" unk_pr="" unk_d=""
  newp="$(mktemp)"
  while IFS="$(printf '\t')" read -r p sha prstate st; do
    [ -n "$p" ] || continue
    if [ "$st" = "pass" ]; then printf '%s\t%s\t%s\t%s\n' "$p" "$sha" "$prstate" "$st" >> "$newp"; continue; fi
    res="$(read_pr "$p" "$final")"
    st="$(printf '%s' "$res" | cut -f1)"
    case "$st" in
      fail)    [ -n "$fail_pr" ] || { fail_pr="$p"; fail_d="$(printf '%s' "$res" | cut -f2-)"; } ;;
      pending) [ -n "$pend_pr" ] || { pend_pr="$p"; pend_d="$(printf '%s' "$res" | cut -f2-)"; } ;;
      unknown) [ -n "$unk_pr" ] || { unk_pr="$p"; unk_d="$(printf '%s' "$res" | cut -f2-)"; } ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$p" "$sha" "$prstate" "$st" >> "$newp"
  done < "$PRS"
  mv "$newp" "$PRS"
  : > "$CHECKS"; for p in $(cut -f1 "$PRS"); do [ -f "$CHECKS.$p" ] && cat "$CHECKS.$p" >> "$CHECKS"; done
  if [ -n "$fail_pr" ]; then
    emit "fail" 3 "blockedOn: CI fail on #$fail_pr ($(printf '%s' "$fail_d" | cut -f1)): $(printf '%s' "$fail_d" | cut -f2-)"
  fi
  if [ -n "$unk_pr" ]; then
    emit "unknown" 5 "blockedOn: CI unknown on #$unk_pr (gh): $(printf '%s' "$unk_d" | cut -f2-)"
  fi
  if [ -z "$pend_pr" ]; then
    jobs="$(awk -F'\t' -v p="$PR" '
      $1 != p { next }
      $3 == "pass" { r = $4; if (r ~ /\/actions\/runs\/[0-9]/) { sub(/.*\/actions\/runs\//, "", r); sub(/[^0-9].*/, "", r) } else r = "-"; s = s (s ? "; " : "") $2 " " r }
      $5 == "true" { s = s (s ? "; " : "") $2 " waived" }
      END { print s }' "$CHECKS")"
    anc="$(awk -F'\t' -v p="$PR" '$1 != p { s = s " #" $1 } END { print s }' "$PRS")"
    wvd="$(awk -F'\t' -v p="$PR" '$5 == "true" && $1 != p { s = s (s ? ", " : "") "#" $1 " " $2 } END { print s }' "$CHECKS")"
    emit "pass" 0 "ci: pass #$PR@$(printf '%s' "$HEAD_SHA" | cut -c1-7) (${jobs:-only skipped checks})${anc:+ · stack:$anc pass}${wvd:+ · waived: $wvd}"
  fi
  if [ "$final" -eq 1 ]; then
    emit "pending" 4 "blockedOn: CI pending on #$pend_pr ($(printf '%s' "$pend_d" | cut -f1)): $(printf '%s' "$pend_d" | cut -f2-) after ${MAX_WAIT}s"
  fi
  echo "ci-boundary: #$pend_pr pending ($(printf '%s' "$pend_d" | cut -f1)) — re-reading in ${INTERVAL}s (waited $((SECONDS - START))s of ${MAX_WAIT}s)" >&2
  sleep "$INTERVAL"
done
