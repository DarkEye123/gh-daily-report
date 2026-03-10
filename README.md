# GitHub Daily Activity Report Generator

This repository contains a Bash script that builds a daily GitHub activity summary from the GitHub CLI. It reports PRs you opened, PRs you reviewed or commented on, and commit or merge-resolution work tied to branches and Linear tickets.

## What It Does

- Collects PRs authored by the current authenticated GitHub user
- Collects PRs where the current user submitted a formal review
- Collects PRs where the current user only commented
- Collects commits authored by the current user within the report date range
- Falls back to merged PR commit history so resolved subtasks still appear after branch cleanup
- Deduplicates activity across sections so the same PR is not repeated unnecessarily
- Extracts `CHE-1234` style Linear ticket IDs from branch names, PR titles, commit headlines, and commit bodies
- Optionally fetches Linear issue titles when `LINEAR_API_KEY` is set
- Copies the markdown report to the macOS clipboard when `pbcopy` is available

## Requirements

- `bash`
- `gh`
- `jq`
- `curl`
- `pbcopy` for clipboard copy on macOS only

The script expects `gh` to already be authenticated:

```bash
gh auth status
```

## Installation

Make the script executable:

```bash
chmod +x github-daily-report.sh
```

Optional shell alias:

```bash
alias daily-report='/absolute/path/to/github-daily-report.sh'
```

## Usage

Run with no arguments to generate a report for the previous working day:

```bash
./github-daily-report.sh
```

Run for a specific day:

```bash
./github-daily-report.sh 2025-06-18
```

Accepted date inputs:

- `YYYY-MM-DD`
- `DD-MM-YYYY`
- `today`
- `yesterday`

Examples:

```bash
./github-daily-report.sh 18-06-2025
./github-daily-report.sh today
./github-daily-report.sh yesterday
```

## Date Behavior

- No argument defaults to the previous working day
- Monday defaults to the previous Friday
- Sunday also resolves back to Friday for the default previous-working-day calculation
- If the requested date is Friday, Saturday, or Sunday, the report range expands to start on Friday and include the weekend
- Weekend expansion is capped to the current day so the script does not search future dates

Examples:

- Running with no argument on Monday reports Friday
- Running with `2026-01-16` on or after Sunday covers `2026-01-16` through `2026-01-18`
- Running with `2026-01-17` on Saturday covers `2026-01-16` through `2026-01-17`

## Configuration

### `GITHUB_REPOS`

Space-separated repository list. If unset, the script uses:

- `ventrata/checkout-frontend`
- `ventrata/web-builder`
- `ventrata/FE-interview-v1`
- `ventrata/FE-interview-questions`

Example:

```bash
export GITHUB_REPOS="owner/repo1 owner/repo2"
./github-daily-report.sh
```

### `LOOKBACK_DAYS`

How far back to search for candidate reviewed or commented PRs before filtering them to the target date range. Default: `3`.

```bash
export LOOKBACK_DAYS=7
./github-daily-report.sh 2025-06-18
```

### `LINEAR_API_KEY`

If set, the script queries the Linear GraphQL API for issue titles. Ticket IDs must match `^CHE-[0-9]+$`.

```bash
export LINEAR_API_KEY="your-linear-api-key"
./github-daily-report.sh
```

## Output Structure

The generated markdown report can contain up to three sections:

- `### Opened PRs`
- `### Code Reviews & Comments`
- `### Commits, Merges, Resolutions`

Typical output:

```markdown
## Daily GitHub Activity Summary
Date: 2025-07-01

### Opened PRs
- [CHE-123](https://linear.app/ventrata/issue/CHE-123) - feat: add new feature [PR #123](https://github.com/test/repo/pull/123)

### Code Reviews & Comments
- [PR #125: chore: update deps](https://github.com/test/repo/pull/125) by @otheruser

### Commits, Merges, Resolutions
- [CHE-1961](https://linear.app/ventrata/issue/CHE-1961) - development on `feature/main-task` (also: [CHE-123](https://linear.app/ventrata/issue/CHE-123)) [PR #124](https://github.com/test/repo/pull/124)
```

When Linear titles are available, the ticket portion is prefixed with the Linear issue title instead of only the ticket ID.

## Deduplication Rules

- PRs shown under `Opened PRs` are not repeated under `Code Reviews & Comments`
- Branch-linked commit summaries are skipped when that same branch or PR context already appeared earlier
- Commit entries are still kept when a commit message introduces an additional Linear ticket not already represented by the PR or branch

## Commit and Merge Resolution Behavior

The commits section is branch-oriented rather than commit-oriented when branch context exists.

- Daily commits are grouped by branch
- Associated PR information is attached when available
- Multiple discovered Linear tickets are merged into a single branch summary
- If a merged PR contains historical commits authored by you, those commits can still appear as a "merged PR resolution" even if they were not authored on the target date and even if the source branch is gone

This fallback is what preserves resolved subtasks from merged work.

## Testing

Run the test suite with:

```bash
./test-github-daily-report.sh
```

## Notes

- The script uses `gh api user` to identify the current GitHub user
- There is no built-in `--help` flag
- Clipboard copy happens only when `pbcopy` is installed and the report is non-empty
- Linear links are generated against `https://linear.app/ventrata/issue/<ticket-id>`
