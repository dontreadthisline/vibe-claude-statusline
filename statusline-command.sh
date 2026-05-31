#!/bin/bash

# Nerd Font icons
ICON_CPU=$''
ICON_MEM=$''
ICON_TIME=$'\UF252'
ICON_DISK=$'󰋊'
ICON_DOWN=$''
ICON_UP=$''
ICON_GPU=$''
ICON_DIR=$''
ICON_TERMINAL=$''
ICON_MODEL=$''
ICON_COST=$'\UF155'
ICON_EDIT=$''

# Dynamic clock icon: MDI clock-time-X (U+F1445 ~ U+F1450)
get_clock_icon() {
    local h m total rounded dh code
    h=$(date +%-H)
    m=$(date +%-M)
    total=$((h * 60 + m))
    rounded=$(( (total + 30) / 60 ))
    dh=$(( rounded % 12 ))
    [ "$dh" -eq 0 ] && dh=12
    code=$((0xF1445 + dh - 1))
    printf "\U$(printf '%08X' "$code")"
}

# ANSI colors
C_RESET=$'\033[0m'
C_CYAN=$'\033[96m'
C_GRAY=$'\033[90m'
C_BLUE=$'\033[94m'
C_GREEN=$'\033[92m'
C_WHITE=$'\033[97m'
C_YELLOW=$'\033[33m'
C_MAGENTA=$'\033[35m'
C_RED=$'\033[91m'

# Read JSON input from stdin
input=$(cat)

# Extract data from JSON
user=$(id -un 2>/dev/null || echo "$USER" | sed 's/ .*//')
host=$(hostname -s)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name' | sed 's/[Dd]eep[Ss]eek/ds/')

# Context usage with color-coded bar (5 blocks, each = 20%)
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
context_str=""
if [ -n "$used" ]; then
    if [ "$used" -le 50 ]; then
        ctx_color="$C_GREEN"
    elif [ "$used" -le 80 ]; then
        ctx_color="$C_YELLOW"
    else
        ctx_color="$C_RED"
    fi
    blocks=$((used / 20))
    bar=""
    i=0
    while [ $i -lt 5 ]; do
        if [ $i -lt $blocks ]; then
            bar="${bar}█"
        else
            bar="${bar}░"
        fi
        i=$((i + 1))
    done
    # Format context window size: 200000 -> 200K, 1000000 -> 1M
    size_str=""
    if [ -n "$ctx_size" ]; then
        if [ "$ctx_size" -ge 1000000 ]; then
            size_str="$(awk "BEGIN {printf \"%.0fM\", $ctx_size/1000000}")"
        else
            size_str="$(awk "BEGIN {printf \"%.0fK\", $ctx_size/1000}")"
        fi
        context_str="${ctx_color}${bar} ${used}%/${size_str}${C_RESET}"
    else
        context_str="${ctx_color}${bar} ${used}%${C_RESET}"
    fi
fi

# Session cost
cost_str=""
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [ -n "$cost_usd" ] && [ "$cost_usd" != "0" ]; then
    cost_str=$(printf '%.2f' "$cost_usd")
    # Append provider balance from cache (refresh every 5 min)
    cache_file="/tmp/claude-balance-cache"
    if [ -f "$cache_file" ]; then
        cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
        [ "$cache_age" -gt 300 ] && /home/zsl/.claude/balance-fetch.sh &
        IFS='|' read -r bal_provider bal_currency bal_total < "$cache_file"
        if [ -n "$bal_total" ]; then
            cost_str="${cost_str}/${bal_total}"
        fi
    else
        /home/zsl/.claude/balance-fetch.sh &
    fi
fi

# Session duration
duration_str=""
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
if [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ]; then
    s=$((duration_ms / 1000))
    if [ $s -lt 60 ]; then dur="${s}s"
    elif [ $s -lt 3600 ]; then dur="$((s / 60))m"
    else dur="$((s / 3600))h$(((s % 3600) / 60))m"
    fi
    duration_str="${ICON_TIME} ${dur}"
fi

# Thinking mode
thinking_str=""
thinking=$(echo "$input" | jq -r '.thinking.enabled // empty')
[ "$thinking" = "true" ] && thinking_str="[think]"
model_str="${ICON_MODEL} ${model}${thinking_str}"

