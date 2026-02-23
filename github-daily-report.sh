#!/bin/bash

# GitHub Daily Activity Report Generator with Comments Support
# Generates a summary of PRs authored, reviewed, and commented on with Linear ticket links

set -e

# Source date utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/date-utils.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse date argument (default to previous working day)
RAW_DATE="${1:-}"
DATE=$(parse_date "$RAW_DATE")
if [ $? -ne 0 ]; then
    exit 1
fi

# Validate the parsed date
if ! validate_date "$DATE"; then
    echo -e "${RED}Error: Invalid date: $DATE${NC}" >&2
    exit 1
fi

# Determine report date range (Friday -> include weekend, capped to today)
REPORT_RANGE=$(get_report_date_range "$DATE") || exit 1
IFS=' ' read -r REPORT_START_DATE REPORT_END_DATE <<< "$REPORT_RANGE"

START_OF_RANGE="${REPORT_START_DATE}T00:00:00Z"
END_OF_RANGE="${REPORT_END_DATE}T23:59:59Z"

DATE_LABEL="$REPORT_START_DATE"
if [ "$REPORT_START_DATE" != "$REPORT_END_DATE" ]; then
    DATE_LABEL="${REPORT_START_DATE} to ${REPORT_END_DATE}"
fi

echo -e "${BLUE}GitHub Activity Report for ${DATE_LABEL}${NC}"
echo "================================================"

# Configuration
# Set GITHUB_REPOS environment variable as a space-separated list of repos
# Example: export GITHUB_REPOS="ventrata/checkout-frontend ventrata/web-builder"
if [ -z "$GITHUB_REPOS" ]; then
    # Default repositories if not specified
    GITHUB_REPOS="ventrata/checkout-frontend ventrata/web-builder ventrata/FE-interview-v1 ventrata/FE-interview-questions"
fi

# Lookback period in days (default: 3)
LOOKBACK_DAYS="${LOOKBACK_DAYS:-3}"

# Build repository filter for gh search
REPO_FILTER=""
for repo in $GITHUB_REPOS; do
    if [ -z "$REPO_FILTER" ]; then
        REPO_FILTER="repo:${repo}"
    else
        REPO_FILTER="${REPO_FILTER} repo:${repo}"
    fi
done

# Function to extract Linear ticket ID from text
extract_linear_ticket() {
    local text="$1"
    echo "$text" | grep -oE 'CHE-[0-9]+' | head -1 || true
}

# Append ticket to a comma-separated list if not already present
append_ticket_unique() {
    local existing="$1"
    local ticket="$2"

    if [ -z "$ticket" ] || [ "$ticket" = "null" ]; then
        echo "$existing"
        return
    fi

    case ",$existing," in
        *",$ticket,"*)
            echo "$existing"
            ;;
        *)
            if [ -z "$existing" ]; then
                echo "$ticket"
            else
                echo "${existing},${ticket}"
            fi
            ;;
    esac
}

# Merge two comma-separated ticket lists while preserving order
merge_ticket_lists() {
    local existing="$1"
    local incoming="$2"
    local merged="$existing"
    local ticket
    local old_ifs="$IFS"

    IFS=','
    for ticket in $incoming; do
        merged=$(append_ticket_unique "$merged" "$ticket")
    done
    IFS="$old_ifs"

    echo "$merged"
}

# Build a unique ticket list from commit context (branch, PR title, commit title, full message)
build_commit_ticket_list() {
    local branch="$1"
    local pr_title="$2"
    local commit_title="$3"
    local message="$4"
    local tickets=""
    local ticket=""

    ticket=$(extract_linear_ticket "$branch")
    tickets=$(append_ticket_unique "$tickets" "$ticket")

    ticket=$(extract_linear_ticket "$pr_title")
    tickets=$(append_ticket_unique "$tickets" "$ticket")

    ticket=$(extract_linear_ticket "$commit_title")
    tickets=$(append_ticket_unique "$tickets" "$ticket")

    ticket=$(extract_linear_ticket "$message")
    tickets=$(append_ticket_unique "$tickets" "$ticket")

    echo "$tickets"
}

# Choose the best ticket candidate for a commit output line
resolve_commit_ticket() {
    local branch="$1"
    local pr_title="$2"
    local commit_title="$3"
    local message="$4"
    local ticket_id=""

    # Prefer task references in commit text, then PR title, then branch
    ticket_id=$(extract_linear_ticket "$commit_title")
    if [ -z "$ticket_id" ]; then
        ticket_id=$(extract_linear_ticket "$message")
    fi
    if [ -z "$ticket_id" ]; then
        ticket_id=$(extract_linear_ticket "$pr_title")
    fi
    if [ -z "$ticket_id" ]; then
        ticket_id=$(extract_linear_ticket "$branch")
    fi

    echo "$ticket_id"
}

