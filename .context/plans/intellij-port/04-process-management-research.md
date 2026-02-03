# Process Management Research for IntelliJ Plugin

## Use Case

Spawning the Claude CLI binary as a child process, communicating with it over stdin/stdout using a line-delimited JSON protocol, and managing its lifecycle within an IntelliJ plugin. This document covers best practices as of 2025 based on the IntelliJ Platform SDK, Kotlin idioms, and production plugin patterns.

---

## 1. GeneralCommandLine vs ProcessBuilder

### Recommendation: Use `GeneralCommandLine`

IntelliJ provides `com.intellij.execution.configurations.GeneralCommandLine` as the preferred abstraction over `java.lang.ProcessBuilder`. You should always use `GeneralCommandLine` in IntelliJ plugin code.

### Why GeneralCommandLine is preferred

| Feature | GeneralCommandLine | ProcessBuilder |
|---------|-------------------|----------------|
| Platform charset handling | Automatic (handles Windows codepages) | Manual |
| Environment variable merging | Built-in `withEnvironment()` | Manual merge with `environment()` |
| Working directory | `withWorkDirectory()` | `directory()` |
| Escaped command display | `getCommandLineString()` for logging | Must construct manually |
| PTY support | `PtyCommandLine` subclass | Not available |
| IntelliJ process handler integration | Direct via `OSProcessHandler(commandLine)` | Must call `start()` first, then wrap |
| Error stream redirect | `withRedirectErrorStream()` | `redirectErrorStream()` |
| Character encoding | `withCharset()` | Not available |
| Validation | `createProcess()` throws with diagnostics | Opaque exceptions |

### GeneralCommandLine API

```kotlin
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.configurations.PtyCommandLine

// Basic usage
val commandLine = GeneralCommandLine()
    .withExePath("/usr/local/bin/claude")
    .withParameters("--output-format", "stream-json", "--verbose")
    .withWorkDirectory(project.basePath)
    .withCharset(Charsets.UTF_8)
    .withRedirectErrorStream(false) // keep stderr separate for error detection
    .withEnvironment("CLAUDE_API_KEY", apiKey)
    .withEnvironment("TERM", "dumb")

// For terminal/PTY scenarios (not our case, but good to know)
val ptyCommandLine = PtyCommandLine()
    .withExePath("/usr/local/bin/claude")
    .withInitialColumns(120)
    .withInitialRows(40)
    .withConsoleMode(true)

// Creating the process
try {
    val process: Process = commandLine.createProcess()
} catch (e: ExecutionException) {
    // GeneralCommandLine throws ExecutionException with useful diagnostics:
    // - binary not found
    // - permission denied
    // - working directory doesn't exist
    LOG.error("Failed to start Claude CLI: ${e.message}")
    LOG.error("Command was: ${commandLine.commandLineString}")
}
```

### Key Details

- `GeneralCommandLine.createProcess()` internally creates a `ProcessBuilder`, configures it, and calls `start()`. It adds platform-specific handling (e.g., Windows console codepage workarounds).
- The `getCommandLineString()` method returns a properly escaped string for logging/debugging.
- `withParentEnvironmentType(ParentEnvironmentType.CONSOLE)` inherits the user's shell environment (the default). Use `ParentEnvironmentType.NONE` for a clean environment.

```kotlin
import com.intellij.execution.configurations.GeneralCommandLine.ParentEnvironmentType

// Inherit user's full shell environment (default, recommended)
commandLine.withParentEnvironmentType(ParentEnvironmentType.CONSOLE)

// Start from clean environment (rarely needed)
commandLine.withParentEnvironmentType(ParentEnvironmentType.NONE)
```

---

## 2. OSProcessHandler and ProcessHandler Hierarchy

### The ProcessHandler Class Hierarchy

```
ProcessHandler (abstract)
  |
  +-- BaseProcessHandler<T : Process>
  |     |
  |     +-- BaseOSProcessHandler
  |     |     |
  |     |     +-- OSProcessHandler          <-- Most commonly used
  |     |     |     |
  |     |     |     +-- KillableProcessHandler  <-- Recommended for CLI tools
  |     |     |     |     |
  |     |     |     |     +-- KillableColoredProcessHandler
  |     |     |     |
  |     |     |     +-- ColoredProcessHandler
  |     |     |
  |     |     +-- CapturingProcessHandler   <-- For short-lived "run and capture output"
  |     |
  |     +-- (custom implementations)
  |
  +-- NopProcessHandler  <-- Stub for testing
```

### Which to use?

| Handler | Use Case |
|---------|----------|
| `OSProcessHandler` | General-purpose long-running process management |
| `KillableProcessHandler` | CLI tools that should be force-killed on stop (our use case) |
| `KillableColoredProcessHandler` | Same as above, but with ANSI color parsing |
| `ColoredProcessHandler` | When you need ANSI escape code handling |
| `CapturingProcessHandler` | Short-lived commands where you want to capture all output |

### Recommendation: Use `KillableProcessHandler`

For the Claude CLI, `KillableProcessHandler` is the right choice because:
1. It sends SIGTERM first, then SIGKILL after a timeout (graceful shutdown).
2. It integrates with IntelliJ's process lifecycle (stop button in tool windows).
3. It handles output streaming via `ProcessListener`.

### Complete OSProcessHandler/KillableProcessHandler Usage

```kotlin
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.KillableProcessHandler
import com.intellij.execution.process.ProcessAdapter
import com.intellij.execution.process.ProcessEvent
import com.intellij.execution.process.ProcessOutputType
import com.intellij.openapi.util.Key

class ClaudeProcessManager(private val project: Project) : Disposable {

    private var processHandler: KillableProcessHandler? = null

    fun startProcess(): KillableProcessHandler {
        val commandLine = GeneralCommandLine()
            .withExePath(getClaudeBinaryPath())
            .withParameters("--output-format", "stream-json")
            .withWorkDirectory(project.basePath)
            .withCharset(Charsets.UTF_8)
            .withEnvironment(buildEnvironment())

        val handler = KillableProcessHandler(commandLine)

        // IMPORTANT: This tells the handler to convert output to text line-by-line
        handler.setShouldDestroyProcessRecursively(true)

        handler.addProcessListener(object : ProcessAdapter() {
            override fun onTextAvailable(event: ProcessEvent, outputType: Key<*>) {
                when (outputType) {
                    ProcessOutputType.STDOUT -> handleStdoutLine(event.text)
                    ProcessOutputType.STDERR -> handleStderrLine(event.text)
                }
            }

            override fun processTerminated(event: ProcessEvent) {
                val exitCode = event.exitCode
                LOG.info("Claude process terminated with exit code: $exitCode")
                handleProcessExit(exitCode)
            }

            override fun processNotStarted() {
                LOG.error("Claude process failed to start")
                notifyUser("Failed to start Claude CLI", NotificationType.ERROR)
            }
        })

        // IMPORTANT: Must call startNotify() to begin reading output
        handler.startNotify()

        processHandler = handler
        return handler
    }

    fun sendMessage(json: String) {
        val handler = processHandler ?: throw IllegalStateException("Process not started")
        val outputStream = handler.processInput
            ?: throw IllegalStateException("Process stdin not available")

        // Write line-delimited JSON
        outputStream.write((json + "\n").toByteArray(Charsets.UTF_8))
        outputStream.flush()
    }

    fun stopProcess() {
        processHandler?.let { handler ->
            if (!handler.isProcessTerminated) {
                // KillableProcessHandler sends SIGTERM, then SIGKILL after timeout
                handler.killProcess()
            }
        }
        processHandler = null
    }

    val isRunning: Boolean
        get() = processHandler?.let { !it.isProcessTerminated } ?: false

    override fun dispose() {
        stopProcess()
    }
}
```

### ProcessHandler Key Methods

```kotlin
// Starting and stopping
handler.startNotify()           // Begin processing output (MUST call after construction)
handler.destroyProcess()        // Send SIGTERM (graceful)
handler.killProcess()           // Send SIGKILL (force) - KillableProcessHandler only

// State queries
handler.isProcessTerminated     // Process has exited
handler.isProcessTerminating    // SIGTERM sent, waiting for exit
handler.exitCode                // Exit code (null if still running)

// I/O
handler.processInput            // OutputStream to write to stdin
handler.process                 // The underlying java.lang.Process object

// Listeners
handler.addProcessListener(listener)
handler.removeProcessListener(listener)
```

### CapturingProcessHandler for One-Shot Commands

For short-lived commands (e.g., checking Claude CLI version), use `CapturingProcessHandler`:

