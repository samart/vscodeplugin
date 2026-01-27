# IntelliJ Plugin Feasibility Analysis

## Executive Summary

**Feasibility Rating: HIGH (85%)**

Creating an IntelliJ version of the Claude Code VSCode extension is highly feasible. The core architecture—launching a CLI binary and communicating via standard I/O while presenting a web-based UI—maps well to IntelliJ's plugin system. The main challenges are architectural differences in how the two IDEs handle webviews and UI integration, not fundamental blockers.

---

## 1. Architecture Comparison

### VSCode Plugin Architecture
```
┌─────────────────────────────────────────────────────┐
│ VSCode Extension (JavaScript/TypeScript)            │
├─────────────────────────────────────────────────────┤
│ extension.js       │ Main extension logic           │
│ webview/           │ React-based UI (index.js/css)  │
│ resources/         │ Icons, native binary           │
└─────────────────────────────────────────────────────┘
         │
         │ spawn() / child_process
         ▼
┌─────────────────────────────────────────────────────┐
│ Claude CLI Binary (native executable)               │
│ - Handles AI communication                          │
│ - File operations                                   │
│ - MCP protocol                                      │
└─────────────────────────────────────────────────────┘
```

### Proposed IntelliJ Architecture
```
┌─────────────────────────────────────────────────────┐
│ IntelliJ Plugin (Kotlin/Java)                       │
├─────────────────────────────────────────────────────┤
│ ClaudeToolWindow  │ JCEF-based webview panel        │
│ ClaudeService     │ Process management              │
│ ClaudeActions     │ IDE actions/commands            │
│ resources/        │ Icons, native binary, web UI    │
└─────────────────────────────────────────────────────┘
         │
         │ ProcessBuilder / Runtime.exec()
         ▼
┌─────────────────────────────────────────────────────┐
│ Claude CLI Binary (same native executable)          │
│ - Handles AI communication                          │
│ - File operations                                   │
│ - MCP protocol                                      │
└─────────────────────────────────────────────────────┘
```

---

## 2. Feature-by-Feature Mapping

| VSCode Feature | IntelliJ Equivalent | Complexity | Notes |
|---------------|---------------------|------------|-------|
| **Webview Panel** | JCEF (JBCefBrowser) | Medium | IntelliJ has excellent Chromium-based webview support |
| **Commands** | AnAction classes | Low | Direct mapping to IntelliJ actions |
| **Keybindings** | Keymap registration | Low | Standard plugin capability |
| **Settings/Config** | PersistentStateComponent | Low | Well-documented pattern |
| **Terminal Integration** | TerminalView API | Medium | Full terminal API available |
| **Editor Integration** | EditorFactory, FileEditorManager | Medium | Rich editor APIs |
| **Diff Viewer** | DiffManager, SimpleDiffRequest | Low | Built-in diff infrastructure |
| **Activity Bar Icon** | ToolWindow | Low | Standard UI component |
| **File/Workspace Access** | VirtualFileSystem, Project | Low | Comprehensive file APIs |
| **JSON Schema Validation** | JsonSchemaProviderFactory | Low | Built-in JSON support |
| **Process Spawning** | ProcessBuilder | Low | Native Java capability |
| **Message Passing** | JCEF JavaScript bridge | Medium | JBCefJSQuery for bidirectional comms |

---

## 3. Detailed Technical Analysis

### 3.1 Webview/UI (React Frontend)

**VSCode Approach:**
- Uses `vscode.Webview` API
- Loads React app from bundled HTML/JS/CSS
- Message passing via `postMessage()` / `onDidReceiveMessage`

**IntelliJ Approach:**
- Use **JCEF (Java Chromium Embedded Framework)**
- `JBCefBrowser` component for embedding web content
- Bidirectional communication via `JBCefJSQuery`

**Reuse Potential:** **HIGH**
- The entire `webview/` folder (index.js, index.css, fonts) can be reused as-is
- Only the message passing bridge needs adaptation
- React app remains unchanged

```kotlin
// Example IntelliJ JCEF integration
class ClaudeToolWindowFactory : ToolWindowFactory {
    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        val browser = JBCefBrowser()

        // Load the React app
        browser.loadHTML(loadResourceAsString("webview/index.html"))

        // Bridge for JS -> Kotlin communication
        val jsQuery = JBCefJSQuery.create(browser as JBCefBrowserBase)
        jsQuery.addHandler { message ->
            handleWebviewMessage(message)
            JBCefJSQuery.Response("ok")
        }

        // Inject bridge into page
        browser.jbCefClient.addLoadHandler(object : CefLoadHandler {
            override fun onLoadEnd(browser: CefBrowser, frame: CefFrame, httpStatusCode: Int) {
                browser.executeJavaScript(
                    "window.sendToPlugin = function(msg) { ${jsQuery.inject("msg")} }",
                    browser.url, 0
                )
            }
        }, browser.cefBrowser)

        toolWindow.component.add(browser.component)
    }
}
```

