#!/bin/bash

# Test suite for GitHub Daily Report Generator
# This script tests the functionality with mocked GitHub API responses

set -e

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Source directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/date-utils.sh"

# Create test fixtures in a temp dir (avoid polluting repo working tree)
TEST_TMP_DIR=$(mktemp -d)
TEST_DATA_DIR="${TEST_TMP_DIR}/test-data"
mkdir -p "$TEST_DATA_DIR"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT

# Function to run a test
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Running test: $test_name... "
    
    # Run test in subshell to prevent it from affecting global state
    if (eval "$test_function" >/dev/null 2>&1); then
        echo -e "${GREEN}PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAILED${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Function to create mock gh command
setup_mock_gh() {
    # Create a temporary directory for our mock
    export MOCK_DIR=$(mktemp -d)
    export ORIGINAL_PATH="$PATH"
    export PATH="$MOCK_DIR:$PATH"
    
    # Create mock gh script
    cat > "$MOCK_DIR/gh" << 'EOF'
#!/bin/bash
# Mock gh command for testing

# Parse the command
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
    if [[ "$*" == *"--jq"* ]]; then
        if [[ "$*" == *".name"* ]]; then
            echo "Test User"
        else
            echo "testuser"
        fi
    else
        echo '{"login": "testuser", "name": "Test User"}'
    fi
    exit 0
fi

if [ "$1" = "search" ] && [ "$2" = "prs" ]; then
    # Return mock PR data based on the query
    if [[ "$*" == *"is:merged"* ]]; then
        cat "$TEST_DATA_DIR/merged-prs.json"
    elif [[ "$*" == *"reviewed-by:@me"* ]]; then
        cat "$TEST_DATA_DIR/reviewed-prs.json"
    elif [[ "$*" == *"author:@me"* ]] || [[ "$*" == *"--author @me"* ]]; then
        if [ -n "$AUTHORED_SEARCH_CALLS_FILE" ]; then
            echo "$*" >> "$AUTHORED_SEARCH_CALLS_FILE"
        fi
        if [[ "$*" == *"--repo test/repo-a"* ]] && [ -f "$TEST_DATA_DIR/authored-prs-repo-a.json" ]; then
            cat "$TEST_DATA_DIR/authored-prs-repo-a.json"
        elif [[ "$*" == *"--repo test/repo-b"* ]] && [ -f "$TEST_DATA_DIR/authored-prs-repo-b.json" ]; then
            cat "$TEST_DATA_DIR/authored-prs-repo-b.json"
        else
            cat "$TEST_DATA_DIR/authored-prs.json"
        fi
    else
        echo "[]"
    fi
    exit 0
fi

if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
    # Return appropriate mock data based on the query
    repo_name=""
    for arg in "$@"; do
        case "$arg" in
            name=*)
                repo_name="${arg#name=}"
                ;;
        esac
    done

    if [[ "$*" == *"mergedBy"* ]]; then
        cat "$TEST_DATA_DIR/merged-pr-search-graphql.json"
    elif [[ "$*" == *".data.search.nodes"* ]]; then
        echo "[]"
    elif [[ "$*" == *"timelineItems"* ]]; then
        cat "$TEST_DATA_DIR/timeline-items.json"
    elif [[ "$*" == *"reviews(first: 100)"* ]]; then
        cat "$TEST_DATA_DIR/pr-reviews.json"
    elif [[ "$*" == *"type: ISSUE"* ]]; then
        cat "$TEST_DATA_DIR/comment-search.json"
    elif [[ "$*" == *"refs(refPrefix: \"refs/heads/\""* ]]; then
        if [ -n "$repo_name" ] && [ -f "$TEST_DATA_DIR/branches-${repo_name}.json" ]; then
            cat "$TEST_DATA_DIR/branches-${repo_name}.json"
        else
            cat "$TEST_DATA_DIR/branches.json"
        fi
    elif [[ "$*" == *"history(first: 50"* ]]; then
        if [ -n "$repo_name" ] && [ -f "$TEST_DATA_DIR/commits-by-branch-${repo_name}.json" ]; then
            cat "$TEST_DATA_DIR/commits-by-branch-${repo_name}.json"
        else
            cat "$TEST_DATA_DIR/commits-by-branch.json"
        fi
    else
        echo '{"data": {}}'
    fi
    exit 0
