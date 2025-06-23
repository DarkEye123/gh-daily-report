# GitHub Daily Activity Report Generator

This tool generates a daily summary of your GitHub activities (PRs authored, reviewed, commented on, and commits made) with Linear ticket integration.

## Features

- Fetches PRs you authored on a specific date
- Fetches PRs you formally reviewed (excluding your own)
- Fetches PRs where you commented without formal review
- Tracks commits you made on the specified date (even without PRs)
- Automatically extracts Linear ticket IDs (CHE-XXXX) from branch names and commit messages
- Fetches Linear task titles when LINEAR_API_KEY is set
- Formats output with Linear ticket links and task titles
- Copies formatted report to clipboard (macOS)
- Color-coded terminal output
- Deduplicates PRs (shows each PR only once even if you both reviewed and commented)

## Installation

1. Make sure you have the GitHub CLI (`gh`) installed and authenticated:
   ```bash
   gh auth status
   ```
~`
2. Make the script executable:
   ```bash
chmod +x github-daily-report.sh
   ```

3. (Optional) Add an alias to your shell configuration:
   ```bash
   alias daily-report='~/path/to/github-daily-report.sh'
   ```

## Configuration

The script can be configured using environment variables:

### Repository Filtering
By default, the script searches only specific repositories to improve performance:
- `ventrata/checkout-frontend`
- `ventrata/web-builder`
- `ventrata/FE-interview-v1`
- `ventrata/FE-interview-questions`

To customize the repositories:
```bash
export GITHUB_REPOS="owner/repo1 owner/repo2 owner/repo3"
./github-daily-report.sh
```

### Lookback Period
The script looks back 3 days by default when searching for reviewed/commented PRs. To change this:
```bash
export LOOKBACK_DAYS=7
./github-daily-report.sh
```

### Linear API Integration
To fetch actual Linear task titles, set your Linear API key:
```bash
export LINEAR_API_KEY="your-linear-api-key"
./github-daily-report.sh
```

You can get your Linear API key from: https://linear.app/settings/api

## Usage

### Generate today's report:
```bash
./github-daily-report.sh
```

### Generate report for a specific date:
```bash
./github-daily-report.sh 2025-06-18
```

### With custom configuration:
```bash
GITHUB_REPOS="myorg/repo1 myorg/repo2" LOOKBACK_DAYS=5 ./github-daily-report.sh
```

## Output Format

The script generates a report in the following format:

```markdown
## Daily GitHub Activity Summary
Date: 2025-06-19

### Implementation (Authored PRs)
- impl: Implement checkout flow [CHE-1234](https://linear.app/ventrata/issue/CHE-1234) - Add new checkout feature [PR #123](https://github.com/org/repo/pull/123)

### Code Reviews & Comments
- code-review: Fix cart calculation [CHE-5678](https://linear.app/ventrata/issue/CHE-5678) - Fix cart total bug [PR #456](https://github.com/org/repo/pull/456)

### Commits
- commit: Update cart logic [CHE-1661](https://linear.app/ventrata/issue/CHE-1661) - fix: revert cart-recovery deletion [PR #2452](https://github.com/org/repo/pull/2452)
```

When LINEAR_API_KEY is not set, Linear ticket IDs are shown without titles:
```markdown
- impl: [CHE-1234](https://linear.app/ventrata/issue/CHE-1234) - Add new checkout feature [PR #123](https://github.com/org/repo/pull/123)
```

## How It Works

1. **Activity Discovery**: Uses GitHub's search API and GraphQL to find:
   - PRs created by you on the specified date
   - PRs where you submitted formal reviews
   - PRs where you only left comments (without formal review)
   - Commits you made on the specified date across all branches
   - Automatically deduplicates PRs where you both reviewed and commented

2. **Linear Integration**: 
   - Extracts Linear ticket IDs from PR branch names and commit messages (format: `CHE-XXXX`)
   - Fetches actual task titles from Linear API when LINEAR_API_KEY is set
   - Generates Linear issue URLs automatically
   - Falls back to showing just ticket ID if no API key is provided

3. **Output**:
   - Displays color-coded report in terminal
   - Shows breakdown of formal reviews vs comment-only interactions
   - Groups commits by their associated PRs
   - Automatically copies markdown-formatted report to clipboard (macOS)

## Customization

### Adding Linear Ticket Titles

The script can fetch actual Linear task titles by setting the LINEAR_API_KEY environment variable. This will show the full task title alongside the ticket ID in the report.

### Extending for Other Issue Trackers

The script can be adapted for other issue tracking systems by:
1. Modifying the `extract_linear_ticket()` function regex pattern
2. Updating the URL generation in the `process_pr()` function
3. Adapting the `get_linear_title()` function for your issue tracker's API

## Requirements

- `gh` (GitHub CLI) - authenticated with appropriate permissions
- `jq` - for JSON processing
- `bash` - shell environment
- `pbcopy` (optional) - for clipboard support on macOS

## Troubleshooting

1. **No PRs found**: Check the date format (YYYY-MM-DD) and ensure you have activity on that date
2. **Authentication errors**: Run `gh auth status` and re-authenticate if needed
3. **Missing branch names**: Some older PRs might not have branch information available

## Future Enhancements

- [x] Direct Linear API integration for fetching ticket titles
- [x] Track commits made on the specified date
- [ ] Support for date ranges
- [ ] Export to different formats (JSON, CSV)
- [ ] Support for multiple issue tracker patterns
- [ ] Cross-platform clipboard support
- [ ] Cache Linear ticket titles to reduce API calls