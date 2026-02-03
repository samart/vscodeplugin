# 06 - VSCode Extension Reverse Engineering

> Systematic analysis of the Claude Code VSCode extension (v2.1.29) minified sources.
> All findings derived from pattern-matching against `extension.js` (~318 lines minified, ~1.3MB)
> and `webview/index.js` (~1431 lines minified, ~882KB React app).

---

## Table of Contents

1. [Process Spawning & Lifecycle](#1-process-spawning--lifecycle)
2. [JSON Message Protocol (Extension <-> CLI)](#2-json-message-protocol-extension---cli)
3. [Webview Initialization](#3-webview-initialization)
4. [Webview Communication Bridge](#4-webview-communication-bridge)
5. [Editor Context Gathering](#5-editor-context-gathering)
6. [File Operations](#6-file-operations)
7. [Diff & Proposed Changes](#7-diff--proposed-changes)
8. [Terminal Mode](#8-terminal-mode)
9. [Authentication Flow](#9-authentication-flow)
10. [Status Bar Updates](#10-status-bar-updates)
11. [Panel/Sidebar Management](#11-panelsidebar-management)
12. [Configuration Handling](#12-configuration-handling)
13. [MCP Server Integration](#13-mcp-server-integration)
14. [All Discovered Message Types](#14-all-discovered-message-types)
15. [IntelliJ Adaptation Notes](#15-intellij-adaptation-notes)

---

## 1. Process Spawning & Lifecycle

### 1.1 Binary Discovery (`getClaudeBinary`)

The extension resolves the Claude CLI binary through a multi-step search:

```
// Pattern: getClaudeBinary
// Found in: extension.js

getClaudeBinary(){
  let r, n=[], i=false;

  // Step 1: Check platform-specific native binary
  {let s = P_e(this.context); s && (r = s)}

  // Step 2: Fall back to bundled binary
  if(!r) {
    let s = this.context.asAbsolutePath(join("resources","native-binary",e));
    if(existsSync(s)) return s;
  }

  // Step 3: Check claudeProcessWrapper setting (custom wrapper)
  let o = vr("claudeProcessWrapper");
  return o && (n=[r], i && n.unshift("node"), r=o),
    {pathToClaudeCodeExecutable:r, executableArgs:n, env:mb()}
}
```

**Platform-specific binary resolution** (`P_e` function):
- Looks for native binaries in `resources/native-binary/{platform}-{arch}/`
- Falls back to `resources/native-binary/{binaryName}`
- On Windows, also tries `where.exe` to locate the binary

**Key findings:**
- Binary name: `claude` (platform native binary)
- If binary is a `.js` file, it spawns with `node` as the interpreter
- The `claudeProcessWrapper` setting allows wrapping the process (e.g., for Docker)
- Environment variables are gathered via `mb()` which merges `process.env` with configured env vars

### 1.2 Process Spawning

```
// Pattern: spawnClaude / spawnLocalProcess
// Found in: extension.js

async spawnClaude(r, n, i, o, s, a, c, l, u={}) {
  // I_e() - validates environment (checks for win32 where.exe etc.)
  let d = new Hh(Gl(this.output));  // Logger wrapper
  let m = {
    cwd: s || this.cwd,
    resume: n,                       // Resume session ID
    canUseTool: i,                   // Permission callback
    permissionMode: a,               // "default" | "acceptEdits" | "plan" | "bypassPermissions"
    allowDangerouslySkipPermissions: c,
    model: o === null ? "default" : o,
    stderr: y => { /* log stderr */ },
    maxThinkingTokens: l,
    includePartialMessages: true,
    hooks: {
      PreToolUse: [
        {matcher: "Edit|Write|Read", hooks: [y => this.saveFileIfNeeded(y)]}
      ],
      PostToolUse: [
        {matcher: "Edit|Write|MultiEdit", hooks: [y => d.findDiagnosticsProblems(y)]}
      ]
    },
    settingSources: ["user", "project", "local"],
    // ... more options
  };
}
```

**The spawning uses the Claude Agent SDK** (`Lm` function which is the SDK's main entry point):
```
// The actual spawn
Lm({prompt: r, options: m})
```

**Process I/O model:**
```
// ProcessTransport class handles I/O
spawnLocalProcess(e) {
  let {command, args, cwd, env, signal} = e;
  let c = spawn(command, args, {
    cwd: cwd,
    stdio: ["pipe", "pipe", a],   // stdin=pipe, stdout=pipe, stderr=pipe/ignore
    signal: s,
    env: o,
    windowsHide: true
  });
  return c;
}

// After spawn:
this.processStdin = this.process.stdin;
this.processStdout = this.process.stdout;
```

### 1.3 Process Communication Protocol

**Line-delimited JSON over stdin/stdout:**

```
// Reading: Uses readline.createInterface on stdout
async* readMessages() {
  let e = createInterface({input: this.processStdout});
  for await (let r of e)
    if (r.trim())
      yield JSON.parse(r);  // Each line is a JSON message
}

// Writing: JSON + newline to stdin
// Pattern: [ProcessTransport] Writing to stdin
this.processStdin.write(e)  // e is JSON string
// Messages are written as: JSON.stringify(msg) + "\n"
```

**This is a newline-delimited JSON (NDJSON) protocol.** Each message is a single line of JSON.

### 1.4 Process Termination

```
// Graceful shutdown: SIGTERM first, then SIGKILL after 5 seconds
let R = () => {
  this.process && !this.process.killed && this.process.kill("SIGTERM")
};
this.processExitHandler = R;
process.on("exit", this.processExitHandler);

// Full close:
this.process.kill("SIGTERM");
setTimeout(() => {
  this.process && !this.process.killed && this.process.kill("SIGKILL");
}, 5000);
this.ready = false;

// Also closes stdin:
this.processStdin.end();
```

### 1.5 Abort Controller Integration

```
// Each spawn gets an AbortController
this.abortController = e.abortController || new AbortController();

// The signal is passed to spawn:
{signal: this.abortController.signal}

// Abort handler kills the process:
this.abortHandler = R;  // R = SIGTERM kill function
```

### IntelliJ Adaptation Notes

- **Binary discovery**: Port the multi-step lookup to `GeneralCommandLine` resolution
- **Process I/O**: Use `ProcessHandler` with `BaseOutputReader` for stdout line reading
- **NDJSON protocol**: Parse each stdout line as JSON, write JSON + newline to stdin
- **Termination**: Use `ProcessHandler.destroyProcess()` with graceful timeout
- **AbortController**: Map to `ProcessHandler.destroyProcess()` + coroutine cancellation

---

## 2. JSON Message Protocol (Extension <-> CLI)

### 2.1 Messages FROM CLI Process (stdout)

The SDK yields these message types on stdout (one JSON object per line):

| Message Type | Description |
|---|---|
| `user` | User message echo: `{type:"user", message, uuid, session_id, parent_tool_use_id}` |
| `assistant` | Assistant response: `{type:"assistant", message, uuid, session_id, parent_tool_use_id}` |
| `system` | System message |
| `result` | Final result of a query |
| `error` | Error from SDK |
| `tool_use` | Tool invocation by the model |
| `tool_result` | Result of a tool call |
| `progress` | Progress/status update |
| `control_response` | Response to a control request (subtype: "success" or "error") |

### 2.2 Control Request Subtypes (Extension -> CLI via stdin)

These are sent as control messages to the running CLI process:

| Subtype | Description |
|---|---|
| `initialize` | Initialize the session |
| `interrupt` | Interrupt current generation |
| `set_model` | Change the model mid-session |
| `set_max_thinking_tokens` | Change thinking level |
| `set_permission_mode` | Change permission mode |
| `mcp_message` | Send MCP protocol message |
| `mcp_reconnect` | Reconnect an MCP server |
| `mcp_set_servers` | Update MCP server configuration |
| `mcp_toggle` | Enable/disable an MCP server |
| `mcp_status` | Get MCP server status |
| `rewind_files` | Rewind file changes to a checkpoint |

### 2.3 User Input Messages (Extension -> CLI via stdin)

```
// User message format:
{type:"user", session_id:"", message:{role:"user", content:[{type:"text", text:"..."}]}, parent_tool_use_id:null}

// Tool permission response:
{...canUseTool response, behavior:"allow"|"deny", message:"..."}
```

### IntelliJ Adaptation Notes

- The protocol is purely JSON-over-NDJSON; no change needed for IntelliJ
- Parse each stdout line independently; buffer partial lines
- Control requests go to stdin as single-line JSON

---

## 3. Webview Initialization

### 3.1 HTML Template Construction

```
// Function: getHtmlForWebview(webview, resume, prompt, isSidebar)

// Resource URIs
let jsUri = webview.asWebviewUri(Uri.joinPath(extensionUri, "webview", "index.js"));
let cssUri = webview.asWebviewUri(Uri.joinPath(extensionUri, "webview", "index.css"));

// CSP nonce for script security
let nonce = randomUUID();

// Content Security Policy
let styleSrc = `style-src ${webview.cspSource} 'unsafe-inline'`;
let fontSrc = `font-src ${webview.cspSource}`;
let imgSrc = `img-src ${webview.cspSource} data:`;
let workerSrc = `worker-src ${webview.cspSource}`;

// Font configuration from VSCode settings
let fontFamily = workspace.getConfiguration("chat.editor").get("fontFamily") || "monospace";
let fontSize = workspace.getConfiguration("chat.editor").get("fontSize") || 12;
let chatFontSize = workspace.getConfiguration("chat").get("fontSize");
let chatFontFamily = workspace.getConfiguration("chat").get("fontFamily") || "system-ui, ...sans-serif";
```

**Generated HTML:**
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy"
        content="default-src 'none';
                 style-src ${cspSource} 'unsafe-inline';
                 font-src ${cspSource};
                 img-src ${cspSource} data:;
                 script-src 'nonce-${nonce}';
                 worker-src ${cspSource};">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link href="${cssUri}" rel="stylesheet">
  <!-- CSS variables for font config are injected inline -->
</head>
<body>
  <div id="root"></div>
  <div id="claude-error"></div>
  <script nonce="${nonce}" src="${jsUri}"></script>
</body>
</html>
```

### 3.2 Webview React App Initialization

```javascript
// webview/index.js entry point (iNt function):
function iNt() {
  let api = acquireVsCodeApi();             // VSCode API handle
  let stateManager = new RJ(api);           // Wraps getState/setState
  let permissionReq = new Fc();             // Signal channel
  let atMention = new Fc();                 // Signal channel
  let selectionChanged = new Fc();          // Signal channel
  let fontConfig = new Fc();                // Signal channel

  let transport = new MJ(api, permissionReq, atMention, selectionChanged, fontConfig);
  // MJ extends Y3 (base transport class)

  let sessionManager = new G3(() => transport);  // Session manager
  let tabManager = new PJ(sessionManager, ...);  // Tab management
  // ... React root render
}
```

### 3.3 Webview Transport (Y3 base class -> MJ subclass)

```javascript
// Y3 = base transport class
class Y3 {
  state = signal("connecting");
  isVisible = signal(true);
  fromHost = new AsyncQueue();        // Messages FROM extension host
  streams = new Map();                // Per-channel message streams
  speechToTextStreams = new Map();
  permissionRequests = signal([]);
  authStatus = signal(undefined);
  config = signal(undefined);
  claudeConfig = signal(undefined);
  outstandingRequests = new Map();
  // ...
}

// MJ = VSCode webview transport implementation
class MJ extends Y3 {
  constructor(api, ...) {
    super(...);
    this.api = api;
    this.state.value = "connected";

    // Listen for messages from extension host
    window.addEventListener("message", (event) => {
      if (event.data.type === "from-extension") {
        this.fromHost.enqueue(event.data.message);
      }
    });

    this.opened = this.requestInit();
  }

  send(msg) { this.api.postMessage(msg); }
  close() {}
}
```

### IntelliJ Adaptation Notes

- **HTML generation**: Generate equivalent HTML for JCEF webview
- **CSP**: JCEF has its own security model; CSP may not be needed
- **Resource URIs**: Use `JBCefBrowser.getCefBrowser().getURL()` for base, or custom scheme handler
- **acquireVsCodeApi**: Replace with a bridge object injected via `JBCefJSQuery`
- **Font configuration**: Read IntelliJ editor font settings and inject as CSS variables

---

## 4. Webview Communication Bridge

### 4.1 Extension -> Webview

**Wrapping pattern:**
```javascript
// Extension sends TO webview:
send(message) {
  this.sendQueue = this.sendQueue.then(() =>
    this.webview.postMessage({type: "from-extension", message: message})
      .then(() => {})
  );
}
```

All messages from the extension are wrapped in `{type: "from-extension", message: <payload>}`.

### 4.2 Webview -> Extension

```javascript
// Webview sends TO extension:
send(msg) { this.api.postMessage(msg); }

// Extension receives FROM webview:
webview.onDidReceiveMessage(msg => {
  this.output.info(`Received message from webview: ${JSON.stringify(msg)}`);
  comm?.fromClient(msg);
});
```

Webview messages are sent directly as the payload (no wrapper).

### 4.3 Request/Response Pattern

The webview uses a request/response pattern with request IDs:

```javascript
// Webview sends request:
sendRequest(request, channelId) {
  let requestId = generateId();
  return new Promise((resolve, reject) => {
    this.outstandingRequests.set(requestId, {resolve, reject});
    this.send({type: "request", channelId, requestId, request});
  });
}

// Extension processes and responds:
handleRequest(e) {
  let response = await this.processRequest(e);
  this.send({type: "response", requestId: e.requestId, response});
}
```

### 4.4 Extension-Initiated Pushes to Webview

These are unsolicited messages pushed from extension to webview:

| Push Message Type | Description |
|---|---|
| `io_message` | CLI output forwarded to webview: `{type:"io_message", channelId, message, done}` |
| `close_channel` | Channel closed: `{type:"close_channel", channelId, error?}` |
| `file_updated` | File was modified: `{type:"file_updated", channelId, filePath, oldContent, newContent}` |
| `request` (update_state) | State push: `{type:"request", request:{type:"update_state", state, config}}` |
| `request` (insert_at_mention) | @-mention insertion: `{type:"request", request:{type:"insert_at_mention", text}}` |
| `request` (selection_changed) | Editor selection changed: `{type:"request", request:{type:"selection_changed", selection}}` |
| `request` (visibility_changed) | Panel visibility changed |
| `request` (font_configuration_changed) | Font settings changed |
| `request` (create_new_conversation) | New conversation requested |
| `request` (auth_url) | OAuth redirect URL |
| `request` (usage_update) | Usage/billing update |
| `request` (proactive_suggestions_update) | Proactive suggestions |
| `request` (open_plugins_dialog) | Open plugins dialog |

### IntelliJ Adaptation Notes

- **postMessage/onDidReceiveMessage**: Replace with `JBCefJSQuery` for Java->JS and JS->Java
- **Message wrapping**: Keep the `{type:"from-extension", message}` pattern
- **Request/Response**: Implement the same requestId-based pattern over JCEF bridge
- **Async queue**: The webview uses `AsyncQueue` (signal-based); implement equivalent

---

## 5. Editor Context Gathering

### 5.1 Selection Tracking

```javascript
// Active editor selection tracking
function w9(callback, registerEvent, settings) {
  registerEvent(() => {
    let editor = window.activeTextEditor;
    if (!editor) return;
    let selection = editor.selection;
    let info = {filePath: editor.document.uri.fsPath};
    if (!selection.isEmpty) {
      info.lineStart = selection.start.line;
      info.lineEnd = selection.end.line;
    }
    // Fires selection_changed event
  });
}

// Detailed selection with text
function x9(subscriptions, selectionChangedEvent) {
  let debounceTimer = null;
  window.onDidChangeTextEditorSelection(event => {
    let editor = event.textEditor;
    let selection = editor.selection;
    let document = editor.document;
    let text = document.getText(selection);

    if (document.uri.scheme === "comment" || document.uri.scheme === "output") return;

    let info = {
      text: text,
      filePath: document.uri.fsPath,
      // ... line info
    };
    selectionChangedEvent.fire(info);
  });
}
```

### 5.2 get_current_selection Request

```javascript
// Webview requests current selection
processRequest(request) {
  if (request.type === "get_current_selection") {
    return {
      type: "get_current_selection_response",
      selection: this.getCurrentSelection()
    };
  }
}
```

### 5.3 @-Mention / Insert At Mention

```javascript
// Alt+K keybinding handler
commands.registerCommand("claude-vscode.insertAtMention", async () => {
  let editor = window.activeTextEditor;
  if (!editor) return;
  let document = editor.document;
  let relativePath = workspace.asRelativePath(document.fileName);
  let selection = editor.selection;

  // If selection is empty, just insert file path
  // If selection has text, insert file path + selection range

  // Then send to webview:
  this.send({type:"request", request:{type:"insert_at_mention", text: mentionText}});
  this.panelTab?.reveal();
});
```

### 5.4 MCP Tools for Editor Access

The extension registers MCP tools that the CLI can call:

| MCP Tool | Description |
|---|---|
| `getCurrentSelection` | Get current editor selection text |
| `getLatestSelection` | Get the most recent selection |
| `getOpenEditors` | List all open editor tabs |
| `getWorkspaceFolders` | List workspace folders |
| `getDiagnostics` | Get IDE diagnostic problems |
| `openFile` | Open a file in the editor |
| `openDiff` | Open a diff view |
| `closeAllDiffTabs` | Close all open diff tabs |
| `checkDocumentDirty` | Check if a document has unsaved changes |
| `saveDocument` | Save a document |
| `close_tab` | Close a tab |
| `executeCode` | Execute code (Jupyter) |

### IntelliJ Adaptation Notes

- **Selection tracking**: Use `SelectionListener` and `CaretListener` on `Editor`
- **File path**: Use `VirtualFile.getPath()` and project-relative conversion
- **@-mention**: Register action, get selected text from `Editor.getSelectionModel()`
- **MCP tools**: Register equivalent tools using IntelliJ APIs

---

## 6. File Operations

### 6.1 Autosave Before Tool Use

```javascript
// PreToolUse hook for autosave
async saveFileIfNeeded(hookEvent) {
  if (!vr("autosave")) return {continue: true};
  if (hookEvent.hook_event_name !== "PreToolUse") return {continue: true};
  if (hookEvent.tool_name !== "Edit" && hookEvent.tool_name !== "Write"
      && hookEvent.tool_name !== "Read") return {continue: true};

  // Find the document and save it
  let document = findOpenDocument(toolInput.file_path);
  if (document && document.isDirty) {
    await document.save();
  }
  return {continue: true};
}
```

### 6.2 File Updated Notifications

```javascript
// When CLI modifies a file, extension notifies webview
(filePath, oldContent, newContent) => {
  if (!isIgnored(filePath)) {
    this.send({
      type: "file_updated",
      channelId: channelId,
      filePath: filePath,
      oldContent: oldContent,
      newContent: newContent
    });
  }
}
```

### 6.3 Open File Command

```javascript
async openFile(filePath, location) {
  let absolutePath = isAbsolute(filePath) ? filePath : join(this.cwd, filePath);

  // If file doesn't exist, try fuzzy search
  if (!existsSync(absolutePath) && !isAbsolute(filePath)) {
    let matches = await findFiles(filePath);
    if (matches.length > 0) absolutePath = join(this.cwd, matches[0].path);
  }

  let uri = Uri.file(absolutePath);
  // Open in editor with showTextDocument
}
```

### 6.4 List Files

The extension can list files in the workspace, respecting `.gitignore` and search excludes:

```javascript
// Uses VSCode workspace.findFiles with exclusion patterns from:
// - search.exclude settings
// - files.exclude settings
// - .gitignore (when claudeCode.respectGitIgnore is true)
```

### IntelliJ Adaptation Notes

- **Autosave**: Use `FileDocumentManager.getInstance().saveDocument()`
- **File change notifications**: Use `VirtualFileListener` or `BulkFileListener`
- **Open file**: Use `FileEditorManager.getInstance().openFile()`
- **File search**: Use `FilenameIndex` and `ProjectFileIndex`

---

## 7. Diff & Proposed Changes

### 7.1 Diff Architecture

The extension uses **three virtual filesystem providers** for diff:

1. **`_claude_vscode_fs_left`** - Left side (original content), registered as `FileSystemProvider`
2. **`_claude_vscode_fs_right`** - Right side (proposed content), registered as `FileSystemProvider`
3. **`_claude_vscode_fs_readonly`** - Read-only content view, registered as `TextDocumentContentProvider`

```javascript
let leftProvider = new mf("_claude_vscode_fs_left");    // In-memory FS
let rightProvider = new mf("_claude_vscode_fs_right");   // In-memory FS
let readOnlyProvider = new vb("_claude_vscode_fs_readonly"); // Content provider

workspace.registerFileSystemProvider(leftProvider.scheme, leftProvider);
workspace.registerFileSystemProvider(rightProvider.scheme, rightProvider);
workspace.registerTextDocumentContentProvider(readOnlyProvider.scheme, readOnlyProvider);
```

### 7.2 Opening a Diff

```javascript
async function openDiff(output, leftProvider, rightProvider, originalPath, newPath, edits, supportMultiEdits, acceptOrRejectDiffs, channel) {
  let title = `* [Claude Code] ${filename}`;

  // Create temp files in virtual filesystem
  let leftUri = leftProvider.createFile(originalPath, originalContent).uri;
  let rightUri = rightProvider.createFile(newPath, proposedContent).uri;

  // Open diff editor
  let diffEditor = await workspace.openTextDocument(rightUri);
  await commands.executeCommand("vscode.diff", leftUri, rightUri, title);

  // Wait for accept/reject
  return new Promise((resolve) => {
    acceptOrRejectDiffs.event(({accepted, activeTab}) => {
      resolve(accepted ? newEdits : []);
    });
  });
}
```

### 7.3 Accept/Reject UI

The diff editor gets toolbar buttons:

```javascript
// Accept button (check icon)
commands.registerCommand("claude-vscode.acceptProposedDiff", () => {
  let activeTab = window.tabGroups.activeTabGroup.activeTab;
  emitter.fire({accepted: true, activeTab});
});

// Reject button (discard icon)
commands.registerCommand("claude-vscode.rejectProposedDiff", () => {
  let activeTab = window.tabGroups.activeTabGroup.activeTab;
  emitter.fire({accepted: false, activeTab});
});

// Context key for showing/hiding buttons
onDidChangeVisibleTextEditors(editors => {
  let isViewingDiff = editors.some(e => e?.document.uri.scheme === scheme);
  commands.executeCommand("setContext", "claude-vscode.viewingProposedDiff", isViewingDiff);
});
```

### 7.4 Multi-File Diffs (open_file_diffs)

```javascript
async openFileDiffs(request) {
  let diffs = [];
  for (let [path, diffInfo] of Object.entries(request.diffs)) {
    if (diffInfo.oldContent === diffInfo.newContent) continue;
    let absolutePath = isAbsolute(path) ? path : join(this.cwd, path);
    let leftUri = diffInfo.oldContent !== null
      ? this.leftTempFileProvider.createFile(absolutePath, diffInfo.oldContent).uri
      : undefined;
    let rightUri = diffInfo.newContent !== null
      ? this.readOnlyTempFileProvider.createFile(absolutePath, diffInfo.newContent)
      : undefined;
    diffs.push([Uri.file(absolutePath), leftUri, rightUri]);
  }
  // Open multi-diff view
}
```

### 7.5 File Watching During Diff

```javascript
// While diff is open, watch for external changes to the file
workspace.onDidChangeTextDocument(event => {
  if (event.document.uri.toString() === fileUri.toString()) {
    // Track content changes for conflict detection
    previousContent = currentContent;
    currentContent = event.document.getText();
  }
});

// When autoSave is off, also wait for manual save
workspace.onWillSaveTextDocument(event => {
  if (event.document.uri.toString() === fileUri.toString()) {
    let content = event.document.getText();
    // Capture saved content
  }
});
```

### IntelliJ Adaptation Notes

- **Virtual FS for diff**: Use `LightVirtualFile` or custom `VirtualFileSystem`
- **Diff viewer**: Use `DiffManager.getInstance().showDiff()` with `SimpleDiffRequest`
- **Accept/Reject**: Add toolbar actions to the diff editor
- **Context key**: Use `DataContext` and custom conditions
- **Multi-file diff**: Use `ChainDiffRequest` or sequential diffs

---

## 8. Terminal Mode

### 8.1 Terminal Creation

```javascript
// When useTerminal setting is true
let terminal = window.createTerminal({
  name: process.env.CLAUDE_CODE_TERMINAL_TITLE || "Claude Code",
  iconPath: Uri.file(join(extensionPath, "resources", "claude-logo.svg")),
  cwd: workingDir || this.cwd,
  location: location,   // ViewColumn.Beside or ViewColumn.One
  isTransient: true,
  env: envVars,
  strictEnv: true
});

// Launch command via shell integration or fallback
terminal.shellIntegration.executeCommand(quote(command));

// Fallback after 3 seconds if shell integration unavailable:
setTimeout(() => {
  if (!terminal.shellIntegration && !sent) {
    sent = true;
    let args = ["claude", ...additionalArgs];
    if (resume) args.push(resume);
    terminal.sendText(quote(args));
  }
}, 3000);

terminal.show();
```

### 8.2 Terminal Contents Reading

```javascript
// get_terminal_contents command
async getTerminalContents(terminalName) {
  let terminal = window.terminals.find(t =>
    t.name.replace(/ /g, "_") === terminalName
  );
  if (!terminal) return null;

  // Uses clipboard workaround to read terminal contents
  let previousClipboard = await env.clipboard.readText();
  terminal.show();
  await commands.executeCommand("workbench.action.terminal.selectAll");
  await commands.executeCommand("workbench.action.terminal.copySelection");
  let contents = await env.clipboard.readText();
  await env.clipboard.writeText(previousClipboard);  // Restore clipboard
  return contents;
}
```

### IntelliJ Adaptation Notes

- **Terminal creation**: Use `TerminalView.createNewSession()` or `LocalTerminalDirectRunner`
- **Shell integration**: IntelliJ terminal has its own shell integration
- **Terminal contents**: Use `TerminalWidget.getTerminalTextBuffer()`
- **Keybindings**: Map Cmd+Escape to focus terminal when in terminal mode

---

## 9. Authentication Flow

### 9.1 Auth Methods

Three authentication methods discovered:

| authMethod | Description |
|---|---|
| `"claudeai"` | OAuth with claude.ai (consumer) |
| `"api-key"` | Direct API key |
| `"3p"` | Third-party (Bedrock/Vertex) |
| `"not-specified"` | Auth disabled or not configured |

### 9.2 OAuth Configuration

```javascript
// Production OAuth config
{
  BASE_API_URL: "https://api.anthropic.com",
  CONSOLE_AUTHORIZE_URL: "https://platform.claude.com/oauth/authorize",
  CLAUDE_AI_AUTHORIZE_URL: "https://claude.ai/oauth/authorize",
  TOKEN_URL: "https://platform.claude.com/v1/oauth/token",
  API_KEY_URL: "https://api.anthropic.com/api/oauth/claude_cli/create_api_key",
  ROLES_URL: "https://api.anthropic.com/api/oauth/claude_cli/roles",
  CLIENT_ID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
  MANUAL_REDIRECT_URL: "https://platform.claude.com/oauth/code/callback"
}

// OAuth scopes
let scopes = [
  "user:profile",
  "user:inference",
  "user:sessions:claude_code",
  "user:mcp_servers",
  "org:create_api_key"
];
```

### 9.3 Login Flow

```javascript
// case "login":
if (!this.authManager) throw new Error("Authentication is not supported");
let {method} = request;  // "claudeai" or other method
let authResult = await this.authManager.login(method, async (oauthInfo) => {
  // Send auth URL to webview for display
  this.send({
    type: "request",
    channelId: "",
    requestId: generateId(),
    request: {
      type: "auth_url",
      url: oauthInfo.manualRedirectUrl,
      method: method
    }
  });
  // Wait for OAuth callback
});
this.closeAllChannelsWithCredentialChange();
return {type: "login_response", auth: authResult};

// Manual OAuth code submission
// case "submit_oauth_code":
this.authManager.handleManualAuthCode(code);
return {type: "submit_oauth_code_response"};
```

### 9.4 Auth Status Check

```javascript
getAuthStatus() {
  if (this.disableAuthLogin) {
    return {authMethod: "not-specified", email: null, subscriptionType: null};
  }
  if (env.CLAUDE_CODE_USE_BEDROCK || env.CLAUDE_CODE_USE_VERTEX) {
    return {authMethod: "3p", ...};
  }
  // Check for OAuth tokens, API keys, etc.
}
```

### 9.5 Subscription Types

```javascript
// case statements for subscription types:
case "claude_enterprise":
case "claude_max":
case "claude_pro":
case "claude_team":
```

### IntelliJ Adaptation Notes

- **OAuth flow**: Use `com.intellij.ide.BrowserUtil` to open auth URL
- **Token storage**: Use `PasswordSafe` for secure credential storage
- **Auth status**: Same API, different UI for status display
- **Login prompt**: Use `com.intellij.notification.Notification` for prompts

---

## 10. Status Bar Updates

### 10.1 Status Bar Item

```javascript
let statusBarItem = window.createStatusBarItem(StatusBarAlignment.Right);
statusBarItem.text = "\u273B Claude Code";  // Unicode asterisk + name
statusBarItem.command = "claude-vscode.editor.openLast";
statusBarItem.tooltip = "Open Claude Code";

// Show only in sidebar mode
if (settings.getPreferredLocation() === "sidebar" && hasSidebar) {
  statusBarItem.show();
}
```

### 10.2 Tab Title Updates

```javascript
// Tab renamed based on conversation state
if (this.panelTab) {
  this.panelTab.title = request.title;

  // Icon changes based on permission state
  if (request.hasPendingPermissions) {
    iconPath = "claude-logo-pending.svg";
  } else {
    iconPath = "claude-logo-done.svg";  // or default
  }
}
```

### IntelliJ Adaptation Notes

- **Status bar**: Use `StatusBar` widget or `StatusBarWidget.TextPresentation`
- **Tool window title**: Update via `ToolWindow.setTitle()`
- **Icon changes**: Use `ToolWindow.setIcon()` with different icon states

---

## 11. Panel/Sidebar Management

### 11.1 Panel Types

The extension supports three display modes:

1. **Editor Tab (Panel)**: `createWebviewPanel("claudeVSCodePanel", "Claude Code", column, options)`
2. **Primary Sidebar**: `registerWebviewViewProvider("claudeVSCodeSidebar", provider, options)`
3. **Secondary Sidebar**: `registerWebviewViewProvider("claudeVSCodeSidebarSecondary", provider, options)`

### 11.2 Panel Creation

```javascript
// Editor tab panel
let panel = window.createWebviewPanel(
  "claudeVSCodePanel",   // viewType
  "Claude Code",          // title
  viewColumn,             // Where to show
  {
    enableScripts: true,
    retainContextWhenHidden: true,  // Keep state when tab not visible
    enableFindWidget: true,          // Ctrl+F search in webview
    localResourceRoots: [
      Uri.joinPath(extensionUri, "webview"),
      Uri.joinPath(extensionUri, "resources")
    ]
  }
);
```

### 11.3 Sidebar Registration

```javascript
// Sidebar view provider
resolveWebviewView(webviewView, context, token) {
  let visibility = {isVisible: () => webviewView.visible};
  this.webviews.add(visibility);

  webviewView.webview.options = {
    enableScripts: true,
    localResourceRoots: [
      Uri.joinPath(this.extensionUri, "webview"),
      Uri.joinPath(this.extensionUri, "resources")
    ]
  };

  webviewView.webview.html = this.getHtmlForWebview(webviewView.webview, ...);

  // Create communication channel
  let comm = new CommunicationHandler(context, cwd, settings, webviewView.webview, ...);
  this.allComms.add(comm);

  // Handle incoming messages
  webviewView.webview.onDidReceiveMessage(msg => {
    comm?.fromClient(msg);
  });
}
```

### 11.4 Preferred Location

```javascript
// Settings-driven location preference
getPreferredLocation() {
  return vr("preferredLocation") === "sidebar" ? "sidebar" : "panel";
}

// Persisted when user moves the panel
async setPreferredLocation(location) {
  await workspace.getConfiguration("claudeCode")
    .update("preferredLocation", location, ConfigurationTarget.Global);
}
```

### 11.5 Secondary Sidebar Support

```javascript
// Detect if secondary sidebar is supported (VSCode 1.94+)
// If not, fall back to primary sidebar
commands.executeCommand("setContext",
  "claude-code:doesNotSupportSecondarySidebar", true);

// Register both sidebar providers
window.registerWebviewViewProvider("claudeVSCodeSidebar", provider,
  {webviewOptions: {retainContextWhenHidden: true}});
window.registerWebviewViewProvider("claudeVSCodeSidebarSecondary", provider,
  {webviewOptions: {retainContextWhenHidden: true}});
```

### 11.6 Visibility Tracking

```javascript
// Panel visibility changes
panel.onDidChangeViewState(() =>
  comm.notifyVisibilityChange(panel.visible)
);

// Sidebar visibility changes
webviewView.onDidChangeVisibility(() =>
  comm.notifyVisibilityChange(webviewView.visible)
);

// Sends to webview:
send({type:"request", request:{type:"visibility_changed", visible: isVisible}})
```

### IntelliJ Adaptation Notes

- **Editor tab**: Use `FileEditorProvider` with JCEF-based editor
- **Sidebar/Tool Window**: Use `ToolWindowFactory` with JCEF panel
- **retainContextWhenHidden**: JCEF naturally retains state; no special handling needed
- **Find widget**: Implement custom search over JCEF content
- **Preferred location**: Store in `PropertiesComponent`
- **Visibility**: Use `ToolWindowManagerListener` for tool window events

---

## 12. Configuration Handling

### 12.1 Settings Class

```javascript
// Settings wrapper (Oh class)
class Settings {
  constructor(context) { this.context = context; }

  getModel() {
    return vr("selectedModel") || "default";
  }

  async setModel(value) {
    await workspace.getConfiguration("claudeCode")
      .update("selectedModel", value, ConfigurationTarget.Global);
  }

  getThinkingLevel() {
    return this.context.globalState.get("thinkingLevel") || "default";
  }

  getInitialPermissionMode() {
    return vr("initialPermissionMode") || "default";
  }

  getAllowDangerouslySkipPermissions() {
    return vr("allowDangerouslySkipPermissions") || false;
  }

  getUseCtrlEnterToSend() {
    return vr("useCtrlEnterToSend") || false;
  }

  getHideOnboarding() {
    return vr("hideOnboarding") || false;
  }

  getPreferredLocation() {
    return vr("preferredLocation") === "sidebar" ? "sidebar" : "panel";
  }

  getSpinnerVerbsConfig() {
    return vr("spinnerVerbs");
  }
}

// Helper function
function vr(settingName) {
  return workspace.getConfiguration("claudeCode").get(settingName);
}
```

### 12.2 All Configuration Properties

| Setting Key | Type | Default | Description |
|---|---|---|---|
| `claudeCode.selectedModel` | string | `"default"` | AI model selection |
| `claudeCode.environmentVariables` | array | `[]` | Env vars for CLI |
| `claudeCode.useTerminal` | boolean | `false` | Terminal mode |
| `claudeCode.allowDangerouslySkipPermissions` | boolean | - | Bypass permissions |
| `claudeCode.claudeProcessWrapper` | string | - | Custom process wrapper |
| `claudeCode.respectGitIgnore` | boolean | `true` | Respect .gitignore |
| `claudeCode.initialPermissionMode` | enum | `"default"` | `default\|acceptEdits\|plan\|bypassPermissions` |
| `claudeCode.disableLoginPrompt` | boolean | `false` | Suppress auth prompts |
| `claudeCode.autosave` | boolean | `true` | Auto-save before read/write |
| `claudeCode.useCtrlEnterToSend` | boolean | `false` | Ctrl+Enter to send |
| `claudeCode.preferredLocation` | enum | `"panel"` | `sidebar\|panel` |
| `claudeCode.enableNewConversationShortcut` | boolean | `true` | Cmd+N shortcut |
| `claudeCode.hideOnboarding` | boolean | `false` | Hide onboarding |
| `claudeCode.usePythonEnvironment` | boolean | `true` | Auto-activate Python env |

### 12.3 Configuration Change Events

```javascript
// React to setting changes
workspace.onDidChangeConfiguration(event => {
  if (event.affectsConfiguration("claudeCode.respectGitIgnore")) {
    fileSearchCache.clear();
  }
  if (event.affectsConfiguration("claudeCode.hideOnboarding")) {
    this.pushStateUpdate();
  }
  if (event.affectsConfiguration("chat.fontSize")
      || event.affectsConfiguration("chat.fontFamily")
      || event.affectsConfiguration("chat.editor.fontFamily")) {
    // Rebuild webview HTML with new fonts, or send font_configuration_changed
  }
});
```

### 12.4 Environment Variable Construction

```javascript
// mb() function - builds env for CLI process
function buildEnvironment() {
  let env = {...process.env};

  // Add configured environment variables
  let envVars = vr("environmentVariables") || [];
  for (let {name, value} of envVars) {
    env[name] = value || "";
  }

  env.CLAUDE_CODE_ENTRYPOINT = "claude-vscode";
  return env;
}
```

### IntelliJ Adaptation Notes

- **Settings storage**: Use `PersistentStateComponent` or `PropertiesComponent`
- **Settings UI**: Generate from `@State` annotations or XML config
- **Change events**: Use `MessageBusConnection` with settings topic
- **Environment**: Build via `GeneralCommandLine.withEnvironment()`

---

## 13. MCP Server Integration

### 13.1 Extension MCP Server

The extension registers its own MCP server (`claude-vscode-extension`) that provides IDE tools:

```javascript
// Extension's built-in MCP server
function createExtensionMcpServer(context, output) {
  let config = createMcpConfig({
    name: "claude-vscode-extension",
    version: "2.1.29",
    tools: []
  });

  // Tools registered:
  // - getCurrentSelection, getLatestSelection
  // - getOpenEditors, getWorkspaceFolders
  // - getDiagnostics
  // - openFile, openDiff, closeAllDiffTabs
  // - checkDocumentDirty, saveDocument, close_tab
  // - executeCode (Jupyter)

  return {
    config: config,
    debuggerController: debuggerCtrl,
    jupyterController: jupyterCtrl
  };
}
```

### 13.2 MCP Server Lifecycle with CLI

```javascript
// MCP servers are passed to CLI at spawn time
let additionalMcpServers = this.getAdditionalMcpServers();
let mcpServers = {
  "claude-vscode": chromeMcpConfig,  // Chrome MCP if enabled
  ...additionalMcpServers
};

// After spawn, extension MCP server is registered:
let servers = {
  ...channel.mcpServers,
  "claude-vscode-extension": this.extensionMcpServer.config
};
await channel.query.setMcpServers(servers);
```

### 13.3 MCP Communication

```javascript
// The extension uses WebSocket for MCP communication
// Lock file stores connection info:
{
  pid: process.ppid,
  workspaceFolders: [...],
  ideName: "Visual Studio Code",
  transport: "ws",
  runningInWindows: false,
  authToken: "..."
}

// WebSocket MCP transport
class WebSocketTransport {
  send(message) {
    let json = JSON.stringify(message);
    this.ws.send(json);
  }
}
```

### 13.4 Chrome MCP Integration

```javascript
// Chrome browser integration via MCP
getChromeMcpServerConfig() {
  let {pathToClaudeCodeExecutable} = this.getClaudeBinary();

  if (pathToClaudeCodeExecutable.endsWith(".js")) {
    return {type: "stdio", command: "node", args: [path, "--claude-in-chrome-mcp"]};
  }
  return {type: "stdio", command: path, args: ["--claude-in-chrome-mcp"]};
}
```

### IntelliJ Adaptation Notes

- **Extension MCP server**: Register equivalent tools using IntelliJ APIs
- **Lock file**: Write to `~/.claude/ide/` with port and workspace info
- **WebSocket transport**: Use Ktor or Java WebSocket for MCP communication
- **Chrome MCP**: Same CLI flag, just different process spawning

---

## 14. All Discovered Message Types

### 14.1 Webview -> Extension (Request Types)

These are messages the webview sends to the extension host via `sendRequest()`:

| Message Type | Key Fields | Description |
|---|---|---|
| `init` | - | Initialize: get state, auth, config |
| `launch_claude` | channelId, cwd, resume, model, permissionMode, thinkingLevel | Start a Claude session |
| `io_message` | channelId, message, done | Forward user input to CLI |
| `interrupt_claude` | channelId | Stop current generation |
| `close_channel` | channelId | Close a session |
| `cancel_request` | targetRequestId | Cancel a pending request |
| `get_claude_state` | - | Get Claude config/state |
| `get_auth_status` | - | Check authentication status |
| `login` | method | Start login flow |
| `submit_oauth_code` | code | Submit OAuth authorization code |
| `get_current_selection` | - | Get editor selection |
| `get_terminal_contents` | terminalName | Read terminal text |
| `get_session_request` | sessionId | Get session details |
| `get_mcp_servers` | channelId | List MCP servers |
| `get_asset_uris` | - | Get icon/asset URIs |
| `list_sessions_request` | - | List saved sessions |
| `list_files_request` | - | List workspace files |
| `list_remote_sessions` | - | List remote/teleport sessions |
| `list_plugins` | includeAvailable | List installed/available plugins |
| `list_marketplaces` | - | List plugin marketplaces |
| `set_model` | model | Change model |
| `set_permission_mode` | permissionMode | Change permission mode |
| `set_thinking_level` | thinkingLevel | Change thinking level |
| `set_mcp_server_enabled` | serverName, enabled, channelId | Toggle MCP server |
| `set_plugin_enabled` | pluginId, enabled | Toggle plugin |
| `open_file` | filePath, location | Open file in editor |
| `open_diff` | originalFilePath, newFilePath, edits, supportMultiEdits | Show diff |
| `open_file_diffs` | fileDiffs | Show multi-file diffs |
| `open_content` | content, fileName, editable | Show read-only content |
| `open_url` | url | Open URL in browser |
| `open_config` | - | Open config settings |
| `open_config_file` | configType | Open specific config file |
| `open_help` | - | Open help/docs |
| `open_output_panel` | - | Show extension output |
| `open_terminal` | - | Open terminal |
| `open_claude_in_terminal` | - | Open Claude in terminal mode |
| `show_claude_terminal_setting` | - | Show terminal setting |
| `show_notification` | message, severity, buttons, onlyIfNotVisible | Show IDE notification |
| `rename_tab` | title, hasPendingPermissions | Update tab title/icon |
| `new_conversation_tab` | - | Open new conversation tab |
| `fork_conversation` | forkedFromSession, resumeSessionAt | Fork a conversation |
| `rewind_code` | userMessageId, channelId | Rewind file changes |
| `request_usage_update` | - | Request billing/usage info |
| `log_event` | event, properties | Log analytics event |
| `exec` | command, dryRun | Execute shell command |
| `dismiss_onboarding` | - | Dismiss onboarding checklist |
| `dismiss_terminal_banner` | - | Dismiss terminal banner |
| `dismiss_review_upsell_banner` | - | Dismiss review upsell |
| `install_plugin` | pluginId, scope | Install a plugin |
| `uninstall_plugin` | pluginId | Uninstall a plugin |
| `add_marketplace` | url | Add plugin marketplace |
| `remove_marketplace` | id | Remove plugin marketplace |
| `refresh_marketplace` | id | Refresh marketplace |
| `reconnect_mcp_server` | serverName, channelId | Reconnect MCP server |
| `ensure_chrome_mcp_enabled` | channelId | Enable Chrome MCP |
| `disable_chrome_mcp` | channelId | Disable Chrome MCP |
| `enable_jupyter_mcp` | channelId | Enable Jupyter MCP |
| `disable_jupyter_mcp` | channelId | Disable Jupyter MCP |
| `create_new_browser_tab` | - | Open browser tab (Chrome MCP) |
| `ask_debugger_help` | channelId | Get debugger help |
| `teleport_session` | sessionId | Teleport/transfer session |

### 14.2 Extension -> Webview (Push Messages)

These are unsolicited messages the extension pushes to the webview:

| Message Type | Key Fields | Description |
|---|---|---|
| `io_message` | channelId, message, done | CLI output forwarded |
| `close_channel` | channelId, error? | Channel terminated |
| `file_updated` | channelId, filePath, oldContent, newContent | File changed by CLI |
| `response` | requestId, response | Response to a request |
| `request` (update_state) | state, config | Full state update |
| `request` (insert_at_mention) | text | @-mention text to insert |
| `request` (selection_changed) | selection | Editor selection changed |
| `request` (visibility_changed) | visible | Panel visibility changed |
| `request` (font_configuration_changed) | fontConfig | Font settings changed |
| `request` (create_new_conversation) | - | Start new conversation |
| `request` (auth_url) | url, method | OAuth URL to display |
| `request` (usage_update) | utilization, error | Usage stats |
| `request` (proactive_suggestions_update) | suggestions | AI suggestions |
| `request` (open_plugins_dialog) | - | Show plugins UI |

### 14.3 CLI Process Messages (stdout, NDJSON)

| Message Type | Description |
|---|---|
| `user` | User message (echo) |
| `assistant` | Assistant response |
| `system` | System message |
| `result` | Final result |
| `error` | Error message |
| `tool_use` | Tool invocation |
| `tool_result` | Tool result |
| `progress` | Progress update |
| `control_response` | Response to control request |
| `auth_status` | Authentication status change |
| `keep_alive` | Keep-alive ping |

### 14.4 CLI Control Subtypes (stdin)

| Subtype | Description |
|---|---|
| `initialize` | Initialize session |
| `interrupt` | Interrupt generation |
| `set_model` | Change model |
| `set_max_thinking_tokens` | Change thinking tokens |
| `set_permission_mode` | Change permission mode |
| `mcp_message` | MCP protocol message |
| `mcp_reconnect` | Reconnect MCP server |
| `mcp_set_servers` | Update MCP servers |
| `mcp_toggle` | Toggle MCP server |
| `mcp_status` | MCP status query |
| `rewind_files` | Rewind file changes |

---

## 15. IntelliJ Adaptation Notes

### 15.1 Architecture Mapping

| VSCode Concept | IntelliJ Equivalent |
|---|---|
| `ExtensionContext` | `Project` + `PluginDisposable` |
| `WebviewPanel` | JCEF `JBCefBrowser` in `FileEditor` |
| `WebviewViewProvider` | `ToolWindowFactory` with JCEF |
| `postMessage` / `onDidReceiveMessage` | `JBCefJSQuery` callbacks |
| `StatusBarItem` | `StatusBarWidget` |
| `OutputChannel` | `ConsoleView` or Logger |
| `workspace.getConfiguration` | `PersistentStateComponent` |
| `commands.registerCommand` | `AnAction` registration |
| `workspace.onDidChange*` | `MessageBus` listeners |
| `TextDocumentContentProvider` | `VirtualFileSystem` |
| `FileSystemProvider` | `VirtualFileSystem` |
| `workspace.findFiles` | `FilenameIndex.getVirtualFilesByName` |
| `env.clipboard` | `CopyPasteManager` |
| `env.openExternal` | `BrowserUtil.browse()` |

### 15.2 Communication Bridge Design

The VSCode extension uses a simple pattern:
1. Extension wraps messages in `{type:"from-extension", message: payload}`
2. Webview reads messages via `window.addEventListener("message", ...)`
3. Webview sends messages via `api.postMessage(payload)` (unwrapped)

**For IntelliJ:**
1. Use `JBCefJSQuery` to create a Java->JS bridge
2. Inject a global `window.idebridge` object in the webview
3. JS calls `window.idebridge.postMessage(JSON.stringify(msg))`
4. Java calls `cefBrowser.executeJavaScript("window.dispatchEvent(new MessageEvent('message', {data: ${json}}))")`

### 15.3 Critical Path Items

1. **NDJSON process protocol**: Identical between VSCode and IntelliJ
2. **Webview HTML**: Same HTML/CSS/JS can be reused, only bridge JS changes
3. **Message types**: All 60+ message types must be handled
4. **Diff integration**: Most complex; IntelliJ has richer diff APIs
5. **MCP server**: WebSocket-based; standard Java WebSocket works
6. **Authentication**: Same OAuth flow, different UI for prompts

### 15.4 What Can Be Reused As-Is

- `webview/index.js` - The entire React app (with bridge adapter)
- `webview/index.css` - All styles (map VSCode CSS vars to IntelliJ theme vars)
- The NDJSON protocol to/from the CLI process
- The Agent SDK communication patterns
- MCP server tool definitions

### 15.5 What Must Be Reimplemented

- Extension host (`extension.js`) - Must be rewritten in Kotlin/Java
- Webview bridge (replace `acquireVsCodeApi()` with JCEF bridge)
- Diff viewer (use IntelliJ `DiffManager`)
- Status bar (use IntelliJ `StatusBarWidget`)
- Settings UI (use IntelliJ settings framework)
- File system providers (use IntelliJ `VirtualFileSystem`)
- Editor integration (use IntelliJ `Editor` and `FileEditorManager`)
- Terminal integration (use IntelliJ `Terminal` API)

### 15.6 Channel Architecture

The extension uses a **channel-based architecture** for managing multiple concurrent Claude sessions:

```
Webview <--messages--> Extension Host (ff class) <--channels--> CLI Processes

Each channel has:
- channelId: unique identifier
- query: Claude SDK query instance (with process)
- in: input stream (AsyncQueue)
- mcpServers: MCP server configuration
- chromeMcpState, debuggerMcpState, jupyterMcpState
```

**For IntelliJ**: Maintain the same channel abstraction. Each conversation tab gets its own channel with its own CLI process.

### 15.7 Init State Shape

The `init_response` contains the full state the webview needs:

```javascript
{
  type: "init_response",
  state: {
    defaultCwd: string,
    openNewInTab: boolean,
    showTerminalBanner: boolean,
    showReviewUpsellBanner: boolean,
    isOnboardingEnabled: boolean,
    isOnboardingDismissed: boolean,
    authStatus: {authMethod, email, subscriptionType},
    modelSetting: string,
    thinkingLevel: string,
    initialPermissionMode: string,
    allowDangerouslySkipPermissions: boolean,
    platform: string,
    speechToTextEnabled: boolean,
    marketplaceType: string,
    useCtrlEnterToSend: boolean,
    chromeMcpState: {status: string},
    browserIntegrationSupported: boolean,
    debuggerMcpState: {status: string},
    jupyterMcpState: {status: string},
    spinnerVerbsConfig: object
  }
}
```

### 15.8 Hooks System

The extension implements pre/post tool hooks:

```
PreToolUse hooks:
  - Edit/Write/Read -> saveFileIfNeeded (autosave)

PostToolUse hooks:
  - Edit/Write/MultiEdit -> findDiagnosticsProblems (IDE diagnostics feedback)
```

**For IntelliJ**: The diagnostics hook is especially valuable. Use IntelliJ's `InspectionManager` to provide code quality feedback after Claude edits files.

---

## Appendix A: Keybinding Summary

| Keybinding | Command | When |
|---|---|---|
| `Cmd+Escape` | Focus Claude input | Not in terminal mode, editor focused |
| `Cmd+Escape` | Blur Claude input | Not in terminal mode, editor not focused |
| `Cmd+Shift+Escape` | Open in new tab | Not in terminal mode |
| `Cmd+Escape` | Open terminal | Terminal mode |
| `Alt+K` | Insert @-mention | Editor text focused (webview mode) |
| `Cmd+Alt+K` | Insert @-mention | Editor text focused (terminal mode) |
| `Cmd+N` | New conversation | Claude panel focused |

## Appendix B: Activation Events

```json
"activationEvents": [
  "onStartupFinished",
  "onWebviewPanel:claudeVSCodePanel"
]
```

The extension activates after VS Code startup completes, or when its webview panel is restored.

## Appendix C: Context Keys

| Context Key | Description |
|---|---|
| `claude-vscode.viewingProposedDiff` | Diff editor is showing proposed changes |
| `claude-code.viewingProposedDiff` | Same (alternate prefix) |
| `claude-vscode.updateSupported` | Update command is available |
| `claude-vscode.sideBarActive` | Sidebar is active |
| `claude-code:doesNotSupportSecondarySidebar` | Secondary sidebar not available |

## Appendix D: CSS Variable Mapping (VSCode -> IntelliJ)

Key VSCode CSS variables used in the webview that need IntelliJ equivalents:

| VSCode Variable | Purpose | IntelliJ Mapping |
|---|---|---|
| `--vscode-button-background` | Primary button | `Button.startBackground` |
| `--vscode-button-foreground` | Button text | `Button.foreground` |
| `--vscode-editor-background` | Editor bg | `Editor.background` |
| `--vscode-editor-foreground` | Editor text | `Editor.foreground` |
| `--vscode-input-background` | Input field bg | `TextField.background` |
| `--vscode-input-foreground` | Input field text | `TextField.foreground` |
| `--vscode-badge-background` | Badge bg | `Counter.background` |
| `--vscode-descriptionForeground` | Secondary text | `Label.disabledForeground` |
| `--vscode-chat-font-family` | Chat font | IDE editor font |
| `--vscode-chat-font-size` | Chat size | IDE editor size |
| `--vscode-diffEditor-insertedLineBackground` | Diff added | DiffColors |
| `--vscode-diffEditor-removedLineBackground` | Diff removed | DiffColors |
