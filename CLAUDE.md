# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a GitHub Daily Activity Report Generator that creates summaries of PRs authored, reviewed, and commented on, with Linear ticket integration.

### Recent Major Refactoring (July 2025)

The script underwent significant refactoring to add:
1. **Deduplication Logic** - PRs mentioned in upper sections won't repeat in lower sections
2. **Enhanced Date Handling** - Supports Slovak format (DD-MM-YYYY), "today", "yesterday" keywords
3. **Working Day Calculations** - Defaults to previous working day, skips weekends
4. **Comprehensive Test Suite** - With mocked GitHub API responses

### Key Implementation Details

#### Deduplication System
- Uses string-based tracking (not associative arrays) for bash 3.x compatibility
- Tracks PR numbers, URLs, and branches with delimiter-based matching
- Cascading exclusion: Opened PRs → Code Reviews → Commits
- Initialize tracking strings with delimiters: `SEEN_PR_NUMBERS="|"`

#### Date Handling
- Date utilities in `lib/date-utils.sh`
- Supports formats: YYYY-MM-DD, DD-MM-YYYY, "today", "yesterday"
- Empty input defaults to previous working day
- Monday defaults to previous Friday
- Robust error handling for date command failures

#### Security Considerations
- Linear ticket IDs must be validated with regex `^CHE-[0-9]+$`
- All variables must be properly quoted
- Error messages should not expose sensitive information

## Truthfulness Framework

### What You MUST Do:

- Use Read/Grep/Glob tools to verify file existence before claiming they exist
- Copy exact code snippets from files, never paraphrase or recreate from memory
- Run commands to check actual state (git status, ls, etc.)
- Say "I need to check" or "I cannot verify" when uncertain
- Document exact error messages, not summaries
- Test commands before presenting them as solutions

### What You MUST NOT Do:

- Write "the file probably contains" or "it should have"
- Create example code that "would work" without testing
- Assume file locations or function names exist
- Hide failures or errors to appear competent
- Continue when core requirements are unclear
- Provide untested solutions

### Escalation Examples:

- "I found multiple implementations and need guidance on which approach to use"
- "The script is failing with this specific error: [exact error]"
- "I cannot find the file mentioned in the requirements"
- "Two approaches are possible, and I need a decision on direction"

## Code Review Process

When performing code reviews:
- **Check for HANDOVER.md** - If present at top level, read it first for additional context
- **Check Linear issues** - If Linear MCP server is set up, load any referenced Linear issues for context
- **Create summary** - Always create a detailed summary in `code-review.md` file
- **Key review areas**:
  - Shell script best practices and error handling
  - Security considerations (no exposed tokens/secrets)
  - Cross-platform compatibility issues
  - Performance for large data sets
  - Error messages clarity and user experience

### Processing Code Review Feedback

When instructed to process feedback from a code review:
- **Read code-review.md first** - This file is a requirement for code review feedback processing
- **Check for HANDOVER.md** - If present at top level, read it for additional context
- **Apply feedback systematically** - Address each point from the code review
- **Verify changes** - Ensure all feedback has been properly addressed
- **Test thoroughly** - Run the script with various inputs to verify fixes

### Self-Review Process (cloop)

When the self-review process is triggered:
- **Follow the state machine exactly** - Do not skip states or exit prematurely
- **Loop until approval** - Continue the review cycle until BOTH code reviewer and decision helper give APPROVED verdicts
- **Automatic progression** - After implementing fixes, automatically trigger the next review iteration without waiting for prompts
- **State transitions**:
  - After IMPLEMENT_SUGGESTIONS → UPDATE_ITERATION_SUMMARY → CHECK_COMPLETION
  - If either verdict is NEEDS_REVISION → Loop back to SPAWN_CODE_REVIEW
  - Only exit when both verdicts are APPROVED
- **Never create summary/conclusion** until the loop completes with approvals

## Code Style Guidelines

### Shell Scripts
- Use `set -e` for error handling
- Add descriptive comments for complex logic
- Use meaningful variable names
- Quote variables properly: `"$var"` not `$var`
- Check command availability before use
- Provide helpful error messages

### Comments Policy
- **Avoid unnecessary comments** - Code should be self-describing through good naming
- **No trivial comments** - Don't explain what code obviously does
- **When to comment**: Only for genuinely complex logic that isn't clear from the code itself
- **Before commenting**: Ask yourself if better naming or clearer code structure would eliminate the need

## Git Workflow

### Branch Naming Convention
- Format: `{type}/{description}` or `{type}/{ticket-id}/{description}`
- Valid types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`
- Keep descriptions short and descriptive

Examples:
- `feat/add-date-range-support`
- `fix/handle-empty-responses`
- `docs/improve-setup-instructions`

### Commit Messages
- Use conventional commits format
- Be specific about what changed and why
- Reference issues when applicable

## Development Best Practices

### Before Making Changes
1. Understand the current implementation
2. Test existing functionality
3. Identify edge cases
4. Plan the approach

### Testing Changes
1. Test with different date formats (YYYY-MM-DD, DD-MM-YYYY, "today", "yesterday")
2. Test with no activity days
3. Test with large result sets
4. Verify clipboard functionality
5. Check error handling
6. Test deduplication logic - ensure PRs don't repeat across sections
7. Test working day calculations (especially Monday → Friday)
8. Run the test suite: `./test-github-daily-report.sh`

### Compatibility Notes
- **Bash Version**: Must work with bash 3.x (macOS default)
- **No Associative Arrays**: Use string-based tracking instead
- **Date Commands**: Support both GNU date (Linux) and BSD date (macOS)
- **Variable Quoting**: Always quote variables to handle spaces and special characters

### Documentation
- Update README.md when adding features
- Include examples for new functionality
- Document any new dependencies
- Keep installation instructions current

## Common Tasks

### Adding New Features
1. Understand current architecture
2. Maintain backward compatibility
3. Follow existing patterns
4. Add appropriate error handling
5. Update documentation
6. Test thoroughly

### Debugging Issues
1. Add debug output (removable with a flag)
2. Check API rate limits
3. Verify authentication status
4. Test with minimal examples
5. Document findings

### Common Pitfalls
1. **Associative Arrays**: Don't use `declare -A` - it's not supported in bash 3.x
2. **Date Parsing**: Always check return codes from date commands
3. **String Matching**: Use delimiters to prevent substring matches (PR #12 vs #123)
4. **Clipboard Output**: Must also implement deduplication in clipboard section
5. **Test Execution**: Tests may hang if output isn't properly handled in subshells
6. **Linear API**: Always validate ticket IDs to prevent GraphQL injection

## Handover Strategy

When context limits are reached or switching between Claude instances:

1. **Create HANDOVER.md** at the root level
2. **Include specific information**:
   - Current task and its status
   - Files modified with specific changes
   - Commands run and their outputs
   - Any blockers or decisions needed
   - Next steps planned
3. **Update throughout session** - don't wait until the end
4. **Clear after completion** - remove HANDOVER.md when task is done

## Important Reminders

- Do what has been asked; nothing more, nothing less
- NEVER create files unless they're absolutely necessary
- ALWAYS prefer editing existing files to creating new ones
- NEVER proactively create documentation unless explicitly requested
- Test all changes before presenting them
- Be honest about limitations and uncertainties