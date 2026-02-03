# Master Implementation Plan: Claude Code IntelliJ Plugin

> **Document Version:** 1.0
> **Date:** February 2, 2026
> **Status:** Planning
> **Synthesized from:** Feasibility analysis + 5 research documents (01-05)

---

## Executive Summary

This document is the comprehensive implementation roadmap for porting the Claude Code VSCode extension to an IntelliJ Platform plugin. The plugin will support all JetBrains IDEs (IntelliJ IDEA, PyCharm, WebStorm, GoLand, PhpStorm, CLion, Rider, RubyMine, DataGrip) running version 2024.3 or later.

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Language | Kotlin (2.0.21) | Modern, concise, first-class IntelliJ support |
| Build system | Gradle + IntelliJ Platform Plugin 2.x | Current recommended toolchain |
| UI framework | JCEF (JBCefBrowser) | Reuse existing React webview from VSCode extension |
| Content loading | Custom CEF scheme handler (`claude://app/`) | Serves bundled assets naturally with caching and DevTools |
| Communication | Single JBCefJSQuery + JSON routing | Proven pattern used by GitHub Copilot and JetBrains AI |
| Process management | GeneralCommandLine + KillableProcessHandler | IntelliJ-native, supports SIGTERM/SIGKILL graceful shutdown |
| Async model | Kotlin coroutines with platform-injected CoroutineScope | Structured concurrency tied to project lifecycle |
| JSON parsing | kotlinx.serialization | Type-safe, Kotlin-native, no extra dependencies |
| Theme sync | CSS variables via LafManagerListener | Standard approach across all major JCEF plugins |
| Platform dependency | `com.intellij.modules.platform` only | Works in ALL JetBrains IDEs |

### Target Platform Matrix

| Parameter | Value |
|-----------|-------|
| Minimum IDE version | IntelliJ 2024.3 (build 243) |
| Maximum IDE version | IntelliJ 2025.2.* (build 252.*) |
| Java version | JDK 21 (JBR 21) |
| Kotlin version | 2.0.21 (K2 compiler) |
| Gradle version | 8.10+ |
| Gradle IntelliJ Plugin | org.jetbrains.intellij.platform 2.2.1+ |

### Estimated Scope

| Metric | Estimate |
|--------|----------|
| Total Kotlin source files | ~25-30 |
| Estimated lines of code | ~3,000-4,000 |
| Reusable assets from VSCode | ~60% (webview, icons, schema, CLI binary) |
| Development time | 4-6 weeks (senior developer) |
| Implementation phases | 8 |

---

## Architecture Overview

### High-Level Architecture

```
+-----------------------------------------------------------------------+
|                        JetBrains IDE (Host)                           |
|                                                                       |
|  +---------------------------+    +-------------------------------+   |
|  |   Plugin Host (Kotlin)    |    |     JCEF Webview (React)      |   |
|  |                           |    |                               |   |
|  |  ClaudeCodeService        |<-->|  Existing webview/index.js    |   |
|  |  ClaudeProcessManager     |    |  Existing webview/index.css   |   |
|  |  WebviewBridge            |    |  IntelliJ bridge adapter      |   |
|  |  ClaudeEditorService      |    |  Theme sync (CSS variables)   |   |
|  |  ClaudeSettings           |    |                               |   |
|  |  Actions + Keybindings    |    |  Loaded via claude://app/     |   |
|  +-------------+-------------+    +-------------------------------+   |
|                |                                                      |
|                | JBCefJSQuery (JS<->Kotlin)                           |
|                | executeJavaScript (Kotlin->JS)                       |
|                |                                                      |
+-----------------------------------------------------------------------+
                 |
                 | GeneralCommandLine + KillableProcessHandler
                 | stdin/stdout (line-delimited JSON)
                 |
+-----------------------------------------------------------------------+
|              Claude CLI Binary (native executable)                     |
|                                                                       |
|  - AI conversation management                                         |
|  - Tool use (file operations, shell commands, etc.)                   |
|  - MCP protocol support                                               |
|  - Streaming responses via JSON protocol                              |
+-----------------------------------------------------------------------+
```

### Three-Layer Design: VSCode to IntelliJ Mapping

| Layer | VSCode | IntelliJ |
|-------|--------|----------|
| **Plugin Host** | `extension.js` (JavaScript/Node.js) | Kotlin services, actions, tool window factory |
| **Webview** | VSCode Webview API + React app | JCEF JBCefBrowser + same React app |
| **CLI Process** | `child_process.spawn()` | `GeneralCommandLine` + `KillableProcessHandler` |

### Communication Flow

```
User types in webview input
        |
        v
[React webview] --JBCefJSQuery--> [WebviewBridge.kt]
                                        |
                                        v
                                   [ClaudeCodeService.kt]
                                        |
                                        | Channel<String> (outgoing)
                                        v
                                   [JsonProtocolHandler.kt]
                                        |
                                        | stdin (line-delimited JSON)
                                        v
                                   [Claude CLI Process]
                                        |
                                        | stdout (line-delimited JSON)
                                        v
                                   [JsonProtocolHandler.kt]
                                        |
                                        | SharedFlow<JsonObject> (incoming)
                                        v
                                   [ClaudeCodeService.kt]
                                        |
                                        | executeJavaScript()
                                        v
                                   [React webview updates]
```

---

## Component Mapping: VSCode to IntelliJ

| VSCode Concept | IntelliJ Equivalent | Key Classes |
|---------------|---------------------|-------------|
| `extension.js` entry point | Plugin services + `ProjectActivity` | `ClaudeCodeService`, `ClaudeStartupActivity` |
| `vscode.Webview` panel | JCEF Tool Window | `JBCefBrowser`, `ClaudeToolWindowFactory` |
| `postMessage()` / `onDidReceiveMessage` | `JBCefJSQuery` + `executeJavaScript()` | `WebviewBridge` |
| `vscode.workspace.getConfiguration()` | `PersistentStateComponent` / `@State` | `ClaudeCodeSettings` |
| `vscode.commands.registerCommand()` | `AnAction` classes + `plugin.xml` | `OpenPanelAction`, etc. |
| `contributes.keybindings` | `<keyboard-shortcut>` in `plugin.xml` | XML registration |
| `vscode.window.createTerminal()` | `TerminalView.createLocalShellWidget()` | `ClaudeTerminalService` |
| `child_process.spawn()` | `GeneralCommandLine` + `KillableProcessHandler` | `ClaudeProcessManager` |
| Custom diff webview | `DiffManager` + `SimpleDiffRequest` | `ClaudeDiffService` |
| `vscode.window.showInformationMessage()` | `NotificationGroupManager` | Notification group in `plugin.xml` |
| Activity bar icon | Tool window with sidebar icon | `<toolWindow>` extension point |
| Settings UI (contributes.configuration) | `Configurable` + Kotlin UI DSL | `ClaudeCodeConfigurable` |
| Status bar item | `StatusBarWidgetFactory` | `ClaudeStatusBarWidget` |
| `vscode.TextEditor` | `Editor` / `FileEditorManager` | `ClaudeEditorService` |
| File system access | `VirtualFileSystem` / `LocalFileSystem` | `VirtualFile`, `VfsUtil` |

