#!/bin/bash
# Report exclusion pattern leaks as a GitHub Pull Request
# Usage: ./scripts/report-leak.sh [project_path] [top_n]
#
# Prerequisites:
#   - gh CLI installed and authenticated
#   - jq installed
#
# This script:
#   1. Clones/uses idris2-coverage repo
#   2. Detects leaks in high_impact_targets
#   3. Creates a branch with the leak report
#   4. Opens a PR to the main repo

set -e

UPSTREAM_REPO="shogochiai/idris2-coverage"
PROJECT=${1:-.}
TOP=${2:-1000}

echo "=== idris2-coverage Leak Reporter ==="
echo ""

# Check prerequisites
if ! command -v gh &> /dev/null; then
  echo "ERROR: 'gh' CLI not found. Install it: https://cli.github.com/"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "ERROR: 'jq' not found. Install it: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  echo "ERROR: Not authenticated with GitHub. Run: gh auth login"
  exit 1
fi

# Determine repo location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if we're in the idris2-coverage repo
if [ -f "$REPO_ROOT/idris2-coverage.ipkg" ]; then
  echo "Using local repo: $REPO_ROOT"
  WORK_DIR="$REPO_ROOT"
else
  # Not in repo - need to clone
  echo "Not running from idris2-coverage repo."
  echo ""
  echo "Where should I clone idris2-coverage?"
  echo "  (Will create 'idris2-coverage' subdirectory)"
  echo ""
  read -p "Clone location [~/src]: " CLONE_BASE
  CLONE_BASE=${CLONE_BASE:-~/src}
  CLONE_BASE="${CLONE_BASE/#\~/$HOME}"  # Expand ~

  WORK_DIR="$CLONE_BASE/idris2-coverage"

  if [ -d "$WORK_DIR" ]; then
    echo "Found existing clone at $WORK_DIR"
  else
    echo "Forking and cloning..."
    mkdir -p "$CLONE_BASE"
    cd "$CLONE_BASE"

    # Fork if not already forked
    gh repo fork "$UPSTREAM_REPO" --clone=true || {
      # If fork exists, just clone it
      GITHUB_USER=$(gh api user -q .login)
      gh repo clone "$GITHUB_USER/idris2-coverage" || {
        echo "ERROR: Could not fork/clone repo"
        exit 1
      }
    }
  fi

  echo "Working directory: $WORK_DIR"
fi

cd "$WORK_DIR"

# Make sure we're on main and up to date
git checkout main 2>/dev/null || git checkout master 2>/dev/null
git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || true

# Build if needed
if [ ! -f "./build/exec/idris2-cov" ]; then
  echo "Building idris2-cov..."
  idris2 --build idris2-coverage.ipkg
fi

IDRIS2_VERSION=$(idris2 --version 2>/dev/null | head -1 || echo "unknown")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BRANCH_NAME="leak-report-$TIMESTAMP"

echo ""
echo "Project: $PROJECT"
echo "Idris2: $IDRIS2_VERSION"
echo ""

