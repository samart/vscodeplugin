# IntelliJ Plugin Gradle Project Setup (2025)

## Overview

This document provides a complete, copy-pasteable project setup for an IntelliJ IDEA plugin
using the **Gradle IntelliJ Platform Plugin 2.x** (`org.jetbrains.intellij.platform`).
This is the modern replacement for the older `org.jetbrains.intellij` plugin (1.x).

**Key changes in 2.x:**
- New plugin ID: `org.jetbrains.intellij.platform` (replaces `org.jetbrains.intellij`)
- Dedicated repository for IntelliJ Platform artifacts
- Dependencies declared via `intellijPlatform {}` block (not `intellij {}`)
- Type-safe DSL for platform, plugin, and test dependencies
- Separate artifact repositories (must be explicitly configured)
- Built-in support for plugin verification, signing, and marketplace publishing

---

## 1. Project Directory Structure

```
claude-code-intellij/
├── .github/
│   └── workflows/
│       └── build.yml                    # CI workflow
├── .run/
│   └── Run IDE with Plugin.run.xml      # IntelliJ run configuration
├── gradle/
│   ├── wrapper/
│   │   ├── gradle-wrapper.jar
│   │   └── gradle-wrapper.properties
│   └── libs.versions.toml               # Version catalog
├── src/
│   ├── main/
│   │   ├── kotlin/
│   │   │   └── com/
│   │   │       └── anthropic/
│   │   │           └── claudecode/
│   │   │               ├── ClaudeCodePlugin.kt
│   │   │               ├── actions/
│   │   │               │   ├── OpenPanelAction.kt
│   │   │               │   └── OpenTerminalAction.kt
│   │   │               ├── listeners/
│   │   │               │   └── ProjectOpenListener.kt
│   │   │               ├── services/
│   │   │               │   ├── ClaudeCodeService.kt
│   │   │               │   └── ClaudeCodeSettings.kt
│   │   │               ├── settings/
│   │   │               │   └── ClaudeCodeConfigurable.kt
│   │   │               └── toolwindow/
│   │   │                   └── ClaudeCodeToolWindowFactory.kt
│   │   └── resources/
│   │       └── META-INF/
│   │           ├── plugin.xml            # Plugin descriptor
│   │           ├── pluginIcon.svg        # 40x40 plugin icon
│   │           └── pluginIcon_dark.svg   # Dark theme variant
│   └── test/
│       ├── kotlin/
│       │   └── com/
│       │       └── anthropic/
│       │           └── claudecode/
│       │               └── ClaudeCodePluginTest.kt
│       └── resources/
├── build.gradle.kts                      # Build configuration
├── settings.gradle.kts                   # Settings & repositories
├── gradle.properties                     # Project properties
├── gradlew                               # Gradle wrapper (Unix)
├── gradlew.bat                           # Gradle wrapper (Windows)
├── CHANGELOG.md                          # Plugin changelog
└── LICENSE
```

---

## 2. `settings.gradle.kts`

The settings file **must** configure the IntelliJ Platform Gradle Plugin's custom
Maven repository, because the plugin is not published to Gradle Plugin Portal.

```kotlin
// settings.gradle.kts

rootProject.name = "claude-code-intellij"

plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "0.9.0"
}

dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS

    repositories {
        mavenCentral()
        gradlePluginPortal()

        // IntelliJ Platform Gradle Plugin releases
        maven("https://cache-redirector.jetbrains.com/intellij-dependencies")
    }
}
```

> **Note:** The `org.jetbrains.intellij.platform` plugin is published to Gradle Plugin Portal
> as of 2.x, so `pluginManagement` custom repos are usually not needed for the plugin itself.
> However, the IntelliJ Platform *artifacts* (SDK JARs) require the dedicated Maven repository,
> which is configured in `build.gradle.kts` via the `intellijPlatform` repositories block.

---

## 3. `gradle/libs.versions.toml` (Version Catalog)

