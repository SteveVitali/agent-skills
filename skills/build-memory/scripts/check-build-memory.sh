#!/usr/bin/env bash
# check-build-memory.sh — validate a repo's build-memory layout. (BM-VALID-01.)
#
# Read-only. Everything the other skills derive (ADR index, BUILD_INDEX rows, the
# ticket sequence, DEFERRALS ids, the layout) is CHECKED here, never trusted:
# decompose-spec runs it after seeding, implement-spec before its close commit,
# orchestrate-build at every boundary. A failure is a real block.
#
# Usage:
#   check-build-memory.sh [repo_root]
#
# Arguments:
#   repo_root — the repo/worktree to check (default: current git toplevel, else cwd).
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
#   - ADRs: files <-> generated index (regenerate + diff); every ADR has ## Revisit trigger;
#     spec ADR appendix equals the file set when a spec+appendix is resolvable
#   - LEDGER.md: the CURRENT STATE key set present and in order (optional `harness` only
#     between round and updatedAt); nextTicket names a chain row or DONE; every PHASE LOG
#     "done" ticket has a BUILD_INDEX row and runs/<ID>.md
#   - LEDGER.md budget + shape (BM-LEDGER-08; guarded — warn, or fail under the guards
#     marker): orient region <= 12 KiB (warn > 8 KiB); CURRENT STATE lines <= 256 B with no
#     `| PRIOR`; returnPass an id list; no other line begins with a CURRENT STATE key; the
#     last `## ` heading is a PHASE LOG heading; its entries <= 2 KiB (older regions: warn)
#   - warnings: projectStatus DONE without a signed readouts/GATE-ACCEPT.md; a seed ledger
#     (PHASE LOG = the seed entry) whose GATE DECISIONS holds a non-pre-authorization row
#   - REQ coverage (when canonicalSpec + req_id_pattern resolve): every id a ticket cites
#     exists in the spec; every in-scope id has exactly one owner
#   - size + secrets: fixtures >1MB / any file >5MB under docs/build flagged; no secret
#     token shapes in docs/build or docs/tickets
#
# Output:
#   Human-readable summary to stdout.
#   Machine-readable JSON to /tmp/build-memory-check.json.
#
# Exit codes:
#   0 — clean (build-memory repo, no violations)
#   1 — violations found
#   2 — not a build-memory repo (no docs/build/README.md marker)
#
# Guards marker (BM-COMPAT-06): a line `<!-- build-memory-guards: 1 -->` alone in
# docs/build/README.md turns the guarded checks from warnings into violations.
#
# Read-only: never writes or mutates the repo (only /tmp/build-memory-check.json).
# Compatible with bash 3.2+ (macOS default). No associative arrays, no mapfile.

set -o pipefail

REPO="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MARKER='<!-- build-memory: v2 -->'
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON='/tmp/build-memory-check.json'

BUILD="$REPO/docs/build"
TICKETS="$REPO/docs/tickets"
ADR="$REPO/docs/adr"

# Not a build-memory repo → exit 2 (the two freshness detectors' "nothing to do" convention).
if [ ! -f "$BUILD/README.md" ] || ! grep -qF "$MARKER" "$BUILD/README.md" 2>/dev/null; then
  echo "check-build-memory: $REPO is not a build-memory repo (no docs/build/README.md marker '$MARKER')."
  printf '{"repo":"%s","buildMemory":false,"violations":[],"warnings":[]}\n' "$REPO" > "$JSON"
  exit 2
fi

