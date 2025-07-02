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

# Create test data directory if it doesn't exist
TEST_DATA_DIR="${SCRIPT_DIR}/test-data"
mkdir -p "$TEST_DATA_DIR"

# Function to run a test
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_RUN++))
    echo -n "Running test: $test_name... "
    
    # Run test in subshell to prevent it from affecting global state
    if (eval "$test_function" >/dev/null 2>&1); then
        echo -e "${GREEN}PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAILED${NC}"
        ((TESTS_FAILED++))
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
    echo '{"login": "testuser"}'
    exit 0
fi

if [ "$1" = "search" ] && [ "$2" = "prs" ]; then
    # Return mock PR data based on the query
    if [[ "$*" == *"author:@me"* ]]; then
        cat "$TEST_DATA_DIR/authored-prs.json"
    elif [[ "$*" == *"reviewed-by:@me"* ]]; then
        cat "$TEST_DATA_DIR/reviewed-prs.json"
    fi
    exit 0
fi

if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
    # Return appropriate mock data based on the query
    if [[ "$*" == *"timelineItems"* ]]; then
        cat "$TEST_DATA_DIR/timeline-items.json"
    elif [[ "$*" == *"reviews"* ]]; then
        cat "$TEST_DATA_DIR/pr-reviews.json"
    elif [[ "$*" == *"refs"* ]]; then
        cat "$TEST_DATA_DIR/commits.json"
    else
        echo '{"data": {}}'
    fi
    exit 0
fi

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    # Return mock PR view data
    echo '{"headRefName": "feature/test-branch"}'
    exit 0
fi

# Default response
echo '[]'
EOF
    chmod +x "$MOCK_DIR/gh"
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
    "headRefName": "fix/bug-fix",
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

    # Mock commits
    cat > "$TEST_DATA_DIR/commits.json" << 'EOF'
{
  "data": {
    "repository": {
      "refs": {
        "nodes": [
          {
            "name": "main",
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
                    "message": "fix: standalone commit",
                    "author": {
                      "name": "Test User",
                      "email": "test@example.com",
                      "user": {"login": "testuser"}
                    },
                    "authoredDate": "2025-07-01T15:00:00Z",
                    "associatedPullRequests": {
                      "nodes": []
                    }
                  }
                ]
              }
            }
          }
        ]
      }
    }
  }
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
    
    # Check that PR #123 appears only once (in Opened PRs, not in Reviews)
    local count_123=$(echo "$output" | grep -c "PR #123" || true)
    
    # PR #123 should appear only in the Opened PRs section
    if [ "$count_123" -eq 1 ]; then
        return 0
    else
        echo "Expected PR #123 to appear once, but found $count_123 occurrences" >&2
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
run_test "Empty date defaults to previous working day" test_empty_date_default

# Deduplication tests
run_test "PR deduplication across sections" test_deduplication

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