### 3.2 Process Management (Claude CLI)

**VSCode Approach:**
- `child_process.spawn()` to launch binary
- Environment variables passed at spawn time
- stdin/stdout for bidirectional communication

**IntelliJ Approach:**
- `ProcessBuilder` or `GeneralCommandLine` (IntelliJ utility)
- Same binary, same communication protocol
- `ProcessHandler` for managing process lifecycle

**Reuse Potential:** **VERY HIGH**
- The Claude CLI binary is platform-agnostic (same binary works)
- Communication protocol is identical
- Only the spawning code needs rewriting in Kotlin/Java

```kotlin
// Example process management
class ClaudeProcessManager(private val project: Project) {
    private var process: Process? = null

    fun startClaude(): Process {
        val binaryPath = getClaudeBinaryPath()
        val workingDir = project.basePath

        val commandLine = GeneralCommandLine(binaryPath)
            .withWorkDirectory(workingDir)
            .withEnvironment(getEnvironmentVariables())
            .withRedirectErrorStream(true)

        process = commandLine.createProcess()

        // Handle stdout/stderr
        ApplicationManager.getApplication().executeOnPooledThread {
            process?.inputStream?.bufferedReader()?.forEachLine { line ->
                handleClaudeOutput(line)
            }
        }

        return process!!
    }

    fun sendToProcess(message: String) {
        process?.outputStream?.write((message + "\n").toByteArray())
        process?.outputStream?.flush()
    }
}
```

### 3.3 Editor Integration

**VSCode Approach:**
- `vscode.window.activeTextEditor` for current file
- `vscode.TextEditor.selections` for selected text
- Diff viewer via custom webview

**IntelliJ Approach:**
- `FileEditorManager.getInstance(project).selectedTextEditor`
- `editor.selectionModel.selectedText`
- Built-in `DiffManager` for diff viewing

**Reuse Potential:** **MEDIUM**
- Concepts map directly but code must be rewritten
- IntelliJ has richer diff infrastructure

```kotlin
// Example editor integration
class ClaudeEditorService(private val project: Project) {
    fun getCurrentFileContext(): FileContext? {
        val editor = FileEditorManager.getInstance(project).selectedTextEditor ?: return null
        val virtualFile = FileDocumentManager.getInstance().getFile(editor.document) ?: return null

        return FileContext(
            path = virtualFile.path,
            content = editor.document.text,
            selection = editor.selectionModel.selectedText,
            selectionRange = editor.selectionModel.let {
                Range(it.selectionStart, it.selectionEnd)
            }
        )
    }

    fun showDiff(originalContent: String, proposedContent: String, filePath: String) {
        val request = SimpleDiffRequest(
            "Claude Proposed Changes: $filePath",
            DiffContentFactory.getInstance().create(originalContent),
            DiffContentFactory.getInstance().create(proposedContent),
            "Original",
            "Proposed"
        )
        DiffManager.getInstance().showDiff(project, request)
    }
}
```

### 3.4 Terminal Integration

**VSCode Approach:**
- `vscode.window.createTerminal()`
- Send commands via `terminal.sendText()`

**IntelliJ Approach:**
- `TerminalView` API
- `TerminalWidget` for terminal interaction

**Reuse Potential:** **MEDIUM**
- Feature parity exists but APIs differ significantly

```kotlin
// Example terminal integration
class ClaudeTerminalService(private val project: Project) {
    fun openClaudeInTerminal() {
        val terminalView = TerminalView.getInstance(project)
        val widget = terminalView.createLocalShellWidget(
            project.basePath,
            "Claude Code"
        )
        widget.executeCommand(getClaudeBinaryPath())
    }
}
```

### 3.5 Configuration/Settings

**VSCode Approach:**
- `contributes.configuration` in package.json
- `vscode.workspace.getConfiguration()`

**IntelliJ Approach:**
- `PersistentStateComponent` for state storage
- Settings UI via `Configurable` interface

**Reuse Potential:** **LOW** (code rewrite needed, but straightforward)

