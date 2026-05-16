#!/bin/bash
# Exa AI REST API Client
# Endpoints: /search, /contents, /findSimilar, /answer
# Docs: https://docs.exa.ai/reference

set -euo pipefail

readonly API_BASE="https://api.exa.ai"
readonly API_KEYS="${EXA_API_KEY:-}"
readonly KEY_STATE_FILE="${TMPDIR:-/tmp}/.exa-key-idx-${UID:-0}"
readonly KEY_LOCK_FILE="${TMPDIR:-/tmp}/.exa-key-lock"
readonly MAX_RETRIES=3
readonly BASE_DELAY=1

get_key_count() {
    [[ -z "$API_KEYS" ]] && { echo 0; return; }
    IFS=',' read -ra keys <<< "$API_KEYS"
    echo ${#keys[@]}
}

select_next_api_key() {
    [[ -z "$API_KEYS" ]] && return

    IFS=',' read -ra keys <<< "$API_KEYS"
    local count=${#keys[@]}

    [[ $count -eq 1 ]] && { echo "${keys[0]}"; return; }

    local idx=0
    (
        flock -w 1 200 2>/dev/null || true
        [[ -f "$KEY_STATE_FILE" ]] && idx=$(cat "$KEY_STATE_FILE" 2>/dev/null || echo 0)
        local next_idx=$(( (idx + 1) % count ))
        local tmp_file="${KEY_STATE_FILE}.tmp.$$"
        echo "$next_idx" > "$tmp_file" && mv "$tmp_file" "$KEY_STATE_FILE"
    ) 200>"$KEY_LOCK_FILE"

    [[ -f "$KEY_STATE_FILE" ]] && idx=$(cat "$KEY_STATE_FILE" 2>/dev/null || echo 0)
    idx=$(( (idx + count - 1) % count ))
    echo "${keys[$idx]}"
}

do_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local key_count attempts_per_round total_attempts max_attempts round
    key_count=$(get_key_count)
    attempts_per_round=$((key_count > 1 ? key_count : 1))
    total_attempts=0
    max_attempts=$((attempts_per_round * MAX_RETRIES))
    round=0

    while [[ $total_attempts -lt $max_attempts ]]; do
        local api_key http_code response
        api_key=$(select_next_api_key)

        if [[ -z "$api_key" ]]; then
            echo "ERROR: EXA_API_KEY not set. Get one at: https://dashboard.exa.ai/api-keys" >&2
            exit 1
        fi

        local -a curl_args=(-sS -w "%{http_code}" --max-time 30)
        curl_args+=(-H "x-api-key: $api_key")
        curl_args+=(-H "Content-Type: application/json")

        if [[ "$method" == "POST" && -n "$data" ]]; then
            curl_args+=(-X POST -d "$data")
        fi

        response=$(curl "${curl_args[@]}" "${API_BASE}${endpoint}" 2>/dev/null) || true
        http_code="${response: -3}"
        response="${response%???}"

        case "$http_code" in
            200) echo "$response"; return 0 ;;
            429|500|502|503|504|000)
                total_attempts=$((total_attempts + 1))
                if [[ $((total_attempts % attempts_per_round)) -eq 0 ]]; then
                    round=$((round + 1))
                    local delay=$((BASE_DELAY * (2 ** (round - 1))))
                    [[ $delay -gt 16 ]] && delay=16
                    sleep "$delay"
                fi
                ;;
            401)
                total_attempts=$((total_attempts + 1))
                if [[ $key_count -gt 1 && $total_attempts -lt $max_attempts ]]; then
                    continue
                fi
                echo "ERROR: Invalid API key(s). Check EXA_API_KEY." >&2
                return 1
                ;;
            400)
                echo "ERROR: Bad request - $response" >&2
                return 1
                ;;
            403)
                echo "ERROR: Forbidden - check API key permissions. $response" >&2
                return 1
                ;;
            *)
                echo "ERROR: HTTP $http_code - $response" >&2
                return 1
                ;;
        esac
    done

    echo "ERROR: Rate limited on all keys after $MAX_RETRIES retries" >&2
    return 1
}

