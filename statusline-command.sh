#!/usr/bin/env bash
# Statusline for Claude Code - Cross-platform (Linux/macOS, bash/zsh)
# Requires: Nerd Font for icons, jq for JSON parsing

# Platform detection
IS_MACOS=false
[ "$(uname -s)" = "Darwin" ] && IS_MACOS=true

# Script directory (portable)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Nerd Font icons - Font Awesome only (consistent sizing)
ICON_CPU=''
ICON_MEM=''
ICON_TIME=''
ICON_DISK=''
ICON_DOWN=''
ICON_UP=''
ICON_GPU=''
ICON_DIR=''
ICON_TERMINAL=''
ICON_MODEL=''
ICON_COST=''
ICON_EDIT=''
ICON_CLOCK=''

# ANSI Colors
C_RESET='\033[0m'
C_CYAN='\033[96m'
C_GRAY='\033[90m'
C_BLUE='\033[94m'
C_GREEN='\033[92m'
C_WHITE='\033[97m'
C_YELLOW='\033[33m'
C_MAGENTA='\033[35m'
C_RED='\033[91m'

get_file_mtime() {
    local file="$1"
    if $IS_MACOS; then stat -f %m "$file" 2>/dev/null || echo 0
    else stat -c %Y "$file" 2>/dev/null || echo 0
    fi
}

input=$(cat)
user=$(id -un 2>/dev/null || echo "${USER:-user}" | cut -d' ' -f1)
host=$(hostname -s 2>/dev/null || echo "host")
cwd=$(echo "$input" | jq -r '.workspace.current_dir // "."')
model=$(echo "$input" | jq -r '.model.display_name // "unknown"' | sed 's/[Dd]eep[Ss]eek/ds/')

# Context Window
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
context_str=""
if [ -n "$used" ]; then
    if [ "$used" -le 50 ]; then ctx_color="$C_GREEN"
    elif [ "$used" -le 80 ]; then ctx_color="$C_YELLOW"
    else ctx_color="$C_RED"
    fi
    blocks=$((used / 20)); bar=""; i=0
    while [ $i -lt 5 ]; do [ $i -lt $blocks ] && bar="${bar}█" || bar="${bar}░"; i=$((i + 1)); done
    if [ -n "$ctx_size" ]; then
        [ "$ctx_size" -ge 1000000 ] && size_str="$(awk "BEGIN {printf \"%.0fM\", $ctx_size/1000000}")" || size_str="$(awk "BEGIN {printf \"%.0fK\", $ctx_size/1000}")"
        context_str="${ctx_color}${bar} ${used}%/${size_str}${C_RESET}"
    else context_str="${ctx_color}${bar} ${used}%${C_RESET}"; fi
fi

# Cost & Balance
cost_str=""; cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [ -n "$cost_usd" ] && [ "$cost_usd" != "0" ]; then
    cost_str=$(printf '%.2f' "$cost_usd")
    cache_file="/tmp/claude-balance-cache"
    if [ -f "$cache_file" ]; then
        cache_age=$(( $(date +%s) - $(get_file_mtime "$cache_file") ))
        [ "$cache_age" -gt 300 ] && "${SCRIPT_DIR}/balance-fetch.sh" &
        IFS='|' read -r _ _ bal_total < "$cache_file"; [ -n "$bal_total" ] && cost_str="${cost_str}/${bal_total}"
    else "${SCRIPT_DIR}/balance-fetch.sh" &
    fi
fi

# Duration
duration_str=""; duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
if [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ]; then
    s=$((duration_ms / 1000))
    [ $s -lt 60 ] && dur="${s}s" || { [ $s -lt 3600 ] && dur="$((s / 60))m" || dur="$((s / 3600))h$(((s % 3600) / 60))m"; }
    duration_str="${ICON_TIME} ${dur}"
fi

# Thinking
thinking=$(echo "$input" | jq -r '.thinking.enabled // empty')
[ "$thinking" = "true" ] && thinking_str="[think]" || thinking_str=""
model_str="${ICON_MODEL} ${model}${thinking_str}"

# Git
git_info=""
git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 && {
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "no-branch")
    [ -n "$branch" ] && git_info="($branch)"
    [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ] && git_info="${git_info}[!]"
}
short_cwd="${ICON_DIR} $(basename "$cwd")"

# CPU
stat_cache="/tmp/statusline-cpustat"; cpu_usage="0"
if $IS_MACOS; then
    cpu_line=$(/usr/bin/top -l 1 2>/dev/null | grep -E '^CPU usage:')
    [ -n "$cpu_line" ] && { idle_pct=$(echo "$cpu_line" | awk -F', ' '{print $3}' | grep -oE '[0-9]+\.[0-9]+')
    [ -n "$idle_pct" ] && cpu_usage=$(awk "BEGIN {printf \"%.0f\", 100 - $idle_pct}"); }
