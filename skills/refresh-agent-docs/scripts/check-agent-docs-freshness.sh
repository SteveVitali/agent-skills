#!/usr/bin/env bash
# check-agent-docs-freshness.sh — Detect stale agent documentation.
#
# Repo/language agnostic: works on any git repo containing AGENTS.md files
# and/or agent_docs/ directories.
#
# Usage:
#   check-agent-docs-freshness.sh [scope]
#
# Arguments:
#   scope — Directory path relative to repo root (default: "." for the whole repo)
#
# Checks:
#   1A. File references     — backticked file paths that no longer exist       (critical)
#   1B. Bazel targets       — //pkg:target references to missing package dirs  (critical, Bazel repos only)
#   1C. Key Files tables    — table rows naming files that no longer exist     (critical)
#   1D. Coverage gaps       — packages with ≥5 source files and no AGENTS.md   (minor)
#   1E. Line count drift    — documented ~N lines vs actual, >30% and >50 off  (moderate)
#
# Missing references are additionally classified with git history (the DOCER
# refinement): if the referenced file existed at the doc's last-modified
# commit, the reference "went stale" (code moved on); if it never existed
# there, it is likely an authoring error. Classification is best-effort and
# skipped outside git repos.
#
# Output:
#   Human-readable summary to stdout.
#   Machine-readable JSON to /tmp/agent-docs-freshness.json.
#
# Exit codes:
#   0 — No critical issues found
#   1 — Critical issues detected
#
# CI usage: the exit code makes this directly usable as a PR gate (e.g. a
# workflow step running this script on the changed scope). Drift research
# shows broken doc references sit unnoticed for years when checking is
# manual-only; wiring the structural check into CI catches them at change
# time. The LLM-driven refresh remains manual.
#
# Compatible with bash 3.2+ (macOS default).

set -o pipefail
set -f   # noglob: $EXCLUDES holds find patterns that must not shell-expand

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCOPE="${1:-.}"
if [ "$SCOPE" = "." ]; then
  SCOPE_ABS="$REPO_ROOT"
else
  SCOPE_ABS="$REPO_ROOT/$SCOPE"
fi
REPORT_FILE="/tmp/agent-docs-freshness.json"

# Extensions considered documentable/verifiable references.
REF_EXT="scala|ts|tsx|js|jsx|py|java|kt|kts|go|rb|rs|c|h|cc|cpp|hpp|cs|php|swift|sh|md|json|thrift|proto|bazel|yaml|yml|sql|tf"
# Extensions counted as "source files" for coverage / key-file / line-count checks.
SRC_EXT="scala|ts|tsx|js|jsx|py|java|kt|kts|go|rb|rs|cs|cpp|swift"

ISSUES_FILE=$(mktemp)
DOCS_FILE=$(mktemp)
FILE_INDEX=$(mktemp)
DIR_INDEX=$(mktemp)
trap 'rm -f "$ISSUES_FILE" "$DOCS_FILE" "$FILE_INDEX" "$DIR_INDEX" 2>/dev/null' EXIT

EXCLUDES='-not -path */node_modules/* -not -path */.git/* -not -path */target/* -not -path */build/* -not -path */dist/* -not -path */vendor/*'

# ─────────────────────────────────────────────────────────────────────────────
# Pre-build file index for fast lookups (avoids repeated find calls)
# ─────────────────────────────────────────────────────────────────────────────

echo "Building file index..." >&2
find "$SCOPE_ABS" -type f $EXCLUDES 2>/dev/null \
  | grep -E "\.(${REF_EXT})$" \
  | while IFS= read -r p; do echo "${p#$REPO_ROOT/}"; done | sort > "$FILE_INDEX"

# Also index cross-scope references: when docs reference files outside the
# scope, verify those too.
if [ "$SCOPE" != "." ]; then
  find "$REPO_ROOT" -type f $EXCLUDES -not -path "$SCOPE_ABS/*" 2>/dev/null \
    | grep -E "\.(${REF_EXT})$" \
    | while IFS= read -r p; do echo "${p#$REPO_ROOT/}"; done | sort >> "$FILE_INDEX"
fi

# Also index directory names for structure checks
find "$SCOPE_ABS" -type d $EXCLUDES 2>/dev/null \
  | while IFS= read -r p; do echo "${p#$REPO_ROOT/}"; done | sort > "$DIR_INDEX"