```kotlin
import com.intellij.execution.process.CapturingProcessHandler
import com.intellij.execution.process.ProcessOutput

fun getClaudeVersion(): String? {
    val commandLine = GeneralCommandLine()
        .withExePath(getClaudeBinaryPath())
        .withParameters("--version")
        .withCharset(Charsets.UTF_8)

    val handler = CapturingProcessHandler(commandLine)
    // Runs synchronously with timeout - use on background thread only!
    val output: ProcessOutput = handler.runProcess(timeoutInMilliseconds = 10_000)

    return when {
        output.isTimeout -> {
            LOG.warn("Claude --version timed out")
            null
        }
        output.exitCode != 0 -> {
            LOG.warn("Claude --version failed: ${output.stderr}")
            null
        }
        else -> output.stdout.trim()
    }
}
```

---

## 3. Threading Model

### The Golden Rules

1. **Never block the EDT** (Event Dispatch Thread / UI thread).
2. **Never modify the UI from a background thread** (use `invokeLater` to post to EDT).
3. **Never do I/O on the EDT** (file reads, network, process communication).
4. **Read actions** can run on any thread but must be wrapped in `ReadAction.run {}`.
5. **Write actions** must run on the EDT and be wrapped in `WriteAction.run {}`.

### Threading Options (Ranked by Preference for 2025)

#### Option 1: Kotlin Coroutines (Recommended - see Section 4)

```kotlin
// Best for 2025 IntelliJ plugins - see Section 4 for details
cs.launch(Dispatchers.IO) {
    // Process I/O here
}
```

#### Option 2: `ApplicationManager.getApplication().executeOnPooledThread()`

The traditional IntelliJ way to run background work. Uses IntelliJ's managed thread pool.

```kotlin
import com.intellij.openapi.application.ApplicationManager

// Fire-and-forget background task
ApplicationManager.getApplication().executeOnPooledThread {
    // This runs on IntelliJ's pooled thread
    // Safe for I/O, network calls, process communication
    val line = bufferedReader.readLine()

    // To update UI from here:
    ApplicationManager.getApplication().invokeLater {
        // This runs on EDT - safe to update UI
        updateToolWindowContent(line)
    }
}

// With a Future result
val future: Future<String> = ApplicationManager.getApplication().executeOnPooledThread(
    Callable<String> {
        // Background work that returns a value
        process.inputStream.bufferedReader().readLine()
    }
)
```

#### Option 3: `Task.Backgroundable` for User-Visible Progress

```kotlin
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task

// Shows progress bar in IDE status bar
object : Task.Backgroundable(project, "Starting Claude CLI", true) {
    override fun run(indicator: ProgressIndicator) {
        indicator.text = "Launching Claude..."
        indicator.isIndeterminate = true

        startClaudeProcess()

        indicator.text = "Claude is ready"
    }

    override fun onSuccess() {
        // Runs on EDT after run() completes successfully
        notifyUser("Claude started successfully", NotificationType.INFORMATION)
    }

    override fun onThrowable(error: Throwable) {
        // Runs on EDT if run() throws
        notifyUser("Failed to start Claude: ${error.message}", NotificationType.ERROR)
    }
}.queue()
```

#### Option 4: `ReadAction.nonBlocking()` for Read-Access Work

```kotlin
import com.intellij.openapi.application.ReadAction
import com.intellij.openapi.project.DumbService

// For tasks that need to read IntelliJ's data model
ReadAction.nonBlocking(Callable {
    // Read PSI, VFS, indices, etc. here
    val file = LocalFileSystem.getInstance().findFileByPath(path)
    file?.contentsToByteArray()
})
    .inSmartMode(project)          // Wait for indexing to complete
    .expireWith(disposable)        // Cancel when disposable is disposed
    .finishOnUiThread(ModalityState.defaultModalityState()) { bytes ->
        // Process result on EDT
        handleFileContent(bytes)
    }
    .submit(AppExecutorUtil.getAppExecutorService())
```

### Process I/O Threading Pattern (Without Coroutines)

```kotlin
class ClaudeProcessIO(
    private val processHandler: KillableProcessHandler,
    private val project: Project
) : Disposable {

    private val outputBuffer = StringBuilder()
    @Volatile
    private var isDisposed = false

    /**
     * Start the stdout reader on a pooled thread.
     * ProcessHandler.addProcessListener already runs callbacks on a pooled thread,
     * so normally you don't need a separate thread for reading.
     * But if you need raw stream access (e.g., for buffered JSON parsing), do this:
     */
    fun startRawStdoutReader() {
        ApplicationManager.getApplication().executeOnPooledThread {
            try {
                val reader = processHandler.process.inputStream.bufferedReader(Charsets.UTF_8)
                while (!isDisposed && !processHandler.isProcessTerminated) {
                    val line = reader.readLine() ?: break
                    handleJsonLine(line)
                }
            } catch (e: IOException) {
                if (!isDisposed) {
                    LOG.warn("Error reading Claude stdout", e)
                }
            }
        }
    }

    /**
     * Write to stdin - must NOT be called from EDT if the write could block.
     * In practice, pipe writes are buffered and rarely block for small messages,
     * but it is still best practice to write from a background thread.
     */
    fun writeToStdin(json: String) {
        ApplicationManager.getApplication().executeOnPooledThread {
            try {
                val stdin = processHandler.processInput ?: return@executeOnPooledThread
                synchronized(stdin) {
                    stdin.write(json.toByteArray(Charsets.UTF_8))
                    stdin.write('\n'.code)
                    stdin.flush()
                }
            } catch (e: IOException) {
                if (!isDisposed) {
                    LOG.warn("Error writing to Claude stdin", e)
                    handleProcessCommunicationError(e)
                }
            }
        }
    }

    private fun handleJsonLine(line: String) {
        // Parse JSON on the background thread
        val message = try {
            JsonParser.parse(line)
        } catch (e: Exception) {
            LOG.warn("Invalid JSON from Claude: $line", e)
            return
        }

        // Post UI updates to EDT
        ApplicationManager.getApplication().invokeLater {
            if (!project.isDisposed) {
                updateUI(message)
            }
        }
    }

    override fun dispose() {
        isDisposed = true
    }
}
```

---

## 4. Kotlin Coroutines in IntelliJ Plugins (2025)

### Status: Recommended for New Plugins

As of IntelliJ 2024.x and 2025.x, Kotlin coroutines are the **recommended** approach for asynchronous work in IntelliJ plugins. The platform provides first-class coroutine support through its own `CoroutineScope` management tied to component lifecycles.

### Key Concepts

1. **`service` coroutine scope**: IntelliJ services that extend specific base classes get a `coroutineScope` automatically.
2. **`Dispatchers.EDT`**: IntelliJ provides a special dispatcher for the Event Dispatch Thread.
3. **`Dispatchers.Default` / `Dispatchers.IO`**: Standard Kotlin dispatchers work as expected.
4. **`readAction {}`**: Suspending read action (replaces `ReadAction.nonBlocking()`).
5. **`writeAction {}`**: Suspending write action.
6. **Structured concurrency**: Scopes are cancelled when the parent component (project, application) is disposed.

### Setting Up Coroutine Support

In `build.gradle.kts`:
```kotlin
dependencies {
    // The IntelliJ Platform SDK includes kotlinx-coroutines
    // No need to add it separately in most cases.
    // If you need a specific version:
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
}
```

In `plugin.xml`:
```xml
<!-- Kotlin coroutines support is included with the platform since 2024.1+ -->
<!-- No special plugin dependency needed -->
```

### Coroutine Scope in Project Services

```kotlin
import com.intellij.openapi.components.Service
import com.intellij.openapi.project.Project
import kotlinx.coroutines.*

/**
 * Project-scoped service with coroutine support.
 *
 * IMPORTANT: In IntelliJ 2024.1+, @Service-annotated project services
 * that accept a CoroutineScope parameter get a scope tied to the project lifecycle.
 * When the project closes, the scope is cancelled automatically.
 */
@Service(Service.Level.PROJECT)
class ClaudeService(
    private val project: Project,
    private val cs: CoroutineScope  // Injected by the platform, cancelled on project close
) {
    private var processHandler: KillableProcessHandler? = null
    private var stdinWriter: Job? = null
    private var stdoutReader: Job? = null

    // Channel for outgoing messages (written to stdin)
    private val outgoingMessages = Channel<String>(Channel.BUFFERED)

    // SharedFlow for incoming messages (read from stdout)
    private val _incomingMessages = MutableSharedFlow<JsonMessage>(
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val incomingMessages: SharedFlow<JsonMessage> = _incomingMessages.asSharedFlow()

    fun start() {
        cs.launch {
            startClaudeProcess()
        }
    }

    private suspend fun startClaudeProcess() {
        val commandLine = GeneralCommandLine()
            .withExePath(getClaudeBinaryPath())
            .withParameters("--output-format", "stream-json")
            .withWorkDirectory(project.basePath)
            .withCharset(Charsets.UTF_8)
            .withEnvironment(buildEnvironment())

        val handler = withContext(Dispatchers.IO) {
            KillableProcessHandler(commandLine).also {
                it.setShouldDestroyProcessRecursively(true)
                it.startNotify()
            }
        }
        processHandler = handler

        // Launch stdout reader coroutine
        stdoutReader = cs.launch(Dispatchers.IO) {
            readStdout(handler)
        }

        // Launch stdin writer coroutine
        stdinWriter = cs.launch(Dispatchers.IO) {
            writeStdin(handler)
        }

        // Monitor process lifecycle
        cs.launch {
            monitorProcess(handler)
        }
    }

    private suspend fun readStdout(handler: KillableProcessHandler) {
        try {
            val reader = handler.process.inputStream.bufferedReader(Charsets.UTF_8)
            // Use lineSequence for efficient line-by-line reading
            reader.useLines { lines ->
                for (line in lines) {
                    if (!isActive) break  // Check cancellation
                    if (line.isBlank()) continue

                    try {
                        val message = parseJsonMessage(line)
                        _incomingMessages.emit(message)
                    } catch (e: Exception) {
                        LOG.warn("Invalid JSON from Claude: $line", e)
                    }
                }
            }
        } catch (e: CancellationException) {
            throw e  // Always rethrow CancellationException
        } catch (e: IOException) {
            LOG.info("Claude stdout stream closed", e)
        }
    }

    private suspend fun writeStdin(handler: KillableProcessHandler) {
        val stdin = handler.processInput ?: run {
            LOG.error("Process stdin not available")
            return
        }

        try {
            for (message in outgoingMessages) {
                if (!isActive) break
                stdin.write(message.toByteArray(Charsets.UTF_8))
                stdin.write('\n'.code)
                stdin.flush()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: IOException) {
            if (isActive) {
                LOG.warn("Error writing to Claude stdin", e)
            }
        }
    }

    private suspend fun monitorProcess(handler: KillableProcessHandler) {
        // Suspend until the process terminates
        // We poll because ProcessHandler doesn't have a suspending wait API
        while (isActive && !handler.isProcessTerminated) {
            delay(500)
        }

        if (isActive) {
            val exitCode = handler.exitCode ?: -1
            LOG.info("Claude process exited with code: $exitCode")

            withContext(Dispatchers.EDT) {
                handleProcessExit(exitCode)
            }
        }
    }

    /**
     * Send a message to the Claude process.
     * Safe to call from any thread/coroutine.
     */
    suspend fun sendMessage(message: JsonMessage) {
        val json = serializeMessage(message)
        outgoingMessages.send(json)
    }

    /**
     * Non-suspending version for Java callers or fire-and-forget
     */
    fun sendMessageAsync(message: JsonMessage) {
        cs.launch {
            sendMessage(message)
        }
    }

    fun stop() {
        stdinWriter?.cancel()
        stdoutReader?.cancel()
        outgoingMessages.close()
        processHandler?.killProcess()
        processHandler = null
    }

    companion object {
        private val LOG = logger<ClaudeService>()

        fun getInstance(project: Project): ClaudeService =
            project.service<ClaudeService>()
    }
}
```

### Dispatchers.EDT (IntelliJ-Specific)

```kotlin
import com.intellij.openapi.application.EDT
import kotlinx.coroutines.Dispatchers

// Switch to EDT for UI updates
cs.launch {
    val data = withContext(Dispatchers.IO) {
        // Background I/O work
        fetchData()
    }

    withContext(Dispatchers.EDT) {
        // Update UI on the Event Dispatch Thread
        toolWindow.updateContent(data)
    }
}
```

### Suspending Read/Write Actions

```kotlin
import com.intellij.openapi.application.readAction
import com.intellij.openapi.application.writeAction
import com.intellij.openapi.application.readAndWriteAction

// Suspending read action - does not block the calling thread
cs.launch {
    val fileContent = readAction {
        // Access PSI, VFS, indices
        val file = LocalFileSystem.getInstance().findFileByPath(path)
        file?.contentsToByteArray()?.toString(Charsets.UTF_8)
    }

    // Process the content...
}

// Suspending write action
cs.launch {
    writeAction {
        // Modify PSI, documents, etc.
        document.setText(newContent)
    }
}

// Combined read-then-write (avoids race conditions)
cs.launch {
    readAndWriteAction {
        val content = readAction {
            document.text
        }
        val modified = processContent(content)
        writeAction {
            document.setText(modified)
        }
    }
}
```

### Scoping Coroutines to Lifecycle (Important Patterns)

```kotlin
// Pattern 1: Service with injected scope (preferred in 2024.1+)
@Service(Service.Level.PROJECT)
class MyService(
    private val project: Project,
    private val cs: CoroutineScope  // Auto-cancelled on project close
)

// Pattern 2: Manual scope management with Disposable
class MyComponent(parentDisposable: Disposable) : Disposable {
    private val cs = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    init {
        Disposer.register(parentDisposable, this)
    }

    override fun dispose() {
        cs.cancel("Component disposed")
    }
}

// Pattern 3: For tool window factories
class ClaudeToolWindowFactory : ToolWindowFactory {
    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        // toolWindow.disposable is cancelled when the tool window closes
        val cs = CoroutineScope(
            SupervisorJob() + Dispatchers.Default + CoroutineName("ClaudeToolWindow")
        )
        Disposer.register(toolWindow.disposable, Disposable { cs.cancel() })

        cs.launch {
            // Coroutine work tied to tool window lifecycle
        }
    }
}
```

---

## 5. Process Lifecycle Management

### Tying Process Lifecycle to Project Open/Close

```kotlin
import com.intellij.openapi.components.Service
import com.intellij.openapi.project.Project
import com.intellij.openapi.startup.ProjectActivity
import kotlinx.coroutines.*

/**
 * ProjectActivity runs after the project is opened.
 * Use this to auto-start the Claude process when a project opens.
 *
 * Register in plugin.xml:
 *   <extensions defaultExtensionNs="com.intellij">
 *       <postStartupActivity implementation="com.anthropic.claude.ClaudeStartupActivity"/>
 *   </extensions>
 *
 * NOTE: In 2024.1+, use `ProjectActivity` (suspending) instead of the older
 * `StartupActivity` (non-suspending).
 */
class ClaudeStartupActivity : ProjectActivity {
    override suspend fun execute(project: Project) {
        // This runs on a background thread after project is fully loaded
        val service = ClaudeService.getInstance(project)

        // Only auto-start if user has enabled it in settings
        val settings = ClaudeSettings.getInstance(project)
        if (settings.state.autoStartOnProjectOpen) {
            service.start()
        }
    }
}

/**
 * Full lifecycle management service
 */
@Service(Service.Level.PROJECT)
class ClaudeProcessLifecycle(
    private val project: Project,
    private val cs: CoroutineScope
) : Disposable {

    enum class ProcessState {
        STOPPED,
        STARTING,
        RUNNING,
        STOPPING,
        CRASHED,
        RESTARTING
    }

    private val _state = MutableStateFlow(ProcessState.STOPPED)
    val state: StateFlow<ProcessState> = _state.asStateFlow()

    private var processHandler: KillableProcessHandler? = null
    private var restartCount = 0
    private val maxRestarts = 5
    private val restartDelayMs = 2000L

    fun start() {
        if (_state.value == ProcessState.RUNNING || _state.value == ProcessState.STARTING) {
            LOG.info("Process already running or starting, ignoring start request")
            return
        }

        cs.launch {
            doStart()
        }
    }

    private suspend fun doStart() {
        _state.value = ProcessState.STARTING

        try {
            val commandLine = buildCommandLine()
            val handler = withContext(Dispatchers.IO) {
                KillableProcessHandler(commandLine).also {
                    it.setShouldDestroyProcessRecursively(true)
                }
            }

            processHandler = handler

            // Add termination listener
            handler.addProcessListener(object : ProcessAdapter() {
                override fun processTerminated(event: ProcessEvent) {
                    cs.launch {
                        handleTermination(event.exitCode)
                    }
                }
            })

            handler.startNotify()
            _state.value = ProcessState.RUNNING
            restartCount = 0  // Reset on successful start

            LOG.info("Claude process started successfully (PID: ${handler.process.pid()})")

        } catch (e: Exception) {
            LOG.error("Failed to start Claude process", e)
            _state.value = ProcessState.CRASHED

            withContext(Dispatchers.EDT) {
                notifyError("Failed to start Claude CLI: ${e.message}")
            }
        }
    }

    private suspend fun handleTermination(exitCode: Int) {
        LOG.info("Claude process terminated with exit code: $exitCode")

        when {
            _state.value == ProcessState.STOPPING -> {
                // Expected shutdown
                _state.value = ProcessState.STOPPED
            }
            exitCode == 0 -> {
                // Clean exit (e.g., user said /exit)
                _state.value = ProcessState.STOPPED
            }
            restartCount < maxRestarts -> {
                // Unexpected crash - attempt restart
                _state.value = ProcessState.CRASHED
                restartCount++
                LOG.warn("Claude crashed, attempting restart $restartCount/$maxRestarts")

                withContext(Dispatchers.EDT) {
                    notifyWarning("Claude process crashed (exit code: $exitCode). Restarting...")
                }

                delay(restartDelayMs * restartCount)  // Exponential-ish backoff
                _state.value = ProcessState.RESTARTING
                doStart()
            }
            else -> {
                // Too many crashes
                _state.value = ProcessState.CRASHED
                LOG.error("Claude process crashed too many times, giving up")

                withContext(Dispatchers.EDT) {
                    notifyError(
                        "Claude process crashed repeatedly. " +
                        "Please check the binary and try restarting manually."
                    )
                }
            }
        }
    }

    fun stop() {
        cs.launch {
            doStop()
        }
    }

    private suspend fun doStop() {
        val handler = processHandler ?: return
        if (handler.isProcessTerminated) {
            _state.value = ProcessState.STOPPED
            return
        }

        _state.value = ProcessState.STOPPING

        // Send graceful shutdown message first
        try {
            val stdin = handler.processInput
            if (stdin != null) {
                withContext(Dispatchers.IO) {
                    val shutdownMsg = """{"type":"shutdown"}"""
                    stdin.write((shutdownMsg + "\n").toByteArray(Charsets.UTF_8))
                    stdin.flush()
                }
            }
        } catch (e: IOException) {
            // Process may already be dead
        }

        // Wait briefly for graceful shutdown, then force kill
        withContext(Dispatchers.IO) {
            delay(3000)
            if (!handler.isProcessTerminated) {
                handler.killProcess()
            }
        }

        processHandler = null
        _state.value = ProcessState.STOPPED
    }

    fun restart() {
        cs.launch {
            doStop()
            delay(500)
            restartCount = 0  // Manual restart resets counter
            doStart()
        }
    }

    private fun buildCommandLine(): GeneralCommandLine {
        val settings = ClaudeSettings.getInstance(project)
        return GeneralCommandLine()
            .withExePath(resolveClaudeBinary(settings))
            .withParameters("--output-format", "stream-json", "--verbose")
            .withWorkDirectory(project.basePath)
            .withCharset(Charsets.UTF_8)
            .withEnvironment(buildEnvironment(settings))
    }

    override fun dispose() {
        processHandler?.let { handler ->
            if (!handler.isProcessTerminated) {
                handler.killProcess()
            }
        }
        processHandler = null
    }

    companion object {
        private val LOG = logger<ClaudeProcessLifecycle>()

        fun getInstance(project: Project): ClaudeProcessLifecycle =
            project.service<ClaudeProcessLifecycle>()
    }
}
```

### Project Close Handling

```kotlin
/**
 * VetoableProjectManagerListener can prevent project close if needed.
 *
 * Register in plugin.xml:
 *   <listener class="com.anthropic.claude.ClaudeProjectCloseListener"
 *             topic="com.intellij.openapi.project.ProjectManagerListener"/>
 */
class ClaudeProjectCloseListener : ProjectManagerListener {
    override fun projectClosing(project: Project) {
        // Stop the Claude process when project is closing
        val service = project.serviceIfCreated<ClaudeProcessLifecycle>()
        service?.stop()
    }

    // NOTE: can also override canClose() to veto project close
    // if there's an active Claude session that needs confirmation
}
```

---

## 6. Environment Variable Handling

### Passing Environment Variables to Spawned Processes

```kotlin
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.configurations.GeneralCommandLine.ParentEnvironmentType
import com.intellij.util.EnvironmentUtil

fun buildEnvironment(settings: ClaudeSettings): Map<String, String> {
    val env = mutableMapOf<String, String>()

    // --- Authentication ---
    // API key from settings (if not using OAuth)
    settings.state.apiKey?.let { env["ANTHROPIC_API_KEY"] = it }

    // --- Claude-specific configuration ---
    env["CLAUDE_CODE_IDE"] = "intellij"
    env["CLAUDE_CODE_IDE_VERSION"] = ApplicationInfo.getInstance().fullVersion
    env["CLAUDE_CODE_PLUGIN_VERSION"] = getPluginVersion()

    // --- Terminal behavior ---
    env["TERM"] = "dumb"            // Suppress ANSI escape sequences
    env["NO_COLOR"] = "1"           // Another color suppression standard
    env["FORCE_COLOR"] = "0"        // Disable chalk/kleur color output

    // --- User-configured env vars ---
    for (envVar in settings.state.environmentVariables) {
        env[envVar.name] = envVar.value
    }

    // --- Path augmentation ---
    // Ensure common binary locations are in PATH
    val currentPath = EnvironmentUtil.getValue("PATH") ?: ""
    val extraPaths = listOf(
        "/usr/local/bin",
        "/opt/homebrew/bin",   // macOS Apple Silicon
        System.getProperty("user.home") + "/.local/bin",
        System.getProperty("user.home") + "/.nvm/current/bin"
    )
    env["PATH"] = (extraPaths + currentPath.split(File.pathSeparator))
        .distinct()
        .joinToString(File.pathSeparator)

    return env
}

/**
 * Apply environment to GeneralCommandLine
 */
fun configureCommandLine(
    commandLine: GeneralCommandLine,
    settings: ClaudeSettings
): GeneralCommandLine {
    return commandLine
        // Inherit user's shell environment as the base
        .withParentEnvironmentType(ParentEnvironmentType.CONSOLE)
        // Add our overrides on top
        .withEnvironment(buildEnvironment(settings))
}
```

### Reading the User's Shell Environment

```kotlin
import com.intellij.util.EnvironmentUtil

/**
 * EnvironmentUtil.getEnvironmentMap() reads the user's login shell environment.
 * This is important because IDE processes don't always inherit the full
 * shell environment (especially on macOS where apps are launched from Finder).
 */
fun getShellEnvironment(): Map<String, String> {
    // This calls the login shell to get the full environment
    // It caches the result, so it's efficient to call multiple times
    return EnvironmentUtil.getEnvironmentMap()
}

// Specific value lookup
val homebrewPrefix = EnvironmentUtil.getValue("HOMEBREW_PREFIX")
```

### Platform-Specific Environment Considerations

```kotlin
import com.intellij.openapi.util.SystemInfo

fun getPlatformSpecificEnv(): Map<String, String> {
    val env = mutableMapOf<String, String>()

    when {
        SystemInfo.isMac -> {
            // macOS: Apps launched from Finder don't get shell PATH
            // EnvironmentUtil handles this, but we add common paths as safety
            env["LANG"] = "en_US.UTF-8"  // Ensure UTF-8
        }
        SystemInfo.isLinux -> {
            env["LANG"] = "en_US.UTF-8"
        }
        SystemInfo.isWindows -> {
            // Windows: Use USERPROFILE-based paths
            val userProfile = System.getenv("USERPROFILE") ?: ""
            env["APPDATA"] = System.getenv("APPDATA") ?: "$userProfile\\AppData\\Roaming"
        }
    }

    return env
}
```

---

## 7. Binary Bundling

### Strategy: Bundle Platform-Specific Binaries in Plugin

IntelliJ plugins are distributed as `.zip` files containing a directory structure. Platform-specific binaries should be placed in platform-specific subdirectories.

### Plugin Directory Structure

```
claude-code-intellij/
  lib/
    claude-code-intellij.jar        # Plugin code
  bin/
    darwin-aarch64/
      claude                         # macOS ARM64
    darwin-x86_64/
      claude                         # macOS Intel
    linux-aarch64/
      claude                         # Linux ARM64
    linux-x86_64/
      claude                         # Linux x86_64
    windows-x86_64/
      claude.exe                     # Windows x86_64
```

### Resolving the Correct Binary at Runtime

```kotlin
import com.intellij.ide.plugins.PluginManagerCore
import com.intellij.openapi.extensions.PluginId
import com.intellij.openapi.util.SystemInfo
import java.io.File
import java.nio.file.Files
import java.nio.file.Path

object ClaudeBinaryResolver {
    private val LOG = logger<ClaudeBinaryResolver>()
    private const val PLUGIN_ID = "com.anthropic.claude-code"

    /**
     * Resolution order:
     * 1. User-configured path in settings
     * 2. Bundled binary inside the plugin directory
     * 3. System-installed binary (on PATH)
     */
    fun resolve(settings: ClaudeSettings): String {
        // 1. User override
        settings.state.claudeBinaryPath?.let { path ->
            if (File(path).canExecute()) {
                LOG.info("Using user-configured Claude binary: $path")
                return path
            }
            LOG.warn("User-configured path is not executable: $path")
        }

        // 2. Bundled binary
        getBundledBinaryPath()?.let { path ->
            LOG.info("Using bundled Claude binary: $path")
            return path
        }

        // 3. System PATH
        getSystemBinaryPath()?.let { path ->
            LOG.info("Using system-installed Claude binary: $path")
            return path
        }

        throw ClaudeBinaryNotFoundException(
            "Could not find Claude CLI binary. " +
            "Please install it or configure the path in Settings > Claude Code."
        )
    }

    private fun getBundledBinaryPath(): String? {
        val plugin = PluginManagerCore.getPlugin(PluginId.getId(PLUGIN_ID))
            ?: return null

        val pluginDir = plugin.pluginPath
        val platformDir = getPlatformDirectoryName()
        val binaryName = if (SystemInfo.isWindows) "claude.exe" else "claude"

        val binaryPath = pluginDir.resolve("bin").resolve(platformDir).resolve(binaryName)

        if (Files.exists(binaryPath)) {
            val file = binaryPath.toFile()
            // Ensure the binary is executable (may lose execute bit during installation)
            if (!file.canExecute()) {
                file.setExecutable(true)
            }
            return binaryPath.toString()
        }

        LOG.debug("Bundled binary not found at: $binaryPath")
        return null
    }

    private fun getSystemBinaryPath(): String? {
        val binaryName = if (SystemInfo.isWindows) "claude.exe" else "claude"

        // Check common installation locations
        val candidates = when {
            SystemInfo.isMac -> listOf(
                "/usr/local/bin/$binaryName",
                "/opt/homebrew/bin/$binaryName",
                "${System.getProperty("user.home")}/.local/bin/$binaryName",
                "${System.getProperty("user.home")}/.claude/bin/$binaryName"
            )
            SystemInfo.isLinux -> listOf(
                "/usr/local/bin/$binaryName",
                "/usr/bin/$binaryName",
                "${System.getProperty("user.home")}/.local/bin/$binaryName",
                "${System.getProperty("user.home")}/.claude/bin/$binaryName"
            )
            SystemInfo.isWindows -> listOf(
                "${System.getenv("LOCALAPPDATA")}\\Claude\\$binaryName",
                "${System.getenv("ProgramFiles")}\\Claude\\$binaryName"
            )
            else -> emptyList()
        }

        for (candidate in candidates) {
            if (File(candidate).canExecute()) {
                return candidate
            }
        }

        // Try to find on PATH using `which`/`where`
        return findOnPath(binaryName)
    }

    private fun findOnPath(binaryName: String): String? {
        return try {
            val cmd = if (SystemInfo.isWindows) {
                GeneralCommandLine("where", binaryName)
            } else {
                GeneralCommandLine("which", binaryName)
            }
            val handler = CapturingProcessHandler(cmd)
            val output = handler.runProcess(5000)
            if (output.exitCode == 0) output.stdout.trim().lines().firstOrNull() else null
        } catch (e: Exception) {
            null
        }
    }

    private fun getPlatformDirectoryName(): String {
        val os = when {
            SystemInfo.isMac -> "darwin"
            SystemInfo.isLinux -> "linux"
            SystemInfo.isWindows -> "windows"
            else -> throw UnsupportedOperationException("Unsupported OS: ${SystemInfo.OS_NAME}")
        }

        val arch = when (val osArch = System.getProperty("os.arch")) {
            "aarch64", "arm64" -> "aarch64"
            "x86_64", "amd64" -> "x86_64"
            else -> throw UnsupportedOperationException("Unsupported architecture: $osArch")
        }

        return "$os-$arch"
    }
}

class ClaudeBinaryNotFoundException(message: String) : RuntimeException(message)
```

### build.gradle.kts Configuration for Bundling

```kotlin
// In build.gradle.kts
tasks {
    prepareSandbox {
        // Copy platform-specific binaries into the plugin sandbox for testing
        from("binaries") {
            into("${pluginName.get()}/bin")
        }
    }

    buildPlugin {
        // The buildPlugin task creates a .zip that includes everything from prepareSandbox
        // So the binaries will be included automatically
    }
}

// For CI/CD - download binaries for all platforms before building
tasks.register("downloadBinaries") {
    doLast {
        val platforms = listOf(
            "darwin-aarch64", "darwin-x86_64",
            "linux-aarch64", "linux-x86_64",
            "windows-x86_64"
        )
        for (platform in platforms) {
            // Download from your artifact storage
            val url = "https://releases.example.com/claude-cli/$platform/claude"
            // ... download logic
        }
    }
}
```

---

## 8. Error Handling

### Process Crash Detection and Recovery

```kotlin
/**
 * Comprehensive error handling for the Claude process.
 */
@Service(Service.Level.PROJECT)
class ClaudeErrorHandler(
    private val project: Project,
    private val cs: CoroutineScope
) {
    private val notificationGroup = NotificationGroupManager.getInstance()
        .getNotificationGroup("Claude Code")

    /**
     * Analyze process exit and determine the cause.
     */
    fun analyzeExit(exitCode: Int, stderrOutput: String): ExitAnalysis {
        return when {
            exitCode == 0 -> ExitAnalysis.NORMAL_EXIT

            exitCode == 1 && stderrOutput.contains("ANTHROPIC_API_KEY") ->
                ExitAnalysis.MISSING_API_KEY

            exitCode == 1 && stderrOutput.contains("rate limit") ->
                ExitAnalysis.RATE_LIMITED

            exitCode == 1 && stderrOutput.contains("authentication") ->
                ExitAnalysis.AUTH_FAILURE

            exitCode == 127 ->
                ExitAnalysis.BINARY_NOT_FOUND

            exitCode == 126 ->
                ExitAnalysis.PERMISSION_DENIED

            exitCode == 137 || exitCode == 9 ->
                ExitAnalysis.KILLED_BY_SIGNAL  // SIGKILL

            exitCode == 143 || exitCode == 15 ->
                ExitAnalysis.TERMINATED_BY_SIGNAL  // SIGTERM

            exitCode == -1 ->
                ExitAnalysis.FAILED_TO_START

            else ->
                ExitAnalysis.UNKNOWN_ERROR
        }
    }

    enum class ExitAnalysis(val message: String, val isRecoverable: Boolean) {
        NORMAL_EXIT("Process exited normally", false),
        MISSING_API_KEY("API key not configured", false),
        RATE_LIMITED("Rate limited by API", true),
        AUTH_FAILURE("Authentication failed", false),
        BINARY_NOT_FOUND("Claude CLI binary not found", false),
        PERMISSION_DENIED("Permission denied running Claude CLI", false),
        KILLED_BY_SIGNAL("Process was killed", true),
        TERMINATED_BY_SIGNAL("Process was terminated", true),
        FAILED_TO_START("Process failed to start", false),
        UNKNOWN_ERROR("Unknown error", true)
    }

    /**
     * Notify the user about an error with appropriate actions.
     */
    fun notifyError(analysis: ExitAnalysis, exitCode: Int) {
        val notification = notificationGroup.createNotification(
            "Claude Code",
            "${analysis.message} (exit code: $exitCode)",
            if (analysis.isRecoverable) NotificationType.WARNING else NotificationType.ERROR
        )

        // Add context-specific actions
        when (analysis) {
            ExitAnalysis.MISSING_API_KEY -> {
                notification.addAction(object : AnAction("Configure API Key") {
                    override fun actionPerformed(e: AnActionEvent) {
                        ShowSettingsUtil.getInstance().showSettingsDialog(
                            project, "Claude Code"
                        )
                    }
                })
            }
            ExitAnalysis.BINARY_NOT_FOUND -> {
                notification.addAction(object : AnAction("Configure Binary Path") {
                    override fun actionPerformed(e: AnActionEvent) {
                        ShowSettingsUtil.getInstance().showSettingsDialog(
                            project, "Claude Code"
                        )
                    }
                })
                notification.addAction(object : AnAction("Install Claude CLI") {
                    override fun actionPerformed(e: AnActionEvent) {
                        BrowserUtil.browse("https://docs.anthropic.com/claude-code/install")
                    }
                })
            }
            ExitAnalysis.RATE_LIMITED, ExitAnalysis.KILLED_BY_SIGNAL -> {
                notification.addAction(object : AnAction("Restart Claude") {
                    override fun actionPerformed(e: AnActionEvent) {
                        ClaudeProcessLifecycle.getInstance(project).restart()
                    }
                })
            }
            else -> {
                if (analysis.isRecoverable) {
                    notification.addAction(object : AnAction("Restart Claude") {
                        override fun actionPerformed(e: AnActionEvent) {
                            ClaudeProcessLifecycle.getInstance(project).restart()
                        }
                    })
                }
            }
        }

        notification.notify(project)
    }

    /**
     * Handle unexpected process termination with restart logic.
     */
    fun handleCrash(
        exitCode: Int,
        stderrOutput: String,
        restartCount: Int,
        maxRestarts: Int,
        onRestart: suspend () -> Unit
    ) {
        val analysis = analyzeExit(exitCode, stderrOutput)

        if (!analysis.isRecoverable || restartCount >= maxRestarts) {
            notifyError(analysis, exitCode)
            return
        }

        cs.launch {
            val delayMs = calculateBackoff(restartCount)
            LOG.info("Scheduling restart in ${delayMs}ms (attempt ${restartCount + 1}/$maxRestarts)")
            delay(delayMs)
            onRestart()
        }
    }

    private fun calculateBackoff(restartCount: Int): Long {
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s (capped)
        val baseMs = 1000L
        val maxMs = 16000L
        return minOf(baseMs * (1L shl restartCount), maxMs)
    }

    companion object {
        private val LOG = logger<ClaudeErrorHandler>()

        fun getInstance(project: Project): ClaudeErrorHandler =
            project.service<ClaudeErrorHandler>()
    }
}
```

### Stderr Capture for Diagnostics

```kotlin
/**
 * Capture stderr from the process for error diagnostics.
 * ProcessHandler's ProcessListener approach is often cleaner than raw stream reading.
 */
class StderrCollector : ProcessAdapter() {
    private val buffer = StringBuilder()
    private val maxBufferSize = 64 * 1024  // 64KB

    override fun onTextAvailable(event: ProcessEvent, outputType: Key<*>) {
        if (outputType == ProcessOutputType.STDERR) {
            synchronized(buffer) {
                if (buffer.length < maxBufferSize) {
                    buffer.append(event.text)
                }
            }
        }
    }

    fun getOutput(): String = synchronized(buffer) { buffer.toString() }
    fun clear() = synchronized(buffer) { buffer.clear() }
}
```

---

## 9. stdin/stdout JSON Protocol

### Line-Delimited JSON (JSONL) Communication Pattern

The recommended approach for efficient JSON communication with a child process in Kotlin.

### Data Types

```kotlin
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

/**
 * Base message types for Claude CLI protocol.
 * Using kotlinx.serialization for type-safe JSON handling.
 */
@Serializable
sealed class ClaudeMessage {
    abstract val type: String
}

@Serializable
data class UserMessage(
    override val type: String = "user_message",
    val content: String,
    val files: List<FileReference> = emptyList(),
    val requestId: String = java.util.UUID.randomUUID().toString()
) : ClaudeMessage()

@Serializable
data class FileReference(
    val path: String,
    val content: String? = null
)

@Serializable
data class AssistantMessage(
    override val type: String = "assistant_message",
    val content: String,
    val messageId: String? = null,
    val conversationId: String? = null
) : ClaudeMessage()

@Serializable
data class StreamDelta(
    override val type: String = "stream_delta",
    val delta: String,
    val messageId: String? = null
) : ClaudeMessage()

@Serializable
data class ToolUseRequest(
    override val type: String = "tool_use",
    val toolName: String,
    val input: JsonElement,
    val requestId: String
) : ClaudeMessage()

@Serializable
data class ToolResult(
    override val type: String = "tool_result",
    val requestId: String,
    val result: String,
    val isError: Boolean = false
) : ClaudeMessage()

@Serializable
data class ErrorMessage(
    override val type: String = "error",
    val error: String,
    val code: String? = null
) : ClaudeMessage()
```

### JSON Configuration

```kotlin
import kotlinx.serialization.json.Json

val claudeJson = Json {
    // Be lenient with unknown fields from the CLI
    ignoreUnknownKeys = true
    // Don't fail on missing optional fields
    isLenient = false
    // Include type discriminator for sealed classes
    classDiscriminator = "type"
    // Pretty print for logging (use non-pretty for actual protocol)
    prettyPrint = false
    // Handle nulls properly
    encodeDefaults = true
}
```

### Full JSON Protocol Handler

```kotlin
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import java.io.*
import java.util.concurrent.ConcurrentHashMap

/**
 * Handles bidirectional JSON communication with the Claude CLI process.
 *
 * Architecture:
 * - One coroutine reads stdout line-by-line and parses JSON
 * - One coroutine consumes an outgoing channel and writes to stdin
 * - Incoming messages are exposed as a SharedFlow
 * - Request-response correlation via requestId
 */
class JsonProtocolHandler(
    private val process: Process,
    private val cs: CoroutineScope
) {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        prettyPrint = false
    }

    // Outgoing message channel
    private val outgoing = Channel<String>(Channel.BUFFERED)

    // Incoming message flow
    private val _messages = MutableSharedFlow<JsonObject>(
        extraBufferCapacity = 128,
        onBufferOverflow = BufferOverflow.SUSPEND
    )
    val messages: SharedFlow<JsonObject> = _messages.asSharedFlow()

    // Pending request-response handlers
    private val pendingRequests = ConcurrentHashMap<String, CompletableDeferred<JsonObject>>()

    // Reader and writer jobs
    private var readerJob: Job? = null
    private var writerJob: Job? = null

    fun start() {
        readerJob = cs.launch(Dispatchers.IO + CoroutineName("claude-stdout-reader")) {
            readLoop()
        }

        writerJob = cs.launch(Dispatchers.IO + CoroutineName("claude-stdin-writer")) {
            writeLoop()
        }
    }

    /**
     * Read stdout line by line, parse each line as JSON.
     *
     * IMPORTANT: Uses BufferedReader.readLine() which blocks.
     * This is correct because we're on Dispatchers.IO which uses
     * an unbounded thread pool designed for blocking I/O.
     */
    private suspend fun readLoop() {
        val reader = BufferedReader(
            InputStreamReader(process.inputStream, Charsets.UTF_8),
            8192  // 8KB buffer for efficiency
        )

        try {
            while (isActive) {
                // readLine() blocks until a line is available or stream closes
                val line = reader.readLine() ?: break  // null = stream closed

                if (line.isBlank()) continue

                try {
                    val jsonObject = json.parseToJsonElement(line).jsonObject

                    // Check if this is a response to a pending request
                    val requestId = jsonObject["requestId"]?.jsonPrimitive?.contentOrNull
                        ?: jsonObject["request_id"]?.jsonPrimitive?.contentOrNull

                    if (requestId != null) {
                        pendingRequests.remove(requestId)?.complete(jsonObject)
                    }

                    // Always emit to the general flow
                    _messages.emit(jsonObject)

                } catch (e: Exception) {
                    LOG.warn("Failed to parse JSON line: ${line.take(200)}", e)
                    // Emit a synthetic error message
                    _messages.emit(buildJsonObject {
                        put("type", "parse_error")
                        put("raw", line.take(1000))
                        put("error", e.message ?: "Unknown parse error")
                    })
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: IOException) {
            if (isActive) {
                LOG.info("Claude stdout stream closed: ${e.message}")
            }
        } finally {
            reader.close()
        }
    }

    /**
     * Consume the outgoing channel and write to stdin.
     */
    private suspend fun writeLoop() {
        val writer = BufferedOutputStream(process.outputStream, 8192)

        try {
            for (message in outgoing) {
                if (!isActive) break

                writer.write(message.toByteArray(Charsets.UTF_8))
                writer.write('\n'.code)
                writer.flush()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: IOException) {
            if (isActive) {
                LOG.warn("Error writing to Claude stdin: ${e.message}")
            }
        } finally {
            try { writer.close() } catch (_: IOException) {}
        }
    }

    /**
     * Send a message (fire-and-forget).
     * Safe to call from any coroutine context.
     */
    suspend fun send(message: JsonObject) {
        val serialized = json.encodeToString(JsonObject.serializer(), message)
        outgoing.send(serialized)
    }

    /**
     * Send a message and wait for a correlated response.
     * Uses the requestId field for correlation.
     */
    suspend fun sendAndReceive(
        message: JsonObject,
        requestId: String,
        timeout: Long = 30_000L
    ): JsonObject {
        val deferred = CompletableDeferred<JsonObject>()
        pendingRequests[requestId] = deferred

        try {
            send(message)
            return withTimeout(timeout) {
                deferred.await()
            }
        } catch (e: TimeoutCancellationException) {
            pendingRequests.remove(requestId)
            throw ClaudeTimeoutException("Request $requestId timed out after ${timeout}ms")
        } catch (e: Exception) {
            pendingRequests.remove(requestId)
            throw e
        }
    }

    /**
     * Convenience: send a typed message
     */
    suspend fun sendUserMessage(content: String, files: List<FileReference> = emptyList()) {
        val requestId = java.util.UUID.randomUUID().toString()
        val message = buildJsonObject {
            put("type", "user_message")
            put("content", content)
            put("request_id", requestId)
            putJsonArray("files") {
                for (file in files) {
                    addJsonObject {
                        put("path", file.path)
                        file.content?.let { put("content", it) }
                    }
                }
            }
        }
        send(message)
    }

    /**
     * Filter messages by type.
     */
    fun messagesOfType(type: String): Flow<JsonObject> {
        return messages.filter {
            it["type"]?.jsonPrimitive?.contentOrNull == type
        }
    }

    /**
     * Get a flow of streaming deltas.
     */
    fun streamDeltas(): Flow<String> {
        return messagesOfType("stream_delta").mapNotNull {
            it["delta"]?.jsonPrimitive?.contentOrNull
        }
    }

    fun stop() {
        readerJob?.cancel()
        writerJob?.cancel()
        outgoing.close()

        // Complete all pending requests with an error
        for ((id, deferred) in pendingRequests) {
            deferred.completeExceptionally(
                CancellationException("Protocol handler stopped")
            )
        }
        pendingRequests.clear()
    }

    companion object {
        private val LOG = logger<JsonProtocolHandler>()
    }
}

class ClaudeTimeoutException(message: String) : RuntimeException(message)
```

### Alternative: Using kotlinx.serialization Polymorphism

```kotlin
import kotlinx.serialization.*
import kotlinx.serialization.json.*

/**
 * Type-safe deserialization using sealed class hierarchy.
 * This approach gives compile-time type safety at the cost of
 * having to define all message types upfront.
 */
@Serializable
sealed class IncomingMessage {
    @Serializable
    @SerialName("assistant_message")
    data class AssistantMessage(
        val content: String,
        val messageId: String? = null
    ) : IncomingMessage()

    @Serializable
    @SerialName("stream_delta")
    data class StreamDelta(
        val delta: String,
        val messageId: String? = null
    ) : IncomingMessage()

    @Serializable
    @SerialName("tool_use")
    data class ToolUse(
        val toolName: String,
        val input: JsonElement,
        val requestId: String
    ) : IncomingMessage()

    @Serializable
    @SerialName("error")
    data class Error(
        val error: String,
        val code: String? = null
    ) : IncomingMessage()

    @Serializable
    @SerialName("status")
    data class Status(
        val status: String,
        val details: JsonElement? = null
    ) : IncomingMessage()
}

// Deserialization
val jsonParser = Json {
    ignoreUnknownKeys = true
    classDiscriminator = "type"
}

fun parseMessage(line: String): IncomingMessage? {
    return try {
        jsonParser.decodeFromString<IncomingMessage>(line)
    } catch (e: SerializationException) {
        LOG.warn("Unknown message type in: ${line.take(200)}", e)
        null
    }
}

// Usage in the read loop
when (val msg = parseMessage(line)) {
    is IncomingMessage.AssistantMessage -> handleAssistantMessage(msg)
    is IncomingMessage.StreamDelta -> handleStreamDelta(msg)
    is IncomingMessage.ToolUse -> handleToolUse(msg)
    is IncomingMessage.Error -> handleError(msg)
    is IncomingMessage.Status -> handleStatus(msg)
    null -> { /* unknown message type, already logged */ }
}
```

### Performance Considerations for JSON I/O

```kotlin
/**
 * Performance tips for high-throughput JSON communication:
 *
 * 1. Use BufferedReader/BufferedOutputStream with adequate buffer sizes
 * 2. Parse JSON lazily - parse to JsonObject first, then extract fields on demand
 * 3. Avoid creating intermediate String objects when possible
 * 4. Use Channel.BUFFERED (default 64) for the outgoing channel to handle bursts
 * 5. Use SharedFlow with extraBufferCapacity for incoming messages to avoid backpressure
 */

// For very high throughput, consider using Jackson Streaming API instead of kotlinx.serialization
// But for typical Claude CLI communication (< 1000 messages/sec), kotlinx.serialization is fine.

// Buffer size recommendations:
// - stdin BufferedOutputStream: 8KB (messages are typically small)
// - stdout BufferedReader: 8KB-32KB (responses can be longer with streaming deltas)
// - SharedFlow extraBufferCapacity: 64-256 (handles UI update latency)
```

---

## 10. Service Lifecycle and Disposable Pattern

### The Disposable Hierarchy

```
Application (root)
  |
  +-- Project
  |     |
  |     +-- Project-level services (disposed when project closes)
  |     |     |
  |     |     +-- ClaudeService
  |     |     +-- ClaudeProcessLifecycle
  |     |
  |     +-- ToolWindow.disposable (disposed when tool window closes)
  |     |     |
  |     |     +-- JCEF browser resources
  |     |     +-- UI listeners
  |     |
  |     +-- Editor disposables
  |
  +-- Application-level services (disposed on IDE exit)
```

### Correct Disposable Usage

```kotlin
import com.intellij.openapi.Disposable
import com.intellij.openapi.util.Disposer

/**
 * Rule 1: Always register disposable children with a parent.
 * Rule 2: Never call dispose() directly - use Disposer.dispose(disposable).
 * Rule 3: Use Disposer.register(parent, child) to establish hierarchy.
 * Rule 4: Check isDisposed before using resources after async operations.
 */

// GOOD: Registering with parent
class ClaudeToolWindowPanel(
    private val project: Project,
    private val parentDisposable: Disposable
) : Disposable {

    private val browser: JBCefBrowser
    private val processHandler: JsonProtocolHandler

    init {
        // Register this panel with the parent (tool window)
        Disposer.register(parentDisposable, this)

        // Create child resources and register them with this panel
        browser = JBCefBrowser()
        Disposer.register(this, browser)

        processHandler = JsonProtocolHandler(/* ... */)
        Disposer.register(this, Disposable { processHandler.stop() })
    }

    override fun dispose() {
        // Called automatically when parent is disposed,
        // or explicitly via Disposer.dispose(this)
        //
        // Children (browser, processHandler wrapper) are disposed AFTER this.
        // So don't try to use them here - just clean up own resources.
        LOG.info("ClaudeToolWindowPanel disposed")
    }
}

// GOOD: Using Disposer.newDisposable() for lightweight disposables
class ClaudeEditorListener(private val project: Project) {
    private val listenerDisposable = Disposer.newDisposable("ClaudeEditorListener")

    init {
        Disposer.register(project, listenerDisposable)

        // Register IDE listeners with the disposable
        EditorFactory.getInstance().addEditorFactoryListener(
            myListener,
            listenerDisposable
        )
    }

    fun deactivate() {
        Disposer.dispose(listenerDisposable)
    }
}
```

### Complete Service with Proper Lifecycle

```kotlin
import com.intellij.openapi.components.Service
import com.intellij.openapi.project.Project
import com.intellij.openapi.Disposable
import com.intellij.openapi.util.Disposer
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/**
 * The main Claude Code service. Manages the complete lifecycle of:
 * - The Claude CLI process
 * - JSON protocol communication
 * - State tracking
 * - Resource cleanup
 *
 * Registered in plugin.xml as:
 *   <projectService serviceImplementation="com.anthropic.claude.ClaudeCodeService"/>
 *
 * The service is automatically disposed when the project closes because it
 * is a project-level service (Service.Level.PROJECT).
 */
@Service(Service.Level.PROJECT)
class ClaudeCodeService(
    private val project: Project,
    private val cs: CoroutineScope  // Platform-injected, cancelled on project close
) : Disposable {

    // --- State ---

    sealed class State {
        object Disconnected : State()
        object Connecting : State()
        data class Connected(val sessionId: String) : State()
        data class Error(val message: String, val recoverable: Boolean) : State()
    }

    private val _state = MutableStateFlow<State>(State.Disconnected)
    val state: StateFlow<State> = _state.asStateFlow()

    // --- Internal components ---

    private var processHandler: KillableProcessHandler? = null
    private var protocolHandler: JsonProtocolHandler? = null
    private var stderrCollector: StderrCollector? = null

    // --- Message flows ---

    private val _assistantMessages = MutableSharedFlow<AssistantMessage>(
        extraBufferCapacity = 64
    )
    val assistantMessages: SharedFlow<AssistantMessage> = _assistantMessages.asSharedFlow()

    private val _streamDeltas = MutableSharedFlow<StreamDelta>(
        extraBufferCapacity = 256  // Higher for streaming text
    )
    val streamDeltas: SharedFlow<StreamDelta> = _streamDeltas.asSharedFlow()

    // --- Public API ---

    /**
     * Start the Claude CLI and establish communication.
     */
    fun connect() {
        cs.launch {
            doConnect()
        }
    }

    /**
     * Send a user message to Claude.
     */
    fun sendMessage(text: String, files: List<FileReference> = emptyList()) {
        cs.launch {
            protocolHandler?.sendUserMessage(text, files)
                ?: LOG.warn("Cannot send message: not connected")
        }
    }

    /**
     * Stop the Claude CLI process.
     */
    fun disconnect() {
        cs.launch {
            doDisconnect()
        }
    }

    /**
     * Restart the Claude CLI process.
     */
    fun reconnect() {
        cs.launch {
            doDisconnect()
            delay(500)
            doConnect()
        }
    }

    // --- Internal implementation ---

    private suspend fun doConnect() {
        if (_state.value is State.Connected || _state.value is State.Connecting) {
            return
        }

        _state.value = State.Connecting

        try {
            // Resolve binary
            val settings = ClaudeSettings.getInstance(project)
            val binaryPath = ClaudeBinaryResolver.resolve(settings)

            // Build command line
            val commandLine = GeneralCommandLine()
                .withExePath(binaryPath)
                .withParameters("--output-format", "stream-json", "--verbose")
                .withWorkDirectory(project.basePath)
                .withCharset(Charsets.UTF_8)
                .withParentEnvironmentType(
                    GeneralCommandLine.ParentEnvironmentType.CONSOLE
                )
                .withEnvironment(buildEnvironment(settings))

            // Start process
            val handler = withContext(Dispatchers.IO) {
                KillableProcessHandler(commandLine).also {
                    it.setShouldDestroyProcessRecursively(true)
                }
            }

            // Set up stderr collection
            val stderr = StderrCollector()
            handler.addProcessListener(stderr)
            stderrCollector = stderr

            // Set up process termination handler
            handler.addProcessListener(object : ProcessAdapter() {
                override fun processTerminated(event: ProcessEvent) {
                    cs.launch {
                        handleProcessTermination(event.exitCode, stderr.getOutput())
                    }
                }
            })

            handler.startNotify()
            processHandler = handler

            // Set up JSON protocol
            val protocol = JsonProtocolHandler(handler.process, cs)
            protocol.start()
            protocolHandler = protocol

            // Start message routing
            startMessageRouting(protocol)

            _state.value = State.Connected(sessionId = generateSessionId())
            LOG.info("Connected to Claude CLI (PID: ${handler.process.pid()})")

        } catch (e: ClaudeBinaryNotFoundException) {
            _state.value = State.Error(e.message ?: "Binary not found", recoverable = false)
            withContext(Dispatchers.EDT) {
                ClaudeErrorHandler.getInstance(project).notifyError(
                    ClaudeErrorHandler.ExitAnalysis.BINARY_NOT_FOUND, -1
                )
            }
        } catch (e: Exception) {
            LOG.error("Failed to connect to Claude CLI", e)
            _state.value = State.Error(
                e.message ?: "Unknown error",
                recoverable = true
            )
            withContext(Dispatchers.EDT) {
                ClaudeErrorHandler.getInstance(project).notifyError(
                    ClaudeErrorHandler.ExitAnalysis.FAILED_TO_START, -1
                )
            }
        }
    }

    private fun startMessageRouting(protocol: JsonProtocolHandler) {
        // Route messages to typed flows
        cs.launch {
            protocol.messagesOfType("assistant_message").collect { json ->
                val msg = AssistantMessage(
                    content = json["content"]?.jsonPrimitive?.contentOrNull ?: "",
                    messageId = json["message_id"]?.jsonPrimitive?.contentOrNull
                )
                _assistantMessages.emit(msg)
            }
        }

        cs.launch {
            protocol.messagesOfType("stream_delta").collect { json ->
                val delta = StreamDelta(
                    delta = json["delta"]?.jsonPrimitive?.contentOrNull ?: "",
                    messageId = json["message_id"]?.jsonPrimitive?.contentOrNull
                )
                _streamDeltas.emit(delta)
            }
        }
    }

    private suspend fun doDisconnect() {
        protocolHandler?.stop()
        protocolHandler = null

        processHandler?.let { handler ->
            if (!handler.isProcessTerminated) {
                withContext(Dispatchers.IO) {
                    handler.destroyProcess()  // SIGTERM
                    // Wait up to 5 seconds for graceful shutdown
                    repeat(50) {
                        if (handler.isProcessTerminated) return@withContext
                        delay(100)
                    }
                    // Force kill if still alive
                    if (!handler.isProcessTerminated) {
                        handler.killProcess()
                    }
                }
            }
        }
        processHandler = null
        stderrCollector = null

        _state.value = State.Disconnected
    }

    private suspend fun handleProcessTermination(exitCode: Int, stderr: String) {
        if (_state.value is State.Disconnected) return  // Expected shutdown

        val errorHandler = ClaudeErrorHandler.getInstance(project)
        val analysis = errorHandler.analyzeExit(exitCode, stderr)

        if (analysis.isRecoverable) {
            LOG.warn("Claude process crashed: $analysis (exit: $exitCode)")
            _state.value = State.Error(analysis.message, recoverable = true)

            // Auto-restart after a delay
            errorHandler.handleCrash(exitCode, stderr, restartCount = 0, maxRestarts = 3) {
                doConnect()
            }
        } else {
            LOG.error("Claude process failed: $analysis (exit: $exitCode)")
            _state.value = State.Error(analysis.message, recoverable = false)
        }

        withContext(Dispatchers.EDT) {
            errorHandler.notifyError(analysis, exitCode)
        }
    }

    /**
     * dispose() is called by the platform when the project closes.
     * At this point, the coroutineScope (cs) has already been cancelled,
     * so we do synchronous cleanup only.
     */
    override fun dispose() {
        protocolHandler?.stop()
        processHandler?.let { handler ->
            if (!handler.isProcessTerminated) {
                handler.killProcess()  // Force kill on dispose
            }
        }
        processHandler = null
        protocolHandler = null
        stderrCollector = null
        LOG.info("ClaudeCodeService disposed for project: ${project.name}")
    }

    companion object {
        private val LOG = logger<ClaudeCodeService>()

        fun getInstance(project: Project): ClaudeCodeService =
            project.service<ClaudeCodeService>()
    }
}
```

### plugin.xml Service Registration

```xml
<extensions defaultExtensionNs="com.intellij">
    <!-- Project-level services: one instance per project, disposed on project close -->
    <projectService
        serviceImplementation="com.anthropic.claude.ClaudeCodeService"/>
    <projectService
        serviceImplementation="com.anthropic.claude.ClaudeSettings"/>
    <projectService
        serviceImplementation="com.anthropic.claude.ClaudeErrorHandler"/>
    <projectService
        serviceImplementation="com.anthropic.claude.ClaudeProcessLifecycle"/>

    <!-- Application-level services: one instance for the entire IDE -->
    <applicationService
        serviceImplementation="com.anthropic.claude.ClaudeApplicationSettings"/>

    <!-- Notification group -->
    <notificationGroup id="Claude Code"
                       displayType="BALLOON"
                       isLogByDefault="true"/>

    <!-- Startup activity -->
    <postStartupActivity
        implementation="com.anthropic.claude.ClaudeStartupActivity"/>
</extensions>
```

---

## Summary of Recommendations

| Topic | Recommendation |
|-------|---------------|
| **Process creation** | `GeneralCommandLine` + `KillableProcessHandler` |
| **Threading** | Kotlin Coroutines with platform-injected `CoroutineScope` |
| **Stdout reading** | `Dispatchers.IO` coroutine with `BufferedReader.readLine()` |
| **Stdin writing** | `Channel<String>` consumed by a writer coroutine |
| **JSON parsing** | `kotlinx.serialization` with `ignoreUnknownKeys = true` |
| **Message routing** | `SharedFlow` for incoming, `Channel` for outgoing |
| **Request-response** | `CompletableDeferred` with requestId correlation |
| **Error handling** | Exit code analysis + exponential backoff restart |
| **Lifecycle** | Project-scoped `@Service` with `Disposable` |
| **Binary resolution** | Settings override, then bundled, then PATH |
| **Environment vars** | `ParentEnvironmentType.CONSOLE` base + explicit overrides |
| **UI updates** | `Dispatchers.EDT` or `withContext(Dispatchers.EDT)` |

---

## References

- IntelliJ Platform SDK: Execution (GeneralCommandLine, ProcessHandler)
  https://plugins.jetbrains.com/docs/intellij/execution.html
- IntelliJ Platform SDK: General Threading Rules
  https://plugins.jetbrains.com/docs/intellij/general-threading-rules.html
- IntelliJ Platform SDK: Kotlin Coroutines
  https://plugins.jetbrains.com/docs/intellij/kotlin-coroutines.html
- IntelliJ Platform SDK: Disposers
  https://plugins.jetbrains.com/docs/intellij/disposers.html
- IntelliJ Platform SDK: Plugin Services
  https://plugins.jetbrains.com/docs/intellij/plugin-services.html
- IntelliJ Platform SDK: Plugin Structure / Directory Layout
  https://plugins.jetbrains.com/docs/intellij/plugin-content.html
- kotlinx.serialization Guide
  https://github.com/Kotlin/kotlinx.serialization/blob/master/docs/serialization-guide.md
- IntelliJ Community Source: `com.intellij.execution.process` package
  https://github.com/JetBrains/intellij-community/tree/master/platform/platform-api/src/com/intellij/execution/process
- IntelliJ Community Source: `GeneralCommandLine`
  https://github.com/JetBrains/intellij-community/blob/master/platform/platform-api/src/com/intellij/execution/configurations/GeneralCommandLine.java
