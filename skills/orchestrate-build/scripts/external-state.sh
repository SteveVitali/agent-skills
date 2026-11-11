#!/usr/bin/env bash
# external-state.sh — classify what changed OUTSIDE the loop at a ticket boundary (orchestrate-build §2.3
# step 5; layout.md "CI and production at the boundary", BM-EXT-01). Read-only (run `git fetch` first).
#
# The default branch and the chain branches can move without the loop: the operator merges chain PRs (merge
# commit, squash or rebase), GitHub retargets the next PR, the operator rebases the remaining branch or merges
# the default branch in, or someone (a person, a bot) pushes onto a chain branch. This script names each event
# so the orchestrator records it instead of guessing, and recognizes two scoped operating rules — GATE
# DECISIONS `pre-authorization` rows (BM-GATE-09):
#   ext:merge-in-order                 the operator merges the chain bottom-up and then rebases or merges the
#                                      default branch into the rest (needs mergePolicy OPERATOR | AUTO-BOTTOM-UP)
#   ext:bot-commits <author-ERE>[, …]  commits by a matching author on a chain branch are expected when each one
#                                      only merges the default branch in, changes whitespace only, or (with
#                                      `paths: <glob>[,<glob>…]` in the row) touches only those paths
#
# Usage:
#   external-state.sh --ledger <LEDGER.md> [--worktree DIR] [--default REF] [--remote NAME] [--no-gh]
#                     [--now ISO] [--json PATH]
#
#   --ledger    The build ledger (chainTip, pinnedBaseSha, mergePolicy, lastCompleted, GATE DECISIONS); its
#               BUILD_INDEX.md (same dir) names the chain rows in order (ticket, branch, PR, base columns).
#   --worktree  Where git and gh run (default: the ledger's buildWorktree when it is a directory, else its repo).
#   --default   The default branch ref (default: refs/remotes/origin/HEAD, else origin/main).
#   --remote    The remote whose copy of each chain branch is compared with the local one (default: origin).
#   --no-gh     Never call gh (git only). Without it, gh is used when on PATH; a PR gh cannot read falls back
#               to git for that row.
#   --now       The clock for a dated `expires:` (default: `date -u`; tests).
#   --json      Write the external-state/1 record here (default: none).
#
# How a chain row counts as merged into the default branch D (first evidence wins):
#   gh       `gh pr view <n> --json state,mergedAt,mergeCommit,headRefName,headRefOid,baseRefName` says MERGED
#   merge    the row's tip is an ancestor of D
#   squash   a first-parent commit of D since merge-base(D, chainTip) whose subject ends in `(#<row PR>)`, or
#            whose patch-id equals the row's whole diff (its base → its tip)
#   rebase   every commit of the row has a patch-equivalent on D (`git cherry`)
# A merged row is *pending* while the commit that brought it into D is not yet in the chainTip; once the chain is
# rebased onto (or merged with) D it is integrated and no longer an event.
#
# Events (D against the chainTip C, PR bases via gh, then every chain branch b against <remote>/b):
#   default-advanced         D moved and no chain row is newly merged — informational (the chain is untouched)
#   chain-merged(T1,…)       a bottom prefix of the chain is merged into D (any method above)              [M]
#   retargeted(#n: a → b)    an open chain PR's base changed (gh only); to D after its base row merged      [M]
#   chain-merged-partial     a chain commit reached D without a bottom prefix of whole rows (gap, part of a row)
#   default-rewritten        pinnedBaseSha is no longer on D (a force-push or a rewrite of the default branch)
#   rebased-onto-default(b)  <remote>/b holds every local commit (or a patch-equivalent) plus only D's commits [M]
#   default-merged-in(b)     <remote>/b = local b + D's commits + merge commits of D                       [M]
#   bot-commits(b: …)        <remote>/b carries commits by an ext:bot-commits author, each a merge of D,
#                            whitespace-only, or inside the row's `paths:`                                   [B]
#   foreign-commits(b: …)    <remote>/b carries any other commit that is not D's, not a patch-equivalent,
#                            not a merge of D
#   foreign-rewrite(b)       <remote>/b dropped a local commit (no patch-equivalent; a merged row's commits excepted)
#   unpushed(b)              local b is ahead of <remote>/b — informational
# [M] = expected under a live ext:merge-in-order row · [B] = only recognized under a live ext:bot-commits row
# (without it those commits are foreign-commits). Every other non-informational event is always a blockedOn.
#
# A pre-authorization row (7-column GATE DECISIONS; the operator's words verbatim, BM-GATE-05/09):
#   | <date -u> | * | external | ext:merge-in-order | "<words>" (<channel>) | <reading> · expires: <ticket|YYYY-MM-DD> · voided-by: <…> | pre-authorization |
#   | <date -u> | * | external | ext:bot-commits ci-format-bot | "<words>" (<channel>) | <reading> · paths: *.md · expires: … · voided-by: … | pre-authorization |
# Author patterns are EREs matched against `<name> <<email>>`, separated by commas (a `|` would split the table).
# A row is live until `expires:` passes (a date after the clock's date, or a ticket id that has landed — a
# BUILD_INDEX row or lastCompleted) or a later `correction` row names the same item with "void". `voided-by:` prose
# (a material new fact) is the orchestrator's to judge; the script prints it.
#
# Output: one line per event, then the line to record —
#   external: clean — D @sha is an ancestor of chainTip C @sha
#   external: informational — <events>
#   external: expected — <events> (pre-authorized: LEDGER.md line <n> <item>, expires <x>; voided-by: <…>[ · …])
#   blockedOn: external — <events> (the operator decides…)
#   external: unknown — <why>
# Exit codes (the shared build-script contract): 0 clean, informational or expected · 1 usage · 3 blockedOn ·
#   5 unknown (a ref that does not resolve — never treated as clean).
# Bash 3.2+, git; gh optional. No associative arrays, no mapfile.