```kotlin
@State(
    name = "ClaudeCodeSettings",
    storages = [Storage("claudeCode.xml")]
)
class ClaudeSettings : PersistentStateComponent<ClaudeSettings.State> {
    data class State(
        var selectedModel: String = "default",
        var useTerminal: Boolean = false,
        var allowDangerouslySkipPermissions: Boolean = false,
        var claudeProcessWrapper: String? = null,
        var environmentVariables: MutableList<EnvVar> = mutableListOf()
    )

    private var state = State()

    override fun getState() = state
    override fun loadState(state: State) { this.state = state }

    companion object {
        fun getInstance(project: Project): ClaudeSettings =
            project.getService(ClaudeSettings::class.java)
    }
}
```

---

## 4. Implementation Effort Estimate

| Component | Effort | Lines of Code (Est.) | Dependencies |
|-----------|--------|---------------------|--------------|
| **Project Setup** | Low | ~200 | Gradle, IntelliJ SDK |
| **JCEF Webview Integration** | Medium | ~500 | JCEF library |
| **Process Management** | Low | ~300 | Java stdlib |
| **Editor Integration** | Medium | ~400 | IntelliJ Platform SDK |
| **Actions/Commands** | Low | ~300 | IntelliJ Platform SDK |
| **Settings/Configuration** | Low | ~250 | IntelliJ Platform SDK |
| **Terminal Integration** | Medium | ~200 | Terminal plugin API |
| **Diff Viewer Integration** | Low | ~150 | IntelliJ Platform SDK |
| **@-Mention Feature** | Medium | ~300 | Custom implementation |
| **Testing & Polish** | Medium | ~400 | JUnit, IntelliJ test framework |
| **Total** | | **~3,000** | |

**Estimated Development Time:** 3-5 weeks for a senior developer familiar with IntelliJ plugin development.

---

## 5. Key Challenges & Mitigations

### Challenge 1: JCEF Message Passing Differences
**Issue:** VSCode uses `postMessage` API; IntelliJ uses `JBCefJSQuery`

**Mitigation:** Create an adapter layer in the React app that abstracts the communication:
```javascript
// In webview, detect environment and use appropriate bridge
const sendMessage = (msg) => {
    if (window.acquireVsCodeApi) {
        // VSCode environment
        vscode.postMessage(msg);
    } else if (window.sendToPlugin) {
        // IntelliJ environment
        window.sendToPlugin(JSON.stringify(msg));
    }
};
```

### Challenge 2: Platform-Specific Binary Paths
**Issue:** Binary location differs between platforms and installation methods

**Mitigation:** Use IntelliJ's `PathManager` and standard installation locations:
```kotlin
fun getClaudeBinaryPath(): String {
    // Check settings override first
    settings.claudeProcessWrapper?.let { return it }

    // Platform-specific defaults
    return when {
        SystemInfo.isMac -> "/usr/local/bin/claude"
        SystemInfo.isLinux -> "/usr/bin/claude"
        SystemInfo.isWindows -> "C:\\Program Files\\Claude\\claude.exe"
        else -> "claude"
    }
}
```

### Challenge 3: Different Diff Viewer UX
**Issue:** VSCode uses custom webview diff; IntelliJ has native diff

**Mitigation:** Leverage IntelliJ's superior built-in diff infrastructure, which provides:
- Side-by-side comparison
- Unified diff view
- Accept/reject individual changes
- Three-way merge support

This is actually an **improvement** over VSCode.

### Challenge 4: Multi-IDE Family Support
**Issue:** IntelliJ plugin should work across IDEA, PyCharm, WebStorm, etc.

**Mitigation:** Use `IntelliJ Platform SDK` (not IDE-specific APIs) to ensure compatibility:
```xml
<!-- plugin.xml -->
<idea-plugin>
    <depends>com.intellij.modules.platform</depends>
    <!-- NOT com.intellij.modules.java -->
</idea-plugin>
```

---

## 6. What Can Be Directly Reused

| Asset | Reusability | Notes |
|-------|-------------|-------|
| `webview/index.js` | 95% | Add IntelliJ bridge adapter |
| `webview/index.css` | 100% | No changes needed |
| `webview/codicon-*.ttf` | 100% | No changes needed |
| `resources/claude-logo.*` | 100% | No changes needed |
| `claude-code-settings.schema.json` | 100% | JSON schema is universal |
| Claude CLI binary | 100% | Platform-agnostic |
| Communication protocol | 100% | Same stdin/stdout JSON |

---

## 7. What Must Be Rewritten

| Component | Reason |
|-----------|--------|
| Extension entry point | JavaScript → Kotlin/Java |
| Command/Action registration | VSCode API → IntelliJ Actions |
| Settings management | VSCode config → PersistentStateComponent |
| Webview host | VSCode Webview → JCEF |
| Terminal integration | VSCode Terminal → IntelliJ Terminal |
| Editor context retrieval | VSCode Editor API → IntelliJ Editor API |
| Diff presentation | VSCode custom → IntelliJ DiffManager |

