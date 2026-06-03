#!/bin/bash
# Fetch account balance from model providers and cache
# Cache format: provider|currency|total_balance
# /tmp/claude-balance-cache

# Platform detection
IS_MACOS=false
[[ "$OSTYPE" == "darwin"* ]] && IS_MACOS=true

# Cross-platform stat for file modification time
get_file_mtime() {
    local file="$1"
    if $IS_MACOS; then
        stat -f %m "$file" 2>/dev/null || echo 0
    else
        stat -c %Y "$file" 2>/dev/null || echo 0
    fi
}

lock="/tmp/claude-balance-fetch.lock"
# Prevent concurrent fetches within 30s
if [ -f "$lock" ] && [ $(( $(date +%s) - $(get_file_mtime "$lock") )) -lt 30 ]; then
    exit 0
fi
trap 'rm -f "$lock"' EXIT
touch "$lock"

get_deepseek_balance() {
    local key="${DEEPSEEK_API_KEY:-}"
    [ -z "$key" ] && return 1
    local resp
    resp=$(curl -sfL -X GET 'https://api.deepseek.com/user/balance' \
        -H 'Accept: application/json' \
        -H "Authorization: Bearer $key" 2>/dev/null) || return 1
    local total currency
    total=$(echo "$resp" | jq -r '.balance_infos[0].total_balance // empty')
    currency=$(echo "$resp" | jq -r '.balance_infos[0].currency // empty')
    [ -z "$total" ] && return 1
    echo "balance|${currency}|${total}"
    return 0
}

get_didi_balance() {
    local key="${DIDI_API_KEY:-}"
    [ -z "$key" ] && return 1
    local resp
    resp=$(curl -sfL -X GET 'http://llm-proxy.intra.xiaojukeji.com/user/info' \
        -H 'Accept: application/json' \
        -H "Authorization: Bearer $key" 2>/dev/null) || return 1

    local spend budget_apps target_total
    spend=$(echo "$resp" | jq -r '.user_info.spend // empty')
    budget_apps=$(echo "$resp" | jq -r '.user_info.metadata.llm_proxy_access.budget_increase_applications // empty')

    [ -z "$spend" ] && return 1

    # Get the latest approved budget application
    target_total=0
    if [ -n "$budget_apps" ] && [ "$budget_apps" != "null" ]; then
        target_total=$(echo "$budget_apps" | jq '[.[] | select(.status == "approved")] | sort_by(.applied_at) | reverse | .[0].target_budget // 0')
    fi

    # Round to integers
    spend=$(printf '%.0f' "$spend")
    target_total=$(printf '%.0f' "$target_total")

    echo "didi|CNY|${spend}|${target_total}"
    return 0
}

# Determine provider from model name (first arg or env)
model="${1:-}"
provider=""
case "$model" in
    deepseek*)  provider="deepseek" ;;
    kimi*)      provider="kimi" ;;
    *)          provider="deepseek" ;;  # default for now
esac

# Check if using DIDI internal proxy via base_url or DIDI_API_KEY
base_url="${ANTHROPIC_BASE_URL:-}"
# Only use didi provider for llm-proxy (not token.intra which is separate service)
if [[ "$base_url" == *"llm-proxy.intra.xiaojukeji"* ]]; then
    provider="didi"
fi

case "$provider" in
    deepseek) get_deepseek_balance ;;
    didi)     get_didi_balance ;;
    *) exit 0 ;;
esac > /tmp/claude-balance-cache.tmp 2>/dev/null && mv /tmp/claude-balance-cache.tmp /tmp/claude-balance-cache