# Search the web
# API: POST /search
cmd_search() {
    local query="" num_results=10 category="" search_type="auto"
    local start_date="" end_date="" include_domains="" exclude_domains=""
    local raw_output="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) search_type="$2"; shift 2 ;;
            --start-date) start_date="$2"; shift 2 ;;
            --end-date) end_date="$2"; shift 2 ;;
            --domains) include_domains="$2"; shift 2 ;;
            --exclude-domains) exclude_domains="$2"; shift 2 ;;
            --json) raw_output="true"; shift ;;
            -*)
                echo "Unknown option: $1" >&2; exit 1 ;;
            *)
                if [[ -z "$query" ]]; then query="$1"
                elif [[ "$1" =~ ^[0-9]+$ ]]; then num_results="$1"
                elif [[ -z "$category" ]]; then category="$1"
                fi
                shift ;;
        esac
    done

    if [[ -z "$query" ]]; then
        echo "Usage: exa.sh search <query> [numResults] [category] [options]"
        echo "Categories: company, research paper, news, personal site, financial report, people"
        echo "Options:"
        echo "  --type TYPE          auto|neural|keyword|deep|deep-reasoning|instant"
        echo "  --start-date DATE    Published after (ISO 8601, e.g. 2025-01-01T00:00:00.000Z)"
        echo "  --end-date DATE      Published before (ISO 8601)"
        echo "  --domains LIST       Comma-separated domains to include"
        echo "  --exclude-domains L  Comma-separated domains to exclude"
        echo "  --json               Output raw JSON response"
        echo "Example: exa.sh search \"latest LLM research\" 5 \"research paper\" --start-date 2025-01-01T00:00:00.000Z"
        exit 1
    fi

    local json_payload
    json_payload=$(jq -n \
        --arg query "$query" \
        --argjson numResults "$num_results" \
        --arg category "$category" \
        --arg search_type "$search_type" \
        --arg startDate "$start_date" \
        --arg endDate "$end_date" \
        --arg domains "$include_domains" \
        --arg excludeDomains "$exclude_domains" \
        '{
            query: $query,
            numResults: $numResults,
            type: $search_type,
            contents: {
                text: true,
                highlights: { numSentences: 3 }
            }
        }
        + (if $category != "" then {category: $category} else {} end)
        + (if $startDate != "" then {startPublishedDate: $startDate} else {} end)
        + (if $endDate != "" then {endPublishedDate: $endDate} else {} end)
        + (if $domains != "" then {includeDomains: ($domains | split(","))} else {} end)
        + (if $excludeDomains != "" then {excludeDomains: ($excludeDomains | split(","))} else {} end)'
    )

    local response
    if ! response=$(do_request "POST" "/search" "$json_payload"); then
        echo "ERROR: Search failed." >&2
        exit 1
    fi

    if [[ "$raw_output" == "true" ]]; then
        echo "$response"
        return 0
    fi

    echo "$response" | jq -r '
        if .results and (.results | length > 0) then
            "\(.results | length) results:\n" +
            (.results | to_entries | map(
                "\(.key + 1). \(.value.title // "No title")\n   URL: \(.value.url)\n   Published: \(.value.publishedDate // "unknown")\n" +
                (if .value.highlights then "   Highlights: " + (.value.highlights | join(" | ")) + "\n" else "" end) +
                "   \(.value.text // "")"
            ) | join("\n\n"))
        elif .error then
            "ERROR: " + .error
        else
            "No results found."
        end
    ' 2>/dev/null || echo "$response"
}