### Settings Mapping (VSCode to IntelliJ)

| VSCode Setting | IntelliJ Setting | Type |
|---------------|------------------|------|
| `claudeCode.selectedModel` | `ClaudeCodeSettings.state.selectedModel` | String |
| `claudeCode.environmentVariables` | `ClaudeCodeSettings.state.environmentVariables` | List<EnvVar> |
| `claudeCode.useTerminal` | `ClaudeCodeSettings.state.useTerminal` | Boolean |
| `claudeCode.allowDangerouslySkipPermissions` | `ClaudeCodeSettings.state.allowDangerouslySkipPermissions` | Boolean |
| `claudeCode.claudeProcessWrapper` | `ClaudeCodeSettings.state.claudeBinaryPath` | String? |
| `claudeCode.respectGitIgnore` | `ClaudeCodeSettings.state.respectGitIgnore` | Boolean |
| `claudeCode.initialPermissionMode` | `ClaudeCodeSettings.state.initialPermissionMode` | String (enum) |
| `claudeCode.autosave` | `ClaudeCodeSettings.state.autosave` | Boolean |

---

## Implementation Phases

### Phase 1: Foundation (Project Scaffold + Build System)

**Goal:** Empty plugin that loads successfully in IntelliJ IDEA.

**Reference:** [03-gradle-project-setup.md](./03-gradle-project-setup.md)

#### Key Files to Create

```
claude-code-intellij/
  settings.gradle.kts
  build.gradle.kts
  gradle.properties
  gradle/libs.versions.toml
  gradle/wrapper/gradle-wrapper.properties
  src/main/resources/META-INF/plugin.xml
  src/main/resources/META-INF/pluginIcon.svg
  src/main/resources/META-INF/pluginIcon_dark.svg
  src/main/resources/META-INF/terminal-support.xml
  src/main/kotlin/com/anthropic/claudecode/ClaudeCodePlugin.kt
  .github/workflows/build.yml
  .run/Run IDE with Plugin.run.xml
```

#### `settings.gradle.kts`

```kotlin
rootProject.name = "claude-code-intellij"

plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "0.9.0"
}
```

#### `gradle/libs.versions.toml` (Key Entries)

```toml
[versions]
intellijPlatformPlugin = "2.2.1"
kotlin = "2.0.21"
intellijPlatformVersion = "2024.3.1"
pluginSinceBuild = "243"
pluginUntilBuild = "252.*"
javaVersion = "21"
kotlinxCoroutines = "1.10.1"
kotlinxSerialization = "1.7.3"

[plugins]
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
intellij-platform = { id = "org.jetbrains.intellij.platform", version.ref = "intellijPlatformPlugin" }
```

#### `build.gradle.kts` (Core Configuration)

```kotlin
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.intellij.platform)
}

dependencies {
    intellijPlatform {
        intellijIdeaCommunity(libs.versions.intellijPlatformVersion.get())
        bundledPlugins("org.jetbrains.plugins.terminal")
        pluginVerifier()
        zipSigner()
        testFramework(TestFrameworkType.Platform)
        instrumentationTools()
    }
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
}

intellijPlatform {
    pluginConfiguration {
        id = "com.anthropic.claudecode"
        name = "Claude Code"
        ideaVersion {
            sinceBuild = libs.versions.pluginSinceBuild
            untilBuild = libs.versions.pluginUntilBuild
        }
        vendor {
            name = "Anthropic"
            email = "support@anthropic.com"
            url = "https://anthropic.com"
        }
    }
}

kotlin { jvmToolchain(21) }
```

#### `plugin.xml` (Minimal)

```xml
<idea-plugin>
    <id>com.anthropic.claudecode</id>
    <name>Claude Code</name>
    <vendor email="support@anthropic.com" url="https://anthropic.com">Anthropic</vendor>
    <depends>com.intellij.modules.platform</depends>
    <depends optional="true" config-file="terminal-support.xml">
        org.jetbrains.plugins.terminal
    </depends>
</idea-plugin>
```

#### CI/CD Pipeline (GitHub Actions)

The workflow runs `buildPlugin`, `test`, `verifyPluginConfiguration`, and `verifyPlugin` on every push. Publishes to Marketplace on version tags.

#### Acceptance Criteria

- [ ] `./gradlew buildPlugin` produces a valid .zip
- [ ] `./gradlew runIde` launches a sandbox IDE without errors
- [ ] `./gradlew verifyPluginConfiguration` passes
- [ ] Plugin appears in the sandbox IDE's plugin list
- [ ] GitHub Actions build passes

---

### Phase 2: Process Management + JSON Protocol

**Goal:** Spawn the Claude CLI binary, exchange JSON messages via stdin/stdout, and manage the process lifecycle with restart logic.

**Reference:** [04-process-management-research.md](./04-process-management-research.md)

#### Key Files to Create

```
src/main/kotlin/com/anthropic/claudecode/
  services/ClaudeCodeService.kt          # Main service: state, connect, disconnect
  process/ClaudeProcessManager.kt        # GeneralCommandLine + KillableProcessHandler
  process/ClaudeBinaryResolver.kt        # Settings -> Bundled -> PATH resolution
  process/JsonProtocolHandler.kt         # Stdin/stdout JSON communication
  process/StderrCollector.kt             # Stderr capture for diagnostics
  process/ClaudeErrorHandler.kt          # Exit code analysis + restart logic
  protocol/Messages.kt                   # @Serializable message types
  listeners/ClaudeStartupActivity.kt     # ProjectActivity for auto-start
  listeners/ProjectCloseListener.kt      # Stop process on project close
```

#### Binary Resolution Strategy

Resolution order:
1. **User-configured path** from settings (`ClaudeCodeSettings.state.claudeBinaryPath`)
2. **Bundled binary** inside the plugin directory (`pluginPath/bin/{platform}/claude`)
3. **System PATH** via `which`/`where` and common installation locations

```kotlin
object ClaudeBinaryResolver {
    fun resolve(settings: ClaudeCodeSettings): String {
        // 1. User override
        settings.state.claudeBinaryPath?.let { path ->
            if (File(path).canExecute()) return path
        }
        // 2. Bundled binary (PluginManagerCore.getPlugin -> pluginPath/bin/{platform})
        getBundledBinaryPath()?.let { return it }
        // 3. System PATH
        getSystemBinaryPath()?.let { return it }
        throw ClaudeBinaryNotFoundException(...)
    }
}
```

Platform directory naming: `darwin-aarch64`, `darwin-x86_64`, `linux-aarch64`, `linux-x86_64`, `windows-x86_64`.

#### Process Lifecycle State Machine

```
    +----> STOPPED ----+
    |         |        |
    |    start()       |
    |         v        |
    |     STARTING     |
    |         |        |
    |    success       |
    |         v        |
    +---- RUNNING      |
    |         |        |
    |  crash / exit    |
    |         v        |
    +---- CRASHED      |
    |         |        |
    |  restart (< max) |
    |         v        |
    +-- RESTARTING     |
              |
         stop()
              v
           STOPPING ----> STOPPED
```