VIOL="$(mktemp)"; WARN="$(mktemp)"
trap 'rm -f "$VIOL" "$WARN" 2>/dev/null' EXIT
viol() { printf '%s\t%s\n' "$1" "$2" >> "$VIOL"; }      # <check>\t<message>
warn() { printf '%s\t%s\n' "$1" "$2" >> "$WARN"; }
# Guarded rules warn without the guards marker and fail with it (BM-COMPAT-06).
GUARDS=0
grep -qE '^[[:space:]]*<!-- build-memory-guards: 1 -->[[:space:]]*$' "$BUILD/README.md" 2>/dev/null && GUARDS=1
guarded() { if [ "$GUARDS" -eq 1 ]; then viol "$1" "$2"; else warn "$1" "$2"; fi; }

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
  case "$ALLOWED" in *" $b "*) : ;; *) viol layout "docs/build/$b is not an allowed build-memory root entry" ;; esac
done
# logs/.gitignore present with the right contents (BM-LAYOUT-03).
if [ ! -f "$BUILD/logs/.gitignore" ]; then
  viol layout "docs/build/logs/.gitignore is missing (must contain '*' and '!.gitignore')"
else
  grep -qE '^\*$' "$BUILD/logs/.gitignore" || warn layout "docs/build/logs/.gitignore should contain a bare '*'"
  grep -qE '^!\.gitignore$' "$BUILD/logs/.gitignore" || warn layout "docs/build/logs/.gitignore should contain '!.gitignore'"
fi

# ── Parse the manifest chain table + companions ──────────────────────────────
CHAIN_FILES="$(mktemp)"     # one filename per chain-table row
COMPANIONS="$(mktemp)"
trap 'rm -f "$VIOL" "$WARN" "$CHAIN_FILES" "$COMPANIONS" 2>/dev/null' EXIT
REQ_PATTERN=""
if [ -f "$MANIFEST" ]; then
  # companions: line (comma-separated filenames).
  grep -m1 -iE '^[[:space:]]*companions:' "$MANIFEST" 2>/dev/null \
    | sed -E 's/^[^:]*:[[:space:]]*//' | tr ',' '\n' \
    | sed -E 's/[`[:space:]]//g' | grep -E '\.md$' >> "$COMPANIONS" || true
  # req_id_pattern: line.
  REQ_PATTERN="$(grep -m1 -iE '^[[:space:]]*req_id_pattern:' "$MANIFEST" 2>/dev/null | sed -E 's/^[^:]*:[[:space:]]*//; s/[`[:space:]]*$//; s/^`//')"
  # Chain rows: table lines inside the "## The chain" section that name a *.md file.
  awk '
    /^##[[:space:]]+The chain/ {inchain=1; next}
    inchain && /^##[[:space:]]/ {inchain=0}
    inchain && /^\|/ {print}
  ' "$MANIFEST" | grep -E '[A-Za-z0-9_.-]+\.md' | while IFS= read -r row; do
    printf '%s\n' "$row" | grep -oE '[0-9A-Za-z_.-]+\.md' | head -1
  done | sort -u >> "$CHAIN_FILES"
fi
# _TEMPLATE.md and DEFERRALS.md are always companions.
printf '%s\n' "_TEMPLATE.md" "DEFERRALS.md" >> "$COMPANIONS"
COMPANIONS_SORTED="$(sort -u "$COMPANIONS")"

is_companion() { printf '%s\n' "$COMPANIONS_SORTED" | grep -qxF "$1"; }
in_chain() { grep -qxF "$1" "$CHAIN_FILES"; }

