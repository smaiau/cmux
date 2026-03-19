#!/bin/bash
# cmux installer — installs cmux + cmux-team to ~/.cmux/
set -e

INSTALL_DIR="$HOME/.cmux"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing cmux to $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR"

# Copy scripts
cp "$REPO_DIR/cmux.sh" "$INSTALL_DIR/cmux.sh"
cp "$REPO_DIR/cmux-team.sh" "$INSTALL_DIR/cmux-team.sh"
cp "$REPO_DIR/VERSION" "$INSTALL_DIR/VERSION"

# Detect shell config
if [[ -n "$ZSH_VERSION" ]] || [[ "$SHELL" == */zsh ]]; then
  RC_FILE="$HOME/.zshrc"
else
  RC_FILE="$HOME/.bashrc"
fi

# Check if already sourced
SOURCE_LINE_CMUX='source "$HOME/.cmux/cmux.sh"'
SOURCE_LINE_TEAM='source "$HOME/.cmux/cmux-team.sh"'

if ! grep -qF 'cmux/cmux.sh' "$RC_FILE" 2>/dev/null; then
  echo "" >> "$RC_FILE"
  echo "# cmux" >> "$RC_FILE"
  echo "$SOURCE_LINE_CMUX" >> "$RC_FILE"
  echo "$SOURCE_LINE_TEAM" >> "$RC_FILE"
  echo "Added source lines to $RC_FILE"
else
  echo "Already sourced in $RC_FILE"
fi

# Add cmux-team if only cmux is sourced
if ! grep -qF 'cmux-team.sh' "$RC_FILE" 2>/dev/null; then
  echo "$SOURCE_LINE_TEAM" >> "$RC_FILE"
  echo "Added cmux-team source to $RC_FILE"
fi

echo ""
echo "Installed! Restart your shell or run:"
echo "  source $RC_FILE"
