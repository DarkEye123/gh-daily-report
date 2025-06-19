# GitHub Daily Activity Report Generator

This tool generates a daily summary of your GitHub activities (PRs authored, reviewed, and commented on) with Linear ticket integration.

## Features

- Fetches PRs you authored on a specific date
- Fetches PRs you formally reviewed (excluding your own)
- Fetches PRs where you commented without formal review
- Automatically extracts Linear ticket IDs (CHE-XXXX) from branch names
- Formats output with Linear ticket links
- Copies formatted report to clipboard (macOS)
- Color-coded terminal output
- Deduplicates PRs (shows each PR only once even if you both reviewed and commented)

## Installation

1. Make sure you have the GitHub CLI (`gh`) installed and authenticated:
   ```bash
   gh auth status
   ```

2. Make the script executable:
   ```bash
   chmod +x github-daily-report.sh
   ```

3. (Optional) Add an alias to your shell configuration:
   ```bash
   alias daily-report='~/path/to/github-daily-report.sh'
   ```

## Usage

### Generate today's report:
```bash
./github-daily-report.sh
```

### Generate report for a specific date:
```bash
./github-daily-report.sh 2025-06-18
```

## Output Format

The script generates a report in the following format:

```markdown
## Daily GitHub Activity Summary
Date: 2025-06-19

### Implementation (Authored PRs)
- impl: [CHE-1234: Feature title](https://linear.app/ventrata/issue/CHE-1234)

### Code Reviews & Comments
- code-review: [CHE-5678: Fix title](https://linear.app/ventrata/issue/CHE-5678)
```

## How It Works

1. **PR Discovery**: Uses GitHub's search API and GraphQL to find:
   - PRs created by you on the specified date
   - PRs where you submitted formal reviews
   - PRs where you only left comments (without formal review)
   - Automatically deduplicates PRs where you both reviewed and commented

2. **Linear Integration**: 
   - Extracts Linear ticket IDs from PR branch names (format: `CHE-XXXX`)
   - Generates Linear issue URLs automatically
   - Falls back to PR title if no Linear ticket is found

3. **Output**:
   - Displays color-coded report in terminal
   - Shows breakdown of formal reviews vs comment-only interactions
   - Automatically copies markdown-formatted report to clipboard (macOS)

## Customization

### Adding Linear Ticket Titles

Currently, the script uses placeholder titles. To fetch actual Linear titles, you can:

1. Integrate with Linear's API directly
2. Use the Linear MCP (Model Context Protocol) integration if available
3. Manually update the `get_linear_title()` function with known ticket mappings

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

- [ ] Direct Linear API integration for fetching ticket titles
- [ ] Support for date ranges
- [ ] Export to different formats (JSON, CSV)
- [ ] Support for multiple issue tracker patterns
- [ ] Cross-platform clipboard support