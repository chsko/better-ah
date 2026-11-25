#!/usr/bin/env bash
# Human-in-the-loop: run one Ralph iteration and watch it work.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

issues=$(gh issue list --state open --label ready-for-agent --limit 50 \
  --json number,title,body,labels,comments)
progress=$(cat progress.txt 2>/dev/null || echo "(no progress yet)")

claude --permission-mode acceptEdits \
  "Open issues: $issues

progress.txt: $progress

$(cat ralph/prompt.md)"