# Get page contents
# API: POST /contents
cmd_contents() {
    local raw_output="false" highlights="false" summary="false"
    local max_chars="" subpages=0
    local -a urls=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-chars) max_chars="$2"; shift 2 ;;
            --highlights) highlights="true"; shift ;;
            --summary) summary="true"; shift ;;
            --subpages) subpages="$2"; shift 2 ;;
            --json) raw_output="true"; shift ;;
            -*) echo "Unknown option: $1" >&2; exit 1 ;;
            *) urls+=("$1"); shift ;;
        esac
    done

    if [[ ${#urls[@]} -eq 0 ]]; then
        echo "Usage: exa.sh contents <url1> [url2] ... [options]"
        echo "Options:"
        echo "  --max-chars N    Max characters per page"
        echo "  --highlights     Return key excerpts (10x more token-efficient)"
        echo "  --summary        Return LLM-generated summary"
        echo "  --subpages N     Number of subpages to crawl per URL"
        echo "  --json           Output raw JSON response"
        echo "Example: exa.sh contents \"https://arxiv.org/abs/2307.06435\" --highlights"
        exit 1
    fi

    local urls_array
    urls_array=$(printf '%s\n' "${urls[@]}" | jq -R . | jq -s .)

    local text_config
    if [[ -n "$max_chars" ]]; then
        text_config="{\"maxCharacters\": $max_chars}"
    else
        text_config="true"
    fi

    local json_payload
    json_payload=$(jq -n \
        --argjson urls "$urls_array" \
        --argjson text "$text_config" \
        --arg highlights "$highlights" \
        --arg summary "$summary" \
        --argjson subpages "$subpages" \
        '{urls: $urls, text: $text}
        + (if $highlights == "true" then {highlights: true} else {} end)
        + (if $summary == "true" then {summary: true} else {} end)
        + (if $subpages > 0 then {subpages: $subpages} else {} end)'
    )

    local response
    if ! response=$(do_request "POST" "/contents" "$json_payload"); then
        echo "ERROR: Failed to fetch contents." >&2
        exit 1
    fi

    if [[ "$raw_output" == "true" ]]; then
        echo "$response"
        return 0
    fi

    echo "$response" | jq -r '
        if .results and (.results | length > 0) then
            .results | map(
                "## \(.title // "No title")\nURL: \(.url)\nPublished: \(.publishedDate // "unknown")\n\n" +
                (if .highlights then "### Highlights\n" + (.highlights | map("- " + .) | join("\n")) + "\n\n" else "" end) +
                (if .summary then "### Summary\n" + .summary + "\n\n" else "" end) +
                (if .text then .text + "\n" else "" end)
            ) | join("\n---\n")
        elif .error then
            "ERROR: " + .error
        else
            "No content retrieved."
        end
    ' 2>/dev/null || echo "$response"
}

# Find similar pages
# API: POST /findSimilar
cmd_similar() {
    local url="${1:-}"
    local num_results="${2:-10}"

    if [[ -z "$url" ]]; then
        echo "Usage: exa.sh similar <url> [numResults]"
        echo "Example: exa.sh similar \"https://github.com/anthropics/anthropic-cookbook\" 5"
        exit 1
    fi

    local json_payload
    json_payload=$(jq -n \
        --arg url "$url" \
        --argjson numResults "$num_results" \
        '{
            url: $url,
            numResults: $numResults,
            contents: {
                text: true,
                highlights: { numSentences: 3 }
            }
        }'
    )

    local response
    if ! response=$(do_request "POST" "/findSimilar" "$json_payload"); then
        echo "ERROR: Find similar failed." >&2
        exit 1
    fi

    echo "$response" | jq -r '
        if .results and (.results | length > 0) then
            "\(.results | length) similar pages:\n" +
            (.results | to_entries | map(
                "\(.key + 1). \(.value.title // "No title")\n   URL: \(.value.url)\n   Published: \(.value.publishedDate // "unknown")\n" +
                (if .value.highlights then "   Highlights: " + (.value.highlights | join(" | ")) + "\n" else "" end) +
                "   \(.value.text // "")"
            ) | join("\n\n"))
        elif .error then
            "ERROR: " + .error
        else
            "No similar pages found."
        end
    ' 2>/dev/null || echo "$response"
}

# Get AI answer with citations
# API: POST /answer
cmd_answer() {
    local query="${1:-}"

    if [[ -z "$query" ]]; then
        echo "Usage: exa.sh answer <question>"
        echo "Example: exa.sh answer \"What is the latest valuation of SpaceX?\""
        exit 1
    fi

    local json_payload
    json_payload=$(jq -n \
        --arg query "$query" \
        '{
            query: $query,
            text: true
        }'
    )

    local response
    if ! response=$(do_request "POST" "/answer" "$json_payload"); then
        echo "ERROR: Answer request failed." >&2
        exit 1
    fi

    echo "$response" | jq -r '
        if .answer then
            "## Answer\n\(.answer)\n\n## Citations\n" +
            (.citations | to_entries | map(
                "\(.key + 1). [\(.value.title // "Source")](\(.value.url))"
            ) | join("\n"))
        elif .error then
            "ERROR: " + .error
        else
            "No answer generated."
        end
    ' 2>/dev/null || echo "$response"
}