---

## 8. Recommended Technology Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| **Language** | Kotlin | Modern, concise, full IntelliJ support |
| **Build System** | Gradle + IntelliJ Plugin | Standard plugin build toolchain |
| **UI Framework** | JCEF | Reuse React frontend |
| **Testing** | JUnit 5 + IntelliJ Test Framework | Standard testing approach |
| **CI/CD** | GitHub Actions | Automated builds and releases |

---

## 9. Plugin.xml Structure (Proposed)

```xml
<idea-plugin>
    <id>com.anthropic.claude-code</id>
    <name>Claude Code</name>
    <vendor email="support@anthropic.com" url="https://anthropic.com">Anthropic</vendor>

    <description><![CDATA[
        Claude Code for IntelliJ: Harness the power of Claude Code without leaving your IDE
    ]]></description>

    <depends>com.intellij.modules.platform</depends>
    <depends optional="true" config-file="terminal-support.xml">org.jetbrains.plugins.terminal</depends>

    <extensions defaultExtensionNs="com.intellij">
        <toolWindow id="Claude"
                    anchor="right"
                    factoryClass="com.anthropic.claude.ClaudeToolWindowFactory"
                    icon="/icons/claude-logo.svg"/>

        <projectService serviceImplementation="com.anthropic.claude.ClaudeService"/>
        <projectService serviceImplementation="com.anthropic.claude.ClaudeSettings"/>

        <projectConfigurable instance="com.anthropic.claude.settings.ClaudeConfigurable"
                            displayName="Claude Code"
                            id="claude.settings"/>

        <notificationGroup id="Claude Code" displayType="BALLOON"/>
    </extensions>

    <actions>
        <group id="Claude.MainMenu" text="Claude" popup="true">
            <add-to-group group-id="ToolsMenu" anchor="last"/>
            <action id="Claude.OpenPanel"
                    class="com.anthropic.claude.actions.OpenPanelAction"
                    text="Open Claude Panel"
                    icon="/icons/claude-logo.svg">
                <keyboard-shortcut keymap="$default" first-keystroke="ctrl ESCAPE"/>
                <keyboard-shortcut keymap="Mac OS X" first-keystroke="meta ESCAPE"/>
            </action>
            <action id="Claude.OpenInTerminal"
                    class="com.anthropic.claude.actions.OpenTerminalAction"
                    text="Open in Terminal"/>
            <action id="Claude.InsertAtMention"
                    class="com.anthropic.claude.actions.InsertAtMentionAction"
                    text="Insert @-Mention Reference">
                <keyboard-shortcut keymap="$default" first-keystroke="alt K"/>
            </action>
        </group>

        <action id="Claude.AcceptDiff"
                class="com.anthropic.claude.actions.AcceptDiffAction"
                text="Accept Proposed Changes"
                icon="AllIcons.Actions.Checked"/>
        <action id="Claude.RejectDiff"
                class="com.anthropic.claude.actions.RejectDiffAction"
                text="Reject Proposed Changes"
                icon="AllIcons.Actions.Cancel"/>
    </actions>
</idea-plugin>
```

---

## 10. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| JCEF compatibility issues | Low | Medium | Extensive testing across IDE versions |
| Binary path resolution failures | Medium | High | Robust fallback chain, user-configurable path |
| Performance issues with large codebases | Low | Medium | Async operations, proper threading |
| IDE version compatibility | Medium | Medium | Target LTS versions, use stable APIs |
| React webview CSP issues | Low | Low | Proper security headers configuration |

---

## 11. Conclusion & Recommendation

**Verdict: PROCEED WITH DEVELOPMENT**

The IntelliJ port is highly feasible with a clear path to implementation:

**Strengths:**
- Core architecture (CLI + webview) translates cleanly
- ~60% of assets (webview, icons, schema, binary) can be reused directly
- IntelliJ has mature APIs for all required features
- Built-in diff viewer is arguably better than VSCode's custom solution

**Weaknesses:**
- Requires rewriting ~3,000 lines of platform-specific code
- JCEF has a learning curve
- Multi-IDE testing adds complexity

**Recommended Approach:**
1. Start with a minimal viable plugin (webview + process spawning)
2. Iterate to add editor integration, terminal mode, and advanced features
3. Share the React webview codebase between VSCode and IntelliJ versions
4. Consider a unified build pipeline for both plugins

The investment is justified given the large IntelliJ user base (PyCharm, WebStorm, IDEA, etc.) and the ability to reuse the core Claude CLI and web UI components.
