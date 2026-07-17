#!/bin/bash
# check-repo-docs-freshness.sh — deterministic drift detector for human-facing
# repo docs (READ-ONLY)
# ---------------------------------------------------------------------------
# Usage: check-repo-docs-freshness.sh [scope]
#   scope: directory relative to the repo root (default: "."). Run from the
#   repo root.
#
# Scans README/docs/CHANGELOG-style files (*.md, *.rst, *.adoc), excluding
# agent docs (AGENTS.md, CLAUDE.md, agent_docs/, harness dirs). For each doc:
#   - broken references: markdown link targets (relative paths) that no
#     longer exist  -> CRITICAL
#   - stale suspects: referenced source files with commits newer than the
#     doc's own last commit -> SUSPECT (evidence of possible drift, not proof)
#
# Writes /tmp/repo-docs-freshness.json and prints a human summary.
# Exit codes: 0 = no critical issues, 1 = critical issues found, 2 = usage.
#
# Limitations: link extraction targets markdown inline syntax; .rst/.adoc
# files are scanned but their native link syntaxes are not parsed. Paths
# containing double quotes will break the JSON. Reference recency uses git
# commit times (fetch-depth-limited clones understate ages).
# ---------------------------------------------------------------------------
set -uo pipefail

SCOPE="${1:-.}"
OUT="${REPO_DOCS_FRESHNESS_OUT:-/tmp/repo-docs-freshness.json}"

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "ERROR: not a git repo" >&2; exit 2; }
[ -d "$SCOPE" ] || { echo "ERROR: scope dir not found: $SCOPE" >&2; exit 2; }

DOCS="$(find "$SCOPE" -type f \( -name '*.md' -o -name '*.rst' -o -name '*.adoc' \) \
  -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' \
  -not -path '*/target/*' -not -path '*/dist/*' -not -path '*/build/*' \
  -not -path '*/agent_docs/*' -not -path '*/.claude/*' -not -path '*/.windsurf/*' \
  -not -path '*/.cursor/*' -not -path '*/.agents/*' \
  -not -name 'AGENTS.md' -not -name 'CLAUDE.md' 2>/dev/null | sort)"

DOC_COUNT=0
CRITICAL_COUNT=0
SUSPECT_COUNT=0
ENTRIES=""

NOW="$(date +%s)"

for doc in $DOCS; do
  DOC_COUNT=$((DOC_COUNT + 1))
  doc_dir="$(dirname "$doc")"
  doc_time="$(git log -1 --format=%ct -- "$doc" 2>/dev/null || echo "")"

  broken=""
  newest_ref_time=0
  newest_ref=""

  # Extract markdown inline link/image targets: ](target)
  targets="$(grep -o '](\([^)]*\))' "$doc" 2>/dev/null | sed 's/^](//; s/)$//' | sort -u)"

  while IFS= read -r t; do
    [ -n "$t" ] || continue
    case "$t" in
      http://*|https://*|mailto:*|\#*|\"*|\`*) continue ;;
    esac
    # strip anchor fragments, angle brackets, and markdown title suffixes
    path="${t%%#*}"
    path="${path#<}"; path="${path%>}"
    path="${path%%[[:space:]]*}"
    [ -n "$path" ] || continue
    case "$path" in *\"*|*\`*|*'${'*) continue ;; esac
    # resolve: leading / = repo-root relative; else doc-relative
    case "$path" in
      /*) resolved=".${path}" ;;
      *)  resolved="${doc_dir}/${path}" ;;
    esac
    if [ ! -e "$resolved" ]; then
      esc_path="$(printf '%s' "$path" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      broken="${broken}${broken:+, }\"${esc_path}\""
      continue
    fi
    # recency of existing referenced source files (skip doc-type refs & dirs)
    case "$resolved" in
      *.md|*.rst|*.adoc) continue ;;
    esac
    [ -f "$resolved" ] || continue
    ref_time="$(git log -1 --format=%ct -- "$resolved" 2>/dev/null || echo "")"
    if [ -n "$ref_time" ] && [ "$ref_time" -gt "$newest_ref_time" ]; then
      newest_ref_time="$ref_time"
      newest_ref="$resolved"
    fi
  done <<EOF_TARGETS
$targets
EOF_TARGETS

  suspect="false"
  days_behind=0
  if [ -n "$doc_time" ] && [ "$newest_ref_time" -gt "$doc_time" ]; then
    suspect="true"
    days_behind=$(( (newest_ref_time - doc_time) / 86400 ))
    SUSPECT_COUNT=$((SUSPECT_COUNT + 1))
  fi

  n_broken=0
  if [ -n "$broken" ]; then
    n_broken="$(printf '%s' "$broken" | awk -F',' '{print NF}')"
    CRITICAL_COUNT=$((CRITICAL_COUNT + n_broken))
  fi

  if [ -n "$broken" ] || [ "$suspect" = "true" ]; then
    ENTRIES="${ENTRIES}${ENTRIES:+,}
    {\"path\": \"${doc}\", \"brokenRefs\": [${broken}], \"staleSuspect\": ${suspect}, \"daysBehind\": ${days_behind}, \"newestRef\": \"${newest_ref}\"}"
  fi
done

cat > "$OUT" <<EOF
{
  "scope": "${SCOPE}",
  "generatedAt": ${NOW},
  "docsScanned": ${DOC_COUNT},
  "criticalCount": ${CRITICAL_COUNT},
  "staleSuspectCount": ${SUSPECT_COUNT},
  "flagged": [${ENTRIES}
  ]
}
EOF

echo "Docs scanned:    ${DOC_COUNT}"
echo "Broken refs:     ${CRITICAL_COUNT} (critical)"
echo "Stale suspects:  ${SUSPECT_COUNT}"
echo "Report:          ${OUT}"

[ "$CRITICAL_COUNT" -eq 0 ] || exit 1
exit 0