set -uo pipefail

LEDGER="" ; WT="" ; DEF="" ; REMOTE="origin" ; NOW="" ; JSON="" ; NOGH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ledger)   LEDGER="${2:-}"; shift 2 ;;
    --worktree) WT="${2:-}"; shift 2 ;;
    --default)  DEF="${2:-}"; shift 2 ;;
    --remote)   REMOTE="${2:-}"; shift 2 ;;
    --no-gh)    NOGH=1; shift ;;
    --now)      NOW="${2:-}"; shift 2 ;;
    --json)     JSON="${2:-}"; shift 2 ;;
    -h|--help)  awk 'NR > 1 && !/^#/ {exit} NR > 1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    *) echo "external-state.sh: unknown arg: $1 (try --help)" >&2; exit 1 ;;
  esac
done
[ -n "$LEDGER" ] && [ -f "$LEDGER" ] || { echo "external-state.sh: --ledger <existing LEDGER.md> required" >&2; exit 1; }
LEDGER="$(cd "$(dirname "$LEDGER")" && pwd)/$(basename "$LEDGER")"
NOW="${NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"; TODAY="$(printf '%s' "$NOW" | cut -c1-10)"
TAB="$(printf '\t')"
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD" 2>/dev/null' EXIT

lval() { grep -m1 -E "^[[:space:]]*${1}:" "$LEDGER" 2>/dev/null | sed -E "s/^[[:space:]]*${1}:[[:space:]]*//; s/[[:space:]]*#.*$//" | awk '{print $1}'; }
if [ -z "$WT" ]; then bw="$(lval buildWorktree)"; case "$bw" in /*) [ -d "$bw" ] && WT="$bw" ;; esac; fi
[ -n "$WT" ] || WT="$(git -C "$(dirname "$LEDGER")" rev-parse --show-toplevel 2>/dev/null || pwd)"
G() { git -C "$WT" "$@"; }
[ -n "$DEF" ] || DEF="$(G symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
DNAME="${DEF#"$REMOTE"/}"            # the default branch as the forge names it (a PR's baseRefName)

emit() {   # emit <exit> <line>
  printf '%s\n' "$2"
  if [ -n "$JSON" ]; then
    local ev; ev="$(printf '%s\n' "${EVENTS:-}" | awk 'NF { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s\"%s\"", (n++ ? "," : ""), $0 }')"
    printf '{"schema":"external-state/1","default":"%s","default_sha":"%s","chain_tip":"%s","chain_tip_sha":"%s","events":[%s],"line":"%s","exit":%s}\n' \
      "$DEF" "${DSHA:-}" "${CT:-}" "${CSHA:-}" "$ev" "$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')" "$1" > "$JSON"
  fi
  exit "$1"
}
sha() { G rev-parse --verify -q "$1^{commit}" 2>/dev/null; }
anc() { G merge-base --is-ancestor "$1" "$2" 2>/dev/null; }
short() { printf '%.7s' "$1"; }

CT="$(lval chainTip)"; PB="$(lval pinnedBaseSha)"; POLICY="$(lval mergePolicy)"; LASTC="$(lval lastCompleted)"
DSHA="$(sha "$DEF")" || true
[ -n "$DSHA" ] || emit 5 "external: unknown — the default branch '$DEF' does not resolve in $WT (git fetch?)"
CSHA="$(sha "$CT")" || true
[ -n "$CSHA" ] || emit 5 "external: unknown — chainTip '${CT:-<unset>}' does not resolve in $WT"
PBSHA="$(sha "$PB")" || true

# ── Chain rows (BUILD_INDEX: ticket, branch, PR, base), in order ─────────────
BI="$(dirname "$LEDGER")/BUILD_INDEX.md"; : > "$TMPD/rows"
[ -f "$BI" ] && LC_ALL=C awk -F'|' '
  function t(x) { gsub(/[*`]/, "", x); gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
  function w(x) { x = t(x); sub(/[[:space:]].*$/, "", x); return x }
  /^\|/ { if ($0 ~ /^\|[-|: ]+\|[[:space:]]*$/) next
          a = b = p = s = 0
          for (i = 1; i <= NF; i++) { c = tolower(t($i)); if (c == "ticket") a = i; if (c == "branch") b = i; if (c == "pr") p = i; if (c == "base") s = i }
          if (a && b) { tc = a; bc = b; pc = p; sc = s; next }
          if (tc && bc) { tk = w($tc); br = w($bc); pr = ""
            if (pc && match($pc, /#[0-9]+/)) pr = substr($pc, RSTART + 1, RLENGTH - 1)
            if (tk != "" && br != "") print tk "\t" br "\t" pr "\t" (sc ? w($sc) : "") } }' "$BI" > "$TMPD/rows"
TICKETS="$(cut -f1 "$TMPD/rows")"

# ── Pre-authorizations (GATE DECISIONS) ──────────────────────────────────────
preauth() {   # preauth <token> → PA_LN PA_ITEM PA_ROW PA_EXP PA_VOID PA_LIVE PA_NOTE
  local out
  out="$(LC_ALL=C awk -F'|' -v tok="$1" '
    function bare(x) { gsub(/[[:space:]`*]/, "", x); return x }
    function trim(x) { gsub(/^[[:space:]`]+|[[:space:]`]+$/, "", x); return x }
    /^##[[:space:]]/ { ingd = ($0 ~ /^##[[:space:]]+GATE DECISIONS/); kc = 0; next }
    ingd && /^\|/ {
      if ($0 ~ /^\|[-|: ]+\|[[:space:]]*$/) next
      hk = hc = hi = 0
      for (i = 1; i <= NF; i++) { c = tolower(bare($i)); if (c == "kind") hk = i; if (c == "consequence") hc = i; if (c == "item") hi = i }
      if (hc) { kc = hk; ic = hi; next }
      if (!kc || !ic || index($ic, tok) == 0) next
      k = bare($kc)
      if (k == "pre-authorization") { ln = NR; row = $0; item = trim($ic) }
      else if (k == "correction" && tolower($0) ~ /void/) ln = 0
    }
    END { if (ln) print ln "\t" item "\t" row }' "$LEDGER")"
  PA_LN="" ; PA_ITEM="" ; PA_ROW="" ; PA_EXP="" ; PA_VOID="" ; PA_LIVE=0 ; PA_NOTE=""
  [ -n "$out" ] || return 0
  PA_LN="$(printf '%s' "$out" | cut -f1)"; PA_ITEM="$(printf '%s' "$out" | cut -f2)"; PA_ROW="$(printf '%s' "$out" | cut -f3-)"
  PA_EXP="$(printf '%s' "$PA_ROW" | sed -nE 's/.*expires:[[:space:]]*`?([^[:space:]`·;|,]+).*/\1/p')"
  PA_VOID="$(printf '%s' "$PA_ROW" | sed -nE 's/.*voided-by:[[:space:]]*([^|]*).*/\1/p' | sed -E 's/[[:space:]]+$//')"
  PA_LIVE=1
  if [ -z "$PA_EXP" ] || [ -z "$PA_VOID" ]; then PA_LIVE=0; PA_NOTE="LEDGER.md line $PA_LN lacks expires:/voided-by: (BM-GATE-09)"
  elif printf '%s' "$PA_EXP" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
    [ "$TODAY" \> "$(printf '%s' "$PA_EXP" | cut -c1-10)" ] && { PA_LIVE=0; PA_NOTE="LEDGER.md line $PA_LN expired $PA_EXP"; }
  elif [ "$LASTC" = "$PA_EXP" ] || printf '%s\n' "$TICKETS" | grep -qxF "$PA_EXP"; then
    PA_LIVE=0; PA_NOTE="LEDGER.md line $PA_LN expired: $PA_EXP has landed"
  fi
}
preauth "ext:merge-in-order"
M_LN="$PA_LN"; M_ITEM="$PA_ITEM"; M_EXP="$PA_EXP"; M_VOID="$PA_VOID"; M_LIVE="$PA_LIVE"; M_NOTE="$PA_NOTE"
if [ -n "$M_LN" ]; then
  case "${POLICY:-}" in OPERATOR|AUTO-BOTTOM-UP) : ;; *) M_LIVE=0; M_NOTE="mergePolicy is '${POLICY:-<unset>}', not OPERATOR or AUTO-BOTTOM-UP" ;; esac
