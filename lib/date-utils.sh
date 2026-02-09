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

# Function to get day of week number
# Input: date in YYYY-MM-DD format
# Output: day number (1=Monday, ..., 7=Sunday)
get_day_number() {
    local date_str="$1"

    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        date -d "$date_str" +%u 2>/dev/null || {
            echo "Error: Cannot determine day of week for '$date_str'" >&2
            return 1
        }
    else
        # BSD date (macOS)
        date -j -f "%Y-%m-%d" "$date_str" +%u 2>/dev/null || {
            echo "Error: Cannot determine day of week for '$date_str'" >&2
            return 1
        }
    fi
}

# Function to add (or subtract) days to a date
# Input: base date in YYYY-MM-DD format, integer days to add (can be negative)
# Output: resulting date in YYYY-MM-DD format
add_days() {
    local base_date="$1"
    local days="$2"

    if ! [[ "$days" =~ ^-?[0-9]+$ ]]; then
        echo "Error: Invalid day offset '$days'" >&2
        return 1
    fi

    # Normalize "-0" to "0" to avoid passing invalid offsets to BSD `date -v`.
    if [ "$days" = "-0" ]; then
        days="0"
    fi

    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        local relative
        if [ "$days" -ge 0 ]; then
            relative="+${days} days"
        else
            relative="${days} days"
        fi
        date -d "$base_date $relative" +%Y-%m-%d 2>/dev/null || {
            echo "Error: Cannot add days to '$base_date'" >&2
            return 1
        }
    else
        # BSD date (macOS)
        if [ "$days" -ge 0 ]; then
            date -j -f "%Y-%m-%d" -v+"${days}"d "$base_date" +%Y-%m-%d 2>/dev/null || {
                echo "Error: Cannot add days to '$base_date'" >&2
                return 1
            }
        else
            local abs_days=$(( -days ))
            date -j -f "%Y-%m-%d" -v-"${abs_days}"d "$base_date" +%Y-%m-%d 2>/dev/null || {
                echo "Error: Cannot add days to '$base_date'" >&2
                return 1
            }
        fi
    fi
}

# Function to compute report date range.
# If the base date is Friday/Saturday/Sunday, the range starts on that Friday and extends to Sunday,
# capped to "today" (to avoid future dates).
# Input: base date in YYYY-MM-DD format, optional today in YYYY-MM-DD format (defaults to system today)
# Output: "<start_date> <end_date>"
get_report_date_range() {
    local base_date="$1"
    local today_date="${2:-$(date +%Y-%m-%d)}"

    if ! validate_date "$base_date"; then
        echo "Error: Invalid date '$base_date'" >&2
        return 1
    fi

    if ! validate_date "$today_date"; then
        echo "Error: Invalid date '$today_date'" >&2
        return 1
    fi

    local start_date="$base_date"
    local end_date="$base_date"

    local day_number
    day_number=$(get_day_number "$base_date") || return 1

    # Friday/Saturday/Sunday -> include the whole weekend (starting Friday)
    if [ "$day_number" -ge 5 ]; then
        local days_since_friday=$((day_number - 5))
        if [ "$days_since_friday" -eq 0 ]; then
            start_date="$base_date"
        else
            start_date=$(add_days "$base_date" "-$days_since_friday") || return 1
        fi
        end_date=$(add_days "$start_date" 2) || return 1

        # Cap to today to avoid searching future days (e.g., running on Saturday and base is Friday).
        if [[ "$end_date" > "$today_date" ]]; then
            end_date="$today_date"
        fi

        # Guard against invalid ranges when the computed weekend is in the future.
        if [[ "$end_date" < "$start_date" ]]; then
            end_date="$start_date"
        fi
    fi

    echo "$start_date $end_date"
}
