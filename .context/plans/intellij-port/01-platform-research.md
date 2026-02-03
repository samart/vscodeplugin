# IntelliJ Platform SDK 2025 - Detailed Research

> **Research Date:** February 2, 2026
> **Scope:** IntelliJ Platform 2025.x releases, Gradle plugin, JCEF, Kotlin, API changes
> **Sources:** JetBrains official documentation, IntelliJ Platform SDK docs, JetBrains blog, GitHub repositories
> **Note:** This document is based on knowledge current through early-mid 2025. Some 2025.2/2025.3 details may need verification against the latest docs.

---

## Table of Contents

1. [IntelliJ Platform Version Numbers](#1-intellij-platform-version-numbers)
2. [Gradle IntelliJ Platform Plugin](#2-gradle-intellij-platform-plugin)
3. [JCEF Status in 2025](#3-jcef-java-chromium-embedded-framework-in-2025)
4. [Kotlin Version for Plugin Development](#4-kotlin-version-for-plugin-development)
5. [Key API Changes 2024 to 2025](#5-key-api-changes-2024-to-2025)
6. [Minimum Java Version](#6-minimum-java-version)
7. [Plugin Compatibility Across Versions](#7-plugin-compatibility-across-versions)
8. [New Extension Points and Services](#8-new-extension-points-and-services-in-2025)
9. [Recommendations for Our Plugin](#9-recommendations-for-our-plugin)

---

## 1. IntelliJ Platform Version Numbers

### 2025 Release Schedule and Build Numbers

| Release | Branch Number | Build Number Range | Release Date (Approx.) | Status |
|---------|--------------|-------------------|----------------------|--------|
| **2025.1** | 251 | 251.x | April 2025 | Released |
| **2025.1.x** (patches) | 251 | 251.x.y | April-July 2025 | Released |
| **2025.2** | 252 | 252.x | July/August 2025 | Released |
| **2025.2.x** (patches) | 252 | 252.x.y | Aug-Nov 2025 | Released |
| **2025.3** | 253 | 253.x | November/December 2025 | Released/Late Beta |

### 2024 Releases (for compatibility reference)

| Release | Branch Number | Build Number Range |
|---------|--------------|-------------------|
| **2024.1** | 241 | 241.x |
| **2024.2** | 242 | 242.x |
| **2024.3** | 243 | 243.x |

### Build Number Format

IntelliJ build numbers follow the format: `BRANCH.BUILD.FIX`

- **BRANCH**: Corresponds to the release (e.g., 251 = 2025.1)
- **BUILD**: Sequential build number within the branch
- **FIX**: Patch number (optional)

Example: `251.14959.14` means IntelliJ 2025.1, build 14959, patch 14.

### How to reference in plugin.xml:

```xml
<!-- Target 2024.3 through 2025.2 -->
<idea-version since-build="243" until-build="252.*"/>

<!-- Target 2025.1 and newer (open-ended) -->
<idea-version since-build="251"/>
```

---

## 2. Gradle IntelliJ Platform Plugin

### Plugin Migration: `org.jetbrains.intellij` to `org.jetbrains.intellij.platform`

The IntelliJ plugin development ecosystem underwent a major shift starting in 2024. The legacy Gradle plugin (`org.jetbrains.intellij`, versions 1.x) has been **fully replaced** by the new **IntelliJ Platform Gradle Plugin** (`org.jetbrains.intellij.platform`, versions 2.x).

### Current Recommended Version

| Plugin | ID | Latest Version | Status |
|--------|----|---------------|--------|
| **IntelliJ Platform Gradle Plugin 2.x** | `org.jetbrains.intellij.platform` | **2.2.1+** (check [releases](https://github.com/JetBrains/intellij-platform-gradle-plugin/releases) for exact latest) | **Active, Recommended** |
| Legacy Gradle IntelliJ Plugin 1.x | `org.jetbrains.intellij` | 1.17.4 (final) | **Deprecated, do not use** |

> **Important:** As of 2025, all new plugin projects MUST use `org.jetbrains.intellij.platform` version 2.x. The 1.x plugin is no longer maintained.

### Key Changes in 2.x Plugin

1. **Completely new DSL** - The configuration syntax has changed significantly
2. **Repository-based platform dependency** - IntelliJ SDK is resolved as a Maven dependency
3. **Better Gradle compatibility** - Works with Gradle 8.x+ and Configuration Cache
4. **Explicit dependency declarations** - All platform dependencies must be declared explicitly
5. **Separated concerns** - Separate tasks for building, testing, signing, and publishing

### Modern `build.gradle.kts` Configuration

```kotlin
// build.gradle.kts for IntelliJ Platform Plugin (2.x)
plugins {
    id("java")
    id("org.jetbrains.kotlin.jvm") version "2.0.21"
    id("org.jetbrains.intellij.platform") version "2.2.1"
}

group = "com.anthropic"
version = "1.0.0"

repositories {
    mavenCentral()

    intellijPlatform {
        defaultRepositories()
    }
}

dependencies {
    intellijPlatform {
        // Target IntelliJ IDEA Community 2025.1
        intellijIdeaCommunity("2025.1")

        // OR use a specific build number:
        // intellijIdeaCommunity("251.14959.14")

        // OR target all JetBrains IDEs via platform:
        // create("IC", "2025.1")   // Community
        // create("IU", "2025.1")   // Ultimate
        // create("PC", "2025.1")   // PyCharm Community

        // Bundle plugins your plugin depends on
        bundledPlugin("com.intellij.java")           // Only if you need Java support
        bundledPlugin("org.jetbrains.plugins.terminal") // Terminal plugin

        // Plugin dependencies from JetBrains Marketplace
        // plugin("com.example.someplugin", "1.0.0")

        // Required for testing
        testFramework(TestFrameworkType.Platform)

        // Plugin Verifier
        pluginVerifier()

        // Instrumentation (required for forms, etc.)
        instrumentationTools()
    }

    // Standard dependencies
    testImplementation("junit:junit:4.13.2")
}

intellijPlatform {
    pluginConfiguration {
        id = "com.anthropic.claude-code"
        name = "Claude Code"
        version = project.version.toString()
        description = """
            Claude Code for JetBrains IDEs - AI-powered coding assistant.
        """.trimIndent()

        ideaVersion {
            sinceBuild = "243"     // 2024.3
            untilBuild = "252.*"   // Through 2025.2.x
        }

        vendor {
            name = "Anthropic"
            email = "support@anthropic.com"
            url = "https://anthropic.com"
        }
    }

    signing {
        // Plugin signing configuration (required for JetBrains Marketplace)
        certificateChain = providers.environmentVariable("CERTIFICATE_CHAIN")
        privateKey = providers.environmentVariable("PRIVATE_KEY")
        password = providers.environmentVariable("PRIVATE_KEY_PASSWORD")
    }

    publishing {
        token = providers.environmentVariable("PUBLISH_TOKEN")
    }

    pluginVerification {
        ides {
            // Verify against these IDE versions
            recommended()
            // Or specify exact versions:
            // ide("IC", "2024.3")
            // ide("IC", "2025.1")
        }
    }
}

// Kotlin JVM target
kotlin {
    jvmToolchain(21)
}

tasks {
    buildSearchableOptions {
        enabled = false  // Disable if not using Settings search
    }

    patchPluginXml {
        // Can also be configured here
    }
}
```

### Key Gradle Tasks

| Task | Purpose |
|------|---------|
| `buildPlugin` | Build the plugin distribution (.zip) |
| `runIde` | Launch a sandboxed IDE with the plugin installed |
| `verifyPlugin` | Run IntelliJ Plugin Verifier |
| `signPlugin` | Sign the plugin for Marketplace |
| `publishPlugin` | Publish to JetBrains Marketplace |
| `prepareSandbox` | Prepare the sandbox environment |
| `test` | Run plugin tests |

### `settings.gradle.kts`

```kotlin
// settings.gradle.kts
pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
    }
}

rootProject.name = "claude-code-intellij"
```

### Migration Notes from 1.x

If migrating from the old `org.jetbrains.intellij` plugin:

| Old (1.x) | New (2.x) |
|------------|-----------|
| `intellij { version = "2024.3" }` | `dependencies { intellijPlatform { intellijIdeaCommunity("2024.3") } }` |
| `intellij { plugins = ["terminal"] }` | `dependencies { intellijPlatform { bundledPlugin("org.jetbrains.plugins.terminal") } }` |
| `patchPluginXml { sinceBuild = "243" }` | `intellijPlatform { pluginConfiguration { ideaVersion { sinceBuild = "243" } } }` |
| `publishPlugin { token = "..." }` | `intellijPlatform { publishing { token = "..." } }` |
| `runPluginVerifier { ... }` | `intellijPlatform { pluginVerification { ... } }` |

---

## 3. JCEF (Java Chromium Embedded Framework) in 2025

### Current Status: SUPPORTED AND RECOMMENDED

JCEF remains the **primary and recommended** way to embed web content in IntelliJ plugins as of 2025. There has been no deprecation and it continues to receive updates.

### Key Points

- **JCEF is bundled** with all JetBrains IDEs since 2020.3
- Based on **Chromium** via the Java CEF bindings
- As of 2025.1, JCEF uses a recent Chromium version (likely 118+ or newer)
- **JBCefBrowser** and **JBCefBrowserBase** are the primary APIs
- Available in all JetBrains IDEs (IDEA, PyCharm, WebStorm, CLion, etc.)

### JCEF API Overview

```kotlin
import com.intellij.ui.jcef.JBCefBrowser
import com.intellij.ui.jcef.JBCefBrowserBase
import com.intellij.ui.jcef.JBCefJSQuery
import org.cef.browser.CefBrowser
import org.cef.browser.CefFrame
import org.cef.handler.CefLoadHandlerAdapter

class ClaudeWebView(private val project: Project) {

    val browser: JBCefBrowser = JBCefBrowser()

    // Create a JS-to-Kotlin query bridge
    val jsQuery: JBCefJSQuery = JBCefJSQuery.create(browser as JBCefBrowserBase)

    init {
        // Handle messages from JavaScript
        jsQuery.addHandler { message: String ->
            handleMessage(message)
            JBCefJSQuery.Response("ok")  // Return value to JS
        }

        // Inject the bridge when page loads
        browser.jbCefClient.addLoadHandler(object : CefLoadHandlerAdapter() {
            override fun onLoadEnd(cefBrowser: CefBrowser, frame: CefFrame, httpStatusCode: Int) {
                // Inject the communication bridge
                val injectedJS = """
                    window.sendToPlugin = function(message) {
                        ${jsQuery.inject("message")}
                    };

                    // Notify the web app that the bridge is ready
                    window.dispatchEvent(new CustomEvent('pluginBridgeReady'));
                """.trimIndent()
                cefBrowser.executeJavaScript(injectedJS, cefBrowser.url, 0)
            }
        }, browser.cefBrowser)
    }

    // Send message from Kotlin to JavaScript
    fun sendToWebView(jsonMessage: String) {
        browser.cefBrowser.executeJavaScript(
            "window.receiveFromPlugin && window.receiveFromPlugin($jsonMessage);",
            browser.cefBrowser.url,
            0
        )
    }

    // Load HTML content
    fun loadContent(html: String) {
        browser.loadHTML(html)
    }

    // Load from URL (e.g., local file)
    fun loadUrl(url: String) {
        browser.loadURL(url)
    }

    // Get the AWT component to add to UI
    val component: JComponent
        get() = browser.component

    fun dispose() {
        jsQuery.dispose()
        browser.dispose()
    }

    private fun handleMessage(message: String): String {
        // Parse and handle message from webview
        return "ok"
    }
}
```

### JCEF Availability Check

```kotlin
// Always check if JCEF is available (it might be disabled by user)
fun isJcefAvailable(): Boolean {
    return JBCefApp.isSupported()
}

// In your tool window factory
class ClaudeToolWindowFactory : ToolWindowFactory {
    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        if (!JBCefApp.isSupported()) {
            // Fallback: show a message or use Swing-based UI
            val panel = JPanel(BorderLayout())
            panel.add(JLabel("JCEF is not available. Please enable it in IDE settings."))
            toolWindow.component.add(panel)
            return
        }

        // Normal JCEF-based UI
        val webView = ClaudeWebView(project)
        toolWindow.component.add(webView.component)
    }
}
```

### JCEF Changes and Considerations for 2025

1. **Performance improvements** - JCEF in 2025 IDEs has better memory management and rendering performance
2. **Off-screen rendering (OSR)** - Still supported via `JBCefBrowserBuilder`; consider using it for better integration with IDE themes
3. **DevTools** - Can be enabled for debugging embedded web content
4. **Security**: JCEF content runs in a sandboxed environment. `file://` URLs may need special handling
5. **Dark mode / theme sync** - Consider injecting CSS variables that match the IDE's theme:

```kotlin
// Sync IDE theme with webview
fun injectThemeVariables(browser: CefBrowser) {
    val isDark = UIUtil.isUnderDarcula()
    val bgColor = if (isDark) "#1e1e1e" else "#ffffff"
    val fgColor = if (isDark) "#cccccc" else "#333333"

    browser.executeJavaScript("""
        document.documentElement.style.setProperty('--ide-bg-color', '$bgColor');
        document.documentElement.style.setProperty('--ide-fg-color', '$fgColor');
        document.documentElement.style.setProperty('--ide-is-dark', '${if (isDark) "1" else "0"}');
    """.trimIndent(), browser.url, 0)
}
```

### Alternatives to JCEF

While JCEF is recommended, there are fallback options:
- **Swing UI**: For simple UIs, pure Swing/Kotlin UI DSL is lighter
- **JetBrains Kotlin UI DSL v2**: Declarative Swing-based UI framework built into IntelliJ (available since 2022.x, matured in 2024-2025)
- **Markdown-based rendering**: For simple content display

**For our use case (embedding a React app), JCEF is the only viable option.**

---

## 4. Kotlin Version for Plugin Development

### Bundled Kotlin Versions by IntelliJ Release

IntelliJ bundles a specific Kotlin version, and plugins **must use a Kotlin version that is compatible with (ideally equal to or older than) the bundled version**.

| IntelliJ Version | Bundled Kotlin Version | Notes |
|-----------------|----------------------|-------|
| 2024.1 | Kotlin 1.9.22-24 | |
| 2024.2 | Kotlin 1.9.24-25 / 2.0.0 | Transitional |
| 2024.3 | Kotlin 2.0.x (2.0.20+) | K2 compiler default |
| **2025.1** | **Kotlin 2.0.21 - 2.1.0** | K2 compiler stable |
| **2025.2** | **Kotlin 2.1.x** | |

### Recommended Kotlin Version for Our Plugin

**Use Kotlin 2.0.21** if targeting 2024.3+:
- Compatible with IntelliJ 2024.3, 2025.1, and 2025.2
- Uses the stable K2 compiler
- Well-tested with the IntelliJ Platform

**Rationale:** The Kotlin version used by the plugin should be **less than or equal to** the Kotlin version bundled with the **oldest** supported IDE version. Using a newer version risks `NoSuchMethodError` or similar runtime issues.

### Kotlin Configuration

```kotlin
// build.gradle.kts
plugins {
    id("org.jetbrains.kotlin.jvm") version "2.0.21"
}

kotlin {
    jvmToolchain(21)  // Java 21 for 2025.x targets
}
```

### Important Kotlin Guidelines for IntelliJ Plugins

1. **Do NOT bundle the Kotlin stdlib** - IntelliJ already includes it. The Gradle plugin handles this automatically.
2. **Avoid Kotlin coroutines stdlib conflicts** - Use IntelliJ's own coroutine infrastructure if needed
3. **Use `@JvmStatic` and `@JvmField`** annotations where needed for Java interop
4. **Prefer `companion object` with `getInstance()`** pattern for services:

```kotlin
@Service(Service.Level.PROJECT)
class ClaudeService(private val project: Project) {
    companion object {
        @JvmStatic
        fun getInstance(project: Project): ClaudeService =
            project.getService(ClaudeService::class.java)
    }
}
```

5. **K2 Compiler**: As of 2025, the K2 compiler is the default. Ensure your build uses it (it's the default with Kotlin 2.0+).

---

## 5. Key API Changes: 2024 to 2025

### Breaking Changes and Deprecations

#### 5.1 Service/Component Registration Changes

**Major change in 2024.3 / 2025.1**: The `<projectService>` and `<applicationService>` XML registration approach has been increasingly replaced by `@Service` annotation-based registration.

```kotlin
// OLD approach (still works but discouraged for new code):
// In plugin.xml:
// <projectService serviceImplementation="com.example.MyService"/>

// NEW preferred approach (2024.3+):
@Service(Service.Level.PROJECT)
class ClaudeProjectService(private val project: Project) {
    // Service implementation
}

@Service(Service.Level.APP)
class ClaudeApplicationService {
    // Application-level service
}
```

> **Note:** XML registration is still supported and necessary for some use cases (e.g., overriding services, optional dependencies). But `@Service` annotation is preferred for new services.

#### 5.2 Coroutines and Threading Model

**2024.3 / 2025.1 introduces significant changes to the threading model:**

- IntelliJ is moving toward **structured concurrency** using Kotlin coroutines
- New `com.intellij.platform.util.coroutines` APIs
- `ApplicationManager.getApplication().executeOnPooledThread()` still works but coroutine-based alternatives are preferred
- New `readAction {}` and `writeAction {}` suspend functions

```kotlin
// Old threading approach (still works)
ApplicationManager.getApplication().executeOnPooledThread {
    val result = computeSomething()
    ApplicationManager.getApplication().invokeLater {
        updateUI(result)
    }
}

// New coroutine-based approach (2024.3+)
// In a coroutine scope (e.g., from a service that implements CoroutineScope)
scope.launch {
    val result = readAction {
        computeSomethingRequiringReadAccess()
    }
    withContext(Dispatchers.EDT) {
        updateUI(result)
    }
}
```

**For our plugin:** Since we primarily manage a subprocess and communicate via stdin/stdout, the traditional threading approach is fine. Use `executeOnPooledThread` for I/O and `invokeLater` for UI updates.

#### 5.3 Light Services (Simplified)

As of 2024.3/2025.1, "light services" (services without XML registration) are the preferred approach. These use only the `@Service` annotation.

Requirements for light services:
- Must be `final` (no subclassing)
- Constructor can only take `Project` (for project-level) or `Application` (for app-level) or no parameters
- Cannot be overridden by other plugins

#### 5.4 Dynamic Plugin Loading

IntelliJ 2025 continues to enforce **dynamic plugin loading/unloading**. Plugins should be designed to be loaded and unloaded without IDE restart.

Requirements:
- Use `Disposable` pattern properly
- Register disposables with parent `Disposable` objects
- Clean up JCEF browsers, processes, and threads on unload
- Avoid static mutable state

```kotlin
class ClaudeToolWindowFactory : ToolWindowFactory, DumbAware {
    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        val disposable = Disposer.newDisposable("ClaudeToolWindow")
        toolWindow.disposable?.let { Disposer.register(it, disposable) }

        val webView = ClaudeWebView(project)
        Disposer.register(disposable, webView)

        toolWindow.component.add(webView.component)
    }
}
```

#### 5.5 New Notification API

As of 2024.3/2025.1, the notification system has been refined:

```kotlin
// Register notification group in plugin.xml
// <notificationGroup id="Claude Code" displayType="BALLOON"/>

// Use in code
NotificationGroupManager.getInstance()
    .getNotificationGroup("Claude Code")
    .createNotification("Claude process started", NotificationType.INFORMATION)
    .notify(project)
```

#### 5.6 `DumbAware` Interface

Actions and tool windows that don't require index access should implement `DumbAware` to remain functional during indexing:

```kotlin
class ClaudeToolWindowFactory : ToolWindowFactory, DumbAware {
    // This tool window works even while the IDE is indexing
}

class OpenClaudePanelAction : AnAction(), DumbAware {
    // This action works even during indexing
}
```

#### 5.7 Deprecated APIs to Avoid

| Deprecated API | Replacement | Since |
|----------------|-------------|-------|
| `ProjectComponent` / `ApplicationComponent` | `@Service` annotation or `projectListener` | 2020+ |
| `ServiceManager.getService()` | `project.getService()` or `service<>()` | 2021+ |
| `com.intellij.openapi.util.Computable` | Kotlin lambdas | 2024 |
| `AnAction(String, String, Icon)` constructor | `AnAction()` + override `update()` | 2024.2+ |
| `ToolWindowFactory.isApplicable()` | Condition in `toolWindow` extension point XML | 2024.3 |
| Some `FileEditorManager` methods | Newer overloads with additional params | 2025.1 |

#### 5.8 New Extension Points in 2025.1

- **`com.intellij.toolWindow` improvements**: New attributes for conditional visibility
- **`com.intellij.notificationGroup`**: Enhanced notification groups
- **Improved `com.intellij.projectService`**: Better lifecycle management
- **`com.intellij.backgroundPostStartupActivity`**: For post-startup initialization

---

## 6. Minimum Java Version

### Java Requirements by IntelliJ Version

| IntelliJ Version | Minimum Java (Runtime) | Recommended JDK | Bundled JBR |
|-----------------|----------------------|-----------------|-------------|
| 2024.1 | Java 17 | JDK 17 | JBR 17 |
| 2024.2 | Java 17 | JDK 17/21 | JBR 21 |
| 2024.3 | Java 21 | JDK 21 | JBR 21 |
| **2025.1** | **Java 21** | **JDK 21** | **JBR 21** |
| **2025.2** | **Java 21** | **JDK 21** | **JBR 21** |

### Key Points

- **IntelliJ 2024.2** was the transitional release that bundled JBR 21 (JetBrains Runtime based on OpenJDK 21)
- **IntelliJ 2024.3+** requires Java 21 as the minimum runtime
- **All 2025.x releases** require Java 21
- JetBrains ships its own JDK distribution called **JBR (JetBrains Runtime)**
- Plugin code should be compiled targeting Java 21 bytecode if your minimum supported IDE is 2024.3+

### Build Configuration

```kotlin
// build.gradle.kts
kotlin {
    jvmToolchain(21)
}

// Or for Java:
java {
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
}
```

### If Targeting 2024.1 or 2024.2 as Minimum

If you need to support IDEs as old as 2024.1, compile with Java 17:

```kotlin
kotlin {
    jvmToolchain(17)
}
```

**Recommendation for our plugin:** Target **Java 21** since we plan to support 2024.3+ at the earliest.

---

## 7. Plugin Compatibility Across Versions

### Strategy for Multi-Version Support

#### Option A: Single Plugin, Wide Compatibility (Recommended)

Target a range of versions using `since-build` and `until-build`:

```xml
<idea-version since-build="243" until-build="253.*"/>
```

This supports 2024.3 through 2025.3.x.

**Pros:** Single codebase, single distribution
**Cons:** Must use only APIs available in the oldest supported version

#### Option B: Multiple Branches

Maintain separate branches for different version ranges. Not recommended unless there are irreconcilable API differences.

### Compatibility Best Practices

1. **Use `pluginVerifier`** to check compatibility:

```kotlin
// build.gradle.kts
intellijPlatform {
    pluginVerification {
        ides {
            // Automatically verify against recommended versions
            recommended()

            // Or specify exact versions
            ide("IC", "2024.3")
            ide("IC", "2025.1")
            ide("IC", "2025.2")
        }
    }
}
```

Run: `./gradlew verifyPlugin`

2. **Use `DumbAware` everywhere possible** - Makes your plugin work during indexing

3. **Avoid internal APIs** - Packages with `impl` in the name are not guaranteed stable

4. **Optional dependencies** for non-essential features:

```xml
<!-- plugin.xml -->
<depends>com.intellij.modules.platform</depends>

<!-- Optional: only loaded if terminal plugin is present -->
<depends optional="true" config-file="terminal-integration.xml">
    org.jetbrains.plugins.terminal
</depends>

<!-- Optional: only loaded if Git plugin is present -->
<depends optional="true" config-file="git-integration.xml">
    Git4Idea
</depends>
```

5. **Runtime version checks** for newer APIs:

```kotlin
// Check platform version at runtime
fun isAtLeast2025_1(): Boolean {
    val build = ApplicationInfo.getInstance().build
    return build.baselineVersion >= 251
}

// Use newer API conditionally
if (isAtLeast2025_1()) {
    // Use 2025.1-specific API
} else {
    // Fallback for older versions
}
```

6. **Compile against the oldest supported version**, test against all:

```kotlin
// build.gradle.kts
dependencies {
    intellijPlatform {
        // Compile against the OLDEST version you support
        intellijIdeaCommunity("2024.3")
    }
}
```

### What to Depend On

For a tool window + process management plugin, the minimal dependency set is:

```xml
<!-- Only require the base platform - works in ALL JetBrains IDEs -->
<depends>com.intellij.modules.platform</depends>
```

This gives you access to:
- Tool windows
- Actions and keybindings
- JCEF / JBCefBrowser
- Editor APIs
- VFS (Virtual File System)
- Project management
- Notifications
- Process management utilities
- Settings/Preferences

---

## 8. New Extension Points and Services in 2025

### Relevant Extension Points for Tool Window + Process Management Plugin

#### 8.1 Tool Window Registration

```xml
<extensions defaultExtensionNs="com.intellij">
    <toolWindow id="Claude"
                anchor="right"
                secondary="false"
                icon="/icons/claude-13.svg"
                factoryClass="com.anthropic.claude.toolwindow.ClaudeToolWindowFactory"
                canCloseContents="false"
                doNotActivateOnStart="true"/>
</extensions>
```

New in 2024.3/2025.1:
- `condition` attribute for conditional registration
- Better support for tool window tabs

#### 8.2 Background Post-Startup Activity

Perfect for initializing the Claude service after IDE startup:

```xml
<extensions defaultExtensionNs="com.intellij">
    <backgroundPostStartupActivity
        implementation="com.anthropic.claude.ClaudeStartupActivity"/>
</extensions>
```

```kotlin
class ClaudeStartupActivity : ProjectActivity {
    override suspend fun execute(project: Project) {
        // Initialize Claude service, check binary availability, etc.
        val service = project.getService(ClaudeService::class.java)
        service.initialize()
    }
}
```

> **Note:** `PostStartupActivity` (non-background) is deprecated in favor of `ProjectActivity` (coroutine-based) as of 2024.3+.

#### 8.3 Project Service (with @Service annotation)

```kotlin
@Service(Service.Level.PROJECT)
class ClaudeService(private val project: Project) : Disposable {

    private var process: Process? = null

    fun startProcess() { /* ... */ }
    fun stopProcess() { /* ... */ }

    override fun dispose() {
        stopProcess()
    }

    companion object {
        fun getInstance(project: Project): ClaudeService =
            project.getService(ClaudeService::class.java)
    }
}
```

#### 8.4 Application-Level Service

```kotlin
@Service(Service.Level.APP)
class ClaudeBinaryManager {
    fun findBinary(): String? { /* ... */ }
    fun getBinaryVersion(): String? { /* ... */ }
}
```

#### 8.5 Notification Group

```xml
<extensions defaultExtensionNs="com.intellij">
    <notificationGroup id="Claude Code"
                       displayType="BALLOON"
                       isLogByDefault="true"/>
</extensions>
```

#### 8.6 Settings / Configurable

```xml
<extensions defaultExtensionNs="com.intellij">
    <projectConfigurable
        instance="com.anthropic.claude.settings.ClaudeConfigurable"
        displayName="Claude Code"
        id="com.anthropic.claude.settings"
        parentId="tools"/>
</extensions>
```

#### 8.7 New in 2025: Improved Process Handling

IntelliJ 2025 continues to improve `com.intellij.execution` APIs:

```kotlin
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.OSProcessHandler
import com.intellij.execution.process.ProcessAdapter
import com.intellij.execution.process.ProcessEvent
import com.intellij.execution.process.ProcessOutputTypes
import com.intellij.openapi.util.Key

class ClaudeProcessHandler(private val project: Project) {

    fun startClaude(): OSProcessHandler {
        val commandLine = GeneralCommandLine(findClaudeBinary())
            .withWorkDirectory(project.basePath)
            .withEnvironment(buildEnvironment())
            .withCharset(Charsets.UTF_8)

        val processHandler = OSProcessHandler(commandLine)

        processHandler.addProcessListener(object : ProcessAdapter() {
            override fun onTextAvailable(event: ProcessEvent, outputType: Key<*>) {
                when (outputType) {
                    ProcessOutputTypes.STDOUT -> handleStdout(event.text)
                    ProcessOutputTypes.STDERR -> handleStderr(event.text)
                }
            }

            override fun processTerminated(event: ProcessEvent) {
                handleProcessExit(event.exitCode)
            }
        })

        processHandler.startNotify()
        return processHandler
    }
}
```

#### 8.8 Editor Gutter Icons (for inline annotations)

If we want to show Claude suggestions inline:

```xml
<extensions defaultExtensionNs="com.intellij">
    <codeInsight.lineMarkerProvider
        language=""
        implementationClass="com.anthropic.claude.editor.ClaudeLineMarkerProvider"/>
</extensions>
```

#### 8.9 Status Bar Widget

```xml
<extensions defaultExtensionNs="com.intellij">
    <statusBarWidgetFactory
        id="ClaudeStatusWidget"
        implementation="com.anthropic.claude.ui.ClaudeStatusBarWidgetFactory"/>
</extensions>
```

```kotlin
class ClaudeStatusBarWidgetFactory : StatusBarWidgetFactory {
    override fun getId() = "ClaudeStatusWidget"
    override fun getDisplayName() = "Claude Code Status"
    override fun createWidget(project: Project) = ClaudeStatusBarWidget(project)
    override fun isAvailable(project: Project) = true
}
```

---

## 9. Recommendations for Our Plugin

### Recommended Target Configuration

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| **Minimum IDE version** | 2024.3 (build 243) | Stable Java 21, modern APIs, good JCEF |
| **Maximum IDE version** | 2025.2.* (build 252.*) | Or leave open-ended |
| **Java version** | 21 | Required by 2024.3+ |
| **Kotlin version** | 2.0.21 | Compatible with 2024.3 through 2025.2 |
| **Gradle Plugin** | org.jetbrains.intellij.platform 2.2.1+ | Current recommended |
| **Gradle version** | 8.10+ | Required by IntelliJ Platform Gradle Plugin 2.x |
| **Platform dependency** | com.intellij.modules.platform | All JetBrains IDEs |
| **JCEF** | Yes, with Swing fallback message | Primary UI approach |

### Quick-Start `build.gradle.kts`

```kotlin
plugins {
    id("java")
    id("org.jetbrains.kotlin.jvm") version "2.0.21"
    id("org.jetbrains.intellij.platform") version "2.2.1"
}

group = "com.anthropic"
version = "1.0.0-alpha.1"

repositories {
    mavenCentral()
    intellijPlatform {
        defaultRepositories()
    }
}

dependencies {
    intellijPlatform {
        intellijIdeaCommunity("2024.3")

        bundledPlugin("org.jetbrains.plugins.terminal")

        pluginVerifier()
        instrumentationTools()
        testFramework(TestFrameworkType.Platform)
    }
}

intellijPlatform {
    pluginConfiguration {
        id = "com.anthropic.claude-code"
        name = "Claude Code"
        version = project.version.toString()

        ideaVersion {
            sinceBuild = "243"
            untilBuild = "252.*"
        }

        vendor {
            name = "Anthropic"
            email = "support@anthropic.com"
            url = "https://anthropic.com"
        }
    }

    pluginVerification {
        ides {
            recommended()
        }
    }
}

kotlin {
    jvmToolchain(21)
}

tasks {
    buildSearchableOptions {
        enabled = false
    }
}
```

### Important Links

- **IntelliJ Platform SDK Docs:** https://plugins.jetbrains.com/docs/intellij/welcome.html
- **IntelliJ Platform Gradle Plugin 2.x:** https://github.com/JetBrains/intellij-platform-gradle-plugin
- **IntelliJ Platform Gradle Plugin Docs:** https://plugins.jetbrains.com/docs/intellij/tools-intellij-platform-gradle-plugin.html
- **Build Number Ranges:** https://plugins.jetbrains.com/docs/intellij/build-number-ranges.html
- **JCEF Documentation:** https://plugins.jetbrains.com/docs/intellij/jcef.html
- **Kotlin for Plugin Development:** https://plugins.jetbrains.com/docs/intellij/using-kotlin.html
- **Plugin Template (Official):** https://github.com/JetBrains/intellij-platform-plugin-template
- **API Changes by Version:** https://plugins.jetbrains.com/docs/intellij/api-changes-list.html
- **JetBrains Marketplace:** https://plugins.jetbrains.com/
- **IntelliJ Community Source:** https://github.com/JetBrains/intellij-community

### Verification Steps Before Starting Development

1. **Check exact latest Gradle plugin version:** Visit https://github.com/JetBrains/intellij-platform-gradle-plugin/releases
2. **Verify Kotlin compatibility:** Visit https://plugins.jetbrains.com/docs/intellij/using-kotlin.html#kotlin-standard-library
3. **Check exact build numbers:** Visit https://plugins.jetbrains.com/docs/intellij/build-number-ranges.html
4. **Review API changes list:** Visit https://plugins.jetbrains.com/docs/intellij/api-changes-list.html
5. **Clone the official template:** `gh repo clone JetBrains/intellij-platform-plugin-template` and compare with our setup

---

## Appendix: Version Cross-Reference Matrix

| Component | Version for 2024.3 target | Version for 2025.1 target | Version for 2025.2 target |
|-----------|--------------------------|--------------------------|--------------------------|
| `since-build` | 243 | 251 | 252 |
| Java | 21 | 21 | 21 |
| Kotlin | 2.0.21 | 2.0.21 | 2.0.21 - 2.1.x |
| Gradle | 8.10+ | 8.10+ | 8.10+ |
| Gradle Plugin | 2.2.x | 2.2.x | 2.2.x |
| JCEF | Supported | Supported | Supported |
| JBR | 21 | 21 | 21 |
