package com.mirrordigital.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Transparent trampoline activity for incoming "Open With" external document intents.
 *
 * External apps (e.g. WhatsApp, Telegram, file managers) fire ACTION_VIEW without
 * FLAG_ACTIVITY_NEW_TASK or FLAG_ACTIVITY_NEW_DOCUMENT. If handled directly by a standard
 * activity, the document opens inside the originating app's task stack or collapses into
 * an existing Flutter instance.
 *
 * DocumentDispatchActivity intercepts the intent, attaches FLAG_ACTIVITY_NEW_DOCUMENT,
 * FLAG_ACTIVITY_MULTIPLE_TASK, FLAG_ACTIVITY_NEW_TASK, and FLAG_GRANT_READ_URI_PERMISSION,
 * targets ExternalDocumentActivity, and immediately finishes.
 *
 * This forces Android's ActivityTaskManager to create an independent document task entry
 * in Recent Apps (Overview screen) for each opened document.
 */
class DocumentDispatchActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val incoming = intent
        if (incoming == null) {
            finish()
            return
        }

        val targetIntent = Intent(incoming).apply {
            setClass(this@DocumentDispatchActivity, ExternalDocumentActivity::class.java)
            // Task creation flags:
            // FLAG_ACTIVITY_NEW_DOCUMENT: Creates a root document task in Android Recent Apps
            // FLAG_ACTIVITY_MULTIPLE_TASK: Forces a new task even if another document task exists
            // FLAG_ACTIVITY_NEW_TASK: Required when starting a task from a non-activity or across boundaries
            // FLAG_GRANT_READ_URI_PERMISSION: Propagates content URI read permission
            addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
            addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        try {
            startActivity(targetIntent)
        } catch (_: Exception) {}
        finish()
    }
}