# Git branch + dirty flag
git_info=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null || echo "no-branch")
    [ -n "$branch" ] && git_info="($branch)"
    [ -n "$(git status --porcelain 2>/dev/null)" ] && git_info="${git_info}[!]"
fi

# Shorten home directory path
short_cwd="${ICON_DIR} $(basename "$cwd")"

# CPU usage (instantaneous via /proc/stat delta)
stat_cache="/tmp/statusline-cpustat"
cpu_usage="0"
if [ -f "$stat_cache" ]; then
    read -r p_user p_nice p_sys p_idle p_iowait p_irq p_softirq p_steal _ < "$stat_cache"
    p_idle=$((p_idle + p_iowait))
    p_total=$((p_user + p_nice + p_sys + p_idle + p_irq + p_softirq + p_steal))

    read -r _ cu_user cu_nice cu_sys cu_idle cu_iowait cu_irq cu_softirq cu_steal _ < /proc/stat
    cu_idle=$((cu_idle + cu_iowait))
    cu_total=$((cu_user + cu_nice + cu_sys + cu_idle + cu_irq + cu_softirq + cu_steal))

    d_idle=$((cu_idle - p_idle))
    d_total=$((cu_total - p_total))
    [ "$d_total" -gt 0 ] && cpu_usage=$(awk "BEGIN {printf \"%.0f\", 100 * (1 - $d_idle / $d_total)}")
fi
awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8, $9}' /proc/stat > "$stat_cache"

# CPU temperature
cpu_temp=$(sensors 2>/dev/null | awk '/Package id 0/ {print $4}' | tr -d '+')
if [ -n "$cpu_temp" ]; then
    cpu_str="${ICON_CPU} ${cpu_usage}%/${cpu_temp}"
else
    cpu_str="${ICON_CPU} ${cpu_usage}%"
fi

# GPU info (2 GPUs)
gpu_str=""
if command -v nvidia-smi > /dev/null 2>&1; then
    gpu_data=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
    if [ -n "$gpu_data" ]; then
        g0=$(echo "$gpu_data" | sed -n '1p' | awk -F', ' '{printf "%s%%/%s°", $1, $2}')
        g1=$(echo "$gpu_data" | sed -n '2p' | awk -F', ' '{printf "%s%%/%s°", $1, $2}')
        gpu_str="${ICON_GPU} ${g0} ${ICON_GPU} ${g1}"
    fi
fi

# Memory
mem_str=$(LC_ALL=C free -h 2>/dev/null | awk '/^Mem:/ {gsub(/i/,""); printf "%s/%s", $3, $2}')
[ -n "$mem_str" ] && mem_str="${ICON_MEM} ${mem_str}" || mem_str="${ICON_MEM} ?/?"

# Disk (current dir usage ; mount point total)
disk_str=""
if [ -d "$cwd" ]; then
    dir_usage=$(du -sh "$cwd" 2>/dev/null | awk '{print $1}')
    part_info=$(df -h "$cwd" 2>/dev/null | awk 'NR==2 {printf "%s/%s", $3, $2}')
    [ -n "$dir_usage" ] && [ -n "$part_info" ] && disk_str="${ICON_DISK} ${dir_usage};${part_info}"
fi
[ -z "$disk_str" ] && disk_str="${ICON_DISK} ?/?"

# Network bandwidth (delta from /proc/net/dev)
net_cache="/tmp/statusline-netstat"
net_str=""
if [ -f /proc/net/dev ]; then
    now=$(date +%s%N)
    curr_rx=0; curr_tx=0
    while read -r iface rx_bytes _ _ _ _ _ _ _ tx_bytes _; do
        [ "$iface" = "lo:" ] && continue
        curr_rx=$((curr_rx + rx_bytes))
        curr_tx=$((curr_tx + tx_bytes))
    done < <(awk 'NR>2 {gsub(/:/,""); print $1, $2, $10}' /proc/net/dev 2>/dev/null)
    if [ -f "$net_cache" ]; then
        read -r prev_ts prev_rx prev_tx < "$net_cache"
        dt=$(( (now - prev_ts) / 1000000000 ))
        if [ "$dt" -gt 0 ]; then
            drx=$(( (curr_rx - prev_rx) / dt ))
            dtx=$(( (curr_tx - prev_tx) / dt ))
            rx_str=$(awk "BEGIN {v=$drx; if(v>=1048576) printf \"%.1fM\",v/1048576; else if(v>=1024) printf \"%.0fK\",v/1024; else printf \"%d\",v}")
            tx_str=$(awk "BEGIN {v=$dtx; if(v>=1048576) printf \"%.1fM\",v/1048576; else if(v>=1024) printf \"%.0fK\",v/1024; else printf \"%d\",v}")
            net_str="${ICON_DOWN} ${rx_str} ${ICON_UP} ${tx_str}"
        fi
    fi
    echo "$now $curr_rx $curr_tx" > "$net_cache"
