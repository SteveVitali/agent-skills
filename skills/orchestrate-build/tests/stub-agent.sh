#!/usr/bin/env bash
# stub-agent.sh — a stand-in agent CLI for drive-build.sh --agent-cmd. Ignores the prompt (its last
# argument) and closes exactly one ticket in $STUB_LEDGER, the way implement-spec Phase 6.5 would:
# lastCompleted ← nextTicket, nextTicket ← the next id in $STUB_CHAIN (or DONE), a BUILD_INDEX row with
# PR #<$STUB_PR_BASE + position>. STUB_AGENT_MODE=gate instead records a pending gate (returnPass) and
# does not advance. Counts its invocations in $STUB_LEDGER.agent-calls and saves the last prompt in
# $STUB_LEDGER.prompt. Compatible with bash 3.2+.
L="${STUB_LEDGER:?}"; IDX="$(dirname "$L")/BUILD_INDEX.md"
c=0; [ -f "$L.agent-calls" ] && c="$(cat "$L.agent-calls")"; printf '%s\n' "$((c + 1))" > "$L.agent-calls"
prompt=""; for a in "$@"; do prompt="$a"; done; printf '%s\n' "$prompt" > "$L.prompt"   # the trailing positional
val() { grep -m1 -E "^$1:" "$L" | sed -E "s/^$1:[[:space:]]*//; s/[[:space:]]*#.*$//"; }
set_val() { awk -v k="$1" -v v="$2" '$0 ~ "^" k ":" { printf "%-17s%s\n", k ":", v; next } { print }' "$L" > "$L.tmp" && mv "$L.tmp" "$L"; }
next="$(val nextTicket)"
if [ "${STUB_AGENT_MODE:-advance}" = "gate" ]; then set_val returnPass "$next"; exit 0; fi
pos=0; new_next="DONE"; found=0
for t in ${STUB_CHAIN:-T1 T2}; do
  pos=$((pos + 1))
  if [ "$found" -eq 1 ]; then new_next="$t"; break; fi
  [ "$t" = "$next" ] && { found=1; me="$pos"; }
done
pr=$(( ${STUB_PR_BASE:-6} + ${me:-0} ))
set_val lastCompleted "$next"
set_val nextTicket "$new_next"
set_val chainTip "demo/$next"
[ "$new_next" = "DONE" ] && set_val projectStatus DONE
printf '| %s | %s | ticket | demo/%s | #%s | demo/base | 2026-10-01 | — | — | n-a | runs/%s.md | stub |\n' \
  "$me" "$next" "$next" "$pr" "$next" >> "$IDX"
printf -- '- 2026-10-01 — %s done — demo/%s · PR #%s · stub close\n' "$next" "$next" "$pr" >> "$L"
exit 0
