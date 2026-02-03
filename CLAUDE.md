# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **custom-installed Claude Code VSCode extension** (publisher: Anthropic). It is a pre-built/distribution package — the source files (`extension.js`, `webview/index.js`, `webview/index.css`) are minified bundles, not editable source code. Development work in this repo centers on the installation tooling, configuration, and packaging.

## Installation & Setup

```bash
# Install the extension (interactive — prompts for version and binary path)
./install.sh

# Manual packaging (requires vsce: npm install -g @vscode/vsce)
vsce package --no-dependencies
code --install-extension *.vsix --force

# Manual symlink install (no vsce needed)
ln -s /path/to/claude resources/native-binary/claude
ln -s "$(pwd)" "$HOME/.vscode/extensions/Anthropic.claude-code-VERSION"
```

The install script: (1) updates `package.json` version, (2) symlinks `resources/native-binary/claude` to the user's Claude CLI binary, (3) packages and installs the extension.

## Architecture

Three-layer design communicating via message passing:

1. **Extension Host** (`extension.js`, 1.4MB minified) — VSCode extension API integration. Registers commands, spawns the Claude CLI as a child process, manages webview lifecycle, handles settings.

2. **Webview UI** (`webview/index.js` + `webview/index.css`, React) — Chat interface running in a sandboxed webview. Communicates with the extension host via `postMessage`.

3. **Claude CLI Binary** (`resources/native-binary/claude`, symlinked) — Platform-specific native binary spawned as a child process. Handles AI communication, file operations, and terminal commands. Communicates with the extension host via stdin/stdout JSON protocol.

## Key Files

- `package.json` — Extension manifest: commands, keybindings, settings, views, menus, walkthrough
- `claude-code-settings.schema.json` — JSON schema validating `.claude/settings.json` files
- `install.sh` — Installation automation script
- `resources/walkthrough/step1-4.md` — Onboarding content

## Important Conventions

- The native binary at `resources/native-binary/claude` is a symlink and is gitignored — never commit it
- No build step exists; the JS/CSS bundles are pre-built
- VSCode engine requirement: `^1.94.0`
- Extension uses two command prefixes: `claude-vscode.*` and `claude-code.*` (legacy compat)
- Platform target: `darwin-arm64` (see `package.json` `__metadata`)
