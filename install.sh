#!/bin/sh
# cmux installer — run via: curl -fsSL <url> | sh
set -e

RELEASE_URL="https://github.com/smaiau/cmux/releases/latest/download"

INSTALL_DIR="$HOME/.cmux"
INSTALL_PATH="$INSTALL_DIR/cmux.sh"
INSTALL_PATH_TEAM="$INSTALL_DIR/cmux-team.sh"

# Download
mkdir -p "$INSTALL_DIR"
echo "Downloading cmux..."
curl -fsSL "$RELEASE_URL/cmux.sh" -o "$INSTALL_PATH"
curl -fsSL "$RELEASE_URL/cmux-team.sh" -o "$INSTALL_PATH_TEAM"
curl -fsSL "$RELEASE_URL/VERSION" | tr -d '[:space:]' > "$INSTALL_DIR/VERSION"

# Clear stale update-check cache from any previous install
rm -f "$INSTALL_DIR/.latest_version" "$INSTALL_DIR/.last_check"

# Detect shell rc file
case "$SHELL" in
  */zsh)  RC_FILE="$HOME/.zshrc" ;;
  *)      RC_FILE="$HOME/.bashrc" ;;
esac

SOURCE_LINE_CMUX='source "$HOME/.cmux/cmux.sh"'
SOURCE_LINE_TEAM='source "$HOME/.cmux/cmux-team.sh"'

# Idempotently add source lines
if ! grep -qF '.cmux/cmux.sh' "$RC_FILE" 2>/dev/null; then
  printf '\n# cmux\n%s\n%s\n' "$SOURCE_LINE_CMUX" "$SOURCE_LINE_TEAM" >> "$RC_FILE"
  echo "Added source lines to $RC_FILE"
else
  # Add cmux-team if only cmux is sourced
  if ! grep -qF 'cmux-team.sh' "$RC_FILE" 2>/dev/null; then
    printf '%s\n' "$SOURCE_LINE_TEAM" >> "$RC_FILE"
    echo "Added cmux-team source to $RC_FILE"
  else
    echo "Source lines already in $RC_FILE"
  fi
fi

echo ""
echo "cmux installed! To start using it:"
echo "  source $RC_FILE"