emit_issue() {
  local severity="$1" type="$2" doc="$3" line="$4" detail="$5" ref="$6"
  printf '{"severity":"%s","type":"%s","doc":"%s","line":%s,"detail":"%s","ref":"%s"}\n' \
    "$severity" "$type" "$doc" "${line:-0}" \
    "$(printf '%s' "$detail" | sed 's/"/\\"/g')" \
    "$(printf '%s' "$ref" | sed 's/"/\\"/g')" >> "$ISSUES_FILE"
}

# Check if a filename exists in the index (fast grep, no disk traversal)
file_exists_in_index() {
  local ref="$1"
  if [[ "$ref" == */* ]]; then
    grep -qF "$ref" "$FILE_INDEX" 2>/dev/null
  else
    grep -qF "/$ref" "$FILE_INDEX" 2>/dev/null || grep -qx "$ref" "$FILE_INDEX" 2>/dev/null
  fi
}

# ref_in_tree <ref> <tree_file> — does the reference match a path listed in a
# git ls-tree snapshot? Same matching semantics as file_exists_in_index.
ref_in_tree() {
  local ref="$1" tree_file="$2"
  [ -s "$tree_file" ] || return 1
  if [[ "$ref" == */* ]]; then
    grep -qF "$ref" "$tree_file" 2>/dev/null
  else
    grep -qF "/$ref" "$tree_file" 2>/dev/null || grep -qx "$ref" "$tree_file" 2>/dev/null
  fi
}

# doc_tree_snapshot <doc_rel> <out_file> — write the repo file listing as of
# the doc's last-modified commit to out_file (empty file = unavailable).
doc_tree_snapshot() {
  local doc_rel="$1" out_file="$2" doc_commit
  : > "$out_file"
  doc_commit=$(git -C "$REPO_ROOT" log -1 --format=%H -- "$doc_rel" 2>/dev/null)
  [ -n "$doc_commit" ] || return 0
  git -C "$REPO_ROOT" ls-tree -r --name-only "$doc_commit" > "$out_file" 2>/dev/null || : > "$out_file"
}