fi

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    # Return mock PR view data
    if [[ "$*" == *"--json number,title,url,headRefName,commits"* ]]; then
        cat "$TEST_DATA_DIR/merged-pr-view.json"
    elif [[ "$*" == *"-q"* ]]; then
        echo "feature/test-branch"
    else
        echo '{"headRefName": "feature/test-branch"}'
    fi
    exit 0
fi

# Default response
echo '[]'
EOF
    chmod +x "$MOCK_DIR/gh"

    cat > "$MOCK_DIR/pbcopy" << 'EOF'
#!/bin/bash
cat > "$TEST_DATA_DIR/clipboard.txt"
EOF
    chmod +x "$MOCK_DIR/pbcopy"

    cat > "$MOCK_DIR/curl" << 'EOF'
#!/bin/bash
if [ -n "$CURL_CALLS_FILE" ]; then
    echo "$*" >> "$CURL_CALLS_FILE"
fi
echo '{"data":{"issue":{"title":"Mock Linear issue"}}}'
EOF
    chmod +x "$MOCK_DIR/curl"
}

# Function to clean up mock
cleanup_mock_gh() {
    export PATH="$ORIGINAL_PATH"
    rm -rf "$MOCK_DIR"
}

# Test: Date parsing with Slovak format
test_slovak_date_format() {
    local result=$(parse_date "01-07-2025")
    [ "$result" = "2025-07-01" ]
}

# Test: Date parsing with today keyword
test_today_keyword() {
    local result=$(parse_date "today")
    local expected=$(date +%Y-%m-%d)
    [ "$result" = "$expected" ]
}

# Test: Date parsing with yesterday keyword (should return previous working day)
test_yesterday_keyword() {
    local result=$(parse_date "yesterday")
    local expected=$(get_previous_working_day)
    [ "$result" = "$expected" ]
}

# Test: Previous working day calculation for Monday
test_previous_working_day_monday() {
    # Test with a known Monday (2025-07-07)
    local result=$(get_previous_working_day "2025-07-07")
    [ "$result" = "2025-07-04" ]  # Should return Friday
}

# Test: Previous working day calculation for Tuesday
test_previous_working_day_tuesday() {
    # Test with a known Tuesday (2025-07-08)
    local result=$(get_previous_working_day "2025-07-08")
    [ "$result" = "2025-07-07" ]  # Should return Monday
}

# Test: Invalid date format
test_invalid_date_format() {
    local result=$(parse_date "invalid-date" 2>&1)
    [[ "$result" == *"Error: Invalid date format"* ]]
}

# Test: Friday date range expands to include weekend (full weekend available)
test_friday_includes_weekend_range() {
    local range
    range=$(get_report_date_range "2026-01-16" "2026-01-20") || return 1
    [ "$range" = "2026-01-16 2026-01-18" ]
}

# Test: Friday date range is capped to today (avoid future weekend days)
test_friday_range_capped_to_today() {
    local range
    range=$(get_report_date_range "2026-01-16" "2026-01-17") || return 1
    [ "$range" = "2026-01-16 2026-01-17" ]
}

# Test: Saturday expands to include Friday + Saturday (and not Sunday if it's in the future)
test_saturday_includes_friday_range_capped() {
    local range
    range=$(get_report_date_range "2026-01-17" "2026-01-17") || return 1
    [ "$range" = "2026-01-16 2026-01-17" ]
}

# Test: Sunday expands to include Friday + Saturday + Sunday
test_sunday_includes_full_weekend_range() {
    local range
    range=$(get_report_date_range "2026-01-18" "2026-01-18") || return 1
    [ "$range" = "2026-01-16 2026-01-18" ]
}

# Test: Non-Friday date stays single-day range
test_non_friday_single_day_range() {
    local range
    range=$(get_report_date_range "2026-01-15" "2026-01-20") || return 1
    [ "$range" = "2026-01-15 2026-01-15" ]
}

# Test: Friday in the future does not produce an invalid range
test_future_friday_does_not_reverse_range() {
    local range
    range=$(get_report_date_range "2026-01-23" "2026-01-17") || return 1
    [ "$range" = "2026-01-23 2026-01-23" ]
}

