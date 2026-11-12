package com.mirrordigital.app

import android.app.ActivityManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Dedicated Activity for external documents opened via "Open With" or file sharing.
 *
 * Runs as an independent root document task in Android Recent Apps with taskAffinity="".
 * Each document opened receives its own ExternalDocumentActivity instance, its own
 * FlutterEngine, its own viewer state, and its own labeled Recent Apps task card.
 */
class ExternalDocumentActivity : FlutterActivity() {

    companion object {
        private const val SECURITY_CHANNEL = "com.mirrordigital.app/security"
        private const val DOCUMENTS_CHANNEL = "com.mirrordigital.app/external_documents"
    }

    private var externalDocumentsChannel: MethodChannel? = null
    private var pendingInitialDocument: Map<String, Any?>? = null
    private val sessionCachedFiles = mutableListOf<File>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // GLOBAL APP-WIDE SCREENSHOT & SCREEN-RECORDING PROTECTION
        // Enforces FLAG_SECURE from the earliest appropriate point.
        // Protects screenshots, video recordings, and Recent Apps multitasking previews.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)

        handleIncomingDocument(intent)
    }

    override fun onResume() {
        super.onResume()
        // Guarantee FLAG_SECURE persists across activity resumptions and configuration changes
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onDestroy() {
        super.onDestroy()
        // Clean up only temporary document files created by this specific activity session
        sessionCachedFiles.forEach { file ->
            try {
                if (file.exists()) file.delete()
            } catch (_: Exception) {}
        }
        sessionCachedFiles.clear()
    }

    private fun handleIncomingDocument(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_SEND) return

        val rawUri = when (action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
            }
            else -> null
        } ?: return

        val targetUri: Uri = rawUri

        try {
            val mimeType: String? = intent.type ?: try {
                contentResolver.getType(targetUri)
            } catch (_: Exception) {
                null
            }

            val uriString = targetUri.toString()
            val isPdf = (mimeType != null && mimeType.contains("pdf", ignoreCase = true)) ||
                    uriString.contains(".pdf", ignoreCase = true)

            if (!isPdf) return

            var displayName = "external_document.pdf"
            try {
                contentResolver.query(targetUri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex != -1) {
                            val queriedName = cursor.getString(nameIndex)
                            if (!queriedName.isNullOrBlank()) {
                                displayName = queriedName
                            }
                        }
                    }
                }
            } catch (_: Exception) {
                val lastSegment = targetUri.lastPathSegment
                if (lastSegment != null) {
                    val cleanSegment = lastSegment.substringAfterLast('/')
                    if (cleanSegment.isNotBlank()) {
                        displayName = cleanSegment
                    }
                }
            }

            if (!displayName.endsWith(".pdf", ignoreCase = true)) {
                displayName += ".pdf"
            }

            val cleanDocTitle = displayName.removeSuffix(".pdf").removeSuffix(".PDF")

            // SET ANDROID RECENT APPS TASK CARD TITLE
            // In Android Overview / Recent Apps, sets the task card title to:
            // "Mirror Digital — [Document Title]" (e.g. "Mirror Digital — PDF A")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try {
                    @Suppress("DEPRECATION")
                    val taskDesc = ActivityManager.TaskDescription("Mirror Digital — $cleanDocTitle")
                    setTaskDescription(taskDesc)
                } catch (_: Exception) {}
            }

            // Stream copy the document to an isolated session cache
            val destDir = File(cacheDir, "external_documents")
            if (!destDir.exists()) {
                destDir.mkdirs()
            }

            val sanitizedTitle = displayName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val destFile = File(destDir, "${System.currentTimeMillis()}_$sanitizedTitle")

            val inputStream = contentResolver.openInputStream(targetUri) ?: return
            inputStream.use { input ->
                destFile.outputStream().use { output ->
                    input.copyTo(output, bufferSize = 8192)
                }
            }

            if (!destFile.exists() || destFile.length() == 0L) {
                destFile.delete()
                return
            }

            sessionCachedFiles.add(destFile)

            val docData = mapOf(
                "filePath" to destFile.absolutePath,
                "title" to cleanDocTitle,
                "mimeType" to (mimeType ?: "application/pdf")
            )

            pendingInitialDocument = docData
            externalDocumentsChannel?.invokeMethod("onDocumentReceived", docData)
        } catch (_: Exception) {
            // Gracefully ignore corrupt or permission-denied intents
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecureScreen", "disableSecureScreen", "isSecureScreenEnabled" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        externalDocumentsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOCUMENTS_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialDocument" -> {
                        val doc = pendingInitialDocument
                        pendingInitialDocument = null
                        result.success(doc)
                    }
                    "clearExternalDocumentsCache" -> {
                        try {
                            val destDir = File(cacheDir, "external_documents")
                            if (destDir.exists()) {
                                val now = System.currentTimeMillis()
                                destDir.listFiles()?.forEach { file ->
                                    val isCurrentSession = sessionCachedFiles.any { it.absolutePath == file.absolutePath }
                                    val isRecent = (now - file.lastModified()) < 2 * 60 * 60 * 1000L
                                    if (!isCurrentSession && !isRecent) {
                                        file.delete()
                                    }
                                }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}
