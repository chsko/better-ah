# Ralph loop prompt

You are working AFK on this repository. GitHub issues are the task list.
The open issues, with their bodies and comments, are provided above.
progress.txt (if present) holds notes from earlier iterations.

1. Pick ONE issue to work on. Only consider open issues labelled
   `ready-for-agent`. Skip any issue whose "Blocked by" issues are still open.
   Prefer, in order: bugs, tracer-bullet foundations, then features. Use your judgement.
2. Read CLAUDE.md, then explore only the code the issue needs.
3. Implement it test-first where the logic is pure Lua (see CLAUDE.md "Testing").
4. Run the feedback loops: `luacheck .` and `busted`. Do not commit if either fails.
5. Commit with a message that ends with `Closes #<number>`, and push.
6. Close the issue with `gh issue close <number> --comment "<short summary of what was done>"`.
   If you could not finish, leave it open, comment what blocks it, and swap the
   `ready-for-agent` label for `ready-for-human`.
7. Append a short note to progress.txt: issue number, what you did, anything the
   next iteration should know.

ONLY WORK ON A SINGLE ISSUE.
If there are no open `ready-for-agent` issues that are unblocked, output <promise>COMPLETE</promise>.
