# Custom Installation Guide

This repository contains a modified version of the Claude Code VSCode extension that uses a symlink to your local Node.js Claude binary instead of bundling the native binary.

## Why This Approach?

- **Smaller Repository**: The native binary (~75MB) is excluded from the repository
- **Flexible Binary**: Symlink to any Claude binary on your system
- **Easy Updates**: Update your Claude binary independently of the extension

## Prerequisites

1. **VSCode** installed with the `code` command available in your PATH
   - Install via: VSCode → Command Palette (Cmd+Shift+P) → "Shell Command: Install 'code' command in PATH"

2. **Claude Binary** - A Node.js Claude binary installed on your system
   - This could be from npm, a custom build, or any compatible Claude CLI

3. **(Optional) vsce** - For packaging the extension as VSIX
   ```bash
   npm install -g @vscode/vsce
   ```

## Installation Steps

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
cd YOUR_REPO_NAME
```

### 2. Run the Installation Script

```bash
./install.sh
```

The script will prompt you for:
- **Claude Code Version**: Enter the version number (e.g., `2.0.29`)
- **Claude Binary Path**: Enter the full path to your Claude binary (e.g., `/usr/local/bin/claude`)

### 3. Restart VSCode

After installation completes, restart VSCode for the extension to load.

## What the Installation Script Does

1. **Updates `package.json`**: Sets the version you specified
2. **Creates Symlink**: Links `resources/native-binary/claude` to your Claude binary
3. **Installs Extension**:
   - If `vsce` is available: Packages as VSIX and installs
   - Otherwise: Creates a symlink in your VSCode extensions directory

## Manual Installation (Alternative)

If you prefer to install manually:

```bash
# 1. Update version in package.json manually
vim package.json

# 2. Create symlink to your Claude binary
mkdir -p resources/native-binary
ln -s /path/to/your/claude resources/native-binary/claude

# 3. Package (if vsce is installed)
vsce package --no-dependencies

# 4. Install
code --install-extension *.vsix --force

# OR link directly to extensions folder
ln -s "$(pwd)" "$HOME/.vscode/extensions/Anthropic.claude-code-VERSION"
```

## Verifying Installation

1. Open VSCode
2. Press `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Windows/Linux)
3. Type "Claude Code" and you should see the extension commands
4. Try opening Claude Code with `Cmd+Escape` or `Ctrl+Escape`

## Updating

To update the extension or change the Claude binary:

1. Pull the latest changes:
   ```bash
   git pull
   ```

2. Run the installation script again:
   ```bash
   ./install.sh
   ```

## Troubleshooting

### Extension Not Loading

- Verify VSCode version is 1.94.0 or higher
- Check Developer Tools (Help → Toggle Developer Tools) for errors
- Verify symlink: `ls -la resources/native-binary/claude`

### Claude Binary Not Found

- Verify the binary exists: `ls -la /path/to/claude`
- Verify it's executable: `chmod +x /path/to/claude`
- Try running it directly: `/path/to/claude --version`

### Permission Errors

- Make sure you have write access to VSCode extensions directory
- Try running with sudo if needed (not recommended)

## File Structure

```
.
├── install.sh                      # Installation script
├── .gitignore                      # Excludes native binary
├── package.json                    # Extension manifest
├── extension.js                    # Main extension code
├── resources/
│   └── native-binary/
│       └── claude                  # Symlink (created during install)
└── webview/                        # UI components
```

## Contributing

When contributing to this repository:

1. Never commit the `resources/native-binary/claude` file (it's in .gitignore)
2. Test the installation script on a clean system before submitting PRs
3. Update this documentation if you change the installation process

## License

© Anthropic PBC. All rights reserved. Use is subject to the Legal Agreements outlined here: https://docs.claude.com/en/docs/claude-code/legal-and-compliance.