# Create mock data files
create_mock_data() {
    # Mock authored PRs
    cat > "$TEST_DATA_DIR/authored-prs.json" << 'EOF'
[
  {
    "number": 123,
    "title": "feat: add new feature",
    "url": "https://github.com/test/repo/pull/123",
    "repository": {"nameWithOwner": "test/repo"},
    "author": {"login": "testuser"},
    "headRefName": "feature/CHE-123-new-feature",
    "createdAt": "2025-07-01T10:00:00Z"
  },
  {
    "number": 124,
    "title": "fix: bug fix",
    "url": "https://github.com/test/repo/pull/124",
    "repository": {"nameWithOwner": "test/repo"},
    "author": {"login": "testuser"},
    "headRefName": "feature/main-task",
    "createdAt": "2025-07-01T11:00:00Z"
  }
]
EOF

    # Mock reviewed PRs (including duplicates that should be filtered)
    cat > "$TEST_DATA_DIR/reviewed-prs.json" << 'EOF'
[
  {
    "number": 123,
    "title": "feat: add new feature",
    "url": "https://github.com/test/repo/pull/123",
    "repository": {"nameWithOwner": "test/repo"},
    "author": {"login": "testuser"},
    "headRefName": "feature/CHE-123-new-feature"
  },
  {
    "number": 125,
    "title": "chore: update deps",
    "url": "https://github.com/test/repo/pull/125",
    "repository": {"nameWithOwner": "test/repo"},
    "author": {"login": "otheruser"},
    "headRefName": "chore/update-deps"
  }
]
EOF

    # Mock timeline items
    cat > "$TEST_DATA_DIR/timeline-items.json" << 'EOF'
{
  "data": {
    "repository": {
      "pullRequest": {
        "timelineItems": {
          "nodes": [
            {
              "__typename": "IssueComment",
              "author": {"login": "testuser"},
              "createdAt": "2025-07-01T12:00:00Z"
            }
          ]
        }
      }
    }
  }
}
EOF

    # Mock PR reviews
    cat > "$TEST_DATA_DIR/pr-reviews.json" << 'EOF'
{
  "data": {
    "repository": {
      "pullRequest": {
        "reviews": {
          "nodes": [
            {
              "author": {"login": "testuser"},
              "createdAt": "2025-07-01T13:00:00Z"
            }
          ]
        }
      }
    }
  }
}
EOF

    # Mock comment search response
    cat > "$TEST_DATA_DIR/comment-search.json" << 'EOF'
{
  "data": {
    "search": {
      "nodes": []
    }
  }
}
EOF

    # Mock branch listing response
    cat > "$TEST_DATA_DIR/branches.json" << 'EOF'
{
  "data": {
    "repository": {
      "refs": {
        "pageInfo": {
          "hasNextPage": false,
          "endCursor": null
        },
        "nodes": [
          {
            "name": "feature/main-task",
            "target": {
              "__typename": "Commit",
              "committedDate": "2025-07-01T15:00:00Z"
            }
          }
        ]
      }
    }
  }
}
EOF

    # Mock commits-by-branch response
    cat > "$TEST_DATA_DIR/commits-by-branch.json" << 'EOF'
{
  "data": {
    "repository": {
      "ref": {
        "name": "feature/main-task",
        "target": {
          "history": {
            "nodes": [
              {
                "oid": "abc123def456",
                "message": "feat: add new feature\n\nDetailed description",
                "author": {
                  "name": "Test User",
                  "email": "test@example.com",
                  "user": {"login": "testuser"}
                },
                "authoredDate": "2025-07-01T14:00:00Z",
                "associatedPullRequests": {
                  "nodes": [
                    {
                      "number": 123,
                      "title": "feat: add new feature",
                      "url": "https://github.com/test/repo/pull/123",
                      "headRefName": "feature/CHE-123-new-feature"
                    }
                  ]
                }
              },
              {
                "oid": "def789ghi012",
                "message": "fix: CHEV4-1961 locale subtask",
                "author": {
                  "name": "Test User",
                  "email": "test@example.com",
                  "user": {"login": "testuser"}
                },
                "authoredDate": "2025-07-01T15:00:00Z",
                "associatedPullRequests": {
                  "nodes": [
                    {
                      "number": 124,
                      "title": "fix: bug fix",
                      "url": "https://github.com/test/repo/pull/124",
                      "headRefName": "feature/main-task"
                    }
                  ]
                }
              }
            ]
          }
        }
      }
    }
  }
}
EOF

    # Mock merged PR search response
    cat > "$TEST_DATA_DIR/merged-prs.json" << 'EOF'
[]
EOF

    # Mock merged PR GraphQL search response
    cat > "$TEST_DATA_DIR/merged-pr-search-graphql.json" << 'EOF'
{
  "data": {
    "search": {
      "nodes": []
    }
  }
}
EOF

    # Mock merged PR detail response
    cat > "$TEST_DATA_DIR/merged-pr-view.json" << 'EOF'
{
  "number": 0,
  "title": "",
  "url": "",
  "headRefName": "",
  "commits": []
}
EOF
}