# classify_missing <ref> <tree_file> — echo a classification suffix for a
# missing reference, using the doc's last-modified tree snapshot.
classify_missing() {
  local ref="$1" tree_file="$2"
  if [ ! -s "$tree_file" ]; then
    echo ""
  elif ref_in_tree "$ref" "$tree_file"; then
    echo " [went stale: existed when the doc was last edited]"
  else
    echo " [authoring error: did not exist even when the doc was last edited]"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Find agent docs
# ─────────────────────────────────────────────────────────────────────────────

find "$SCOPE_ABS" -name "AGENTS.md" -not -path "*/node_modules/*" -not -path "*/.git/*" >> "$DOCS_FILE" 2>/dev/null || true
find "$SCOPE_ABS" -type d -name "agent_docs" -not -path "*/node_modules/*" 2>/dev/null | while read -r d; do
  find "$d" -name "*.md" >> "$DOCS_FILE" 2>/dev/null || true
done

DOCS_SCANNED=$(sort -u "$DOCS_FILE" | grep -c . | tr -d ' ')
sort -u "$DOCS_FILE" -o "$DOCS_FILE"

if [ "$DOCS_SCANNED" -eq 0 ]; then
  echo "No agent docs found within scope: $SCOPE"
  echo '{"scope":"'"$SCOPE"'","summary":{"docsScanned":0,"totalIssues":0},"issues":[]}' > "$REPORT_FILE"
  exit 0
fi

echo "Agent Docs Freshness Check — scope: $SCOPE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 1A: File Reference Checker (uses pre-built index)
# ─────────────────────────────────────────────────────────────────────────────

check_file_refs() {
  local doc="$1"
  local doc_rel="${doc#$REPO_ROOT/}"
  local tree_file
  tree_file=$(mktemp)
  doc_tree_snapshot "$doc_rel" "$tree_file"

  grep -noE '`[A-Za-z0-9_./-]+\.('"$REF_EXT"')`' "$doc" 2>/dev/null | while IFS=: read -r line_num match; do
    local ref="${match//\`/}"
    [ -z "$ref" ] && continue
    # Skip short bare names that are likely identifiers
    [[ "$ref" != */* ]] && [[ ${#ref} -lt 8 ]] && continue
    # Skip dotted package/module names (e.g., com.example.service) with no slash
    [[ "$ref" =~ ^[a-z]+\.[a-z]+\.[a-z] ]] && [[ "$ref" != */* ]] && continue
    # Skip template/placeholder patterns (e.g., <Entity>Repository.ext)
    [[ "$ref" == *"<"* ]] && continue

    if ! file_exists_in_index "$ref"; then
      emit_issue "critical" "missing_file_reference" "$doc_rel" "$line_num" \
        "References \`$ref\` which does not exist$(classify_missing "$ref" "$tree_file")" "$ref"
    fi
  done
  rm -f "$tree_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# 1B: Bazel Target Checker (only when the repo uses Bazel)
# ─────────────────────────────────────────────────────────────────────────────

HAS_BAZEL=false
{ [ -f "$REPO_ROOT/WORKSPACE" ] || [ -f "$REPO_ROOT/MODULE.bazel" ] || [ -f "$REPO_ROOT/WORKSPACE.bazel" ]; } && HAS_BAZEL=true

check_build_targets() {
  [ "$HAS_BAZEL" = true ] || return 0
  local doc="$1"
  local doc_rel="${doc#$REPO_ROOT/}"

  grep -noE '//[A-Za-z0-9_][A-Za-z0-9_./-]*:[A-Za-z0-9_.-]+' "$doc" 2>/dev/null | while IFS=: read -r line_num match; do
    local pkg_path="${match#//}"
    pkg_path="${pkg_path%%:*}"
    if ! grep -qE "(^|/)${pkg_path}$" "$DIR_INDEX" 2>/dev/null; then
      emit_issue "critical" "missing_build_target" "$doc_rel" "$line_num" \
        "Build target \`$match\` — package dir does not exist" "$match"
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# 1C: Key Files Table Checker
# ─────────────────────────────────────────────────────────────────────────────

check_key_files() {
  local doc="$1"
  local doc_rel="${doc#$REPO_ROOT/}"
  local tree_file
  tree_file=$(mktemp)
  doc_tree_snapshot "$doc_rel" "$tree_file"

  grep -nE '^\|.*`[A-Za-z0-9_.-]+\.('"$SRC_EXT"')`' "$doc" 2>/dev/null | while IFS=: read -r line_num content; do
    local filename
    filename=$(echo "$content" | grep -oE '`[A-Za-z0-9_.-]+\.('"$SRC_EXT"')`' | head -1 | tr -d '`')
    [ -z "$filename" ] && continue

    if ! file_exists_in_index "$filename"; then
      emit_issue "critical" "missing_key_file" "$doc_rel" "$line_num" \
        "Key Files references \`$filename\` — not found$(classify_missing "$filename" "$tree_file")" "$filename"
    fi
  done
  rm -f "$tree_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# 1D: Coverage Gap Finder
# ─────────────────────────────────────────────────────────────────────────────

check_coverage_gaps() {
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    local abs_dir="$REPO_ROOT/$dir"

    # Count source files directly in this directory
    local src_count
    src_count=$(grep -cE "^${dir}/[^/]+\.(${SRC_EXT})$" "$FILE_INDEX" 2>/dev/null || true)
    src_count="${src_count:-0}"
    [[ "$src_count" =~ ^[0-9]+$ ]] || src_count=0
    [ "$src_count" -lt 5 ] && continue

    # Walk up to find AGENTS.md
    local check_dir="$abs_dir"
    local has_docs=false
    while [[ "$check_dir" == "$SCOPE_ABS"* ]] || [ "$check_dir" = "$REPO_ROOT" ]; do
      if [ -f "$check_dir/AGENTS.md" ]; then
        has_docs=true
        break
      fi
      local parent
      parent="$(dirname "$check_dir")"
      [ "$parent" = "$check_dir" ] && break
      check_dir="$parent"
    done

    if [ "$has_docs" = false ]; then
      emit_issue "minor" "coverage_gap" "" "0" \
        "Package \`$dir/\` has $src_count source files but no AGENTS.md in hierarchy" "$dir"
    fi
  done < "$DIR_INDEX"
}

# ─────────────────────────────────────────────────────────────────────────────
# 1E: Line Count Drift
# ─────────────────────────────────────────────────────────────────────────────

check_line_counts() {
  local doc="$1"
  local doc_rel="${doc#$REPO_ROOT/}"

  grep -nE '^\|.*\.('"$SRC_EXT"').*\|.*~[0-9]' "$doc" 2>/dev/null | grep -i "line" | while IFS=: read -r line_num content; do
    local filename
    filename=$(echo "$content" | grep -oE '[A-Za-z0-9_.-]+\.('"$SRC_EXT"')' | head -1)
    [ -z "$filename" ] && continue

    local raw_count
    raw_count=$(echo "$content" | grep -oE '~[0-9]+\.?[0-9]*k?' | head -1)
    [ -z "$raw_count" ] && continue
    raw_count="${raw_count#\~}"

    local doc_lines=0
    if [[ "$raw_count" == *k ]]; then
      raw_count="${raw_count%k}"
      if [[ "$raw_count" == *.* ]]; then
        local whole="${raw_count%%.*}"
        local frac="${raw_count#*.}"
        doc_lines=$(( whole * 1000 + frac * 100 ))
      else
        doc_lines=$(( raw_count * 1000 ))
      fi
    else
      doc_lines="$raw_count"
    fi
    [ "$doc_lines" -lt 50 ] && continue

    # Find file from index
    local actual_path
    actual_path=$(grep -E "(^|/)${filename}$" "$FILE_INDEX" | head -1)
    [ -z "$actual_path" ] && continue

    local actual_lines
    actual_lines=$(wc -l < "$REPO_ROOT/$actual_path" | tr -d ' ')

    local threshold=$(( doc_lines * 30 / 100 ))
    local diff=$(( actual_lines - doc_lines ))
    [ $diff -lt 0 ] && diff=$(( -diff ))

    if [ $diff -gt $threshold ] && [ $diff -gt 50 ]; then
      emit_issue "moderate" "line_count_drift" "$doc_rel" "$line_num" \
        "\`$filename\` documented ~${doc_lines} lines, actual ${actual_lines}" "$filename"
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Execute all checks
# ─────────────────────────────────────────────────────────────────────────────

while IFS= read -r doc; do
  [ -z "$doc" ] && continue
  [ ! -f "$doc" ] && continue
  echo "  Scanning: ${doc#$REPO_ROOT/}"
  check_file_refs "$doc"
  check_build_targets "$doc"
  check_key_files "$doc"
  check_line_counts "$doc"
done < "$DOCS_FILE"

echo "  Checking coverage gaps..."
check_coverage_gaps
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Generate Report
# ─────────────────────────────────────────────────────────────────────────────

CRITICAL=$(grep -c '"critical"' "$ISSUES_FILE" 2>/dev/null) || CRITICAL=0
MODERATE=$(grep -c '"moderate"' "$ISSUES_FILE" 2>/dev/null) || MODERATE=0
MINOR=$(grep -c '"minor"' "$ISSUES_FILE" 2>/dev/null) || MINOR=0
TOTAL=$((CRITICAL + MODERATE + MINOR))

{
  printf '{\n  "scope": "%s",\n  "timestamp": "%s",\n' "$SCOPE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "summary": {"docsScanned":%d,"totalIssues":%d,"critical":%d,"moderate":%d,"minor":%d},\n' \
    "$DOCS_SCANNED" "$TOTAL" "$CRITICAL" "$MODERATE" "$MINOR"
  printf '  "issues": [\n'
  [ -s "$ISSUES_FILE" ] && sed '$ ! s/$/,/' "$ISSUES_FILE" | sed 's/^/    /'
  printf '  ]\n}\n'
} > "$REPORT_FILE"

# Print summary
echo "$DOCS_SCANNED docs scanned | $TOTAL issues found"
echo ""

if [ "$CRITICAL" -gt 0 ]; then
  echo "🔴 CRITICAL ($CRITICAL) — actively misleading agents"
  grep '"critical"' "$ISSUES_FILE" | head -10 | while IFS= read -r issue; do
    printf "   %s:%s  %s\n" \
      "$(echo "$issue" | sed 's/.*"doc":"\([^"]*\)".*/\1/')" \
      "$(echo "$issue" | sed 's/.*"line":\([0-9]*\).*/\1/')" \
      "$(echo "$issue" | sed 's/.*"detail":"\([^"]*\)".*/\1/')"
  done
  echo ""
fi

if [ "$MODERATE" -gt 0 ]; then
  echo "🟡 MODERATE ($MODERATE) — potentially stale"
  grep '"moderate"' "$ISSUES_FILE" | head -10 | while IFS= read -r issue; do
    printf "   %s:%s  %s\n" \
      "$(echo "$issue" | sed 's/.*"doc":"\([^"]*\)".*/\1/')" \
      "$(echo "$issue" | sed 's/.*"line":\([0-9]*\).*/\1/')" \
      "$(echo "$issue" | sed 's/.*"detail":"\([^"]*\)".*/\1/')"
  done
  echo ""
fi

if [ "$MINOR" -gt 0 ]; then
  echo "🟢 MINOR ($MINOR) — coverage gaps"
  grep '"minor"' "$ISSUES_FILE" | head -5 | while IFS= read -r issue; do
    printf "   %s\n" "$(echo "$issue" | sed 's/.*"detail":"\([^"]*\)".*/\1/')"
  done
  echo ""
fi

echo "Full report: $REPORT_FILE"

if [ "${CRITICAL:-0}" -gt 0 ]; then exit 1; else exit 0; fi
