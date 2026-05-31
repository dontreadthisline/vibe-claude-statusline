#!/bin/bash
# Fetch account balance from model providers and cache
# Cache format: provider|currency|total_balance
# /tmp/claude-balance-cache

lock="/tmp/claude-balance-fetch.lock"
# Prevent concurrent fetches within 30s
if [ -f "$lock" ] && [ $(( $(date +%s) - $(stat -c %Y "$lock") )) -lt 30 ]; then
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
    echo "deepseek|${currency}|${total}"
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

case "$provider" in
    deepseek) get_deepseek_balance ;;
    *) exit 0 ;;
esac > /tmp/claude-balance-cache.tmp 2>/dev/null && mv /tmp/claude-balance-cache.tmp /tmp/claude-balance-cache