# ── 2. Ticket files: grammar, unique sequence, marker+chain membership ───────
SEQ_KEYS="$(mktemp)"; ID_SEQ="$(mktemp)"
trap 'rm -f "$VIOL" "$WARN" "$CHAIN_FILES" "$COMPANIONS" "$SEQ_KEYS" "$ID_SEQ" 2>/dev/null' EXIT
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
      in_chain "$b" || viol manifest "ticket file $b has no row in the manifest chain table"
    else
      # Legacy filename allowed only if the chain table lists it.
      if in_chain "$b"; then
        id="$(printf '%s' "$b" | sed -E 's/__.*$//; s/^[0-9]*[a-z]?_?//; s/\.md$//')"
        num="$(printf '%s' "$b" | sed -E 's/^([0-9]+).*$/\1/')"
        case "$num" in ''|*[!0-9]*) num=0 ;; esac
        printf '%s\t%s\t%s\n' "$id" "$num" "$b" >> "$ID_SEQ"
      else
        viol filename "ticket file $b does not match the filename grammar and is not a listed chain row"
      fi
    fi
  done
  # duplicate ticket ids (the sequence invariant: no two ticket files declare the same id)
  if [ -s "$SEQ_KEYS" ]; then
    cut -f1 "$SEQ_KEYS" | sort | uniq -d | while IFS= read -r dup; do
      [ -n "$dup" ] && viol sequence "duplicate ticket id '$dup' (two ticket files declare the same id)"
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
      [ -f "$REPO/$cf" ] || viol manifest "manifest chain row names $cf but no such file exists in docs/tickets/"
    fi
  done < "$CHAIN_FILES"
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
        viol skeleton "skeleton ticket $b carries a Run: line (a skeleton must have no run line)"
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
          viol depends "ticket $b depends on $dep which lands later (forward dependency)"
        fi
      done
    ;; esac
  done
fi

# ── 5. DEFERRALS.md ids unique + valid statuses ──────────────────────────────
DEF="$TICKETS/DEFERRALS.md"
VALID_STATUS=" OPEN PARTIAL DONE WONTFIX ACCEPTED-SKELETON "
if [ -f "$DEF" ]; then
  DEF_IDS="$(mktemp)"
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
      viol deferrals "DEFERRALS row $id has an invalid (orphan) status '$shown'"
    fi
  done
  if [ -s "$DEF_IDS" ]; then
    sort "$DEF_IDS" | uniq -d | while IFS= read -r dup; do
      [ -n "$dup" ] && viol deferrals "duplicate DEFERRALS id '$dup'"
    done
  fi
  rm -f "$DEF_IDS" 2>/dev/null
  # P (human-prerequisite) rows still owed must be scheduled: owner: + trigger: in
  # `unblocked by` (DEFERRALS rule 5). Warning only in tree mode — failing rows ADDED under
  # the guards marker needs history mode (forward: SK-16). Header-aware: each table's own
  # `kind` / `unblocked by` columns are located from its `| id | … |` header row.
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
    [ -n "$pid" ] && warn deferrals "DEFERRALS row $pid (kind P, still owed) has no owner:/trigger: in 'unblocked by' (rule 5: human work is scheduled)"
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
          viol deferrals "an OPEN DEFERRALS row references $g whose readout says PASSED"
        fi
      fi
    done
  fi
fi

# ── 6. ADRs: index match + revisit trigger + spec appendix (when present) ────
if [ -d "$ADR" ]; then
  for a in "$ADR"/ADR-*.md; do
    [ -f "$a" ] || continue
    grep -qE '^##[[:space:]]+Revisit trigger' "$a" || viol adr "$(basename "$a") has no '## Revisit trigger' section"
  done
  if [ -f "$ADR/README.md" ]; then
    if [ -x "$SELF_DIR/adr-index.sh" ] || [ -f "$SELF_DIR/adr-index.sh" ]; then
      gen="$(mktemp)"
      bash "$SELF_DIR/adr-index.sh" --check "$ADR" > "$gen" 2>/dev/null
      if ! diff -q "$gen" "$ADR/README.md" >/dev/null 2>&1; then
        viol adr "docs/adr/README.md does not match a fresh adr-index regeneration (hand-edited or stale)"
      fi
      rm -f "$gen" 2>/dev/null
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
      warn adr "spec ADR appendix and docs/adr/ file set differ (BM-ADR-04)"
    fi
  fi
fi

