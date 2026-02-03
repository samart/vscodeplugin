# JCEF Webview Integration Research for IntelliJ Plugins (2025)

> Research compiled for the Claude Code IntelliJ port project.
> Covers JCEF APIs, communication patterns, performance, theming, debugging, and alternatives.

---

## Table of Contents

1. [JBCefBrowser API](#1-jbcefbrowser-api)
2. [JBCefJSQuery - Bidirectional Communication](#2-jbcefjsquery---bidirectional-communication)
3. [Loading Local HTML/JS/CSS](#3-loading-local-htmljscss)
4. [Performance Best Practices](#4-performance-best-practices)
5. [Dark Theme Integration](#5-dark-theme-integration)
6. [DevTools for Debugging](#6-devtools-for-debugging)
7. [Alternatives to JCEF](#7-alternatives-to-jcef)
8. [Real-World Examples](#8-real-world-examples)
9. [Sources and References](#9-sources-and-references)

---

## 1. JBCefBrowser API

### 1.1 Overview

JCEF (Java Chromium Embedded Framework) is IntelliJ's wrapper around the Chromium Embedded Framework (CEF). JetBrains provides the `JBCef*` family of classes as a high-level abstraction in the IntelliJ Platform SDK. It has been the primary supported way to embed web content in IntelliJ plugins since IntelliJ 2020.2.

**Key classes:**
- `JBCefBrowser` - Main browser component (tool window embedding, editor tabs)
- `JBCefBrowserBase` - Abstract base; `JBCefBrowser` extends this
- `JBCefClient` - Manages CEF client handlers (load, display, keyboard, etc.)
- `JBCefJSQuery` - JS-to-Java/Kotlin communication bridge
- `JBCefApp` - Application-level JCEF state (singleton)

### 1.2 Availability Check

JCEF may not be available in all environments (e.g., headless, remote dev, some Linux distros). Always check:

```kotlin
import com.intellij.ui.jcef.JBCefApp

fun isJcefAvailable(): Boolean {
    return JBCefApp.isSupported()
}
```

If JCEF is not available, you should provide a fallback UI (e.g., a Swing-based panel with a message).

### 1.3 Creating a JBCefBrowser

**Current API (IntelliJ 2024.x / 2025.x):**

```kotlin
import com.intellij.ui.jcef.JBCefBrowser
import com.intellij.ui.jcef.JBCefBrowserBuilder

// Simple creation (default settings)
val browser = JBCefBrowser()

// Builder pattern (recommended for customization, available since 2022.3+)
val browser = JBCefBrowserBuilder()
    .setUrl("about:blank")
    .setEnableOpenDevToolsMenuItem(true)   // right-click -> Open DevTools
    .setOffScreenRendering(false)          // on-screen for tool windows
    .setMouseWheelEventEnable(true)
    .build()
```

**Key builder options:**
| Method | Description | Default |
|--------|-------------|---------|
| `setUrl(String)` | Initial URL to load | `about:blank` |
| `setOffScreenRendering(Boolean)` | Off-screen rendering mode (for editor tabs) | `false` |
| `setEnableOpenDevToolsMenuItem(Boolean)` | Add DevTools to context menu | `false` (production) |
| `setMouseWheelEventEnable(Boolean)` | Forward mouse wheel events | `true` |
| `setCreateImmediately(Boolean)` | Create CEF browser immediately vs lazily | `false` |
| `setClient(JBCefClient)` | Use a shared `JBCefClient` | New per browser |

### 1.4 Deprecated / Changed Methods (2024-2025)

| Deprecated | Replacement | Since |
|------------|-------------|-------|
| `JBCefBrowser(String url)` constructor | `JBCefBrowserBuilder().setUrl(url).build()` | 2023.1 |
| `JBCefBrowser.createBuilder()` | `JBCefBrowserBuilder()` (top-level) | 2024.1 |
| `getCefBrowser()` direct usage | Prefer `JBCefBrowser` wrapper methods | Ongoing |
| `JBCefJSQuery.create(JBCefBrowser)` | `JBCefJSQuery.create(browser as JBCefBrowserBase)` | 2022.3 |

**Important:** The `JBCefBrowser()` no-arg constructor still works but is considered legacy. Using `JBCefBrowserBuilder` is the recommended approach as it provides explicit control over all parameters.

### 1.5 Core JBCefBrowser Methods

```kotlin
// Loading content
browser.loadURL("https://example.com")
browser.loadHTML("<html>...</html>")
browser.loadHTML(htmlContent, "https://localhost")  // with base URL

// Getting the Swing component for embedding
val swingComponent: JComponent = browser.component

// Executing JavaScript (fire-and-forget)
browser.cefBrowser.executeJavaScript(
    "document.body.style.background = 'red'",
    browser.cefBrowser.url,   // sourceUrl for debugging
    0                          // line number for debugging
)

// Accessing underlying CEF browser
val cefBrowser: CefBrowser = browser.cefBrowser

// Accessing the JBCefClient for handler registration
val client: JBCefClient = browser.jbCefClient

// Zoom
browser.zoomLevel = 1.0  // 1.0 = 100%

// Lifecycle
browser.dispose()  // MUST be called to release native resources
```

### 1.6 Embedding in a Tool Window

```kotlin
import com.intellij.openapi.project.Project
import com.intellij.openapi.wm.ToolWindow
import com.intellij.openapi.wm.ToolWindowFactory
import com.intellij.ui.content.ContentFactory
import com.intellij.ui.jcef.JBCefApp
import com.intellij.ui.jcef.JBCefBrowser
import com.intellij.ui.jcef.JBCefBrowserBuilder
import java.awt.BorderLayout
import javax.swing.JLabel
import javax.swing.JPanel

class MyToolWindowFactory : ToolWindowFactory {

    override fun isApplicable(project: Project): Boolean {
        // Only show tool window if JCEF is available
        return JBCefApp.isSupported()
    }

    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        val panel = JPanel(BorderLayout())

        if (JBCefApp.isSupported()) {
            val browser = JBCefBrowserBuilder()
                .setEnableOpenDevToolsMenuItem(true)
                .build()

            browser.loadHTML(getInitialHtml())
            panel.add(browser.component, BorderLayout.CENTER)

            // Register Disposable to clean up native resources
            toolWindow.disposable.let { parentDisposable ->
                com.intellij.openapi.util.Disposer.register(parentDisposable, browser)
            }
        } else {
            panel.add(JLabel("JCEF is not supported in this environment"), BorderLayout.CENTER)
        }

        val content = ContentFactory.getInstance().createContent(panel, "", false)
        toolWindow.contentManager.addContent(content)
    }
}
```

---

## 2. JBCefJSQuery - Bidirectional Communication

### 2.1 Architecture Overview

Communication between the JCEF webview and the Kotlin/Java plugin host uses two channels:

```
  Kotlin/Java (Host)                     JavaScript (Webview)
  ──────────────────                     ───────────────────
       │                                       │
       │  ── executeJavaScript() ──────────>   │   Host -> JS (push)
       │                                       │
       │  <── JBCefJSQuery callback ────────   │   JS -> Host (pull)
       │                                       │
```

- **Host to JS:** Call `cefBrowser.executeJavaScript(code, url, line)` to run arbitrary JS in the page.
- **JS to Host:** Use `JBCefJSQuery` to create a bridge function that JS can call; the call is routed back to a Kotlin/Java handler.

### 2.2 Creating a JBCefJSQuery

```kotlin
import com.intellij.ui.jcef.JBCefBrowserBase
import com.intellij.ui.jcef.JBCefJSQuery

// Create the query object (must be done on EDT or after browser is initialized)
val jsQuery = JBCefJSQuery.create(browser as JBCefBrowserBase)

// Register handler for incoming JS calls
jsQuery.addHandler { message: String ->
    // `message` is the string argument passed from JavaScript
    // Process the message (runs on the CEF IO thread - offload heavy work!)
    val response = processMessage(message)

    // Return a response (or null for no response)
    JBCefJSQuery.Response(response)
}
```

### 2.3 Injecting the Bridge into the Page

The `jsQuery.inject(argExpression)` method returns a JavaScript code snippet that, when executed in the browser, calls back into the Kotlin handler. The `argExpression` is a JavaScript expression that evaluates to the string argument.

```kotlin
import org.cef.browser.CefBrowser
import org.cef.browser.CefFrame
import org.cef.handler.CefLoadHandlerAdapter

// Add a load handler to inject the bridge after page loads
browser.jbCefClient.addLoadHandler(object : CefLoadHandlerAdapter() {
    override fun onLoadEnd(cefBrowser: CefBrowser, frame: CefFrame, httpStatusCode: Int) {
        if (frame.isMain) {
            // Create the bridge function in the page
            val injectedJs = """
                window.__sendToHost = function(message) {
                    ${jsQuery.inject("message")}
                };

                // Notify the page that the bridge is ready
                window.dispatchEvent(new CustomEvent('hostBridgeReady'));
            """.trimIndent()

            cefBrowser.executeJavaScript(injectedJs, cefBrowser.url, 0)
        }
    }
}, browser.cefBrowser)
```

### 2.4 The Inject Pattern Explained

`jsQuery.inject("msg")` generates something like:

```javascript
window.cefQuery_12345({
    request: msg,
    onSuccess: function(response) {},
    onFailure: function(error_code, error_message) {}
});
```

You can also use the three-argument form to handle async responses:

```kotlin
val injectedJs = """
    window.__sendToHost = function(message) {
        return new Promise(function(resolve, reject) {
            ${jsQuery.inject(
                "message",           // request expression
                "function(r) { resolve(r); }",  // onSuccess
                "function(c, m) { reject(new Error(m)); }"  // onFailure
            )}
        });
    };
""".trimIndent()
```

### 2.5 Sending Data from Host to JS

```kotlin
// Simple: execute JavaScript that the page listens for
fun sendToWebview(type: String, payload: String) {
    val escapedPayload = payload
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")

    browser.cefBrowser.executeJavaScript(
        """
        window.dispatchEvent(new CustomEvent('hostMessage', {
            detail: { type: "$type", payload: "$escapedPayload" }
        }));
        """.trimIndent(),
        browser.cefBrowser.url,
        0
    )
}
```

### 2.6 Recommended Full Bridge Pattern

This is the recommended complete bidirectional communication pattern:

**Kotlin side:**

```kotlin
class WebviewBridge(
    private val browser: JBCefBrowser,
    private val project: Project
) : Disposable {

    private val jsQuery = JBCefJSQuery.create(browser as JBCefBrowserBase)
    private val objectMapper = ObjectMapper()

    init {
        jsQuery.addHandler { rawMessage ->
            try {
                val message = objectMapper.readTree(rawMessage)
                val type = message.get("type").asText()
                val payload = message.get("payload")

                val response = handleMessage(type, payload)
                JBCefJSQuery.Response(objectMapper.writeValueAsString(response))
            } catch (e: Exception) {
                JBCefJSQuery.Response(null, 1, e.message ?: "Unknown error")
            }
        }

        // Inject bridge when page loads
        browser.jbCefClient.addLoadHandler(object : CefLoadHandlerAdapter() {
            override fun onLoadEnd(cefBrowser: CefBrowser, frame: CefFrame, httpStatusCode: Int) {
                if (frame.isMain) {
                    injectBridge(cefBrowser)
                }
            }
        }, browser.cefBrowser)
    }

    private fun injectBridge(cefBrowser: CefBrowser) {
        val js = """
            (function() {
                // JS -> Host communication
                window.__sendToHost = function(type, payload) {
                    return new Promise(function(resolve, reject) {
                        var message = JSON.stringify({ type: type, payload: payload });
                        ${jsQuery.inject(
                            "message",
                            "function(response) { resolve(JSON.parse(response)); }",
                            "function(code, msg) { reject(new Error(msg)); }"
                        )}
                    });
                };

                // Host -> JS communication (event-based)
                window.__hostMessageHandlers = {};
                window.onHostMessage = function(type, handler) {
                    window.__hostMessageHandlers[type] = handler;
                };

                window.addEventListener('hostMessage', function(e) {
                    var handler = window.__hostMessageHandlers[e.detail.type];
                    if (handler) handler(e.detail.payload);
                });

                // Signal readiness
                window.dispatchEvent(new CustomEvent('hostBridgeReady'));
            })();
        """.trimIndent()
        cefBrowser.executeJavaScript(js, cefBrowser.url, 0)
    }

    fun postMessage(type: String, payload: Any?) {
        val json = objectMapper.writeValueAsString(mapOf("type" to type, "payload" to payload))
        val escaped = json.replace("\\", "\\\\").replace("'", "\\'")
        browser.cefBrowser.executeJavaScript(
            """
            window.dispatchEvent(new CustomEvent('hostMessage', {
                detail: JSON.parse('$escaped')
            }));
            """.trimIndent(),
            browser.cefBrowser.url,
            0
        )
    }

    private fun handleMessage(type: String, payload: JsonNode?): Any {
        return when (type) {
            "ready" -> mapOf("status" to "ok")
            "getTheme" -> getCurrentThemeInfo()
            "sendInput" -> {
                // Forward to CLI process
                handleUserInput(payload?.asText() ?: "")
                mapOf("status" to "ok")
            }
            else -> mapOf("error" to "Unknown message type: $type")
        }
    }

    override fun dispose() {
        jsQuery.dispose()
    }
}
```

**JavaScript side:**

```javascript
// Wait for bridge to be ready
function waitForBridge() {
    return new Promise((resolve) => {
        if (window.__sendToHost) {
            resolve();
        } else {
            window.addEventListener('hostBridgeReady', () => resolve(), { once: true });
        }
    });
}

// Usage
async function init() {
    await waitForBridge();

    // Send message to host and get response
    const themeInfo = await window.__sendToHost('getTheme', null);
    applyTheme(themeInfo);

    // Listen for host-initiated messages
    window.onHostMessage('cliOutput', (data) => {
        appendOutput(data);
    });

    window.onHostMessage('themeChanged', (themeInfo) => {
        applyTheme(themeInfo);
    });
}

init();
```

### 2.7 Multiple JBCefJSQuery Instances

You can create multiple `JBCefJSQuery` instances for different purposes (e.g., one for general messages, one for streaming data). Each gets a unique CEF query ID. However, a single query with JSON message routing is generally simpler and recommended.

### 2.8 Threading Considerations for JBCefJSQuery

- The handler callback runs on **CEF's IO thread**, not the EDT.
- If you need to access IntelliJ APIs (which often require EDT), use `ApplicationManager.getApplication().invokeLater { ... }`.
- If you need to return a response synchronously but compute it on EDT, this creates a deadlock risk. Instead, use the fire-and-forget pattern (return immediately, send response via `executeJavaScript` later).

```kotlin
jsQuery.addHandler { rawMessage ->
    // Parse on CEF thread (fast)
    val message = parseMessage(rawMessage)

    // Offload to background thread for heavy work
    ApplicationManager.getApplication().executeOnPooledThread {
        val result = heavyComputation(message)

        // Send result back to JS via executeJavaScript
        ApplicationManager.getApplication().invokeLater {
            sendToWebview("result", result)
        }
    }

    // Return immediately
    null  // or JBCefJSQuery.Response("ack")
}
```

---

## 3. Loading Local HTML/JS/CSS

### 3.1 Option A: `loadHTML()` with Inline Content

The simplest approach. All HTML/CSS/JS is inlined into a single string.

```kotlin
browser.loadHTML("""
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body { font-family: sans-serif; margin: 0; padding: 16px; }
        </style>
    </head>
    <body>
        <div id="app"></div>
        <script>
            // Your JS here
        </script>
    </body>
    </html>
""".trimIndent())
```

**Pros:** Simple, no CSP issues.
**Cons:** Impossible for large apps; no caching; hard to maintain.

### 3.2 Option B: `loadHTML()` with Resource Embedding

Read bundled resources and inline them into the HTML template:

```kotlin
fun loadWebviewFromResources(browser: JBCefBrowser) {
    val cssContent = loadResource("/webview/index.css")
    val jsContent = loadResource("/webview/index.js")
    val fontBase64 = loadResourceBase64("/webview/codicon.ttf")

    val html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta http-equiv="Content-Security-Policy"
                  content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src data:;">
            <style>
                @font-face {
                    font-family: 'codicon';
                    src: url(data:font/ttf;base64,$fontBase64) format('truetype');
                }
                $cssContent
            </style>
        </head>
        <body>
            <div id="root"></div>
            <script>
                $jsContent
            </script>
        </body>
        </html>
    """.trimIndent()

    browser.loadHTML(html, "https://localhost")
}

private fun loadResource(path: String): String {
    return MyToolWindowFactory::class.java.getResourceAsStream(path)
        ?.bufferedReader()?.readText()
        ?: throw IllegalStateException("Resource not found: $path")
}

private fun loadResourceBase64(path: String): String {
    val bytes = MyToolWindowFactory::class.java.getResourceAsStream(path)
        ?.readAllBytes()
        ?: throw IllegalStateException("Resource not found: $path")
    return java.util.Base64.getEncoder().encodeToString(bytes)
}
```

**Pros:** Works reliably; full CSP control; no external requests needed.
**Cons:** Large JS bundles mean large HTML strings; no lazy loading of assets.

### 3.3 Option C: Custom Scheme Handler (Recommended for Large Apps)

Register a custom CEF scheme handler to serve local resources via a virtual URL scheme. This is the **recommended approach for non-trivial webviews** like our React app.

```kotlin
import org.cef.browser.CefBrowser
import org.cef.callback.CefCallback
import org.cef.handler.CefResourceHandler
import org.cef.handler.CefResourceHandlerAdapter
import org.cef.misc.IntRef
import org.cef.misc.StringRef
import org.cef.network.CefRequest
import org.cef.network.CefResponse
import com.intellij.ui.jcef.JBCefApp
import java.io.ByteArrayInputStream
import java.io.InputStream

class LocalResourceSchemeHandlerFactory : CefSchemeHandlerFactory {
    override fun create(
        browser: CefBrowser?,
        frame: CefFrame?,
        schemeName: String?,
        request: CefRequest?
    ): CefResourceHandler {
        return LocalResourceHandler()
    }
}

class LocalResourceHandler : CefResourceHandler {
    private var inputStream: InputStream? = null
    private var mimeType: String = "text/html"
    private var responseLength: Int = 0

    override fun processRequest(request: CefRequest, callback: CefCallback): Boolean {
        val url = request.url ?: return false
        // URL format: claud://app/webview/index.html
        val path = url.removePrefix("claude://app/")

        val resourcePath = "/webview/$path"
        val bytes = javaClass.getResourceAsStream(resourcePath)?.readAllBytes()

        if (bytes != null) {
            inputStream = ByteArrayInputStream(bytes)
            responseLength = bytes.size
            mimeType = getMimeType(path)
            callback.Continue()
            return true
        }

        return false
    }

    override fun getResponseHeaders(
        response: CefResponse,
        responseLength: IntRef,
        redirectUrl: StringRef
    ) {
        response.mimeType = mimeType
        response.status = 200
        responseLength.set(this.responseLength)
    }

    override fun readResponse(
        dataOut: ByteArray,
        bytesToRead: Int,
        bytesRead: IntRef,
        callback: CefCallback
    ): Boolean {
        val stream = inputStream ?: return false
        val available = stream.available()
        if (available == 0) return false

        val toRead = minOf(bytesToRead, available)
        val read = stream.read(dataOut, 0, toRead)
        bytesRead.set(read)
        return true
    }

    override fun cancel() {
        inputStream?.close()
        inputStream = null
    }

    private fun getMimeType(path: String): String = when {
        path.endsWith(".html") -> "text/html"
        path.endsWith(".css") -> "text/css"
        path.endsWith(".js") -> "application/javascript"
        path.endsWith(".json") -> "application/json"
        path.endsWith(".svg") -> "image/svg+xml"
        path.endsWith(".png") -> "image/png"
        path.endsWith(".ttf") -> "font/ttf"
        path.endsWith(".woff") -> "font/woff"
        path.endsWith(".woff2") -> "font/woff2"
        else -> "application/octet-stream"
    }
}
```

**Register the scheme handler at app startup:**

```kotlin
// In your plugin's initialization or a StartupActivity
class JcefSchemeRegistrar : com.intellij.ide.AppLifecycleListener {
    override fun appStarted() {
        if (JBCefApp.isSupported()) {
            val cefApp = JBCefApp.getInstance().cefApp
            // Register before any browsers are created
            cefApp.registerSchemeHandlerFactory(
                "claude", "app",
                LocalResourceSchemeHandlerFactory()
            )
        }
    }
}
```

**Then load the page:**

```kotlin
browser.loadURL("claude://app/index.html")
```

**Pros:**
- Each file is served individually (like a real web server)
- Relative paths in HTML (`<script src="index.js">`, `<link rel="stylesheet" href="index.css">`) work naturally
- Browser caching works
- DevTools shows individual files in Sources tab
- Supports lazy loading, dynamic imports
- Most similar to real web development

**Cons:**
- More setup code
- Custom scheme names must be registered early in app lifecycle

### 3.4 Option D: Embedded HTTP Server

Run a lightweight HTTP server on localhost to serve assets:

```kotlin
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress

class LocalWebServer(private val port: Int = 0) {
    private val server = HttpServer.create(InetSocketAddress("127.0.0.1", port), 0)

    fun start(): Int {
        server.createContext("/") { exchange ->
            val path = exchange.requestURI.path.trimStart('/')
            val resourcePath = "/webview/${path.ifEmpty { "index.html" }}"

            val bytes = javaClass.getResourceAsStream(resourcePath)?.readAllBytes()
            if (bytes != null) {
                val mimeType = getMimeType(path)
                exchange.responseHeaders.add("Content-Type", mimeType)
                exchange.responseHeaders.add("Access-Control-Allow-Origin", "*")
                exchange.sendResponseHeaders(200, bytes.size.toLong())
                exchange.responseBody.write(bytes)
            } else {
                exchange.sendResponseHeaders(404, 0)
            }
            exchange.close()
        }

        server.start()
        return server.address.port  // returns the actual port (dynamic if 0)
    }

    fun stop() {
        server.stop(0)
    }
}

// Usage:
val webServer = LocalWebServer()
val port = webServer.start()
browser.loadURL("http://127.0.0.1:$port/index.html")
```

**Pros:** Full HTTP behavior; works with any web tooling; hot reload possible.
**Cons:** Port conflicts; security concerns; firewall issues; extra resource consumption.

### 3.5 Security Considerations

#### Content Security Policy (CSP)

When using `loadHTML()`, inject a CSP meta tag:

```html
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none';
               script-src 'unsafe-inline';
               style-src 'unsafe-inline';
               font-src data: claude://app/;
               img-src data: claude://app/;
               connect-src claude://app/;">
```

When using the custom scheme handler, CSP can be set via response headers in `getResponseHeaders()`:

```kotlin
override fun getResponseHeaders(response: CefResponse, ...) {
    response.setHeaderByName(
        "Content-Security-Policy",
        "default-src 'self' claude://app/; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'",
        false
    )
}
```

#### Same-Origin Policy

- `loadHTML()` pages have the origin `about:blank` or the base URL you provide.
- Custom scheme URLs (e.g., `claude://app/`) get their own origin.
- Requests from the page to external URLs are blocked unless explicitly allowed.

#### Recommendation

For our Claude Code plugin with a substantial React frontend:
- **Use Option C (custom scheme handler)** as the primary approach.
- This allows the React app to be bundled as separate files (index.html, index.js, index.css) and served naturally.
- Falls back gracefully (the scheme just serves from the JAR's classpath resources).

---

## 4. Performance Best Practices

### 4.1 Threading Model

JCEF uses multiple threads:

| Thread | Purpose | Notes |
|--------|---------|-------|
| **EDT (Event Dispatch Thread)** | Swing UI updates | IntelliJ's main UI thread |
| **CEF UI Thread** | CEF browser UI operations | Separate from EDT |
| **CEF IO Thread** | Network and JS bridge callbacks | Where `JBCefJSQuery` handlers run |
| **CEF Renderer Thread** | Page rendering | Internal to CEF |

**Critical rules:**
1. `JBCefBrowser` creation and `component` access must happen on **EDT**.
2. `executeJavaScript()` can be called from any thread.
3. `JBCefJSQuery` handler callbacks run on the **CEF IO thread** -- never block this thread.
4. Never perform long-running operations on EDT or CEF IO thread.

```kotlin
// CORRECT: Heavy work on pooled thread, UI update on EDT
jsQuery.addHandler { message ->
    // Fast parse on CEF IO thread
    val parsed = parseMessage(message)

    // Offload to background
    ApplicationManager.getApplication().executeOnPooledThread {
        val result = expensiveOperation(parsed)

        // Update UI on EDT
        ApplicationManager.getApplication().invokeLater {
            updateUIComponent(result)
        }
    }

    // Return immediate ack
    JBCefJSQuery.Response("""{"status":"received"}""")
}
```

### 4.2 Avoiding UI Freezes

1. **Never call `loadURL()` or `loadHTML()` with very large content on EDT synchronously.** The browser creation is async internally, but extremely large HTML strings can cause allocation pauses.

2. **Debounce rapid `executeJavaScript()` calls.** If you are streaming CLI output, batch updates:

```kotlin
class BatchedWebviewUpdater(private val browser: JBCefBrowser) {
    private val buffer = StringBuilder()
    private val alarm = SingleAlarm(::flush, 16, Disposer.newDisposable()) // ~60fps

    fun appendOutput(text: String) {
        synchronized(buffer) {
            buffer.append(text)
        }
        alarm.request()
    }

    private fun flush() {
        val content = synchronized(buffer) {
            val s = buffer.toString()
            buffer.clear()
            s
        }
        if (content.isNotEmpty()) {
            val escaped = escapeForJs(content)
            browser.cefBrowser.executeJavaScript(
                "window.__appendOutput('$escaped')",
                browser.cefBrowser.url, 0
            )
        }
    }
}
```

3. **Use `ReadAction.nonBlocking()` for file operations** that feed data into the webview:

```kotlin
ReadAction.nonBlocking<String> {
    // Read project files safely
    FileDocumentManager.getInstance().getDocument(virtualFile)?.text ?: ""
}.expireWith(disposable)
 .finishOnUiThread(ModalityState.defaultModalityState()) { text ->
    sendToWebview("fileContent", text)
 }
 .submit(AppExecutorUtil.getAppExecutorService())
```

### 4.3 Memory Management

1. **Always dispose browsers.** Register them with a parent `Disposable`:

```kotlin
Disposer.register(parentDisposable, browser)
Disposer.register(parentDisposable, jsQuery)
```

2. **Dispose JBCefJSQuery before JBCefBrowser.** The query holds a reference to the browser's native resources.

3. **Limit number of browser instances.** Each `JBCefBrowser` is a full Chromium renderer process. Reuse a single browser instance per tool window.

4. **Clear large JavaScript objects when done:**

```javascript
// In the webview, clear large data when switching contexts
window.addEventListener('beforeunload', () => {
    window.__largeDataSet = null;
});
```

5. **Monitor memory usage** in development using `chrome://memory-internals` (loadable in JCEF if scheme is allowed) or by checking `CefApp.getInstance().isDisposed`.

### 4.4 Startup Performance

1. **Lazy-initialize the browser.** Don't create it until the tool window is first opened:

```kotlin
class ClaudeToolWindowFactory : ToolWindowFactory {
    // Tool window content is created lazily by default
    override fun shouldBeAvailable(project: Project) = true

    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        // This runs only when user first opens the tool window
        val browser = JBCefBrowserBuilder()
            .setCreateImmediately(false)  // defer native browser creation
            .build()
        // ...
    }
}
```

2. **Pre-warm on background thread** if you expect the user to open the panel soon:

```kotlin
// In a startup activity, after IDE is idle
StartupManager.getInstance(project).runAfterOpened {
    ApplicationManager.getApplication().executeOnPooledThread {
        if (JBCefApp.isSupported()) {
            JBCefApp.getInstance()  // triggers CEF initialization
        }
    }
}
```

---

## 5. Dark Theme Integration

### 5.1 Detecting IDE Theme

IntelliJ provides `UIManager` and `JBColor` to detect theme. The approach is to read IDE theme colors and pass them to the webview.

```kotlin
import com.intellij.util.ui.UIUtil
import com.intellij.ui.JBColor
import javax.swing.UIManager

fun getCurrentThemeInfo(): Map<String, String> {
    val isDark = UIUtil.isUnderDarcula()

    // Read colors from IntelliJ's UIManager
    val bgColor = UIManager.getColor("Panel.background")
    val fgColor = UIManager.getColor("Panel.foreground")
    val editorBg = UIManager.getColor("Editor.background") ?: bgColor
    val borderColor = UIManager.getColor("Borders.color") ?: JBColor.border()
    val linkColor = UIManager.getColor("Link.activeForeground") ?: JBColor.BLUE
    val selectionBg = UIManager.getColor("List.selectionBackground")
    val selectionFg = UIManager.getColor("List.selectionForeground")
    val inputBg = UIManager.getColor("TextField.background")
    val inputBorder = UIManager.getColor("Component.borderColor")

    return mapOf(
        "isDark" to isDark.toString(),
        "background" to colorToHex(bgColor),
        "foreground" to colorToHex(fgColor),
        "editorBackground" to colorToHex(editorBg),
        "border" to colorToHex(borderColor),
        "link" to colorToHex(linkColor),
        "selectionBackground" to colorToHex(selectionBg),
        "selectionForeground" to colorToHex(selectionFg),
        "inputBackground" to colorToHex(inputBg),
        "inputBorder" to colorToHex(inputBorder),
        "fontFamily" to (UIManager.getFont("Label.font")?.family ?: "sans-serif"),
        "fontSize" to (UIManager.getFont("Label.font")?.size?.toString() ?: "13")
    )
}

private fun colorToHex(color: java.awt.Color?): String {
    if (color == null) return "#000000"
    return String.format("#%02x%02x%02x", color.red, color.green, color.blue)
}
```

### 5.2 Sending Theme to Webview

```kotlin
fun syncThemeToWebview() {
    val theme = getCurrentThemeInfo()
    val json = ObjectMapper().writeValueAsString(theme)
    browser.cefBrowser.executeJavaScript(
        "window.__applyIdeTheme && window.__applyIdeTheme($json);",
        browser.cefBrowser.url, 0
    )
}
```

### 5.3 Listening for Theme Changes

Register a `LafManagerListener` to detect when the user changes the IDE theme:

```kotlin
import com.intellij.ide.ui.LafManagerListener

// In your service init or tool window creation:
project.messageBus.connect(disposable).subscribe(
    LafManagerListener.TOPIC,
    LafManagerListener {
        // Theme changed - update webview
        syncThemeToWebview()
    }
)
```

### 5.4 Applying Theme in JavaScript/CSS

```javascript
window.__applyIdeTheme = function(theme) {
    const root = document.documentElement;
    root.style.setProperty('--ide-bg', theme.background);
    root.style.setProperty('--ide-fg', theme.foreground);
    root.style.setProperty('--ide-editor-bg', theme.editorBackground);
    root.style.setProperty('--ide-border', theme.border);
    root.style.setProperty('--ide-link', theme.link);
    root.style.setProperty('--ide-selection-bg', theme.selectionBackground);
    root.style.setProperty('--ide-selection-fg', theme.selectionForeground);
    root.style.setProperty('--ide-input-bg', theme.inputBackground);
    root.style.setProperty('--ide-input-border', theme.inputBorder);
    root.style.setProperty('--ide-font-family', theme.fontFamily);
    root.style.setProperty('--ide-font-size', theme.fontSize + 'px');

    document.body.classList.toggle('dark', theme.isDark === 'true');
    document.body.classList.toggle('light', theme.isDark !== 'true');
};
```

```css
/* CSS using IDE theme variables */
body {
    background-color: var(--ide-bg, #1e1e1e);
    color: var(--ide-fg, #cccccc);
    font-family: var(--ide-font-family, -apple-system, BlinkMacSystemFont, sans-serif);
    font-size: var(--ide-font-size, 13px);
}

.input-area {
    background: var(--ide-input-bg, #2d2d2d);
    border: 1px solid var(--ide-input-border, #3c3c3c);
}

a { color: var(--ide-link, #589df6); }
```

### 5.5 Known IntelliJ UIManager Color Keys

Commonly useful `UIManager` color keys for theming:

| Key | Description |
|-----|-------------|
| `Panel.background` | Main panel background |
| `Panel.foreground` | Main text color |
| `Editor.background` | Code editor background |
| `Editor.foreground` | Code editor text color |
| `Borders.color` | Standard border color |
| `Component.borderColor` | Input field borders |
| `TextField.background` | Text input background |
| `TextField.foreground` | Text input text color |
| `List.selectionBackground` | Selection highlight |
| `List.selectionForeground` | Selected item text |
| `Link.activeForeground` | Hyperlink color |
| `ToolWindow.Header.background` | Tool window header |
| `ScrollBar.track` | Scrollbar track |
| `ScrollBar.thumb` | Scrollbar thumb |
| `Tree.selectionBackground` | Tree item selection |
| `Table.stripeColor` | Alternating row color |
| `Notification.background` | Notification popup bg |

---

## 6. DevTools for Debugging

### 6.1 Enabling DevTools via Builder

```kotlin
val browser = JBCefBrowserBuilder()
    .setEnableOpenDevToolsMenuItem(true)
    .build()
```

With this setting, right-clicking in the browser shows "Open DevTools" in the context menu.

### 6.2 Opening DevTools Programmatically

```kotlin
// Open DevTools in a separate window
browser.openDevtools()

// Or via the underlying CEF API
browser.cefBrowser.devTools  // Returns CefBrowser instance for DevTools
```

### 6.3 Using the Registry Key

In IntelliJ, you can enable JCEF DevTools globally via the Registry:

1. Open **Help > Find Action** (Ctrl+Shift+A / Cmd+Shift+A)
2. Type "Registry"
3. Find key: `ide.browser.jcef.debug.port`
4. Set a port number (e.g., `9222`)
5. Restart IDE
6. Open Chrome and navigate to `chrome://inspect`
7. Configure target discovery for `localhost:9222`

This enables **remote debugging** of all JCEF browsers from an external Chrome window, which is extremely useful during development.

### 6.4 Debug-Only Keyboard Shortcut

Add a keyboard shortcut for quick DevTools toggle during development:

```kotlin
// In your tool window setup (debug builds only)
if (ApplicationManager.getApplication().isInternal) {
    browser.cefBrowser.executeJavaScript("""
        document.addEventListener('keydown', function(e) {
            if (e.key === 'F12' || (e.ctrlKey && e.shiftKey && e.key === 'I')) {
                // F12 or Ctrl+Shift+I to toggle DevTools
                // This requires the DevTools menu to be enabled
            }
        });
    """.trimIndent(), browser.cefBrowser.url, 0)
}
```

### 6.5 Console.log Capture

Capture `console.log` output from the webview in the IntelliJ log:

```kotlin
import org.cef.handler.CefDisplayHandlerAdapter

browser.jbCefClient.addDisplayHandler(object : CefDisplayHandlerAdapter() {
    override fun onConsoleMessage(
        browser: CefBrowser,
        level: CefSettings.LogSeverity,
        message: String,
        source: String,
        line: Int
    ): Boolean {
        val logger = com.intellij.openapi.diagnostic.Logger.getInstance("ClaudeWebview")
        when (level) {
            CefSettings.LogSeverity.LOGSEVERITY_ERROR -> logger.error("[$source:$line] $message")
            CefSettings.LogSeverity.LOGSEVERITY_WARNING -> logger.warn("[$source:$line] $message")
            else -> logger.info("[$source:$line] $message")
        }
        return false  // false = also show in DevTools console
    }
}, browser.cefBrowser)
```

---

## 7. Alternatives to JCEF

### 7.1 IntelliJ Swing UI (Traditional)

The classic approach uses Swing/AWT components with IntelliJ's UI DSL:

```kotlin
// Kotlin UI DSL v2 (recommended for settings panels)
val panel = panel {
    row("Model:") {
        comboBox(listOf("Claude Sonnet", "Claude Opus"))
    }
    row {
        textArea()
            .rows(10)
            .columns(50)
            .align(Align.FILL)
    }
}
```

**Verdict for our use case:** Unsuitable. We have a complex React-based conversational UI that cannot be reasonably replicated in Swing. Swing is appropriate for settings pages and simple forms, not rich interactive webviews.

### 7.2 Compose for Desktop / Jewel

JetBrains has been developing **Jewel** (JetBrains' Compose for Desktop theme for IntelliJ) as a modern UI toolkit for IntelliJ plugins.

**Status as of 2025:**
- Jewel is available at `https://github.com/JetBrains/jewel`
- It provides IntelliJ-themed Compose for Desktop components
- Still marked as experimental/incubating for plugin development
- Not yet a first-class replacement for Swing in production IntelliJ plugins
- Does **not** render web content (HTML/JS/CSS) -- it's a native UI framework

```kotlin
// Jewel example (Compose for Desktop with IntelliJ theme)
// Requires: org.jetbrains.jewel dependency
@Composable
fun MyToolWindowContent() {
    JewelTheme {
        Column {
            Text("Hello from Compose!")
            TextField(value = text, onValueChange = { text = it })
        }
    }
}
```

**Verdict for our use case:** Not suitable yet. Jewel is promising for future native-feel UIs, but:
1. It doesn't render web content (can't reuse our React frontend)
2. The API is still evolving
3. Plugin marketplace support is limited
4. We'd have to rewrite the entire UI in Compose, losing the shared codebase with VSCode

### 7.3 JxBrowser (Third-Party)

JxBrowser is a commercial Chromium-based browser component for Java/Kotlin, similar to JCEF but maintained by TeamDev.

**Verdict:** Not recommended. JCEF is free, built-in to IntelliJ, and actively maintained by JetBrains. JxBrowser adds a commercial dependency for no clear benefit.

### 7.4 JavaFX WebView

JavaFX includes a `WebView` component based on WebKit.

**Verdict:** Strongly not recommended. JavaFX WebView is WebKit-based (not Chromium), has worse JavaScript compatibility, is not bundled with IntelliJ, and would require bundling the JavaFX runtime.

### 7.5 Recommendation

**JCEF is the correct choice** for this project:
- It is the officially supported way to embed web content in IntelliJ plugins
- It allows reuse of the React frontend from the VSCode extension
- It provides a full modern Chromium browser with DevTools
- JetBrains is actively maintaining and improving it
- All major plugins with webviews use JCEF

Long-term, watch Jewel/Compose for Desktop for potential native UI rewrites, but JCEF is the right choice for 2025.

---

## 8. Real-World Examples

### 8.1 GitHub Copilot for JetBrains

GitHub Copilot's JetBrains plugin uses JCEF for its chat panel:
- **Source:** Bundled with JetBrains IDEs (closed source, but observable)
- **Architecture:** JCEF webview in a tool window, similar to our planned approach
- **Communication:** Uses `JBCefJSQuery` for bidirectional JS-Kotlin messaging
- **Theme:** Syncs IDE theme to webview via CSS variables
- **Key insight:** Copilot Chat renders Markdown in the webview, handles streaming responses, and manages conversation state entirely in the JS layer -- very similar to our Claude Code UI

### 8.2 JetBrains AI Assistant

JetBrains' own AI Assistant plugin (bundled since 2023.3):
- Uses JCEF for the chat interface
- Demonstrates the JetBrains-recommended pattern for AI chat in a tool window
- Handles theme synchronization, message streaming, code block rendering
- **Key insight:** JetBrains chose JCEF over Swing/Compose for their own AI chat UI, validating our approach

### 8.3 Markdown Preview

The built-in Markdown plugin uses JCEF for live preview:
- **Source:** Part of IntelliJ Community Edition (open source)
- **Repository:** `https://github.com/JetBrains/intellij-community/tree/master/plugins/markdown`
- **Key classes:**
  - `MarkdownJCEFHtmlPanel` -- main JCEF panel implementation
  - Uses `JBCefBrowser.loadHTML()` for content
  - Handles scroll synchronization between editor and preview
  - Theme-aware rendering

### 8.4 PlantUML Integration

The PlantUML plugin uses JCEF for SVG diagram rendering:
- **Repository:** `https://github.com/esteinberg/plantuml4idea`
- Uses JCEF to render SVG diagrams in a preview panel
- Demonstrates zoom, scroll, and theme handling

### 8.5 JetBrains Space Plugin

The Space plugin (now deprecated in favor of JetBrains integrations) used JCEF for:
- Code review UI
- Document previews
- Rich text editing
- **Key insight:** Demonstrated complex bidirectional communication patterns with `JBCefJSQuery`

### 8.6 Open-Source JCEF Sample Projects

- **intellij-jcef-sample-plugin** (`https://github.com/nicholasgasior/intellij-jcef-sample-plugin`)
  - Clean minimal example of JCEF in a tool window
  - Shows `JBCefBrowser` + `JBCefJSQuery` pattern
  - Good starting reference

- **IntelliJ Platform Plugin Template** (`https://github.com/JetBrains/intellij-platform-plugin-template`)
  - Official JetBrains plugin template
  - Doesn't use JCEF by default but is the recommended project scaffolding

### 8.7 Key Patterns Observed Across Plugins

| Pattern | Used By | Recommended |
|---------|---------|-------------|
| `loadHTML()` with inlined content | Markdown, small UIs | For simple content |
| Custom scheme handler | Copilot, AI Assistant | For complex webapps |
| Single `JBCefJSQuery` with JSON routing | Most plugins | Yes |
| `LafManagerListener` for theme sync | All theme-aware plugins | Yes |
| `Disposer.register()` for cleanup | All plugins | Yes |
| Console.log capture via `CefDisplayHandler` | Debug builds | Yes (dev only) |

---

## 9. Sources and References

### Official JetBrains Documentation

- **JCEF - Java Chromium Embedded Framework** (IntelliJ Platform SDK Docs)
  `https://plugins.jetbrains.com/docs/intellij/jcef.html`

- **Tool Windows** (IntelliJ Platform SDK Docs)
  `https://plugins.jetbrains.com/docs/intellij/tool-windows.html`

- **Threading Model** (IntelliJ Platform SDK Docs)
  `https://plugins.jetbrains.com/docs/intellij/general-threading-rules.html`

- **Themes and UI Customization**
  `https://plugins.jetbrains.com/docs/intellij/themes-getting-started.html`

### Source Code References

- **JBCefBrowser source** (IntelliJ Community)
  `https://github.com/JetBrains/intellij-community/blob/master/platform/platform-api/src/com/intellij/ui/jcef/JBCefBrowser.java`

- **JBCefJSQuery source**
  `https://github.com/JetBrains/intellij-community/blob/master/platform/platform-api/src/com/intellij/ui/jcef/JBCefJSQuery.java`

- **JBCefBrowserBuilder source**
  `https://github.com/JetBrains/intellij-community/blob/master/platform/platform-api/src/com/intellij/ui/jcef/JBCefBrowserBuilder.java`

- **Markdown plugin JCEF panel**
  `https://github.com/JetBrains/intellij-community/tree/master/plugins/markdown/core/src/org/intellij/plugins/markdown/ui/preview/jcef`

### Community Resources

- **Jewel (Compose for Desktop IntelliJ Theme)**
  `https://github.com/JetBrains/jewel`

- **IntelliJ Platform Plugin Template**
  `https://github.com/JetBrains/intellij-platform-plugin-template`

- **JCEF Sample Plugin**
  `https://github.com/nicholasgasior/intellij-jcef-sample-plugin`

- **IntelliJ Plugin Development Forum**
  `https://intellij-support.jetbrains.com/hc/en-us/community/topics/200366979-IntelliJ-IDEA-Open-API-and-Plugin-Development`

- **JetBrains Platform Slack**
  `https://plugins.jetbrains.com/slack`

---

## Appendix A: Quick Reference - Complete Minimal JCEF Tool Window

This is a copy-paste-ready minimal example combining all the patterns above:

```kotlin
package com.example.myplugin

import com.intellij.ide.ui.LafManagerListener
import com.intellij.openapi.Disposable
import com.intellij.openapi.project.Project
import com.intellij.openapi.util.Disposer
import com.intellij.openapi.wm.ToolWindow
import com.intellij.openapi.wm.ToolWindowFactory
import com.intellij.ui.content.ContentFactory
import com.intellij.ui.jcef.*
import com.intellij.util.ui.UIUtil
import org.cef.browser.CefBrowser
import org.cef.browser.CefFrame
import org.cef.handler.CefLoadHandlerAdapter
import java.awt.BorderLayout
import javax.swing.JLabel
import javax.swing.JPanel
import javax.swing.UIManager

class MyWebviewToolWindowFactory : ToolWindowFactory {

    override fun isApplicable(project: Project) = JBCefApp.isSupported()

    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        val panel = JPanel(BorderLayout())
        val disposable = toolWindow.disposable

        if (!JBCefApp.isSupported()) {
            panel.add(JLabel("Chromium browser is not available"), BorderLayout.CENTER)
            val content = ContentFactory.getInstance().createContent(panel, "", false)
            toolWindow.contentManager.addContent(content)
            return
        }

        // 1. Create browser
        val browser = JBCefBrowserBuilder()
            .setEnableOpenDevToolsMenuItem(true)
            .build()
        Disposer.register(disposable, browser)

        // 2. Create JS bridge
        val jsQuery = JBCefJSQuery.create(browser as JBCefBrowserBase)
        Disposer.register(disposable, jsQuery)

        jsQuery.addHandler { message ->
            // Handle messages from JS (runs on CEF IO thread)
            println("Received from JS: $message")
            JBCefJSQuery.Response("""{"status":"ok"}""")
        }

        // 3. Inject bridge on page load
        browser.jbCefClient.addLoadHandler(object : CefLoadHandlerAdapter() {
            override fun onLoadEnd(b: CefBrowser, frame: CefFrame, status: Int) {
                if (frame.isMain) {
                    b.executeJavaScript("""
                        window.__sendToHost = function(msg) {
                            return new Promise(function(resolve, reject) {
                                ${jsQuery.inject(
                                    "JSON.stringify(msg)",
                                    "function(r) { resolve(JSON.parse(r)); }",
                                    "function(c, m) { reject(new Error(m)); }"
                                )}
                            });
                        };
                        window.dispatchEvent(new CustomEvent('bridgeReady'));
                    """.trimIndent(), b.url, 0)

                    // Send initial theme
                    val isDark = UIUtil.isUnderDarcula()
                    val bg = colorHex(UIManager.getColor("Panel.background"))
                    val fg = colorHex(UIManager.getColor("Panel.foreground"))
                    b.executeJavaScript(
                        "document.body.style.background='$bg';" +
                        "document.body.style.color='$fg';" +
                        "document.body.classList.toggle('dark',$isDark);",
                        b.url, 0
                    )
                }
            }
        }, browser.cefBrowser)

        // 4. Listen for theme changes
        project.messageBus.connect(disposable).subscribe(
            LafManagerListener.TOPIC,
            LafManagerListener {
                val isDark = UIUtil.isUnderDarcula()
                val bg = colorHex(UIManager.getColor("Panel.background"))
                val fg = colorHex(UIManager.getColor("Panel.foreground"))
                browser.cefBrowser.executeJavaScript(
                    "document.body.style.background='$bg';" +
                    "document.body.style.color='$fg';" +
                    "document.body.classList.toggle('dark',$isDark);",
                    browser.cefBrowser.url, 0
                )
            }
        )

        // 5. Load content
        browser.loadHTML("""
            <!DOCTYPE html>
            <html>
            <head><meta charset="UTF-8"></head>
            <body>
                <h1>Hello from JCEF!</h1>
                <button onclick="window.__sendToHost({type:'click',data:'hello'}).then(r => console.log(r))">
                    Send to Host
                </button>
            </body>
            </html>
        """.trimIndent())

        panel.add(browser.component, BorderLayout.CENTER)
        val content = ContentFactory.getInstance().createContent(panel, "", false)
        toolWindow.contentManager.addContent(content)
    }

    private fun colorHex(c: java.awt.Color?): String {
        c ?: return "#000000"
        return String.format("#%02x%02x%02x", c.red, c.green, c.blue)
    }
}
```

**plugin.xml registration:**

```xml
<extensions defaultExtensionNs="com.intellij">
    <toolWindow id="My Webview"
                anchor="right"
                factoryClass="com.example.myplugin.MyWebviewToolWindowFactory"
                icon="AllIcons.General.Web"/>
</extensions>
```

---

## Appendix B: Decision Matrix for Our Claude Code Plugin

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | **JCEF** | Reuse React frontend; complex conversational UI |
| Content Loading | **Custom scheme handler** | Separate files; DevTools-friendly; natural imports |
| Communication | **Single JBCefJSQuery + JSON** | Simple, proven pattern |
| Theme Sync | **CSS variables via LafManagerListener** | Standard approach; all major plugins use it |
| DevTools | **Enable in dev builds via builder flag** | Essential for debugging |
| Fallback | **Swing JLabel with "not supported" message** | Graceful degradation |
| Data Streaming | **Batched executeJavaScript at 60fps** | Avoid UI freezes during CLI streaming |
| Disposal | **Disposer.register chain** | Prevent memory leaks |
