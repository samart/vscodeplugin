# Agent Execution Plan: Claude Code IntelliJ Plugin

> **Document Version:** 1.0
> **Date:** February 2, 2026
> **Status:** Ready for execution
> **Prerequisite:** All research documents (01-06) and master plan (00) completed

---

## Overview

This document breaks the Claude Code IntelliJ plugin implementation into **11 independent work packages** that can be assigned to multiple coding agents working simultaneously. Each task is sized for a single agent session (2-4 hours of focused work, 3-10 files).

### Design Principles

1. **Agent-0 creates stubs** -- every other agent writes into files that already exist with compilable empty stubs
2. **No agent modifies another agent's files** -- each agent owns a disjoint set of files
3. **Interfaces are defined in Agent-0's stubs** -- agents code against interfaces, not implementations
4. **plugin.xml is owned by Agent-0** -- other agents provide XML snippets in comments; Agent-0's stubs include all registrations
5. **Tests are a separate agent** -- unit tests run after all implementation agents complete

### Metrics

| Metric | Value |
|--------|-------|
| Total agents | 11 (Agent-0 through Agent-10) |
| Maximum parallelism | 4 agents at T1 |
| Total estimated files | ~55-65 |
| Critical path length | 4 phases (T0 -> T1 -> T2 -> T3 -> T4) |
| Estimated wall-clock time | ~12-16 hours with 4 parallel agents |

---

## Dependency Graph (ASCII)

```
Phase T0: Bootstrap (must complete first)
  Agent-0: Project Scaffold & Stubs
        |
        +-------+-------+-------+
        |       |       |       |
Phase T1: (all four can run in parallel after Agent-0)
  Agent-1    Agent-2    Agent-3    Agent-4
  Process    JCEF       Settings   Actions &
  Mgmt &     Webview    & Config   Keybindings
  Protocol   Core
        |       |       |       |
        +---+---+       |       |
        |   |           |       |
Phase T2: (can run in parallel; each depends on specific T1 agents)
  Agent-5         Agent-6         Agent-7         Agent-9
  Editor          Webview         Diff            Terminal
  Integration     Bridge          Service         & MCP
  [needs A1]      [needs A1+A2]   [needs A1]      [needs A1]
        |               |               |
        +-------+-------+-------+-------+
                |
Phase T3: (needs most T1+T2 agents)
          Agent-8
          Main Service
          Orchestrator
          [needs A1+A2+A3+A5+A6]
                |
Phase T4: (needs all agents)
          Agent-10
          Testing &
          Verification
```

### Dependency Matrix

| Agent | Depends On | Blocks |
|-------|-----------|--------|
| Agent-0 | None | All others |
| Agent-1 | Agent-0 | Agent-5, Agent-6, Agent-7, Agent-8, Agent-9 |
| Agent-2 | Agent-0 | Agent-6, Agent-8 |
| Agent-3 | Agent-0 | Agent-8 |
| Agent-4 | Agent-0 | Agent-10 |
| Agent-5 | Agent-1 | Agent-8, Agent-10 |
| Agent-6 | Agent-1, Agent-2 | Agent-8, Agent-10 |
| Agent-7 | Agent-1 | Agent-10 |
| Agent-8 | Agent-1, Agent-2, Agent-3, Agent-5, Agent-6 | Agent-10 |
| Agent-9 | Agent-1 | Agent-10 |
| Agent-10 | All | None |

---

## Parallel Execution Schedule

```
Time --->

T0:  [=== Agent-0: Scaffold ===]
      ~2 hours

T1:  [=== Agent-1: Process ===] [=== Agent-2: JCEF ===] [=== Agent-3: Settings ===] [=== Agent-4: Actions ===]
      ~3 hours                    ~3 hours                 ~2 hours                    ~2 hours

T2:  [=== Agent-5: Editor ===]  [=== Agent-6: Bridge ===] [=== Agent-7: Diff ===]    [=== Agent-9: Terminal ===]
      ~2 hours                    ~3 hours                  ~2 hours                    ~2 hours

T3:  [======= Agent-8: Orchestrator =======]
      ~3 hours

T4:  [======= Agent-10: Testing & Verification =======]
      ~3 hours
```

**Wall-clock total:** ~13 hours (with 4 parallel agents at T1 and T2)
**Sequential total:** ~25 hours (if done by a single agent)
**Speedup factor:** ~1.9x

---

## Task Definitions

---

### Agent-0: Project Scaffold & Build System

**Dependencies:** None (run first)
**Estimated effort:** 2 hours
**Estimated files:** 12-15
**Packages to create:** `actions`, `editor`, `listeners`, `process`, `protocol`, `services`, `settings`, `terminal`, `toolwindow`, `ui`, `webview`, `mcp`

#### Description

Create the complete Gradle project structure with `plugin.xml`, `build.gradle.kts`, all package directories, and **compilable stub classes** for every file in the target structure. Stubs contain class/interface declarations, method signatures with `TODO()` bodies, and correct imports. This allows all other agents to code against concrete types from the start.

#### Files to Create

**Build system:**
- `claude-code-intellij/settings.gradle.kts`
- `claude-code-intellij/build.gradle.kts`
- `claude-code-intellij/gradle.properties`
- `claude-code-intellij/gradle/libs.versions.toml`
- `claude-code-intellij/gradle/wrapper/gradle-wrapper.properties`

**Plugin descriptor (complete, with all extension points registered):**
- `src/main/resources/META-INF/plugin.xml`
- `src/main/resources/META-INF/terminal-support.xml`
- `src/main/resources/META-INF/pluginIcon.svg` (placeholder)
- `src/main/resources/META-INF/pluginIcon_dark.svg` (placeholder)

**Icon resources:**
- `src/main/resources/icons/claude-toolwindow.svg`
- `src/main/resources/icons/claude-action.svg`

**Stub Kotlin files (one per target class, compilable with TODO bodies):**
- `src/main/kotlin/com/anthropic/claudecode/ClaudeCodeBundle.kt` -- plugin-level constants, message bundle
- All stub files for services, actions, process, protocol, etc. (see "Stub Requirements" below)

**Webview resources (copy from VSCode extension):**
- `src/main/resources/webview/index.html` (wrapper HTML)
- Copy `webview/index.js` and `webview/index.css` from the VSCode extension

**Run configuration:**
- `.run/Run IDE with Plugin.run.xml`

#### Stub Requirements

Every stub class must:
1. Have the correct package declaration
2. Import all IntelliJ Platform types it will use
3. Implement the correct interface (e.g., `ToolWindowFactory`, `PersistentStateComponent`, `AnAction`)
4. Have method signatures matching the interface contract
5. Use `TODO("Implemented by Agent-N")` as the method body
6. Be compilable -- `./gradlew build` must succeed with all stubs

Example stub:
```kotlin
// src/main/kotlin/com/anthropic/claudecode/process/ClaudeBinaryResolver.kt
package com.anthropic.claudecode.process

/**
 * Resolves the Claude CLI binary path.
 * Resolution order: Settings override -> Bundled binary -> System PATH
 *
 * @see com.anthropic.claudecode.services.ClaudeCodeSettings
 */
object ClaudeBinaryResolver {
    data class ResolvedBinary(
        val executablePath: String,
        val args: List<String> = emptyList(),
        val env: Map<String, String> = emptyMap()
    )

    fun resolve(settings: com.anthropic.claudecode.services.ClaudeCodeSettings): ResolvedBinary {
        TODO("Implemented by Agent-1")
    }
}
```

#### Plugin.xml Must Include

All extension point registrations:
- `<projectService>` for ClaudeCodeService, ClaudeCodeSettings, ClaudeEditorService, ClaudeDiffService, ClaudeTerminalService
- `<toolWindow>` for ClaudeCodeToolWindowFactory
- `<statusBarWidgetFactory>` for ClaudeStatusBarWidgetFactory
- `<projectConfigurable>` for ClaudeCodeConfigurable
- `<notificationGroup>` for "Claude Code Notifications"
- `<postStartupActivity>` for ClaudeStartupActivity
- `<appLifecycleListener>` for JcefSchemeRegistrar
- All `<action>` registrations with keyboard shortcuts
- Optional dependency on `org.jetbrains.plugins.terminal`

#### Acceptance Criteria

- [ ] `./gradlew build` succeeds (all stubs compile)
- [ ] `./gradlew runIde` launches a sandbox IDE
- [ ] Plugin appears in the sandbox IDE's plugin list as "Claude Code"
- [ ] Tool window icon is visible in the sidebar (shows TODO content)
- [ ] All package directories exist under `com/anthropic/claudecode/`
- [ ] Every target Kotlin file exists as a compilable stub
- [ ] `plugin.xml` registers all extension points

#### Key References

- `03-gradle-project-setup.md` -- Complete Gradle setup, build.gradle.kts, settings.gradle.kts, gradle.properties, libs.versions.toml
- `00-master-implementation-plan.md` -- File Structure section (lines 1031-1149), Component Mapping table (lines 132-149)

#### What NOT to Do

