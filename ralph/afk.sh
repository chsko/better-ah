#!/usr/bin/env bash
# AFK: loop Ralph for N iterations, stopping early when no work is left.
# Usage: ralph/afk.sh 10
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

for ((i = 1; i <= $1; i++)); do
  echo "=== Ralph iteration $i/$1 ==="
  git pull --ff-only || true

  issues=$(gh issue list --state open --label ready-for-agent --limit 50 \
    --json number,title,body,labels,comments)
  progress=$(cat progress.txt 2>/dev/null || echo "(no progress yet)")

  result=$(claude -p --permission-mode acceptEdits \
    --allowedTools "Bash(git:*),Bash(gh:*),Bash(luacheck:*),Bash(busted:*),Edit,Write,Read,Glob,Grep" \
    "Open issues: $issues

progress.txt: $progress

$(cat ralph/prompt.md)")

  echo "$result"

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo "No unblocked ready-for-agent issues left after $i iterations."
    exit 0
  fi
done