# Test: Run script with deduplication
test_deduplication() {
    setup_mock_gh
    create_mock_data
    
    # Export test data dir for mock gh to find it
    export TEST_DATA_DIR
    
    # Run the script with a specific date
    local output=$("${SCRIPT_DIR}/github-daily-report.sh" "2025-07-01" 2>&1 || true)
    
    cleanup_mock_gh
    
    # Check that PR #123 appears only once (in Pull Requests Created, not in Reviews)
    local count_123=$(echo "$output" | grep -c "PR #123" || true)
    
    # PR #123 should appear only in the Pull Requests Created section
    if [ "$count_123" -eq 1 ]; then
        return 0
    else
        echo "Expected PR #123 to appear once, but found $count_123 occurrences" >&2
        return 1
    fi
}

# Test: authored PR searches cover each configured repository and retain all states
test_authored_prs_are_collected_per_repository() {
    setup_mock_gh
    create_mock_data

    cat > "$TEST_DATA_DIR/authored-prs-repo-a.json" << 'EOF'
[
  {
    "number": 301,
    "title": "feat: merged work",
    "url": "https://github.com/test/repo-a/pull/301",
    "repository": {"nameWithOwner": "test/repo-a"},
    "author": {"login": "testuser"},
    "headRefName": "feature/merged",
    "createdAt": "2025-07-01T09:00:00Z",
    "state": "MERGED"
  }
]
EOF
    cat > "$TEST_DATA_DIR/authored-prs-repo-b.json" << 'EOF'
[
  {
    "number": 302,
    "title": "feat: open work",
    "url": "https://github.com/test/repo-b/pull/302",
    "repository": {"nameWithOwner": "test/repo-b"},
    "author": {"login": "testuser"},
    "headRefName": "feature/open",
    "createdAt": "2025-07-01T10:00:00Z",
    "state": "OPEN"
  }
]
EOF

    export TEST_DATA_DIR
    export GITHUB_REPOS="test/repo-a test/repo-b"
    export AUTHORED_SEARCH_CALLS_FILE="$TEST_DATA_DIR/authored-search-calls.txt"

    local output=$("${SCRIPT_DIR}/github-daily-report.sh" "2025-07-01" 2>&1 || true)
    local search_calls=$(cat "$AUTHORED_SEARCH_CALLS_FILE")

    rm -f "$TEST_DATA_DIR/authored-prs-repo-a.json" "$TEST_DATA_DIR/authored-prs-repo-b.json"
    unset GITHUB_REPOS
    unset AUTHORED_SEARCH_CALLS_FILE
    cleanup_mock_gh

    if [[ "$output" == *"### Pull Requests Created"* ]] &&
       [[ "$output" == *"PR #301"* ]] &&
       [[ "$output" == *"PR #302"* ]] &&
       [[ "$search_calls" == *"--repo test/repo-a"* ]] &&
       [[ "$search_calls" == *"--repo test/repo-b"* ]] &&
       [[ "$search_calls" != *"--state"* ]]; then
        return 0
    else
        echo "Expected per-repository authored PR searches without a state filter" >&2
        return 1
    fi
}

# Test: Keep commit entry when it adds a different ticket than PR/branch context
test_commit_subtask_ticket_visible() {
    setup_mock_gh
    create_mock_data

    # Export test data dir for mock gh to find it
    export TEST_DATA_DIR

    # Run the script with a specific date
    local output=$("${SCRIPT_DIR}/github-daily-report.sh" "2025-07-01" 2>&1 || true)

    cleanup_mock_gh

    # Commit message contains CHEV4-1961 even though PR/branch do not
    if [[ "$output" == *"CHEV4-1961"* ]]; then
        return 0
    else
        echo "Expected CHEV4-1961 from commit message to appear in report output" >&2
        return 1
    fi
}

