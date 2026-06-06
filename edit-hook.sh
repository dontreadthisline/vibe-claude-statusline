#!/bin/bash
# PostToolUse hook: record file being edited/created/deleted
# Output format: CATEGORY|COMMAND|FILEPATH
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
status_file="/tmp/claude-status-edit-file-${session_id}"
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

classify_cmd() {
    # Returns: category|display_name
    # Categories: edit(green) create(yellow) delete(red)
    local c="$1"
    case "$c" in
        # ---- create ----
        touch|mkdir|mknod|mkfifo|fallocate|cp|install|rsync|ln|link)    echo "create|$c" ;;
        gzip|bzip2|xz|zip|7z|ar|compress|dd)                              echo "create|$c" ;;
        wget|curl)                                                       echo "create|$c" ;;
        # ---- delete ----
        rm|rmdir|shred|unlink)                                           echo "delete|$c" ;;
        # ---- edit ----
        sed|awk|perl|ed|ex|patch|truncate|split|csplit|source)            echo "edit|$c" ;;
        mv|rename|mmv)                                                   echo "edit|$c" ;;
        chmod|chown|chgrp|chattr|setfacl|strip)                          echo "edit|$c" ;;
        tee)                                                             echo "edit|$c" ;;
        gunzip|bunzip2|unxz|unzip)                                       echo "edit|$c" ;;
        *)                                                               echo "edit|$c" ;;
    esac
}

skip_path() {
    # Filter out self-referencing status files
    case "$1" in
        */tmp/claude-status-edit-file-*) return 0 ;;
        *) return 1 ;;
    esac
}

extract_from_bash() {
    local cmd
    cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
    [ -z "$cmd" ] && return

    # Strip comment lines and ignore self-referencing paths
    cmd=$(echo "$cmd" | grep -v '^\s*#')
    [ -z "$cmd" ] && return

    local cat display
    local basename_cmd
    # Take last command in a pipe (e.g. "echo x | tee file" -> tee)
    basename_cmd=$(echo "$cmd" | awk -F'|' '{print $NF}' | awk '{print $1}')
    basename_cmd=$(basename "$basename_cmd" 2>/dev/null || echo "$basename_cmd")

    # 1. Redirection: get the file, command is whatever piped into it
    local redir
    # Only stdout redirect (not 2>, &>, 1>, 2>>)
    redir=$(echo "$cmd" | grep -oP '(?<![0-9&])>>?\s*\K(/\S+|\./\S+|\.\./\S+|~\S+)' | tail -1)
    if [ -n "$redir" ]; then
        redir=$(echo "$redir" | sed "s|^~|$HOME|")
        skip_path "$redir" && return
        # >> means append/edit, > means create (or truncate)
        if echo "$cmd" | grep -qP '>>'; then
            echo "edit|${basename_cmd}|${redir}"
        else
            echo "create|${basename_cmd}|${redir}"
        fi
        return
    fi

    # 2. -f / --file flag: only for tar/zip/ar (not rm -rf, etc.)
    if echo "$cmd" | grep -qP '\b(tar|zip|unzip|ar|7z)\b'; then
        local f_flag
        f_flag=$(echo "$cmd" | grep -oP '(?:--file\s+|(?:^|\s)-[a-zA-Z]*f[a-zA-Z]*\s+)\K(/\S+|\./\S+|\.\.\S+)' | head -1)
        if [ -n "$f_flag" ]; then
            skip_path "$f_flag" && return
            if echo "$cmd" | grep -qP '\btar\s+-[a-zA-Z]*c'; then
                echo "create|tar|${f_flag}"
            else
                echo "edit|tar|${f_flag}"
            fi
            return
        fi
    fi

    # 3. Output-file flags: -o/-O, --output, -out, of=
    local out_flag
    out_flag=$(echo "$cmd" | grep -oP '(?:of=|-o\s+|-O\s+|--output\s+|-out\s+)\K(/\S+|\./\S+|\.\.\S+)' | head -1)
    if [ -n "$out_flag" ]; then
        skip_path "$out_flag" && return
        IFS='|' read -r cat display <<< "$(classify_cmd "$basename_cmd")"
        echo "${cat}|${basename_cmd}|${out_flag}"
        return
    fi

    # 4. git subcommands
    if echo "$cmd" | grep -qP '\bgit\s+(?:add|rm|mv|restore|checkout\s+--)'; then
        local git_sub
        git_sub=$(echo "$cmd" | grep -oP '\bgit\s+\K(add|rm|mv|restore|checkout)' | head -1)
        local after_git
        after_git=$(echo "$cmd" | sed -E 's/.*\bgit\s+(add|rm|mv|restore|checkout\s+--)[[:space:]]+//')
        local git_path
        git_path=$(echo "$after_git" | grep -oP '(?<!\w)(/[\w./-]+|\./[\w./-]+|\.\.[\w./-]*|~[\w./-]*)(?!\w)' | tail -1)
        if [ -n "$git_path" ]; then
            git_path=$(echo "$git_path" | sed "s|^~|$HOME|")
            skip_path "$git_path" && return
            case "$git_sub" in
                rm)  echo "delete|git ${git_sub}|${git_path}" ;;
                add) echo "create|git ${git_sub}|${git_path}" ;;
                *)   echo "edit|git ${git_sub}|${git_path}" ;;
            esac
            return
        fi
    fi

    # 5. Other file-modifying commands
    local pat='\b(rm|rmdir|shred|unlink|touch|mkdir|mknod|mkfifo|fallocate|mv|cp|install|rsync|rename|mmv|sed|awk|perl|ed|ex|tee|truncate|split|csplit|chmod|chown|chgrp|chattr|setfacl|ln|tar|gzip|gunzip|bzip2|bunzip2|xz|unxz|zip|unzip|7z|ar|patch|strip|wget|curl|source)\b'
    if echo "$cmd" | grep -qP "$pat"; then
        local last_path
        last_path=$(echo "$cmd" | grep -oP '(?<!\w)(/[\w./-]+|\./[\w./-]+|\.\.[\w./-]*|~[\w./-]*)(?!\w)' | tail -1)
        if [ -n "$last_path" ]; then
            last_path=$(echo "$last_path" | sed "s|^~|$HOME|")
            skip_path "$last_path" && return
            IFS='|' read -r cat display <<< "$(classify_cmd "$basename_cmd")"
            echo "${cat}|${display}|${last_path}"
        fi
    fi
}

case "$tool_name" in
    Write)
        file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
        [ -n "$file_path" ] && echo "create|Write|${file_path}"
        ;;
    Edit|NotebookEdit)
        file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
        [ -n "$file_path" ] && echo "edit|${tool_name}|${file_path}"
        ;;
    Bash)
        extract_from_bash
        ;;
esac > "${status_file}.tmp" && [ -s "${status_file}.tmp" ] && mv "${status_file}.tmp" "$status_file" || rm -f "${status_file}.tmp"
