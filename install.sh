#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Claude Code VSCode Extension Installer${NC}"
echo "========================================"
echo ""

# Prompt for Claude version
read -p "Enter the Claude Code version (e.g., 2.0.29): " CLAUDE_VERSION
if [ -z "$CLAUDE_VERSION" ]; then
    echo -e "${RED}Error: Claude version is required${NC}"
    exit 1
fi

# Prompt for Claude binary path
echo ""
echo "Enter the path to your Node.js Claude binary to symlink:"
echo "(e.g., /usr/local/bin/claude or ~/bin/claude)"
read -p "Claude binary path: " CLAUDE_BINARY_PATH

# Expand tilde to home directory if present
CLAUDE_BINARY_PATH="${CLAUDE_BINARY_PATH/#\~/$HOME}"

# Verify the binary exists
if [ ! -f "$CLAUDE_BINARY_PATH" ]; then
    echo -e "${RED}Error: Binary not found at $CLAUDE_BINARY_PATH${NC}"
    exit 1
fi

# Verify the binary is executable
if [ ! -x "$CLAUDE_BINARY_PATH" ]; then
    echo -e "${YELLOW}Warning: $CLAUDE_BINARY_PATH is not executable${NC}"
    read -p "Do you want to make it executable? (y/n): " MAKE_EXEC
    if [ "$MAKE_EXEC" = "y" ] || [ "$MAKE_EXEC" = "Y" ]; then
        chmod +x "$CLAUDE_BINARY_PATH"
        echo -e "${GREEN}Made binary executable${NC}"
    fi
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo ""
echo -e "${GREEN}Step 1: Updating package.json with version $CLAUDE_VERSION${NC}"

# Update version in package.json
if command -v jq &> /dev/null; then
    # Use jq if available for safer JSON manipulation
    jq --arg version "$CLAUDE_VERSION" '.version = $version' package.json > package.json.tmp
    mv package.json.tmp package.json
    echo -e "${GREEN}✓ Version updated using jq${NC}"
else
    # Fallback to sed (less safe but works)
    sed -i.bak "s/\"version\": \".*\"/\"version\": \"$CLAUDE_VERSION\"/" package.json
    rm -f package.json.bak
    echo -e "${GREEN}✓ Version updated using sed${NC}"
fi

echo ""
echo -e "${GREEN}Step 2: Creating symlink to Claude binary${NC}"

# Create the native-binary directory if it doesn't exist
mkdir -p resources/native-binary

# Remove existing symlink or file if it exists
if [ -e "resources/native-binary/claude" ] || [ -L "resources/native-binary/claude" ]; then
    rm -f resources/native-binary/claude
    echo "Removed existing file/symlink"
fi

# Create the symlink
ln -s "$CLAUDE_BINARY_PATH" resources/native-binary/claude
echo -e "${GREEN}✓ Symlink created: resources/native-binary/claude -> $CLAUDE_BINARY_PATH${NC}"

# Verify symlink was created successfully
if [ ! -L "resources/native-binary/claude" ]; then
    echo -e "${RED}Error: Failed to create symlink${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Step 3: Installing extension to VSCode${NC}"

# Check if VSCode CLI is available
if ! command -v code &> /dev/null; then
    echo -e "${RED}Error: VSCode CLI 'code' command not found${NC}"
    echo "Please ensure VSCode is installed and the 'code' command is in your PATH"
    echo "You can install it from VSCode: Cmd+Shift+P -> 'Shell Command: Install code command in PATH'"
    exit 1
fi

# Check if vsce is available for packaging
if command -v vsce &> /dev/null; then
    echo "Packaging extension with vsce..."
    vsce package --no-dependencies

    # Find the generated .vsix file
    VSIX_FILE=$(ls -t *.vsix 2>/dev/null | head -1)

    if [ -n "$VSIX_FILE" ]; then
        echo -e "${GREEN}✓ Extension packaged: $VSIX_FILE${NC}"
        echo "Installing extension from VSIX..."
        code --install-extension "$VSIX_FILE" --force
        echo -e "${GREEN}✓ Extension installed successfully!${NC}"
    else
        echo -e "${RED}Error: Failed to create VSIX package${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Warning: vsce not found. Installing extension from directory...${NC}"
    echo "Note: For production use, install vsce with: npm install -g @vscode/vsce"

    # Install from directory (development mode)
    # Create a symlink in VSCode extensions directory
    VSCODE_EXT_DIR="$HOME/.vscode/extensions"
    EXT_NAME="Anthropic.claude-code-$CLAUDE_VERSION"

    # Remove existing extension if present
    if [ -d "$VSCODE_EXT_DIR/$EXT_NAME" ]; then
        echo "Removing existing extension..."
        rm -rf "$VSCODE_EXT_DIR/$EXT_NAME"
    fi

    # Create symlink to current directory
    ln -s "$SCRIPT_DIR" "$VSCODE_EXT_DIR/$EXT_NAME"
    echo -e "${GREEN}✓ Extension linked to VSCode extensions directory${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Extension version: $CLAUDE_VERSION"
echo "Claude binary: $CLAUDE_BINARY_PATH"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Restart VSCode for the changes to take effect"
echo "2. Open the Command Palette (Cmd+Shift+P / Ctrl+Shift+P)"
echo "3. Search for 'Claude Code' to start using the extension"
echo ""