State is exposed as `StateFlow<ProcessState>` for reactive UI updates.

#### JSON Protocol Handler (Core Pattern)

```kotlin
class JsonProtocolHandler(private val process: Process, private val cs: CoroutineScope) {
    private val outgoing = Channel<String>(Channel.BUFFERED)
    private val _messages = MutableSharedFlow<JsonObject>(extraBufferCapacity = 128)
    val messages: SharedFlow<JsonObject> = _messages.asSharedFlow()
    private val pendingRequests = ConcurrentHashMap<String, CompletableDeferred<JsonObject>>()

    fun start() {
        cs.launch(Dispatchers.IO) { readLoop() }   // stdout reader
        cs.launch(Dispatchers.IO) { writeLoop() }   // stdin writer
    }

    suspend fun send(message: JsonObject) { ... }
    suspend fun sendAndReceive(message: JsonObject, requestId: String, timeout: Long = 30_000): JsonObject { ... }
    fun messagesOfType(type: String): Flow<JsonObject> { ... }
    fun streamDeltas(): Flow<String> { ... }
}
```

- **Stdout reading:** `BufferedReader.readLine()` on `Dispatchers.IO`, parse each line as JSON, emit to `SharedFlow`
- **Stdin writing:** Consume `Channel<String>`, write line-delimited JSON, flush
- **Request-response correlation:** `CompletableDeferred` keyed by `requestId`
- **Error handling:** Exponential backoff restart (1s, 2s, 4s, 8s, 16s cap), max 5 restarts

#### Environment Variables

```kotlin
fun buildEnvironment(settings: ClaudeCodeSettings): Map<String, String> {
    val env = mutableMapOf<String, String>()
    env["CLAUDE_CODE_IDE"] = "intellij"
    env["CLAUDE_CODE_IDE_VERSION"] = ApplicationInfo.getInstance().fullVersion
    env["TERM"] = "dumb"
    env["NO_COLOR"] = "1"
    // User-configured env vars from settings
    for (envVar in settings.state.environmentVariables) {
        env[envVar.name] = envVar.value
    }
    return env
}
```

Use `ParentEnvironmentType.CONSOLE` to inherit the user's shell environment as the base.

#### Acceptance Criteria

- [ ] Claude CLI binary is found via the resolution chain
- [ ] Process starts with correct environment variables and working directory
- [ ] JSON messages can be sent to stdin and received from stdout
- [ ] Process crash triggers automatic restart with backoff
- [ ] Process terminates cleanly when project closes
- [ ] State changes are observable via `StateFlow`
- [ ] Exit code analysis produces actionable error messages

---

### Phase 3: JCEF Webview Integration

**Goal:** Display the Claude Code React UI in a JCEF tool window with bidirectional communication between the webview and the Kotlin plugin host.

**Reference:** [02-jcef-webview-research.md](./02-jcef-webview-research.md)

#### Key Files to Create

```
src/main/kotlin/com/anthropic/claudecode/
  toolwindow/ClaudeCodeToolWindowFactory.kt  # ToolWindowFactory + DumbAware
  webview/WebviewBridge.kt                    # JBCefJSQuery bidirectional bridge
  webview/LocalResourceSchemeHandler.kt       # Custom claude://app/ scheme handler
  webview/JcefSchemeRegistrar.kt              # Register scheme at app startup
  webview/ThemeSynchronizer.kt                # IDE theme -> CSS variables
  webview/BatchedWebviewUpdater.kt            # Debounced JS execution for streaming

src/main/resources/
  webview/index.html                          # HTML wrapper for React app
  webview/index.js                            # Existing React bundle (from VSCode)
  webview/index.css                           # Existing styles (from VSCode)
  webview/codicon.ttf                         # Codicon font (from VSCode)
  icons/claude-toolwindow.svg                 # 13x13 SVG tool window icon
```

#### Custom Scheme Handler (claude://app/)

The React app is served via a custom CEF scheme, allowing natural relative paths for scripts, styles, and fonts:

```kotlin
class LocalResourceSchemeHandlerFactory : CefSchemeHandlerFactory {
    override fun create(browser: CefBrowser?, frame: CefFrame?,
                        schemeName: String?, request: CefRequest?): CefResourceHandler {
        return LocalResourceHandler()
    }
}

class LocalResourceHandler : CefResourceHandler {
    override fun processRequest(request: CefRequest, callback: CefCallback): Boolean {
        val path = request.url.removePrefix("claude://app/")
        val resourcePath = "/webview/$path"
        val bytes = javaClass.getResourceAsStream(resourcePath)?.readAllBytes() ?: return false
        // Set inputStream, responseLength, mimeType, call callback.Continue()
        return true
    }
    // ... getResponseHeaders(), readResponse(), cancel()
}
```

Register at app startup via `AppLifecycleListener`:

```kotlin
class JcefSchemeRegistrar : AppLifecycleListener {
    override fun appStarted() {
        if (JBCefApp.isSupported()) {
            JBCefApp.getInstance().cefApp.registerSchemeHandlerFactory(
                "claude", "app", LocalResourceSchemeHandlerFactory()
            )
        }
    }
}
```

Then load: `browser.loadURL("claude://app/index.html")`

#### Bidirectional Communication Bridge

**JS to Kotlin** (via JBCefJSQuery):
```kotlin
val jsQuery = JBCefJSQuery.create(browser as JBCefBrowserBase)
jsQuery.addHandler { rawMessage ->
    val message = Json.parseToJsonElement(rawMessage).jsonObject
    val type = message["type"]?.jsonPrimitive?.content
    val response = handleMessage(type, message)
    JBCefJSQuery.Response(Json.encodeToString(response))
}
```

**Kotlin to JS** (via executeJavaScript):
```kotlin
fun postMessage(type: String, payload: Any?) {
    val json = Json.encodeToString(mapOf("type" to type, "payload" to payload))
    browser.cefBrowser.executeJavaScript(
        "window.dispatchEvent(new CustomEvent('hostMessage', { detail: JSON.parse('$escaped') }));",
        browser.cefBrowser.url, 0
    )
}
```

**Bridge injection** on page load:
```javascript
window.__sendToHost = function(type, payload) {
    return new Promise(function(resolve, reject) {
        var message = JSON.stringify({ type: type, payload: payload });
        ${jsQuery.inject("message",
            "function(response) { resolve(JSON.parse(response)); }",
            "function(code, msg) { reject(new Error(msg)); }"
        )}
    });
};
window.dispatchEvent(new CustomEvent('hostBridgeReady'));
```

#### Theme Synchronization

Read IDE theme colors via `UIManager` and inject as CSS variables:

```kotlin
fun syncThemeToWebview(browser: CefBrowser) {
    val isDark = UIUtil.isUnderDarcula()
    val theme = mapOf(
        "isDark" to isDark.toString(),
        "background" to colorToHex(UIManager.getColor("Panel.background")),
        "foreground" to colorToHex(UIManager.getColor("Panel.foreground")),
        "editorBackground" to colorToHex(UIManager.getColor("Editor.background")),
        "inputBackground" to colorToHex(UIManager.getColor("TextField.background")),
        // ... more color keys
    )
    browser.executeJavaScript("window.__applyIdeTheme && window.__applyIdeTheme($json);", ...)
}
```

Listen for theme changes via `LafManagerListener.TOPIC` on the project message bus.

#### Webview Adapter Layer

The React webview needs a thin adapter to detect the IntelliJ environment:

```javascript
// Detect environment and use appropriate bridge
const sendMessage = (msg) => {
    if (window.acquireVsCodeApi) {
        vscode.postMessage(msg);           // VSCode environment
    } else if (window.__sendToHost) {
        window.__sendToHost(msg.type, msg.payload);  // IntelliJ environment
    }
};
```

#### Performance: Batched Updates for Streaming

When streaming CLI output, batch `executeJavaScript` calls at ~60fps using `SingleAlarm`:

```kotlin
class BatchedWebviewUpdater(private val browser: JBCefBrowser) {
    private val buffer = StringBuilder()
    private val alarm = SingleAlarm(::flush, 16, disposable) // ~60fps

    fun appendOutput(text: String) {
        synchronized(buffer) { buffer.append(text) }
        alarm.request()
    }
}
```

#### JCEF Fallback

If `JBCefApp.isSupported()` returns false (headless, remote dev, etc.), show a Swing panel with a message directing the user to enable JCEF or use the terminal mode instead.

#### Acceptance Criteria

- [ ] Tool window appears in IDE sidebar with Claude icon
- [ ] React app loads and renders correctly in the JCEF browser
- [ ] Webview adapts to IDE dark/light theme
- [ ] Messages flow bidirectionally between webview and Kotlin host
- [ ] Streaming CLI output renders in webview without freezing
- [ ] Browser resources are properly disposed on tool window close
- [ ] DevTools are accessible in development builds (right-click menu)

---

### Phase 4: Editor Integration

**Goal:** Claude can read editor context (file, selection, caret) and apply changes via diffs with accept/reject workflow.

**Reference:** [05-editor-diff-terminal-research.md](./05-editor-diff-terminal-research.md)

#### Key Files to Create

```
src/main/kotlin/com/anthropic/claudecode/
  editor/ClaudeEditorService.kt           # Context gathering, document modification
  editor/ClaudeDiffService.kt             # Diff view creation and management
  editor/EditorContext.kt                 # Data classes for editor state
  editor/ClaudeEditorListener.kt          # Listen for editor open/close/change
  actions/SendSelectionAction.kt          # Send selected text to Claude
  actions/AcceptDiffAction.kt             # Accept proposed changes
  actions/RejectDiffAction.kt             # Reject proposed changes
```

#### Editor Context Extraction

```kotlin
data class EditorContext(
    val filePath: String,
    val fileName: String,
    val fileExtension: String?,
    val language: String?,
    val content: String,
    val cursorLine: Int,         // 0-based
    val cursorColumn: Int,       // 0-based
    val selection: SelectionInfo?,
    val visibleStartLine: Int,
    val visibleEndLine: Int,
    val lineCount: Int,
    val isModified: Boolean
)

fun gatherFullContext(project: Project): EditorContext? {
    val editor = FileEditorManager.getInstance(project).selectedTextEditor ?: return null
    val document = editor.document
    val virtualFile = FileDocumentManager.getInstance().getFile(document) ?: return null
    val psiFile = PsiDocumentManager.getInstance(project).getPsiFile(document)
    // ... extract all fields
}
```

**Important:** Context gathering requires `ReadAction`. Use `readAction {}` (suspending) from coroutines or `ReadAction.nonBlocking()` from callbacks.

#### Document Modification

All modifications MUST use `WriteCommandAction` on EDT for undo/redo support:

```kotlin
fun applyChanges(project: Project, document: Document, newContent: String) {
    WriteCommandAction.writeCommandAction(project)
        .withName("Claude: Apply Changes")
        .withGroupId("claude.applyChanges")
        .run<RuntimeException> {
            document.setText(newContent)
        }
}
```

For targeted line edits, apply in reverse offset order to preserve validity.

#### Diff View (Accept/Reject Workflow)

```kotlin
fun showDiff(project: Project, originalContent: String,
             proposedContent: String, filePath: String) {
    val contentFactory = DiffContentFactory.getInstance()
    val request = SimpleDiffRequest(
        "Claude: Proposed Changes to ${filePath.substringAfterLast('/')}",
        contentFactory.create(project, originalContent),
        contentFactory.create(project, proposedContent),
        "Current", "Proposed by Claude"
    )
    DiffManager.getInstance().showDiff(project, request)
}
```

For file-type-aware syntax highlighting in diff:

```kotlin
val fileType = FileTypeManager.getInstance().getFileTypeByFileName(filePath)
val originalDiffContent = contentFactory.create(project, originalContent, fileType)
```

#### File Creation

```kotlin
fun createFile(project: Project, relativePath: String, content: String) {
    WriteCommandAction.runWriteCommandAction(project) {
        val baseDir = project.guessProjectDir() ?: return@runWriteCommandAction
        val directory = VfsUtil.createDirectoryIfMissing(baseDir, relativePath.substringBeforeLast('/'))
        directory?.createChildData(this, relativePath.substringAfterLast('/'))?.let { file ->
            VfsUtil.saveText(file, content)
        }
    }
}
```

#### Acceptance Criteria

- [ ] Claude receives accurate file path, content, selection, and cursor position
- [ ] Claude can replace file content with proper undo support
- [ ] Diff view shows proposed changes with syntax highlighting
- [ ] Accept action applies changes; Reject action discards them
- [ ] File creation works for new files
- [ ] Undo (Ctrl+Z / Cmd+Z) reverses Claude's changes in a single step
- [ ] Bulk document changes are performant (using `DocumentUtil.executeInBulk`)

---

### Phase 5: Settings + Configuration

**Goal:** All VSCode settings have IntelliJ equivalents with a proper settings UI.

**Reference:** [03-gradle-project-setup.md](./03-gradle-project-setup.md), [01-platform-research.md](./01-platform-research.md)

#### Key Files to Create

```
src/main/kotlin/com/anthropic/claudecode/
  services/ClaudeCodeSettings.kt          # PersistentStateComponent
  settings/ClaudeCodeConfigurable.kt      # Settings UI (Kotlin UI DSL)
```

#### Persistent State

```kotlin
@State(
    name = "ClaudeCodeSettings",
    storages = [Storage("claudeCode.xml")]
)
class ClaudeCodeSettings : PersistentStateComponent<ClaudeCodeSettings.State> {

    data class State(
        var selectedModel: String = "default",
        var useTerminal: Boolean = false,
        var allowDangerouslySkipPermissions: Boolean = false,
        var claudeBinaryPath: String? = null,
        var respectGitIgnore: Boolean = true,
        var initialPermissionMode: String = "default",
        var autosave: Boolean = true,
        var disableLoginPrompt: Boolean = false,
        var environmentVariables: MutableList<EnvVar> = mutableListOf()
    )

    @Serializable
    data class EnvVar(var name: String = "", var value: String = "")

    private var state = State()
    override fun getState() = state
    override fun loadState(state: State) { this.state = state }
}
```