# ── 7. LEDGER key order + nextTicket + PHASE LOG done coverage ───────────────
EXPECTED_KEYS="projectStatus nextTicket lastCompleted blockedOn pauseRequested returnPass manifest canonicalSpec memoryRoot dispatchTarget buildWorktree buildBranchBase pinnedBaseSha chainTip benchmarkSet autonomy mergePolicy round updatedAt"
# The optional `harness` key (BM-LEDGER-02) is accepted only in its slot, between round and updatedAt.
EXPECTED_KEYS_H="$(printf '%s' "$EXPECTED_KEYS" | sed -E 's/ round updatedAt$/ round harness updatedAt/')"
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
    viol ledger "LEDGER.md CURRENT STATE keys are missing or out of order (expected: $exp; optional 'harness' only between round and updatedAt)"
  fi
  nt="$(lval nextTicket)"
  if [ -n "$nt" ] && [ "$nt" != "DONE" ] && [ "$nt" != "SETUP" ]; then
    # must name a chain row — by exact id (ID_SEQ) or as the _<ID>__ segment of a chain filename.
    nt_re="$(printf '%s' "$nt" | sed 's/[.[\*^$]/\\&/g')"
    if [ -s "$ID_SEQ" ] && ! grep -qE "^${nt_re}$(printf '\t')" "$ID_SEQ" && ! grep -qE "_${nt_re}__" "$CHAIN_FILES"; then
      warn ledger "LEDGER nextTicket '$nt' does not name a known chain row or DONE"
    fi
  fi
  # PHASE LOG "done" tickets -> a BUILD_INDEX row + an evidence file (runs/<ID>.md or pr/<ID>.md)
  grep -E '^-[[:space:]]' "$LEDGER" | while IFS= read -r ln; do
    printf '%s' "$ln" | grep -qE '\bdone\b' || continue
    tid="$(printf '%s' "$ln" | sed -E "s/^-[[:space:]]*[0-9-]+[[:space:]]*—[[:space:]]*(${ID_RE}).*/\1/")"
    printf '%s' "$tid" | grep -qE "^${ID_RE}$" || continue
    tid_re="$(printf '%s' "$tid" | sed 's/[.[\*^$]/\\&/g')"
    # match the id as a whole table cell, not a substring (T1 must not be satisfied by a T12 row)
    if [ -f "$BUILD/BUILD_INDEX.md" ] && ! grep -qE "\|[[:space:]]*${tid_re}[[:space:]]*\|" "$BUILD/BUILD_INDEX.md"; then
      viol index "PHASE LOG marks $tid done but BUILD_INDEX.md has no row for it"
    fi
    if [ ! -f "$BUILD/runs/$tid.md" ] && [ ! -f "$BUILD/pr/$tid.md" ]; then
      viol index "PHASE LOG marks $tid done but neither docs/build/runs/$tid.md nor pr/$tid.md exists (no evidence file)"
    fi
  done
fi