```toml
# gradle/libs.versions.toml

[versions]
# -- Gradle IntelliJ Platform Plugin --
# https://github.com/JetBrains/intellij-platform-gradle-plugin/releases
intellijPlatformPlugin = "2.2.1"

# -- Kotlin --
kotlin = "2.1.0"

# -- IntelliJ Platform --
# https://www.jetbrains.com/idea/download/other.html
# Use the FULL build number, e.g. "243.21565.193" or a release shorthand "2024.3.1"
intellijPlatformVersion = "2024.3.1"
# Minimum IDE version the plugin supports (since-build)
pluginSinceBuild = "243"
# Maximum IDE version the plugin supports (until-build); empty = no upper bound
pluginUntilBuild = "251.*"

# -- Plugin metadata --
pluginGroup = "com.anthropic.claudecode"
pluginName = "claude-code-intellij"
pluginVersion = "0.1.0"

# -- Java / JVM --
javaVersion = "21"

# -- Testing --
junit = "5.11.4"

# -- Libraries --
kotlinxCoroutines = "1.10.1"
kotlinxSerialization = "1.7.3"

[libraries]
kotlinx-coroutines-core = { group = "org.jetbrains.kotlinx", name = "kotlinx-coroutines-core", version.ref = "kotlinxCoroutines" }
kotlinx-coroutines-swing = { group = "org.jetbrains.kotlinx", name = "kotlinx-coroutines-swing", version.ref = "kotlinxCoroutines" }
kotlinx-serialization-json = { group = "org.jetbrains.kotlinx", name = "kotlinx-serialization-json", version.ref = "kotlinxSerialization" }
junit-jupiter-api = { group = "org.junit.jupiter", name = "junit-jupiter-api", version.ref = "junit" }
junit-jupiter-engine = { group = "org.junit.jupiter", name = "junit-jupiter-engine", version.ref = "junit" }

[plugins]
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
intellij-platform = { id = "org.jetbrains.intellij.platform", version.ref = "intellijPlatformPlugin" }
```

---

## 4. `gradle.properties`

```properties
# gradle.properties

# --- IntelliJ Platform Plugin ---
# These are read by build.gradle.kts and/or version catalog.
# Keep in sync with libs.versions.toml when applicable.

# --- Gradle Performance ---
org.gradle.configuration-cache=true
org.gradle.caching=true
org.gradle.parallel=true
org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError

# --- Kotlin ---
kotlin.stdlib.default.dependency=false
# Opt into Kotlin incremental compilation
kotlin.incremental=true
# Suppress Kotlin version compatibility warnings from IntelliJ SDK
kotlin.suppressGradlePluginWarnings=IncorrectCompileOnlyDependencyWarning

# --- Encoding ---
systemProp.file.encoding=UTF-8
```

---

## 5. `build.gradle.kts`

This is the core build file using the Gradle IntelliJ Platform Plugin 2.x.