#### Settings UI

Register as `projectConfigurable` under `parentId="tools"`:

```kotlin
class ClaudeCodeConfigurable(private val project: Project) : BoundConfigurable("Claude Code") {
    override fun createPanel(): DialogPanel = panel {
        group("General") {
            row("Model:") {
                comboBox(listOf("default", "claude-sonnet-4-20250514", "claude-opus-4-20250514"))
                    .bindItem(settings::selectedModel.toNullableProperty())
            }
            row("Binary path:") {
                textFieldWithBrowseButton("Select Claude Binary")
                    .bindText(settings::claudeBinaryPath)
            }
            row { checkBox("Use terminal mode").bindSelected(settings::useTerminal) }
            row { checkBox("Auto-save files").bindSelected(settings::autosave) }
            row { checkBox("Respect .gitignore").bindSelected(settings::respectGitIgnore) }
        }
        group("Permission Mode") {
            row("Initial mode:") {
                comboBox(listOf("default", "acceptEdits", "plan", "bypassPermissions"))
                    .bindItem(settings::initialPermissionMode.toNullableProperty())
            }
        }
        group("Environment Variables") {
            // Editable table for key-value pairs
        }
    }
}
```

#### Acceptance Criteria

- [ ] Settings appear under Settings > Tools > Claude Code
- [ ] All VSCode settings have IntelliJ equivalents
- [ ] Settings persist across IDE restarts (stored in `claudeCode.xml`)
- [ ] Changing settings takes effect without restart
- [ ] Binary path has a file browser button
- [ ] Environment variables are editable as a key-value table

---

### Phase 6: Commands, Keybindings, and UX Polish

**Goal:** Full action registration, keyboard shortcuts, status bar widget, notifications, and welcome experience.

**Reference:** [05-editor-diff-terminal-research.md](./05-editor-diff-terminal-research.md)

#### Key Files to Create

```
src/main/kotlin/com/anthropic/claudecode/
  actions/OpenPanelAction.kt              # Open the Claude tool window
  actions/NewConversationAction.kt        # Start new conversation
  actions/OpenTerminalAction.kt           # Open Claude in terminal
  actions/SendSelectionAction.kt          # Send selection to Claude
  ui/ClaudeStatusBarWidgetFactory.kt      # Connection status widget
  ui/ClaudeStatusBarWidget.kt             # Widget implementation
```

#### Action Registration (plugin.xml)

```xml
<actions>
    <group id="ClaudeCode.ToolsMenu" text="Claude Code" popup="true">
        <add-to-group group-id="ToolsMenu" anchor="last"/>

        <action id="ClaudeCode.OpenPanel"
                class="com.anthropic.claudecode.actions.OpenPanelAction"
                text="Open Claude Code"
                icon="/icons/claude-action.svg">
            <keyboard-shortcut keymap="$default" first-keystroke="ctrl shift PERIOD"/>
            <keyboard-shortcut keymap="Mac OS X" first-keystroke="meta shift PERIOD"/>
            <keyboard-shortcut keymap="Mac OS X 10.5+" first-keystroke="meta shift PERIOD"/>
        </action>

        <action id="ClaudeCode.NewConversation"
                class="com.anthropic.claudecode.actions.NewConversationAction"
                text="New Conversation">
            <keyboard-shortcut keymap="$default" first-keystroke="ctrl shift COMMA"/>
            <keyboard-shortcut keymap="Mac OS X" first-keystroke="meta shift COMMA"/>
        </action>

        <action id="ClaudeCode.SendSelection"
                class="com.anthropic.claudecode.actions.SendSelectionAction"
                text="Send Selection to Claude"/>
    </group>

    <!-- Editor context menu -->
    <group id="ClaudeCode.EditorPopupMenu">
        <add-to-group group-id="EditorPopupMenu" anchor="last"/>
        <reference ref="ClaudeCode.SendSelection"/>
    </group>
</actions>
```

All actions should implement `DumbAware` to remain functional during indexing.

#### Status Bar Widget

```xml
<extensions defaultExtensionNs="com.intellij">
    <statusBarWidgetFactory id="ClaudeStatusWidget"
        implementation="com.anthropic.claudecode.ui.ClaudeStatusBarWidgetFactory"/>
</extensions>
```

The widget observes `ClaudeCodeService.state` (StateFlow) and shows:
- Disconnected (gray icon)
- Connecting (spinning icon)
- Connected (green icon)
- Error (red icon with tooltip)

Click opens the tool window; right-click shows Restart/Stop actions.

#### Notifications

```xml
<notificationGroup id="Claude Code Notifications" displayType="BALLOON" isLogByDefault="true"/>
```

Used for: process start/stop, errors, crash recovery, binary not found.

#### Acceptance Criteria

- [ ] All actions appear in Tools > Claude Code menu
- [ ] Keyboard shortcuts work on Windows, macOS, and Linux
- [ ] "Send Selection to Claude" appears in editor right-click menu
- [ ] Status bar widget shows current connection state
- [ ] Notifications appear for important events (start, crash, error)
- [ ] Actions are grayed out appropriately (e.g., Send Selection when nothing selected)

---

### Phase 7: Terminal Integration

**Goal:** Support launching Claude CLI directly in an IDE terminal tab as an alternative to the JCEF webview.

**Reference:** [05-editor-diff-terminal-research.md](./05-editor-diff-terminal-research.md)

#### Key Files to Create

```
src/main/kotlin/com/anthropic/claudecode/
  terminal/ClaudeTerminalService.kt       # Terminal tab creation
  actions/OpenTerminalAction.kt           # Already listed in Phase 6
src/main/resources/META-INF/
  terminal-support.xml                    # Optional dependency extensions
```

#### Terminal Tab Creation

```kotlin
class ClaudeTerminalService(private val project: Project) {
    fun openClaudeInTerminal() {
        val terminalView = TerminalView.getInstance(project)
        val binaryPath = ClaudeBinaryResolver.resolve(ClaudeCodeSettings.getInstance(project))
        val widget = terminalView.createLocalShellWidget(
            project.basePath,
            "Claude Code",
            true  // activate
        )
        widget.executeCommand(binaryPath)
    }
}
```

Terminal integration is an **optional dependency** (`org.jetbrains.plugins.terminal`). When the terminal plugin is not available, the "Open in Terminal" action is hidden.

#### `useTerminal` Setting

When `ClaudeCodeSettings.state.useTerminal` is `true`, clicking the tool window icon opens a terminal tab instead of the JCEF webview. This mirrors the VSCode `claudeCode.useTerminal` behavior.

#### Acceptance Criteria

