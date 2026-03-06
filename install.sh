#!/bin/bash
# Install pdf-to-csv Claude Code skills to ~/.claude/skills/
# Usage: bash install.sh

SKILLS_DIR="$HOME/.claude/skills"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)/skills"

mkdir -p "$SKILLS_DIR"

for skill in pdf-to-csv-analyze pdf-to-csv-scaffold pdf-to-csv-parse pdf-to-csv-validate; do
    cp -r "$REPO_DIR/$skill" "$SKILLS_DIR/"
    echo "Installed: $skill"
done

echo ""
echo "Done. 4 skills installed to $SKILLS_DIR"
echo "Restart Claude Code to use them."
echo ""
echo "Workflow:"
echo "  /pdf-to-csv-analyze <pdf-path-or-url>"
echo "  /pdf-to-csv-scaffold <project-name> <pdf-url>"
echo "  /pdf-to-csv-parse <project-directory>"
echo "  /pdf-to-csv-validate <project-directory>"