```kotlin
// build.gradle.kts

import org.jetbrains.intellij.platform.gradle.TestFrameworkType

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.intellij.platform)
}

group = providers.gradleProperty("pluginGroup").getOrElse("com.anthropic.claudecode")
version = providers.gradleProperty("pluginVersion").getOrElse("0.1.0")

// ---------------------------------------------------------------------------
//  Repositories
// ---------------------------------------------------------------------------
repositories {
    mavenCentral()

    // IntelliJ Platform dependencies (SDK jars, plugins, etc.)
    intellijPlatform {
        defaultRepositories()
    }
}

// ---------------------------------------------------------------------------
//  Kotlin / Java compilation settings
// ---------------------------------------------------------------------------
kotlin {
    jvmToolchain {
        languageVersion = JavaLanguageVersion.of(
            libs.versions.javaVersion.get()
        )
    }
}

// ---------------------------------------------------------------------------
//  Dependencies
// ---------------------------------------------------------------------------
dependencies {
    // -- IntelliJ Platform --
    intellijPlatform {
        // Target IDE: IntelliJ IDEA Community Edition
        // Alternatives: intellijIdeaUltimate(), clion(), pycharmCommunity(),
        //               pycharmProfessional(), webStorm(), goLand(), rider(),
        //               phpStorm(), rubyMine(), dataGrip(), androidStudio()
        intellijIdeaCommunity(libs.versions.intellijPlatformVersion.get())

        // Bundled plugins that ship with the IDE (use plugin ID)
        bundledPlugins(
            "com.intellij.java",           // Java support (if needed)
            "org.jetbrains.plugins.terminal" // Terminal plugin
        )

        // Marketplace plugins the plugin depends on (optional)
        // plugins(
        //     "com.example.some-plugin:1.2.3"
        // )

        // Plugin verifier (checks binary compatibility)
        pluginVerifier()

        // Zip distribution signer
        zipSigner()

        // Test framework
        testFramework(TestFrameworkType.Platform)

        // Additional test dependencies
        // testFramework(TestFrameworkType.JUnit5)

        // Instrumentation (required for form-based UI and some platform features)
        instrumentationTools()
    }

    // -- Kotlin libraries --
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.swing)
    implementation(libs.kotlinx.serialization.json)

    // -- Test dependencies --
    testImplementation(libs.junit.jupiter.api)
    testRuntimeOnly(libs.junit.jupiter.engine)
}

// ---------------------------------------------------------------------------
//  IntelliJ Platform configuration
// ---------------------------------------------------------------------------
intellijPlatform {
    // ---- Plugin metadata ----
    pluginConfiguration {
        id = providers.gradleProperty("pluginGroup")
            .getOrElse("com.anthropic.claudecode")
        name = providers.gradleProperty("pluginName")
            .getOrElse("Claude Code")
        version = project.version.toString()

        description = providers.provider {
            """
            Claude Code for JetBrains IDEs.

            An agentic coding assistant that lives in your IDE, powered by Claude.
            Supports all JetBrains IDEs including IntelliJ IDEA, PyCharm, WebStorm,
            GoLand, PhpStorm, RubyMine, CLion, Rider, and more.

            Features:
            - AI-powered code assistance via Claude
            - Integrated tool window with web-based UI
            - Terminal integration
            - Editor context awareness
            - Multi-project support
            """.trimIndent()
        }

        // Changelog entries (supports HTML)
        changeNotes = providers.provider {
            """
            <h3>0.1.0</h3>
            <ul>
                <li>Initial release</li>
                <li>JCEF-based webview integration</li>
                <li>Process management for Claude CLI</li>
                <li>Tool window with integrated chat UI</li>
            </ul>
            """.trimIndent()
        }

        // IDE version compatibility
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

    // ---- Plugin signing (for JetBrains Marketplace) ----
    signing {
        certificateChain = providers.environmentVariable("CERTIFICATE_CHAIN")
        privateKey = providers.environmentVariable("PRIVATE_KEY")
        password = providers.environmentVariable("PRIVATE_KEY_PASSWORD")
    }

    // ---- Publishing to JetBrains Marketplace ----
    publishing {
        token = providers.environmentVariable("PUBLISH_TOKEN")
        // channels = listOf("stable") // or "eap", "beta"
    }

    // ---- Plugin verification ----
    pluginVerification {
        ides {
            // Verify against these IDE versions
            recommended()
            // Or specify explicit versions:
            // ide(IntelliJPlatformType.IntellijIdeaCommunity, "2024.2")
            // ide(IntelliJPlatformType.IntellijIdeaCommunity, "2024.3.1")
        }
    }
}

// ---------------------------------------------------------------------------
//  Tasks
// ---------------------------------------------------------------------------
tasks {
    // Use JUnit 5 for tests
    test {
        useJUnitPlatform()
    }

    // Configure the sandbox IDE
    // The sandbox is a clean IDE installation used for testing the plugin
    prepareSandbox {
        // Copy additional files to the sandbox if needed
        // from("src/main/resources/webview") {
        //     into("${intellijPlatform.projectName.get()}/webview")
        // }
    }

    // Configure the 'runIde' task (launches sandbox IDE)
    runIde {
        // Increase memory for the sandbox IDE
        jvmArgs("-Xmx2g")

        // System properties for debugging
        systemProperty("idea.log.trace.categories", "#com.anthropic.claudecode")
    }

    // Wrapper task configuration
    wrapper {
        gradleVersion = "8.12"
        distributionType = Wrapper.DistributionType.ALL
    }

    // Kotlin compiler options
    compileKotlin {
        compilerOptions {
            // Enable experimental coroutines API
            freeCompilerArgs.addAll(
                "-Xjsr305=strict",
                "-opt-in=kotlin.RequiresOptIn"
            )
        }
    }
}
```

---

## 6. `src/main/resources/META-INF/plugin.xml`

The plugin descriptor is the core metadata file. With Gradle IntelliJ Platform Plugin 2.x,
some fields (id, name, version, description, vendor, idea-version) can be set in
`build.gradle.kts` via `pluginConfiguration {}` and will be **patched** into this file
during the build. You still provide the structural elements here.

```xml
<!-- src/main/resources/META-INF/plugin.xml -->
<idea-plugin>
    <!--
        Unique plugin identifier. Convention: reversed domain + plugin name.
        This will be patched by Gradle if configured in pluginConfiguration {}.
    -->
    <id>com.anthropic.claudecode</id>
    <name>Claude Code</name>

    <!--
        Vendor info (patched by Gradle).
    -->
    <vendor email="support@anthropic.com" url="https://anthropic.com">
        Anthropic
    </vendor>

    <!--
        Description displayed in the Marketplace and IDE plugin manager.
        Patched by Gradle from pluginConfiguration.description.
    -->
    <description><![CDATA[
        Claude Code for JetBrains IDEs - An agentic coding assistant powered by Claude.
    ]]></description>

    <!--
        Required platform modules.
        com.intellij.modules.platform = works in ALL JetBrains IDEs
        com.intellij.modules.lang    = IDEs with language support (all except DataGrip)
        com.intellij.modules.java    = ONLY IntelliJ IDEA (Java/Kotlin IDEs)
    -->
    <depends>com.intellij.modules.platform</depends>

    <!--
        Optional dependencies on other plugins.
        The config-file attribute points to an additional XML with extensions
        that only load when the dependency is available.
    -->
    <depends optional="true" config-file="terminal-support.xml">
        org.jetbrains.plugins.terminal
    </depends>

    <!--
        Application-level listeners (not tied to a project).
    -->
    <applicationListeners>
        <!-- Example: listen for app lifecycle events -->
    </applicationListeners>

    <!--
        Project-level listeners.
    -->
    <projectListeners>
        <listener
            class="com.anthropic.claudecode.listeners.ProjectOpenListener"
            topic="com.intellij.openapi.project.ProjectManagerListener"/>
    </projectListeners>

    <extensions defaultExtensionNs="com.intellij">
        <!--
            Tool window: appears in the IDE sidebar.
            anchor: "right", "left", "bottom"
            secondary: true = appears in the secondary group (less prominent)
            icon: 13x13 SVG icon for the tool window stripe
        -->
        <toolWindow
            id="Claude Code"
            anchor="right"
            factoryClass="com.anthropic.claudecode.toolwindow.ClaudeCodeToolWindowFactory"
            icon="/icons/claude-toolwindow.svg"
            canCloseContents="false"/>

        <!--
            Project-level services: one instance per open project.
        -->
        <projectService
            serviceImplementation="com.anthropic.claudecode.services.ClaudeCodeService"/>
        <projectService
            serviceImplementation="com.anthropic.claudecode.services.ClaudeCodeSettings"/>

        <!--
            Settings page: appears under Settings > Tools > Claude Code.
        -->
        <projectConfigurable
            instance="com.anthropic.claudecode.settings.ClaudeCodeConfigurable"
            displayName="Claude Code"
            id="com.anthropic.claudecode.settings"
            parentId="tools"/>

        <!--
            Notification group for balloon notifications.
        -->
        <notificationGroup
            id="Claude Code Notifications"
            displayType="BALLOON"/>

        <!--
            Startup activity: runs when a project is opened.
        -->
        <postStartupActivity
            implementation="com.anthropic.claudecode.listeners.ProjectOpenListener"/>
    </extensions>

    <!--
        Actions: menu items, toolbar buttons, keyboard shortcuts.
    -->
    <actions>
        <!--
            Action group in the Tools menu.
        -->
        <group
            id="ClaudeCode.ToolsMenu"
            text="Claude Code"
            description="Claude Code actions"
            popup="true">

            <add-to-group group-id="ToolsMenu" anchor="last"/>

            <action
                id="ClaudeCode.OpenPanel"
                class="com.anthropic.claudecode.actions.OpenPanelAction"
                text="Open Claude Code"
                description="Open the Claude Code tool window"
                icon="/icons/claude-action.svg">
                <keyboard-shortcut
                    keymap="$default"
                    first-keystroke="ctrl shift PERIOD"/>
                <keyboard-shortcut
                    keymap="Mac OS X"
                    first-keystroke="meta shift PERIOD"/>
                <keyboard-shortcut
                    keymap="Mac OS X 10.5+"
                    first-keystroke="meta shift PERIOD"/>
            </action>

            <action
                id="ClaudeCode.NewConversation"
                class="com.anthropic.claudecode.actions.NewConversationAction"
                text="New Conversation"
                description="Start a new Claude conversation">
                <keyboard-shortcut
                    keymap="$default"
                    first-keystroke="ctrl shift COMMA"/>
                <keyboard-shortcut
                    keymap="Mac OS X"
                    first-keystroke="meta shift COMMA"/>
                <keyboard-shortcut
                    keymap="Mac OS X 10.5+"
                    first-keystroke="meta shift COMMA"/>
            </action>

            <separator/>

            <action
                id="ClaudeCode.OpenInTerminal"
                class="com.anthropic.claudecode.actions.OpenTerminalAction"
                text="Open Claude in Terminal"
                description="Open Claude Code in a terminal tab"/>

            <action
                id="ClaudeCode.SendSelection"
                class="com.anthropic.claudecode.actions.SendSelectionAction"
                text="Send Selection to Claude"
                description="Send the current editor selection to Claude"/>
        </group>

        <!--
            Editor context menu (right-click) actions.
        -->
        <group id="ClaudeCode.EditorPopupMenu">
            <add-to-group group-id="EditorPopupMenu" anchor="last"/>
            <separator/>
            <reference ref="ClaudeCode.SendSelection"/>
        </group>
    </actions>
</idea-plugin>
```

### Optional dependency configuration file

```xml
<!-- src/main/resources/META-INF/terminal-support.xml -->
<idea-plugin>
    <!--
        Extensions that only load when the Terminal plugin is available.
        This file is referenced by the optional <depends> in plugin.xml.
    -->
    <extensions defaultExtensionNs="com.intellij">
        <!-- Terminal-specific extensions go here -->
    </extensions>

    <actions>
        <!--
            Actions that require the Terminal plugin.
            These will only be registered if the Terminal plugin is installed.
        -->
    </actions>
</idea-plugin>
```

---

## 7. IntelliJ Platform Dependencies Reference

### Target IDE Selection

In `build.gradle.kts`, inside `dependencies { intellijPlatform { ... } }`:

```kotlin
// Pick ONE target IDE for development:
intellijIdeaCommunity("2024.3.1")     // IntelliJ IDEA Community
intellijIdeaUltimate("2024.3.1")      // IntelliJ IDEA Ultimate
pycharmCommunity("2024.3.1")          // PyCharm Community
pycharmProfessional("2024.3.1")       // PyCharm Professional
webStorm("2024.3.1")                  // WebStorm
goLand("2024.3.1")                    // GoLand
phpStorm("2024.3.1")                  // PhpStorm
clion("2024.3.1")                     // CLion
rider("2024.3.1")                     // Rider
rubyMine("2024.3.1")                  // RubyMine
dataGrip("2024.3.1")                  // DataGrip
androidStudio("2024.2.1.8")           // Android Studio

// Local IDE installation (useful for testing against a specific install):
local("/path/to/ide")
```

### Bundled Plugin Dependencies

Bundled plugins ship with the IDE. Use the plugin **ID** (not the display name):

```kotlin
bundledPlugins(
    "com.intellij.java",                    // Java language support
    "org.jetbrains.plugins.terminal",       // Terminal
    "com.intellij.modules.json",            // JSON support
    "org.jetbrains.plugins.yaml",           // YAML support
    "Git4Idea",                             // Git integration
    "org.intellij.plugins.markdown",        // Markdown support
    "com.intellij.properties",              // Properties files
)
```

### Marketplace Plugin Dependencies

Third-party plugins from JetBrains Marketplace:

```kotlin
plugins(
    "com.example.plugin-id:1.2.3",  // plugin-id:version
)
```

### Test Framework Dependencies

```kotlin
testFramework(TestFrameworkType.Platform)        // Platform test base
testFramework(TestFrameworkType.JUnit5)          // JUnit 5 integration
testFramework(TestFrameworkType.Bundled)         // Bundled test framework
```

---

## 8. Running and Debugging

### Using Gradle Tasks

```bash
# Run the plugin in a sandbox IDE
./gradlew runIde

# Run with additional JVM arguments
./gradlew runIde --jvm-args="-Xmx4g"

# Run tests
./gradlew test

# Run plugin verifier (checks binary compatibility)
./gradlew verifyPlugin

# List all available tasks
./gradlew tasks --group="intellij platform"
```

### IDE Run Configuration

Create `.run/Run IDE with Plugin.run.xml` for easy IntelliJ-based debugging:

```xml
<!-- .run/Run IDE with Plugin.run.xml -->
<component name="ProjectRunConfigurationManager">
    <configuration
        default="false"
        name="Run IDE with Plugin"
        type="GradleRunConfiguration"
        factoryName="Gradle">
        <ExternalSystemSettings>
            <option name="executionName"/>
            <option name="externalProjectPath" value="$PROJECT_DIR$"/>
            <option name="externalSystemIdString" value="GRADLE"/>
            <option name="scriptParameters" value=""/>
            <option name="taskDescriptions">
                <list/>
            </option>
            <option name="taskNames">
                <list>
                    <option value="runIde"/>
                </list>
            </option>
            <option name="vmOptions" value=""/>
        </ExternalSystemSettings>
        <GradleScriptDebugEnabled>true</GradleScriptDebugEnabled>
        <method v="2"/>
    </configuration>
</component>
```

### Sandbox IDE Configuration

The sandbox IDE is a separate IntelliJ installation used for testing:

- **Location:** `build/idea-sandbox/`
- **Config:** `build/idea-sandbox/config/`
- **System:** `build/idea-sandbox/system/`
- **Plugins:** `build/idea-sandbox/plugins/`
- **Log files:** `build/idea-sandbox/system/log/idea.log`

To customize the sandbox:

```kotlin
// In build.gradle.kts
tasks {
    runIde {
        // Use a different IDE for the sandbox
        // (by default it uses the target IDE from dependencies)
        jvmArgs("-Xmx2g", "-Xms512m")

        // Enable debug logging for your plugin
        systemProperty(
            "idea.log.trace.categories",
            "#com.anthropic.claudecode"
        )

        // Enable internal mode (extra developer tools in the IDE)
        systemProperty("idea.is.internal", "true")
    }

    // Copy webview resources to the sandbox
    prepareSandbox {
        from("src/main/resources/webview") {
            into("${project.name}/webview")
        }
    }
}
```

---

## 9. Building and Publishing

### Build the Plugin Distribution

```bash
# Build the plugin ZIP (distributable artifact)
./gradlew buildPlugin

# Output location:
# build/distributions/claude-code-intellij-0.1.0.zip
```

The output ZIP can be installed in any compatible JetBrains IDE via:
**Settings > Plugins > Gear icon > Install Plugin from Disk...**

### Sign the Plugin

Plugin signing is required for JetBrains Marketplace distribution:

```bash
# Generate a key pair (one-time setup)
# See: https://plugins.jetbrains.com/docs/intellij/plugin-signing.html

# Sign during build (reads from environment variables)
CERTIFICATE_CHAIN="..." PRIVATE_KEY="..." PRIVATE_KEY_PASSWORD="..." \
  ./gradlew signPlugin
```

### Publish to JetBrains Marketplace

```bash
# Publish (requires PUBLISH_TOKEN environment variable)
PUBLISH_TOKEN="your-marketplace-token" \
  ./gradlew publishPlugin
```

### Verify Plugin Compatibility

```bash
# Run IntelliJ Plugin Verifier
./gradlew verifyPlugin

# This checks:
# - Binary compatibility with target IDE versions
# - Usage of deprecated/removed APIs
# - Plugin descriptor correctness
```

---

## 10. GitHub Actions CI Workflow

```yaml
# .github/workflows/build.yml

name: Build Plugin

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    name: Build & Verify
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '21'

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v4
        with:
          gradle-home-cache-cleanup: true

      - name: Build plugin
        run: ./gradlew buildPlugin

      - name: Run tests
        run: ./gradlew test

      - name: Verify plugin descriptor
        run: ./gradlew verifyPluginConfiguration

      - name: Run Plugin Verifier
        run: ./gradlew verifyPlugin

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: plugin-distribution
          path: build/distributions/*.zip

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: build/reports/tests/

  # Optional: Publish to Marketplace on release tags
  publish:
    name: Publish to Marketplace
    needs: build
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    timeout-minutes: 15

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '21'

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v4

      - name: Publish plugin
        env:
          PUBLISH_TOKEN: ${{ secrets.JETBRAINS_MARKETPLACE_TOKEN }}
          CERTIFICATE_CHAIN: ${{ secrets.CERTIFICATE_CHAIN }}
          PRIVATE_KEY: ${{ secrets.PRIVATE_KEY }}
          PRIVATE_KEY_PASSWORD: ${{ secrets.PRIVATE_KEY_PASSWORD }}
        run: ./gradlew publishPlugin
```

---

## 11. Gradle Wrapper Configuration

```properties
# gradle/wrapper/gradle-wrapper.properties

distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.12-all.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
```

---

## 12. Complete Dependency Cheat Sheet

### `intellijPlatform { }` Repository Functions

```kotlin
repositories {
    intellijPlatform {
        // All default JetBrains repositories (recommended)
        defaultRepositories()

        // Or configure individually:
        releases()           // Stable releases
        snapshots()          // Nightly/snapshot builds
        marketplace()        // JetBrains Marketplace plugins
        localPlatformArtifacts() // Local IDE installations

        // IntelliJ CDN (binary releases)
        intellijDependencies()

        // Custom JetBrains Maven repository
        jetbrainsRuntime()
    }
}
```

### All `intellijPlatform { }` Dependency Functions

```kotlin
dependencies {
    intellijPlatform {
        // --- Target IDE (pick one) ---
        intellijIdeaCommunity("version")
        intellijIdeaUltimate("version")
        pycharmCommunity("version")
        pycharmProfessional("version")
        webStorm("version")
        goLand("version")
        phpStorm("version")
        clion("version")
        rider("version")
        rubyMine("version")
        dataGrip("version")
        androidStudio("version")
        local("/path/to/ide")

        // --- Plugin dependencies ---
        bundledPlugins("pluginId1", "pluginId2")  // Ship with the IDE
        plugins("pluginId:version")                // From Marketplace

        // --- Build tools ---
        instrumentationTools()  // Required for form-based UI
        pluginVerifier()        // Plugin compatibility checker
        zipSigner()             // ZIP distribution signer

        // --- Test frameworks ---
        testFramework(TestFrameworkType.Platform)
        testFramework(TestFrameworkType.JUnit5)
        testFramework(TestFrameworkType.Bundled)
    }
}
```

### Key Gradle IntelliJ Platform Plugin Tasks

| Task | Description |
|------|-------------|
| `runIde` | Launch a sandbox IDE with the plugin installed |
| `buildPlugin` | Build the plugin distribution ZIP |
| `prepareSandbox` | Prepare the sandbox directory |
| `patchPluginXml` | Patch plugin.xml with values from build script |
| `signPlugin` | Sign the plugin distribution |
| `publishPlugin` | Publish to JetBrains Marketplace |
| `verifyPlugin` | Verify compatibility with target IDEs |
| `verifyPluginConfiguration` | Validate plugin configuration |
| `verifyPluginProjectConfiguration` | Validate project configuration |
| `verifyPluginStructure` | Validate plugin ZIP structure |
| `instrumentCode` | Instrument compiled classes |
| `buildSearchableOptions` | Build searchable options index |
| `jarSearchableOptions` | Package searchable options |
| `listProductsReleases` | List available IDE releases |
| `printBundledPlugins` | List bundled plugins in the target IDE |
| `printProductsReleases` | Print available product releases |

---

## 13. Bootstrapping the Project from Scratch

Here is the minimal set of commands to create a new IntelliJ plugin project:

```bash
# 1. Create project directory
mkdir claude-code-intellij && cd claude-code-intellij

# 2. Initialize Gradle wrapper
gradle wrapper --gradle-version=8.12 --distribution-type=all

# 3. Create directory structure
mkdir -p src/main/kotlin/com/anthropic/claudecode/{actions,listeners,services,settings,toolwindow}
mkdir -p src/main/resources/META-INF
mkdir -p src/main/resources/icons
mkdir -p src/test/kotlin/com/anthropic/claudecode
mkdir -p src/test/resources
mkdir -p gradle
mkdir -p .github/workflows
mkdir -p .run

# 4. Create the files listed above:
#    - settings.gradle.kts
#    - gradle/libs.versions.toml
#    - gradle.properties
#    - build.gradle.kts
#    - src/main/resources/META-INF/plugin.xml

# 5. Build and verify
./gradlew buildPlugin

# 6. Run in sandbox IDE
./gradlew runIde
```

---

## 14. Important Notes and Gotchas

### Migration from Plugin 1.x to 2.x

If migrating from `org.jetbrains.intellij` (1.x):

| 1.x (old) | 2.x (new) |
|------------|-----------|
| `id("org.jetbrains.intellij") version "1.x"` | `id("org.jetbrains.intellij.platform") version "2.x"` |
| `intellij { version.set("...") }` | `dependencies { intellijPlatform { intellijIdeaCommunity("...") } }` |
| `intellij { plugins.set(listOf("...")) }` | `dependencies { intellijPlatform { bundledPlugins("...") } }` |
| `intellij { type.set("IC") }` | Use specific function: `intellijIdeaCommunity()` |
| `patchPluginXml { sinceBuild.set("...") }` | `intellijPlatform { pluginConfiguration { ideaVersion { sinceBuild = "..." } } }` |
| `publishPlugin { token.set("...") }` | `intellijPlatform { publishing { token = "..." } }` |
| `signPlugin { ... }` | `intellijPlatform { signing { ... } }` |

### Common Bundled Plugin IDs

| Plugin | ID |
|--------|----|
| Java | `com.intellij.java` |
| Kotlin | `org.jetbrains.kotlin` |
| Terminal | `org.jetbrains.plugins.terminal` |
| Git | `Git4Idea` |
| Markdown | `org.intellij.plugins.markdown` |
| JSON | `com.intellij.modules.json` |
| YAML | `org.jetbrains.plugins.yaml` |
| Properties | `com.intellij.properties` |
| HTTP Client | `com.jetbrains.restClient` |
| Database | `com.intellij.database` |
| Docker | `Docker` |

To find bundled plugin IDs in your target IDE:

```bash
./gradlew printBundledPlugins
```

### Platform Compatibility Matrix

To support ALL JetBrains IDEs:
- Depend on `com.intellij.modules.platform` (most basic, works everywhere)
- Do NOT depend on `com.intellij.modules.java` (only IDEA + Android Studio)
- Use `optional="true"` for IDE-specific features
- Test with `./gradlew verifyPlugin` against multiple IDE versions

### Version Number Formats

```
# Build number format: BRANCH.BUILD.FIX
# Example: 243.21565.193

# Release shorthand: YEAR.MAJOR.MINOR
# Example: 2024.3.1

# In sinceBuild/untilBuild, use the branch number:
# sinceBuild = "243"        -> IntelliJ 2024.3+
# untilBuild = "243.*"      -> IntelliJ 2024.3.x (any patch)
# untilBuild = "251.*"      -> Up to IntelliJ 2025.1.x
# untilBuild = ""           -> No upper bound (not recommended)
```

---

## 15. Minimal Starter Kotlin Files

### `ClaudeCodeToolWindowFactory.kt`

```kotlin
// src/main/kotlin/com/anthropic/claudecode/toolwindow/ClaudeCodeToolWindowFactory.kt
package com.anthropic.claudecode.toolwindow

import com.intellij.openapi.project.DumbAware
import com.intellij.openapi.project.Project
import com.intellij.openapi.wm.ToolWindow
import com.intellij.openapi.wm.ToolWindowFactory
import com.intellij.ui.jcef.JBCefBrowser

class ClaudeCodeToolWindowFactory : ToolWindowFactory, DumbAware {
    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        val contentManager = toolWindow.contentManager
        val browser = JBCefBrowser()

        // Load initial content
        browser.loadHTML(
            """
            <html>
            <head><style>
                body {
                    margin: 0; padding: 16px;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    background: #1e1e1e; color: #d4d4d4;
                }
            </style></head>
            <body>
                <h2>Claude Code</h2>
                <p>Plugin loaded successfully. Initializing...</p>
            </body>
            </html>
            """.trimIndent()
        )

        val content = contentManager.factory.createContent(
            browser.component,
            "Claude Code",
            false
        )
        contentManager.addContent(content)
    }
}
```

### `OpenPanelAction.kt`

```kotlin
// src/main/kotlin/com/anthropic/claudecode/actions/OpenPanelAction.kt
package com.anthropic.claudecode.actions

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.wm.ToolWindowManager

class OpenPanelAction : AnAction() {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val toolWindow = ToolWindowManager.getInstance(project)
            .getToolWindow("Claude Code")
        toolWindow?.show()
    }

    override fun update(e: AnActionEvent) {
        e.presentation.isEnabledAndVisible = e.project != null
    }
}
```

### `ClaudeCodeService.kt`

```kotlin
// src/main/kotlin/com/anthropic/claudecode/services/ClaudeCodeService.kt
package com.anthropic.claudecode.services

import com.intellij.openapi.components.Service
import com.intellij.openapi.diagnostic.logger
import com.intellij.openapi.project.Project

@Service(Service.Level.PROJECT)
class ClaudeCodeService(private val project: Project) {
    private val log = logger<ClaudeCodeService>()

    init {
        log.info("Claude Code service initialized for project: ${project.name}")
    }

    companion object {
        fun getInstance(project: Project): ClaudeCodeService =
            project.getService(ClaudeCodeService::class.java)
    }
}
```

### `ProjectOpenListener.kt`

```kotlin
// src/main/kotlin/com/anthropic/claudecode/listeners/ProjectOpenListener.kt
package com.anthropic.claudecode.listeners

import com.intellij.openapi.diagnostic.logger
import com.intellij.openapi.project.Project
import com.intellij.openapi.startup.ProjectActivity

class ProjectOpenListener : ProjectActivity {
    private val log = logger<ProjectOpenListener>()

    override suspend fun execute(project: Project) {
        log.info("Claude Code: project opened - ${project.name}")
    }
}
```

---

## 16. Reference Links

- **Gradle IntelliJ Platform Plugin 2.x docs:**
  https://plugins.jetbrains.com/docs/intellij/tools-intellij-platform-gradle-plugin.html
- **IntelliJ Platform Plugin Template (GitHub):**
  https://github.com/JetBrains/intellij-platform-plugin-template
- **Gradle IntelliJ Platform Plugin GitHub:**
  https://github.com/JetBrains/intellij-platform-gradle-plugin
- **IntelliJ Platform SDK docs:**
  https://plugins.jetbrains.com/docs/intellij/welcome.html
- **Plugin Descriptor (plugin.xml) docs:**
  https://plugins.jetbrains.com/docs/intellij/plugin-configuration-file.html
- **JetBrains Marketplace:**
  https://plugins.jetbrains.com/
- **Plugin Signing docs:**
  https://plugins.jetbrains.com/docs/intellij/plugin-signing.html
- **Plugin Verifier:**
  https://plugins.jetbrains.com/docs/intellij/verifying-plugin-compatibility.html