- [ ] "Open Claude in Terminal" creates a new terminal tab running Claude CLI
- [ ] Terminal tab has the title "Claude Code"
- [ ] Setting `useTerminal=true` changes default behavior to terminal mode
- [ ] Plugin works when terminal plugin is not installed (graceful degradation)

---

### Phase 8: Testing, Packaging, and Distribution

**Goal:** Comprehensive test suite, plugin verification, and distribution setup.

**Reference:** [03-gradle-project-setup.md](./03-gradle-project-setup.md)

#### Key Files to Create

```
src/test/kotlin/com/anthropic/claudecode/
  services/ClaudeCodeServiceTest.kt       # Service lifecycle tests
  process/ClaudeBinaryResolverTest.kt     # Binary resolution tests
  process/JsonProtocolHandlerTest.kt      # JSON protocol tests
  webview/WebviewBridgeTest.kt            # Message routing tests
  editor/ClaudeEditorServiceTest.kt       # Editor context tests
  settings/ClaudeCodeSettingsTest.kt      # Settings persistence tests
```

#### Unit Testing Pattern

Use `LightPlatformTestCase` for tests that need an IntelliJ project context:

```kotlin
class ClaudeBinaryResolverTest : LightPlatformTestCase() {
    fun testResolvesFromSettings() {
        val settings = ClaudeCodeSettings()
        settings.loadState(ClaudeCodeSettings.State(claudeBinaryPath = "/usr/local/bin/claude"))
        val path = ClaudeBinaryResolver.resolve(settings)
        assertEquals("/usr/local/bin/claude", path)
    }

    fun testThrowsWhenNotFound() {
        val settings = ClaudeCodeSettings()
        assertThrows(ClaudeBinaryNotFoundException::class.java) {
            ClaudeBinaryResolver.resolve(settings)
        }
    }
}
```

For services with `CoroutineScope`, use `runBlocking` with a test scope.

#### Plugin Verification

```bash
./gradlew verifyPlugin
```

This checks binary compatibility against all IDE versions in the `recommended()` set. Catches:
- Usage of removed APIs
- Incorrect plugin descriptor
- Missing dependencies
- Incompatible bytecode

#### Packaging

```bash
./gradlew buildPlugin
# Output: build/distributions/claude-code-intellij-0.1.0.zip
```

The ZIP can be installed via Settings > Plugins > Install from Disk.

#### JetBrains Marketplace Submission

1. Generate signing certificate and private key
2. Set environment variables: `CERTIFICATE_CHAIN`, `PRIVATE_KEY`, `PRIVATE_KEY_PASSWORD`
3. Run `./gradlew signPlugin`
4. Set `PUBLISH_TOKEN` from Marketplace account
5. Run `./gradlew publishPlugin`

#### Custom Distribution (Alternative)

For internal or pre-release distribution, host an `updatePlugins.xml` file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plugins>
    <plugin id="com.anthropic.claudecode"
            url="https://releases.anthropic.com/claude-code-intellij/latest.zip"
            version="0.1.0"/>
</plugins>
```

Users add the URL as a custom plugin repository in Settings > Plugins > Manage Repositories.

#### Acceptance Criteria

- [ ] All unit tests pass (`./gradlew test`)
- [ ] Plugin verifier passes (`./gradlew verifyPlugin`)
- [ ] Plugin ZIP installs correctly in a clean IDE
- [ ] Plugin loads in IntelliJ IDEA, PyCharm, and WebStorm
- [ ] CI/CD pipeline builds, tests, verifies, and (on tags) publishes
- [ ] Marketplace listing is approved (if applicable)

---

## File Structure

### Complete Target Directory Tree

```
claude-code-intellij/
|
+-- .github/
|   +-- workflows/
|       +-- build.yml                          # CI/CD pipeline
|
+-- .run/
|   +-- Run IDE with Plugin.run.xml            # IDE run configuration
|
+-- gradle/
|   +-- wrapper/
|   |   +-- gradle-wrapper.jar
|   |   +-- gradle-wrapper.properties          # Gradle 8.12
|   +-- libs.versions.toml                     # Version catalog
|
+-- src/
|   +-- main/
|   |   +-- kotlin/
|   |   |   +-- com/anthropic/claudecode/
|   |   |       +-- actions/
|   |   |       |   +-- OpenPanelAction.kt         # Open tool window
|   |   |       |   +-- NewConversationAction.kt   # New conversation
|   |   |       |   +-- OpenTerminalAction.kt      # Open in terminal
|   |   |       |   +-- SendSelectionAction.kt     # Send selection
|   |   |       |   +-- AcceptDiffAction.kt        # Accept proposed changes
|   |   |       |   +-- RejectDiffAction.kt        # Reject proposed changes
|   |   |       |
|   |   |       +-- editor/
|   |   |       |   +-- EditorContext.kt            # Data classes
|   |   |       |   +-- ClaudeEditorService.kt      # Context + modification
|   |   |       |   +-- ClaudeDiffService.kt        # Diff view management
|   |   |       |   +-- ClaudeEditorListener.kt     # Editor events
|   |   |       |
|   |   |       +-- listeners/
|   |   |       |   +-- ClaudeStartupActivity.kt    # ProjectActivity
|   |   |       |   +-- ProjectCloseListener.kt     # Cleanup on close
|   |   |       |
|   |   |       +-- process/
|   |   |       |   +-- ClaudeBinaryResolver.kt     # Binary resolution
|   |   |       |   +-- ClaudeProcessManager.kt     # Process lifecycle
|   |   |       |   +-- ClaudeErrorHandler.kt       # Error analysis + restart
|   |   |       |   +-- JsonProtocolHandler.kt      # JSON stdin/stdout
|   |   |       |   +-- StderrCollector.kt          # Stderr capture
|   |   |       |
|   |   |       +-- protocol/
|   |   |       |   +-- Messages.kt                 # @Serializable types
|   |   |       |
|   |   |       +-- services/
|   |   |       |   +-- ClaudeCodeService.kt        # Main orchestrator
|   |   |       |   +-- ClaudeCodeSettings.kt       # Persistent state
|   |   |       |
|   |   |       +-- settings/
|   |   |       |   +-- ClaudeCodeConfigurable.kt   # Settings UI
|   |   |       |
|   |   |       +-- terminal/
|   |   |       |   +-- ClaudeTerminalService.kt    # Terminal integration
|   |   |       |
|   |   |       +-- toolwindow/
|   |   |       |   +-- ClaudeCodeToolWindowFactory.kt  # JCEF tool window
|   |   |       |
|   |   |       +-- ui/
|   |   |       |   +-- ClaudeStatusBarWidgetFactory.kt  # Status bar
|   |   |       |   +-- ClaudeStatusBarWidget.kt         # Widget impl
|   |   |       |
|   |   |       +-- webview/
|   |   |           +-- WebviewBridge.kt                 # JS <-> Kotlin bridge
|   |   |           +-- LocalResourceSchemeHandler.kt    # claude://app/ handler
|   |   |           +-- JcefSchemeRegistrar.kt           # Scheme registration
|   |   |           +-- ThemeSynchronizer.kt             # Theme sync
|   |   |           +-- BatchedWebviewUpdater.kt         # Debounced updates
|   |   |
|   |   +-- resources/
|   |       +-- META-INF/
|   |       |   +-- plugin.xml                  # Plugin descriptor
|   |       |   +-- pluginIcon.svg              # 40x40 plugin icon
|   |       |   +-- pluginIcon_dark.svg         # Dark theme variant
|   |       |   +-- terminal-support.xml        # Optional terminal config
|   |       |
|   |       +-- icons/
|   |       |   +-- claude-toolwindow.svg       # 13x13 tool window icon
|   |       |   +-- claude-action.svg           # Action icon
|   |       |
|   |       +-- webview/
|   |           +-- index.html                  # HTML wrapper
|   |           +-- index.js                    # React bundle (from VSCode)
|   |           +-- index.css                   # Styles (from VSCode)
|   |           +-- codicon.ttf                 # Font (from VSCode)
|   |
|   +-- test/
|       +-- kotlin/
|       |   +-- com/anthropic/claudecode/
|       |       +-- services/ClaudeCodeServiceTest.kt
|       |       +-- process/ClaudeBinaryResolverTest.kt
|       |       +-- process/JsonProtocolHandlerTest.kt
|       |       +-- webview/WebviewBridgeTest.kt
|       |       +-- editor/ClaudeEditorServiceTest.kt
|       |       +-- settings/ClaudeCodeSettingsTest.kt
|       +-- resources/
|
+-- binaries/                                   # Platform-specific CLI binaries
|   +-- darwin-aarch64/claude
|   +-- darwin-x86_64/claude
|   +-- linux-aarch64/claude
|   +-- linux-x86_64/claude
|   +-- windows-x86_64/claude.exe
|
+-- build.gradle.kts
+-- settings.gradle.kts
+-- gradle.properties
+-- gradlew
+-- gradlew.bat
+-- CHANGELOG.md
+-- LICENSE
```

---

## Key Implementation Details

### Binary Resolution Strategy

```
Settings override ──> Bundled binary ──> System PATH
    |                      |                   |
    v                      v                   v
