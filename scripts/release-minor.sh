#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Commit pending changes before creating the release commit and tag.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes before releasing." >&2
  exit 1
fi

npm version minor --tag-version-prefix=v -m "Release %s"
TAG="v$(node -p "require('./package.json').version")"

git push origin HEAD
git push origin "$TAG"
