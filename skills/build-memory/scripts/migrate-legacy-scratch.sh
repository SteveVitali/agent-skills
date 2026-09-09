#!/usr/bin/env bash
# migrate-legacy-scratch.sh — move a legacy .agents/scratch/ into docs/build/. (BM-COMPAT-04.)
#
# MUTATING (with --apply): moves and renames files; drops logs; converts the machine
# ledger to docs/build/LEDGER.md by APPENDING three keys. It NEVER edits the contents
# of a moved file — moves and renames only — so each migrated run ledger / PR body /
# tool / fixture is byte-identical to its source. Dry-run by default.
#
# Usage:
#   migrate-legacy-scratch.sh --from <scratch_dir> [--to <docs/build>] [--apply]
#
#   --from    Legacy scratch dir (e.g. .agents/scratch or $AGENT_SCRATCH_DIR). Required.
#   --to      Destination memory root. Default: <repo>/docs/build.
#   --apply   Perform the migration. Without it, print the dry-run plan and exit.
#
# Mapping:
#   implement-spec_*.md (anywhere)      -> <to>/runs/<ID>.md   (ID from filename, else the
#                                          file's H1; unresolvable -> keep basename)
#   pr/*                                -> <to>/pr/            (basename kept)
#   tools/*                             -> <to>/tools/         (basename kept)
#   fixtures/*                          -> <to>/fixtures/      (basename kept)
#   planning/* (except the build ledger)-> <to>/planning/     (basename kept)
#   *build-ledger.md                    -> <to>/LEDGER.md      (converted: manifest/memoryRoot/round added)
#   *.log (anywhere)                    -> dropped
#   anything else                       -> left in place (reported as skipped)
#   The rename mapping is written into <to>/README.md (created with the v2 marker if absent).
#
# Output:
#   The plan (dry-run) or the applied mapping, to stdout.
#
# Exit codes:
#   0 — plan printed / migration applied
#   1 — usage error / --from does not exist
#
# Compatible with bash 3.2+ (macOS default). No associative arrays, no mapfile.

set -o pipefail

FROM="" ; TO="" ; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from)  FROM="${2:-}"; shift 2 ;;
    --to)    TO="${2:-}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    from=*)  FROM="${1#from=}"; shift ;;      # tolerate key=value style
    to=*)    TO="${1#to=}"; shift ;;
    apply=true)  APPLY=1; shift ;;
    apply=false) APPLY=0; shift ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "migrate-legacy-scratch.sh: unknown arg: $1 (try --help)" >&2; exit 1 ;;
  esac
done

[ -n "$FROM" ] && [ -d "$FROM" ] || { echo "migrate-legacy-scratch.sh: --from <existing dir> required" >&2; exit 1; }
FROM="$(cd "$FROM" && pwd -P)"    # physical path (macOS /private symlink)
REPO="$(git -C "$FROM" rev-parse --show-toplevel 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO="$(cd "$REPO" && pwd -P)"
[ -n "$TO" ] || TO="$REPO/docs/build"
MARKER='<!-- build-memory: v2 -->'

# ── ID resolver ──────────────────────────────────────────────────────────────
# Uppercase only the leading alpha run (macOS-safe; no GNU sed \U).
upfirst() {
  local s="$1" pre rest
  pre="$(printf '%s' "$s" | sed -E 's/^([A-Za-z]+).*$/\1/')"
  rest="${s#"$pre"}"
  printf '%s%s' "$(printf '%s' "$pre" | tr 'a-z' 'A-Z')" "$rest"
}
resolve_id() {
  local base="$1" f="$2" raw id
  raw="$base"; raw="${raw#implement-spec_}"; raw="${raw%.md}"
  raw="$(printf '%s' "$raw" | sed -E 's/_[0-9]{8}$//')"                    # strip trailing _YYYYMMDD
  id="$(printf '%s' "$raw" | grep -oE '^[A-Za-z]+[0-9]*\.[0-9]+[a-z]?' | head -1)"           # P19.2 / PRB.04
  [ -n "$id" ] || id="$(printf '%s' "$raw" | grep -oE '^[A-Za-z]+[0-9]+-[0-9]+[a-z]?' | head -1 | sed -E 's/-/./')"  # p20-3
  [ -n "$id" ] || id="$(printf '%s' "$raw" | grep -oE '[A-Za-z]+[0-9]+-[0-9]+[a-z]?' | head -1 | sed -E 's/-/./')"    # inside a branch name
  if [ -z "$id" ] && [ -f "$f" ]; then
    id="$(grep -m1 -E '^#[[:space:]]' "$f" | grep -oE '[A-Za-z]+[0-9]*\.[0-9]+[a-z]?' | head -1)"   # from the H1
  fi
  [ -n "$id" ] && id="$(upfirst "$id")"
  printf '%s' "$id"
}

PLAN="$(mktemp)"    # action<TAB>orig<TAB>dest
trap 'rm -f "$PLAN" 2>/dev/null' EXIT
rel() { printf '%s' "$1" | sed "s#^$REPO/##"; }