# Test: Clipboard output uses raw Linear URLs without resolving tickets
test_clipboard_uses_raw_linear_urls() {
    setup_mock_gh
    create_mock_data

    export TEST_DATA_DIR
    export LINEAR_API_KEY="test-key"
    export CURL_CALLS_FILE="$TEST_DATA_DIR/curl-calls.txt"

    "${SCRIPT_DIR}/github-daily-report.sh" "2025-07-01" >/dev/null 2>&1 || true
    local clipboard_content=$(cat "$TEST_DATA_DIR/clipboard.txt")

    unset LINEAR_API_KEY
    unset CURL_CALLS_FILE
    cleanup_mock_gh

    if [[ "$clipboard_content" == *"### Pull Requests Created"* ]] &&
       [[ "$clipboard_content" == *"- "* ]] &&
       [[ "$clipboard_content" == *"https://linear.app/ventrata/issue/CHEV4-1961"* ]] &&
       [[ "$clipboard_content" != *"[CHEV4-"* ]] &&
       [[ "$clipboard_content" == *"[PR #"* ]] &&
       [[ "$clipboard_content" == *"]("* ]] &&
       [[ "$clipboard_content" != *"•"* ]] &&
       [[ ! -e "$TEST_DATA_DIR/curl-calls.txt" ]]; then
        return 0
    else
        echo "Expected clipboard output to use raw Linear URLs without API calls" >&2
        return 1
    fi
}

test_linear_ticket_link_includes_title() {
    setup_mock_gh
    create_mock_data

    export TEST_DATA_DIR
    export LINEAR_API_KEY="test-key"

    "${SCRIPT_DIR}/github-daily-report.sh" "2025-07-01" --resolve-linear >/dev/null 2>&1 || true
    local clipboard_content=$(cat "$TEST_DATA_DIR/clipboard.txt")

    unset LINEAR_API_KEY
    cleanup_mock_gh

    [[ "$clipboard_content" == *"[CHEV4-1961: Mock Linear issue](https://linear.app/ventrata/issue/CHEV4-1961)"* ]]
}

# Test: Single-repository reports omit the redundant repository slug
test_single_repository_branch_summary_omits_repository_slug() {
    setup_mock_gh
    create_mock_data

    export TEST_DATA_DIR
    export GITHUB_REPOS="test/repo"

    local output=$("${SCRIPT_DIR}/github-daily-report.sh" "2025-07-01" 2>&1 || true)

    unset GITHUB_REPOS
    cleanup_mock_gh

    if [[ "$output" == *"development on \`feature/main-task\`"* ]] &&
       [[ "$output" != *"\`repo\`"* ]]; then
        return 0
    else
        echo "Expected single-repository branch summary to omit repository slug" >&2
        return 1
    fi
}

# Test: Same branch names across repositories remain separate summaries
test_same_branch_name_kept_separate_per_repo() {
    setup_mock_gh
    create_mock_data

    cat > "$TEST_DATA_DIR/authored-prs.json" << 'EOF'
[]
EOF
    cat > "$TEST_DATA_DIR/reviewed-prs.json" << 'EOF'
[]
EOF
    cat > "$TEST_DATA_DIR/branches-repo-a.json" << 'EOF'
{
  "data": {
    "repository": {
      "refs": {
        "pageInfo": {
          "hasNextPage": false,
          "endCursor": null
        },
        "nodes": [
          {
            "name": "main",
            "target": {
              "__typename": "Commit",
              "committedDate": "2025-07-01T10:00:00Z"
            }
          }
        ]
      }
    }
  }
}
EOF
    cat > "$TEST_DATA_DIR/branches-repo-b.json" << 'EOF'
{
  "data": {
    "repository": {
      "refs": {
        "pageInfo": {
          "hasNextPage": false,
          "endCursor": null
        },
        "nodes": [
          {
            "name": "main",
            "target": {
              "__typename": "Commit",
              "committedDate": "2025-07-01T11:00:00Z"
            }
          }
        ]
      }
    }
  }
}
EOF
    cat > "$TEST_DATA_DIR/commits-by-branch-repo-a.json" << 'EOF'
{
  "data": {
    "repository": {
      "ref": {
        "name": "main",
        "target": {
          "history": {
            "nodes": [
              {
                "oid": "repoa111",
                "message": "chore: repo-a maintenance",
                "author": {
                  "name": "Test User",
                  "email": "test@example.com",
                  "user": {"login": "testuser"}
                },
                "authoredDate": "2025-07-01T10:00:00Z",
                "associatedPullRequests": {
                  "nodes": []
                }
              }
            ]
          }
        }
      }
    }
  }
}
EOF
    cat > "$TEST_DATA_DIR/commits-by-branch-repo-b.json" << 'EOF'
{
  "data": {
    "repository": {
      "ref": {
        "name": "main",
        "target": {
          "history": {
            "nodes": [
              {
                "oid": "repob222",
                "message": "chore: repo-b maintenance",
                "author": {
                  "name": "Test User",
                  "email": "test@example.com",
                  "user": {"login": "testuser"}
                },
                "authoredDate": "2025-07-01T11:00:00Z",
                "associatedPullRequests": {
                  "nodes": []
                }
              }
            ]
          }
        }
      }
    }
  }
}
EOF

    export TEST_DATA_DIR
    export GITHUB_REPOS="test/repo-a test/repo-b"

    local output=$("${SCRIPT_DIR}/github-daily-report.sh" "2025-07-01" 2>&1 || true)

    unset GITHUB_REPOS
    cleanup_mock_gh

    if [[ "$output" == *"Development in \`repo-a\` on \`main\`"* ]] &&
       [[ "$output" == *"Development in \`repo-b\` on \`main\`"* ]]; then
        return 0
    else
        echo "Expected separate main-branch summaries for repo-a and repo-b" >&2
        return 1
    fi
}

