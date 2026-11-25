# Issue tracker

- Tracker: GitHub Issues on `chsko/better-ah`, using the `gh` CLI.
- Work is closed by a commit on `main` containing `Closes #<n>`, plus `gh issue close` with a summary comment.
- Blocking: use GitHub's native "blocked by" relationship where available, and always also write a
  `## Blocked by` section listing `#n` in the issue body.
- Specs are issues labelled `spec`. Tickets reference their spec with `Part of #<spec>`.
- External pull requests are not a request surface.

## Triage labels

| Role            | Label             |
|-----------------|-------------------|
| bug             | `bug`             |
| enhancement     | `enhancement`     |
| needs-triage    | `needs-triage`    |
| needs-info      | `needs-info`      |
| ready-for-agent | `ready-for-agent` |
| ready-for-human | `ready-for-human` |
| wontfix         | `wontfix`         |

Extra labels: `spec` (a spec issue, never picked by the loop), `spike` (research, output is a doc or comment).