# ── 7b. LEDGER budget + shape (BM-LEDGER-06/08, guarded) + tail/seed warnings ──
if [ -f "$LEDGER" ]; then
  # Orient region: line 1 up to (not including) the first "## OPEN FINDINGS" heading.
  head_b="$(LC_ALL=C awk '/^##[[:space:]]+OPEN FINDINGS/ {exit} {print}' "$LEDGER" | wc -c | tr -d ' ')"
  case "$head_b" in ''|*[!0-9]*) head_b=0 ;; esac
  if [ "$head_b" -gt 12288 ]; then
    guarded ledger-budget "LEDGER.md orient region (line 1 → ## OPEN FINDINGS) is $head_b B, over the 12 KiB budget (BM-LEDGER-08)"
  elif [ "$head_b" -gt 8192 ]; then
    warn ledger-budget "LEDGER.md orient region is $head_b B, above the 8 KiB warning level (budget 12 KiB, BM-LEDGER-08)"
  fi
  # CURRENT STATE: values only — each key line <= 256 B, no `| PRIOR` history.
  LC_ALL=C awk -v keys=" $EXPECTED_KEYS harness " '
    /^##[[:space:]]+CURRENT STATE/ {inblk=1; next}
    inblk && /^##[[:space:]]/ {inblk=0}
    inblk && /^[[:space:]]*[A-Za-z][A-Za-z0-9]*:([[:space:]]|$)/ {
      k=$0; sub(/^[[:space:]]*/,"",k); sub(/:.*/,"",k)
      if (index(keys, " " k " ")) print k "\t" length($0) "\t" ($0 ~ /\|[[:space:]]*\**PRIOR/ ? 1 : 0)
    }' "$LEDGER" | while IFS="$(printf '\t')" read -r k len prior; do
    [ -n "$k" ] || continue
    [ "$len" -gt 256 ] 2>/dev/null && guarded ledger-budget "LEDGER.md CURRENT STATE '$k' line is $len B (> 256 B; values only, BM-LEDGER-08)"
    [ "$prior" = "1" ] && guarded ledger-budget "LEDGER.md CURRENT STATE '$k' carries '| PRIOR' history (values only; git + PHASE LOG carry history, BM-LEDGER-08)"
  done
  # returnPass is a comma-separated id list (or "(none)").
  rp="$(lval returnPass)"
  case "$rp" in ''|'(none)'|none|'(nothing)') : ;; *)
    printf '%s' "$rp" | grep -qE "^${ID_RE}([[:space:]]*,[[:space:]]*${ID_RE})*$" \
      || guarded ledger-budget "LEDGER.md returnPass is not a comma-separated ticket-id list (BM-LEDGER-08)" ;;
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
    guarded ledger-budget "LEDGER.md: $(printf '%s' "$dupk" | cut -f1) line(s) outside CURRENT STATE begin with a CURRENT STATE key name (first: line $(printf '%s' "$dupk" | cut -f2)) (BM-LEDGER-08)"
  fi
  # One append target: the last "## " heading is a PHASE LOG heading (BM-LEDGER-06).
  last_h="$(grep -E '^##[[:space:]]' "$LEDGER" | tail -1)"
  if grep -qE '^##[[:space:]]+PHASE LOG' "$LEDGER"; then
    if ! printf '%s' "$last_h" | grep -qE '^##[[:space:]]+PHASE LOG([[:space:]]|$)' \
       || printf '%s' "$last_h" | grep -qE '^##[[:space:]]+PHASE LOG[[:space:]]+INDEX'; then
      guarded ledger-budget "LEDGER.md: the last region is '$last_h', not a PHASE LOG heading — new entries go only at the end of the file (BM-LEDGER-06)"
    fi
  fi
  # PHASE LOG entries <= 2 KiB: guarded in the last (current) PHASE LOG region; a warning in older regions.
  # Also counts the entries, for the seed check below.
  plog="$(LC_ALL=C awk '
    function flush() { if (cur && sz > 2048) { ov++; ovl[ov] = cur; ovr[ov] = region } cur = 0; sz = 0 }
    /^##[[:space:]]/ { flush(); inlog = ($0 ~ /^##[[:space:]]+PHASE LOG/ && $0 !~ /^##[[:space:]]+PHASE LOG[[:space:]]+INDEX/); if (inlog) region++; next }
    inlog && /^- / { flush(); cur = NR; sz = length($0) + 1; entries++; next }
    inlog && cur && /^[[:space:]]*$/ { flush(); next }
    inlog && cur { sz += length($0) + 1; next }
    END {
      flush()
      for (i = 1; i <= ov; i++) {
        if (ovr[i] == region) { nl++; if (nl <= 5) ll = ll " " ovl[i] } else { no++; if (no <= 5) lo = lo " " ovl[i] }
      }
      print entries + 0 "\t" nl + 0 "\t" ll "\t" no + 0 "\t" lo
    }' "$LEDGER")"
  pl_entries="$(printf '%s' "$plog" | cut -f1)"
  pl_nl="$(printf '%s' "$plog" | cut -f2)"; pl_no="$(printf '%s' "$plog" | cut -f4)"
  [ "${pl_nl:-0}" -gt 0 ] && guarded ledger-budget "LEDGER.md: $pl_nl PHASE LOG entr(y/ies) in the current region exceed 2 KiB (BM-LEDGER-06; lines:$(printf '%s' "$plog" | cut -f3))"
  [ "${pl_no:-0}" -gt 0 ] && warn ledger-budget "LEDGER.md: $pl_no PHASE LOG entr(y/ies) in older regions exceed 2 KiB (legacy; lines:$(printf '%s' "$plog" | cut -f5))"
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
    [ "${gd_rows:-0}" -gt 0 ] && warn gate "LEDGER.md is a seed (PHASE LOG holds only the seed entry) but GATE DECISIONS has $gd_rows non-pre-authorization row(s) — pre-answered gate?"
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
    [ "$ga_signed" -eq 1 ] || warn tail "projectStatus is DONE but docs/build/readouts/GATE-ACCEPT.md is missing or not signed (BM-TAIL-03)"
  fi
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
        printf '%s\n' "$spec_ids" | grep -qxF "$rid" || warn reqcov "ticket $b cites $rid which is not in the spec"
      done
    done
  fi
