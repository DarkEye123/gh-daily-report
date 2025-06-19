#!/bin/bash

# GitHub Daily Activity Report Generator with Comments Support
# Generates a summary of PRs authored, reviewed, and commented on with Linear ticket links

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default to today's date
DATE="${1:-$(date -I)}"

echo -e "${BLUE}GitHub Activity Report for ${DATE}${NC}"
echo "================================================"

# Function to extract Linear ticket ID from text
extract_linear_ticket() {
    local text="$1"
    echo "$text" | grep -oE 'CHE-[0-9]+' | head -1 || true
}

# Function to get Linear ticket title (placeholder for now)
get_linear_title() {
    local ticket_id="$1"
    
    # Try to get from Linear (this would use the MCP integration in a real scenario)
    case "$ticket_id" in
        "CHE-1654")
            echo "window.Ventrata({}) -> window.Ventrata()"
            ;;
        "CHE-1463")
            echo "Brands V2"
            ;;
        "CHE-255")
            echo "fix: combobox smooth scroll to select container on input click"
            ;;
        "CHE-256")
            echo "feat: end of the month show the next month in calendar day"
            ;;
        "CHE-1604")
            echo "feat: memberships support headless logout"
            ;;
        "CHE-1475")
            echo "fix: debounce for unit data loading functions"
            ;;
        *)
            # Return empty string if we don't have the title
            echo ""
            ;;
    esac
}

# Get current user
CURRENT_USER=$(gh api user --jq '.login')
echo -e "${PURPLE}Current user: ${CURRENT_USER}${NC}"

# Temporary directory for storing results
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo -e "\n${YELLOW}Fetching your GitHub activity...${NC}"

# 1. Fetch PRs created today
echo -e "${YELLOW}  - Searching for PRs you created on ${DATE}...${NC}"
gh search prs \
    --author "@me" \
    --created "${DATE}" \
    --json number,title,url,repository,author,createdAt \
    --limit 100 \
    > "$TEMP_DIR/authored.json"

# 2. Fetch PRs where you submitted a formal review on the specific date
echo -e "${YELLOW}  - Searching for PRs you reviewed...${NC}"

# Get PRs potentially reviewed in the last 30 days
LOOKBACK_DATE=$(date -d "${DATE} -30 days" -I 2>/dev/null || date -v-30d -I)

gh search prs \
    --reviewed-by "@me" \
    --updated ">=${LOOKBACK_DATE}" \
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
      repository(owner: \"$(echo $repo | cut -d'/' -f1)\", name: \"$(echo $repo | cut -d'/' -f2)\") {
        pullRequest(number: ${pr_number}) {
          reviews(first: 100) {
            nodes {
              author {
                login
              }
              createdAt
            }
          }
        }
      }
    }" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        has_review=$(echo "$review_data" | jq --arg user "$CURRENT_USER" --arg date "$DATE" '
          .data.repository.pullRequest.reviews.nodes // [] |
          map(select(.author.login == $user and (.createdAt | startswith($date)))) |
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
# We look back 30 days to ensure we don't miss any PRs
LOOKBACK_DATE=$(date -d "${DATE} -30 days" -I 2>/dev/null || date -v-30d -I)