else
    [ -f "$stat_cache" ] && [ -f /proc/stat ] && {
        read -r p_user p_nice p_sys p_idle p_iowait p_irq p_softirq p_steal _ < "$stat_cache"
        p_idle=$((p_idle + p_iowait)); p_total=$((p_user + p_nice + p_sys + p_idle + p_irq + p_softirq + p_steal))
        read -r _ cu_user cu_nice cu_sys cu_idle cu_iowait cu_irq cu_softirq cu_steal _ < /proc/stat
        cu_idle=$((cu_idle + cu_iowait)); cu_total=$((cu_user + cu_nice + cu_sys + cu_idle + cu_irq + cu_softirq + cu_steal))
        d_idle=$((cu_idle - p_idle)); d_total=$((cu_total - p_total))
        [ "$d_total" -gt 0 ] && cpu_usage=$(awk "BEGIN {printf \"%.0f\", 100 * (1 - $d_idle / $d_total)}")
    }
    [ -f /proc/stat ] && awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8, $9}' /proc/stat > "$stat_cache"
fi
cpu_temp=""
if $IS_MACOS; then command -v osx-cpu-temp >/dev/null 2>&1 && { cpu_temp=$(osx-cpu-temp 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1); [ -n "$cpu_temp" ] && cpu_temp="${cpu_temp}°C"; }
else cpu_temp=$(sensors 2>/dev/null | awk '/Package id 0/ {print $4}' | tr -d '+'); fi
[ -n "$cpu_temp" ] && cpu_str="${ICON_CPU} ${cpu_usage}%/${cpu_temp}" || cpu_str="${ICON_CPU} ${cpu_usage}%"

# GPU
gpu_str=""
command -v nvidia-smi >/dev/null 2>&1 && {
    gpu_data=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
    [ -n "$gpu_data" ] && { g0=$(echo "$gpu_data" | sed -n '1p' | awk -F', ' '{printf "%s%%/%s°", $1, $2}')
    g1=$(echo "$gpu_data" | sed -n '2p' | awk -F', ' '{printf "%s%%/%s°", $1, $2}')
    gpu_str="${ICON_GPU} ${g0} ${ICON_GPU} ${g1}"; }
}

# Memory
mem_str=""
if $IS_MACOS; then
    mem_info=$(LC_ALL=C vm_stat 2>/dev/null)
    [ -n "$mem_info" ] && {
        page_size=4096
        active_pages=$(echo "$mem_info" | awk '/Pages active/ {print $3}' | tr -d '.')
        inactive_pages=$(echo "$mem_info" | awk '/Pages inactive/ {print $3}' | tr -d '.')
        wired_pages=$(echo "$mem_info" | awk '/Pages wired down/ {print $4}' | tr -d '.')
        used_bytes=$(( (active_pages + inactive_pages + wired_pages) * page_size ))
        total_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        [ "$total_bytes" -gt 0 ] && { used_gb=$(awk "BEGIN {printf \"%.1fG\", $used_bytes/1073741824}")
        total_gb=$(awk "BEGIN {printf \"%.0fG\", $total_bytes/1073741824}"); mem_str="${ICON_MEM} ${used_gb}/${total_gb}"; }
    }
else mem_str=$(LC_ALL=C free -h 2>/dev/null | awk '/^Mem:/ {gsub(/i/,""); printf "%s/%s", $3, $2}'); [ -n "$mem_str" ] && mem_str="${ICON_MEM} ${mem_str}"; fi
[ -z "$mem_str" ] && mem_str="${ICON_MEM} ?/?"

# Disk
disk_str=""
[ -d "$cwd" ] && { dir_usage=$(du -sh "$cwd" 2>/dev/null | awk '{print $1}')
part_info=$(df -h "$cwd" 2>/dev/null | awk 'NR==2 {printf "%s/%s", $3, $2}')
[ -n "$dir_usage" ] && [ -n "$part_info" ] && disk_str="${ICON_DISK} ${dir_usage};${part_info}"; }
[ -z "$disk_str" ] && disk_str="${ICON_DISK} ?/?"

# Network
net_cache="/tmp/statusline-netstat"; net_str=""
if $IS_MACOS; then
    now=$(date +%s); curr_rx=0; curr_tx=0
    while read -r iface _ _ _ _ _ _ _ _ _ rx _ _ _ _ _ tx _; do
        [ "$iface" = "lo0" ] && continue
        [ -n "$rx" ] && [ "$rx" -eq "$rx" ] 2>/dev/null && curr_rx=$((curr_rx + rx))
        [ -n "$tx" ] && [ "$tx" -eq "$tx" ] 2>/dev/null && curr_tx=$((curr_tx + tx))
    done < <(netstat -ib 2>/dev/null | awk 'NR>1 {print $1, $7, $10}')
    [ -f "$net_cache" ] && { read -r prev_ts prev_rx prev_tx < "$net_cache"; dt=$((now - prev_ts))
    [ "$dt" -gt 0 ] && { drx=$(( (curr_rx - prev_rx) / dt )); dtx=$(( (curr_tx - prev_tx) / dt ))
    rx_str=$(awk "BEGIN {v=$drx; if(v>=1048576) printf \"%.1fM\",v/1048576; else if(v>=1024) printf \"%.0fK\",v/1024; else printf \"%d\",v}")
    tx_str=$(awk "BEGIN {v=$dtx; if(v>=1048576) printf \"%.1fM\",v/1048576; else if(v>=1024) printf \"%.0fK\",v/1024; else printf \"%d\",v}")
    net_str="${ICON_DOWN} ${rx_str} ${ICON_UP} ${tx_str}"; }; }
    echo "$now $curr_rx $curr_tx" > "$net_cache"
