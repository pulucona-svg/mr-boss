package com.example.mirror_laikipia

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    
    // TOGGLE: Set to true to ENABLE screenshot protection, false to DISABLE it.
    // This blocks screenshots, screen recordings, and hides recent app previews.
    private val SECURE_SCREEN_ENABLED = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        if (SECURE_SCREEN_ENABLED) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