- Do NOT implement any business logic -- stubs only
- Do NOT add test files (Agent-10's job)
- Do NOT add CI/CD pipeline (Agent-10's job)
- Do NOT modify the React webview code (`index.js`, `index.css`)

---

### Agent-1: Process Management & JSON Protocol

**Dependencies:** Agent-0 (stubs must exist)
**Estimated effort:** 3 hours
**Estimated files:** 7

#### Description

Implement the full Claude CLI process lifecycle: binary resolution, process spawning via `GeneralCommandLine` + `KillableProcessHandler`, NDJSON protocol communication over stdin/stdout, stderr collection, error handling with exponential backoff restart, and all `@Serializable` message types.

#### Files to Implement (replace stub bodies)

| File | Path (under `src/main/kotlin/com/anthropic/claudecode/`) | Lines Est. |
|------|------|------------|
| ClaudeBinaryResolver.kt | `process/ClaudeBinaryResolver.kt` | ~80 |
| ClaudeProcessManager.kt | `process/ClaudeProcessManager.kt` | ~150 |
| JsonProtocolHandler.kt | `process/JsonProtocolHandler.kt` | ~120 |
| StderrCollector.kt | `process/StderrCollector.kt` | ~40 |
| ClaudeErrorHandler.kt | `process/ClaudeErrorHandler.kt` | ~60 |
| Messages.kt | `protocol/Messages.kt` | ~200 |
| CliMessages.kt | `protocol/CliMessages.kt` | ~80 |

#### Implementation Details

**ClaudeBinaryResolver.kt:**
- Resolution chain: Settings path -> Bundled binary (`PluginManagerCore.getPlugin().pluginPath/bin/{platform}-{arch}/claude`) -> System PATH (`/usr/local/bin`, `/opt/homebrew/bin`, `~/.local/bin`, `which claude`)
- Platform detection via `SystemInfo.isMac`, `SystemInfo.isLinux`, `SystemInfo.isWindows` + `System.getProperty("os.arch")`
- Throws `ClaudeBinaryNotFoundException` (custom exception) with actionable message
- Returns `ResolvedBinary(executablePath, args, env)`

**ClaudeProcessManager.kt:**
- Uses `GeneralCommandLine` with `ParentEnvironmentType.CONSOLE`
- Sets env vars: `CLAUDE_CODE_IDE=intellij`, `CLAUDE_CODE_IDE_VERSION=...`, `TERM=dumb`, `NO_COLOR=1`, plus user-configured env vars
- Wraps in `KillableProcessHandler` with `setShouldDestroyProcessRecursively(true)`
- State machine via `StateFlow<ProcessState>`: `STOPPED -> STARTING -> RUNNING -> CRASHED -> RESTARTING -> STOPPED`
- Graceful shutdown: SIGTERM, wait 5s, SIGKILL
- Owns a `CoroutineScope` that is cancelled on dispose

**JsonProtocolHandler.kt:**
- Read loop: `BufferedReader(process.inputStream).readLine()` on `Dispatchers.IO`, parse as `JsonObject`, emit to `MutableSharedFlow<JsonObject>(extraBufferCapacity = 128)`
- Write loop: consume from `Channel<String>(Channel.BUFFERED)`, write line + newline + flush to `process.outputStream`
- `sendAndReceive()`: generates UUID `requestId`, stores `CompletableDeferred<JsonObject>` in `ConcurrentHashMap`, sends message, waits with `withTimeout(30_000)`
- `messagesOfType(type)`: returns `Flow<JsonObject>` filtered by `type` field
- `streamDeltas()`: returns flow of `delta` string values from `stream_delta` messages

**StderrCollector.kt:**
- Reads `process.errorStream` line-by-line, stores last 100 lines in ring buffer
- Exposes `getRecentStderr(): List<String>`

**ClaudeErrorHandler.kt:**
- Maps exit codes to error messages: 0=normal, 1=general error, 2=binary not found, etc.
- Exponential backoff: delays of 1s, 2s, 4s, 8s, 16s (cap), max 5 restarts
- `shouldRestart(exitCode, restartCount): Boolean`
- `getRestartDelay(restartCount): Long`

**Messages.kt (protocol/Messages.kt):**
- All `@Serializable` data classes for the wire protocol
- Webview request types (init, launch_claude, io_message, interrupt_claude, close_channel, etc. -- ~54 types from Section 14.1)
- Extension push message types (io_message, close_channel, file_updated, response, request -- ~14 types from Section 14.2)

**CliMessages.kt (protocol/CliMessages.kt):**
- CLI stdout message types: user, assistant, system, result, error, tool_use, tool_result, progress, control_response, auth_status, keep_alive
- CLI stdin control subtypes: initialize, interrupt, set_model, set_max_thinking_tokens, set_permission_mode, mcp_message, mcp_reconnect, mcp_set_servers, mcp_toggle

#### Code Patterns to Follow

```kotlin
// Process spawning pattern
val commandLine = GeneralCommandLine(binaryPath)
    .withWorkDirectory(project.basePath)
    .withParentEnvironmentType(GeneralCommandLine.ParentEnvironmentType.CONSOLE)
    .withEnvironment(buildEnvironment(settings))
    .withParameters("--ide", "--output-format", "stream-json")

val processHandler = KillableProcessHandler(commandLine).apply {
    setShouldDestroyProcessRecursively(true)
}

// NDJSON read pattern
val reader = BufferedReader(InputStreamReader(process.inputStream, Charsets.UTF_8))
while (isActive) {
    val line = withContext(Dispatchers.IO) { reader.readLine() } ?: break
    val json = Json.parseToJsonElement(line).jsonObject
    _messages.emit(json)
    // Check for request-response correlation
    json["requestId"]?.jsonPrimitive?.contentOrNull?.let { id ->
        pendingRequests.remove(id)?.complete(json)
    }
}
```

#### Acceptance Criteria

- [ ] `ClaudeBinaryResolver.resolve()` finds the Claude binary on the test system
- [ ] `ClaudeProcessManager` can spawn the CLI process with correct env vars and working directory
- [ ] JSON messages can be written to stdin and read from stdout (NDJSON format)
- [ ] `sendAndReceive()` correlates requests and responses by `requestId`
- [ ] `messagesOfType()` correctly filters the message stream
- [ ] Process crash triggers automatic restart with exponential backoff (1s, 2s, 4s, 8s, 16s)
- [ ] Max 5 restarts before giving up (state becomes `STOPPED` with error)
- [ ] Graceful shutdown via `destroyProcess()` sends SIGTERM then SIGKILL after 5s
- [ ] `ProcessState` changes are observable via `StateFlow`
- [ ] All 54+ webview message types and 12 CLI message types have `@Serializable` definitions

#### Key References

- `04-process-management-research.md` -- GeneralCommandLine, KillableProcessHandler, ProcessListener, environment setup, restart logic
- `06-vscode-extension-reverse-engineering.md` Section 1-2 -- Binary discovery, process spawning, NDJSON protocol
- `06-vscode-extension-reverse-engineering.md` Section 14 -- All message type tables
- `00-master-implementation-plan.md` Phase 2 (lines 290-418) -- Process lifecycle state machine, JSON protocol handler pattern

#### What NOT to Do

- Do NOT implement the webview bridge (Agent-6's job)
- Do NOT implement the main ClaudeCodeService orchestrator (Agent-8's job)
- Do NOT implement settings UI (Agent-3's job)
- Do NOT write to the UI thread -- all process I/O happens on `Dispatchers.IO`
- Do NOT modify `plugin.xml`

---

### Agent-2: JCEF Webview Core

**Dependencies:** Agent-0 (stubs must exist)
**Estimated effort:** 3 hours
**Estimated files:** 6

#### Description

Create the JCEF-based tool window that loads the existing React webview. Implement the custom `claude://app/` scheme handler for serving bundled resources, theme synchronization from IntelliJ LAF to CSS variables, the HTML wrapper generator, and the JCEF fallback for unsupported environments.

#### Files to Implement

| File | Path (under `src/main/kotlin/com/anthropic/claudecode/`) | Lines Est. |
|------|------|------------|
| ClaudeCodeToolWindowFactory.kt | `toolwindow/ClaudeCodeToolWindowFactory.kt` | ~80 |
| LocalResourceSchemeHandler.kt | `webview/LocalResourceSchemeHandler.kt` | ~120 |
| JcefSchemeRegistrar.kt | `webview/JcefSchemeRegistrar.kt` | ~30 |
| ThemeSynchronizer.kt | `webview/ThemeSynchronizer.kt` | ~120 |
| WebviewHtmlGenerator.kt | `webview/WebviewHtmlGenerator.kt` | ~60 |
| BatchedWebviewUpdater.kt | `webview/BatchedWebviewUpdater.kt` | ~50 |

#### Implementation Details

**ClaudeCodeToolWindowFactory.kt:**
- Implements `ToolWindowFactory`, `DumbAware`
- `createToolWindowContent()`: check `JBCefApp.isSupported()`, create `JBCefBrowser`, load `claude://app/index.html`
- If JCEF not supported: show Swing `JPanel` with message "JCEF is not available. Use terminal mode (Settings > Tools > Claude Code > Use Terminal)"
- Store `JBCefBrowser` reference in project-level service or tool window content
- Register as `Disposable` -- dispose browser on tool window close
- Enable DevTools in development builds via `JBCefBrowser.setProperty("ide.browser.jcef.contextMenu.devTools.enabled", true)`

**LocalResourceSchemeHandler.kt:**
- `LocalResourceSchemeHandlerFactory : CefSchemeHandlerFactory` -- creates `LocalResourceHandler` instances
- `LocalResourceHandler : CefResourceHandler` -- serves files from `/webview/` classpath resources
- Maps URL path `claude://app/{path}` to classpath resource `/webview/{path}`
- MIME type detection: `.html` -> `text/html`, `.js` -> `application/javascript`, `.css` -> `text/css`, `.svg` -> `image/svg+xml`, `.ttf` -> `font/ttf`, `.woff2` -> `font/woff2`, `.png` -> `image/png`
- Sets proper `Content-Type` and `Content-Length` headers
- Returns 404 for missing resources

**JcefSchemeRegistrar.kt:**
- Implements `AppLifecycleListener`
- `appStarted()`: register `claude` scheme with `app` domain via `JBCefApp.getInstance().cefApp.registerSchemeHandlerFactory("claude", "app", LocalResourceSchemeHandlerFactory())`
- Guard with `JBCefApp.isSupported()` check

**ThemeSynchronizer.kt:**
- Maps IntelliJ `UIManager` color keys to VSCode CSS variable equivalents
- CSS variable mapping (from Appendix D of 06-reverse-engineering.md):
  - `--vscode-editor-background` <- `UIManager.getColor("Editor.background")`
  - `--vscode-editor-foreground` <- `UIManager.getColor("Editor.foreground")`
  - `--vscode-button-background` <- `UIManager.getColor("Button.startBackground")`
  - `--vscode-button-foreground` <- `UIManager.getColor("Button.foreground")`
  - `--vscode-input-background` <- `UIManager.getColor("TextField.background")`
  - `--vscode-input-foreground` <- `UIManager.getColor("TextField.foreground")`
  - `--vscode-badge-background` <- `UIManager.getColor("Counter.background")`
  - `--vscode-descriptionForeground` <- `UIManager.getColor("Label.disabledForeground")`
  - Plus ~15 more mappings
- `syncTheme(browser: CefBrowser)`: builds JSON map, calls `browser.executeJavaScript("window.__applyIdeTheme && window.__applyIdeTheme(${json})", ...)`
- Subscribes to `LafManagerListener.TOPIC` via `project.messageBus.connect(disposable)` to re-sync on theme change
- Adds CSS class `vscode-dark` or `vscode-light` to `<body>` based on `UIUtil.isUnderDarcula()`

**WebviewHtmlGenerator.kt:**
- Generates the `index.html` wrapper that loads the React app
- Sets Content-Security-Policy meta tag allowing `claude://app/` and `data:` schemes
- Includes `<link>` to `index.css` and `<script>` for `index.js`
- Includes inline script for bridge adapter (environment detection)
- Sets `<body class="vscode-dark">` or `"vscode-light"` based on theme

**BatchedWebviewUpdater.kt:**
- Accumulates streaming text in a `StringBuilder` (synchronized)
- Uses `SingleAlarm(::flush, 16, disposable)` to batch at ~60fps
- `flush()` serializes accumulated text, calls `browser.cefBrowser.executeJavaScript(...)` to push to React app
- `appendOutput(text: String)`: add to buffer, request alarm

#### Code Patterns to Follow

```kotlin
// Tool window creation
class ClaudeCodeToolWindowFactory : ToolWindowFactory, DumbAware {
    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        if (!JBCefApp.isSupported()) {
            // Fallback Swing panel
            val panel = JPanel(BorderLayout())
            panel.add(JBLabel("JCEF not available. Use Settings > Tools > Claude Code > Use Terminal"))
            toolWindow.component.add(panel)
            return
        }
        val browser = JBCefBrowser()
        // Register disposable
        Disposer.register(toolWindow.disposable, browser)
        browser.loadURL("claude://app/index.html")
        toolWindow.component.add(browser.component, BorderLayout.CENTER)
    }
}

// Scheme handler pattern
class LocalResourceHandler : CefResourceHandler {
    private var data: ByteArray? = null
    private var offset = 0
    private var mimeType = "text/html"

    override fun processRequest(request: CefRequest, callback: CefCallback): Boolean {
        val path = URI(request.url).path.removePrefix("/")
        val resource = javaClass.getResourceAsStream("/webview/$path") ?: return false
        data = resource.readAllBytes()
        mimeType = getMimeType(path)
        callback.Continue()
        return true
    }
}

// Theme sync pattern
fun syncTheme(browser: CefBrowser) {
    val colors = buildMap {
        put("isDark", UIUtil.isUnderDarcula().toString())
        put("background", colorToHex(UIManager.getColor("Panel.background")))
        // ... more colors
    }
    val json = Json.encodeToString(colors)
    browser.executeJavaScript("window.__applyIdeTheme && window.__applyIdeTheme($json);", "", 0)
}
```

#### Acceptance Criteria

- [ ] Tool window appears in IDE sidebar with Claude icon
- [ ] Clicking the tool window icon opens a JCEF browser panel
- [ ] `claude://app/index.html` loads successfully
- [ ] React app renders (the bundled `index.js` executes)
- [ ] CSS/JS/font resources are served correctly via the scheme handler
- [ ] IntelliJ dark theme colors map to VSCode CSS variables
- [ ] Switching IDE theme (dark/light) updates webview colors in real time
- [ ] Fallback Swing panel shows when JCEF is unavailable
- [ ] Streaming text updates render at ~60fps without EDT freezes
- [ ] Browser is properly disposed when tool window closes

#### Key References

- `02-jcef-webview-research.md` -- JBCefBrowser API, scheme handlers, DevTools, performance
- `06-vscode-extension-reverse-engineering.md` Section 3 (Webview Init), Section 11 (Panel Management), Appendix D (CSS Variable Mapping)
- `00-master-implementation-plan.md` Phase 3 (lines 421-589)

#### What NOT to Do

- Do NOT implement the communication bridge (`postMessage`/`onMessage`) -- that is Agent-6's job
- Do NOT implement message routing logic
- Do NOT modify the React webview code (`index.js`)
- Do NOT implement process management -- Agent-1's job
- Do NOT write any code that depends on `ClaudeCodeService` -- Agent-8's job

---

### Agent-3: Settings & Configuration

**Dependencies:** Agent-0 (stubs must exist)
**Estimated effort:** 2 hours
**Estimated files:** 3

#### Description

Implement the persistent settings component (`PersistentStateComponent`), the settings UI panel using Kotlin UI DSL, and a settings change notification system. All VSCode settings from `package.json` must have IntelliJ equivalents.

#### Files to Implement

| File | Path (under `src/main/kotlin/com/anthropic/claudecode/`) | Lines Est. |
|------|------|------------|
| ClaudeCodeSettings.kt | `services/ClaudeCodeSettings.kt` | ~100 |
| ClaudeCodeConfigurable.kt | `settings/ClaudeCodeConfigurable.kt` | ~120 |
| ClaudeCodeSettingsListener.kt | `settings/ClaudeCodeSettingsListener.kt` | ~30 |

#### Implementation Details

**ClaudeCodeSettings.kt:**
- `@State(name = "ClaudeCodeSettings", storages = [Storage("claudeCode.xml")])`
- `@Service(Service.Level.PROJECT)` -- project-level settings
- Implements `PersistentStateComponent<ClaudeCodeSettings.State>`
- `companion object { fun getInstance(project: Project): ClaudeCodeSettings }`

Settings to implement (mapped from VSCode `package.json`):

| Setting | Field | Type | Default |
|---------|-------|------|---------|
| Selected model | `selectedModel` | `String` | `"default"` |
| Environment variables | `environmentVariables` | `MutableList<EnvVar>` | `mutableListOf()` |
| Use terminal mode | `useTerminal` | `Boolean` | `false` |
| Allow dangerous skip | `allowDangerouslySkipPermissions` | `Boolean` | `false` |
| Binary path override | `claudeBinaryPath` | `String?` | `null` |
| Respect .gitignore | `respectGitIgnore` | `Boolean` | `true` |
| Initial permission mode | `initialPermissionMode` | `String` | `"default"` |
| Autosave | `autosave` | `Boolean` | `true` |
| Disable login prompt | `disableLoginPrompt` | `Boolean` | `false` |
| Open new in tab | `openNewInTab` | `Boolean` | `true` |
| Thinking level | `thinkingLevel` | `String` | `"default"` |
| Max thinking tokens | `maxThinkingTokens` | `Int?` | `null` |

- `EnvVar` data class: `data class EnvVar(var name: String = "", var value: String = "")`
- Must use `var` fields (not `val`) for XML serialization compatibility
- State class needs a no-arg constructor

**ClaudeCodeConfigurable.kt:**
- `class ClaudeCodeConfigurable(private val project: Project) : BoundConfigurable("Claude Code")`
- Register under `parentId="tools"` in `plugin.xml`
- UI layout using Kotlin UI DSL `panel { ... }`:
  - **General** group: Model dropdown, Binary path with browse button, Use terminal checkbox, Autosave checkbox, Respect .gitignore checkbox
  - **Permission Mode** group: Initial mode dropdown (`default`, `acceptEdits`, `plan`, `bypassPermissions`), Allow dangerous skip checkbox (with warning text)
  - **Advanced** group: Thinking level dropdown, Max thinking tokens spinner, Open new in tab checkbox, Disable login prompt checkbox
  - **Environment Variables** group: Editable key-value table (name, value columns)

**ClaudeCodeSettingsListener.kt:**
- Topic-based listener interface for settings changes
- `interface ClaudeCodeSettingsListener { fun settingsChanged(oldState: State, newState: State) }`
- Topic: `val TOPIC = Topic.create("Claude Code Settings", ClaudeCodeSettingsListener::class.java)`
- `ClaudeCodeSettings` publishes changes via `project.messageBus.syncPublisher(TOPIC).settingsChanged(old, new)` in `loadState()`

#### Code Patterns to Follow

```kotlin
// Settings UI DSL pattern
override fun createPanel(): DialogPanel = panel {
    group("General") {
        row("Model:") {
            comboBox(listOf("default", "claude-sonnet-4-20250514", "claude-opus-4-20250514"))
                .bindItem(settings.state::selectedModel.toNullableProperty())
        }
        row("Claude binary path:") {
            textFieldWithBrowseButton("Select Claude Binary", project)
                .bindText(settings.state::claudeBinaryPath.toNonNullableProperty(""))
                .comment("Leave empty to auto-detect")
        }
        row {
            checkBox("Use terminal mode instead of webview")
                .bindSelected(settings.state::useTerminal)
        }
    }
}

// Environment variables table
group("Environment Variables") {
    row {
        // Use a ListCellRenderer-based table
        cell(ToolbarDecorator.createDecorator(envVarTable)
            .setAddAction { addEnvVar() }
            .setRemoveAction { removeSelectedEnvVar() }
            .createPanel()
        ).align(Align.FILL)
    }
}
```

#### Acceptance Criteria

- [ ] Settings page appears under Settings > Tools > Claude Code
- [ ] All 12 settings from the mapping table render correctly
- [ ] Model dropdown shows available models
- [ ] Binary path field has a file browser button
- [ ] Permission mode dropdown shows all 4 modes
- [ ] Environment variables table supports add/remove/edit rows
- [ ] Settings persist across IDE restarts (check `claudeCode.xml` in project config)
- [ ] Changing a setting fires `ClaudeCodeSettingsListener` notification
- [ ] Default values are sensible (no binary path = auto-detect, model = default)
- [ ] Warning text appears next to "Allow dangerous skip permissions"

#### Key References

- `00-master-implementation-plan.md` Phase 5 (lines 706-791) -- Settings mapping, PersistentStateComponent pattern, Kotlin UI DSL
- `06-vscode-extension-reverse-engineering.md` Section 12 -- Configuration handling patterns from VSCode

#### What NOT to Do

- Do NOT implement process management logic that depends on settings
- Do NOT implement the service that reads settings for process startup -- Agent-8's job
- Do NOT modify `plugin.xml` (registrations are in Agent-0's stubs)
- Do NOT add settings validation that depends on binary resolution

---

### Agent-4: Actions & Keybindings

**Dependencies:** Agent-0 (stubs must exist)
**Estimated effort:** 2 hours
**Estimated files:** 8-10

#### Description

Implement all `AnAction` classes, register keyboard shortcuts, and wire up the Tools menu, editor context menu, and command palette entries. Actions should be self-contained -- they interact with services via `project.service<...>()` calls but do not implement the services themselves.

#### Files to Implement

| File | Path (under `src/main/kotlin/com/anthropic/claudecode/actions/`) | Lines Est. |
|------|------|------------|
| OpenPanelAction.kt | `actions/OpenPanelAction.kt` | ~30 |
| NewConversationAction.kt | `actions/NewConversationAction.kt` | ~30 |
| OpenTerminalAction.kt | `actions/OpenTerminalAction.kt` | ~35 |
| SendSelectionAction.kt | `actions/SendSelectionAction.kt` | ~50 |
| AcceptDiffAction.kt | `actions/AcceptDiffAction.kt` | ~40 |
| RejectDiffAction.kt | `actions/RejectDiffAction.kt` | ~30 |
| InsertAtMentionAction.kt | `actions/InsertAtMentionAction.kt` | ~35 |
| FocusInputAction.kt | `actions/FocusInputAction.kt` | ~25 |
| BlurInputAction.kt | `actions/BlurInputAction.kt` | ~25 |
| ShowLogsAction.kt | `actions/ShowLogsAction.kt` | ~25 |

#### Implementation Details

All actions implement `AnAction` and `DumbAware` (functional during indexing).

**OpenPanelAction.kt:**
- Opens/focuses the Claude Code tool window
- `ToolWindowManager.getInstance(project).getToolWindow("Claude Code")?.show()`
- Keyboard shortcut: `Ctrl+Shift+.` (Windows/Linux), `Cmd+Shift+.` (macOS)

**NewConversationAction.kt:**
- Delegates to `ClaudeCodeService.getInstance(project).startNewConversation()`
- `update()`: enabled only when the tool window is open/service is connected
- Keyboard shortcut: `Ctrl+Shift+,` (Windows/Linux), `Cmd+Shift+,` (macOS)

**OpenTerminalAction.kt:**
- Delegates to `ClaudeTerminalService.getInstance(project).openClaudeInTerminal()`
- `update()`: visible only when terminal plugin is available (`PluginManagerCore.getPlugin(...)`)
- Keyboard shortcut: `Ctrl+Shift+Escape` (Windows/Linux), `Cmd+Shift+Escape` (macOS)

**SendSelectionAction.kt:**
- Gets current editor selection via `FileEditorManager.getInstance(project).selectedTextEditor`
- Sends selection text + file path to Claude via `ClaudeCodeService`
- `update()`: enabled only when there is an active selection (check `editor.selectionModel.hasSelection()`)
- Also registered in editor context menu (right-click)
- No keyboard shortcut (menu-only)

**AcceptDiffAction.kt:**
- Delegates to `ClaudeDiffService.getInstance(project).acceptCurrentDiff()`
- `update()`: enabled only when a Claude diff is currently shown (check context key)

**RejectDiffAction.kt:**
- Delegates to `ClaudeDiffService.getInstance(project).rejectCurrentDiff()`
- `update()`: enabled only when a Claude diff is currently shown

**InsertAtMentionAction.kt:**
- Sends `insert_at_mention` message to the webview
- Gets current file path and inserts as `@filename` in the Claude input
- Keyboard shortcut: `Alt+K` (all platforms)

**FocusInputAction.kt:**
- Focuses the Claude input in the tool window
- Shows the tool window if hidden, then sends `focus_input` to webview
- Keyboard shortcut: `Cmd+Escape` (macOS), `Ctrl+Escape` (Windows/Linux) -- when editor is focused

**BlurInputAction.kt:**
- Blurs the Claude input, returns focus to editor
- Keyboard shortcut: `Cmd+Escape` / `Ctrl+Escape` -- when Claude input is focused

**ShowLogsAction.kt:**
- Opens the "Claude Code" output channel/log
- `ToolWindowManager.getInstance(project).getToolWindow("Run")?.show()`

#### Code Patterns to Follow

```kotlin
// Action pattern
class OpenPanelAction : AnAction("Open Claude Code", "Open the Claude Code panel", AllIcons.Actions.Find), DumbAware {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        ToolWindowManager.getInstance(project).getToolWindow("Claude Code")?.show()
    }

    override fun update(e: AnActionEvent) {
        e.presentation.isEnabledAndVisible = e.project != null
    }

    override fun getActionUpdateThread(): ActionUpdateThread = ActionUpdateThread.BGT
}

// Selection-dependent action
class SendSelectionAction : AnAction(), DumbAware {
    override fun update(e: AnActionEvent) {
        val editor = e.getData(CommonDataKeys.EDITOR)
        e.presentation.isEnabled = editor?.selectionModel?.hasSelection() == true
    }

    override fun getActionUpdateThread(): ActionUpdateThread = ActionUpdateThread.BGT
}
```

#### Keyboard Shortcut Summary

| Action | Default Keymap | macOS Keymap |
|--------|---------------|-------------|
| Open Panel | `ctrl shift PERIOD` | `meta shift PERIOD` |
| New Conversation | `ctrl shift COMMA` | `meta shift COMMA` |
| Open Terminal | `ctrl shift ESCAPE` | `meta shift ESCAPE` |
| Insert @-mention | `alt K` | `alt K` |
| Focus Input | `ctrl ESCAPE` | `meta ESCAPE` |

#### Acceptance Criteria

- [ ] All 10 actions are registered and appear in the Tools > Claude Code menu
- [ ] "Send Selection to Claude" appears in editor right-click context menu
- [ ] Keyboard shortcuts work on macOS, Windows, and Linux
- [ ] Actions are grayed out when inappropriate (no selection, no diff, etc.)
- [ ] All actions implement `DumbAware` (work during indexing)
- [ ] `getActionUpdateThread()` returns `BGT` for all actions (no EDT checks)
- [ ] Actions compile and delegate to service stubs without crashing

#### Key References

- `06-vscode-extension-reverse-engineering.md` Appendix A -- Keybinding summary
- `00-master-implementation-plan.md` Phase 6 (lines 794-883) -- Action registration XML, status bar
- `05-editor-diff-terminal-research.md` -- Editor context access patterns

#### What NOT to Do

- Do NOT implement the service methods that actions call -- delegate to stubs
- Do NOT implement diff viewing logic (Agent-7's job)
- Do NOT implement terminal opening logic (Agent-9's job)
- Do NOT modify `plugin.xml` -- all registrations exist in Agent-0's scaffold

---

### Agent-5: Editor Integration

**Dependencies:** Agent-1 (needs process manager types for sending context)
**Estimated effort:** 2 hours
**Estimated files:** 3

#### Description

Implement editor context gathering (file path, content, selection, cursor position, language), file modification via `WriteCommandAction`, editor event listeners for selection/open/close changes, and `@`-mention file resolution.

#### Files to Implement

| File | Path (under `src/main/kotlin/com/anthropic/claudecode/editor/`) | Lines Est. |
|------|------|------------|
| ClaudeEditorService.kt | `editor/ClaudeEditorService.kt` | ~150 |
| ClaudeEditorListener.kt | `editor/ClaudeEditorListener.kt` | ~60 |
| EditorContext.kt | `editor/EditorContext.kt` | ~50 |

#### Implementation Details

**EditorContext.kt:**
- Data classes for editor state:
```kotlin
data class EditorContext(
    val filePath: String,            // Absolute path
    val fileName: String,            // File name only
    val fileExtension: String?,      // Extension without dot
    val language: String?,           // IntelliJ language ID
    val content: String,             // Full file content
    val cursorLine: Int,             // 0-based
    val cursorColumn: Int,           // 0-based
    val selection: SelectionInfo?,   // Null if no selection
    val visibleStartLine: Int,       // Visible range start
    val visibleEndLine: Int,         // Visible range end
    val lineCount: Int,
    val isModified: Boolean          // Has unsaved changes
)

data class SelectionInfo(
    val startLine: Int,
    val startColumn: Int,
    val endLine: Int,
    val endColumn: Int,
    val text: String
)

data class OpenFileInfo(
    val filePath: String,
    val fileName: String,
    val isActive: Boolean
)
```

**ClaudeEditorService.kt:**
- `@Service(Service.Level.PROJECT)`
- `gatherContext(project: Project): EditorContext?` -- reads current editor state via `ReadAction`
  - `FileEditorManager.getInstance(project).selectedTextEditor` for active editor
  - `editor.document` for content
  - `editor.caretModel.primaryCaret` for cursor position
  - `editor.selectionModel` for selection
  - `editor.scrollingModel.visibleArea` for visible range
  - `PsiDocumentManager.getInstance(project).getPsiFile(document)?.language?.id` for language
  - `FileDocumentManager.getInstance().getFile(document)?.path` for file path
- `getOpenFiles(project: Project): List<OpenFileInfo>` -- list all open editors
- `applyFileContent(project: Project, filePath: String, content: String)` -- replaces file content via `WriteCommandAction` with undo group `"claude.applyChanges"`
- `createFile(project: Project, relativePath: String, content: String)` -- creates new file via `VfsUtil.createDirectoryIfMissing` + `WriteCommandAction`
- `deleteFile(project: Project, filePath: String)` -- deletes via `WriteCommandAction`
- `openFile(project: Project, filePath: String, line: Int?, column: Int?)` -- opens file in editor, optionally navigates to position
- `resolveAtMention(project: Project, query: String): List<String>` -- fuzzy file search for `@` mentions using `FilenameIndex`
- `saveFileIfNeeded(filePath: String)` -- autosave hook (pre-tool-use)
- `getDiagnostics(project: Project, filePath: String): List<DiagnosticInfo>` -- get IDE problems for a file via `InspectionManager`

All read operations wrapped in `readAction { }` (Kotlin coroutine-compatible).
All write operations wrapped in `WriteCommandAction.writeCommandAction(project).withName("Claude: ...").withGroupId("claude.applyChanges").run { }`.

**ClaudeEditorListener.kt:**
- Implements `FileEditorManagerListener` (for file open/close events)
- Implements `SelectionListener` (for selection changes via `EditorFactory.getInstance().eventMulticaster.addSelectionListener()`)
- On selection change: debounce (200ms), then notify `ClaudeCodeService` with new selection context
- On file open/close: notify `ClaudeCodeService` with updated open files list
- Registered via `project.messageBus.connect(disposable).subscribe(FileEditorManagerListener.FILE_EDITOR_MANAGER, this)`

#### Code Patterns to Follow

```kotlin
// Context gathering (MUST use ReadAction)
suspend fun gatherContext(project: Project): EditorContext? = readAction {
    val editor = FileEditorManager.getInstance(project).selectedTextEditor ?: return@readAction null
    val document = editor.document
    val virtualFile = FileDocumentManager.getInstance().getFile(document) ?: return@readAction null
    val psiFile = PsiDocumentManager.getInstance(project).getPsiFile(document)
    val caret = editor.caretModel.primaryCaret
    val selection = editor.selectionModel

    EditorContext(
        filePath = virtualFile.path,
        fileName = virtualFile.name,
        fileExtension = virtualFile.extension,
        language = psiFile?.language?.id,
        content = document.text,
        cursorLine = caret.logicalPosition.line,
        cursorColumn = caret.logicalPosition.column,
        selection = if (selection.hasSelection()) SelectionInfo(...) else null,
        visibleStartLine = editor.xyToLogicalPosition(editor.scrollingModel.visibleArea.location).line,
        visibleEndLine = editor.xyToLogicalPosition(Point(0, editor.scrollingModel.visibleArea.y + editor.scrollingModel.visibleArea.height)).line,
        lineCount = document.lineCount,
        isModified = FileDocumentManager.getInstance().isFileModified(virtualFile)
    )
}

// File modification (MUST use WriteCommandAction on EDT)
fun applyFileContent(project: Project, filePath: String, content: String) {
    val virtualFile = LocalFileSystem.getInstance().findFileByPath(filePath) ?: return
    val document = FileDocumentManager.getInstance().getDocument(virtualFile) ?: return
    WriteCommandAction.writeCommandAction(project)
        .withName("Claude: Apply Changes")
        .withGroupId("claude.applyChanges")
        .run<RuntimeException> { document.setText(content) }
}
```

#### Acceptance Criteria

- [ ] `gatherContext()` returns accurate file path, content, selection, and cursor position
- [ ] `gatherContext()` uses `ReadAction` correctly (no threading violations)
- [ ] `applyFileContent()` modifies files with proper undo support via `WriteCommandAction`
- [ ] Undo (`Cmd+Z`) reverses Claude's changes in a single step (grouped)
- [ ] `createFile()` creates directories as needed and writes content
- [ ] `openFile()` navigates to the specified line and column
- [ ] `resolveAtMention()` returns fuzzy file matches for `@` queries
- [ ] Editor selection changes trigger debounced notifications (200ms)
- [ ] File open/close events trigger notifications
- [ ] `getDiagnostics()` returns IDE problems for a given file

#### Key References

- `05-editor-diff-terminal-research.md` Sections 1-2 -- Editor APIs, context gathering, document modification
- `06-vscode-extension-reverse-engineering.md` Section 5-6 -- Editor context gathering, file operations
- `00-master-implementation-plan.md` Phase 4 (lines 592-703) -- EditorContext data class, WriteCommandAction pattern

#### What NOT to Do

- Do NOT implement diff viewing (Agent-7's job)
- Do NOT implement the webview bridge (Agent-6's job)
- Do NOT implement process communication (Agent-1's job)
- Do NOT block the EDT in any method

---

### Agent-6: Webview Communication Bridge

**Dependencies:** Agent-1 (message types) + Agent-2 (JCEF browser instance)
**Estimated effort:** 3 hours
**Estimated files:** 3

#### Description

Build the bidirectional communication bridge between the JCEF webview and the Kotlin plugin host. Handle all 54+ webview-to-extension message types and all 14 extension-to-webview push messages. Implement the JavaScript adapter that replaces `acquireVsCodeApi()` for the IntelliJ environment.

#### Files to Implement

| File | Path | Lines Est. |
|------|------|------------|
| WebviewBridge.kt | `src/main/kotlin/com/anthropic/claudecode/webview/WebviewBridge.kt` | ~250 |
| WebviewAdapter.js | `src/main/resources/webview/bridge-adapter.js` | ~80 |
| WebviewMessageRouter.kt | `src/main/kotlin/com/anthropic/claudecode/webview/WebviewMessageRouter.kt` | ~150 |

#### Implementation Details

**WebviewBridge.kt:**
- Creates `JBCefJSQuery` from the `JBCefBrowser` instance
- Injects the bridge JavaScript on page load via `CefLoadHandler.onLoadEnd()`
- Handles incoming messages from JS via `jsQuery.addHandler { rawMessage -> ... }`
- Routes messages to `WebviewMessageRouter` for dispatch
- Provides `postMessageToWebview(type: String, payload: JsonObject)` for Kotlin-to-JS
- Kotlin-to-JS delivery: `browser.cefBrowser.executeJavaScript("window.dispatchEvent(new MessageEvent('message', {data: ${jsonEscaped}}))", url, 0)`

Bridge injection script (injected on every page load):
```javascript
(function() {
    // Create the bridge query function
    var queryFunction = ${jsQuery.inject("message",
        "function(response) { window.__bridgeResolve && window.__bridgeResolve(response); }",
        "function(code, msg) { window.__bridgeReject && window.__bridgeReject(new Error(msg)); }"
    )};

    // Replace acquireVsCodeApi
    window.acquireVsCodeApi = function() {
        return {
            postMessage: function(msg) {
                var json = JSON.stringify(msg);
                return new Promise(function(resolve, reject) {
                    window.__bridgeResolve = function(resp) {
                        resolve(resp ? JSON.parse(resp) : undefined);
                    };
                    window.__bridgeReject = reject;
                    queryFunction(json);
                });
            },
            getState: function() { return window.__vsCodeState || {}; },
            setState: function(s) { window.__vsCodeState = s; }
        };
    };

    // Signal that bridge is ready
    window.dispatchEvent(new Event('hostBridgeReady'));
})();
```

**WebviewMessageRouter.kt:**
- Routes webview messages by `type` field to appropriate handlers
- Large `when` expression mapping all 54+ message types to handler functions
- Categories:
  - **Session management:** `init`, `launch_claude`, `close_channel`, `interrupt_claude`
  - **IO:** `io_message`, `cancel_request`
  - **State queries:** `get_claude_state`, `get_auth_status`, `get_current_selection`, `get_terminal_contents`, `get_session_request`, `list_sessions_request`, `list_files_request`
  - **Configuration:** `set_model`, `set_permission_mode`, `set_thinking_level`, `open_config`, `open_config_file`
  - **Editor actions:** `open_file`, `open_diff`, `open_file_diffs`, `open_content`
  - **UI actions:** `open_url`, `open_help`, `open_output_panel`, `open_terminal`, `open_claude_in_terminal`, `show_notification`, `rename_tab`, `new_conversation_tab`
  - **MCP:** `get_mcp_servers`, `set_mcp_server_enabled`, `reconnect_mcp_server`, `ensure_chrome_mcp_enabled`, `disable_chrome_mcp`, `enable_jupyter_mcp`, `disable_jupyter_mcp`
  - **Misc:** `log_event`, `exec`, `dismiss_onboarding`, `dismiss_terminal_banner`, `request_usage_update`, `fork_conversation`, `rewind_code`
- Each handler returns `JsonObject?` as the response (null = no response)

**WebviewAdapter.js (bridge-adapter.js):**
- Loaded before `index.js` in the HTML wrapper
- Provides `window.__applyIdeTheme(themeJson)` function that sets CSS variables on `document.documentElement`
- Provides `window.__handleHostMessage(json)` function that the bridge calls
- Detects environment: checks for `window.acquireVsCodeApi` (will be overridden by bridge injection)
- Theme application: iterates over theme JSON keys, sets `document.documentElement.style.setProperty('--vscode-' + key, value)`

#### Message Flow

```
JS (webview)                        Kotlin (plugin host)
-----------                        -------------------
acquireVsCodeApi().postMessage(msg)
    |
    v
JSON.stringify(msg) --> JBCefJSQuery --> WebviewBridge.handleIncoming(raw)
                                             |
                                             v
                                        WebviewMessageRouter.route(type, payload)
                                             |
                                             v
                                        handler returns JsonObject response
                                             |
                                             v
                                        JBCefJSQuery.Response(json) --> Promise resolves in JS
```

```
Kotlin (push)                       JS (webview)
-------------                       -----------
WebviewBridge.postMessageToWebview(type, payload)
    |
    v
executeJavaScript("window.dispatchEvent(new MessageEvent('message', {data: ...}))")
    |                                    |
    v                                    v
browser executes JS              window.addEventListener('message', handler)
                                        |
                                        v
                                  React app processes the message
```

#### Acceptance Criteria

- [ ] `acquireVsCodeApi()` is shimmed correctly -- React app calls `postMessage()` and receives responses
- [ ] All 54 webview->extension message types are routed to handler functions
- [ ] All 14 extension->webview push messages are delivered via `executeJavaScript()`
- [ ] Request-response correlation works: webview sends request, receives response via Promise
- [ ] `init` message returns correct initial state (cwd, auth, config, theme)
- [ ] `launch_claude` message triggers session creation (delegates to service)
- [ ] `io_message` forward works in both directions (webview -> CLI, CLI -> webview)
- [ ] `open_file` message opens the file in the IDE editor
- [ ] `show_notification` message shows an IntelliJ notification balloon
- [ ] Streaming output updates are batched (uses `BatchedWebviewUpdater` from Agent-2)
- [ ] No EDT violations in message handling

#### Key References

- `06-vscode-extension-reverse-engineering.md` Section 4 (Webview Communication Bridge) -- Message patterns
- `06-vscode-extension-reverse-engineering.md` Section 14 (All Message Types) -- Complete type tables
- `06-vscode-extension-reverse-engineering.md` Section 15.2 (Communication Bridge Design) -- IntelliJ bridge pattern
- `02-jcef-webview-research.md` -- JBCefJSQuery API, executeJavaScript patterns
- `00-master-implementation-plan.md` Phase 3 (lines 486-523) -- Bridge injection, message envelope format

#### What NOT to Do

- Do NOT implement the actual business logic for each message handler -- delegate to service stubs
- Do NOT modify the React webview source code (`index.js`)
- Do NOT implement process spawning or management (Agent-1's job)
- Do NOT implement theme synchronization (Agent-2's job)
- Do NOT block in `JBCefJSQuery` handlers -- return immediately, do async work in coroutines

---

### Agent-7: Diff Service & File Change Review

**Dependencies:** Agent-1 (process types) + Agent-5 available (editor service for applying changes)
**Estimated effort:** 2 hours
**Estimated files:** 3

#### Description

Implement the diff viewing system for Claude's proposed file changes. Use IntelliJ's native `DiffManager` with `SimpleDiffRequest` for single-file diffs and `DiffRequestChain` for multi-file changes. Provide accept/reject workflow with full undo support.

#### Files to Implement

| File | Path (under `src/main/kotlin/com/anthropic/claudecode/editor/`) | Lines Est. |
|------|------|------------|
| ClaudeDiffService.kt | `editor/ClaudeDiffService.kt` | ~180 |
| DiffActionGroup.kt | `editor/DiffActionGroup.kt` | ~60 |
| PendingDiff.kt | `editor/PendingDiff.kt` | ~30 |

#### Implementation Details

**PendingDiff.kt:**
```kotlin
data class PendingDiff(
    val filePath: String,
    val originalContent: String,
    val proposedContent: String,
    val channelId: String,              // Which Claude session proposed this
    val requestId: String?,             // For response correlation
    val edits: List<EditOperation>?     // Optional structured edits
)

data class EditOperation(
    val startLine: Int,
    val endLine: Int,
    val newText: String
)
```

**ClaudeDiffService.kt:**
- `@Service(Service.Level.PROJECT)`
- Maintains `ConcurrentHashMap<String, PendingDiff>` of pending diffs keyed by filePath
- `showDiff(project, pendingDiff)`:
  - Creates `DiffContentFactory.getInstance()` contents with file-type-aware syntax highlighting
  - `val fileType = FileTypeManager.getInstance().getFileTypeByFileName(filePath)`
  - `val original = contentFactory.create(project, originalContent, fileType)`
  - `val proposed = contentFactory.create(project, proposedContent, fileType)`
  - Builds `SimpleDiffRequest("Claude: Proposed Changes to ${fileName}", original, proposed, "Current", "Proposed by Claude")`
  - Calls `DiffManager.getInstance().showDiff(project, request)`
  - Stores in `pendingDiffs` map
- `showMultiFileDiff(project, diffs: List<PendingDiff>)`:
  - Creates `DiffRequestChain` from list of `SimpleDiffRequest`
  - Shows all diffs in sequence
- `acceptDiff(project, filePath)`:
  - Retrieves `PendingDiff` from map
  - Applies `proposedContent` via `ClaudeEditorService.applyFileContent()`
  - Removes from `pendingDiffs`
  - Sends acceptance response back to Claude (via callback/coroutine)
- `rejectDiff(project, filePath)`:
  - Removes `PendingDiff` from map
  - Sends rejection response back to Claude
  - Closes the diff tab
- `acceptCurrentDiff(project)` / `rejectCurrentDiff(project)`:
  - Determines which diff is currently shown (from active editor)
  - Delegates to `acceptDiff()` / `rejectDiff()`
- `acceptAllDiffs(project)`:
  - Accepts all pending diffs in order
- `hasPendingDiffs(): Boolean`
- `getPendingDiffForFile(filePath: String): PendingDiff?`

**DiffActionGroup.kt:**
- Custom toolbar actions added to the diff viewer
- Accept button: applies proposed changes
- Reject button: discards proposed changes
- Accept All button: accepts all pending diffs
- Uses `ActionManager.getInstance().getAction(...)` to register inline diff actions

#### Code Patterns to Follow

```kotlin
// Single file diff
fun showDiff(project: Project, diff: PendingDiff) {
    val contentFactory = DiffContentFactory.getInstance()
    val fileType = FileTypeManager.getInstance().getFileTypeByFileName(diff.filePath)

    val request = SimpleDiffRequest(
        "Claude: Proposed Changes to ${diff.filePath.substringAfterLast('/')}",
        contentFactory.create(project, diff.originalContent, fileType),
        contentFactory.create(project, diff.proposedContent, fileType),
        "Current",
        "Proposed by Claude"
    )

    // Add accept/reject actions to the diff request
    request.putUserData(CLAUDE_DIFF_KEY, diff)

    invokeLater {
        DiffManager.getInstance().showDiff(project, request)
    }
    pendingDiffs[diff.filePath] = diff
}

// Accept
fun acceptDiff(project: Project, filePath: String) {
    val diff = pendingDiffs.remove(filePath) ?: return
    project.service<ClaudeEditorService>().applyFileContent(project, filePath, diff.proposedContent)
}

// Multi-file diff
fun showMultiFileDiff(project: Project, diffs: List<PendingDiff>) {
    val requests = diffs.map { diff ->
        val fileType = FileTypeManager.getInstance().getFileTypeByFileName(diff.filePath)
        SimpleDiffRequest(
            diff.filePath.substringAfterLast('/'),
            DiffContentFactory.getInstance().create(project, diff.originalContent, fileType),
            DiffContentFactory.getInstance().create(project, diff.proposedContent, fileType),
            "Current", "Proposed"
        ).also { it.putUserData(CLAUDE_DIFF_KEY, diff) }
    }
    val chain = SimpleDiffRequestChain(requests)
    invokeLater { DiffManager.getInstance().showDiff(project, chain) }
}
```

#### Acceptance Criteria

- [ ] Single-file diff opens in IntelliJ's native diff viewer
- [ ] Diff viewer shows syntax highlighting appropriate to the file type
- [ ] Left side shows "Current" content, right side shows "Proposed by Claude"
- [ ] Accept applies proposed content via `WriteCommandAction` (undoable)
- [ ] Reject discards changes and closes the diff tab
- [ ] Multi-file diffs work via `DiffRequestChain` (navigate between files)
- [ ] Accept All applies all pending changes
- [ ] Undo (`Cmd+Z`/`Ctrl+Z`) reverses accepted changes in one step
- [ ] Pending diffs are tracked and queryable
- [ ] Diff service is properly disposed (no leaked references)

#### Key References

- `05-editor-diff-terminal-research.md` Sections 3-4 -- DiffManager, SimpleDiffRequest, DiffRequestChain, accept/reject patterns
- `06-vscode-extension-reverse-engineering.md` Section 7 -- Diff & proposed changes patterns from VSCode
- `00-master-implementation-plan.md` Phase 4 (lines 657-703) -- Diff view creation, undo integration

#### What NOT to Do

- Do NOT implement the webview message handling for `open_diff` -- Agent-6 routes it, this service provides the implementation
- Do NOT implement file modification logic -- delegate to `ClaudeEditorService` (Agent-5)
- Do NOT create a custom diff UI -- use IntelliJ's built-in `DiffManager`

---

### Agent-8: Main Service Orchestrator

**Dependencies:** Agent-1 (process), Agent-2 (JCEF), Agent-3 (settings), Agent-5 (editor), Agent-6 (bridge)
**Estimated effort:** 3 hours
**Estimated files:** 5

#### Description

Implement the central `ClaudeCodeService` that ties everything together. This is the main orchestrator: it manages channels (multiple concurrent Claude sessions), coordinates between the process manager, webview bridge, editor service, and settings. It also implements the startup activity, project close listener, and status bar widget.

#### Files to Implement

| File | Path (under `src/main/kotlin/com/anthropic/claudecode/`) | Lines Est. |
|------|------|------------|
| ClaudeCodeService.kt | `services/ClaudeCodeService.kt` | ~300 |
| ClaudeStartupActivity.kt | `listeners/ClaudeStartupActivity.kt` | ~40 |
| ProjectCloseListener.kt | `listeners/ProjectCloseListener.kt` | ~30 |
| ClaudeStatusBarWidgetFactory.kt | `ui/ClaudeStatusBarWidgetFactory.kt` | ~30 |
| ClaudeStatusBarWidget.kt | `ui/ClaudeStatusBarWidget.kt` | ~80 |

#### Implementation Details

**ClaudeCodeService.kt:**
- `@Service(Service.Level.PROJECT)`
- Constructor: `(private val project: Project, private val cs: CoroutineScope)`
- Implements `Disposable`

**Channel management:**
```kotlin
data class ClaudeChannel(
    val channelId: String,
    val processManager: ClaudeProcessManager,
    val protocolHandler: JsonProtocolHandler,
    val mcpServers: Map<String, Any> = emptyMap()
)

private val channels = ConcurrentHashMap<String, ClaudeChannel>()
```

**State machine:**
```kotlin
enum class ServiceState { DISCONNECTED, CONNECTING, CONNECTED, ERROR }
private val _state = MutableStateFlow(ServiceState.DISCONNECTED)
val state: StateFlow<ServiceState> = _state.asStateFlow()
```

**Core methods:**
- `startNewConversation(cwd: String? = null, resume: String? = null, model: String? = null, permissionMode: String? = null)`:
  - Generates `channelId = UUID.randomUUID().toString()`
  - Creates `ClaudeProcessManager` with settings and env vars
  - Starts process, creates `JsonProtocolHandler`
  - Registers channel
  - Starts forwarding CLI output to webview via `WebviewBridge.postMessageToWebview("io_message", ...)`
  - Updates state to `CONNECTED`

- `closeChannel(channelId: String)`:
  - Stops the process
  - Removes channel from map
  - Notifies webview via `close_channel` message

- `interruptChannel(channelId: String)`:
  - Sends `interrupt` control message to CLI via stdin

- `sendToChannel(channelId: String, message: JsonObject)`:
  - Forwards message to the channel's `JsonProtocolHandler`

- `handleInit(): JsonObject`:
  - Returns the `init_response` state object the webview needs:
    - `defaultCwd` = project base path
    - `openNewInTab` = settings value
    - `authStatus` = from CLI query
    - `modelSetting` = settings value
    - `thinkingLevel` = settings value
    - `initialPermissionMode` = settings value
    - `allowDangerouslySkipPermissions` = settings value
    - `platform` = `SystemInfo` detection
    - etc.

- `handleSettingsChange(oldState, newState)`:
  - Implements `ClaudeCodeSettingsListener`
  - Propagates setting changes to active channels (e.g., model change sends `set_model` to CLI)

- `forwardCliOutput(channelId: String)`:
  - Collects from `protocolHandler.messages` flow
  - Forwards to webview as `io_message` push messages
  - Handles `tool_use` messages: calls pre/post tool hooks
  - Handles `auth_status` messages: updates auth state

**Pre/Post Tool Hooks (from VSCode pattern):**
- PreToolUse: `Edit|Write|Read` -> `ClaudeEditorService.saveFileIfNeeded(filePath)`
- PostToolUse: `Edit|Write|MultiEdit` -> `ClaudeEditorService.getDiagnostics(filePath)` then feed back to CLI

**ClaudeStartupActivity.kt:**
- Implements `ProjectActivity` (coroutine-based)
- `execute(project: Project)`: initializes `ClaudeCodeService` (triggers lazy service creation)
- Does NOT auto-start a Claude session -- just ensures the service is ready

**ProjectCloseListener.kt:**
- Implements `ProjectCloseListener`
- `projectClosing(project)`: calls `ClaudeCodeService.getInstance(project).dispose()`
- Ensures all channels are stopped and processes terminated

**ClaudeStatusBarWidgetFactory.kt:**
- Implements `StatusBarWidgetFactory`
- `getId()` returns `"ClaudeStatusWidget"`
- `getDisplayName()` returns `"Claude Code"`
- `createWidget(project)` returns `ClaudeStatusBarWidget(project)`

**ClaudeStatusBarWidget.kt:**
- Implements `StatusBarWidget.TextPresentation`
- Observes `ClaudeCodeService.state` flow
- Displays based on state:
  - `DISCONNECTED`: gray icon, "Claude: Disconnected"
  - `CONNECTING`: spinner, "Claude: Connecting..."
  - `CONNECTED`: green icon, "Claude: Connected"
  - `ERROR`: red icon, "Claude: Error" with tooltip showing error details
- Click handler: opens the Claude Code tool window
- Right-click: popup menu with Restart, Stop, Settings options
- Updates via `myStatusBar?.updateWidget(ID)` when state changes

#### Acceptance Criteria

- [ ] Service initializes on project open (via startup activity)
- [ ] `startNewConversation()` creates a channel, spawns CLI, connects webview
- [ ] Multiple concurrent channels are supported
- [ ] CLI output forwards to webview in real-time
- [ ] Webview input forwards to CLI via stdin
- [ ] `interruptChannel()` sends interrupt signal to CLI
- [ ] `closeChannel()` stops process and notifies webview
- [ ] State machine transitions correctly: DISCONNECTED -> CONNECTING -> CONNECTED
- [ ] Status bar widget shows current state
- [ ] Status bar click opens tool window; right-click shows menu
- [ ] Settings changes propagate to active channels
- [ ] Pre-tool-use hooks save files before CLI reads/writes them
- [ ] Post-tool-use hooks send IDE diagnostics back to CLI
- [ ] Clean shutdown on project close (all processes terminated)

#### Key References

- `00-master-implementation-plan.md` Phases 2, 3, 6 -- Service architecture, state machine, status bar
- `06-vscode-extension-reverse-engineering.md` Section 15.6-15.7 -- Channel architecture, init state shape
- `06-vscode-extension-reverse-engineering.md` Section 15.8 -- Hooks system
- `04-process-management-research.md` -- Process lifecycle, coroutine scope

#### What NOT to Do

- Do NOT re-implement process management -- use `ClaudeProcessManager` from Agent-1
- Do NOT re-implement webview communication -- use `WebviewBridge` from Agent-6
- Do NOT re-implement settings -- use `ClaudeCodeSettings` from Agent-3
- Do NOT re-implement editor context -- use `ClaudeEditorService` from Agent-5

---

### Agent-9: Terminal Integration & MCP

**Dependencies:** Agent-1 (needs process manager for binary resolution)
**Estimated effort:** 2 hours
**Estimated files:** 3

#### Description

Implement terminal mode (launching Claude CLI in an IntelliJ terminal tab) and the MCP server that provides IDE tools to the Claude CLI.

#### Files to Implement

| File | Path (under `src/main/kotlin/com/anthropic/claudecode/`) | Lines Est. |
|------|------|------------|
| ClaudeTerminalService.kt | `terminal/ClaudeTerminalService.kt` | ~80 |
| ClaudeMcpServer.kt | `mcp/ClaudeMcpServer.kt` | ~200 |
| McpLockFile.kt | `mcp/McpLockFile.kt` | ~50 |

#### Implementation Details

**ClaudeTerminalService.kt:**
- `@Service(Service.Level.PROJECT)`
- `openClaudeInTerminal()`:
  - Resolves binary via `ClaudeBinaryResolver`
  - Gets `TerminalView.getInstance(project)` (requires terminal plugin)
  - Creates shell widget: `terminalView.createLocalShellWidget(project.basePath, "Claude Code", true)`
  - Executes command: `widget.executeCommand(binaryPath + " --ide")`
- Uses optional dependency pattern: class is only loaded when terminal plugin is present
- `isTerminalAvailable(): Boolean` -- checks if terminal plugin is installed

**ClaudeMcpServer.kt:**
- Provides IDE tools to the Claude CLI via MCP protocol
- Creates a WebSocket server on a random available port
- Registers MCP tools:

| Tool Name | Description | IntelliJ API |
|-----------|-------------|-------------|
| `getCurrentSelection` | Get editor selection text | `ClaudeEditorService.gatherContext()` |
| `getLatestSelection` | Get most recent selection | Same, cached |
| `getOpenEditors` | List open editor tabs | `FileEditorManager.getOpenFiles()` |
| `getWorkspaceFolders` | List workspace roots | `ProjectRootManager.getContentRoots()` |
| `getDiagnostics` | Get IDE errors/warnings | `InspectionManager` |
| `openFile` | Open file in editor | `ClaudeEditorService.openFile()` |
| `openDiff` | Show diff viewer | `ClaudeDiffService.showDiff()` |
| `closeAllDiffTabs` | Close diff editors | `FileEditorManager.closeFile()` |
| `checkDocumentDirty` | Check for unsaved changes | `FileDocumentManager.isFileModified()` |
| `saveDocument` | Save a file | `FileDocumentManager.saveDocument()` |

- MCP message handling via JSON-RPC 2.0 over WebSocket
- Server starts when a channel is created, stops when last channel closes

**McpLockFile.kt:**
- Writes lock file to `~/.claude/ide/{hash}.json` with:
  - `pid`: current process PID
  - `workspaceFolders`: list of project content roots
  - `ideName`: "IntelliJ IDEA" / "PyCharm" / etc. (from `ApplicationInfo.getInstance().fullProductName`)
  - `transport`: "ws"
  - `port`: WebSocket server port
  - `authToken`: random UUID for authentication
- Lock file is deleted on service dispose
- File name hash is based on the project path

#### Code Patterns to Follow

```kotlin
// Terminal integration (with optional dependency guard)
class ClaudeTerminalService(private val project: Project) {
    fun openClaudeInTerminal() {
        val binary = ClaudeBinaryResolver.resolve(ClaudeCodeSettings.getInstance(project))
        try {
            val terminalView = TerminalView.getInstance(project)
            val widget = terminalView.createLocalShellWidget(
                project.basePath ?: System.getProperty("user.home"),
                "Claude Code",
                true
            )
            widget.executeCommand("${binary.executablePath} ${binary.args.joinToString(" ")} --ide")
        } catch (e: Exception) {
            // Terminal plugin not available
            NotificationGroupManager.getInstance()
                .getNotificationGroup("Claude Code Notifications")
                .createNotification("Terminal plugin not available", NotificationType.WARNING)
                .notify(project)
        }
    }
}

// MCP lock file
fun writeLockFile(port: Int, authToken: String) {
    val lockDir = Path.of(System.getProperty("user.home"), ".claude", "ide")
    Files.createDirectories(lockDir)
    val hash = project.basePath?.hashCode()?.toString(16) ?: "default"
    val lockFile = lockDir.resolve("$hash.json")
    val data = buildJsonObject {
        put("pid", ProcessHandle.current().pid())
        put("ideName", ApplicationInfo.getInstance().fullProductName)
        put("transport", "ws")
        put("port", port)
        put("authToken", authToken)
        putJsonArray("workspaceFolders") {
            ProjectRootManager.getInstance(project).contentRoots.forEach { add(it.path) }
        }
    }
    Files.writeString(lockFile, Json.encodeToString(data))
}
```

#### Acceptance Criteria

- [ ] "Open Claude in Terminal" creates a terminal tab running the Claude CLI
- [ ] Terminal tab has the title "Claude Code"
- [ ] `useTerminal=true` setting causes tool window to open terminal instead of webview
- [ ] Plugin works correctly when terminal plugin is NOT installed (graceful degradation)
- [ ] MCP WebSocket server starts on a random port
- [ ] Lock file is written to `~/.claude/ide/` with correct fields
- [ ] MCP tools respond correctly to tool calls from the CLI
- [ ] `getCurrentSelection` returns current editor selection
- [ ] `getDiagnostics` returns IDE errors/warnings
- [ ] `openFile` opens the requested file in the editor
- [ ] Lock file is cleaned up on service dispose

#### Key References

- `05-editor-diff-terminal-research.md` Section 11 -- Terminal API, `TerminalView`, `ShellTerminalWidget`
- `06-vscode-extension-reverse-engineering.md` Section 8 (Terminal Mode), Section 13 (MCP Server)
- `00-master-implementation-plan.md` Phase 7 (lines 886-931) -- Terminal integration, optional dependency

#### What NOT to Do

- Do NOT implement the full MCP protocol parser -- use a library or minimal implementation
- Do NOT implement Chrome/Jupyter MCP (scope creep -- these are extensions of the base MCP)
- Do NOT create a custom terminal emulator -- use IntelliJ's built-in terminal
- Do NOT make the terminal plugin a required dependency -- it must be optional

---

### Agent-10: Testing & Verification

**Dependencies:** All agents (run last)
**Estimated effort:** 3 hours
**Estimated files:** 8-10

#### Description

Write unit tests for all major components, create the CI/CD pipeline, and verify the plugin across multiple IDE versions.

#### Files to Create

| File | Path (under `src/test/kotlin/com/anthropic/claudecode/`) | Lines Est. |
|------|------|------------|
| ClaudeCodeServiceTest.kt | `services/ClaudeCodeServiceTest.kt` | ~100 |
| ClaudeBinaryResolverTest.kt | `process/ClaudeBinaryResolverTest.kt` | ~80 |
| JsonProtocolHandlerTest.kt | `process/JsonProtocolHandlerTest.kt` | ~120 |
| WebviewBridgeTest.kt | `webview/WebviewBridgeTest.kt` | ~80 |
| WebviewMessageRouterTest.kt | `webview/WebviewMessageRouterTest.kt` | ~100 |
| ClaudeEditorServiceTest.kt | `editor/ClaudeEditorServiceTest.kt` | ~80 |
| ClaudeDiffServiceTest.kt | `editor/ClaudeDiffServiceTest.kt` | ~60 |
| ClaudeCodeSettingsTest.kt | `settings/ClaudeCodeSettingsTest.kt` | ~60 |
| build.yml | `.github/workflows/build.yml` | ~80 |

#### Implementation Details

**Test Patterns:**

Use `BasePlatformTestCase` for tests needing IDE project context:
```kotlin
class ClaudeBinaryResolverTest : BasePlatformTestCase() {
    fun testResolvesFromSettings() {
        // Setup settings with a known path
        val settings = ClaudeCodeSettings()
        settings.loadState(ClaudeCodeSettings.State(claudeBinaryPath = "/usr/local/bin/claude"))
        val result = ClaudeBinaryResolver.resolve(settings)
        assertEquals("/usr/local/bin/claude", result.executablePath)
    }

    fun testThrowsWhenBinaryNotFound() {
        val settings = ClaudeCodeSettings()
        settings.loadState(ClaudeCodeSettings.State(claudeBinaryPath = "/nonexistent/path"))
        assertThrows(ClaudeBinaryNotFoundException::class.java) {
            ClaudeBinaryResolver.resolve(settings)
        }
    }
}
```

Use `runBlocking` for coroutine tests:
```kotlin
class JsonProtocolHandlerTest : BasePlatformTestCase() {
    fun testSendAndReceive() = runBlocking {
        val (input, output) = createMockProcess()
        val handler = JsonProtocolHandler(mockProcess, this)
        handler.start()

        val response = handler.sendAndReceive(
            buildJsonObject { put("type", "test"); put("requestId", "123") },
            requestId = "123",
            timeout = 5000
        )
        assertEquals("test_response", response["type"]?.jsonPrimitive?.content)
    }
}
```

**Test Coverage Targets:**

| Component | Tests | Focus |
|-----------|-------|-------|
| ClaudeBinaryResolver | 4 tests | Settings path, bundled path, system PATH, not-found error |
| JsonProtocolHandler | 5 tests | Send, receive, sendAndReceive, timeout, malformed JSON |
| WebviewBridge | 3 tests | Message routing, response correlation, error handling |
| WebviewMessageRouter | 6 tests | One per message category (session, IO, config, editor, UI, MCP) |
| ClaudeEditorService | 4 tests | Context gathering, file modification, file creation, at-mention resolution |
| ClaudeDiffService | 3 tests | Show diff, accept, reject |
| ClaudeCodeSettings | 3 tests | Default values, persistence, change notification |
| ClaudeCodeService | 4 tests | Channel create, channel close, state transitions, init response |

**CI/CD Pipeline (`.github/workflows/build.yml`):**

```yaml
name: Build & Verify
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '21'
      - uses: gradle/actions/setup-gradle@v4
      - run: ./gradlew buildPlugin
      - run: ./gradlew test
      - run: ./gradlew verifyPluginConfiguration
      - run: ./gradlew verifyPlugin
      - uses: actions/upload-artifact@v4
        with:
          name: plugin-zip
          path: build/distributions/*.zip
```

#### Acceptance Criteria

- [ ] All unit tests pass: `./gradlew test`
- [ ] Plugin verification passes: `./gradlew verifyPlugin`
- [ ] Plugin configuration verification passes: `./gradlew verifyPluginConfiguration`
- [ ] Plugin builds successfully: `./gradlew buildPlugin`
- [ ] Plugin ZIP installs in a clean IntelliJ IDEA
- [ ] Plugin loads in IntelliJ IDEA, PyCharm, and WebStorm without errors
- [ ] No EDT thread violations (check via `ThreadingAssertions` in tests)
- [ ] CI pipeline runs all checks on push and PR
- [ ] Test coverage: at least 1 test per major component

#### Key References

- `03-gradle-project-setup.md` -- Testing patterns, `BasePlatformTestCase`, CI/CD pipeline
- `00-master-implementation-plan.md` Phase 8 (lines 934-1028) -- Testing, packaging, verification

#### What NOT to Do

- Do NOT write integration tests that require a running Claude CLI
- Do NOT write UI tests (Swing/JCEF testing is fragile and out of scope)
- Do NOT submit to the JetBrains Marketplace (separate task)
- Do NOT modify implementation files -- only add test files

---

## Agent Prompt Templates

Each agent should be given a prompt following this template. Replace the placeholders with the specific agent's details.

### Template

```
You are implementing Agent-{N}: {Task Name} for the Claude Code IntelliJ plugin.

## Context
Read these reference documents before starting:
{list of reference docs with specific line ranges}

## Your Files
You own these files exclusively. No other agent will modify them:
{list of exact file paths}

## Dependencies You Can Use
These files are implemented by other agents. Code against their interfaces:
{list of dependency files and their key interfaces}

## What to Implement
{Detailed description from the task definition above}

## Code Patterns
Follow these specific patterns:
{Copy relevant patterns from the task definition}

## Acceptance Criteria
{Copy from task definition}

## Constraints
- Do NOT modify files outside your ownership list
- Do NOT modify plugin.xml (owned by Agent-0)
- Do NOT implement business logic that belongs to other agents
- Use TODO() for any code that depends on not-yet-implemented services
- All code must compile with `./gradlew build`
- Follow IntelliJ Platform threading rules (no EDT blocking)
```

---

### Agent-0 Prompt

```
You are implementing Agent-0: Project Scaffold & Build System for the Claude Code IntelliJ plugin.

## Context
Read these reference documents:
- .context/plans/intellij-port/03-gradle-project-setup.md (FULL - build system setup)
- .context/plans/intellij-port/00-master-implementation-plan.md lines 1-200 (architecture)
- .context/plans/intellij-port/00-master-implementation-plan.md lines 1031-1149 (file structure)

## Your Task
Create the complete Gradle project structure with all build files, plugin.xml with ALL
extension point registrations, and compilable Kotlin stub classes for every file in the
target structure. Stubs must have correct class signatures, interface implementations,
and TODO() method bodies. The project must compile with `./gradlew build`.

## Files to Create
- claude-code-intellij/settings.gradle.kts
- claude-code-intellij/build.gradle.kts
- claude-code-intellij/gradle.properties
- claude-code-intellij/gradle/libs.versions.toml
- claude-code-intellij/gradle/wrapper/gradle-wrapper.properties
- src/main/resources/META-INF/plugin.xml (COMPLETE with all registrations)
- src/main/resources/META-INF/terminal-support.xml
- src/main/resources/META-INF/pluginIcon.svg
- src/main/resources/META-INF/pluginIcon_dark.svg
- src/main/resources/icons/claude-toolwindow.svg
- src/main/resources/icons/claude-action.svg
- src/main/resources/webview/index.html
- All ~30 Kotlin stub files (see master plan file structure)
- .run/Run IDE with Plugin.run.xml

## Key Requirement
Every stub must be a COMPILABLE Kotlin class with:
1. Correct package declaration
2. Correct interface implementation (ToolWindowFactory, AnAction, PersistentStateComponent, etc.)
3. Method signatures matching the interface contract
4. TODO("Implemented by Agent-N") as method bodies
5. Proper imports

## Acceptance
- ./gradlew build succeeds
- ./gradlew runIde launches sandbox IDE
- Plugin shows in plugin list
- All packages exist

## Constraints
- Do NOT implement any business logic
- Do NOT add test files
- Do NOT add CI/CD pipeline
- Copy webview/index.js and webview/index.css from the VSCode extension as-is
```

---

### Agent-1 Prompt

```
You are implementing Agent-1: Process Management & JSON Protocol for the Claude Code IntelliJ plugin.

## Context
Read these reference documents:
- .context/plans/intellij-port/04-process-management-research.md (FULL)
- .context/plans/intellij-port/06-vscode-extension-reverse-engineering.md Sections 1-2, 14
- .context/plans/intellij-port/00-master-implementation-plan.md lines 290-418

## Your Files (replace TODO stub bodies)
- src/main/kotlin/com/anthropic/claudecode/process/ClaudeBinaryResolver.kt
- src/main/kotlin/com/anthropic/claudecode/process/ClaudeProcessManager.kt
- src/main/kotlin/com/anthropic/claudecode/process/JsonProtocolHandler.kt
- src/main/kotlin/com/anthropic/claudecode/process/StderrCollector.kt
- src/main/kotlin/com/anthropic/claudecode/process/ClaudeErrorHandler.kt
- src/main/kotlin/com/anthropic/claudecode/protocol/Messages.kt
- src/main/kotlin/com/anthropic/claudecode/protocol/CliMessages.kt

## Dependencies
- ClaudeCodeSettings (Agent-3) - use the stub interface to read settings
- No webview dependency

## Key Patterns
- GeneralCommandLine with ParentEnvironmentType.CONSOLE
- KillableProcessHandler with setShouldDestroyProcessRecursively(true)
- BufferedReader.readLine() for NDJSON on Dispatchers.IO
- ConcurrentHashMap<String, CompletableDeferred<JsonObject>> for request correlation
- StateFlow<ProcessState> for lifecycle state
- Exponential backoff: 1s, 2s, 4s, 8s, 16s cap, max 5 restarts

## Constraints
- Do NOT implement webview bridge logic
- Do NOT implement the main service orchestrator
- Do NOT block the EDT
- All I/O on Dispatchers.IO
```

---

### Agent-2 Prompt

```
You are implementing Agent-2: JCEF Webview Core for the Claude Code IntelliJ plugin.

## Context
Read these reference documents:
- .context/plans/intellij-port/02-jcef-webview-research.md (FULL)
- .context/plans/intellij-port/06-vscode-extension-reverse-engineering.md Section 3, 11, Appendix D
- .context/plans/intellij-port/00-master-implementation-plan.md lines 421-589

## Your Files (replace TODO stub bodies)
- src/main/kotlin/com/anthropic/claudecode/toolwindow/ClaudeCodeToolWindowFactory.kt
- src/main/kotlin/com/anthropic/claudecode/webview/LocalResourceSchemeHandler.kt
- src/main/kotlin/com/anthropic/claudecode/webview/JcefSchemeRegistrar.kt
- src/main/kotlin/com/anthropic/claudecode/webview/ThemeSynchronizer.kt
- src/main/kotlin/com/anthropic/claudecode/webview/WebviewHtmlGenerator.kt
- src/main/kotlin/com/anthropic/claudecode/webview/BatchedWebviewUpdater.kt

## Key Patterns
- JBCefBrowser loaded into ToolWindow component
- Custom CefSchemeHandlerFactory for claude://app/ scheme
- UIManager.getColor() mapped to --vscode-* CSS variables
- LafManagerListener.TOPIC for theme change detection
- SingleAlarm(::flush, 16, disposable) for 60fps batched updates

## Constraints
- Do NOT implement the communication bridge (JBCefJSQuery) - Agent-6's job
- Do NOT implement message routing
- Do NOT modify index.js or index.css
```

---

### Agent-3 Prompt

```
You are implementing Agent-3: Settings & Configuration for the Claude Code IntelliJ plugin.

## Context
Read these reference documents:
- .context/plans/intellij-port/00-master-implementation-plan.md lines 706-791
- .context/plans/intellij-port/06-vscode-extension-reverse-engineering.md Section 12

## Your Files (replace TODO stub bodies)
- src/main/kotlin/com/anthropic/claudecode/services/ClaudeCodeSettings.kt
- src/main/kotlin/com/anthropic/claudecode/settings/ClaudeCodeConfigurable.kt
- src/main/kotlin/com/anthropic/claudecode/settings/ClaudeCodeSettingsListener.kt

## Key Patterns
- @State(name = "ClaudeCodeSettings", storages = [Storage("claudeCode.xml")])
- @Service(Service.Level.PROJECT)
- PersistentStateComponent<State> with var fields
- Kotlin UI DSL panel { group { row { } } }
- Topic-based change notification

## Settings to Implement
selectedModel, environmentVariables, useTerminal, allowDangerouslySkipPermissions,
claudeBinaryPath, respectGitIgnore, initialPermissionMode, autosave, disableLoginPrompt,
openNewInTab, thinkingLevel, maxThinkingTokens

## Constraints
- Do NOT implement process management logic
- Do NOT implement any service that consumes settings
```

---

### Agent-4 Prompt

```
You are implementing Agent-4: Actions & Keybindings for the Claude Code IntelliJ plugin.

## Context
Read these reference documents:
- .context/plans/intellij-port/06-vscode-extension-reverse-engineering.md Appendix A
- .context/plans/intellij-port/00-master-implementation-plan.md lines 794-883
- .context/plans/intellij-port/05-editor-diff-terminal-research.md (action patterns)

## Your Files (replace TODO stub bodies)
- src/main/kotlin/com/anthropic/claudecode/actions/OpenPanelAction.kt
- src/main/kotlin/com/anthropic/claudecode/actions/NewConversationAction.kt
- src/main/kotlin/com/anthropic/claudecode/actions/OpenTerminalAction.kt
- src/main/kotlin/com/anthropic/claudecode/actions/SendSelectionAction.kt
- src/main/kotlin/com/anthropic/claudecode/actions/AcceptDiffAction.kt
- src/main/kotlin/com/anthropic/claudecode/actions/RejectDiffAction.kt
- src/main/kotlin/com/anthropic/claudecode/actions/InsertAtMentionAction.kt
- src/main/kotlin/com/anthropic/claudecode/actions/FocusInputAction.kt
- src/main/kotlin/com/anthropic/claudecode/actions/BlurInputAction.kt
- src/main/kotlin/com/anthropic/claudecode/actions/ShowLogsAction.kt

## Key Patterns
- All actions extend AnAction and implement DumbAware
- getActionUpdateThread() returns ActionUpdateThread.BGT
- Delegate to services via project.service<ServiceName>() calls
- update() enables/disables based on context

## Constraints
- Do NOT implement the service methods that actions call
- Do NOT implement diff viewing, terminal, or process logic
- Do NOT modify plugin.xml
```

---

### Agent-5 Prompt

```
You are implementing Agent-5: Editor Integration for the Claude Code IntelliJ plugin.

## Context
Read these reference documents:
- .context/plans/intellij-port/05-editor-diff-terminal-research.md Sections 1-2
- .context/plans/intellij-port/06-vscode-extension-reverse-engineering.md Sections 5-6
- .context/plans/intellij-port/00-master-implementation-plan.md lines 592-703

## Your Files (replace TODO stub bodies)
- src/main/kotlin/com/anthropic/claudecode/editor/ClaudeEditorService.kt
- src/main/kotlin/com/anthropic/claudecode/editor/ClaudeEditorListener.kt
- src/main/kotlin/com/anthropic/claudecode/editor/EditorContext.kt

## Key Patterns
- ReadAction for all context gathering
- WriteCommandAction for all modifications with groupId "claude.applyChanges"
- FileEditorManagerListener for file open/close
- SelectionListener for selection changes (debounced 200ms)
- FilenameIndex for @-mention resolution
- VfsUtil.createDirectoryIfMissing for file creation

## Constraints
- Do NOT implement diff viewing (Agent-7)
- Do NOT implement the webview bridge (Agent-6)
- Do NOT block the EDT
```

---

### Agent-6 Prompt

```
You are implementing Agent-6: Webview Communication Bridge for the Claude Code IntelliJ plugin.

## Context
Read these reference documents:
- .context/plans/intellij-port/06-vscode-extension-reverse-engineering.md Sections 4, 14, 15.2
- .context/plans/intellij-port/02-jcef-webview-research.md (JBCefJSQuery patterns)
- .context/plans/intellij-port/00-master-implementation-plan.md lines 486-523, 1226-1250

## Your Files (replace TODO stub bodies)
- src/main/kotlin/com/anthropic/claudecode/webview/WebviewBridge.kt
- src/main/kotlin/com/anthropic/claudecode/webview/WebviewMessageRouter.kt
- src/main/resources/webview/bridge-adapter.js (NEW FILE)

## Dependencies
- JBCefBrowser instance from Agent-2
- Message types from Agent-1 (protocol/Messages.kt)

## Key Patterns
- JBCefJSQuery.create() for JS-to-Kotlin bridge
- CefLoadHandler.onLoadEnd() for bridge injection
- executeJavaScript() for Kotlin-to-JS push
- acquireVsCodeApi() shim that delegates to JBCefJSQuery
- when(type) { } for message routing (54+ types)
- Return immediately from JBCefJSQuery handlers

## Constraints
- Do NOT implement business logic for handlers - delegate to service stubs
- Do NOT modify index.js
- Do NOT implement process management
- Do NOT block in JBCefJSQuery handlers
```

---

### Agent-7 Prompt

```
You are implementing Agent-7: Diff Service for the Claude Code IntelliJ plugin.

## Context
Read these reference documents:
- .context/plans/intellij-port/05-editor-diff-terminal-research.md Sections 3-4
- .context/plans/intellij-port/06-vscode-extension-reverse-engineering.md Section 7
- .context/plans/intellij-port/00-master-implementation-plan.md lines 657-703

## Your Files (replace TODO stub bodies)
- src/main/kotlin/com/anthropic/claudecode/editor/ClaudeDiffService.kt
- src/main/kotlin/com/anthropic/claudecode/editor/DiffActionGroup.kt
- src/main/kotlin/com/anthropic/claudecode/editor/PendingDiff.kt (NEW FILE)

## Key Patterns
- DiffContentFactory.getInstance() for creating diff content
- SimpleDiffRequest for single-file diffs
- DiffRequestChain / SimpleDiffRequestChain for multi-file diffs
- FileTypeManager.getInstance().getFileTypeByFileName() for syntax highlighting
- DiffManager.getInstance().showDiff() to open viewer
- ConcurrentHashMap for pending diff tracking

## Constraints
- Do NOT implement file modification - delegate to ClaudeEditorService (Agent-5)
- Do NOT implement webview message handling for open_diff
- Use IntelliJ's built-in DiffManager, not a custom UI
```

---

### Agent-8 Prompt

```
You are implementing Agent-8: Main Service Orchestrator for the Claude Code IntelliJ plugin.

## Context
Read these reference documents:
- .context/plans/intellij-port/04-process-management-research.md (process lifecycle)
- .context/plans/intellij-port/06-vscode-extension-reverse-engineering.md Sections 15.6-15.8
- .context/plans/intellij-port/00-master-implementation-plan.md (full document)

## Your Files (replace TODO stub bodies)
- src/main/kotlin/com/anthropic/claudecode/services/ClaudeCodeService.kt
- src/main/kotlin/com/anthropic/claudecode/listeners/ClaudeStartupActivity.kt
- src/main/kotlin/com/anthropic/claudecode/listeners/ProjectCloseListener.kt
- src/main/kotlin/com/anthropic/claudecode/ui/ClaudeStatusBarWidgetFactory.kt
- src/main/kotlin/com/anthropic/claudecode/ui/ClaudeStatusBarWidget.kt

## Dependencies (all implemented by other agents)
- ClaudeProcessManager (Agent-1)
- JsonProtocolHandler (Agent-1)
- WebviewBridge (Agent-6)
- ClaudeEditorService (Agent-5)
- ClaudeCodeSettings (Agent-3)
- JBCefBrowser (Agent-2)

## Key Patterns
- @Service(Service.Level.PROJECT) with injected CoroutineScope
- Channel-based architecture: ConcurrentHashMap<String, ClaudeChannel>
- StateFlow<ServiceState> for reactive state
- ProjectActivity for startup
- StatusBarWidget.TextPresentation for status
- Pre/Post tool hooks for autosave and diagnostics

## Constraints
- Do NOT re-implement any component - use instances from other agents
- Do NOT modify files outside your ownership list
```

---

### Agent-9 Prompt

```
You are implementing Agent-9: Terminal Integration & MCP for the Claude Code IntelliJ plugin.

## Context
Read these reference documents:
- .context/plans/intellij-port/05-editor-diff-terminal-research.md Section 11
- .context/plans/intellij-port/06-vscode-extension-reverse-engineering.md Sections 8, 13
- .context/plans/intellij-port/00-master-implementation-plan.md lines 886-931

## Your Files (replace TODO stub bodies)
- src/main/kotlin/com/anthropic/claudecode/terminal/ClaudeTerminalService.kt
- src/main/kotlin/com/anthropic/claudecode/mcp/ClaudeMcpServer.kt
- src/main/kotlin/com/anthropic/claudecode/mcp/McpLockFile.kt (NEW FILE)

## Key Patterns
- TerminalView.getInstance(project).createLocalShellWidget() for terminal
- Optional dependency: terminal plugin may not be present
- WebSocket server on random port for MCP
- Lock file at ~/.claude/ide/{hash}.json
- JSON-RPC 2.0 for MCP protocol

## Constraints
- Do NOT implement Chrome/Jupyter MCP extensions
- Do NOT create a custom terminal emulator
- Terminal plugin must be OPTIONAL dependency
```

---

### Agent-10 Prompt

```
You are implementing Agent-10: Testing & Verification for the Claude Code IntelliJ plugin.

## Context
Read these reference documents:
- .context/plans/intellij-port/03-gradle-project-setup.md (testing, CI/CD)
- .context/plans/intellij-port/00-master-implementation-plan.md lines 934-1028

## Your Files (ALL NEW)
- src/test/kotlin/com/anthropic/claudecode/services/ClaudeCodeServiceTest.kt
- src/test/kotlin/com/anthropic/claudecode/process/ClaudeBinaryResolverTest.kt
- src/test/kotlin/com/anthropic/claudecode/process/JsonProtocolHandlerTest.kt
- src/test/kotlin/com/anthropic/claudecode/webview/WebviewBridgeTest.kt
- src/test/kotlin/com/anthropic/claudecode/webview/WebviewMessageRouterTest.kt
- src/test/kotlin/com/anthropic/claudecode/editor/ClaudeEditorServiceTest.kt
- src/test/kotlin/com/anthropic/claudecode/editor/ClaudeDiffServiceTest.kt
- src/test/kotlin/com/anthropic/claudecode/settings/ClaudeCodeSettingsTest.kt
- .github/workflows/build.yml

## Key Patterns
- BasePlatformTestCase for IDE context tests
- runBlocking for coroutine tests
- Mock processes with PipedInputStream/PipedOutputStream
- No integration tests requiring live Claude CLI

## Constraints
- Do NOT modify implementation files
- Do NOT write UI tests
- Do NOT submit to JetBrains Marketplace
```

---

## File Ownership Matrix

This table ensures no two agents modify the same file.

| File Path (under `src/main/kotlin/com/anthropic/claudecode/`) | Owner |
|------|-------|
| `ClaudeCodeBundle.kt` | Agent-0 |
| `process/ClaudeBinaryResolver.kt` | Agent-1 |
| `process/ClaudeProcessManager.kt` | Agent-1 |
| `process/JsonProtocolHandler.kt` | Agent-1 |
| `process/StderrCollector.kt` | Agent-1 |
| `process/ClaudeErrorHandler.kt` | Agent-1 |
| `protocol/Messages.kt` | Agent-1 |
| `protocol/CliMessages.kt` | Agent-1 |
| `toolwindow/ClaudeCodeToolWindowFactory.kt` | Agent-2 |
| `webview/LocalResourceSchemeHandler.kt` | Agent-2 |
| `webview/JcefSchemeRegistrar.kt` | Agent-2 |
| `webview/ThemeSynchronizer.kt` | Agent-2 |
| `webview/WebviewHtmlGenerator.kt` | Agent-2 |
| `webview/BatchedWebviewUpdater.kt` | Agent-2 |
| `services/ClaudeCodeSettings.kt` | Agent-3 |
| `settings/ClaudeCodeConfigurable.kt` | Agent-3 |
| `settings/ClaudeCodeSettingsListener.kt` | Agent-3 |
| `actions/OpenPanelAction.kt` | Agent-4 |
| `actions/NewConversationAction.kt` | Agent-4 |
| `actions/OpenTerminalAction.kt` | Agent-4 |
| `actions/SendSelectionAction.kt` | Agent-4 |
| `actions/AcceptDiffAction.kt` | Agent-4 |
| `actions/RejectDiffAction.kt` | Agent-4 |
| `actions/InsertAtMentionAction.kt` | Agent-4 |
| `actions/FocusInputAction.kt` | Agent-4 |
| `actions/BlurInputAction.kt` | Agent-4 |
| `actions/ShowLogsAction.kt` | Agent-4 |
| `editor/ClaudeEditorService.kt` | Agent-5 |
| `editor/ClaudeEditorListener.kt` | Agent-5 |
| `editor/EditorContext.kt` | Agent-5 |
| `webview/WebviewBridge.kt` | Agent-6 |
| `webview/WebviewMessageRouter.kt` | Agent-6 |
| `editor/ClaudeDiffService.kt` | Agent-7 |
| `editor/DiffActionGroup.kt` | Agent-7 |
| `editor/PendingDiff.kt` | Agent-7 |
| `services/ClaudeCodeService.kt` | Agent-8 |
| `listeners/ClaudeStartupActivity.kt` | Agent-8 |
| `listeners/ProjectCloseListener.kt` | Agent-8 |
| `ui/ClaudeStatusBarWidgetFactory.kt` | Agent-8 |
| `ui/ClaudeStatusBarWidget.kt` | Agent-8 |
| `terminal/ClaudeTerminalService.kt` | Agent-9 |
| `mcp/ClaudeMcpServer.kt` | Agent-9 |
| `mcp/McpLockFile.kt` | Agent-9 |

| Resource File | Owner |
|------|-------|
| `src/main/resources/META-INF/plugin.xml` | Agent-0 |
| `src/main/resources/META-INF/terminal-support.xml` | Agent-0 |
| `src/main/resources/webview/index.html` | Agent-0 (initial), Agent-2 (updates) |
| `src/main/resources/webview/bridge-adapter.js` | Agent-6 |
| `src/main/resources/webview/index.js` | None (copied from VSCode, read-only) |
| `src/main/resources/webview/index.css` | None (copied from VSCode, read-only) |
| `.github/workflows/build.yml` | Agent-10 |

| Test File | Owner |
|------|-------|
| All `src/test/` files | Agent-10 |

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Agent-0 stubs have wrong signatures | Agent-0 must read ALL research docs to get interfaces right; other agents can submit signature change requests |
| Two agents need to modify the same file | File ownership matrix prevents this; shared state goes through interfaces |
| Agent-N finishes but downstream agent finds bugs | Each agent runs `./gradlew build` before declaring done; compilation errors caught early |
| Message type table incomplete | Agent-1 (Messages.kt) can be extended later; use `JsonObject` as fallback for unknown types |
| JCEF not available on CI | CI tests skip JCEF-dependent tests via `assumeTrue(JBCefApp.isSupported())` |
| Merge conflicts between agents | File ownership matrix ensures no conflicts; only `plugin.xml` is shared (owned by Agent-0) |

---

## Verification Checklist (Run After All Agents Complete)

```bash
# 1. Build
./gradlew clean build

# 2. Tests
./gradlew test

# 3. Plugin verification
./gradlew verifyPluginConfiguration
./gradlew verifyPlugin

# 4. Manual smoke test
./gradlew runIde
# In sandbox IDE:
# - Check plugin appears in Settings > Plugins
# - Open Claude Code tool window
# - Check Settings > Tools > Claude Code
# - Check Tools > Claude Code menu
# - Check keyboard shortcuts
# - Check status bar widget
```
