package com.rochapps.flashbackcam

import android.content.ContentValues
import android.graphics.Color
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executors

/**
 * ═══════════════════════════════════════════════════════════════════════════════
 * MAIN ACTIVITY - COLD START OPTIMIZED & ANDROID 15 EDGE-TO-EDGE COMPLIANT
 * 
 * ANDROID 15 (API 35) EDGE-TO-EDGE COMPLIANCE:
 * 
 * On Android 15, apps targeting SDK 35+ automatically run edge-to-edge.
 * The following deprecated APIs are NO LONGER USED:
 * - Window.setStatusBarColor() - deprecated, ignored on API 35+
 * - Window.setNavigationBarColor() - deprecated, ignored on API 35+
 * - Window.setNavigationBarDividerColor() - deprecated, ignored on API 35+
 * 
 * Instead, we use:
 * - WindowCompat.setDecorFitsSystemWindows(window, false) - enables edge-to-edge
 * - WindowInsetsControllerCompat - controls system bar appearance (light/dark icons)
 * - App handles insets via Flutter's SafeArea/MediaQuery
 * 
 * COLD START OPTIMIZATION STRATEGY:
 * 
 * 1. onCreate() does minimal work:
 *    - Install splash screen (Android 12+ API)
 *    - Enable edge-to-edge display
 *    - Call super.onCreate()
 *    - That's it - no heavy initialization
 * 
 * 2. All heavy work is deferred to Flutter:
 *    - Camera initialization → User taps "Start Buffer"
 *    - AdMob SDK → First ad request
 *    - Billing client → Paywall opened
 *    - Analytics → Background after UI visible
 * 
 * 3. First frame target: <500ms
 *    - Splash screen shows branding only
 *    - No blocking operations
 *    - Flutter engine starts in parallel
 * 
 * ═══════════════════════════════════════════════════════════════════════════════
 */
class MainActivity : FlutterActivity() {
    private val mediaChannel = "flashback_cam/media"
    private val ioExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        // ═══════════════════════════════════════════════════════════════════════
        // COLD START: Install splash screen BEFORE super.onCreate()
        // This uses the Android 12+ SplashScreen API for smoother cold start
        // The splash is purely for branding - no blocking work happens here
        // ═══════════════════════════════════════════════════════════════════════
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val splashScreen = installSplashScreen()
            // Don't keep splash screen visible - let Flutter take over immediately
            // The splash screen is just for branding during process creation
            splashScreen.setKeepOnScreenCondition { false }
        }
        
        // ═══════════════════════════════════════════════════════════════════════
        // ANDROID 15 EDGE-TO-EDGE SETUP
        // 
        // CRITICAL: Do NOT use deprecated APIs:
        // - window.statusBarColor = Color.TRANSPARENT (deprecated API 35)
        // - window.navigationBarColor = Color.TRANSPARENT (deprecated API 35)
        //
        // Instead use WindowCompat and WindowInsetsControllerCompat
        // ═══════════════════════════════════════════════════════════════════════
        
        // Enable edge-to-edge display - tells system we handle insets ourselves
        WindowCompat.setDecorFitsSystemWindows(window, false)
        
        // Use WindowInsetsControllerCompat for system bar appearance (not color!)
        // This is the Android 15-compliant way to control light/dark system bar icons
        WindowCompat.getInsetsController(window, window.decorView).apply {
            // Light status bar icons (white) for dark backgrounds - camera app
            isAppearanceLightStatusBars = false
            // Light navigation bar icons (white) for dark backgrounds
            isAppearanceLightNavigationBars = false
        }
        
        // Call super - this starts Flutter engine
        // COLD START: No other work should happen in onCreate
        super.onCreate(savedInstanceState)
        
        // Log cold start timing for debugging
        android.util.Log.d("ColdStart", "MainActivity.onCreate() complete - Edge-to-edge enabled")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register our comprehensive camera plugin
        flutterEngine.plugins.add(CameraPlugin())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveVideoToGallery" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        if (sourcePath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "Source path is missing", null)
                        } else {
                            ioExecutor.execute {
                                try {
                                    val savedLocation = saveVideoToGallery(sourcePath)
                                    runOnUiThread { result.success(savedLocation) }
                                } catch (e: Exception) {
                                    runOnUiThread {
                                        result.error("SAVE_FAILED", e.localizedMessage, null)
                                    }
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun saveVideoToGallery(sourcePath: String): String {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw IOException("Source file does not exist")
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            insertViaMediaStore(sourceFile)
        } else {
            copyToPublicMovies(sourceFile)
        }
    }

    private fun insertViaMediaStore(sourceFile: File): String {
        val resolver = applicationContext.contentResolver
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)

        val displayName = sourceFile.name.ifEmpty { "flashback_${System.currentTimeMillis()}.mp4" }

        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.DATE_ADDED, System.currentTimeMillis() / 1000)
            put(MediaStore.Video.Media.DATE_TAKEN, System.currentTimeMillis())
            put(
                MediaStore.Video.Media.RELATIVE_PATH,
                "${Environment.DIRECTORY_MOVIES}/Flashback Cam"
            )
        }

        var uri: Uri? = null
        try {
            uri = resolver.insert(collection, values)
            if (uri == null) throw IOException("Failed to create MediaStore entry")

            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(output)
                }
            } ?: throw IOException("Failed to open output stream")

            return uri.toString()
        } catch (e: Exception) {
            uri?.let { resolver.delete(it, null, null) }
            throw e
        }
    }

    @Suppress("DEPRECATION")
    private fun copyToPublicMovies(sourceFile: File): String {
        val moviesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        val flashbackDir = File(moviesDir, "Flashback Cam")
        if (!flashbackDir.exists()) {
            flashbackDir.mkdirs()
        }

        val destinationFile = File(flashbackDir, sourceFile.name)
        FileInputStream(sourceFile).use { input ->
            FileOutputStream(destinationFile).use { output ->
                input.copyTo(output)
            }
        }

        MediaScannerConnection.scanFile(
            applicationContext,
            arrayOf(destinationFile.absolutePath),
            arrayOf("video/mp4"),
            null
        )

        return destinationFile.absolutePath
    }
}