fi
[ -z "$net_str" ] && net_str="${ICON_DOWN} 0 ${ICON_UP} 0"

# System time
sys_time=$(date '+%H:%M')

# Currently edited file (written by PostToolUse hook: CATEGORY|CMD|PATH)
edit_str=""
session_id=$(echo "$input" | jq -r '.session_id // empty')
if [ -n "$session_id" ] && [ -f "/tmp/claude-status-edit-file-${session_id}" ]; then
    edit_age=$(( $(date +%s) - $(stat -c %Y "/tmp/claude-status-edit-file-${session_id}" 2>/dev/null || echo 0) ))
    if [ "$edit_age" -lt 5 ]; then
        IFS='|' read -r edit_cat edit_cmd edit_path <<< "$(cat "/tmp/claude-status-edit-file-${session_id}")"
        # Validate category
        case "$edit_cat" in create|edit|delete) ;; *) edit_cat="";; esac
        # Guard against literal "null" strings
        [ "$edit_cmd" = "null" ] && edit_cmd=""
        [ "$edit_path" = "null" ] && edit_path=""
        # All three must be non-empty
        [ -z "$edit_cat" ] || [ -z "$edit_cmd" ] || [ -z "$edit_path" ] && edit_cat=""
        # Path basename must be meaningful (not "null", not empty)
        if [ -n "$edit_cat" ]; then
            bn=$(basename "$edit_path" 2>/dev/null)
            [ -z "$bn" ] || [ "$bn" = "null" ] && edit_cat=""
            if [ -n "$edit_cat" ]; then
                case "$edit_cat" in
                    create) edit_color="$C_YELLOW" ;;
                    delete) edit_color="$C_RED" ;;
                    *)      edit_color="$C_GREEN" ;;
                esac
                edit_str="${edit_color}${ICON_EDIT} (${edit_cmd}) ${bn}${C_RESET}"
            fi
        fi
    fi
fi

# Build segments - only non-empty to avoid double-spacing
segments=()
segments+=("${C_CYAN}${ICON_TERMINAL}${C_RESET} ${C_GRAY}${user}@${host}${C_RESET}")
[ -n "$short_cwd" ] && segments+=("${C_BLUE}${short_cwd}${C_RESET}")
[ -n "$git_info" ] && segments+=("${C_GREEN}${git_info}${C_RESET}")
[ -n "$model_str" ] && segments+=("${C_WHITE}${model_str}${C_RESET}")
[ -n "$context_str" ] && segments+=("${context_str}")
[ -n "$cost_str" ] && segments+=("${C_MAGENTA}${ICON_COST}${cost_str}${C_RESET}")
[ -n "$duration_str" ] && segments+=("${C_CYAN}${duration_str}${C_RESET}")
[ -n "$cpu_str" ] && segments+=("${C_RED}${cpu_str}${C_RESET}")
[ -n "$gpu_str" ] && segments+=("${C_CYAN}${gpu_str}${C_RESET}")
[ -n "$mem_str" ] && segments+=("${C_GRAY}${mem_str}${C_RESET}")
[ -n "$disk_str" ] && segments+=("${C_GREEN}${disk_str}${C_RESET}")
segments+=("${C_YELLOW}$(get_clock_icon)${C_RESET} ${C_WHITE}${sys_time}${C_RESET}")
[ -n "$net_str" ] && segments+=("${C_BLUE}${net_str}${C_RESET}")
[ -n "$edit_str" ] && segments+=("${edit_str}")

# Join with single space then output
output=""
for seg in "${segments[@]}"; do
    [ -n "$output" ] && output+=" "
    output+="$seg"
done
printf "%s" "$output"