# Test: Seen branch deduplication is repository-aware
test_pr_seen_branch_does_not_hide_other_repo_branch() {
    setup_mock_gh
    create_mock_data

    cat > "$TEST_DATA_DIR/authored-prs.json" << 'EOF'
[
  {
    "number": 201,
    "title": "docs: update repo-a main",
    "url": "https://github.com/test/repo-a/pull/201",
    "repository": {"nameWithOwner": "test/repo-a"},
    "author": {"login": "testuser"},
    "headRefName": "main",
    "createdAt": "2025-07-01T09:00:00Z"
  }
]
EOF
    cat > "$TEST_DATA_DIR/reviewed-prs.json" << 'EOF'
[]
EOF
    cat > "$TEST_DATA_DIR/branches-repo-a.json" << 'EOF'
{
  "data": {
    "repository": {
      "refs": {
        "pageInfo": {
          "hasNextPage": false,
          "endCursor": null
        },
        "nodes": []
      }
    }
  }
}
EOF
    cat > "$TEST_DATA_DIR/branches-repo-b.json" << 'EOF'
{
  "data": {
    "repository": {
      "refs": {
        "pageInfo": {
          "hasNextPage": false,
          "endCursor": null
        },
        "nodes": [
          {
            "name": "main",
            "target": {
              "__typename": "Commit",
              "committedDate": "2025-07-01T11:00:00Z"
            }
          }
        ]
      }
    }
  }
}
EOF
    cat > "$TEST_DATA_DIR/commits-by-branch-repo-b.json" << 'EOF'
{
  "data": {
    "repository": {
      "ref": {
        "name": "main",
        "target": {
          "history": {
            "nodes": [
              {
                "oid": "repob333",
                "message": "chore: repo-b follow-up",
                "author": {
                  "name": "Test User",
                  "email": "test@example.com",
                  "user": {"login": "testuser"}
                },
                "authoredDate": "2025-07-01T11:00:00Z",
                "associatedPullRequests": {
                  "nodes": []
                }
              }
            ]
          }
        }
      }
    }
  }
}
EOF

    export TEST_DATA_DIR
    export GITHUB_REPOS="test/repo-a test/repo-b"

    local output=$("${SCRIPT_DIR}/github-daily-report.sh" "2025-07-01" 2>&1 || true)

    unset GITHUB_REPOS
    cleanup_mock_gh

    if [[ "$output" == *"[PR #201: docs: update repo-a main](https://github.com/test/repo-a/pull/201)"* ]] &&
       [[ "$output" == *"Development in \`repo-b\` on \`main\`"* ]]; then
        return 0
    else
        echo "Expected repo-b main commit summary to remain visible after repo-a main PR" >&2
        return 1
    fi
}