else
    [ -f /proc/net/dev ] && {
        now=$(date +%s%N); curr_rx=0; curr_tx=0
        while read -r iface rx_bytes _ _ _ _ _ _ _ tx_bytes _; do
            [ "$iface" = "lo:" ] && continue; curr_rx=$((curr_rx + rx_bytes)); curr_tx=$((curr_tx + tx_bytes))
        done < <(awk 'NR>2 {gsub(/:/,""); print $1, $2, $10}' /proc/net/dev 2>/dev/null)
        [ -f "$net_cache" ] && { read -r prev_ts prev_rx prev_tx < "$net_cache"; dt=$(( (now - prev_ts) / 1000000000 ))
        [ "$dt" -gt 0 ] && { drx=$(( (curr_rx - prev_rx) / dt )); dtx=$(( (curr_tx - prev_tx) / dt ))
        rx_str=$(awk "BEGIN {v=$drx; if(v>=1048576) printf \"%.1fM\",v/1048576; else if(v>=1024) printf \"%.0fK\",v/1024; else printf \"%d\",v}")
        tx_str=$(awk "BEGIN {v=$dtx; if(v>=1048576) printf \"%.1fM\",v/1048576; else if(v>=1024) printf \"%.0fK\",v/1024; else printf \"%d\",v}")
        net_str="${ICON_DOWN} ${rx_str} ${ICON_UP} ${tx_str}"; }; }
        echo "$now $curr_rx $curr_tx" > "$net_cache"
    }
fi
[ -z "$net_str" ] && net_str="${ICON_DOWN} 0 ${ICON_UP} 0"

sys_time=$(date '+%H:%M')

# Edit indicator
edit_str=""; session_id=$(echo "$input" | jq -r '.session_id // empty')
edit_file="/tmp/claude-status-edit-file-${session_id}"
[ -n "$session_id" ] && [ -f "$edit_file" ] && {
    edit_age=$(( $(date +%s) - $(get_file_mtime "$edit_file") ))
    [ "$edit_age" -lt 5 ] && {
        IFS='|' read -r edit_cat edit_cmd edit_path < "$edit_file"
        case "$edit_cat" in create|edit|delete) ;; *) edit_cat="";; esac
        [ "$edit_cmd" = "null" ] && edit_cmd=""; [ "$edit_path" = "null" ] && edit_path=""
        [ -z "$edit_cat" ] || [ -z "$edit_cmd" ] || [ -z "$edit_path" ] && edit_cat=""
        [ -n "$edit_cat" ] && { bn=$(basename "$edit_path" 2>/dev/null)
        [ -z "$bn" ] || [ "$bn" = "null" ] && edit_cat=""
        [ -n "$edit_cat" ] && {
            case "$edit_cat" in create) edit_color="$C_YELLOW" ;; delete) edit_color="$C_RED" ;; *) edit_color="$C_GREEN" ;; esac
            edit_str="${edit_color}${ICON_EDIT} (${edit_cmd}) ${bn}${C_RESET}"
        }; }
    }
}

# Output
segments="${C_CYAN}${ICON_TERMINAL}${C_RESET} ${C_GRAY}${user}@${host}${C_RESET}"
segments="${segments} ${C_BLUE}${short_cwd}${C_RESET}"
[ -n "$git_info" ] && segments="${segments} ${C_GREEN}${git_info}${C_RESET}"
[ -n "$model_str" ] && segments="${segments} ${C_WHITE}${model_str}${C_RESET}"
[ -n "$context_str" ] && segments="${segments} ${context_str}"
[ -n "$cost_str" ] && segments="${segments} ${C_MAGENTA}${ICON_COST}${cost_str}${C_RESET}"
[ -n "$duration_str" ] && segments="${segments} ${C_CYAN}${duration_str}${C_RESET}"
[ -n "$cpu_str" ] && segments="${segments} ${C_RED}${cpu_str}${C_RESET}"
[ -n "$gpu_str" ] && segments="${segments} ${C_CYAN}${gpu_str}${C_RESET}"
[ -n "$mem_str" ] && segments="${segments} ${C_GRAY}${mem_str}${C_RESET}"
[ -n "$disk_str" ] && segments="${segments} ${C_GREEN}${disk_str}${C_RESET}"
segments="${segments} ${C_YELLOW}${ICON_CLOCK}${C_RESET} ${C_WHITE}${sys_time}${C_RESET}"
[ -n "$net_str" ] && segments="${segments} ${C_BLUE}${net_str}${C_RESET}"
[ -n "$edit_str" ] && segments="${segments} ${edit_str}"

printf "%s" "$segments"
