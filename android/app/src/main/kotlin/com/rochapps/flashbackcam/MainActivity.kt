package com.rochapps.flashbackcam

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val mediaChannel = "flashback_cam/media"
    private val ioExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        // Enable edge-to-edge display for Android 15+ compatibility
        // This tells the system we want to handle insets ourselves
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
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
