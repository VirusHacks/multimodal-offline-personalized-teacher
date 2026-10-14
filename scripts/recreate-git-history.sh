#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/recreate-git-history.sh [--reset]

Create a new main branch with ten dated milestone commits covering the last
ten calendar days. By default the script only works when .git does not exist.
Pass --reset to remove the existing .git directory before rebuilding history.

Optional environment variables:
  HISTORY_AUTHOR_NAME   Commit author name (default: current GitHub user)
  HISTORY_AUTHOR_EMAIL  Commit author email (default: current GitHub user)
  HISTORY_END_DATE      Last date in YYYY-MM-DD format (default: today)
EOF
}

reset_requested=false
case "${1:-}" in
  "") ;;
  --reset) reset_requested=true ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ -e .git ]]; then
  if [[ "$reset_requested" != true ]]; then
    echo "Refusing to overwrite existing Git metadata. Re-run with --reset." >&2
    exit 1
  fi
  rm -rf .git
fi

if [[ -n "${HISTORY_AUTHOR_NAME:-}" ]]; then
  author_name="$HISTORY_AUTHOR_NAME"
else
  author_name="$(git config --global user.name 2>/dev/null || true)"
fi

if [[ -n "${HISTORY_AUTHOR_EMAIL:-}" ]]; then
  author_email="$HISTORY_AUTHOR_EMAIL"
else
  author_email="$(git config --global user.email 2>/dev/null || true)"
fi

if [[ -z "$author_name" || -z "$author_email" ]]; then
  echo "Set HISTORY_AUTHOR_NAME and HISTORY_AUTHOR_EMAIL before running." >&2
  exit 1
fi

end_date="${HISTORY_END_DATE:-$(date +%Y-%m-%d)}"
if ! [[ "$end_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "HISTORY_END_DATE must use YYYY-MM-DD format." >&2
  exit 1
fi

date_for_offset() {
  local offset="$1"
  if date -v-"${offset}"d -j -f "%Y-%m-%d" "$end_date" "+%Y-%m-%d" >/dev/null 2>&1; then
    date -v-"${offset}"d -j -f "%Y-%m-%d" "$end_date" "+%Y-%m-%d"
  else
    date -d "$end_date - ${offset} days" "+%Y-%m-%d"
  fi
}

commit_milestone() {
  local offset="$1"
  local subject="$2"
  shift 2

  for path in "$@"; do
    if [[ -e "$path" ]]; then
      git add -- "$path"
    fi
  done

  if git diff --cached --quiet; then
    echo "No files staged for milestone: $subject" >&2
    exit 1
  fi

  local commit_date
  commit_date="$(date_for_offset "$offset")T12:00:00+0000"
  GIT_AUTHOR_DATE="$commit_date" \
  GIT_COMMITTER_DATE="$commit_date" \
    git commit -m "$subject" --author="$author_name <$author_email>"
}

git init -b main
git config user.name "$author_name"
git config user.email "$author_email"

commit_milestone 9 "chore: establish Next.js project foundation" \
  .dockerignore .gitignore .eslintrc.cjs components.json electron-builder.config.js \
  next.config.js package.json package-lock.json postcss.config.mjs tailwind.config.ts \
  tsconfig.json src/env.js src/middleware.ts

commit_milestone 8 "feat: add persistence and authentication foundation" \
  prisma src/server src/app/api/auth

commit_milestone 7 "feat: add application shell and presentation routes" \
  src/app/favicon.ico src/app/fonts src/app/globals.css src/app/layout.tsx \
  src/app/loading.tsx src/app/page.tsx src/app/presentation

commit_milestone 6 "feat: add presentation actions and AI API routes" \
  src/app/_actions src/app/api/ai src/app/api/presentation

commit_milestone 5 "feat: add presentation state, themes, and hooks" \
  src/hooks src/lib src/provider src/states

commit_milestone 4 "feat: add editor and presentation interface components" \
  src/components

commit_milestone 3 "feat: add Python AI and retrieval services" \
  backend
git add -f backend/training.ipynb
commit_date="$(date_for_offset 3)T12:00:00+0000"
GIT_AUTHOR_DATE="$commit_date" \
GIT_COMMITTER_DATE="$commit_date" \
  git commit --amend --no-edit

commit_milestone 2 "feat: add Electron desktop integration" \
  electron

commit_milestone 1 "docs: document setup and presentation workflows" \
  COMPARISON_TABLE.md ELECTRON_SETUP.md ELECTRON_SUMMARY.md README.md TODO.md \
  .github
git add -f assets/image-25a5ef03-b572-4eaf-9c41-cb0ca8245ad0.png
git add -A

commit_milestone 0 "test: add presentation generation coverage and finalize history" \
  tests scripts

echo
echo "Created $(git rev-list --count HEAD) commits on $(git branch --show-current)."
git --no-pager log --format='%h %ad %s' --date=short
