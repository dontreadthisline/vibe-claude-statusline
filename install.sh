#!/bin/bash
# Claude Code Statusline Installer for macOS

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo -e "${CYAN}"
echo "======================================"
echo "  Claude Code Statusline Installer"
echo "======================================"
echo -e "${RESET}"

# Check macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo -e "${YELLOW}Warning: This installer is optimized for macOS.${RESET}"
    echo "It may work on Linux but some features might need manual setup."
fi

# Check strong dependencies
echo -e "\n${CYAN}[1/5] Checking strong dependencies...${RESET}"
missing_deps=()

for cmd in jq curl bash; do
    if ! command -v "$cmd" &>/dev/null; then
        missing_deps+=("$cmd")
    else
        echo -e "  ${GREEN}✓${RESET} $cmd"
    fi
done

if [ ${#missing_deps[@]} -gt 0 ]; then
    echo -e "\n${RED}Missing required dependencies: ${missing_deps[*]}${RESET}"
    echo "Please install them first:"
    echo "  brew install ${missing_deps[*]}"
    exit 1
fi

# Check optional dependencies
echo -e "\n${CYAN}[2/5] Checking optional dependencies...${RESET}"

if command -v git &>/dev/null; then
    echo -e "  ${GREEN}✓${RESET} git (branch/dirty status)"
else
    echo -e "  ${YELLOW}○${RESET} git (not found, branch info disabled)"
fi

if command -v nvidia-smi &>/dev/null; then
    echo -e "  ${GREEN}✓${RESET} nvidia-smi (GPU status)"
else
    echo -e "  ${YELLOW}○${RESET} nvidia-smi (not found, GPU info disabled)"
fi

# Check Nerd Font
echo -e "\n${CYAN}[3/5] Checking Nerd Font...${RESET}"

has_nerd_font() {
    # Check if a Nerd Font is installed in system fonts
    if [ -d "$HOME/Library/Fonts" ]; then
        if ls "$HOME/Library/Fonts"/*Nerd* 2>/dev/null | head -1 | grep -q .; then
            return 0
        fi
    fi
    # Check Homebrew fonts
    if [ -d "/opt/homebrew/share/fonts" ]; then
        if ls /opt/homebrew/share/fonts/*Nerd* 2>/dev/null | head -1 | grep -q .; then
            return 0
        fi
    fi
    return 1
}

if has_nerd_font; then
    echo -e "  ${GREEN}✓${RESET} Nerd Font detected"
else
    echo -e "  ${YELLOW}○${RESET} Nerd Font not found"
    echo -e "  ${CYAN}Installing Nerd Font via Homebrew...${RESET}"

    if command -v brew &>/dev/null; then
        brew tap homebrew/cask-fonts 2>/dev/null || true
        brew install --cask font-hack-nerd-font 2>/dev/null && \
            echo -e "  ${GREEN}✓${RESET} font-hack-nerd-font installed" || \
            echo -e "  ${YELLOW}○${RESET} Failed to install font. You may install manually."
    else
        echo -e "  ${YELLOW}Homebrew not found. Please install a Nerd Font manually:${RESET}"
        echo "    https://www.nerdfonts.com/font-downloads"
    fi
fi

# Install scripts
echo -e "\n${CYAN}[4/5] Installing scripts...${RESET}"

mkdir -p "$CLAUDE_DIR"

for script in statusline-command.sh balance-fetch.sh edit-hook.sh; do
    if [ -f "$CLAUDE_DIR/$script" ]; then
        echo -e "  ${YELLOW}→${RESET} Backing up existing $script"
        mv "$CLAUDE_DIR/$script" "$CLAUDE_DIR/${script}.bak"
    fi
    cp "$SCRIPT_DIR/$script" "$CLAUDE_DIR/"
    chmod +x "$CLAUDE_DIR/$script"
    echo -e "  ${GREEN}✓${RESET} $script installed"
done

# Merge settings
echo -e "\n${CYAN}[5/5] Configuring settings...${RESET}"

SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SETTINGS_LOCAL="$CLAUDE_DIR/settings.local.json"
SNIPPET_FILE="$SCRIPT_DIR/settings-snippet.json"

if [ -f "$SETTINGS_FILE" ]; then
    # Merge with existing settings
    echo -e "  ${GREEN}✓${RESET} Found existing settings.json"

    # Create a merged temp file
    TMP_FILE=$(mktemp)
    jq -s '.[0] * .[1]' "$SETTINGS_FILE" "$SNIPPET_FILE" > "$TMP_FILE" && \
        mv "$TMP_FILE" "$SETTINGS_FILE" && \
        echo -e "  ${GREEN}✓${RESET} Merged settings-snippet.json into settings.json" || \
        { rm -f "$TMP_FILE"; echo -e "  ${YELLOW}○${RESET} Failed to merge, please add manually"; }
else
    cp "$SNIPPET_FILE" "$SETTINGS_FILE"
    echo -e "  ${GREEN}✓${RESET} Created new settings.json"
fi

# Summary
echo -e "\n${GREEN}======================================"
echo "  Installation Complete!"
echo "======================================${RESET}"

echo -e "\n${CYAN}Optional Environment Variables:${RESET}"
echo "  For DeepSeek balance:"
echo "    export DEEPSEEK_API_KEY=sk-xxx"
echo ""
echo "  For DIDI LLM Proxy (internal):"
echo "    export DIDI_API_KEY=sk-xxx"
echo ""

echo -e "${CYAN}Font Configuration:${RESET}"
echo "  After installation, set your terminal font to:"
echo -e "    ${GREEN}Hack Nerd Font${RESET} (or any Nerd Font)"
echo ""

echo -e "${CYAN}Test the statusline:${RESET}"
echo "  Restart Claude Code or open a new session"
echo "  Or test manually:"
echo "    echo '{\"model\":{\"display_name\":\"test\"},\"workspace\":{\"current_dir\":\"/tmp\"},\"session_id\":\"test\",\"cost\":{\"total_cost_usd\":1.0}}' | ~/.claude/statusline-command.sh"
echo ""

echo -e "${GREEN}Done! Enjoy your statusline.${RESET}"
