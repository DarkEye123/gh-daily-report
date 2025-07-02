#!/bin/bash

# Date utility functions for GitHub Daily Report

# Function to get the previous working day
# Input: date in format YYYY-MM-DD (optional, defaults to today)
# Output: previous working day in format YYYY-MM-DD
get_previous_working_day() {
    local base_date="${1:-$(date +%Y-%m-%d)}"
    
    # Convert to timestamp
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        local timestamp=$(date -d "$base_date" +%s 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "Error: Invalid date '$base_date'" >&2
            return 1
        fi
        local day_of_week=$(date -d "$base_date" +%u 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "Error: Cannot determine day of week for '$base_date'" >&2
            return 1
        fi
    else
        # BSD date (macOS)
        local timestamp=$(date -j -f "%Y-%m-%d" "$base_date" +%s 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "Error: Invalid date '$base_date'" >&2
            return 1
        fi
        local day_of_week=$(date -j -f "%Y-%m-%d" "$base_date" +%u 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "Error: Cannot determine day of week for '$base_date'" >&2
            return 1
        fi
    fi
    
    # Calculate days to subtract
    local days_to_subtract=1
    if [ "$day_of_week" -eq 1 ]; then
        # Monday -> Friday
        days_to_subtract=3
    elif [ "$day_of_week" -eq 7 ]; then
        # Sunday -> Friday
        days_to_subtract=2
    fi
    
    # Calculate new timestamp (86400 seconds = 1 day)
    # Using UTC to avoid DST issues
    local new_timestamp=$((timestamp - (days_to_subtract * 86400)))
    
    # Convert back to date
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        date -d "@$new_timestamp" +%Y-%m-%d 2>/dev/null || {
            echo "Error: Cannot convert timestamp to date" >&2
            return 1
        }
    else
        # BSD date (macOS)
        date -r "$new_timestamp" +%Y-%m-%d 2>/dev/null || {
            echo "Error: Cannot convert timestamp to date" >&2
            return 1
        }
    fi
}

# Function to parse various date formats
# Input: date string (YYYY-MM-DD, DD-MM-YYYY, "today", "yesterday")
# Output: normalized date in YYYY-MM-DD format
parse_date() {
    local input="$1"
    
    case "$input" in
        "today")
            date +%Y-%m-%d
            ;;
        "yesterday")
            get_previous_working_day "$(date +%Y-%m-%d)"
            ;;
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            # Already in YYYY-MM-DD format
            echo "$input"
            ;;
        [0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9])
            # Slovak format DD-MM-YYYY
            local day=$(echo "$input" | cut -d'-' -f1)
            local month=$(echo "$input" | cut -d'-' -f2)
            local year=$(echo "$input" | cut -d'-' -f3)
            echo "${year}-${month}-${day}"
            ;;
        "")
            # No input, default to previous working day
            get_previous_working_day
            ;;
        *)
            echo "Error: Invalid date format: $input" >&2
            echo "Supported formats: YYYY-MM-DD, DD-MM-YYYY, 'today', 'yesterday'" >&2
            return 1
            ;;
    esac
}

# Function to validate date
# Input: date in YYYY-MM-DD format
# Output: 0 if valid, 1 if invalid
validate_date() {
    local date_str="$1"
    
    # Check format
    if ! [[ "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        return 1
    fi
    
    # Extract components for basic validation
    local year="${date_str:0:4}"
    local month="${date_str:5:2}"
    local day="${date_str:8:2}"
    
    # Remove leading zeros for arithmetic
    month=$((10#$month))
    day=$((10#$day))
    
    # Basic range checks
    if (( month < 1 || month > 12 )); then
        return 1
    fi
    if (( day < 1 || day > 31 )); then
        return 1
    fi
    
    # Check if date is valid using date command
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        date -d "$date_str" >/dev/null 2>&1
    else
        # BSD date (macOS)
        date -j -f "%Y-%m-%d" "$date_str" >/dev/null 2>&1
    fi
}

# Function to get day of week name
# Input: date in YYYY-MM-DD format
# Output: day name (Monday, Tuesday, etc.)
get_day_name() {
    local date_str="$1"
    
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        date -d "$date_str" +%A
    else
        # BSD date (macOS)
        date -j -f "%Y-%m-%d" "$date_str" +%A
    fi
}