# Test: Include merged PR commit tickets even when branch commit lookup has no matches
test_merged_pr_commit_fallback_includes_subtasks() {
    setup_mock_gh
    create_mock_data

    # Ensure regular daily commit scan is empty.
    cat > "$TEST_DATA_DIR/authored-prs.json" << 'EOF'
[]
EOF
    cat > "$TEST_DATA_DIR/reviewed-prs.json" << 'EOF'
[]
EOF
    cat > "$TEST_DATA_DIR/branches.json" << 'EOF'
{
  "data": {
    "repository": {
      "refs": {
        "pageInfo": {
          "hasNextPage": false,
          "endCursor": null
        },
        "nodes": []
      }
    }
  }
}
EOF
    cat > "$TEST_DATA_DIR/commits-by-branch.json" << 'EOF'
{
  "data": {
    "repository": {
      "ref": {
        "name": "develop",
        "target": {
          "history": {
            "nodes": []
          }
        }
      }
    }
  }
}
EOF

    # Provide merged PR data with historical commits that still represent resolved tasks.
    cat > "$TEST_DATA_DIR/merged-pr-search-graphql.json" << 'EOF'
{
  "data": {
    "search": {
      "nodes": [
        {
          "number": 300,
          "title": "feat: merged work",
          "url": "https://github.com/test/repo/pull/300",
          "repository": {"nameWithOwner": "test/repo"},
          "author": {"login": "testuser"},
          "headRefName": "feature/CHE-300-main",
          "mergedBy": {"login": "testuser"}
        }
      ]
    }
  }
}
EOF
    cat > "$TEST_DATA_DIR/merged-pr-view.json" << 'EOF'
{
  "number": 300,
  "title": "feat: merged work",
  "url": "https://github.com/test/repo/pull/300",
  "headRefName": "feature/CHE-300-main",
  "commits": [
    {
      "oid": "aaa111",
      "messageHeadline": "feat: CHE-301 first subtask",
      "messageBody": "",
      "authoredDate": "2025-06-30T09:00:00Z",
      "authors": [
        {
          "login": "testuser",
          "name": "Test User",
          "email": "test@example.com"
        }
      ]
    },
    {
      "oid": "bbb222",
      "messageHeadline": "fix: CHE-302 second subtask",
      "messageBody": "",
      "authoredDate": "2025-06-30T10:00:00Z",
      "authors": [
        {
          "login": "testuser",
          "name": "Test User",
          "email": "test@example.com"
        }
      ]
    }
  ]
}
EOF

    export TEST_DATA_DIR

    unset LINEAR_API_KEY
    local output=$("${SCRIPT_DIR}/github-daily-report.sh" --resolve-linear "2025-07-01" 2>&1 || true)
    local resolved_clipboard=$(cat "$TEST_DATA_DIR/clipboard.txt")
    local expected_related=$'  related:\n    - [CHE-301](https://linear.app/ventrata/issue/CHE-301)\n    - [CHE-302](https://linear.app/ventrata/issue/CHE-302)'

    local raw_output=$("${SCRIPT_DIR}/github-daily-report.sh" "2025-07-01" 2>&1 || true)
    local raw_clipboard=$(cat "$TEST_DATA_DIR/clipboard.txt")
    local expected_raw_related=$'  related:\n    - https://linear.app/ventrata/issue/CHE-301\n    - https://linear.app/ventrata/issue/CHE-302'

    cleanup_mock_gh

    if [[ "$output" == *"[CHE-300](https://linear.app/ventrata/issue/CHE-300)"* && "$output" == *"$expected_related"* && "$output" == *"merged PR with 2 historical commits"* && "$output" == *"0 commits, 1 merged PR resolutions"* ]] &&
       [[ "$resolved_clipboard" == *"$expected_related"* ]] &&
       [[ "$raw_output" == *"$expected_raw_related"* ]] &&
       [[ "$raw_clipboard" == *"$expected_raw_related"* ]]; then
        return 0
    else
        echo "Expected merged PR fallback to include related ticket bullets in terminal and clipboard output, and merged-PR summary text" >&2
        return 1
    fi
}

