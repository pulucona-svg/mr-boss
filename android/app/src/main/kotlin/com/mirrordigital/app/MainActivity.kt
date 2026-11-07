package com.mirrordigital.app

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

class MainActivity : FlutterActivity() {
    
    companion object {
        private const val SECURITY_CHANNEL = "com.mirrordigital.app/security"
        private const val DOCUMENTS_CHANNEL = "com.mirrordigital.app/external_documents"
    }

    private var externalDocumentsChannel: MethodChannel? = null
    private var pendingInitialDocument: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // GLOBAL APP-WIDE SCREENSHOT & SCREEN-RECORDING PROTECTION
        // Enforces FLAG_SECURE from the earliest appropriate point across all application screens.
        // Protects screenshots, video recordings, and Recent Apps multitasking previews globally.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)

        handleIncomingIntent(intent, isInitial = true)
    }

    override fun onResume() {
        super.onResume()
        // Guarantee FLAG_SECURE persists across activity resumptions and configuration changes
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent, isInitial = false)
    }

    private fun handleIncomingIntent(intent: Intent?, isInitial: Boolean) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_SEND) return

        val rawUri: Uri? = when (action) {
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
        }

        // Gracefully exit if the incoming intent has no valid URI
        if (rawUri == null) {
            return
        }

        // Establish non-nullable target URI for safe operations
        val targetUri: Uri = rawUri

        try {
            // Verify MIME type or extension
            val mimeType: String? = intent.type ?: try {
                contentResolver.getType(targetUri)
            } catch (_: Exception) {
                null
            }

            val uriString = targetUri.toString()
            val isPdf = (mimeType != null && mimeType.contains("pdf", ignoreCase = true)) ||
                    uriString.contains(".pdf", ignoreCase = true)

            // Strictly enforce supported document formats - reject unsupported MIME types gracefully
            if (!isPdf) {
                return
            }

            // Resolve human-readable display name safely via ContentResolver
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

            // Safely stream copy the document to application cache directory
            val destDir = File(cacheDir, "external_documents")
            if (!destDir.exists()) {
                destDir.mkdirs()
            }

            val sanitizedTitle = displayName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val destFile = File(destDir, "${System.currentTimeMillis()}_$sanitizedTitle")

            val inputStream = try {
                contentResolver.openInputStream(targetUri)
            } catch (_: Exception) {
                null
            } ?: return

            inputStream.use { input ->
                destFile.outputStream().use { output ->
                    input.copyTo(output, bufferSize = 8192)
                }
            }

            if (!destFile.exists() || destFile.length() == 0L) {
                destFile.delete()
                return
            }

            val docData = mapOf(
                "filePath" to destFile.absolutePath,
                "title" to displayName.removeSuffix(".pdf").removeSuffix(".PDF"),
                "mimeType" to (mimeType ?: "application/pdf")
            )

            if (isInitial) {
                pendingInitialDocument = docData
            } else {
                externalDocumentsChannel?.invokeMethod("onDocumentReceived", docData)
            }
        } catch (_: Exception) {
            // Gracefully ignore corrupt, permission-denied or unreadable external intents
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecureScreen" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "disableSecureScreen" -> {
                    // Global security policy: Protection is enforced application-wide.
                    // Sub-screens (such as document readers) cannot disable global protection upon disposal.
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "isSecureScreenEnabled" -> {
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
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
                                destDir.listFiles()?.forEach { it.delete() }
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