# Convert PROJECT to absolute path if relative
if [[ "$PROJECT" != /* ]]; then
  PROJECT="$(cd "$OLDPWD" 2>/dev/null && cd "$PROJECT" && pwd)" || {
    echo "ERROR: Cannot find project: $PROJECT"
    exit 1
  }
fi

# Run analysis and capture only JSON
JSON_OUTPUT=$(./build/exec/idris2-cov --json --top $TOP "$PROJECT" 2>&1 | \
  sed -n '/^{/,$p')

if [ -z "$JSON_OUTPUT" ]; then
  echo "ERROR: No JSON output from idris2-cov"
  exit 2
fi

# Extract leaks
LEAKS=$(echo "$JSON_OUTPUT" | \
  jq -r '.high_impact_targets[].funcName' 2>/dev/null | \
  grep -E '^(\{|_builtin\.|prim__|Prelude\.|Data\.|System\.|Control\.|Decidable\.|Language\.|Debug\.)' | \
  sort -u)

if [ -z "$LEAKS" ]; then
  echo "No leaks detected. Nothing to report."
  exit 0
fi

LEAK_COUNT=$(echo "$LEAKS" | wc -l | tr -d ' ')
echo "Found $LEAK_COUNT potential leaks:"
echo "$LEAKS" | while read func; do
  echo "  - $func"
done
echo ""

# Generate LLM prompt for analysis
LLM_PROMPT=$(cat <<PROMPT_EOF
I'm using idris2-coverage to analyze my Idris2 project, and the following functions appeared in \`high_impact_targets\` but look like they should be excluded (stdlib, compiler-generated, or dependency code):

\`\`\`
$LEAKS
\`\`\`

**Idris2 version**: $IDRIS2_VERSION

Please help me categorize these:

1. **Standard Library** (Prelude.*, Data.*, System.*, Control.*, etc.)
   - These are from Idris2's base/contrib packages

2. **Compiler-Generated** ({csegen:N}, {eta:N}, _builtin.*, prim__*)
   - Machine names from optimization passes

3. **Type Constructors** (names ending with '.')
   - Auto-generated ADT case trees

4. **False Positives** (actually user code that looks like stdlib)
   - Should NOT be excluded

For each function, tell me:
- Category (1-4 above)
- If it's a new pattern, what exclusion rule should be added to idris2-coverage

Format your response as a checklist I can use for the PR.
PROMPT_EOF
)

echo "=========================================="
echo "  STEP 1: Verify these are actual leaks"
echo "=========================================="
echo ""
echo "Not sure if these are leaks? Copy this prompt to Claude/ChatGPT:"
echo ""
echo "--- COPY FROM HERE ---"
echo "$LLM_PROMPT"
echo "--- COPY TO HERE ---"
echo ""
echo "The LLM will help you categorize each function."
echo ""

# Confirm with user
read -p "Continue to create PR? (y=yes, n=no, c=copy prompt to clipboard) " -n 1 -r
echo
if [[ $REPLY =~ ^[Cc]$ ]]; then
  # Try to copy to clipboard
  if command -v pbcopy &> /dev/null; then
    echo "$LLM_PROMPT" | pbcopy
    echo "Copied to clipboard! Paste into Claude/ChatGPT."
  elif command -v xclip &> /dev/null; then
    echo "$LLM_PROMPT" | xclip -selection clipboard
    echo "Copied to clipboard! Paste into Claude/ChatGPT."
  else
    echo "Clipboard not available. Please copy manually."
  fi
  echo ""
  read -p "After reviewing, create PR? [y/N] " -n 1 -r
  echo
fi

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# Create branch
echo "Creating branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME"

# Generate leak report file
REPORT_FILE="leak-reports/$TIMESTAMP.md"
mkdir -p leak-reports

cat > "$REPORT_FILE" << EOF
# Leak Report: $TIMESTAMP

## Environment
- **Idris2 Version**: $IDRIS2_VERSION
- **Project Analyzed**: $(basename "$PROJECT")
- **Date**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Detected Leaks

The following functions appeared in \`high_impact_targets\` but should be excluded:

\`\`\`
$LEAKS
\`\`\`

## Suggested Actions

These patterns should be added to \`src/Coverage/DumpcasesParser.idr\`:

### New Compiler-Generated Patterns
$(echo "$LEAKS" | grep -E '^\{' | sed 's/^/- `/' | sed 's/$/`/' || echo "(none)")

### New Standard Library Modules
$(echo "$LEAKS" | grep -E '^(Prelude\.|Data\.|System\.|Control\.|Decidable\.|Language\.|Debug\.)' | sed 's/\..*/\./' | sort -u | sed 's/^/- `/' | sed 's/$/`/' || echo "(none)")

### New Builtin/Primitive Patterns
$(echo "$LEAKS" | grep -E '^(_builtin\.|prim__)' | sed 's/^/- `/' | sed 's/$/`/' || echo "(none)")

---
*Generated by \`scripts/report-leak.sh\`*
EOF

echo "Generated report: $REPORT_FILE"

# Commit
git add "$REPORT_FILE"
git commit -m "$(cat <<EOF
leak-report: $LEAK_COUNT patterns found with Idris2 $IDRIS2_VERSION

Detected exclusion pattern leaks that need to be added to
src/Coverage/DumpcasesParser.idr

See $REPORT_FILE for details.
EOF
)"

# Push and create PR
echo "Pushing branch..."
git push -u origin "$BRANCH_NAME"

echo "Creating Pull Request..."
gh pr create \
  --repo "$UPSTREAM_REPO" \
  --title "Leak Report: $LEAK_COUNT patterns (Idris2 $IDRIS2_VERSION)" \
  --body "$(cat <<EOF
## Summary

Detected **$LEAK_COUNT exclusion pattern leaks** when analyzing with Idris2 $IDRIS2_VERSION.

These functions appeared in \`high_impact_targets\` but should be filtered out.

## Leaks Found

\`\`\`
$LEAKS
\`\`\`

## LLM Analysis (Optional)

If you used Claude/ChatGPT to categorize these, paste the analysis here:

<!-- PASTE LLM ANALYSIS HERE -->

## How to Fix

Add the new patterns to \`src/Coverage/DumpcasesParser.idr\`:
- For \`{xyz:N}\` patterns: add to \`isCompilerGenerated\`
- For \`Prelude.*\` etc: add to \`isStandardLibraryFunction\`
- For \`prim__*\`: add to \`isCompilerGenerated\`

See [$REPORT_FILE]($REPORT_FILE) for categorized suggestions.

---
*Generated by \`scripts/report-leak.sh\`*
*Tip: Use the LLM prompt from the script to help categorize leaks*
EOF
)"

echo ""
echo "Done! PR created."
echo ""
echo "Return to main branch:"
echo "  cd $WORK_DIR && git checkout main"