# Function to get Linear task title
get_linear_task_title() {
    local ticket_id="$1"
    
    # Validate ticket ID format to prevent injection
    if ! [[ "$ticket_id" =~ ^CHE-[0-9]+$ ]]; then
        return 1
    fi
    
    # Check if Linear API key is available
    if [ -z "$LINEAR_API_KEY" ]; then
        return 1
    fi
    
    # Fetch task details from Linear
    local response=$(curl -s -X POST \
        -H "Authorization: $LINEAR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"query { issue(id: \\\"$ticket_id\\\") { title } }\"}" \
        https://api.linear.app/graphql 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "$response" | jq -r '.data.issue.title // empty' 2>/dev/null
    fi
}


# Get current user
CURRENT_USER=$(gh api user --jq '.login')
echo -e "${PURPLE}Current user: ${CURRENT_USER}${NC}"

# Temporary directory for storing results
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Initialize deduplication tracking arrays
# These will store PR numbers and branches that have been seen
# Note: Using a different approach for compatibility with older bash versions
# Initialize with delimiters to prevent substring matching issues
SEEN_PR_NUMBERS="|"
SEEN_PR_URLS="|"
SEEN_BRANCHES="|"

# Helper functions for tracking seen items
is_pr_seen() {
    local pr_number="$1"
    [[ "$SEEN_PR_NUMBERS" == *"|$pr_number|"* ]]
}

mark_pr_seen() {
    local pr_number="$1"
    SEEN_PR_NUMBERS="${SEEN_PR_NUMBERS}|$pr_number|"
}

is_url_seen() {
    local url="$1"
    [[ "$SEEN_PR_URLS" == *"|$url|"* ]]
}

mark_url_seen() {
    local url="$1"
    SEEN_PR_URLS="${SEEN_PR_URLS}|$url|"
}

is_branch_seen() {
    local branch="$1"
    [[ "$SEEN_BRANCHES" == *"|$branch|"* ]]
}

mark_branch_seen() {
    local branch="$1"
    SEEN_BRANCHES="${SEEN_BRANCHES}|$branch|"
}

echo -e "\n${YELLOW}Fetching your GitHub activity...${NC}"

# 1. Fetch PRs created today
echo -e "${YELLOW}  - Searching for PRs you created on ${DATE_LABEL}...${NC}"
CREATED_QUALIFIER="${DATE}"
if [ "$REPORT_START_DATE" != "$REPORT_END_DATE" ]; then
    CREATED_QUALIFIER="${REPORT_START_DATE}..${REPORT_END_DATE}"
fi
gh search prs ${REPO_FILTER} author:@me created:"${CREATED_QUALIFIER}" \
    --json number,title,url,repository,author,createdAt \
    --limit 100 \
    > "$TEMP_DIR/authored.json"

# 2. Fetch PRs where you submitted a formal review on the specific date
echo -e "${YELLOW}  - Searching for PRs you reviewed...${NC}"

# Get PRs potentially reviewed in the last N days
LOOKBACK_DATE=$(date -d "${REPORT_START_DATE} -${LOOKBACK_DAYS} days" -I 2>/dev/null || date -v-${LOOKBACK_DAYS}d -I)

# Validate date generation
if [ -z "$LOOKBACK_DATE" ] || [ "$LOOKBACK_DATE" = "" ]; then
    echo -e "${RED}Error: Failed to generate lookback date. Please check your date command and input.${NC}" >&2
    exit 1
fi

gh search prs ${REPO_FILTER} reviewed-by:@me updated:">=${LOOKBACK_DATE}" \
    --json number,title,url,repository,author \
    --limit 200 \
    > "$TEMP_DIR/reviewed_all.json"

# Filter to only PRs where we actually submitted a review on the specific date
echo "[]" > "$TEMP_DIR/reviewed.json"

jq -c '.[]' "$TEMP_DIR/reviewed_all.json" | while read -r pr_json; do
    pr_number=$(echo "$pr_json" | jq -r '.number')
    repo=$(echo "$pr_json" | jq -r '.repository.nameWithOwner')
    
    # Check if we reviewed this PR on the specific date
    review_data=$(gh api graphql -f query="
    {
      repository(owner: \"$(echo "$repo" | cut -d'/' -f1)\", name: \"$(echo "$repo" | cut -d'/' -f2)\") {
        pullRequest(number: ${pr_number}) {
          reviews(first: 100) {
            nodes {
              author {
                login
              }
              createdAt
              submittedAt
            }
          }
        }
      }
    }" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        has_review=$(echo "$review_data" | jq --arg user "$CURRENT_USER" --arg start_ts "$START_OF_RANGE" --arg end_ts "$END_OF_RANGE" '
          .data.repository.pullRequest.reviews.nodes // [] |
          map(select(
            (.author.login // "") == $user and
            ((.submittedAt // .createdAt // "") as $ts | ($ts != "" and $ts >= $start_ts and $ts <= $end_ts))
          )) |
          length > 0
        ')
        
        if [ "$has_review" = "true" ]; then
            # Fetch headRefName for this PR
            headRefName=$(gh pr view "$pr_number" -R "$repo" --json headRefName -q '.headRefName' 2>/dev/null || echo "")
            
            # Add headRefName to the PR JSON
            pr_with_branch=$(echo "$pr_json" | jq --arg branch "$headRefName" '. + {headRefName: $branch}')
            
            # Add this PR to our reviewed list
            jq --argjson pr "$pr_with_branch" '. += [$pr]' "$TEMP_DIR/reviewed.json" > "$TEMP_DIR/temp.json" && mv "$TEMP_DIR/temp.json" "$TEMP_DIR/reviewed.json"
        fi
    fi
done

# Filter out your own PRs from reviewed list
jq --arg user "$CURRENT_USER" '[.[] | select(.author.login != $user)]' "$TEMP_DIR/reviewed.json" > "$TEMP_DIR/temp.json" && mv "$TEMP_DIR/temp.json" "$TEMP_DIR/reviewed.json"

# 3. Fetch PRs where you commented on the specific date
echo -e "${YELLOW}  - Searching for PRs you commented on...${NC}"

# First, get a list of recently active PRs where you might have commented
# We look back N days to ensure we don't miss any PRs
LOOKBACK_DATE=$(date -d "${REPORT_START_DATE} -${LOOKBACK_DAYS} days" -I 2>/dev/null || date -v-${LOOKBACK_DAYS}d -I)

# Build GraphQL repository filter
GRAPHQL_REPO_FILTER=""
for repo in $GITHUB_REPOS; do
    if [ -n "$GRAPHQL_REPO_FILTER" ]; then
        GRAPHQL_REPO_FILTER="${GRAPHQL_REPO_FILTER} "
    fi
    GRAPHQL_REPO_FILTER="${GRAPHQL_REPO_FILTER}repo:${repo}"
done

gh api graphql -f query="
{
  search(first: 100, type: ISSUE, query: \"commenter:${CURRENT_USER} updated:>=${LOOKBACK_DATE} is:pr ${GRAPHQL_REPO_FILTER}\") {
    nodes {
      ... on PullRequest {
        number
        title
        url
        repository {
          nameWithOwner
        }
        author {
          login
        }
        headRefName
      }
    }
  }
}" --jq '.data.search.nodes' > "$TEMP_DIR/potential_commented.json"

# Now fetch timeline items for each PR to check actual comment dates
echo "" > "$TEMP_DIR/commented_only.json"
echo "[]" > "$TEMP_DIR/commented_only.json"

# Process each PR to check if we actually commented on the specified date
jq -c '.[]' "$TEMP_DIR/potential_commented.json" | while read -r pr_json; do
    pr_number=$(echo "$pr_json" | jq -r '.number')
    repo=$(echo "$pr_json" | jq -r '.repository.nameWithOwner')
    
    # Fetch timeline items (comments and reviews) for this PR
    timeline_data=$(gh api graphql -f query="
    {
      repository(owner: \"$(echo "$repo" | cut -d'/' -f1)\", name: \"$(echo "$repo" | cut -d'/' -f2)\") {
        pullRequest(number: ${pr_number}) {
          timelineItems(first: 100, itemTypes: [ISSUE_COMMENT, PULL_REQUEST_REVIEW]) {
            nodes {
              __typename
              ... on IssueComment {
                author {
                  login
                }
                createdAt
              }
              ... on PullRequestReview {
                author {
                  login
                }
                createdAt
                submittedAt
              }
            }
          }
        }
      }
    }" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # Check if current user commented on the specific date
        has_activity=$(echo "$timeline_data" | jq --arg user "$CURRENT_USER" --arg start_ts "$START_OF_RANGE" --arg end_ts "$END_OF_RANGE" '
          .data.repository.pullRequest.timelineItems.nodes // [] |
          map(select(
            (.author.login // "") == $user and
            ((.submittedAt // .createdAt // "") as $ts | ($ts != "" and $ts >= $start_ts and $ts <= $end_ts))
          )) |
          length > 0
        ')
        
        if [ "$has_activity" = "true" ]; then
            # Add to commented PRs if we haven't already reviewed it
            reviewed=$(jq --arg num "$pr_number" --arg repo "$repo" '
              any(.number == ($num | tonumber) and .repository.nameWithOwner == $repo)
            ' "$TEMP_DIR/reviewed.json")
            
            if [ "$reviewed" = "false" ]; then
                # Add this PR to our commented list
                jq --argjson pr "$pr_json" '. += [$pr]' "$TEMP_DIR/commented_only.json" > "$TEMP_DIR/temp.json" && mv "$TEMP_DIR/temp.json" "$TEMP_DIR/commented_only.json"
            fi
        fi
    fi
done

# Filter out authored PRs
jq --arg user "$CURRENT_USER" '[.[] | select(.author.login != $user)]' "$TEMP_DIR/commented_only.json" > "$TEMP_DIR/temp.json" && mv "$TEMP_DIR/temp.json" "$TEMP_DIR/commented_only.json"

# Merge reviewed and commented PRs, removing duplicates
jq -s '
  (.[0] + .[1]) | 
  unique_by(.number) |
  sort_by(.number)
' "$TEMP_DIR/reviewed.json" "$TEMP_DIR/commented_only.json" > "$TEMP_DIR/all_reviews.json"

# 4. Fetch commits made on the specific date
echo -e "${YELLOW}  - Searching for commits you made on ${DATE_LABEL}...${NC}"
echo "[]" > "$TEMP_DIR/commits.json"

# GraphQL helper queries for commit discovery
IFS='' read -r -d '' BRANCHES_QUERY <<'EOF' || true
query($owner: String!, $name: String!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    refs(refPrefix: "refs/heads/", first: 50, after: $cursor, orderBy: {field: ALPHABETICAL, direction: ASC}) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        name
        target {
          __typename
          ... on Commit {
            committedDate
          }
        }
      }
    }
  }
}
EOF

IFS='' read -r -d '' COMMITS_BY_BRANCH_QUERY <<'EOF' || true
query($owner: String!, $name: String!, $branch: String!, $since: GitTimestamp!, $until: GitTimestamp!) {
  repository(owner: $owner, name: $name) {
    ref(qualifiedName: $branch) {
      name
      target {
        ... on Commit {
          history(first: 50, since: $since, until: $until) {
            nodes {
              oid
              message
              authoredDate
              author {
                name
                email
                user {
                  login
                }
              }
              associatedPullRequests(first: 1) {
                nodes {
                  number
                  title
                  url
                  headRefName
                  createdAt
                }
              }
            }
          }
        }
      }
    }
  }
}
EOF

# Search for commits in each repository
for repo in $GITHUB_REPOS; do
    owner="$(echo "$repo" | cut -d'/' -f1)"
    name="$(echo "$repo" | cut -d'/' -f2)"
    cursor=""

    while :; do
        if [ -n "$cursor" ]; then
            if ! branches_payload=$(gh api graphql \
                -f query="$BRANCHES_QUERY" \
                -F owner="$owner" \
                -F name="$name" \
                -F cursor="$cursor" 2>/dev/null); then
                echo -e "${YELLOW}    ⚠️  Unable to list branches for ${repo}; skipping commit lookup.${NC}" >&2
                break
            fi
        else
            if ! branches_payload=$(gh api graphql \
                -f query="$BRANCHES_QUERY" \
                -F owner="$owner" \
                -F name="$name" 2>/dev/null); then
                echo -e "${YELLOW}    ⚠️  Unable to list branches for ${repo}; skipping commit lookup.${NC}" >&2
                break
            fi
        fi

        if [ -z "$branches_payload" ]; then
            echo -e "${YELLOW}    ⚠️  Unable to list branches for ${repo}; skipping commit lookup.${NC}" >&2
            break
        fi

        if echo "$branches_payload" | jq -e '.errors' >/dev/null 2>&1; then
            echo -e "${YELLOW}    ⚠️  GraphQL error while listing branches for ${repo}; skipping.${NC}" >&2
            break
        fi

        # Extract branch names from the payload
        branch_names=$(echo "$branches_payload" | jq -r '
          .data.repository.refs.nodes[]? |
          [.name, (if .target.__typename == "Commit" then (.target.committedDate // "") else "" end)] | @tsv
        ' 2>/dev/null || true)

        if [ -n "$branch_names" ]; then
            while IFS=$'\t' read -r branch_name tip_date; do
                [ -z "$branch_name" ] && continue

                # Skip branches whose tip commit predates the requested day to avoid expensive lookups
                if [ -n "$tip_date" ] && [[ "$tip_date" < "$START_OF_RANGE" ]]; then
                    continue
                fi

                branch_ref="refs/heads/${branch_name}"

                if ! commit_payload=$(gh api graphql \
                    -f query="$COMMITS_BY_BRANCH_QUERY" \
                    -F owner="$owner" \
                    -F name="$name" \
                    -F branch="$branch_ref" \
                    -F since="$START_OF_RANGE" \
                    -F until="$END_OF_RANGE" 2>/dev/null); then
                    echo -e "${YELLOW}      ⚠️  Failed to load commits for ${repo}:${branch_name}.${NC}" >&2
                    continue
                fi

                if [ -z "$commit_payload" ]; then
                    continue
                fi

                if echo "$commit_payload" | jq -e '.errors' >/dev/null 2>&1; then
                    echo -e "${YELLOW}      ⚠️  GraphQL error on ${repo}:${branch_name}; skipping branch.${NC}" >&2
                    continue
                fi

                filtered_commits=$(echo "$commit_payload" | jq --arg user "$CURRENT_USER" --arg repo "$repo" --arg branch "$branch_name" '
                  [.data.repository.ref.target.history.nodes[]? // empty |
                   select((.author.user.login // "") == $user or (.author.name // "") == $user) |
                   . + {repository: $repo, branchName: $branch}]' 2>/dev/null || echo "[]")

                if [ -n "$filtered_commits" ] && [ "$filtered_commits" != "[]" ]; then
                    jq --argjson new_commits "$filtered_commits" '
                      . as $existing |
                      ($existing + $new_commits) |
                      unique_by(.oid)
                    ' "$TEMP_DIR/commits.json" > "$TEMP_DIR/temp.json" && mv "$TEMP_DIR/temp.json" "$TEMP_DIR/commits.json"
                fi
            done <<< "$branch_names"
        fi

        has_next=$(echo "$branches_payload" | jq -r '.data.repository.refs.pageInfo.hasNextPage // false')
        cursor=$(echo "$branches_payload" | jq -r '.data.repository.refs.pageInfo.endCursor // ""')

        if [ "$has_next" != "true" ] || [ -z "$cursor" ] || [ "$cursor" = "null" ]; then
            break
        fi
    done
done

# Preserve full commit list for summary statistics before filtering
cp "$TEMP_DIR/commits.json" "$TEMP_DIR/commits_all.json"

# Function to process a PR and format the output
process_pr() {
    local pr_json="$1"
    local pr_type="$2"
    local format="${3:-markdown}"  # default to markdown
    
    local number=$(echo "$pr_json" | jq -r '.number')
    local title=$(echo "$pr_json" | jq -r '.title')
    local url=$(echo "$pr_json" | jq -r '.url')
    local repo=$(echo "$pr_json" | jq -r '.repository.nameWithOwner')
    local author=$(echo "$pr_json" | jq -r '.author.login // ""')
    local branch=$(echo "$pr_json" | jq -r '.headRefName // ""')
    
    # If we don't have branch from the initial data, fetch it
    if [ -z "$branch" ] || [ "$branch" = "null" ]; then
        branch=$(gh pr view "$number" -R "$repo" --json headRefName -q '.headRefName' 2>/dev/null || echo "")
    fi
    
    local ticket_id=$(extract_linear_ticket "$branch")
    if [ -z "$ticket_id" ]; then
        ticket_id=$(extract_linear_ticket "$title")
    fi
    
    if [ -n "$ticket_id" ]; then
        local linear_url="https://linear.app/ventrata/issue/${ticket_id}"
        local linear_title=$(get_linear_task_title "$ticket_id")
        
        if [ -n "$linear_title" ]; then
            # Format: <linear task title>[linear task link] - <pr title>[pr link]
            if [ "$format" = "slack" ]; then
                echo "${linear_title} ${ticket_id} (${linear_url}) - ${title} - PR #${number} (${url})"
            else
                echo "${linear_title} [${ticket_id}](${linear_url}) - ${title} [PR #${number}](${url})"
            fi
        else
            # Fallback if we can't get Linear title
            if [ "$format" = "slack" ]; then
                echo "${ticket_id} (${linear_url}) - ${title} - PR #${number} (${url})"
            else
                echo "[${ticket_id}](${linear_url}) - ${title} [PR #${number}](${url})"
            fi
        fi
    else
        # No Linear ticket
        if [ "$pr_type" = "code-review" ] && [ -n "$author" ]; then
            if [ "$format" = "slack" ]; then
                echo "PR #${number}: ${title} (${url}) by @${author}"
            else
                echo "[PR #${number}: ${title}](${url}) by @${author}"
            fi
        else
            if [ "$format" = "slack" ]; then
                echo "PR #${number}: ${title} (${url})"
            else
                echo "[PR #${number}: ${title}](${url})"
            fi
        fi
    fi
}

# Function to process a commit and format the output
process_commit() {
    local commit_json="$1"
    local format="${2:-markdown}"  # default to markdown
    
    local message=$(echo "$commit_json" | jq -r '.message')
    local oid=$(echo "$commit_json" | jq -r '.oid' | cut -c1-7)
    local repo=$(echo "$commit_json" | jq -r '.repository')
    local pr_data=$(echo "$commit_json" | jq -r '.associatedPullRequests.nodes[0] // empty')
    local branch=$(echo "$commit_json" | jq -r '.branchName // ""')
    
    # Extract first line of commit message
    local commit_title=$(echo "$message" | head -1)
    
    if [ -n "$pr_data" ] && [ "$pr_data" != "null" ]; then
        local pr_number=$(echo "$pr_data" | jq -r '.number')
        local pr_title=$(echo "$pr_data" | jq -r '.title // ""')
        local pr_url=$(echo "$pr_data" | jq -r '.url')
        local pr_branch=$(echo "$pr_data" | jq -r '.headRefName // ""')
        if [ -n "$pr_branch" ] && [ "$pr_branch" != "null" ]; then
            branch="$pr_branch"
        fi
        local ticket_id=$(resolve_commit_ticket "$branch" "$pr_title" "$commit_title" "$message")
        
        if [ -n "$ticket_id" ]; then
            local linear_url="https://linear.app/ventrata/issue/${ticket_id}"
            local linear_title=$(get_linear_task_title "$ticket_id")
            
            if [ -n "$linear_title" ]; then
                if [ "$format" = "slack" ]; then
                    echo "${linear_title} ${ticket_id} (${linear_url}) - ${commit_title} - PR #${pr_number} (${pr_url})"
                else
                    echo "${linear_title} [${ticket_id}](${linear_url}) - ${commit_title} [PR #${pr_number}](${pr_url})"
                fi
            else
                if [ "$format" = "slack" ]; then
                    echo "${ticket_id} (${linear_url}) - ${commit_title} - PR #${pr_number} (${pr_url})"
                else
                    echo "[${ticket_id}](${linear_url}) - ${commit_title} [PR #${pr_number}](${pr_url})"
                fi
            fi
        else
            if [ "$format" = "slack" ]; then
                echo "${commit_title} - PR #${pr_number} (${pr_url})"
            else
                echo "${commit_title} [PR #${pr_number}](${pr_url})"
            fi
        fi
    else
        # Commit without PR
        local ticket_id=$(resolve_commit_ticket "$branch" "" "$commit_title" "$message")
        if [ -n "$ticket_id" ]; then
            local linear_url="https://linear.app/ventrata/issue/${ticket_id}"
            local linear_title=$(get_linear_task_title "$ticket_id")
            
            if [ -n "$linear_title" ]; then
                if [ "$format" = "slack" ]; then
                    echo "${linear_title} ${ticket_id} (${linear_url}) - ${commit_title} (${oid})"
                else
                    echo "${linear_title} [${ticket_id}](${linear_url}) - ${commit_title} (${oid})"
                fi
            else
                if [ "$format" = "slack" ]; then
                    echo "${ticket_id} (${linear_url}) - ${commit_title} (${oid})"
                else
                    echo "[${ticket_id}](${linear_url}) - ${commit_title} (${oid})"
                fi
            fi
        else
            echo "${commit_title} (${oid})"
        fi
    fi
}

# Generate report
echo -e "\n${GREEN}## Daily GitHub Activity Summary${NC}"
echo -e "${GREEN}Date: ${DATE_LABEL}${NC}\n"

# Build the report content once
REPORT_CONTENT=""

# Process authored PRs
authored_count=$(jq 'length' "$TEMP_DIR/authored.json")
if [ "$authored_count" -gt 0 ]; then
    REPORT_CONTENT+="### Opened PRs\n"
    
    # Process authored PRs without subshell to preserve variable changes
    authored_lines=$(jq -c '.[]' "$TEMP_DIR/authored.json")
    while IFS= read -r pr_json; do
        [ -z "$pr_json" ] && continue
        
        # Track PR for deduplication
        pr_number=$(echo "$pr_json" | jq -r '.number')
        pr_url=$(echo "$pr_json" | jq -r '.url')
        branch=$(echo "$pr_json" | jq -r '.headRefName // ""')
        
        mark_pr_seen "$pr_number"
        mark_url_seen "$pr_url"
        if [ -n "$branch" ] && [ "$branch" != "null" ]; then
            mark_branch_seen "$branch"
        fi
        
        output=$(process_pr "$pr_json" "impl")
        REPORT_CONTENT+="- $output\n"
    done <<< "$authored_lines"
    REPORT_CONTENT+="\n"
fi

# Process reviewed/commented PRs
review_count=$(jq 'length' "$TEMP_DIR/all_reviews.json")
if [ "$review_count" -gt 0 ]; then
    # Track if we actually display any reviews after deduplication
    review_displayed=0
    REVIEW_SECTION=""
    
    # Process reviews without subshell to preserve variable changes
    review_lines=$(jq -c '.[]' "$TEMP_DIR/all_reviews.json")
    while IFS= read -r pr_json; do
        [ -z "$pr_json" ] && continue
        
        # Check if this PR was already shown in authored section
        pr_number=$(echo "$pr_json" | jq -r '.number')
        pr_url=$(echo "$pr_json" | jq -r '.url')
        branch=$(echo "$pr_json" | jq -r '.headRefName // ""')
        
        # Skip if already shown
        if is_pr_seen "$pr_number" || is_url_seen "$pr_url"; then
            continue
        fi
        
        # Track for next section
        mark_pr_seen "$pr_number"
        mark_url_seen "$pr_url"
        if [ -n "$branch" ] && [ "$branch" != "null" ]; then
            mark_branch_seen "$branch"
        fi
        
        output=$(process_pr "$pr_json" "code-review")
        REVIEW_SECTION+="- $output\n"
        review_displayed=$((review_displayed + 1))
    done <<< "$review_lines"
    
    # Only add section if we have reviews to display
    if [ "$review_displayed" -gt 0 ]; then
        REPORT_CONTENT+="### Code Reviews & Comments\n"
        REPORT_CONTENT+="$REVIEW_SECTION"
        REPORT_CONTENT+="\n"
    fi
fi

# Process commits
commit_total_count=$(jq 'length' "$TEMP_DIR/commits_all.json")
commit_display_count=$(jq 'length' "$TEMP_DIR/commits.json")
if [ "$commit_display_count" -gt 0 ]; then
    # Track if we actually display any commits after deduplication
    displayed_branches=0
    COMMITS_SECTION=""
    
    # First, group commits by branch
    # Using bash 3.x compatible approach (no associative arrays)
    # Format: branch_name|commit_count|linear_tickets_csv|pr_number|pr_url
    BRANCH_GROUPS=""
    
    # Process commits to group by branch
    commit_lines=$(jq -c '.[]' "$TEMP_DIR/commits.json")
    while IFS= read -r commit_json; do
        [ -z "$commit_json" ] && continue
        
        # Reset PR variables for each commit
        pr_number=""
        pr_url=""
        
        # Extract branch from commit data first, then check PR info
        message=$(echo "$commit_json" | jq -r '.message // ""')
        commit_title=$(echo "$message" | head -1)
        branch=$(echo "$commit_json" | jq -r '.branchName // ""')
        pr_data=$(echo "$commit_json" | jq -r '.associatedPullRequests.nodes[0] // empty')
        pr_title=""
        branch_ticket=""
        pr_title_ticket=""
        commit_title_ticket=""
        message_ticket=""
        extra_commit_ticket=""
        is_seen_context=0

        if [ -n "$pr_data" ] && [ "$pr_data" != "null" ]; then
            pr_number=$(echo "$pr_data" | jq -r '.number')
            pr_url=$(echo "$pr_data" | jq -r '.url')
            pr_title=$(echo "$pr_data" | jq -r '.title // ""')
            # Use PR branch if available, otherwise use commit branch
            pr_branch=$(echo "$pr_data" | jq -r '.headRefName // ""')
            if [ -n "$pr_branch" ] && [ "$pr_branch" != "null" ]; then
                branch="$pr_branch"
            fi
        fi

        branch_ticket=$(extract_linear_ticket "$branch")
        pr_title_ticket=$(extract_linear_ticket "$pr_title")
        commit_title_ticket=$(extract_linear_ticket "$commit_title")
        message_ticket=$(extract_linear_ticket "$message")

        if [ -n "$commit_title_ticket" ] && [ "$commit_title_ticket" != "$branch_ticket" ] && [ "$commit_title_ticket" != "$pr_title_ticket" ]; then
            extra_commit_ticket="$commit_title_ticket"
        elif [ -n "$message_ticket" ] && [ "$message_ticket" != "$branch_ticket" ] && [ "$message_ticket" != "$pr_title_ticket" ]; then
            extra_commit_ticket="$message_ticket"
        fi

        if [ -n "$pr_number" ] && [ -n "$pr_url" ]; then
            if is_pr_seen "$pr_number" || is_url_seen "$pr_url"; then
                is_seen_context=1
            fi
        fi

        if [ -n "$branch" ] && [ "$branch" != "null" ] && is_branch_seen "$branch"; then
            is_seen_context=1
        fi

        # Skip deduplicated commits unless they introduce an additional ticket
        if [ "$is_seen_context" -eq 1 ] && [ -z "$extra_commit_ticket" ]; then
            continue
        fi

        # If we have a branch (from commit or PR), track it
        if [ -n "$branch" ] && [ "$branch" != "null" ]; then
            ticket_list=$(build_commit_ticket_list "$branch" "$pr_title" "$commit_title" "$message")
            
            # Check if this branch is already in our groups
            found_branch=0
            NEW_GROUPS=""
            while IFS='#' read -r group_entry; do
                [ -z "$group_entry" ] && continue
                branch_name=$(echo "$group_entry" | cut -d'|' -f1)
                count=$(echo "$group_entry" | cut -d'|' -f2)
                existing_tickets=$(echo "$group_entry" | cut -d'|' -f3)
                existing_pr=$(echo "$group_entry" | cut -d'|' -f4)
                existing_url=$(echo "$group_entry" | cut -d'|' -f5)
                
                if [ "$branch_name" = "$branch" ]; then
                    count=$((count + 1))
                    found_branch=1
                    # Keep first PR info if we don't have one
                    if [ -z "$existing_pr" ] || [ "$existing_pr" = "null" ] || [ "$existing_pr" = "" ]; then
                        existing_pr="$pr_number"
                        existing_url="$pr_url"
                    fi
                    # Merge tickets discovered from branch/PR/commit context
                    existing_tickets=$(merge_ticket_lists "$existing_tickets" "$ticket_list")
                fi
                NEW_GROUPS+="${branch_name}|${count}|${existing_tickets}|${existing_pr}|${existing_url}#"
            done <<< "${BRANCH_GROUPS//\#/$'\n'}"
            
            if [ "$found_branch" -eq 0 ]; then
                # Add new branch
                NEW_GROUPS+="${branch}|1|${ticket_list}|${pr_number}|${pr_url}#"
            fi
            BRANCH_GROUPS="$NEW_GROUPS"
        else
            # Commit without branch - process individually
            output=$(process_commit "$commit_json")
            COMMITS_SECTION+="- $output\n"
            displayed_branches=$((displayed_branches + 1))
        fi
    done <<< "$commit_lines"
    
    # Now process grouped branches
    while IFS='#' read -r group_entry; do
        [ -z "$group_entry" ] && continue
        
        branch=$(echo "$group_entry" | cut -d'|' -f1)
        count=$(echo "$group_entry" | cut -d'|' -f2)
        ticket_list=$(echo "$group_entry" | cut -d'|' -f3)
        ticket_id=$(echo "$ticket_list" | cut -d',' -f1)
        additional_tickets=$(echo "$ticket_list" | cut -d',' -f2-)
        pr_number=$(echo "$group_entry" | cut -d'|' -f4)
        pr_url=$(echo "$group_entry" | cut -d'|' -f5)
        
        # Mark branch as seen
        mark_branch_seen "$branch"
        if [ -n "$pr_number" ] && [ "$pr_number" != "null" ]; then
            mark_pr_seen "$pr_number"
            mark_url_seen "$pr_url"
        fi
        
        # Format the branch summary
        if [ -n "$ticket_id" ] && [ "$ticket_id" != "null" ]; then
            linear_url="https://linear.app/ventrata/issue/${ticket_id}"
            linear_title=$(get_linear_task_title "$ticket_id" || true)
            
            if [ -n "$linear_title" ]; then
                base_msg="${linear_title} [${ticket_id}](${linear_url}) - development on \`${branch}\`"
            else
                base_msg="[${ticket_id}](${linear_url}) - development on \`${branch}\`"
            fi
        else
            base_msg="Development on \`${branch}\`"
        fi
        
        # Add commit count if more than 1
        if [ "$count" -gt 1 ]; then
            base_msg+=" (${count} commits)"
        fi

        # Add additional ticket links when commit messages reference subtasks
        if [ -n "$additional_tickets" ] && [ "$additional_tickets" != "$ticket_list" ]; then
            related_links=""
            old_ifs="$IFS"
            IFS=','
            for related_ticket in $additional_tickets; do
                [ -z "$related_ticket" ] && continue
                related_url="https://linear.app/ventrata/issue/${related_ticket}"
                if [ -n "$related_links" ]; then
                    related_links="${related_links}, "
                fi
                related_links="${related_links}[${related_ticket}](${related_url})"
            done
            IFS="$old_ifs"

            if [ -n "$related_links" ]; then
                base_msg+=" (also: ${related_links})"
            fi
        fi

        # Add PR reference if available
        if [ -n "$pr_number" ] && [ "$pr_number" != "null" ] && [ "$pr_number" != "" ]; then
            base_msg+=" [PR #${pr_number}](${pr_url})"
        fi
        
        COMMITS_SECTION+="- ${base_msg}\n"
        displayed_branches=$((displayed_branches + 1))
    done <<< "${BRANCH_GROUPS//\#/$'\n'}"
    
    # Only add section if we have commits to display
    if [ "$displayed_branches" -gt 0 ]; then
        REPORT_CONTENT+="### Commits, Merges, Resolutions\n"
        REPORT_CONTENT+="$COMMITS_SECTION"
        REPORT_CONTENT+="\n"
    fi
fi

# Display the report content to terminal with colors
if [ -n "$REPORT_CONTENT" ]; then
    # Split content by lines and colorize section headers
    while IFS= read -r line; do
        if [[ "$line" == "### "* ]]; then
            echo -e "${BLUE}$line${NC}"
        else
            echo "$line"
        fi
    done <<< "${REPORT_CONTENT%$'\n'}"  # Remove trailing newline
fi

# Summary
total=$((authored_count + review_count + commit_total_count))
if [ "$total" -eq 0 ]; then
    echo -e "${YELLOW}No GitHub activity found for ${DATE_LABEL}${NC}"
else
    echo -e "${GREEN}Total: ${authored_count} PRs authored, ${review_count} PRs reviewed/commented, ${commit_total_count} commits${NC}"
    
    # Show breakdown if we have both reviews and comments
    reviewed_count=$(jq 'length' "$TEMP_DIR/reviewed.json")
    commented_only_count=$(jq 'length' "$TEMP_DIR/commented_only.json")
    if [ "$commented_only_count" -gt 0 ] && [ "$reviewed_count" -gt 0 ]; then
        echo -e "${CYAN}  (${reviewed_count} formal reviews, ${commented_only_count} comment-only interactions)${NC}"
    fi
    
    # Copy to clipboard if available
    if command -v pbcopy &> /dev/null && [ -n "$REPORT_CONTENT" ]; then
        # Copy the same content to clipboard (without colors)
        echo -n -e "${REPORT_CONTENT%\\n}" | pbcopy
        echo -e "\n${YELLOW}✓ Report copied to clipboard!${NC}"
    fi
fi

# Tips
echo -e "\n${PURPLE}Tips:${NC}"
echo -e "  • This version includes PRs where you only left comments (not formal reviews)"
echo -e "  • Tracks commits you made on the specified date, even without PRs"
echo -e "  • Set LINEAR_API_KEY to fetch Linear task titles"
echo -e "  • Run without arguments for previous working day: ${BLUE}./$(basename "$0")${NC}"
echo -e "  • Specify a date: ${BLUE}./$(basename "$0") 2025-06-18${NC} or ${BLUE}./$(basename "$0") 18-06-2025${NC}"
echo -e "  • Use shortcuts: ${BLUE}./$(basename "$0") today${NC} or ${BLUE}./$(basename "$0") yesterday${NC}"
echo -e "  • Add as alias: ${BLUE}alias daily-report='$(pwd)/$(basename "$0")'${NC}"
