#!/bin/bash
set -e

# Configuration
DEPLOY_BRANCH="deploy/apppaas"
SOURCE_DIR="app"
CURRENT_BRANCH=$(git branch --show-current)

echo "🚀 Preparing deployment branch '${DEPLOY_BRANCH}' from '${SOURCE_DIR}'..."

# Ensure clean state
if [ -n "$(git status --porcelain)" ]; then 
  echo "⚠️  You have uncommitted changes. Please commit or stash them first."
  exit 1
fi

# 1. Update branches
git fetch origin

# 2. Create/Reset deployment branch from current
# We use -B to force reset if it exists
git checkout -B $DEPLOY_BRANCH

echo "📂 Rearranging files..."

# 3. Remove everything except the SOURCE_DIR and .git
# usage of extglob for pattern matching exclusion
shopt -s extglob
rm -rf !($SOURCE_DIR|.git|.|..)

# 4. Move SOURCE_DIR content to root
# Move visible files
mv $SOURCE_DIR/* .
# Move hidden files (if any, suppress errors if none)
mv $SOURCE_DIR/.* . 2>/dev/null || true
# Remove empty dir
rmdir $SOURCE_DIR

echo "📦 Committing changes..."
# 5. Commit
git add -A
git commit -m "chore: release ${SOURCE_DIR} to root for AppPaaS"

# 6. Push
echo "Epushing to origin/${DEPLOY_BRANCH}..."
git push -f origin $DEPLOY_BRANCH

# 7. Cleanup
echo "🔙 Returning to ${CURRENT_BRANCH}..."
git checkout $CURRENT_BRANCH

echo "✅ AppPaaS deployment branch updated successfully!"
echo "Now go to AppPaaS console and select '${DEPLOY_BRANCH}' branch."