fi
preauth "ext:bot-commits"
B_LN="$PA_LN"; B_ITEM="$PA_ITEM"; B_EXP="$PA_EXP"; B_VOID="$PA_VOID"; B_LIVE="$PA_LIVE"
B_PATS="" ; B_PATHS=""
if [ "$B_LIVE" -eq 1 ]; then
  B_PATS="$(printf '%s' "$B_ITEM" | sed -E 's/.*ext:bot-commits//' | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$')"
  B_PATHS="$(printf '%s' "$PA_ROW" | sed -nE 's/.*paths:[[:space:]]*([^·;|]+).*/\1/p' | tr ',' '\n' | sed -E 's/^[[:space:]`]+|[[:space:]`]+$//g' | grep -v '^$')"
  [ -n "$B_PATS" ] || B_LIVE=0
fi

# bot_kind <commit> → prints merge-of-default | whitespace-only | paths-allowlisted when an ext:bot-commits author's
# commit is of an accepted shape; returns 1 otherwise (and for every commit when no bot row is live).
bot_kind() {
  local c="$1" who p n f a b ok=1 g
  [ "$B_LIVE" -eq 1 ] || return 1
  who="$(G log -1 --format='%an <%ae>' "$c")"
  printf '%s\n' "$B_PATS" | while IFS= read -r p; do printf '%s' "$who" | grep -qE -- "$p" && echo hit; done | grep -q hit || return 1
  n="$(G rev-list --parents -n1 "$c" | wc -w | tr -d ' ')"
  if [ "$n" -gt 2 ]; then
    for p in $(G rev-list --parents -n1 "$c" | cut -d' ' -f3-); do anc "$p" "$DSHA" || return 1; done
    echo merge-of-default; return 0
  fi
  for f in $(G diff-tree --no-commit-id --name-only -r "$c"); do
    a="$(G show "$c^:$f" 2>/dev/null | tr -d '[:space:]' | git hash-object --stdin)"
    b="$(G show "$c:$f" 2>/dev/null | tr -d '[:space:]' | git hash-object --stdin)"
    [ "$a" = "$b" ] || { ok=0; break; }
  done
  [ "$ok" -eq 1 ] && { echo whitespace-only; return 0; }
  [ -n "$B_PATHS" ] || return 1
  for f in $(G diff-tree --no-commit-id --name-only -r "$c"); do
    ok=0
    while IFS= read -r g; do case "$f" in $g) ok=1 ;; esac; done <<PATHS