fi

# ── 9. size + secret checks ──────────────────────────────────────────────────
if [ -d "$BUILD" ]; then
  find "$BUILD" -type f ! -path '*/logs/*' 2>/dev/null | while IFS= read -r f; do
    sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
    case "$sz" in ''|*[!0-9]*) continue ;; esac
    [ "$sz" -gt 5242880 ] && warn size "$(printf '%s' "$f" | sed "s#$REPO/##") exceeds 5 MB"
    case "$f" in */fixtures/*) [ "$sz" -gt 1048576 ] && warn size "fixture $(printf '%s' "$f" | sed "s#$REPO/##") exceeds 1 MB" ;; esac
  done
fi
SECRET_RE='AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{36}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-'
for scan in "$BUILD" "$TICKETS"; do
  [ -d "$scan" ] || continue
  hits="$(grep -rlE "$SECRET_RE" "$scan" 2>/dev/null | grep -v '/logs/' || true)"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | while IFS= read -r h; do
      [ -n "$h" ] && viol secret "$(printf '%s' "$h" | sed "s#$REPO/##") contains a secret-shaped token"
    done
  fi
done

# ── Report + JSON ────────────────────────────────────────────────────────────
NV="$(wc -l < "$VIOL" | tr -d ' ')"; NW="$(wc -l < "$WARN" | tr -d ' ')"
{
  printf '{"repo":"%s","buildMemory":true,"guards":%s,"violations":[' "$REPO" "$([ "$GUARDS" -eq 1 ] && echo true || echo false)"
  first=1
  while IFS="$(printf '\t')" read -r c m; do
    [ -n "$c" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    em="$(printf '%s' "$m" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf '{"check":"%s","message":"%s"}' "$c" "$em"
  done < "$VIOL"
  printf '],"warnings":['
  first=1
  while IFS="$(printf '\t')" read -r c m; do
    [ -n "$c" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    em="$(printf '%s' "$m" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    printf '{"check":"%s","message":"%s"}' "$c" "$em"
  done < "$WARN"
  printf ']}\n'
} > "$JSON"

echo "check-build-memory: $REPO$([ "$GUARDS" -eq 1 ] && echo ' (guards marker: on)')"
if [ "$NV" -eq 0 ]; then
  echo "  ✓ no violations ($NW warning(s))"
else
  echo "  ✗ $NV violation(s), $NW warning(s):"
  sed -E 's/\t/: /' "$VIOL" | sed 's/^/    - /'
fi
[ "$NW" -gt 0 ] && sed -E 's/\t/: /' "$WARN" | sed 's/^/    ~ /'
echo "  JSON: $JSON"

[ "$NV" -eq 0 ] || exit 1
exit 0