gh api graphql -f query="
{
  search(first: 100, type: ISSUE, query: \"commenter:${CURRENT_USER} updated:>=${LOOKBACK_DATE} is:pr\") {
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
      repository(owner: \"$(echo $repo | cut -d'/' -f1)\", name: \"$(echo $repo | cut -d'/' -f2)\") {
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
              }
            }
          }
        }
      }
    }" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # Check if current user commented on the specific date
        has_activity=$(echo "$timeline_data" | jq --arg user "$CURRENT_USER" --arg date "$DATE" '
          .data.repository.pullRequest.timelineItems.nodes // [] |
          map(select(.author.login == $user and (.createdAt | startswith($date)))) |
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

# Function to process a PR and format the output
process_pr() {
    local pr_json="$1"
    local pr_type="$2"
    
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
    
    if [ -n "$ticket_id" ]; then
        local linear_title=$(get_linear_title "$ticket_id")
        local linear_url="https://linear.app/ventrata/issue/${ticket_id}"
        
        if [ -n "$linear_title" ]; then
            echo "${pr_type}: [${ticket_id}: ${linear_title}](${linear_url})"
        else
            # Use PR title as fallback
            echo "${pr_type}: [${ticket_id}: ${title}](${linear_url})"
        fi
    else
        # No Linear ticket
        if [ "$pr_type" = "code-review" ] && [ -n "$author" ]; then
            echo "${pr_type}: [PR #${number}: ${title}](${url}) - ${repo} by @${author}"
        else
            echo "${pr_type}: [PR #${number}: ${title}](${url}) - ${repo}"
        fi
    fi
}

# Generate report
echo -e "\n${GREEN}## Daily GitHub Activity Summary${NC}"
echo -e "${GREEN}Date: ${DATE}${NC}\n"

# Collect all output for clipboard
REPORT_SECTIONS=""

# Process authored PRs
authored_count=$(jq 'length' "$TEMP_DIR/authored.json")
if [ "$authored_count" -gt 0 ]; then
    echo -e "${BLUE}### Implementation (Authored PRs)${NC}"
    SECTION="### Implementation (Authored PRs)\n"
    
    jq -c '.[]' "$TEMP_DIR/authored.json" | while read -r pr_json; do
        output=$(process_pr "$pr_json" "impl")
        echo "- $output"
        SECTION+="- $output\n"
    done
    echo
    REPORT_SECTIONS+="$SECTION\n"
fi

# Process reviewed/commented PRs
review_count=$(jq 'length' "$TEMP_DIR/all_reviews.json")
if [ "$review_count" -gt 0 ]; then
    echo -e "${BLUE}### Code Reviews & Comments${NC}"
    SECTION="### Code Reviews & Comments\n"
    
    jq -c '.[]' "$TEMP_DIR/all_reviews.json" | while read -r pr_json; do
        output=$(process_pr "$pr_json" "code-review")
        echo "- $output"
        SECTION+="- $output\n"
    done
    echo
    REPORT_SECTIONS+="$SECTION\n"
fi

# Summary
total=$((authored_count + review_count))
if [ "$total" -eq 0 ]; then
    echo -e "${YELLOW}No GitHub activity found for ${DATE}${NC}"
else
    echo -e "${GREEN}Total: ${authored_count} PRs authored, ${review_count} PRs reviewed/commented${NC}"
    
    # Show breakdown if we have both reviews and comments
    reviewed_count=$(jq 'length' "$TEMP_DIR/reviewed.json")
    commented_only_count=$(jq 'length' "$TEMP_DIR/commented_only.json")
    if [ "$commented_only_count" -gt 0 ] && [ "$reviewed_count" -gt 0 ]; then
        echo -e "${CYAN}  (${reviewed_count} formal reviews, ${commented_only_count} comment-only interactions)${NC}"
    fi
    
    # Copy to clipboard if available
    if command -v pbcopy &> /dev/null; then
        {
            echo "## Daily GitHub Activity Summary"
            echo "Date: ${DATE}"
            echo
            
            # Re-process for clean clipboard output
            if [ "$authored_count" -gt 0 ]; then
                echo "### Implementation (Authored PRs)"
                jq -c '.[]' "$TEMP_DIR/authored.json" | while read -r pr_json; do
                    output=$(process_pr "$pr_json" "impl")
                    echo "- $output"
                done
                echo
            fi
            
            if [ "$review_count" -gt 0 ]; then
                echo "### Code Reviews & Comments"
                jq -c '.[]' "$TEMP_DIR/all_reviews.json" | while read -r pr_json; do
                    output=$(process_pr "$pr_json" "code-review")
                    echo "- $output"
                done
            fi
        } | pbcopy
        
        echo -e "\n${YELLOW}✓ Report copied to clipboard!${NC}"
    fi
fi

# Tips
echo -e "\n${PURPLE}Tips:${NC}"
echo -e "  • This version includes PRs where you only left comments (not formal reviews)"
echo -e "  • Run without arguments for today's report: ${BLUE}./$(basename "$0")${NC}"
echo -e "  • Specify a date: ${BLUE}./$(basename "$0") 2025-06-18${NC}"
echo -e "  • Add as alias: ${BLUE}alias daily-report='$(pwd)/$(basename "$0")'${NC}"