package com.mirrordigital.app

import android.content.Intent
import android.os.Bundle
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // GLOBAL APP-WIDE SCREENSHOT & SCREEN-RECORDING PROTECTION
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)

        // If an external document intent somehow targeted MainActivity directly,
        // dispatch it to DocumentDispatchActivity so it opens in its own independent document task
        val action = intent?.action
        if (action == Intent.ACTION_VIEW || action == Intent.ACTION_SEND) {
            val dispatchIntent = Intent(intent).apply {
                setClass(this@MainActivity, ExternalDocumentActivity::class.java)
                addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
                addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(dispatchIntent)
            finish()
            return
        }
    }

    override fun onResume() {
        super.onResume()
        // Guarantee FLAG_SECURE persists across activity resumptions and configuration changes
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.action
        if (action == Intent.ACTION_VIEW || action == Intent.ACTION_SEND) {
            val dispatchIntent = Intent(intent).apply {
                setClass(this@MainActivity, ExternalDocumentActivity::class.java)
                addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
                addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(dispatchIntent)
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOCUMENTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialDocument" -> {
                    // MainActivity is the main app launcher, external documents open in ExternalDocumentActivity
                    result.success(null)
                }
                "clearExternalDocumentsCache" -> {
                    try {
                        val destDir = File(cacheDir, "external_documents")
                        if (destDir.exists()) {
                            val now = System.currentTimeMillis()
                            // Retain any files created within the last 2 hours
                            destDir.listFiles()?.forEach { file ->
                                val isRecent = (now - file.lastModified()) < 2 * 60 * 60 * 1000L
                                if (!isRecent) {
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