# Search for code context
# Uses search with dev-focused includeDomains
cmd_code() {
    local query="${1:-}"

    if [[ -z "$query" ]]; then
        echo "Usage: exa.sh code <programming query>"
        echo "Example: exa.sh code \"React useCallback hook TypeScript examples\""
        exit 1
    fi

    local json_payload
    json_payload=$(jq -n \
        --arg query "$query" \
        '{
            query: $query,
            numResults: 10,
            type: "auto",
            contents: {
                text: true,
                highlights: { numSentences: 3 }
            },
            includeDomains: ["github.com", "stackoverflow.com", "dev.to", "medium.com", "npmjs.com", "pypi.org"]
        }'
    )

    local response
    if ! response=$(do_request "POST" "/search" "$json_payload"); then
        echo "ERROR: Code search failed." >&2
        exit 1
    fi

    echo "$response" | jq -r '
        if .results and (.results | length > 0) then
            "\(.results | length) code results:\n" +
            (.results | to_entries | map(
                "\(.key + 1). \(.value.title // "No title")\n   URL: \(.value.url)\n" +
                (if .value.highlights then "   Highlights: " + (.value.highlights | join(" | ")) + "\n" else "" end) +
                "   \(.value.text // "")"
            ) | join("\n\n"))
        elif .error then
            "ERROR: " + .error
        else
            "No code results found."
        end
    ' 2>/dev/null || echo "$response"
}

# Main dispatch
case "${1:-}" in
    search)
        shift
        cmd_search "$@"
        ;;
    contents)
        shift
        cmd_contents "$@"
        ;;
    similar)
        shift
        cmd_similar "$@"
        ;;
    answer)
        shift
        cmd_answer "$@"
        ;;
    code)
        shift
        cmd_code "$@"
        ;;
    -h|--help|help)
        cat <<'EOF'
Exa AI Web Search

Usage:
  exa.sh search <query> [numResults] [category] [options]  Web search
  exa.sh contents <url1> [url2] ... [options]              Get page contents
  exa.sh similar <url> [numResults]                        Find similar pages
  exa.sh answer <question>                                 Get AI answer with citations
  exa.sh code <query>                                      Search for code examples

Categories (for search):
  company, research paper, news, personal site, financial report, people

Search options:
  --type TYPE          auto|neural|keyword|deep|deep-reasoning|instant
  --start-date DATE    Published after (ISO 8601)
  --end-date DATE      Published before (ISO 8601)
  --domains LIST       Comma-separated domains to include
  --exclude-domains L  Comma-separated domains to exclude
  --json               Output raw JSON response

Contents options:
  --max-chars N        Max characters per page
  --highlights         Return key excerpts (10x more token-efficient)
  --summary            Return LLM-generated summary
  --subpages N         Number of subpages to crawl
  --json               Output raw JSON response

Examples:
  exa.sh search "latest AI research" 5 "research paper" --start-date 2025-01-01T00:00:00.000Z
  exa.sh contents "https://arxiv.org/abs/2307.06435" --highlights
  exa.sh similar "https://github.com/anthropics/anthropic-cookbook" 5
  exa.sh answer "What is the current valuation of SpaceX?"
  exa.sh code "React useState hook TypeScript examples"

Environment:
  EXA_API_KEY    API key(s) for Exa (required)
             Supports comma-separated keys for rotation
             Get one at: https://dashboard.exa.ai/api-keys
EOF
        ;;
    *)
        echo "Usage: exa.sh {search|contents|similar|answer|code} [args...]"
        echo "Run 'exa.sh --help' for examples"
        exit 1
        ;;
esac