$B_PATHS
PATHS
    [ "$ok" -eq 1 ] || return 1
  done
  echo paths-allowlisted
}

EVENTS="" ; BLOCK=0 ; NEED_M=0 ; NEED_B=0
ev() { EVENTS="$EVENTS$1
"; echo "  - $1"; }

echo "external-state: $DEF @$(short "$DSHA") · chainTip $CT @$(short "$CSHA") · mergePolicy ${POLICY:-<unset>} · in $WT"

# ── gh: the PR state of every chain row (optional) ───────────────────────────
HAVE_GH=0; [ "$NOGH" -eq 0 ] && command -v gh >/dev/null 2>&1 && [ -n "$(cut -f3 "$TMPD/rows" | grep -v '^$')" ] && HAVE_GH=1
ghview() {   # ghview <n> → "state<TAB>mergeCommitOid<TAB>baseRefName<TAB>headRefName<TAB>headRefOid<TAB>mergedAt"
  ( cd "$WT" && gh pr view "$1" --json state,mergedAt,mergeCommit,headRefName,headRefOid,baseRefName \
      --jq '[.state, (.mergeCommit.oid // ""), .baseRefName, .headRefName, .headRefOid, (.mergedAt // "")] | @tsv' 2>/dev/null ) | head -1
}
NGH=0
if [ "$HAVE_GH" -eq 1 ]; then
  while IFS="$TAB" read -r tk br pr base; do
    [ -n "$pr" ] || continue
    v="$(ghview "$pr")"
    case "$(printf '%s' "$v" | cut -f1)" in OPEN|CLOSED|MERGED) printf '%s\t%s\n' "$pr" "$v" >> "$TMPD/gh"; NGH=$((NGH + 1)) ;; esac
  done < "$TMPD/rows"
fi
ghfield() { [ -f "$TMPD/gh" ] && awk -F'\t' -v p="$1" -v k="$2" '$1 == p { print $k; exit }' "$TMPD/gh"; }   # k: 2 state 3 oid 4 base

# ── The default branch against the chain ─────────────────────────────────────
MERGED_TIP=""
if anc "$DSHA" "$CSHA"; then
  :
elif [ -n "$PBSHA" ] && ! anc "$PBSHA" "$DSHA"; then
  ev "default-rewritten: pinnedBaseSha $(short "$PBSHA") is not on $DEF"; BLOCK=1
else
  MB="$(G merge-base "$DSHA" "$CSHA" 2>/dev/null)"
  G log --first-parent --max-count=5000 --format='%H %s' "${MB:+$MB..}$DSHA" 2>/dev/null > "$TMPD/fps"
  cut -d' ' -f1 "$TMPD/fps" > "$TMPD/fp"
  oldest="$(tail -1 "$TMPD/fp")"
  FP=0; { [ -z "$MB" ] || [ -z "$oldest" ] || [ "$(G rev-parse -q --verify "$oldest^1" 2>/dev/null)" = "$MB" ]; } && FP=1
  PIDS_DONE=0
  pids() {   # the patch-id of every first-parent commit of D since MB (computed once, on demand)
    [ "$PIDS_DONE" -eq 1 ] && return 0; PIDS_DONE=1
    G log --first-parent --max-count=2000 -p --no-color "${MB:+$MB..}$DSHA" 2>/dev/null | git patch-id --stable > "$TMPD/pids" 2>/dev/null
  }
  merged="" ; pending="" ; detail="" ; gap=0 ; seen_unmerged=0 ; prev_tip=""
  while IFS="$TAB" read -r tk br pr base; do
    [ -n "$tk" ] || continue
    tip="$(sha "refs/heads/$br")"; [ -n "$tip" ] || tip="$(sha "refs/remotes/$REMOTE/$br")"
    rbase="$prev_tip"; [ -n "$rbase" ] || { [ -n "$tip" ] && rbase="$(G merge-base "$tip" "$DSHA" 2>/dev/null)"; }
    how="" ; E="" ; gs="$(ghfield "$pr" 2)"
    if [ "$gs" = "MERGED" ]; then
      how="gh: #$pr merged"; E="$(ghfield "$pr" 3)"
      if [ -n "$E" ]; then sha "$E" >/dev/null || E="pending"
      elif [ -n "$tip" ] && anc "$tip" "$CSHA"; then E="pending"; fi
    elif [ -z "$gs" ]; then
      if [ -n "$tip" ] && anc "$tip" "$DSHA"; then
        how="merge commit"
        while read -r c; do anc "$tip" "$c" && ! anc "$tip" "$c^1" && { E="$c"; break; }; done < "$TMPD/fp"
      else
        c=""
        [ -n "$pr" ] && c="$(grep -E " \(#$pr\)\$" "$TMPD/fps" | head -1 | cut -d' ' -f1)"
        rowpid=""; [ -n "$tip" ] && [ -n "$rbase" ] && rowpid="$(G diff "$rbase" "$tip" | git patch-id --stable | cut -d' ' -f1)"
        if [ -n "$c" ]; then
          how="squash $(short "$c") (#$pr)"; E="$c"
          [ -n "$rowpid" ] && [ "$(G show --format= "$c" | git patch-id --stable | cut -d' ' -f1)" = "$rowpid" ] && how="$how + patch-id"
        elif [ -n "$rowpid" ] && { pids; c="$(awk -v p="$rowpid" '$1 == p { print $2; exit }' "$TMPD/pids")"; [ -n "$c" ]; }; then
          how="squash $(short "$c") (patch-id)"; E="$c"
        elif [ -n "$tip" ] && [ -n "$rbase" ] && [ -n "$(G cherry "$DSHA" "$tip" "$rbase" 2>/dev/null)" ] \
             && ! G cherry "$DSHA" "$tip" "$rbase" 2>/dev/null | grep -q '^+'; then
          how="rebase merge (patch-equivalent)"; anc "$tip" "$CSHA" && E="pending"
        fi
      fi
    fi
    if [ -n "$how" ]; then
      [ "$seen_unmerged" -eq 1 ] && gap=1
      merged="$merged${merged:+,}$tk"; [ -n "$tip" ] && MERGED_TIP="$tip"
      if [ "$E" = "pending" ] || { [ -n "$E" ] && ! anc "$E" "$CSHA"; }; then
        pending="$pending${pending:+,}$tk"; detail="$detail${detail:+; }$tk: $how"
      fi
    else
      seen_unmerged=1
    fi
    [ -n "$tip" ] && prev_tip="$tip"
  done < "$TMPD/rows"
  if [ "$gap" -eq 1 ]; then
    ev "chain-merged-partial: merged rows ($merged) are not a bottom prefix of the chain"; BLOCK=1
  elif [ -n "$pending" ]; then
    ev "chain-merged($pending): the bottom of the chain is on $DEF ($detail)"; NEED_M=1
  elif [ "$FP" -eq 1 ]; then
    ev "default-advanced: $DEF has $(G rev-list --count "$CSHA..$DSHA" 2>/dev/null) commit(s) the chain lacks, none of them a chain row's merge"
  else
    ev "chain-merged-partial: merge-base $(short "$MB") reached $DEF through a merge, but no whole bottom row of the chain did"; BLOCK=1
  fi
fi

# ── Open chain PRs whose base moved (gh only) ────────────────────────────────
if [ "$NGH" -gt 0 ]; then
  prev_tk="" ; prev_merged=0
  while IFS="$TAB" read -r tk br pr base; do
    gs="$(ghfield "$pr" 2)"; gb="$(ghfield "$pr" 4)"
    if [ "$gs" = "OPEN" ] && [ -n "$base" ] && [ -n "$gb" ] && [ "$gb" != "$base" ]; then
      if [ "$gb" = "$DNAME" ] && [ "$prev_merged" -eq 1 ]; then
        ev "retargeted(#$pr: $base → $gb): its base row $prev_tk is merged"; NEED_M=1
      else
        ev "retargeted(#$pr: $base → $gb): not to $DNAME after a merged base row"; BLOCK=1
      fi
    fi
    prev_tk="$tk"; prev_merged=0; [ "$gs" = "MERGED" ] && prev_merged=1
  done < "$TMPD/rows"
elif [ "$HAVE_GH" -eq 0 ] && [ -n "$(cut -f3 "$TMPD/rows" | grep -v '^$')" ]; then
  echo "  (PR state and retargets not read: gh $([ "$NOGH" -eq 1 ] && echo 'disabled (--no-gh)' || echo 'absent'); git only)"
fi

# ── Every chain branch against its remote copy ───────────────────────────────
BRANCHES="$(cut -f2 "$TMPD/rows")"
case "$CT" in *[!0-9a-f]*) BRANCHES="$BRANCHES
$CT" ;; esac
for b in $(printf '%s\n' "$BRANCHES" | awk 'NF && !s[$0]++'); do
  L="$(sha "refs/heads/$b")"; R="$(sha "refs/remotes/$REMOTE/$b")"
  { [ -n "$L" ] && [ -n "$R" ]; } || continue          # a deleted (merged) branch or one never pushed: nothing to compare
  [ "$L" = "$R" ] && continue
  lonly=""
  for c in $(G cherry "$R" "$L" 2>/dev/null | sed -n 's/^+ //p'); do   # local commits with no equivalent upstream…
    [ -n "$MERGED_TIP" ] && anc "$c" "$MERGED_TIP" && continue         # …except a merged row's (squash: dropped on rebase)
    lonly="$lonly $c"
  done
  req="$(G cherry "$L" "$R" 2>/dev/null | sed -n 's/^- //p')"      # remote commits equivalent to a local one
  foreign="" ; bots="" ; nonbot_merge=0 ; ronly="$(G rev-list "$L..$R" 2>/dev/null)"
  for c in $ronly; do
    anc "$c" "$DSHA" && continue
    printf '%s\n' "$req" | grep -qxF "$c" && continue
    k="$(bot_kind "$c")" && { bots="$bots $(G log -1 --format='%h %an' "$c") ($k);"; continue; }
    np="$(G rev-list --parents -n1 "$c" | wc -w | tr -d ' ')"
    if [ "$np" -gt 2 ]; then
      ok=1; for p in $(G rev-list --parents -n1 "$c" | cut -d' ' -f3-); do anc "$p" "$DSHA" || ok=0; done
      [ "$ok" -eq 1 ] && { nonbot_merge=1; continue; }
    fi
    foreign="$foreign $(G log -1 --format='%h %an' "$c")"
  done
  if [ -n "$foreign" ]; then
    ev "foreign-commits($b:$foreign): $REMOTE/$b carries commits that are neither $DEF's nor the chain's"; BLOCK=1
  elif [ -n "$lonly" ] && [ -n "$ronly" ]; then
    ev "foreign-rewrite($b): $REMOTE/$b dropped $(printf '%s\n' $lonly | grep -c .) local commit(s)"; BLOCK=1
  elif [ -n "$lonly" ]; then
    ev "unpushed($b): local $b is $(printf '%s\n' $lonly | grep -c .) commit(s) ahead of $REMOTE/$b"
  else
    [ -n "$bots" ] && { ev "bot-commits($b:${bots%;}): by an ext:bot-commits author, each of an accepted shape"; NEED_B=1; }
    if ! anc "$L" "$R"; then
      ev "rebased-onto-default($b): $REMOTE/$b holds every local commit (patch-equivalent) on top of $DEF"; NEED_M=1
    elif [ "$nonbot_merge" -eq 1 ] || { [ -z "$bots" ] && [ -n "$ronly" ]; }; then
      ev "default-merged-in($b): $REMOTE/$b = local + $DEF's commits (a merge of $DEF)"; NEED_M=1
    fi
  fi
done

# ── Verdict ──────────────────────────────────────────────────────────────────
# the event names (each up to its first `:` outside parentheses), joined
ONE="$(printf '%s' "$EVENTS" | awk 'NF { d = 0; k = length($0)
  for (i = 1; i <= length($0); i++) { c = substr($0, i, 1); if (c == "(") d++; else if (c == ")") d--; else if (c == ":" && d == 0) { k = i - 1; break } }
  printf "%s%s", (n++ ? "; " : ""), substr($0, 1, k) }')"
[ -n "$EVENTS" ] || emit 0 "external: clean — $DEF @$(short "$DSHA") is an ancestor of chainTip $CT @$(short "$CSHA")"
[ "$BLOCK" -eq 1 ] && emit 3 "blockedOn: external — $ONE (the operator decides)"
if [ "$NEED_M" -eq 1 ] && [ "$M_LIVE" -ne 1 ]; then
  emit 3 "blockedOn: external — $ONE (the operator decides; no live ext:merge-in-order pre-authorization${M_NOTE:+: $M_NOTE})"
fi
if [ "$NEED_M" -eq 1 ] || [ "$NEED_B" -eq 1 ]; then
  why=""
  [ "$NEED_M" -eq 1 ] && why="LEDGER.md line $M_LN $M_ITEM, expires $M_EXP; voided-by: $M_VOID"
  [ "$NEED_B" -eq 1 ] && why="$why${why:+ · }LEDGER.md line $B_LN $B_ITEM, expires $B_EXP; voided-by: $B_VOID"
  emit 0 "external: expected — $ONE (pre-authorized: $why)"
fi
emit 0 "external: informational — $ONE"
