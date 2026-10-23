#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

DOTFILES_DIR="$HOME/dotfiles"

if [ ! -d "$DOTFILES_DIR" ]; then
    echo "Error: Directory $DOTFILES_DIR does not exist."
    exit 1
fi

cd "$DOTFILES_DIR"

echo "==> Re-stowing all packages..."
for dir in */; do
    dir_name="${dir%/}"
    
    # Skip hidden directories like .git
    if [[ "$dir_name" == .* ]]; then
        continue
    fi
    
    stow -R "$dir_name"
    echo "  [✓] Stowed: $dir_name"
done

# Check if there are any changes in the git workspace
if [ -z "$(git status --porcelain)" ]; then
    echo "==> No changes detected in Git repository. Everything is up to date."
    exit 0
fi

echo "==> Staging changed files..."
git add -A

# Use argument as commit message if provided, otherwise default to timestamp
COMMIT_MSG="${1:-Auto-sync: $(date '+%Y-%m-%d %H:%M:%S')}"

echo "==> Committing with message: \"$COMMIT_MSG\""
git commit -m "$COMMIT_MSG"

echo "==> Pushing changes to GitHub..."
git push

echo "==> Dotfiles successfully synced!"
