#!/usr/bin/env bash
# stub-gh.sh — a canned `gh` for the orchestrate-build self-test. Installed as `gh` on PATH.
#
# Reads canned answers from $STUB_GH_DIR and appends every call to $STUB_GH_DIR/calls:
#   gh pr view <n> …          → $D/view-<n>  ("<headSha>\t<STATE>\t<base>\t<head>"); absent → exit 1
#   gh pr list --head <b> …   → $D/head-<b> (a PR number; `/` in <b> written as `_`); absent → empty
#   gh pr list --state <s> …  → $D/list-<s> (pre-rendered --jq output lines); absent → empty
#   gh pr checks <n> …        → $D/checks-<n>.<k> for the k-th call (the highest k <= the call count),
#                               else $D/checks-<n>; lines "<name>\t<bucket>\t<link>\t<description>\t<workflow>".
#                               A file whose first line is `@nochecks` or `@error` emulates gh's stderr + exit 1.
# Compatible with bash 3.2+.
D="${STUB_GH_DIR:?STUB_GH_DIR not set}"
printf '%s\n' "$*" >> "$D/calls"
[ "${1:-}" = "pr" ] || { echo "stub gh: unsupported: $*" >&2; exit 1; }
sub="${2:-}"; shift 2
case "$sub" in
  view)
    [ -f "$D/view-$1" ] || { echo "GraphQL: Could not resolve to a PullRequest with the number of $1." >&2; exit 1; }
    cat "$D/view-$1" ;;
  list)
    head="" ; state=""
    while [ $# -gt 0 ]; do [ "$1" = "--head" ] && head="${2:-}"; [ "$1" = "--state" ] && state="${2:-}"; shift; done
    if [ -n "$head" ]; then f="$D/head-$(printf '%s' "$head" | tr '/' '_')"; else f="$D/list-$state"; fi
    [ -f "$f" ] && cat "$f"
    exit 0 ;;
  checks)
    n="$1"; c=0
    [ -f "$D/count-$n" ] && c="$(cat "$D/count-$n")"
    c=$((c + 1)); printf '%s\n' "$c" > "$D/count-$n"
    f="" ; k=1
    while [ "$k" -le "$c" ]; do [ -f "$D/checks-$n.$k" ] && f="$D/checks-$n.$k"; k=$((k + 1)); done
    [ -n "$f" ] || f="$D/checks-$n"
    [ -f "$f" ] || { echo "no checks reported on the 'branch-$n' branch" >&2; exit 1; }
    case "$(head -1 "$f")" in
      @nochecks) echo "no checks reported on the 'branch-$n' branch" >&2; exit 1 ;;
      @error)    echo "HTTP 401: Bad credentials (https://api.github.com/graphql)" >&2; exit 1 ;;
    esac
    cat "$f" ;;
  *) echo "stub gh: unsupported: pr $sub" >&2; exit 1 ;;
esac