# Test: Include merged PRs you merged even when authored by someone else
test_merged_by_user_includes_foreign_authored_pr() {
    setup_mock_gh
    create_mock_data

    cat > "$TEST_DATA_DIR/authored-prs.json" << 'EOF'
[]
EOF
    cat > "$TEST_DATA_DIR/reviewed-prs.json" << 'EOF'
[]
EOF
    cat > "$TEST_DATA_DIR/branches.json" << 'EOF'
{
  "data": {
    "repository": {
      "refs": {
        "pageInfo": {
          "hasNextPage": false,
          "endCursor": null
        },
        "nodes": []
      }
    }
  }
}
EOF
    cat > "$TEST_DATA_DIR/commits-by-branch.json" << 'EOF'
{
  "data": {
    "repository": {
      "ref": {
        "name": "develop",
        "target": {
          "history": {
            "nodes": []
          }
        }
      }
    }
  }
}
EOF
    cat > "$TEST_DATA_DIR/merged-pr-search-graphql.json" << 'EOF'
{
  "data": {
    "search": {
      "nodes": [
        {
          "number": 3277,
          "title": "Fix widget closing when resuming checkout from a specific page",
          "url": "https://github.com/test/repo/pull/3277",
          "repository": {"nameWithOwner": "test/repo"},
          "author": {"login": "ollym"},
          "headRefName": "fix-widget-closing",
          "mergedBy": {"login": "testuser"}
        }
      ]
    }
  }
}
EOF
    cat > "$TEST_DATA_DIR/merged-pr-view.json" << 'EOF'
{
  "number": 3277,
  "title": "Fix widget closing when resuming checkout from a specific page",
  "url": "https://github.com/test/repo/pull/3277",
  "headRefName": "fix-widget-closing",
  "commits": [
    {
      "oid": "91b7f44",
      "messageHeadline": "making QA happy again",
      "messageBody": "",
      "authoredDate": "2025-07-01T09:00:00Z",
      "authors": [
        {
          "login": "testuser",
          "name": "Test User",
          "email": "test@example.com"
        }
      ]
    }
  ]
}
EOF

    export TEST_DATA_DIR

    local output=$("${SCRIPT_DIR}/github-daily-report.sh" "2025-07-01" 2>&1 || true)

    cleanup_mock_gh

    if [[ "$output" == *"fix-widget-closing"* && "$output" == *"PR #3277"* && "$output" == *"0 commits, 1 merged PR resolutions"* ]]; then
        return 0
    else
        echo "Expected merged-by fallback to include PR #3277 from a different author" >&2
        return 1
    fi
}

# Test: Empty date defaults to previous working day
test_empty_date_default() {
    local current_day=$(date +%A)
    local expected_date=$(get_previous_working_day)
    
    # Create a minimal test script to check date parsing
    local test_script=$(mktemp)
    cat > "$test_script" << 'EOF'
#!/bin/bash
source "lib/date-utils.sh"
DATE=$(parse_date "")
echo "$DATE"
EOF
    chmod +x "$test_script"
    
    local result=$(cd "$SCRIPT_DIR" && "$test_script")
    rm -f "$test_script"
    
    [ "$result" = "$expected_date" ]
}

# Main test execution
echo -e "${BLUE}Running GitHub Daily Report Tests${NC}"
echo "================================="

# Date utility tests
run_test "Slovak date format parsing" test_slovak_date_format
run_test "Today keyword parsing" test_today_keyword
run_test "Yesterday keyword parsing" test_yesterday_keyword
run_test "Previous working day - Monday" test_previous_working_day_monday
run_test "Previous working day - Tuesday" test_previous_working_day_tuesday
run_test "Invalid date format handling" test_invalid_date_format
run_test "Friday expands to weekend range" test_friday_includes_weekend_range
run_test "Friday range capped to today" test_friday_range_capped_to_today
run_test "Saturday includes Friday (capped)" test_saturday_includes_friday_range_capped
run_test "Sunday includes full weekend" test_sunday_includes_full_weekend_range
run_test "Non-Friday stays single day range" test_non_friday_single_day_range
run_test "Future Friday does not reverse range" test_future_friday_does_not_reverse_range
run_test "Empty date defaults to previous working day" test_empty_date_default

# Deduplication tests
run_test "PR deduplication across sections" test_deduplication
run_test "Authored PRs are collected per repository" test_authored_prs_are_collected_per_repository
run_test "Commit subtask ticket appears from commit message" test_commit_subtask_ticket_visible
run_test "Clipboard uses raw Linear URLs" test_clipboard_uses_raw_linear_urls
run_test "Linear ticket links include issue titles" test_linear_ticket_link_includes_title
run_test "Single-repository branch summary omits repository slug" test_single_repository_branch_summary_omits_repository_slug
run_test "Same branch names stay separate per repository" test_same_branch_name_kept_separate_per_repo
run_test "Seen branch deduplication is repository-aware" test_pr_seen_branch_does_not_hide_other_repo_branch
run_test "Merged PR fallback includes resolved subtasks" test_merged_pr_commit_fallback_includes_subtasks
run_test "Merged-by fallback includes foreign-authored PRs" test_merged_by_user_includes_foreign_authored_pr

# Summary
echo
echo "================================="
echo -e "Tests run: ${TESTS_RUN}"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi
