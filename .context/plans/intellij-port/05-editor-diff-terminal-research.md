# IntelliJ Platform API Research: Editor, Diff, Terminal & Notifications

> Research date: 2025 (covers IntelliJ Platform 2024.x - 2025.x APIs)
> Use case: AI coding assistant plugin needing editor context, code change application, diff review, and terminal integration.

---

## Table of Contents

1. [Editor APIs](#1-editor-apis)
2. [Document Modification](#2-document-modification)
3. [DiffManager](#3-diffmanager)
4. [SimpleDiffRequest vs MergeRequest](#4-simplediffrequest-vs-mergerequest)
5. [Virtual File System](#5-virtual-file-system)
6. [File Change Events](#6-file-change-events)
7. [Editor Decorations and Inlays](#7-editor-decorations-and-inlays)
8. [Context Menu Integration](#8-context-menu-integration)
9. [Multi-Caret Support](#9-multi-caret-support)
10. [Undo Integration](#10-undo-integration)
11. [Terminal API](#11-terminal-api)
12. [Notification API](#12-notification-api)
13. [Threading Model Summary](#13-threading-model-summary)
14. [Recommendations for Claude Code Plugin](#14-recommendations-for-claude-code-plugin)

---

## 1. Editor APIs

### Key Classes

| Class | Purpose |
|-------|---------|
| `FileEditorManager` | Manages open file editors per project |
| `EditorFactory` | Creates editors and listens for editor events globally |
| `Editor` | Core editor interface - access to document, caret, selection, scrolling |
| `CaretModel` | Cursor position(s) within an editor |
| `SelectionModel` | Text selection(s) within an editor |
| `ScrollingModel` | Scroll position and visible area |
| `FoldingModel` | Code folding regions |
| `FileDocumentManager` | Maps between `Document` and `VirtualFile` |

### Getting the Active Editor

```kotlin
import com.intellij.openapi.editor.Editor
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.project.Project

fun getActiveEditor(project: Project): Editor? {
    return FileEditorManager.getInstance(project).selectedTextEditor
}
```

**Important:** `selectedTextEditor` can return `null` if no text editor is focused (e.g., user is in a tool window or a non-text editor like an image viewer).

### Getting the Current File Path

```kotlin
import com.intellij.openapi.fileEditor.FileDocumentManager

fun getCurrentFilePath(project: Project): String? {
    val editor = FileEditorManager.getInstance(project).selectedTextEditor ?: return null
    val virtualFile = FileDocumentManager.getInstance().getFile(editor.document)
    return virtualFile?.path  // Absolute OS path
}
```

**Note:** `VirtualFile.path` returns the absolute OS path (e.g., `/Users/dev/project/src/Main.kt`). Use `VirtualFile.presentableUrl` for display purposes. For project-relative paths, compute it against `project.basePath`.

### Getting Selected Text

```kotlin
fun getSelectedText(editor: Editor): String? {
    return editor.selectionModel.selectedText
}

// With full range information
fun getSelectionInfo(editor: Editor): SelectionInfo? {
    val selectionModel = editor.selectionModel
    if (!selectionModel.hasSelection()) return null

    return SelectionInfo(
        text = selectionModel.selectedText ?: return null,
        startOffset = selectionModel.selectionStart,
        endOffset = selectionModel.selectionEnd,
        startLine = editor.document.getLineNumber(selectionModel.selectionStart),
        endLine = editor.document.getLineNumber(selectionModel.selectionEnd),
        startColumn = selectionModel.selectionStart -
            editor.document.getLineStartOffset(
                editor.document.getLineNumber(selectionModel.selectionStart)
            ),
        endColumn = selectionModel.selectionEnd -
            editor.document.getLineStartOffset(
                editor.document.getLineNumber(selectionModel.selectionEnd)
            )
    )
}

data class SelectionInfo(
    val text: String,
    val startOffset: Int,
    val endOffset: Int,
    val startLine: Int,
    val endLine: Int,
    val startColumn: Int,
    val endColumn: Int
)
```

### Getting Cursor Position

```kotlin
import com.intellij.openapi.editor.LogicalPosition
import com.intellij.openapi.editor.VisualPosition

fun getCursorPosition(editor: Editor): CursorPosition {
    val caret = editor.caretModel.primaryCaret
    val logicalPos = caret.logicalPosition
    val offset = caret.offset

    return CursorPosition(
        line = logicalPos.line,        // 0-based line number
        column = logicalPos.column,    // 0-based column number
        offset = offset,               // Absolute offset in document
        visualLine = caret.visualPosition.line,  // Accounts for folding
        visualColumn = caret.visualPosition.column
    )
}

data class CursorPosition(
    val line: Int,
    val column: Int,
    val offset: Int,
    val visualLine: Int,
    val visualColumn: Int
)
```

**LogicalPosition vs VisualPosition:** `LogicalPosition` is the actual line/column in the document. `VisualPosition` accounts for soft-wraps and code folding -- it is what the user visually sees. For sending context to an AI, use `LogicalPosition`.

### Getting the Visible Range

```kotlin
fun getVisibleRange(editor: Editor): VisibleRange {
    val visibleArea = editor.scrollingModel.visibleArea
    val startLine = editor.xyToLogicalPosition(
        java.awt.Point(0, visibleArea.y)
    ).line
    val endLine = editor.xyToLogicalPosition(
        java.awt.Point(0, visibleArea.y + visibleArea.height)
    ).line

    val document = editor.document
    val startOffset = document.getLineStartOffset(startLine.coerceAtMost(document.lineCount - 1))
    val endOffset = document.getLineEndOffset(endLine.coerceAtMost(document.lineCount - 1))

    return VisibleRange(
        startLine = startLine,
        endLine = endLine,
        startOffset = startOffset,
        endOffset = endOffset,
        visibleText = document.getText(com.intellij.openapi.util.TextRange(startOffset, endOffset))
    )
}

data class VisibleRange(
    val startLine: Int,
    val endLine: Int,
    val startOffset: Int,
    val endOffset: Int,
    val visibleText: String
)
```

### Listening for Editor Open/Close Events

```kotlin
import com.intellij.openapi.editor.event.EditorFactoryEvent
import com.intellij.openapi.editor.event.EditorFactoryListener

class ClaudeEditorListener : EditorFactoryListener {
    override fun editorCreated(event: EditorFactoryEvent) {
        val editor = event.editor
        val project = editor.project ?: return
        val virtualFile = FileDocumentManager.getInstance().getFile(editor.document) ?: return
        // Editor opened for file: virtualFile.path
    }

    override fun editorReleased(event: EditorFactoryEvent) {
        val editor = event.editor
        // Editor closed
    }
}

// Register in plugin.xml:
// <listener class="com.anthropic.claude.ClaudeEditorListener"
//           topic="com.intellij.openapi.editor.event.EditorFactoryListener"/>

// Or register programmatically:
// EditorFactory.getInstance().addEditorFactoryListener(listener, parentDisposable)
```

### Getting All Open Files

```kotlin
fun getAllOpenFiles(project: Project): List<String> {
    return FileEditorManager.getInstance(project).openFiles.map { it.path }
}

fun getAllOpenEditors(project: Project): Array<out com.intellij.openapi.fileEditor.FileEditor> {
    return FileEditorManager.getInstance(project).allEditors
}
```

### Full Context Gathering for AI

```kotlin
data class EditorContext(
    val filePath: String,
    val fileName: String,
    val fileExtension: String?,
    val language: String?,
    val content: String,
    val cursorLine: Int,
    val cursorColumn: Int,
    val cursorOffset: Int,
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
    val psiFile = com.intellij.psi.PsiDocumentManager.getInstance(project).getPsiFile(document)

    val caret = editor.caretModel.primaryCaret
    val selModel = editor.selectionModel

    val visibleArea = editor.scrollingModel.visibleArea
    val startLine = editor.xyToLogicalPosition(java.awt.Point(0, visibleArea.y)).line
    val endLine = editor.xyToLogicalPosition(
        java.awt.Point(0, visibleArea.y + visibleArea.height)
    ).line

    return EditorContext(
        filePath = virtualFile.path,
        fileName = virtualFile.name,
        fileExtension = virtualFile.extension,
        language = psiFile?.language?.id,
        content = document.text,
        cursorLine = caret.logicalPosition.line,
        cursorColumn = caret.logicalPosition.column,
        cursorOffset = caret.offset,
        selection = if (selModel.hasSelection()) SelectionInfo(
            text = selModel.selectedText ?: "",
            startOffset = selModel.selectionStart,
            endOffset = selModel.selectionEnd,
            startLine = document.getLineNumber(selModel.selectionStart),
            endLine = document.getLineNumber(selModel.selectionEnd),
            startColumn = selModel.selectionStart - document.getLineStartOffset(
                document.getLineNumber(selModel.selectionStart)
            ),
            endColumn = selModel.selectionEnd - document.getLineStartOffset(
                document.getLineNumber(selModel.selectionEnd)
            )
        ) else null,
        visibleStartLine = startLine,
        visibleEndLine = endLine,
        lineCount = document.lineCount,
        isModified = FileDocumentManager.getInstance().isDocumentUnsaved(document)
    )
}
```

---

## 2. Document Modification

### Key Classes

| Class | Purpose |
|-------|---------|
| `Document` | Represents text content of a file in memory |
| `WriteCommandAction` | Wraps modifications for undo/redo support |
| `CommandProcessor` | Manages command grouping for undo/redo |
| `FileDocumentManager` | Saves documents to disk, maps documents to files |
| `DocumentListener` | Listens for document content changes |

### Basic Document Modification with WriteCommandAction

All document modifications MUST happen inside a `WriteCommandAction` (or `runWriteAction`) on the EDT (Event Dispatch Thread). Without this, the platform will throw an `IncorrectOperationException`.

```kotlin
import com.intellij.openapi.command.WriteCommandAction
import com.intellij.openapi.editor.Document

fun replaceText(
    project: Project,
    document: Document,
    startOffset: Int,
    endOffset: Int,
    newText: String
) {
    WriteCommandAction.runWriteCommandAction(project) {
        document.replaceString(startOffset, endOffset, newText)
    }
}

fun insertText(project: Project, document: Document, offset: Int, text: String) {
    WriteCommandAction.runWriteCommandAction(project) {
        document.insertString(offset, text)
    }
}

fun deleteText(project: Project, document: Document, startOffset: Int, endOffset: Int) {
    WriteCommandAction.runWriteCommandAction(project) {
        document.deleteString(startOffset, endOffset)
    }
}
```

### Applying Full File Replacement

For AI-proposed changes that replace entire file content:

```kotlin
fun replaceEntireFileContent(project: Project, document: Document, newContent: String) {
    WriteCommandAction.runWriteCommandAction(
        project,
        "Claude: Apply Changes",  // Command name (shown in undo history)
        "claude.applyChanges",    // Group ID for undo grouping
        {
            document.setText(newContent)
        }
    )
}
```

### Applying Targeted Edits (Line-Based)

For AI-proposed changes that target specific lines:

```kotlin
data class LineEdit(
    val startLine: Int,   // 0-based, inclusive
    val endLine: Int,     // 0-based, exclusive
    val newText: String
)

fun applyLineEdits(project: Project, document: Document, edits: List<LineEdit>) {
    WriteCommandAction.runWriteCommandAction(
        project,
        "Claude: Apply Edits",
        "claude.applyEdits",
        {
            // Apply edits in reverse order to preserve offset validity
            val sortedEdits = edits.sortedByDescending { it.startLine }
            for (edit in sortedEdits) {
                val startOffset = document.getLineStartOffset(edit.startLine)
                val endOffset = if (edit.endLine >= document.lineCount) {
                    document.textLength
                } else {
                    document.getLineStartOffset(edit.endLine)
                }
                document.replaceString(startOffset, endOffset, edit.newText)
            }
        }
    )
}
```

### Using WriteCommandAction.Builder (More Flexible)

```kotlin
fun applyChangesWithBuilder(project: Project, document: Document, newContent: String) {
    WriteCommandAction.writeCommandAction(project)
        .withName("Claude: Apply Suggested Changes")
        .withGroupId("claude.applySuggestion")
        .withUndoConfirmationPolicy(
            com.intellij.openapi.command.UndoConfirmationPolicy.REQUEST_CONFIRMATION
        )
        .run<RuntimeException> {
            document.setText(newContent)
        }
}
```

### Saving Documents

```kotlin
fun saveDocument(document: Document) {
    FileDocumentManager.getInstance().saveDocument(document)
}

fun saveAllDocuments() {
    FileDocumentManager.getInstance().saveAllDocuments()
}
```

### Document Listener

```kotlin
import com.intellij.openapi.editor.event.DocumentEvent
import com.intellij.openapi.editor.event.DocumentListener

fun addDocumentListener(document: Document, disposable: com.intellij.openapi.Disposable) {
    document.addDocumentListener(object : DocumentListener {
        override fun beforeDocumentChange(event: DocumentEvent) {
            // Called before change is applied
        }

        override fun documentChanged(event: DocumentEvent) {
            // Called after change is applied
            val offset = event.offset
            val oldFragment = event.oldFragment
            val newFragment = event.newFragment
        }
    }, disposable)
}
```

### Bulk Document Changes (for Performance)

When applying many edits at once, use `DocumentUtil.executeInBulk` to suppress intermediate events:

```kotlin
import com.intellij.openapi.editor.ex.DocumentEx
import com.intellij.util.DocumentUtil

fun applyBulkChanges(project: Project, document: Document, changes: List<Pair<IntRange, String>>) {
    WriteCommandAction.runWriteCommandAction(project) {
        DocumentUtil.executeInBulk(document as DocumentEx, true) {
            // Apply changes in reverse order
            val sorted = changes.sortedByDescending { it.first.first }
            for ((range, newText) in sorted) {
                document.replaceString(range.first, range.last + 1, newText)
            }
        }
    }
}
```

---

## 3. DiffManager

### Key Classes

| Class | Purpose |
|-------|---------|
| `DiffManager` | Service for showing diff windows |
| `DiffRequestChain` | Sequence of diff requests (for multi-file diffs) |
| `SimpleDiffRequest` | Single two-panel diff comparison |
| `MergeRequest` | Three-panel merge with editable result |
| `DiffContent` | Wraps content to be shown in a diff panel |
| `DiffContentFactory` | Creates `DiffContent` instances |
| `DiffRequestPanel` | Embeddable diff panel for tool windows |

### Showing a Simple Side-by-Side Diff

```kotlin
import com.intellij.diff.DiffManager
import com.intellij.diff.requests.SimpleDiffRequest
import com.intellij.diff.DiffContentFactory

fun showDiff(
    project: Project,
    originalContent: String,
    proposedContent: String,
    filePath: String
) {
    val contentFactory = DiffContentFactory.getInstance()

    // Create diff contents
    val originalDiffContent = contentFactory.create(project, originalContent)
    val proposedDiffContent = contentFactory.create(project, proposedContent)

    // Create the diff request
    val request = SimpleDiffRequest(
        "Claude: Proposed Changes to ${filePath.substringAfterLast('/')}",  // Window title
        originalDiffContent,     // Left panel
        proposedDiffContent,     // Right panel
        "Current",               // Left panel title
        "Proposed by Claude"     // Right panel title
    )

    // Show the diff in a dialog/window
    DiffManager.getInstance().showDiff(project, request)
}
```

### Diff with File Type Syntax Highlighting

```kotlin
import com.intellij.openapi.fileTypes.FileTypeManager

fun showDiffWithHighlighting(
    project: Project,
    originalContent: String,
    proposedContent: String,
    fileName: String
) {
    val contentFactory = DiffContentFactory.getInstance()
    val fileType = FileTypeManager.getInstance().getFileTypeByFileName(fileName)

    val originalDiffContent = contentFactory.create(project, originalContent, fileType)
    val proposedDiffContent = contentFactory.create(project, proposedContent, fileType)

    val request = SimpleDiffRequest(
        "Claude: Proposed Changes to $fileName",
        originalDiffContent,
        proposedDiffContent,
        "Current",
        "Proposed by Claude"
    )

    DiffManager.getInstance().showDiff(project, request)
}
```

### Diff Against Current Document (Editable)

This approach lets the user see the diff and edit the proposed version before accepting:

```kotlin
import com.intellij.diff.contents.DocumentContent
import com.intellij.diff.contents.DiffContent

fun showEditableDiff(
    project: Project,
    virtualFile: com.intellij.openapi.vfs.VirtualFile,
    proposedContent: String
) {
    val contentFactory = DiffContentFactory.getInstance()

    // Left: current file content (read-only in diff)
    val currentContent = contentFactory.create(project, virtualFile)

    // Right: proposed content (editable)
    val proposedDiffContent = contentFactory.create(project, proposedContent)

    val request = SimpleDiffRequest(
        "Claude: Review Changes - ${virtualFile.name}",
        currentContent,
        proposedDiffContent,
        "Current File",
        "Claude's Suggestion (editable)"
    )

    DiffManager.getInstance().showDiff(project, request)
}
```

### Showing Diff in a Tool Window (Embedded)

For embedding a diff viewer inside your own tool window rather than opening a separate dialog:

```kotlin
import com.intellij.diff.DiffRequestPanel
import com.intellij.diff.requests.SimpleDiffRequest
import javax.swing.JComponent

fun createEmbeddedDiffPanel(
    project: Project,
    originalContent: String,
    proposedContent: String,
    fileName: String,
    parentDisposable: com.intellij.openapi.Disposable
): JComponent {
    val contentFactory = DiffContentFactory.getInstance()
    val fileType = FileTypeManager.getInstance().getFileTypeByFileName(fileName)

    val request = SimpleDiffRequest(
        "Proposed Changes",
        contentFactory.create(project, originalContent, fileType),
        contentFactory.create(project, proposedContent, fileType),
        "Current",
        "Proposed"
    )

    val diffPanel = DiffManager.getInstance().createRequestPanel(project, parentDisposable, null)
    diffPanel.setRequest(request)

    return diffPanel.component
}
```

### Multi-File Diff (DiffRequestChain)

For showing diffs across multiple files at once (common when AI proposes changes to several files):

```kotlin
import com.intellij.diff.chains.SimpleDiffRequestChain
import com.intellij.diff.requests.SimpleDiffRequest

fun showMultiFileDiff(
    project: Project,
    changes: List<FileChange>  // Your data class
) {
    val requests = changes.map { change ->
        val contentFactory = DiffContentFactory.getInstance()
        val fileType = FileTypeManager.getInstance().getFileTypeByFileName(change.fileName)

        SimpleDiffRequest(
            change.fileName,
            contentFactory.create(project, change.originalContent, fileType),
            contentFactory.create(project, change.proposedContent, fileType),
            "Current",
            "Proposed"
        )
    }

    val chain = SimpleDiffRequestChain(requests)
    chain.windowTitle = "Claude: Review All Proposed Changes"

    DiffManager.getInstance().showDiff(project, chain)
}

data class FileChange(
    val fileName: String,
    val filePath: String,
    val originalContent: String,
    val proposedContent: String
)
```

### Accept/Reject Workflow

The DiffManager itself does not provide built-in accept/reject buttons. You need to implement the workflow around it. Two main patterns:

**Pattern A: Dialog-based approval (simplest)**

```kotlin
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.diff.DiffManager
import javax.swing.JComponent
import javax.swing.Action

class DiffApprovalDialog(
    private val project: Project,
    private val originalContent: String,
    private val proposedContent: String,
    private val fileName: String
) : DialogWrapper(project, true) {

    init {
        title = "Claude: Review Proposed Changes"
        setOKButtonText("Accept Changes")
        setCancelButtonText("Reject")
        init()
    }

    override fun createCenterPanel(): JComponent {
        val contentFactory = DiffContentFactory.getInstance()
        val fileType = FileTypeManager.getInstance().getFileTypeByFileName(fileName)

        val request = SimpleDiffRequest(
            fileName,
            contentFactory.create(project, originalContent, fileType),
            contentFactory.create(project, proposedContent, fileType),
            "Current",
            "Proposed by Claude"
        )

        val diffPanel = DiffManager.getInstance().createRequestPanel(
            project, disposable, null
        )
        diffPanel.setRequest(request)

        return diffPanel.component
    }

    override fun getPreferredSize() = java.awt.Dimension(900, 600)
}

// Usage:
fun showDiffForApproval(
    project: Project,
    document: Document,
    proposedContent: String,
    fileName: String
) {
    val dialog = DiffApprovalDialog(
        project,
        document.text,
        proposedContent,
        fileName
    )

    if (dialog.showAndGet()) {
        // User clicked "Accept Changes"
        WriteCommandAction.runWriteCommandAction(
            project,
            "Claude: Accept Proposed Changes",
            "claude.acceptChanges",
            { document.setText(proposedContent) }
        )
    }
    // else: user clicked "Reject" -- do nothing
}
```

**Pattern B: Notification-based with actions**

```kotlin
import com.intellij.notification.NotificationAction
import com.intellij.notification.NotificationType

fun proposeDiffWithNotification(
    project: Project,
    document: Document,
    proposedContent: String,
    fileName: String
) {
    val notification = com.intellij.notification.NotificationGroupManager.getInstance()
        .getNotificationGroup("Claude Code")
        .createNotification(
            "Claude suggests changes to $fileName",
            NotificationType.INFORMATION
        )

    notification.addAction(NotificationAction.createSimple("View Diff") {
        showDiff(project, document.text, proposedContent, fileName)
    })

    notification.addAction(NotificationAction.createSimple("Accept") {
        WriteCommandAction.runWriteCommandAction(project) {
            document.setText(proposedContent)
        }
        notification.expire()
    })

    notification.addAction(NotificationAction.createSimple("Reject") {
        notification.expire()
    })

    notification.notify(project)
}
```

---

## 4. SimpleDiffRequest vs MergeRequest

### SimpleDiffRequest

- **Purpose:** Show a two-panel side-by-side comparison (left = original, right = proposed).
- **Panels:** 2 (left, right)
- **Editability:** Both sides can be read-only or editable depending on the `DiffContent` type.
- **Best for:** Showing what Claude proposes vs. what exists now. User reviews and then accepts or rejects the whole change set.
- **User interaction:** View only (by default). No built-in "apply" button.

```kotlin
// Two-panel diff
val request = SimpleDiffRequest(
    title,
    leftContent,   // DiffContent
    rightContent,   // DiffContent
    "Left Title",
    "Right Title"
)
```

### MergeRequest

- **Purpose:** Three-panel merge view with an editable result panel in the center.
- **Panels:** 3 (left = theirs, center = result/merged, right = yours -- or whichever labeling you choose)
- **Editability:** Center panel is always editable. User can pick changes from either side.
- **Best for:** When the user needs to selectively cherry-pick parts of Claude's suggestions while keeping some of their own code.
- **User interaction:** Arrows/chevrons to accept individual hunks from left or right into the center panel.

```kotlin
import com.intellij.diff.merge.MergeRequest
import com.intellij.diff.merge.MergeResult
import com.intellij.diff.merge.TextMergeRequest

fun showMerge(
    project: Project,
    baseContent: String,        // Common ancestor or original
    currentContent: String,     // User's current version
    proposedContent: String,    // Claude's proposed version
    fileName: String,
    onResult: (MergeResult, String) -> Unit
) {
    val contentFactory = DiffContentFactory.getInstance()
    val fileType = FileTypeManager.getInstance().getFileTypeByFileName(fileName)

    val outputDocument = com.intellij.openapi.editor.EditorFactory.getInstance()
        .createDocument(currentContent)

    val request = com.intellij.diff.merge.TextMergeRequest(
        project,
        outputDocument,
        /* title */ "Claude: Merge Changes - $fileName",
        /* contentTitles */ listOf("Current", "Result", "Claude's Suggestion"),
        /* contents */ listOf(
            currentContent,
            baseContent,  // or currentContent as base
            proposedContent
        ),
        /* onResult */ { result ->
            onResult(result, outputDocument.text)
        }
    )

    // Note: In practice, constructing TextMergeRequest directly is internal API.
    // Use MergeRequestFactory or the higher-level DiffManager.showMerge() approach.
}
```

**In practice, using `MergeRequest` directly is harder** because the public constructors are limited. The more practical approach uses `DiffManager.showMerge()`:

```kotlin
import com.intellij.diff.DiffManager
import com.intellij.diff.merge.MergeRequest
import com.intellij.diff.merge.MergeResult
import com.intellij.diff.merge.ThreesideMergeRequest

fun showThreeWayMerge(
    project: Project,
    virtualFile: com.intellij.openapi.vfs.VirtualFile,
    baseContent: ByteArray,
    currentContent: ByteArray,
    proposedContent: ByteArray,
    onFinished: (MergeResult) -> Unit
) {
    val request = com.intellij.diff.InvalidDiffRequestException("") // placeholder

    // The standard approach is through the merge dialog:
    com.intellij.openapi.diff.DiffManager.getInstance().getDiffTool()
    // ... see recommendation below
}
```

### Recommendation for Claude Code Plugin

**Use `SimpleDiffRequest` as the primary mechanism.** Reasons:

1. **Simpler mental model:** User sees "what I have" vs "what Claude proposes." Binary accept/reject.
2. **Easier to implement:** Two-panel diff is straightforward to set up.
3. **Sufficient for most AI use cases:** AI typically proposes a complete replacement, not a merge of two divergent branches.
4. **MergeRequest adds complexity** without much benefit since the AI's changes are not a "branch" that needs merging.

**Use `MergeRequest` only if** you later support scenarios where the user has modified the file after requesting changes from Claude, and the file has diverged. In that case, a three-way merge with base = original at request time, left = user's current version, right = Claude's proposal, makes sense.

### Comparison Table

| Feature | SimpleDiffRequest | MergeRequest |
|---------|------------------|--------------|
| Panels | 2 | 3 |
| Built-in accept/reject per hunk | No | Yes |
| Editable result | Optional | Always (center panel) |
| Complexity | Low | High |
| Use case | Review and approve | Selective merge |
| Construction API difficulty | Easy | Moderate (some internal APIs) |
| **Recommended for Claude Code** | **Yes (primary)** | Secondary / advanced |

---

## 5. Virtual File System

### Key Classes

| Class | Purpose |
|-------|---------|
| `VirtualFile` | Abstract representation of a file (could be on disk, in memory, in a JAR) |
| `VirtualFileManager` | Finds virtual files by URL or path |
| `LocalFileSystem` | Access to local filesystem virtual files |
| `LightVirtualFile` | In-memory virtual file (no backing on disk) |
| `FileDocumentManager` | Maps virtual files to documents and vice versa |

### Reading a File

```kotlin
import com.intellij.openapi.vfs.LocalFileSystem
import com.intellij.openapi.vfs.VirtualFile

fun readFile(path: String): String? {
    val virtualFile = LocalFileSystem.getInstance().findFileByPath(path) ?: return null
    return String(virtualFile.contentsToByteArray(), virtualFile.charset)
}

// Safer version with refresh (in case file changed externally)
fun readFileRefreshed(path: String): String? {
    val virtualFile = LocalFileSystem.getInstance().refreshAndFindFileByPath(path) ?: return null
    return String(virtualFile.contentsToByteArray(), virtualFile.charset)
}
```

### Writing a File

```kotlin
import com.intellij.openapi.application.WriteAction

fun writeFile(project: Project, path: String, content: String) {
    WriteAction.run<Exception> {
        val virtualFile = LocalFileSystem.getInstance().findFileByPath(path) ?: return@run
        virtualFile.setBinaryContent(content.toByteArray(virtualFile.charset))
    }
}
```

### Creating a Temporary File (for Diff Content)

Use `LightVirtualFile` for in-memory files that do not need to persist to disk. This is ideal for diff content:

```kotlin
import com.intellij.testFramework.LightVirtualFile
import com.intellij.openapi.fileTypes.FileTypeManager

fun createTempVirtualFile(
    name: String,
    content: String,
    extension: String = "txt"
): LightVirtualFile {
    val fileType = FileTypeManager.getInstance().getFileTypeByExtension(extension)
    return LightVirtualFile(name, fileType, content)
}
```

### Using DiffContentFactory with VirtualFile

```kotlin
fun createDiffContentFromFile(
    project: Project,
    virtualFile: VirtualFile
): com.intellij.diff.contents.DiffContent {
    return DiffContentFactory.getInstance().create(project, virtualFile)
}

// For proposed content (not on disk), use string-based creation:
fun createDiffContentFromString(
    project: Project,
    content: String,
    virtualFile: VirtualFile?  // For file type detection
): com.intellij.diff.contents.DiffContent {
    return if (virtualFile != null) {
        val fileType = virtualFile.fileType
        DiffContentFactory.getInstance().create(project, content, fileType)
    } else {
        DiffContentFactory.getInstance().create(project, content)
    }
}
```

### Creating New Files

```kotlin
fun createNewFile(project: Project, parentPath: String, fileName: String, content: String): VirtualFile? {
    var result: VirtualFile? = null
    WriteCommandAction.runWriteCommandAction(project) {
        val parentDir = LocalFileSystem.getInstance().findFileByPath(parentPath) ?: return@runWriteCommandAction
        val newFile = parentDir.createChildData(this, fileName)
        newFile.setBinaryContent(content.toByteArray(Charsets.UTF_8))
        result = newFile
    }
    return result
}
```

### Refreshing VFS After External Changes

If Claude CLI modifies files on disk outside the IDE, you need to refresh:

```kotlin
fun refreshAfterExternalChanges(paths: List<String>) {
    val localFS = LocalFileSystem.getInstance()
    val files = paths.mapNotNull { localFS.findFileByPath(it) }
    localFS.refreshFiles(files, true, false, null)
    // async=true, recursive=false
}

// Or refresh a directory recursively:
fun refreshDirectory(dirPath: String) {
    val dir = LocalFileSystem.getInstance().findFileByPath(dirPath) ?: return
    dir.refresh(true, true)  // async=true, recursive=true
}
```

---

## 6. File Change Events

### Key Interfaces

| Interface | Purpose |
|-----------|---------|
| `BulkFileListener` | Listens for VFS-level file events (create, modify, delete, move) |
| `VirtualFileListener` | Similar but registered per-file |
| `FileDocumentManagerListener` | Listens for document save events |
| `DocumentListener` | Listens for in-memory document changes (character by character) |

### Listening for File Saves

```kotlin
import com.intellij.openapi.fileEditor.FileDocumentManagerListener
import com.intellij.openapi.editor.Document

class ClaudeFileSaveListener : FileDocumentManagerListener {
    override fun beforeDocumentSaving(document: Document) {
        val virtualFile = FileDocumentManager.getInstance().getFile(document) ?: return
        // File is about to be saved: virtualFile.path
    }

    override fun beforeAllDocumentsSaving() {
        // Called before "Save All"
    }
}

// Register in plugin.xml:
// <listener class="com.anthropic.claude.ClaudeFileSaveListener"
//           topic="com.intellij.openapi.fileEditor.FileDocumentManagerListener"/>
```

### Listening for File System Changes (Create, Delete, Modify, Move)

```kotlin
import com.intellij.openapi.vfs.newvfs.BulkFileListener
import com.intellij.openapi.vfs.newvfs.events.*

class ClaudeFileChangeListener : BulkFileListener {
    override fun after(events: MutableList<out VFileEvent>) {
        for (event in events) {
            when (event) {
                is VFileContentChangeEvent -> {
                    // File content changed: event.file.path
                }
                is VFileCreateEvent -> {
                    // File created: event.path
                }
                is VFileDeleteEvent -> {
                    // File deleted: event.file.path
                }
                is VFileMoveEvent -> {
                    // File moved from ${event.oldPath} to ${event.newPath}
                }
                is VFilePropertyChangeEvent -> {
                    if (event.propertyName == VirtualFile.PROP_NAME) {
                        // File renamed
                    }
                }
            }
        }
    }
}

// Register in plugin.xml:
// <listener class="com.anthropic.claude.ClaudeFileChangeListener"
//           topic="com.intellij.openapi.vfs.newvfs.BulkFileListener"/>
```

### Project-Scoped File Listening

To filter events to only the current project's files:

```kotlin
class ProjectScopedFileListener(private val project: Project) : BulkFileListener {
    override fun after(events: MutableList<out VFileEvent>) {
        val projectBasePath = project.basePath ?: return
        val relevantEvents = events.filter { event ->
            val path = when (event) {
                is VFileContentChangeEvent -> event.file.path
                is VFileCreateEvent -> event.path
                is VFileDeleteEvent -> event.file.path
                else -> null
            }
            path?.startsWith(projectBasePath) == true
        }

        if (relevantEvents.isNotEmpty()) {
            // Process relevant events
        }
    }
}

// Register programmatically with project as parent disposable:
// project.messageBus.connect(parentDisposable)
//     .subscribe(VirtualFileManager.VFS_CHANGES, ProjectScopedFileListener(project))
```

---

## 7. Editor Decorations and Inlays

### Key Classes

| Class | Purpose |
|-------|---------|
| `InlayModel` | Manages inline/block inlays in the editor |
| `EditorCustomElementRenderer` | Renders custom content in an inlay |
| `RangeHighlighter` | Highlights a range of text with a style |
| `MarkupModel` | Manages range highlighters and gutter icons |
| `TextAttributes` | Style (color, font, etc.) for text ranges |
| `GutterIconRenderer` | Renders icons in the gutter |
| `EditorLinePainter` | Adds virtual text at end of lines (like git blame) |

### Inline Inlay Hints (e.g., "Claude suggests...")

```kotlin
import com.intellij.openapi.editor.InlayModel
import com.intellij.openapi.editor.EditorCustomElementRenderer
import com.intellij.openapi.editor.Inlay
import com.intellij.openapi.editor.markup.TextAttributes
import java.awt.Graphics
import java.awt.Rectangle

class ClaudeSuggestionRenderer(
    private val text: String
) : EditorCustomElementRenderer {

    override fun calcWidthInPixels(inlay: Inlay<*>): Int {
        val fontMetrics = inlay.editor.contentComponent
            .getFontMetrics(inlay.editor.colorsScheme.getFont(com.intellij.openapi.editor.EditorFontType.ITALIC))
        return fontMetrics.stringWidth(text) + 10
    }

    override fun paint(
        inlay: Inlay<*>,
        g: Graphics,
        targetRegion: Rectangle,
        textAttributes: TextAttributes
    ) {
        val editor = inlay.editor
        g.color = java.awt.Color.GRAY
        g.font = editor.colorsScheme.getFont(com.intellij.openapi.editor.EditorFontType.ITALIC)
        g.drawString(text, targetRegion.x + 5, targetRegion.y + editor.ascent)
    }
}

fun addInlineHint(editor: Editor, offset: Int, text: String): Inlay<*>? {
    return editor.inlayModel.addInlineElement(
        offset,
        true,  // relates to preceding text
        ClaudeSuggestionRenderer(text)
    )
}
```

### Block Inlay (Multi-Line Suggestion Preview)

```kotlin
class ClaudeBlockRenderer(
    private val lines: List<String>
) : EditorCustomElementRenderer {

    override fun calcWidthInPixels(inlay: Inlay<*>): Int = 0  // Spans full width

    override fun calcHeightInPixels(inlay: Inlay<*>): Int {
        val lineHeight = inlay.editor.lineHeight
        return lineHeight * lines.size
    }

    override fun paint(
        inlay: Inlay<*>,
        g: Graphics,
        targetRegion: Rectangle,
        textAttributes: TextAttributes
    ) {
        val editor = inlay.editor
        g.color = java.awt.Color(0, 128, 0, 60)  // Semi-transparent green background
        g.fillRect(targetRegion.x, targetRegion.y, targetRegion.width, targetRegion.height)

        g.color = java.awt.Color(0, 128, 0)
        g.font = editor.colorsScheme.getFont(com.intellij.openapi.editor.EditorFontType.PLAIN)

        val lineHeight = editor.lineHeight
        for ((index, line) in lines.withIndex()) {
            g.drawString(
                line,
                targetRegion.x + 5,
                targetRegion.y + editor.ascent + (lineHeight * index)
            )
        }
    }
}

fun addBlockInlay(editor: Editor, afterLine: Int, lines: List<String>): Inlay<*>? {
    val offset = editor.document.getLineEndOffset(afterLine)
    return editor.inlayModel.addBlockElement(
        offset,
        false,       // relatesToPrecedingText
        true,        // showAbove = true means it shows above the offset line
        0,           // priority
        ClaudeBlockRenderer(lines)
    )
}
```

### Range Highlighter (Highlighting Modified Regions)

```kotlin
import com.intellij.openapi.editor.markup.HighlighterLayer
import com.intellij.openapi.editor.markup.HighlighterTargetArea
import com.intellij.openapi.editor.markup.RangeHighlighter

fun highlightRange(
    editor: Editor,
    startOffset: Int,
    endOffset: Int,
    backgroundColor: java.awt.Color
): RangeHighlighter {
    val attributes = TextAttributes().apply {
        this.backgroundColor = backgroundColor
    }

    return editor.markupModel.addRangeHighlighter(
        startOffset,
        endOffset,
        HighlighterLayer.SELECTION - 1,  // Below selection highlight
        attributes,
        HighlighterTargetArea.EXACT_RANGE
    )
}

fun highlightClaudeChangedLines(editor: Editor, startLine: Int, endLine: Int): RangeHighlighter {
    val startOffset = editor.document.getLineStartOffset(startLine)
    val endOffset = editor.document.getLineEndOffset(endLine)

    return highlightRange(editor, startOffset, endOffset, java.awt.Color(0, 255, 0, 30))
}

// Remove highlighting:
fun removeHighlight(editor: Editor, highlighter: RangeHighlighter) {
    editor.markupModel.removeHighlighter(highlighter)
}
```

### Gutter Icon (e.g., Claude Icon Next to Modified Lines)

```kotlin
import com.intellij.openapi.editor.markup.GutterIconRenderer
import javax.swing.Icon

class ClaudeGutterIcon(
    private val lineNumber: Int,
    private val tooltip: String,
    private val action: () -> Unit
) : GutterIconRenderer() {

    override fun getIcon(): Icon = com.intellij.icons.AllIcons.Actions.IntentionBulb
    // Or load your own: IconLoader.getIcon("/icons/claude-gutter.svg", javaClass)

    override fun getTooltipText(): String = tooltip

    override fun getClickAction(): com.intellij.openapi.actionSystem.AnAction {
        return object : com.intellij.openapi.actionSystem.AnAction() {
            override fun actionPerformed(e: com.intellij.openapi.actionSystem.AnActionEvent) {
                action()
            }
        }
    }

    override fun equals(other: Any?): Boolean =
        other is ClaudeGutterIcon && other.lineNumber == lineNumber

    override fun hashCode(): Int = lineNumber
}

fun addGutterIcon(editor: Editor, line: Int, tooltip: String, action: () -> Unit) {
    val offset = editor.document.getLineStartOffset(line)
    val highlighter = editor.markupModel.addRangeHighlighter(
        offset, offset,
        HighlighterLayer.LAST,
        null,
        HighlighterTargetArea.EXACT_RANGE
    )
    highlighter.gutterIconRenderer = ClaudeGutterIcon(line, tooltip, action)
}
```

### After-Line Virtual Text (EditorLinePainter - Deprecated Path)

For adding ghost text at the end of lines (like "// Claude: consider refactoring this"):

```kotlin
import com.intellij.openapi.editor.EditorLinePainter
import com.intellij.openapi.editor.LineExtensionInfo
import com.intellij.openapi.vfs.VirtualFile

class ClaudeLinePainter : EditorLinePainter() {
    // Store annotations: Map<filePath, Map<lineNumber, annotationText>>
    private val annotations = mutableMapOf<String, MutableMap<Int, String>>()

    override fun getLineExtensions(
        project: Project,
        file: VirtualFile,
        lineNumber: Int
    ): Collection<LineExtensionInfo>? {
        val fileAnnotations = annotations[file.path] ?: return null
        val text = fileAnnotations[lineNumber] ?: return null

        return listOf(
            LineExtensionInfo(
                "  // Claude: $text",
                java.awt.Color.GRAY,
                null,   // effectColor
                null,   // effectType
                java.awt.Font.ITALIC
            )
        )
    }

    fun setAnnotation(filePath: String, line: Int, text: String) {
        annotations.getOrPut(filePath) { mutableMapOf() }[line] = text
    }

    fun clearAnnotations(filePath: String) {
        annotations.remove(filePath)
    }
}

// Register in plugin.xml:
// <editorLinePainter implementation="com.anthropic.claude.ClaudeLinePainter"/>
```

### Inline Completion Provider (2024.1+)

IntelliJ 2024.1+ introduced `InlineCompletionProvider` for ghost-text style completions (like GitHub Copilot). This is the modern way to show inline AI suggestions:

```kotlin
import com.intellij.codeInsight.inline.completion.*
import com.intellij.codeInsight.inline.completion.elements.InlineCompletionGrayTextElement
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

class ClaudeInlineCompletionProvider : InlineCompletionProvider {
    override val id: InlineCompletionProviderID =
        InlineCompletionProviderID("ClaudeInlineCompletion")

    override suspend fun getSuggestion(request: InlineCompletionRequest): InlineCompletionSuggestion {
        return InlineCompletionSuggestion {
            // Emit gray text suggestion
            emit(InlineCompletionGrayTextElement("// suggested by Claude"))
        }
    }

    override fun isEnabled(event: InlineCompletionEvent): Boolean {
        return event is InlineCompletionEvent.DocumentChange
    }
}

// Register in plugin.xml:
// <inlineCompletionProvider implementation="com.anthropic.claude.ClaudeInlineCompletionProvider"/>
```

---

## 8. Context Menu Integration

### Adding "Ask Claude About Selection" to Editor Context Menu

**plugin.xml registration:**

```xml
<actions>
    <!-- Editor popup (right-click) menu -->
    <action id="Claude.AskAboutSelection"
            class="com.anthropic.claude.actions.AskAboutSelectionAction"
            text="Ask Claude About Selection"
            description="Send the selected code to Claude for analysis"
            icon="/icons/claude-logo.svg">
        <add-to-group group-id="EditorPopupMenu" anchor="last"/>
        <keyboard-shortcut keymap="$default" first-keystroke="ctrl shift K"/>
        <keyboard-shortcut keymap="Mac OS X" first-keystroke="meta shift K"/>
    </action>

    <!-- A submenu with multiple Claude actions -->
    <group id="Claude.EditorPopupGroup"
           text="Claude"
           popup="true"
           icon="/icons/claude-logo.svg">
        <add-to-group group-id="EditorPopupMenu" anchor="last"/>

        <action id="Claude.ExplainCode"
                class="com.anthropic.claude.actions.ExplainCodeAction"
                text="Explain This Code"/>
        <action id="Claude.RefactorCode"
                class="com.anthropic.claude.actions.RefactorCodeAction"
                text="Suggest Refactoring"/>
        <action id="Claude.AddTests"
                class="com.anthropic.claude.actions.AddTestsAction"
                text="Generate Tests"/>
        <action id="Claude.FixBugs"
                class="com.anthropic.claude.actions.FixBugsAction"
                text="Find & Fix Bugs"/>
        <action id="Claude.AddDocumentation"
                class="com.anthropic.claude.actions.AddDocumentationAction"
                text="Add Documentation"/>
        <separator/>
        <action id="Claude.CustomPrompt"
                class="com.anthropic.claude.actions.CustomPromptAction"
                text="Custom Prompt..."/>
    </group>

    <!-- Project view context menu (right-click on files) -->
    <action id="Claude.AskAboutFile"
            class="com.anthropic.claude.actions.AskAboutFileAction"
            text="Ask Claude About This File"
            icon="/icons/claude-logo.svg">
        <add-to-group group-id="ProjectViewPopupMenu" anchor="last"/>
    </action>
</actions>
```

### Action Implementation

```kotlin
import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.actionSystem.CommonDataKeys

class AskAboutSelectionAction : AnAction() {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val editor = e.getData(CommonDataKeys.EDITOR) ?: return
        val selectedText = editor.selectionModel.selectedText ?: return
        val virtualFile = e.getData(CommonDataKeys.VIRTUAL_FILE)

        val filePath = virtualFile?.path ?: "unknown"
        val language = virtualFile?.extension ?: "text"

        val startLine = editor.document.getLineNumber(editor.selectionModel.selectionStart)
        val endLine = editor.document.getLineNumber(editor.selectionModel.selectionEnd)

        // Send to Claude via your service
        val claudeService = project.getService(ClaudeService::class.java)
        claudeService.askAboutCode(
            code = selectedText,
            filePath = filePath,
            language = language,
            startLine = startLine,
            endLine = endLine
        )
    }

    override fun update(e: AnActionEvent) {
        // Only enable when there is a selection
        val editor = e.getData(CommonDataKeys.EDITOR)
        e.presentation.isEnabledAndVisible =
            editor != null && editor.selectionModel.hasSelection()
    }

    override fun getActionUpdateThread(): com.intellij.openapi.actionSystem.ActionUpdateThread {
        return com.intellij.openapi.actionSystem.ActionUpdateThread.EDT
    }
}
```

### File-Level Context Menu Action

```kotlin
class AskAboutFileAction : AnAction() {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val virtualFile = e.getData(CommonDataKeys.VIRTUAL_FILE) ?: return

        if (virtualFile.isDirectory) {
            // Handle directory selection
            return
        }

        val content = String(virtualFile.contentsToByteArray(), virtualFile.charset)

        val claudeService = project.getService(ClaudeService::class.java)
        claudeService.askAboutFile(
            content = content,
            filePath = virtualFile.path,
            language = virtualFile.extension ?: "text"
        )
    }

    override fun update(e: AnActionEvent) {
        val virtualFile = e.getData(CommonDataKeys.VIRTUAL_FILE)
        e.presentation.isEnabledAndVisible =
            virtualFile != null && !virtualFile.isDirectory
    }

    override fun getActionUpdateThread(): com.intellij.openapi.actionSystem.ActionUpdateThread {
        return com.intellij.openapi.actionSystem.ActionUpdateThread.BGT
    }
}
```

### Dynamic Context Menu Based on Cursor Context

```kotlin
class SmartClaudeAction : AnAction() {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val editor = e.getData(CommonDataKeys.EDITOR) ?: return
        val psiFile = e.getData(CommonDataKeys.PSI_FILE) ?: return
        val offset = editor.caretModel.offset

        // Find the PSI element at cursor
        val element = psiFile.findElementAt(offset)
        val containingMethod = com.intellij.psi.util.PsiTreeUtil.getParentOfType(
            element,
            com.intellij.psi.PsiNamedElement::class.java
        )

        if (containingMethod != null) {
            // Ask about the specific method/function
            val methodText = containingMethod.text
            // Send to Claude with context about the surrounding method
        }
    }

    override fun getActionUpdateThread(): com.intellij.openapi.actionSystem.ActionUpdateThread {
        return com.intellij.openapi.actionSystem.ActionUpdateThread.BGT
    }
}
```

---

## 9. Multi-Caret Support

IntelliJ supports multiple carets (cursors). When a user has multiple carets/selections, each selection should be handled properly.

### Reading All Carets

```kotlin
fun getAllCarets(editor: Editor): List<CaretInfo> {
    return editor.caretModel.allCarets.map { caret ->
        CaretInfo(
            offset = caret.offset,
            line = caret.logicalPosition.line,
            column = caret.logicalPosition.column,
            selectedText = caret.selectedText,
            selectionStart = caret.selectionStart,
            selectionEnd = caret.selectionEnd,
            hasSelection = caret.hasSelection()
        )
    }
}

data class CaretInfo(
    val offset: Int,
    val line: Int,
    val column: Int,
    val selectedText: String?,
    val selectionStart: Int,
    val selectionEnd: Int,
    val hasSelection: Boolean
)
```

### Applying Edits to All Selections

```kotlin
fun replaceAllSelections(project: Project, editor: Editor, replacement: (String) -> String) {
    WriteCommandAction.runWriteCommandAction(project, "Claude: Replace Selections", "claude.multiReplace", {
        val document = editor.document
        val carets = editor.caretModel.allCarets.sortedByDescending { it.selectionStart }

        for (caret in carets) {
            if (caret.hasSelection()) {
                val originalText = caret.selectedText ?: continue
                val newText = replacement(originalText)
                document.replaceString(caret.selectionStart, caret.selectionEnd, newText)
            }
        }
    })
}
```

### Running Caret-Aware Operations

The `CaretModel` provides `runForEachCaret` for operations that should execute per-caret:

```kotlin
fun processEachCaret(editor: Editor, action: (com.intellij.openapi.editor.Caret) -> Unit) {
    editor.caretModel.runForEachCaret(action)
}
```

### Getting All Selected Texts for AI Context

```kotlin
fun getAllSelectedTexts(editor: Editor): List<SelectedRegion> {
    return editor.caretModel.allCarets
        .filter { it.hasSelection() }
        .map { caret ->
            SelectedRegion(
                text = caret.selectedText ?: "",
                startLine = editor.document.getLineNumber(caret.selectionStart),
                endLine = editor.document.getLineNumber(caret.selectionEnd),
                startOffset = caret.selectionStart,
                endOffset = caret.selectionEnd
            )
        }
}

data class SelectedRegion(
    val text: String,
    val startLine: Int,
    val endLine: Int,
    val startOffset: Int,
    val endOffset: Int
)
```

---

## 10. Undo Integration

### Key Concepts

- Every document modification inside a `WriteCommandAction` is automatically undoable.
- The `CommandProcessor` groups modifications into named undo units.
- Using the same `groupId` in consecutive `WriteCommandAction` calls merges them into one undo step.
- `UndoManager` provides programmatic undo/redo.

### Grouping Multiple Edits as Single Undo

```kotlin
import com.intellij.openapi.command.CommandProcessor
import com.intellij.openapi.command.WriteCommandAction

fun applyClaudeChangesAsOneUndo(
    project: Project,
    changes: List<DocumentChange>
) {
    WriteCommandAction.runWriteCommandAction(
        project,
        "Claude: Apply All Suggested Changes",   // This name appears in Edit > Undo
        "claude.batchApply",                      // Group ID
        {
            for (change in changes) {
                val document = FileDocumentManager.getInstance()
                    .getDocument(change.virtualFile) ?: continue
                document.setText(change.newContent)
            }
        }
    )
}

data class DocumentChange(
    val virtualFile: com.intellij.openapi.vfs.VirtualFile,
    val newContent: String
)
```

### Merging Consecutive Commands into One Undo Step

If you need to apply changes across multiple `WriteCommandAction` calls but want them to be a single undo operation:

```kotlin
fun applyChangesIncrementally(
    project: Project,
    document: Document,
    edits: List<Pair<IntRange, String>>
) {
    val groupId = "claude.incrementalApply.${System.currentTimeMillis()}"

    for (edit in edits.sortedByDescending { it.first.first }) {
        CommandProcessor.getInstance().executeCommand(
            project,
            {
                com.intellij.openapi.application.ApplicationManager.getApplication().runWriteAction {
                    document.replaceString(edit.first.first, edit.first.last + 1, edit.second)
                }
            },
            "Claude: Apply Change",
            groupId  // Same group ID = merged into single undo
        )
    }
}
```

### Programmatic Undo

```kotlin
import com.intellij.openapi.command.undo.UndoManager

fun undoLastClaudeChange(project: Project) {
    val editor = FileEditorManager.getInstance(project).selectedEditor ?: return
    val undoManager = UndoManager.getInstance(project)

    if (undoManager.isUndoAvailable(editor)) {
        undoManager.undo(editor)
    }
}

fun redoLastClaudeChange(project: Project) {
    val editor = FileEditorManager.getInstance(project).selectedEditor ?: return
    val undoManager = UndoManager.getInstance(project)

    if (undoManager.isRedoAvailable(editor)) {
        undoManager.redo(editor)
    }
}
```

### Custom Undoable Action (Advanced)

For complex operations that are not just document edits:

```kotlin
import com.intellij.openapi.command.undo.BasicUndoableAction
import com.intellij.openapi.command.undo.UndoableAction
import com.intellij.openapi.command.undo.UnexpectedUndoException
import com.intellij.openapi.command.undo.DocumentReferenceManager

class ClaudeUndoableAction(
    private val document: Document,
    private val originalContent: String,
    private val newContent: String,
    private val description: String
) : BasicUndoableAction(
    DocumentReferenceManager.getInstance().create(document)
) {
    override fun undo() {
        document.setText(originalContent)
    }

    override fun redo() {
        document.setText(newContent)
    }
}

fun applyWithCustomUndo(project: Project, document: Document, newContent: String) {
    val originalContent = document.text

    WriteCommandAction.runWriteCommandAction(
        project,
        "Claude: Apply Changes",
        "claude.apply",
        {
            document.setText(newContent)

            // Register custom undo action (optional, for additional side effects)
            val undoAction = ClaudeUndoableAction(document, originalContent, newContent, "Claude changes")
            UndoManager.getInstance(project)
            // Note: WriteCommandAction already registers the document change for undo.
            // Custom UndoableAction is needed only if you have non-document side effects.
        }
    )
}
```

### Complete Accept/Reject/Undo Flow

```kotlin
class ClaudeChangeManager(private val project: Project) {
    private data class PendingChange(
        val document: Document,
        val originalContent: String,
        val proposedContent: String,
        val filePath: String
    )

    private val pendingChanges = mutableMapOf<String, PendingChange>()

    fun proposeChange(document: Document, proposedContent: String, filePath: String) {
        val original = document.text
        pendingChanges[filePath] = PendingChange(document, original, proposedContent, filePath)

        // Show diff for review
        showDiffForApproval(
            project, document, proposedContent, filePath,
            onAccept = { acceptChange(filePath) },
            onReject = { rejectChange(filePath) }
        )
    }

    fun acceptChange(filePath: String) {
        val change = pendingChanges.remove(filePath) ?: return
        WriteCommandAction.runWriteCommandAction(
            project,
            "Claude: Accept Changes to ${change.filePath.substringAfterLast('/')}",
            "claude.accept",
            { change.document.setText(change.proposedContent) }
        )
    }

    fun rejectChange(filePath: String) {
        pendingChanges.remove(filePath)
        // Nothing to do -- the original content is still in the document
    }

    fun acceptAllChanges() {
        WriteCommandAction.runWriteCommandAction(
            project,
            "Claude: Accept All Changes",
            "claude.acceptAll",
            {
                for ((_, change) in pendingChanges) {
                    change.document.setText(change.proposedContent)
                }
            }
        )
        pendingChanges.clear()
    }

    fun rejectAllChanges() {
        pendingChanges.clear()
    }

    private fun showDiffForApproval(
        project: Project,
        document: Document,
        proposedContent: String,
        filePath: String,
        onAccept: () -> Unit,
        onReject: () -> Unit
    ) {
        val dialog = DiffApprovalDialog(project, document.text, proposedContent, filePath)
        if (dialog.showAndGet()) {
            onAccept()
        } else {
            onReject()
        }
    }
}
```

---

## 11. Terminal API

### Key Classes

| Class | Purpose |
|-------|---------|
| `TerminalView` | Main service for terminal tabs in the Terminal tool window |
| `ShellTerminalWidget` | A terminal widget that runs a shell |
| `TerminalWidget` | Base terminal widget interface |
| `TerminalToolWindowManager` | Manages terminal tabs in 2024.2+ |

**Important dependency:** The Terminal API requires a dependency on the terminal plugin.

```xml
<!-- plugin.xml -->
<depends optional="true" config-file="terminal-support.xml">org.jetbrains.plugins.terminal</depends>
```

### Creating a Terminal Tab

```kotlin
import org.jetbrains.plugins.terminal.TerminalView
import org.jetbrains.plugins.terminal.ShellTerminalWidget

fun createClaudeTerminal(project: Project): ShellTerminalWidget? {
    val terminalView = TerminalView.getInstance(project)

    // Create a new local shell terminal tab
    val widget = terminalView.createLocalShellWidget(
        project.basePath ?: System.getProperty("user.home"),  // working directory
        "Claude Code"  // tab name
    )

    return widget
}
```

### Sending Commands to Terminal

```kotlin
fun sendCommandToTerminal(widget: ShellTerminalWidget, command: String) {
    widget.executeCommand(command)
}

// Example: run Claude CLI in terminal
fun launchClaudeInTerminal(project: Project) {
    val widget = createClaudeTerminal(project) ?: return
    widget.executeCommand("/usr/local/bin/claude")
}
```

### Reading Terminal Output (Limited)

IntelliJ's terminal API does not provide a robust public API for reading terminal output programmatically. The terminal is primarily a visual component. For reading command output, use `ProcessBuilder` instead.

However, you can get a text buffer from the `TerminalTextBuffer`:

```kotlin
import com.jediterm.terminal.model.TerminalTextBuffer

fun getTerminalContent(widget: ShellTerminalWidget): String {
    val textBuffer = widget.terminalTextBuffer
    val sb = StringBuilder()
    for (i in 0 until textBuffer.height) {
        sb.appendLine(textBuffer.getLine(i).text)
    }
    return sb.toString()
}
```

**Caveat:** `TerminalTextBuffer` is from JediTerm (the underlying terminal emulator library). Its API is semi-internal and may change. For reliable command output reading, running processes via `ProcessBuilder`/`GeneralCommandLine` is strongly recommended.

### Running a Process and Showing Output in Terminal (2024.2+)

```kotlin
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.OSProcessHandler
import com.intellij.terminal.TerminalExecutionConsole

fun runCommandInTerminalView(project: Project, command: String, args: List<String> = emptyList()) {
    val commandLine = GeneralCommandLine(command)
        .withParameters(args)
        .withWorkDirectory(project.basePath)
        .withParentEnvironmentType(GeneralCommandLine.ParentEnvironmentType.CONSOLE)

    val processHandler = OSProcessHandler(commandLine)

    // Show in a run window (not exactly terminal, but displays output with ANSI colors)
    val console = TerminalExecutionConsole(project, processHandler)
    // Attach to a tool window or run configuration
    processHandler.startNotify()
}
```

### Alternative: Using ProcessBuilder for Reliable I/O

For the Claude CLI integration, `ProcessBuilder` (or `GeneralCommandLine`) is more appropriate than the Terminal API because you need to parse structured output:

```kotlin
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.CapturingProcessHandler
import com.intellij.execution.process.ProcessOutput

fun runClaudeCommand(project: Project, args: List<String>): ProcessOutput {
    val commandLine = GeneralCommandLine()
        .withExePath(getClaudeBinaryPath())
        .withParameters(args)
        .withWorkDirectory(project.basePath)
        .withParentEnvironmentType(GeneralCommandLine.ParentEnvironmentType.CONSOLE)
        .withCharset(Charsets.UTF_8)

    val handler = CapturingProcessHandler(commandLine)
    return handler.runProcess(30_000)  // 30 second timeout
}

// For long-running interactive processes:
fun startClaudeInteractive(
    project: Project,
    onStdout: (String) -> Unit,
    onStderr: (String) -> Unit,
    onExit: (Int) -> Unit
): OSProcessHandler {
    val commandLine = GeneralCommandLine()
        .withExePath(getClaudeBinaryPath())
        .withWorkDirectory(project.basePath)
        .withParentEnvironmentType(GeneralCommandLine.ParentEnvironmentType.CONSOLE)
        .withCharset(Charsets.UTF_8)

    val handler = OSProcessHandler(commandLine)

    handler.addProcessListener(object : com.intellij.execution.process.ProcessAdapter() {
        override fun onTextAvailable(event: com.intellij.execution.process.ProcessEvent, outputType: com.intellij.openapi.util.Key<*>) {
            val text = event.text
            if (outputType === com.intellij.execution.process.ProcessOutputTypes.STDOUT) {
                onStdout(text)
            } else if (outputType === com.intellij.execution.process.ProcessOutputTypes.STDERR) {
                onStderr(text)
            }
        }

        override fun processTerminated(event: com.intellij.execution.process.ProcessEvent) {
            onExit(event.exitCode)
        }
    })

    handler.startNotify()
    return handler
}
```

### Creating a Custom Terminal-Like Tool Window

For a custom "Claude Terminal" that wraps the CLI with a custom UI:

```kotlin
import com.intellij.execution.ui.ConsoleView
import com.intellij.execution.ui.ConsoleViewContentType
import com.intellij.execution.filters.TextConsoleBuilderFactory

fun createClaudeConsole(project: Project): ConsoleView {
    val console = TextConsoleBuilderFactory.getInstance()
        .createBuilder(project)
        .console

    // Write styled output
    console.print("Claude Code> ", ConsoleViewContentType.SYSTEM_OUTPUT)
    console.print("Ready\n", ConsoleViewContentType.NORMAL_OUTPUT)
    console.print("Error occurred\n", ConsoleViewContentType.ERROR_OUTPUT)

    return console
}
```

---

## 12. Notification API

### Key Classes

| Class | Purpose |
|-------|---------|
| `NotificationGroupManager` | Access registered notification groups |
| `NotificationGroup` | A group of related notifications (configured in plugin.xml) |
| `Notification` | A single notification instance |
| `NotificationAction` | A clickable action in a notification |
| `NotificationType` | INFORMATION, WARNING, ERROR |
| `ToolWindowManager` | Show balloon notifications on tool windows |

### Registering a Notification Group

```xml
<!-- plugin.xml -->
<extensions defaultExtensionNs="com.intellij">
    <!-- Balloon notification (floats in bottom-right) -->
    <notificationGroup id="Claude Code"
                       displayType="BALLOON"/>

    <!-- Sticky balloon (stays until dismissed) -->
    <notificationGroup id="Claude Code Important"
                       displayType="STICKY_BALLOON"/>

    <!-- Tool window notification (appears in Event Log) -->
    <notificationGroup id="Claude Code Log"
                       displayType="NONE"/>
</extensions>
```

### Simple Balloon Notification

```kotlin
import com.intellij.notification.NotificationGroupManager
import com.intellij.notification.NotificationType

fun notifyInfo(project: Project, title: String, content: String) {
    NotificationGroupManager.getInstance()
        .getNotificationGroup("Claude Code")
        .createNotification(title, content, NotificationType.INFORMATION)
        .notify(project)
}

fun notifyWarning(project: Project, title: String, content: String) {
    NotificationGroupManager.getInstance()
        .getNotificationGroup("Claude Code")
        .createNotification(title, content, NotificationType.WARNING)
        .notify(project)
}

fun notifyError(project: Project, title: String, content: String) {
    NotificationGroupManager.getInstance()
        .getNotificationGroup("Claude Code Important")
        .createNotification(title, content, NotificationType.ERROR)
        .notify(project)
}
```

### Notification with Actions

```kotlin
import com.intellij.notification.NotificationAction

fun notifyWithActions(project: Project, message: String) {
    val notification = NotificationGroupManager.getInstance()
        .getNotificationGroup("Claude Code")
        .createNotification("Claude Code", message, NotificationType.INFORMATION)

    notification.addAction(NotificationAction.createSimple("View Changes") {
        // Open diff viewer or navigate to changes
        notification.expire()
    })

    notification.addAction(NotificationAction.createSimple("Accept All") {
        // Accept all proposed changes
        notification.expire()
    })

    notification.addAction(NotificationAction.createSimple("Dismiss") {
        notification.expire()
    })

    notification.notify(project)
}
```

### Notification with Hyperlink

```kotlin
import com.intellij.notification.NotificationListener

fun notifyWithLink(project: Project) {
    val content = """
        Claude has suggested changes to 3 files.
        <a href="review">Review changes</a> |
        <a href="accept">Accept all</a>
    """.trimIndent()

    val notification = NotificationGroupManager.getInstance()
        .getNotificationGroup("Claude Code")
        .createNotification("Claude Code", content, NotificationType.INFORMATION)

    notification.setListener { notif, event ->
        when (event.description) {
            "review" -> {
                // Open diff viewer
            }
            "accept" -> {
                // Accept changes
                notif.expire()
            }
        }
    }

    notification.notify(project)
}
```

### Progress Indicator (for Long-Running Operations)

```kotlin
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task

fun runClaudeWithProgress(project: Project, prompt: String) {
    ProgressManager.getInstance().run(object : Task.Backgroundable(
        project,
        "Claude is thinking...",
        true  // cancellable
    ) {
        override fun run(indicator: com.intellij.openapi.progress.ProgressIndicator) {
            indicator.isIndeterminate = true
            indicator.text = "Sending request to Claude..."

            // Long-running operation
            Thread.sleep(1000)

            indicator.text = "Claude is analyzing your code..."
            indicator.fraction = 0.5

            // Continue processing
            Thread.sleep(1000)

            indicator.text = "Preparing response..."
            indicator.fraction = 0.9
        }

        override fun onSuccess() {
            // Called on EDT when task completes successfully
            notifyInfo(project, "Claude Code", "Analysis complete!")
        }

        override fun onCancel() {
            notifyInfo(project, "Claude Code", "Request cancelled.")
        }

        override fun onThrowable(error: Throwable) {
            notifyError(project, "Claude Code", "Error: ${error.message}")
        }
    })
}
```

### Status Bar Widget

```kotlin
import com.intellij.openapi.wm.StatusBar
import com.intellij.openapi.wm.StatusBarWidget
import com.intellij.openapi.wm.StatusBarWidgetFactory
import com.intellij.openapi.util.NlsContexts

class ClaudeStatusWidgetFactory : StatusBarWidgetFactory {
    override fun getId(): String = "ClaudeStatus"
    override fun getDisplayName(): @NlsContexts.ConfigurableName String = "Claude Code Status"
    override fun isAvailable(project: Project): Boolean = true
    override fun createWidget(project: Project): StatusBarWidget = ClaudeStatusWidget(project)
}

class ClaudeStatusWidget(private val project: Project) : StatusBarWidget,
    StatusBarWidget.TextPresentation {

    private var statusBar: StatusBar? = null
    private var currentStatus = "Claude: Ready"

    override fun ID(): String = "ClaudeStatus"

    override fun getPresentation(): StatusBarWidget.WidgetPresentation = this

    override fun install(statusBar: StatusBar) {
        this.statusBar = statusBar
    }

    override fun getText(): String = currentStatus

    override fun getAlignment(): Float = java.awt.Component.CENTER_ALIGNMENT

    override fun getTooltipText(): String = "Claude Code Status"

    override fun getClickConsumer(): com.intellij.util.Consumer<java.awt.event.MouseEvent>? {
        return com.intellij.util.Consumer {
            // Open Claude tool window on click
        }
    }

    fun updateStatus(status: String) {
        currentStatus = status
        statusBar?.updateWidget(ID())
    }

    override fun dispose() {}
}

// Register in plugin.xml:
// <statusBarWidgetFactory implementation="com.anthropic.claude.ClaudeStatusWidgetFactory"
//                          id="ClaudeStatus"
//                          order="after encodingWidget"/>
```

---

## 13. Threading Model Summary

IntelliJ has strict threading rules. Violating them causes `IncorrectOperationException` or deadlocks.

### Rules

| Operation | Required Thread | How to Invoke |
|-----------|----------------|---------------|
| Read document/PSI | Any thread (with read lock) | `ReadAction.run { }` or `runReadAction { }` |
| Write document/PSI | EDT + write lock | `WriteCommandAction.runWriteCommandAction(project) { }` |
| Access UI components | EDT | `ApplicationManager.getApplication().invokeLater { }` |
| Long-running work | Background thread | `ProgressManager` or `ApplicationManager.getApplication().executeOnPooledThread { }` |
| VFS operations | EDT + write lock | Inside `WriteAction.run { }` on EDT |

### Common Patterns for Claude Plugin

```kotlin
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.application.ReadAction
import com.intellij.openapi.command.WriteCommandAction

// Pattern 1: Read file content on background thread
fun readFileOnBackground(project: Project, path: String, callback: (String) -> Unit) {
    ApplicationManager.getApplication().executeOnPooledThread {
        val content = ReadAction.compute<String?, RuntimeException> {
            val vf = LocalFileSystem.getInstance().findFileByPath(path) ?: return@compute null
            val doc = FileDocumentManager.getInstance().getDocument(vf) ?: return@compute null
            doc.text
        }
        content?.let(callback)
    }
}

// Pattern 2: Apply changes from background thread
fun applyChangesFromBackground(project: Project, document: Document, newContent: String) {
    ApplicationManager.getApplication().invokeLater {
        WriteCommandAction.runWriteCommandAction(project) {
            document.setText(newContent)
        }
    }
}

// Pattern 3: Full async flow - read, process, write
fun asyncClaudeOperation(project: Project) {
    ApplicationManager.getApplication().executeOnPooledThread {
        // Read on background (with read lock)
        val context = ReadAction.compute<EditorContext?, RuntimeException> {
            gatherFullContext(project)
        }

        if (context == null) return@executeOnPooledThread

        // Process (still on background thread -- no lock needed for your own logic)
        val response = callClaudeAPI(context)

        // Write back on EDT
        ApplicationManager.getApplication().invokeLater {
            WriteCommandAction.runWriteCommandAction(project) {
                // Apply changes
            }
        }
    }
}
```

### Kotlin Coroutines (2024.1+)

IntelliJ 2024.1+ provides coroutine-friendly APIs:

```kotlin
import com.intellij.openapi.application.readAction
import com.intellij.openapi.application.writeAction
import com.intellij.platform.ide.progress.withBackgroundProgress
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

// In a coroutine scope (e.g., service scope):
fun CoroutineScope.processClaudeRequest(project: Project) {
    launch {
        // Read with read action (suspending)
        val context = readAction {
            gatherFullContext(project)
        }

        // Background progress
        withBackgroundProgress(project, "Claude is thinking...") {
            val response = callClaudeAPI(context!!)

            // Write action (suspending, runs on EDT)
            writeAction {
                // Apply response to document
            }
        }
    }
}
```

---

## 14. Recommendations for Claude Code Plugin

### Architecture Summary

Based on this research, here is the recommended approach for each major feature:

### Editor Context

- Use `FileEditorManager.getInstance(project).selectedTextEditor` for active editor.
- Wrap all reads in `ReadAction.compute { }` when off EDT.
- Build an `EditorContext` data class (section 1) to gather all context in one call.
- Support multi-caret by iterating `editor.caretModel.allCarets`.

### Applying Changes

- Always use `WriteCommandAction` with a descriptive name and group ID.
- For multi-file changes, use a single `WriteCommandAction` block so all changes are one undo.
- Apply edits in reverse offset order when doing multiple edits to the same document.
- Use `DocumentUtil.executeInBulk` for many small edits.

### Diff Viewing

- **Primary: `SimpleDiffRequest`** in a dialog with Accept/Reject buttons (section 3, Pattern A).
- Use `DiffContentFactory.getInstance().create(project, content, fileType)` for syntax highlighting.
- For multi-file diffs, use `SimpleDiffRequestChain`.
- Consider an embedded `DiffRequestPanel` inside the Claude tool window for inline review.
- Fall back to `MergeRequest` only for conflicting-edit scenarios.

### Terminal

- Use `TerminalView.createLocalShellWidget()` for a user-facing Claude terminal tab.
- Use `GeneralCommandLine` + `OSProcessHandler` for programmatic CLI interaction.
- Do NOT rely on terminal output scraping; use process I/O instead.

### Notifications

- Register three notification groups: `BALLOON` (transient), `STICKY_BALLOON` (important), `NONE` (log only).
- Use `NotificationAction` for actionable notifications (accept/reject/review).
- Use `ProgressManager` with `Task.Backgroundable` for long-running Claude operations.
- Add a `StatusBarWidget` for persistent status display.

### Undo

- All document modifications through `WriteCommandAction` are automatically undoable.
- Use a consistent `groupId` like `"claude.applyChanges"` to merge related edits.
- Name commands descriptively (e.g., `"Claude: Apply Changes to Main.kt"`) since this shows in Edit > Undo.

### Threading

- Never modify documents off EDT.
- Use `ReadAction` / `readAction` for background reads.
- Use `invokeLater { WriteCommandAction { } }` to write from background threads.
- Prefer coroutine-based APIs (`readAction`/`writeAction` suspending functions) on 2024.1+.

---

## Appendix A: Key Import Paths Quick Reference

```
Editor APIs:
  com.intellij.openapi.editor.Editor
  com.intellij.openapi.editor.EditorFactory
  com.intellij.openapi.editor.CaretModel
  com.intellij.openapi.editor.SelectionModel
  com.intellij.openapi.editor.ScrollingModel
  com.intellij.openapi.editor.LogicalPosition
  com.intellij.openapi.editor.VisualPosition
  com.intellij.openapi.editor.Document

File editors:
  com.intellij.openapi.fileEditor.FileEditorManager
  com.intellij.openapi.fileEditor.FileDocumentManager
  com.intellij.openapi.fileEditor.FileDocumentManagerListener

Diff:
  com.intellij.diff.DiffManager
  com.intellij.diff.DiffContentFactory
  com.intellij.diff.requests.SimpleDiffRequest
  com.intellij.diff.chains.SimpleDiffRequestChain
  com.intellij.diff.DiffRequestPanel

Commands/Undo:
  com.intellij.openapi.command.WriteCommandAction
  com.intellij.openapi.command.CommandProcessor
  com.intellij.openapi.command.undo.UndoManager
  com.intellij.openapi.command.undo.BasicUndoableAction

VFS:
  com.intellij.openapi.vfs.VirtualFile
  com.intellij.openapi.vfs.VirtualFileManager
  com.intellij.openapi.vfs.LocalFileSystem
  com.intellij.openapi.vfs.newvfs.BulkFileListener
  com.intellij.testFramework.LightVirtualFile

Actions:
  com.intellij.openapi.actionSystem.AnAction
  com.intellij.openapi.actionSystem.AnActionEvent
  com.intellij.openapi.actionSystem.CommonDataKeys

Terminal:
  org.jetbrains.plugins.terminal.TerminalView
  org.jetbrains.plugins.terminal.ShellTerminalWidget

Notifications:
  com.intellij.notification.NotificationGroupManager
  com.intellij.notification.NotificationType
  com.intellij.notification.NotificationAction
  com.intellij.notification.Notification

Inlays/Decorations:
  com.intellij.openapi.editor.InlayModel
  com.intellij.openapi.editor.EditorCustomElementRenderer
  com.intellij.openapi.editor.markup.MarkupModel
  com.intellij.openapi.editor.markup.RangeHighlighter
  com.intellij.openapi.editor.markup.GutterIconRenderer
  com.intellij.openapi.editor.EditorLinePainter
  com.intellij.codeInsight.inline.completion.InlineCompletionProvider

Threading:
  com.intellij.openapi.application.ApplicationManager
  com.intellij.openapi.application.ReadAction
  com.intellij.openapi.application.WriteAction
  com.intellij.openapi.command.WriteCommandAction
  com.intellij.openapi.progress.ProgressManager
  com.intellij.openapi.progress.Task
  com.intellij.platform.ide.progress.withBackgroundProgress  (2024.1+)
  com.intellij.openapi.application.readAction   (coroutine, 2024.1+)
  com.intellij.openapi.application.writeAction   (coroutine, 2024.1+)

Process execution:
  com.intellij.execution.configurations.GeneralCommandLine
  com.intellij.execution.process.OSProcessHandler
  com.intellij.execution.process.CapturingProcessHandler
  com.intellij.execution.process.ProcessAdapter
  com.intellij.execution.process.ProcessOutputTypes

UI:
  com.intellij.openapi.ui.DialogWrapper
  com.intellij.openapi.wm.ToolWindow
  com.intellij.openapi.wm.StatusBarWidget
  com.intellij.openapi.wm.StatusBarWidgetFactory
```

## Appendix B: plugin.xml Skeleton with All Extension Points

```xml
<idea-plugin>
    <id>com.anthropic.claude-code</id>
    <name>Claude Code</name>
    <vendor email="support@anthropic.com" url="https://anthropic.com">Anthropic</vendor>
    <depends>com.intellij.modules.platform</depends>
    <depends optional="true" config-file="terminal-support.xml">org.jetbrains.plugins.terminal</depends>

    <extensions defaultExtensionNs="com.intellij">
        <!-- Tool Window -->
        <toolWindow id="Claude" anchor="right" secondary="false"
                    factoryClass="com.anthropic.claude.ui.ClaudeToolWindowFactory"
                    icon="/icons/claude-13.svg"/>

        <!-- Settings -->
        <projectService serviceImplementation="com.anthropic.claude.services.ClaudeSettings"/>
        <projectService serviceImplementation="com.anthropic.claude.services.ClaudeService"/>
        <projectService serviceImplementation="com.anthropic.claude.services.ClaudeChangeManager"/>

        <projectConfigurable instance="com.anthropic.claude.settings.ClaudeConfigurable"
                             displayName="Claude Code" id="claude.settings"
                             parentId="tools"/>

        <!-- Notifications -->
        <notificationGroup id="Claude Code" displayType="BALLOON"/>
        <notificationGroup id="Claude Code Important" displayType="STICKY_BALLOON"/>
        <notificationGroup id="Claude Code Log" displayType="NONE"/>

        <!-- Status bar -->
        <statusBarWidgetFactory implementation="com.anthropic.claude.ui.ClaudeStatusWidgetFactory"
                                id="ClaudeStatus" order="after encodingWidget"/>

        <!-- Line painter (for inline annotations) -->
        <editorLinePainter implementation="com.anthropic.claude.editor.ClaudeLinePainter"/>

        <!-- Inline completion (2024.1+) -->
        <!-- <inlineCompletionProvider implementation="com.anthropic.claude.editor.ClaudeInlineCompletionProvider"/> -->
    </extensions>

    <!-- File save listener -->
    <applicationListeners>
        <listener class="com.anthropic.claude.listeners.ClaudeFileSaveListener"
                  topic="com.intellij.openapi.fileEditor.FileDocumentManagerListener"/>
        <listener class="com.anthropic.claude.listeners.ClaudeFileChangeListener"
                  topic="com.intellij.openapi.vfs.newvfs.BulkFileListener"/>
    </applicationListeners>

    <actions>
        <!-- Main menu group -->
        <group id="Claude.MainMenu" text="Claude" popup="true">
            <add-to-group group-id="ToolsMenu" anchor="last"/>
            <action id="Claude.OpenPanel" class="com.anthropic.claude.actions.OpenPanelAction"
                    text="Open Claude Panel" icon="/icons/claude-13.svg">
                <keyboard-shortcut keymap="$default" first-keystroke="ctrl BACK_QUOTE"/>
                <keyboard-shortcut keymap="Mac OS X" first-keystroke="meta BACK_QUOTE"/>
            </action>
        </group>

        <!-- Editor context menu -->
        <group id="Claude.EditorPopup" text="Claude" popup="true" icon="/icons/claude-13.svg">
            <add-to-group group-id="EditorPopupMenu" anchor="last"/>
            <action id="Claude.AskAboutSelection"
                    class="com.anthropic.claude.actions.AskAboutSelectionAction"
                    text="Ask Claude About Selection">
                <keyboard-shortcut keymap="$default" first-keystroke="ctrl shift K"/>
                <keyboard-shortcut keymap="Mac OS X" first-keystroke="meta shift K"/>
            </action>
            <action id="Claude.ExplainCode" class="com.anthropic.claude.actions.ExplainCodeAction"
                    text="Explain This Code"/>
            <action id="Claude.RefactorCode" class="com.anthropic.claude.actions.RefactorCodeAction"
                    text="Suggest Refactoring"/>
            <action id="Claude.AddTests" class="com.anthropic.claude.actions.AddTestsAction"
                    text="Generate Tests"/>
            <separator/>
            <action id="Claude.CustomPrompt" class="com.anthropic.claude.actions.CustomPromptAction"
                    text="Custom Prompt..."/>
        </group>

        <!-- Project view context menu -->
        <action id="Claude.AskAboutFile" class="com.anthropic.claude.actions.AskAboutFileAction"
                text="Ask Claude About This File" icon="/icons/claude-13.svg">
            <add-to-group group-id="ProjectViewPopupMenu" anchor="last"/>
        </action>
    </actions>
</idea-plugin>
```