# ── Build the plan ───────────────────────────────────────────────────────────
BUILD_LEDGER=""
# 1. machine build ledger (first match) -> LEDGER.md
for cand in "$FROM"/*build-ledger.md "$FROM"/planning/*build-ledger.md; do
  [ -f "$cand" ] || continue
  BUILD_LEDGER="$cand"; break
done
[ -n "$BUILD_LEDGER" ] && printf 'convert\t%s\t%s\n' "$BUILD_LEDGER" "$TO/LEDGER.md" >> "$PLAN"

# 2. run ledgers: implement-spec_*.md anywhere under FROM
find "$FROM" -type f -name 'implement-spec_*.md' 2>/dev/null | sort | while IFS= read -r f; do
  base="$(basename "$f")"
  id="$(resolve_id "$base" "$f")"
  if [ -n "$id" ]; then dest="$TO/runs/$id.md"; else dest="$TO/runs/$base"; fi
  printf 'move\t%s\t%s\n' "$f" "$dest" >> "$PLAN"
done

# 3. pr / tools / fixtures subdirs -> same-named dirs (basename kept)
for sub in pr tools fixtures; do
  [ -d "$FROM/$sub" ] || continue
  find "$FROM/$sub" -type f ! -name '*.log' 2>/dev/null | sort | while IFS= read -r f; do
    printf 'move\t%s\t%s\n' "$f" "$TO/$sub/$(basename "$f")" >> "$PLAN"
  done
done

# 4. planning/* except the build ledger -> planning/
if [ -d "$FROM/planning" ]; then
  find "$FROM/planning" -type f ! -name '*.log' 2>/dev/null | sort | while IFS= read -r f; do
    [ "$f" = "$BUILD_LEDGER" ] && continue
    printf 'move\t%s\t%s\n' "$f" "$TO/planning/$(basename "$f")" >> "$PLAN"
  done
fi

# 5. logs -> dropped
find "$FROM" -type f -name '*.log' 2>/dev/null | sort | while IFS= read -r f; do
  printf 'drop\t%s\t(dropped: regenerable log)\n' "$f" >> "$PLAN"
done

# ── Dry-run: print the plan and stop ─────────────────────────────────────────
if [ "$APPLY" -ne 1 ]; then
  echo "migrate-legacy-scratch.sh — DRY RUN (pass --apply to perform)"
  echo "  from: $FROM"
  echo "  to:   $TO"
  echo "  plan:"
  if [ -s "$PLAN" ]; then
    while IFS="$(printf '\t')" read -r act orig dest; do
      printf '    %-7s %s  ->  %s\n' "$act" "$(rel "$orig")" "$(rel "$dest")"
    done < "$PLAN"
  else
    echo "    (nothing to migrate)"
  fi
  exit 0
fi

# ── Apply ────────────────────────────────────────────────────────────────────
mkdir -p "$TO" "$TO/runs" "$TO/logs"
[ -d "$FROM/pr" ] && mkdir -p "$TO/pr"
[ -d "$FROM/tools" ] && mkdir -p "$TO/tools"
[ -d "$FROM/fixtures" ] && mkdir -p "$TO/fixtures"
[ -d "$FROM/planning" ] && mkdir -p "$TO/planning"

# logs/.gitignore (BM-LAYOUT-03)
if [ ! -f "$TO/logs/.gitignore" ]; then
  printf '*\n!.gitignore\n' > "$TO/logs/.gitignore"
fi

# Ensure docs/build/README.md exists with the marker.
if [ ! -f "$TO/README.md" ]; then
  {
    printf '# Build memory\n\n'
    printf '%s\n\n' "$MARKER"
    printf 'The committed record of what happened during the build (see the layout contract in\n'
    printf 'skills/build-memory/layout.md). Migrated from a legacy agent scratch dir.\n'
  } > "$TO/README.md"
fi

MAP="$(mktemp)"; trap 'rm -f "$PLAN" "$MAP" 2>/dev/null' EXIT
while IFS="$(printf '\t')" read -r act orig dest; do
  [ -n "$act" ] || continue
  case "$act" in
    drop)
      rm -f "$orig"
      printf '| %s | (dropped) |\n' "$(rel "$orig")" >> "$MAP" ;;
    move)
      mkdir -p "$(dirname "$dest")"
      # collision-safe: if dest exists, keep the older-by-mtime under the plain name.
      if [ -e "$dest" ]; then
        if [ "$orig" -ot "$dest" ]; then
          mv -f "$dest" "${dest%.md}-dup1.md" 2>/dev/null || true
          printf '| (existing) | %s |\n' "$(rel "${dest%.md}-dup1.md")" >> "$MAP"
        else
          dest="${dest%.md}-dup1.md"
        fi
      fi
      mv "$orig" "$dest"
      printf '| %s | %s |\n' "$(rel "$orig")" "$(rel "$dest")" >> "$MAP" ;;
    convert)
      # copy the machine ledger verbatim, then APPEND the three keys inside CURRENT STATE.
      cp "$orig" "$dest"
      if grep -qE '^[[:space:]]*manifest:' "$dest"; then :; else
        # insert the added keys just after the projectStatus line (inside CURRENT STATE)
        tmp="$(mktemp)"
        awk '
          BEGIN{done=0}
          /^[[:space:]]*projectStatus:/ && !done {
            print
            print "manifest:        docs/tickets/00_MANIFEST.md   # added by migrate"
            print "memoryRoot:      docs/build                    # added by migrate"
            print "round:           2                             # added by migrate"
            done=1; next
          }
          {print}
        ' "$dest" > "$tmp" && cat "$tmp" > "$dest" && rm -f "$tmp"
      fi
      rm -f "$orig"
      printf '| %s | %s (converted) |\n' "$(rel "$orig")" "$(rel "$dest")" >> "$MAP" ;;
  esac
done < "$PLAN"

# Append the rename mapping into docs/build/README.md (append-only provenance).
{
  printf '\n## Migration rename mapping\n\n'
  printf 'Written by `build-memory migrate` on %s. Move/rename only; contents byte-identical.\n\n' "$(date +%Y-%m-%d)"
  printf '| original path | new path |\n|---|---|\n'
  sort "$MAP"
} >> "$TO/README.md"

echo "migrate-legacy-scratch.sh: applied. Mapping appended to $(rel "$TO/README.md")."
echo "  Review, then remove the now-empty legacy scratch dir if desired: $FROM"
exit 0