ClaudeCodeSettings    PluginManagerCore    which/where +
.state.claudeBinary   .getPlugin()        common locations
Path                  .pluginPath/bin/    (/usr/local/bin,
                      {platform}/claude   /opt/homebrew/bin,
                                          ~/.local/bin, etc.)
```

Cross-platform path handling uses `SystemInfo.isMac`, `SystemInfo.isLinux`, `SystemInfo.isWindows` and `System.getProperty("os.arch")` for architecture detection.

### Message Protocol

Communication with the Claude CLI uses **line-delimited JSON** (JSONL) over stdin/stdout.

**Outgoing (plugin to CLI):**
```json
{"type":"user_message","content":"Explain this code","request_id":"uuid-1234","files":[{"path":"/src/Main.kt"}]}
```

**Incoming (CLI to plugin):**
```json
{"type":"assistant_message","content":"This code does...","message_id":"msg-5678"}
{"type":"stream_delta","delta":"partial text","message_id":"msg-5678"}
{"type":"tool_use","toolName":"edit_file","input":{...},"requestId":"req-9012"}
{"type":"error","error":"Rate limited","code":"rate_limit"}
```

**Request-response correlation:** Messages include `request_id` / `requestId` fields. The `JsonProtocolHandler` uses `ConcurrentHashMap<String, CompletableDeferred<JsonObject>>` to correlate responses to pending requests.

**Event streaming:** Streaming deltas are exposed via `SharedFlow<JsonObject>`. Consumers filter by message type:

```kotlin
protocolHandler.messagesOfType("stream_delta").collect { json ->
    val delta = json["delta"]?.jsonPrimitive?.content ?: ""
    batchedUpdater.appendOutput(delta)
}
```

### Threading Model

| Thread | When to Use | How to Access |
|--------|-------------|---------------|
| **EDT** | UI updates, WriteCommandAction, showing dialogs | `Dispatchers.EDT` or `invokeLater {}` |
| **Dispatchers.IO** | Process I/O, file reads, network | `withContext(Dispatchers.IO) {}` |
| **Dispatchers.Default** | CPU-intensive computation | `withContext(Dispatchers.Default) {}` |
| **CEF IO Thread** | JBCefJSQuery handler callbacks | Automatic (offload heavy work) |

**Key rules:**
1. Never block the EDT (no process I/O, no sleep, no waiting)
2. Never modify UI from a background thread (use `withContext(Dispatchers.EDT)`)
3. `ReadAction` can run on any thread (but must be wrapped)
4. `WriteAction` must run on EDT
5. JBCefJSQuery handlers run on CEF IO thread -- return immediately, send responses via `executeJavaScript`

**Coroutine scope lifecycle:**

```kotlin
@Service(Service.Level.PROJECT)
class ClaudeCodeService(
    private val project: Project,
    private val cs: CoroutineScope  // Platform-injected, cancelled on project close
) : Disposable {
    // All cs.launch {} calls are automatically cancelled when the project closes
}
```

### JCEF Communication Protocol

**JS to Kotlin:**
1. JS calls `window.__sendToHost(type, payload)` which returns a `Promise`
2. JBCefJSQuery routes the call to the Kotlin handler on CEF IO thread
3. Handler returns `JBCefJSQuery.Response(json)` which resolves the Promise

**Kotlin to JS:**
1. Kotlin calls `browser.cefBrowser.executeJavaScript(code, url, 0)`
2. Code dispatches a `CustomEvent('hostMessage', { detail: data })`
3. JS listener `window.addEventListener('hostMessage', handler)` receives the event

**Message envelope format:**
```json
{
    "type": "messageType",
    "payload": { ... }
}
```

**Error handling:**
- JBCefJSQuery supports `Response(null, errorCode, errorMessage)` for error responses
- JS side receives errors via the `onFailure` callback of the injected query
- Timeouts are handled by Promise wrappers on the JS side

### Diff Workflow

1. Claude proposes changes to a file
2. Plugin calls `ClaudeDiffService.showDiff(original, proposed, filePath)`
3. `SimpleDiffRequest` opens a side-by-side diff viewer with syntax highlighting
4. User reviews changes in IntelliJ's native diff viewer
5. **Accept:** Plugin applies `proposed` content via `WriteCommandAction` (undoable)
6. **Reject:** Plugin discards the proposed content (no-op)

For multi-file changes, use `DiffRequestChain` to show a sequence of diffs.

Undo integration: `WriteCommandAction` with `groupId = "claude.applyChanges"` ensures all changes from a single Claude response can be undone in one Ctrl+Z / Cmd+Z step.

---

## Risk Assessment & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **JCEF not available** (headless, remote dev, some Linux) | Low | Medium | Check `JBCefApp.isSupported()`, show fallback Swing panel, offer terminal mode |
| **React webview adapter complexity** | Medium | Medium | Thin adapter layer that detects IntelliJ vs VSCode environment; minimize changes to shared webview code |
| **Cross-IDE compatibility** | Medium | Medium | Depend only on `com.intellij.modules.platform`; test on IDEA, PyCharm, WebStorm; use `verifyPlugin` |
| **IntelliJ API deprecations** | Low | Low | Target 2024.3+, use `@Service` annotations, avoid internal APIs, run `verifyPlugin` in CI |
| **Binary path resolution failures** | Medium | High | Three-tier resolution (settings, bundled, PATH); clear error messages with "Configure" action |
| **Process stability** | Medium | Medium | Exponential backoff restart (up to 5 attempts), stderr analysis for actionable errors |
| **Theme synchronization drift** | Low | Low | Listen to `LafManagerListener.TOPIC`; re-sync on every theme change event |
| **Performance with large streaming output** | Low | Medium | Batched `executeJavaScript` at ~60fps via `SingleAlarm`; `SharedFlow` with buffer |
| **Dynamic plugin load/unload** | Low | Medium | Proper `Disposable` hierarchy; clean up JCEF, processes, coroutines on dispose |
| **Kotlin version conflicts** | Low | High | Use Kotlin 2.0.21 (compatible with 2024.3+); do NOT bundle Kotlin stdlib |

---

## Dependencies & Prerequisites

### Development Environment

| Requirement | Version | Purpose |
|-------------|---------|---------|
| JDK | 21 (JBR 21 recommended) | Compile and run |
| Gradle | 8.10+ (wrapper: 8.12) | Build system |
| IntelliJ IDEA | 2024.3+ | Development IDE |
| Kotlin plugin | 2.0.21+ | Language support |
| Git | Any recent | Version control |

### Runtime Dependencies

| Dependency | Source | Purpose |
|------------|--------|---------|
| `kotlinx-coroutines-core` | Maven Central | Async communication |
| `kotlinx-serialization-json` | Maven Central | JSON parsing |
| IntelliJ Platform SDK | JetBrains repositories | All IDE APIs |
| Terminal plugin | Bundled (optional) | Terminal integration |

### External Dependencies

| Dependency | Required | Purpose |
|------------|----------|---------|
| Claude CLI binary | Yes | AI backend |
| Node.js | Only if modifying React code | Webview development |

### Build Dependencies

| Dependency | Purpose |
|------------|---------|
| `instrumentationTools()` | Platform instrumentation |
| `pluginVerifier()` | Binary compatibility checking |
| `zipSigner()` | Plugin signing for Marketplace |
| `testFramework(TestFrameworkType.Platform)` | IntelliJ test base classes |

---

## Success Criteria

### Functional Requirements

- [ ] Plugin loads successfully in IntelliJ IDEA, PyCharm, WebStorm, GoLand, PhpStorm, CLion, Rider, RubyMine
- [ ] Can spawn and communicate with Claude CLI binary
- [ ] JCEF webview renders the React UI correctly
- [ ] Theme synchronization works (dark/light mode)
- [ ] Editor context (file, selection, cursor) is sent to Claude
- [ ] Claude can read and write files with proper undo support
- [ ] Diff view shows proposed changes with accept/reject
- [ ] All VSCode settings have IntelliJ equivalents
- [ ] Keyboard shortcuts work on Windows, macOS, and Linux
- [ ] Terminal mode works as an alternative to the webview
- [ ] Status bar widget shows connection state
- [ ] Process crash recovery with automatic restart

### Non-Functional Requirements

- [ ] Plugin passes `verifyPlugin` against 2024.3, 2025.1, and 2025.2
- [ ] Plugin loads without errors when JCEF is unavailable (graceful fallback)
- [ ] No EDT freezes during streaming output
- [ ] Memory: single JCEF browser instance per project, proper disposal
- [ ] Dynamic plugin load/unload works without IDE restart
- [ ] CI pipeline builds, tests, and verifies on every push

---

## References

### Research Documents

| Document | Description |
|----------|-------------|
| [intellij-plugin.md](../intellij-plugin.md) | Original feasibility analysis (85% feasibility rating) |
| [01-platform-research.md](./01-platform-research.md) | IntelliJ Platform SDK versions, Gradle plugin 2.x, JCEF status, Kotlin versions, API changes |
| [02-jcef-webview-research.md](./02-jcef-webview-research.md) | JBCefBrowser API, JBCefJSQuery communication, custom scheme handlers, theme sync, DevTools |
| [03-gradle-project-setup.md](./03-gradle-project-setup.md) | Complete Gradle project setup, plugin.xml, CI/CD, dependencies, build tasks |
| [04-process-management-research.md](./04-process-management-research.md) | GeneralCommandLine, KillableProcessHandler, coroutines, JSON protocol, lifecycle management |
| [05-editor-diff-terminal-research.md](./05-editor-diff-terminal-research.md) | Editor APIs, document modification, DiffManager, terminal API, notifications |

### Official Documentation

| Resource | URL |
|----------|-----|
| IntelliJ Platform SDK Docs | https://plugins.jetbrains.com/docs/intellij/welcome.html |
| Gradle IntelliJ Platform Plugin 2.x | https://plugins.jetbrains.com/docs/intellij/tools-intellij-platform-gradle-plugin.html |
| JCEF Documentation | https://plugins.jetbrains.com/docs/intellij/jcef.html |
| Threading Model | https://plugins.jetbrains.com/docs/intellij/general-threading-rules.html |
| Kotlin Coroutines in Plugins | https://plugins.jetbrains.com/docs/intellij/kotlin-coroutines.html |
| Disposers | https://plugins.jetbrains.com/docs/intellij/disposers.html |
| Plugin Services | https://plugins.jetbrains.com/docs/intellij/plugin-services.html |
| Tool Windows | https://plugins.jetbrains.com/docs/intellij/tool-windows.html |
| Actions | https://plugins.jetbrains.com/docs/intellij/basic-action-system.html |
| Diff Framework | https://plugins.jetbrains.com/docs/intellij/diff.html |
| Plugin Signing | https://plugins.jetbrains.com/docs/intellij/plugin-signing.html |
| Plugin Verification | https://plugins.jetbrains.com/docs/intellij/verifying-plugin-compatibility.html |
| Build Number Ranges | https://plugins.jetbrains.com/docs/intellij/build-number-ranges.html |
| API Changes List | https://plugins.jetbrains.com/docs/intellij/api-changes-list.html |

### Templates and Examples

| Resource | URL |
|----------|-----|
| IntelliJ Platform Plugin Template | https://github.com/JetBrains/intellij-platform-plugin-template |
| Gradle IntelliJ Platform Plugin Source | https://github.com/JetBrains/intellij-platform-gradle-plugin |
| IntelliJ Community Source | https://github.com/JetBrains/intellij-community |
| Markdown Plugin (JCEF example) | https://github.com/JetBrains/intellij-community/tree/master/plugins/markdown |
| JCEF Sample Plugin | https://github.com/nicholasgasior/intellij-jcef-sample-plugin |
| Jewel (Compose for Desktop theme) | https://github.com/JetBrains/jewel |
