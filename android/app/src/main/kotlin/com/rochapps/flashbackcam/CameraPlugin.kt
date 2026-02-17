package com.rochapps.flashbackcam

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.app.ActivityManager
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.hardware.camera2.params.StreamConfigurationMap
import android.hardware.display.DisplayManager
import android.location.Location
import android.media.Image
import android.media.ImageReader
import android.media.MediaRecorder
import android.media.MediaMuxer
import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaCodecInfo
import android.media.MediaMetadataRetriever
import android.media.AudioRecord
import android.media.AudioFormat as AndroidAudioFormat
import android.media.MediaScannerConnection
import java.nio.ByteBuffer
import java.util.concurrent.ArrayBlockingQueue
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.util.Range
import android.util.SparseIntArray
import android.util.Size
import android.view.Surface
import android.view.Display
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.IOException
import java.util.*
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import kotlin.collections.HashMap
import kotlin.math.abs
import kotlin.math.max
import android.os.StatFs

// ═══════════════════════════════════════════════════════════════════════════════
// STORAGE MANAGEMENT - Low storage handling to prevent crashes and corruption
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Storage mode indicating current storage conditions.
 * Exposed to Flutter for UI adaptation.
 */
enum class StorageMode {
    NORMAL,     // Sufficient storage - all features available
    LOW         // Low storage - 4K disabled, buffer duration limited
}

/**
 * Result of storage check operations
 */
data class StorageCheckResult(
    val hasEnoughSpace: Boolean,
    val availableBytes: Long,
    val requiredBytes: Long,
    val storageMode: StorageMode,
    val message: String? = null
)

/**
 * Manages storage checks and cleanup for the disk-based buffer system.
 * Provides configurable thresholds based on resolution and fps.
 */
class StorageManager(private val context: Context) {
    private val TAG = "StorageManager"
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // CONFIGURABLE THRESHOLDS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    companion object {
        // Minimum free space required to START buffering (configurable by quality)
        // These values account for buffer size + overhead
        private const val MIN_FREE_SPACE_4K_60FPS = 800L * 1024 * 1024      // 800 MB for 4K 60fps
        private const val MIN_FREE_SPACE_4K_30FPS = 500L * 1024 * 1024      // 500 MB for 4K 30fps
        private const val MIN_FREE_SPACE_1080P_60FPS = 400L * 1024 * 1024   // 400 MB for 1080p 60fps
        private const val MIN_FREE_SPACE_1080P_30FPS = 300L * 1024 * 1024   // 300 MB for 1080p 30fps
        private const val MIN_FREE_SPACE_720P = 200L * 1024 * 1024          // 200 MB for 720p
        private const val MIN_FREE_SPACE_DEFAULT = 500L * 1024 * 1024       // 500 MB default
        
        // Safety margin for recording (added to estimated recording size)
        private const val RECORDING_SAFETY_MARGIN = 200L * 1024 * 1024      // 200 MB
        
        // Low storage threshold - triggers smart mode
        private const val LOW_STORAGE_THRESHOLD = 1024L * 1024 * 1024       // 1 GB
        
        // Maximum buffer duration in low storage mode
        const val LOW_STORAGE_MAX_BUFFER_SECONDS = 10
        
        // Approximate bitrates for space estimation (bytes per second)
        // These are conservative estimates to ensure we don't run out of space
        private const val BITRATE_4K_60FPS = 6_000_000L       // ~48 Mbps / 8 = 6 MB/s
        private const val BITRATE_4K_30FPS = 3_500_000L       // ~28 Mbps / 8 = 3.5 MB/s
        private const val BITRATE_1080P_60FPS = 2_000_000L    // ~16 Mbps / 8 = 2 MB/s
        private const val BITRATE_1080P_30FPS = 1_000_000L    // ~8 Mbps / 8 = 1 MB/s
        private const val BITRATE_720P = 500_000L             // ~4 Mbps / 8 = 0.5 MB/s
    }
    
    private var bufferDirectory: File? = null
    
    /**
     * Get the app-specific buffer directory.
     * Uses getExternalFilesDir for better performance, falls back to cacheDir.
     */
    fun getBufferDirectory(): File {
        if (bufferDirectory == null) {
            // Try external files dir first (better I/O performance)
            bufferDirectory = context.getExternalFilesDir("flashback_buffer")
                ?: File(context.cacheDir, "flashback_buffer")
            
            // Ensure directory exists
            bufferDirectory?.mkdirs()
        }
        return bufferDirectory!!
    }
    
    /**
     * Get available free space in bytes at the buffer storage location.
     */
    fun getAvailableFreeSpace(): Long {
        return try {
            val dir = getBufferDirectory()
            val statFs = StatFs(dir.absolutePath)
            statFs.availableBytes
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get free space", e)
            0L
        }
    }
    
    /**
     * Get total storage space in bytes.
     */
    fun getTotalStorageSpace(): Long {
        return try {
            val dir = getBufferDirectory()
            val statFs = StatFs(dir.absolutePath)
            statFs.totalBytes
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get total space", e)
            0L
        }
    }
    
    /**
     * Determine current storage mode based on available space.
     */
    fun getCurrentStorageMode(): StorageMode {
        val availableSpace = getAvailableFreeSpace()
        return if (availableSpace < LOW_STORAGE_THRESHOLD) {
            StorageMode.LOW
        } else {
            StorageMode.NORMAL
        }
    }
    
    /**
     * Get minimum free space required to start buffering for given settings.
     */
    fun getMinBufferFreeSpace(resolution: String, fps: Int): Long {
        return when {
            resolution == "4K" && fps >= 60 -> MIN_FREE_SPACE_4K_60FPS
            resolution == "4K" && fps < 60 -> MIN_FREE_SPACE_4K_30FPS
            resolution == "1080P" && fps >= 60 -> MIN_FREE_SPACE_1080P_60FPS
            resolution == "1080P" && fps < 60 -> MIN_FREE_SPACE_1080P_30FPS
            resolution == "720P" -> MIN_FREE_SPACE_720P
            else -> MIN_FREE_SPACE_DEFAULT
        }
    }
    
    /**
     * Get approximate bitrate for given settings (bytes per second).
     */
    fun getApproximateBitrate(resolution: String, fps: Int): Long {
        return when {
            resolution == "4K" && fps >= 60 -> BITRATE_4K_60FPS
            resolution == "4K" && fps < 60 -> BITRATE_4K_30FPS
            resolution == "1080P" && fps >= 60 -> BITRATE_1080P_60FPS
            resolution == "1080P" && fps < 60 -> BITRATE_1080P_30FPS
            resolution == "720P" -> BITRATE_720P
            else -> BITRATE_1080P_30FPS
        }
    }
    
    /**
     * Check if there's enough space to start buffering.
     */
    fun checkBufferStartSpace(resolution: String, fps: Int): StorageCheckResult {
        val availableSpace = getAvailableFreeSpace()
        val requiredSpace = getMinBufferFreeSpace(resolution, fps)
        val storageMode = getCurrentStorageMode()
        
        Log.d(TAG, "Buffer space check: available=${availableSpace / 1024 / 1024}MB, " +
                "required=${requiredSpace / 1024 / 1024}MB, mode=$storageMode")
        
        return if (availableSpace >= requiredSpace) {
            StorageCheckResult(
                hasEnoughSpace = true,
                availableBytes = availableSpace,
                requiredBytes = requiredSpace,
                storageMode = storageMode
            )
        } else {
            StorageCheckResult(
                hasEnoughSpace = false,
                availableBytes = availableSpace,
                requiredBytes = requiredSpace,
                storageMode = storageMode,
                message = "Not enough storage for buffer. Please free up space or reduce quality."
            )
        }
    }
    
    /**
     * Check if there's enough space to start recording.
     * Estimates space needed for: current buffer + expected recording duration + safety margin.
     */
    fun checkRecordingStartSpace(
        resolution: String,
        fps: Int,
        bufferDurationSeconds: Int,
        expectedRecordingSeconds: Int
    ): StorageCheckResult {
        val availableSpace = getAvailableFreeSpace()
        val bitrate = getApproximateBitrate(resolution, fps)
        val storageMode = getCurrentStorageMode()
        
        // Calculate required space:
        // - Buffer content (already partially on disk, but may need to be kept)
        // - Expected recording duration
        // - Safety margin
        val bufferSize = bitrate * bufferDurationSeconds
        val recordingSize = bitrate * expectedRecordingSeconds
        val requiredSpace = bufferSize + recordingSize + RECORDING_SAFETY_MARGIN
        
        Log.d(TAG, "Recording space check: available=${availableSpace / 1024 / 1024}MB, " +
                "required=${requiredSpace / 1024 / 1024}MB (buffer=${bufferSize / 1024 / 1024}MB, " +
                "recording=${recordingSize / 1024 / 1024}MB, safety=${RECORDING_SAFETY_MARGIN / 1024 / 1024}MB)")
        
        return if (availableSpace >= requiredSpace) {
            StorageCheckResult(
                hasEnoughSpace = true,
                availableBytes = availableSpace,
                requiredBytes = requiredSpace,
                storageMode = storageMode
            )
        } else {
            StorageCheckResult(
                hasEnoughSpace = false,
                availableBytes = availableSpace,
                requiredBytes = requiredSpace,
                storageMode = storageMode,
                message = "Not enough storage to safely record. Try reducing resolution, frame rate, or buffer duration."
            )
        }
    }
    
    /**
     * Get adjusted settings for low storage mode.
     * Returns map with adjusted resolution, fps, and maxBufferSeconds.
     */
    fun getAdjustedSettingsForLowStorage(
        requestedResolution: String,
        requestedFps: Int,
        requestedBufferSeconds: Int
    ): Map<String, Any> {
        val storageMode = getCurrentStorageMode()
        
        return if (storageMode == StorageMode.LOW) {
            mapOf(
                "resolution" to if (requestedResolution == "4K") "1080P" else requestedResolution,
                "fps" to if (requestedResolution == "4K" || requestedFps > 30) 30 else requestedFps,
                "maxBufferSeconds" to minOf(requestedBufferSeconds, LOW_STORAGE_MAX_BUFFER_SECONDS),
                "storageMode" to "low",
                "adjusted" to true
            )
        } else {
            mapOf(
                "resolution" to requestedResolution,
                "fps" to requestedFps,
                "maxBufferSeconds" to requestedBufferSeconds,
                "storageMode" to "normal",
                "adjusted" to false
            )
        }
    }
    
    /**
     * Clean up all buffer files in the buffer directory.
     * Called when buffer stops, app closes, or buffer reinitializes.
     */
    fun cleanupBufferFiles() {
        try {
            val dir = getBufferDirectory()
            if (dir.exists()) {
                var deletedCount = 0
                var deletedSize = 0L
                
                dir.listFiles()?.forEach { file ->
                    if (file.isFile && (file.name.startsWith("segment_") || 
                        file.name.startsWith("dvr_buffer_") ||
                        file.name.endsWith(".bin"))) {
                        deletedSize += file.length()
                        if (file.delete()) {
                            deletedCount++
                        }
                    } else if (file.isDirectory && file.name.startsWith("dvr_buffer_")) {
                        deletedSize += file.walkTopDown().filter { it.isFile }.sumOf { it.length() }
                        if (file.deleteRecursively()) {
                            deletedCount++
                        }
                    }
                }
                
                Log.d(TAG, "Cleaned up $deletedCount buffer files (${deletedSize / 1024 / 1024}MB)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cleanup buffer files", e)
        }
    }
    
    /**
     * Clean up old buffer directories (from previous sessions).
     */
    fun cleanupOldBufferDirectories() {
        try {
            // Clean from cache dir
            context.cacheDir.listFiles()?.filter { 
                it.name.startsWith("dvr_buffer_") && it.isDirectory 
            }?.forEach { dir ->
                try {
                    val deletedSize = dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
                    dir.deleteRecursively()
                    Log.d(TAG, "Cleaned old buffer dir: ${dir.name} (${deletedSize / 1024 / 1024}MB)")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to delete old buffer dir: ${dir.name}", e)
                }
            }
            
            // Clean from external files dir
            context.getExternalFilesDir("flashback_buffer")?.listFiles()?.filter {
                it.name.startsWith("dvr_buffer_") || it.name.startsWith("segment_")
            }?.forEach { file ->
                try {
                    if (file.isDirectory) {
                        file.deleteRecursively()
                    } else {
                        file.delete()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to delete old buffer file: ${file.name}", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cleanup old buffer directories", e)
        }
    }
    
    /**
     * Get storage status info for Flutter UI.
     */
    fun getStorageStatus(): Map<String, Any> {
        val availableSpace = getAvailableFreeSpace()
        val totalSpace = getTotalStorageSpace()
        val storageMode = getCurrentStorageMode()
        
        return mapOf(
            "availableBytes" to availableSpace,
            "totalBytes" to totalSpace,
            "availableMB" to (availableSpace / 1024 / 1024),
            "totalMB" to (totalSpace / 1024 / 1024),
            "storageMode" to storageMode.name.lowercase(),
            "isLowStorage" to (storageMode == StorageMode.LOW),
            "lowStorageThresholdMB" to (LOW_STORAGE_THRESHOLD / 1024 / 1024)
        )
    }
}

// Data class to hold encoded samples in the buffer
data class EncodedSample(
    val data: ByteArray,
    val info: MediaCodec.BufferInfo,
    val isVideo: Boolean,
    val globalPtsUs: Long
) {
    // Create a copy of BufferInfo to avoid reference issues
    fun getBufferInfoCopy(): MediaCodec.BufferInfo {
        val copy = MediaCodec.BufferInfo()
        copy.set(info.offset, info.size, globalPtsUs, info.flags)
        return copy
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as EncodedSample
        return data.contentEquals(other.data) && isVideo == other.isVideo
    }
    
    override fun hashCode(): Int {
        var result = data.contentHashCode()
        result = 31 * result + isVideo.hashCode()
        return result
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DISK-BASED ROLLING BUFFER - Writes segments to disk to avoid RAM exhaustion
// At 4K 60fps with 30s buffer, RAM-based storage causes OOM crashes.
// This implementation writes encoded samples to temporary segment files on disk.
// ═══════════════════════════════════════════════════════════════════════════════
class RollingMediaBuffer(private var maxDurationUs: Long) {
    private val TAG = "RollingMediaBuffer"
    
    // In-memory index of samples (metadata only, data is on disk)
    private data class SampleIndex(
        val globalPtsUs: Long,
        val isVideo: Boolean,
        val flags: Int,
        val size: Int,
        val segmentId: Int,
        val offsetInSegment: Long
    )
    
    // Segment file management
    private data class Segment(
        val id: Int,
        val file: File,
        var size: Long = 0,
        var sampleCount: Int = 0,
        val startPtsUs: Long
    )
    
    private val sampleIndex = LinkedList<SampleIndex>()
    private val segments = mutableListOf<Segment>()
    private var currentSegment: Segment? = null
    private var currentSegmentStream: java.io.RandomAccessFile? = null
    private var segmentCounter = 0
    private var bufferDir: File? = null
    
    // Configuration
    private val MAX_SEGMENT_SIZE = 10 * 1024 * 1024L // 10 MB per segment
    private val MAX_SEGMENT_DURATION_US = 2_000_000L // 2 seconds per segment
    private var currentSegmentStartPts = 0L
    
    // RAM fallback for very short buffers (< 3 seconds) on high-RAM devices
    private var useRamBuffer = false
    private val ramSamples = LinkedList<EncodedSample>()
    private val RAM_BUFFER_THRESHOLD_SECONDS = 3
    
    // Storage failure callback
    private var storageFullCallback: (() -> Unit)? = null
    private var lastStorageError: String? = null
    private var storageManager: StorageManager? = null
    
    /**
     * Set callback for storage full errors during buffer writes.
     */
    fun setStorageFullCallback(callback: (() -> Unit)?) {
        storageFullCallback = callback
    }
    
    /**
     * Get last storage error message, if any.
     */
    fun getLastStorageError(): String? = lastStorageError
    
    /**
     * Clear the last storage error.
     */
    fun clearStorageError() {
        lastStorageError = null
    }
    
    fun initialize(context: android.content.Context, useRam: Boolean = false, manager: StorageManager? = null) {
        storageManager = manager
        useRamBuffer = useRam
        lastStorageError = null
        
        if (!useRamBuffer) {
            // Clean up any old buffer directories first using StorageManager if available
            if (manager != null) {
                manager.cleanupOldBufferDirectories()
                bufferDir = File(manager.getBufferDirectory(), "dvr_buffer_${System.currentTimeMillis()}")
            } else {
                // Fallback: clean up manually
                try {
                    context.cacheDir.listFiles()?.filter { it.name.startsWith("dvr_buffer_") }?.forEach { 
                        it.deleteRecursively() 
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to clean old buffer dirs", e)
                }
                bufferDir = File(context.cacheDir, "dvr_buffer_${System.currentTimeMillis()}")
            }
            
            val created = bufferDir?.mkdirs() ?: false
            Log.d(TAG, "Initialized disk-based buffer at: ${bufferDir?.absolutePath}, created=$created")
            
            if (!created && bufferDir?.exists() != true) {
                Log.e(TAG, "Failed to create buffer directory, falling back to RAM")
                useRamBuffer = true
            }
        } else {
            Log.d(TAG, "Initialized RAM-based buffer (short duration or high-RAM device)")
        }
    }
    
    private var isInitialized = false
    
    // Track consecutive storage failures for detecting storage full condition
    private var consecutiveWriteFailures = 0
    private val MAX_CONSECUTIVE_FAILURES = 5
    
    @Synchronized
    fun addSample(sample: EncodedSample): Boolean {
        if (useRamBuffer) {
            addSampleToRam(sample)
            return true
        }
        
        // Check if buffer directory exists
        if (bufferDir == null || bufferDir?.exists() != true) {
            Log.w(TAG, "Buffer directory not available, using RAM fallback")
            ramSamples.offer(sample)
            while (ramSamples.size > 500) ramSamples.poll() // Keep limited fallback
            return true
        }
        
        try {
            // Create new segment if needed
            if (shouldCreateNewSegment(sample.globalPtsUs)) {
                createNewSegment(sample.globalPtsUs)
            }
            
            val segment = currentSegment
            val stream = currentSegmentStream
            
            if (segment == null || stream == null) {
                Log.w(TAG, "No current segment available, sample dropped")
                return false
            }
            
            // Write sample data to disk
            val offset = segment.size
            stream.seek(offset)
            stream.write(sample.data)
            
            // Add to index (metadata only)
            val indexEntry = SampleIndex(
                globalPtsUs = sample.globalPtsUs,
                isVideo = sample.isVideo,
                flags = sample.info.flags,
                size = sample.data.size,
                segmentId = segment.id,
                offsetInSegment = offset
            )
            sampleIndex.offer(indexEntry)
            
            // Update segment stats
            segment.size += sample.data.size
            segment.sampleCount++
            
            // Mark as initialized after first successful write
            if (!isInitialized) {
                isInitialized = true
                Log.d(TAG, "First sample written to disk successfully")
            }
            
            // Reset failure counter on success
            consecutiveWriteFailures = 0
            
            // Trim old samples/segments to maintain time window
            trimOldData()
            
            return true
            
        } catch (e: IOException) {
            consecutiveWriteFailures++
            Log.e(TAG, "Failed to write sample to disk (failure $consecutiveWriteFailures/$MAX_CONSECUTIVE_FAILURES)", e)
            
            // Check if this is a storage full condition
            val isStorageFull = e.message?.contains("No space left", ignoreCase = true) == true ||
                    e.message?.contains("ENOSPC", ignoreCase = true) == true ||
                    consecutiveWriteFailures >= MAX_CONSECUTIVE_FAILURES
            
            if (isStorageFull) {
                lastStorageError = "Storage is full. Recording stopped to prevent data corruption."
                Log.e(TAG, "Storage full detected! Triggering callback.")
                storageFullCallback?.invoke()
                return false
            }
            
            // Non-fatal failure: fall back to RAM buffer temporarily
            ramSamples.offer(sample)
            while (ramSamples.size > 100) {
                ramSamples.poll()
            }
            return true
            
        } catch (e: Exception) {
            consecutiveWriteFailures++
            Log.e(TAG, "Failed to write sample to disk (failure $consecutiveWriteFailures)", e)
            
            // Fallback: add to RAM buffer
            ramSamples.offer(sample)
            while (ramSamples.size > 100) { // Keep limited RAM samples as emergency fallback
                ramSamples.poll()
            }
            return true
        }
    }
    
    private fun addSampleToRam(sample: EncodedSample) {
        ramSamples.offer(sample)
        
        // Trim old samples to maintain time window
        while (ramSamples.size > 1) {
            val oldestPts = ramSamples.first.globalPtsUs
            val newestPts = ramSamples.last.globalPtsUs
            val durationUs = newestPts - oldestPts
            
            if (durationUs > maxDurationUs) {
                ramSamples.poll()
            } else {
                break
            }
        }
    }
    
    private fun shouldCreateNewSegment(ptsUs: Long): Boolean {
        val segment = currentSegment ?: return true
        
        // Create new segment if current one is too large or too old
        if (segment.size >= MAX_SEGMENT_SIZE) return true
        if (ptsUs - currentSegmentStartPts >= MAX_SEGMENT_DURATION_US) return true
        
        return false
    }
    
    private fun createNewSegment(startPtsUs: Long) {
        // Close current segment
        try {
            currentSegmentStream?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing segment stream", e)
        }
        
        // Create new segment file
        val segmentId = segmentCounter++
        val segmentFile = File(bufferDir, "segment_$segmentId.bin")
        
        try {
            currentSegmentStream = java.io.RandomAccessFile(segmentFile, "rw")
            val newSegment = Segment(
                id = segmentId,
                file = segmentFile,
                startPtsUs = startPtsUs
            )
            segments.add(newSegment)
            currentSegment = newSegment
            currentSegmentStartPts = startPtsUs
            
            Log.d(TAG, "Created new segment $segmentId at ${segmentFile.name}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create segment file", e)
        }
    }
    
    private fun trimOldData() {
        if (sampleIndex.size < 2) return
        
        val oldestPts = sampleIndex.first.globalPtsUs
        val newestPts = sampleIndex.last.globalPtsUs
        val durationUs = newestPts - oldestPts
        
        if (durationUs <= maxDurationUs) return
        
        // Remove old samples from index
        val samplesToRemove = mutableListOf<SampleIndex>()
        val segmentsToRemove = mutableSetOf<Int>()
        
        for (sample in sampleIndex) {
            if (newestPts - sample.globalPtsUs > maxDurationUs) {
                samplesToRemove.add(sample)
                segmentsToRemove.add(sample.segmentId)
            } else {
                break // Index is sorted by time
            }
        }
        
        // Remove samples from index
        sampleIndex.removeAll(samplesToRemove.toSet())
        
        // Check which segments are completely empty and can be deleted
        val usedSegmentIds = sampleIndex.map { it.segmentId }.toSet()
        val segmentsToDelete = segments.filter { it.id !in usedSegmentIds && it.id != currentSegment?.id }
        
        for (segment in segmentsToDelete) {
            try {
                segment.file.delete()
                Log.d(TAG, "Deleted old segment ${segment.id}")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to delete segment ${segment.id}", e)
            }
        }
        segments.removeAll(segmentsToDelete.toSet())
    }
    
    @Synchronized
    fun getSnapshot(): List<EncodedSample> {
        Log.d(TAG, "getSnapshot called: useRamBuffer=$useRamBuffer, sampleIndex.size=${sampleIndex.size}, ramSamples.size=${ramSamples.size}")
        
        if (useRamBuffer) {
            return ramSamples.toList()
        }
        
        // If disk buffer is empty but we have RAM fallback samples, use those
        if (sampleIndex.isEmpty() && ramSamples.isNotEmpty()) {
            Log.d(TAG, "Using RAM fallback samples: ${ramSamples.size}")
            return ramSamples.toList()
        }
        
        // Flush current segment to ensure all data is written
        try {
            currentSegmentStream?.fd?.sync()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to sync current segment", e)
        }
        
        // Read samples from disk
        val result = mutableListOf<EncodedSample>()
        val segmentStreams = mutableMapOf<Int, java.io.RandomAccessFile>()
        
        try {
            // Make a copy of the index to avoid concurrent modification
            val indexCopy = sampleIndex.toList()
            Log.d(TAG, "Reading ${indexCopy.size} samples from ${segments.size} segments")
            
            for (indexEntry in indexCopy) {
                try {
                    // Get or open stream for this segment
                    val stream = segmentStreams.getOrPut(indexEntry.segmentId) {
                        val segment = segments.find { it.id == indexEntry.segmentId }
                        if (segment == null) {
                            Log.w(TAG, "Segment ${indexEntry.segmentId} not found in segments list")
                            throw Exception("Segment ${indexEntry.segmentId} not found")
                        }
                        if (!segment.file.exists()) {
                            Log.w(TAG, "Segment file does not exist: ${segment.file.absolutePath}")
                            throw Exception("Segment file ${indexEntry.segmentId} does not exist")
                        }
                        java.io.RandomAccessFile(segment.file, "r")
                    }
                    
                    // Read sample data
                    stream.seek(indexEntry.offsetInSegment)
                    val data = ByteArray(indexEntry.size)
                    stream.readFully(data)
                    
                    // Reconstruct BufferInfo
                    val bufferInfo = MediaCodec.BufferInfo()
                    bufferInfo.set(0, indexEntry.size, indexEntry.globalPtsUs, indexEntry.flags)
                    
                    result.add(EncodedSample(data, bufferInfo, indexEntry.isVideo, indexEntry.globalPtsUs))
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to read sample at offset ${indexEntry.offsetInSegment} from segment ${indexEntry.segmentId}", e)
                    // Continue with next sample instead of failing completely
                }
            }
            
            Log.d(TAG, "Successfully read ${result.size} samples from disk")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error reading snapshot from disk", e)
        } finally {
            // Close all opened streams
            segmentStreams.forEach { (_, stream) ->
                try { stream.close() } catch (_: Exception) {}
            }
        }
        
        // If we couldn't read from disk, fall back to RAM samples
        if (result.isEmpty() && ramSamples.isNotEmpty()) {
            Log.w(TAG, "Disk read failed, using ${ramSamples.size} RAM fallback samples")
            return ramSamples.toList()
        }
        
        return result
    }
    
    @Synchronized
    fun clear() {
        // Clear RAM buffer
        ramSamples.clear()
        
        // Clear index
        sampleIndex.clear()
        
        // Close current stream
        try {
            currentSegmentStream?.close()
        } catch (_: Exception) {}
        currentSegmentStream = null
        currentSegment = null
        
        // Delete all segment files
        for (segment in segments) {
            try {
                segment.file.delete()
            } catch (_: Exception) {}
        }
        segments.clear()
        segmentCounter = 0
        
        // Delete buffer directory and all contents
        try {
            bufferDir?.let { dir ->
                if (dir.exists()) {
                    dir.listFiles()?.forEach { file ->
                        try {
                            if (file.isDirectory) {
                                file.deleteRecursively()
                            } else {
                                file.delete()
                            }
                        } catch (_: Exception) {}
                    }
                    // Also delete the buffer directory itself
                    dir.delete()
                }
            }
        } catch (_: Exception) {}
        bufferDir = null
        
        // Reset state
        isInitialized = false
        consecutiveWriteFailures = 0
        lastStorageError = null
        
        Log.d(TAG, "Buffer cleared and directory removed, ready for reinitialization")
    }
    
    /**
     * Cleanup buffer files without clearing in-memory state.
     * Used when stopping buffer or app closes.
     */
    @Synchronized
    fun cleanup() {
        Log.d(TAG, "Cleanup called - deleting all buffer files")
        
        // Close current stream
        try {
            currentSegmentStream?.close()
        } catch (_: Exception) {}
        currentSegmentStream = null
        
        // Delete all segment files and buffer directory
        try {
            bufferDir?.let { dir ->
                if (dir.exists()) {
                    var deletedSize = 0L
                    dir.listFiles()?.forEach { file ->
                        deletedSize += file.length()
                        try {
                            if (file.isDirectory) {
                                file.deleteRecursively()
                            } else {
                                file.delete()
                            }
                        } catch (_: Exception) {}
                    }
                    dir.delete()
                    Log.d(TAG, "Deleted buffer directory (${deletedSize / 1024}KB freed)")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error during cleanup", e)
        }
        
        // Clear in-memory state
        ramSamples.clear()
        sampleIndex.clear()
        segments.clear()
        currentSegment = null
        segmentCounter = 0
        bufferDir = null
        isInitialized = false
        consecutiveWriteFailures = 0
    }
    
    @Synchronized
    fun getSampleCount(): Int = if (useRamBuffer) ramSamples.size else sampleIndex.size
    
    @Synchronized
    fun getDurationSeconds(): Double {
        if (useRamBuffer) {
            if (ramSamples.size < 2) return 0.0
            val oldestPts = ramSamples.first.globalPtsUs
            val newestPts = ramSamples.last.globalPtsUs
            return (newestPts - oldestPts) / 1_000_000.0
        }
        
        if (sampleIndex.size < 2) return 0.0
        val oldestPts = sampleIndex.first.globalPtsUs
        val newestPts = sampleIndex.last.globalPtsUs
        return (newestPts - oldestPts) / 1_000_000.0
    }
    
    /**
     * Get the PTS of the oldest sample in the buffer.
     * This is the actual start of the buffered content.
     */
    @Synchronized
    fun getOldestSamplePts(): Long {
        if (useRamBuffer) {
            return ramSamples.firstOrNull()?.globalPtsUs ?: -1L
        }
        return sampleIndex.firstOrNull()?.globalPtsUs ?: -1L
    }
    
    /**
     * Get the PTS of the newest sample in the buffer.
     * This is the current end of the buffered content.
     */
    @Synchronized
    fun getNewestSamplePts(): Long {
        if (useRamBuffer) {
            return ramSamples.lastOrNull()?.globalPtsUs ?: -1L
        }
        return sampleIndex.lastOrNull()?.globalPtsUs ?: -1L
    }
    
    @Synchronized
    fun getVideoSampleCount(): Int = if (useRamBuffer) ramSamples.count { it.isVideo } else sampleIndex.count { it.isVideo }
    
    @Synchronized
    fun getAudioSampleCount(): Int = if (useRamBuffer) ramSamples.count { !it.isVideo } else sampleIndex.count { !it.isVideo }
    
    @Synchronized
    fun updateMaxDuration(newMaxDurationUs: Long) {
        maxDurationUs = newMaxDurationUs
        trimOldData()
    }
    
    @Synchronized
    fun getMemoryUsageBytes(): Long {
        if (useRamBuffer) {
            return ramSamples.sumOf { it.data.size.toLong() }
        }
        return 0L // Disk buffer doesn't use RAM for sample data
    }
    
    @Synchronized
    fun getDiskUsageBytes(): Long {
        if (useRamBuffer) return 0L
        return segments.sumOf { it.size }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // STREAMING EXPORT API - Process samples without loading all into RAM
    // This is critical for 4K 60fps where loading 170MB+ into RAM causes OOM
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * Get sample metadata for filtering/planning without loading sample data
     */
    data class SampleMetadata(
        val globalPtsUs: Long,
        val isVideo: Boolean,
        val flags: Int,
        val size: Int,
        val index: Int // Position in sample list for later retrieval
    )
    
    @Synchronized
    fun getSampleMetadataInRange(startPtsUs: Long, endPtsUs: Long): List<SampleMetadata> {
        if (useRamBuffer) {
            return ramSamples.mapIndexedNotNull { index, sample ->
                if (sample.globalPtsUs in startPtsUs..endPtsUs) {
                    SampleMetadata(sample.globalPtsUs, sample.isVideo, sample.info.flags, sample.data.size, index)
                } else null
            }
        }
        
        return sampleIndex.mapIndexedNotNull { index, entry ->
            if (entry.globalPtsUs in startPtsUs..endPtsUs) {
                SampleMetadata(entry.globalPtsUs, entry.isVideo, entry.flags, entry.size, index)
            } else null
        }
    }
    
    /**
     * Stream samples in batches to a processor function.
     * This avoids loading all samples into RAM at once.
     */
    fun streamSamplesInRange(
        startPtsUs: Long,
        endPtsUs: Long,
        batchSize: Int = 50,
        processor: (List<EncodedSample>) -> Unit
    ) {
        Log.d(TAG, "streamSamplesInRange: start=$startPtsUs, end=$endPtsUs, batchSize=$batchSize")
        
        if (useRamBuffer) {
            // Stream from RAM in batches
            val relevantSamples = ramSamples.filter { it.globalPtsUs in startPtsUs..endPtsUs }
            relevantSamples.chunked(batchSize).forEach { batch ->
                processor(batch)
            }
            return
        }
        
        // Stream from disk in batches
        synchronized(this) {
            // Flush current segment
            try {
                currentSegmentStream?.fd?.sync()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to sync current segment", e)
            }
        }
        
        // Get relevant sample indices
        val relevantIndices = synchronized(this) {
            sampleIndex.filter { it.globalPtsUs in startPtsUs..endPtsUs }.toList()
        }
        
        Log.d(TAG, "Found ${relevantIndices.size} samples in range, streaming in batches of $batchSize")
        
        // Open segment files as needed
        val segmentStreams = mutableMapOf<Int, java.io.RandomAccessFile>()
        
        try {
            // Process in batches
            relevantIndices.chunked(batchSize).forEach { batchIndices ->
                val batch = mutableListOf<EncodedSample>()
                
                for (indexEntry in batchIndices) {
                    try {
                        val stream = synchronized(this) {
                            segmentStreams.getOrPut(indexEntry.segmentId) {
                                val segment = segments.find { it.id == indexEntry.segmentId }
                                if (segment != null && segment.file.exists()) {
                                    java.io.RandomAccessFile(segment.file, "r")
                                } else {
                                    throw Exception("Segment ${indexEntry.segmentId} not found")
                                }
                            }
                        }
                        
                        stream.seek(indexEntry.offsetInSegment)
                        val data = ByteArray(indexEntry.size)
                        stream.readFully(data)
                        
                        val bufferInfo = MediaCodec.BufferInfo()
                        bufferInfo.set(0, indexEntry.size, indexEntry.globalPtsUs, indexEntry.flags)
                        
                        batch.add(EncodedSample(data, bufferInfo, indexEntry.isVideo, indexEntry.globalPtsUs))
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to read sample", e)
                    }
                }
                
                if (batch.isNotEmpty()) {
                    processor(batch)
                }
                
                // Clear batch to allow GC
                batch.clear()
            }
        } finally {
            // Close all segment streams
            segmentStreams.values.forEach { stream ->
                try { stream.close() } catch (_: Exception) {}
            }
        }
        
        Log.d(TAG, "Streaming complete")
    }
    
    /**
     * Get total sample count in range (for progress calculation)
     */
    @Synchronized
    fun getSampleCountInRange(startPtsUs: Long, endPtsUs: Long): Int {
        return if (useRamBuffer) {
            ramSamples.count { it.globalPtsUs in startPtsUs..endPtsUs }
        } else {
            sampleIndex.count { it.globalPtsUs in startPtsUs..endPtsUs }
        }
    }
    
    /**
     * Get video sample count in range
     */
    @Synchronized
    fun getVideoSampleCountInRange(startPtsUs: Long, endPtsUs: Long): Int {
        return if (useRamBuffer) {
            ramSamples.count { it.isVideo && it.globalPtsUs in startPtsUs..endPtsUs }
        } else {
            sampleIndex.count { it.isVideo && it.globalPtsUs in startPtsUs..endPtsUs }
        }
    }
    
    /**
     * Get first video sample with SYNC flag (keyframe) for CSD extraction
     */
    fun getFirstKeyframeSample(startPtsUs: Long, endPtsUs: Long): EncodedSample? {
        if (useRamBuffer) {
            return ramSamples.firstOrNull { 
                it.isVideo && 
                it.globalPtsUs in startPtsUs..endPtsUs && 
                (it.info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0 
            }
        }
        
        synchronized(this) {
            val keyframeIndex = sampleIndex.firstOrNull {
                it.isVideo &&
                it.globalPtsUs in startPtsUs..endPtsUs &&
                (it.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0
            } ?: return null
            
            // Read this single sample from disk
            val segment = segments.find { it.id == keyframeIndex.segmentId } ?: return null
            if (!segment.file.exists()) return null
            
            return try {
                java.io.RandomAccessFile(segment.file, "r").use { stream ->
                    stream.seek(keyframeIndex.offsetInSegment)
                    val data = ByteArray(keyframeIndex.size)
                    stream.readFully(data)
                    
                    val bufferInfo = MediaCodec.BufferInfo()
                    bufferInfo.set(0, keyframeIndex.size, keyframeIndex.globalPtsUs, keyframeIndex.flags)
                    
                    EncodedSample(data, bufferInfo, true, keyframeIndex.globalPtsUs)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to read keyframe sample", e)
                null
            }
        }
    }
}

class CameraPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val TAG = "CameraPlugin"
    
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var context: Context
    private lateinit var textureRegistry: TextureRegistry
    
    // Camera components
    private var cameraManager: CameraManager? = null
    private var cameraCharacteristics: CameraCharacteristics? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private val cameraOpenCloseLock = Semaphore(1)
    
    // Recording components
    private var mediaRecorder: MediaRecorder? = null
    private var previewRequestBuilder: CaptureRequest.Builder? = null
    private var previewRequest: CaptureRequest? = null
    private var isRecording = false
    private var isBuffering = false
    
    // Preview components
    private var previewSize = Size(1920, 1080) // Will be updated based on resolution
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSurface: Surface? = null
    private var activeFpsRange: Range<Int>? = null
    
    // Continuous Pre-roll Buffer System with MediaCodec
    // ═══════════════════════════════════════════════════════════════════════
    // SYNCHRONIZATION STRATEGY:
    // - Video and audio encoders are created during buffer initialization
    // - Both encoders are configured but NOT started during initialization
    // - Both encoders start TOGETHER when camera session is configured
    // - This ensures frame-accurate A/V sync across ALL resolutions and FPS
    // - Timestamps are captured using nowUs() for consistent timing
    // - Works with any resolution (720P, 1080P, 4K), any FPS (30, 60, etc.)
    // - Works with zoom enabled/disabled - sync is maintained
    // ═══════════════════════════════════════════════════════════════════════
    private var videoEncoder: MediaCodec? = null
    private var audioEncoder: MediaCodec? = null
    private var audioRecord: AudioRecord? = null
    private var videoEncoderSurface: Surface? = null
    private val rollingBuffer = RollingMediaBuffer(5_000_000L) // 5 seconds in microseconds (default)
    private var encoderThread: HandlerThread? = null
    private var encoderHandler: Handler? = null
    private var audioThread: HandlerThread? = null
    private var audioHandler: Handler? = null
    private var bufferLoggingTimer: Timer? = null
    private var selectedBufferSeconds = 5 // User-selected buffer duration (default 5s)
    private var isAudioCapturing = false
    private var activeCaptureProfile: CaptureProfile? = null
    
    // Storage management for low-storage handling
    private var storageManager: StorageManager? = null
    private var currentStorageMode: StorageMode = StorageMode.NORMAL
    
    // Device orientation at recording time (for video metadata only, not preview)
    private var recordingOrientation: Int = 0
    
    // Track formats for muxing later
    private var videoFormat: MediaFormat? = null
    private var audioFormat: MediaFormat? = null
    
    // DVR-style recording - O(1) record press, background export on stop
    // Recording only marks timestamps, export happens in background thread after stop
    private var recordingStartGlobalPtsUs: Long = -1  // Global PTS when record was pressed
    private var recordingStopGlobalPtsUs: Long = -1   // Global PTS when record was stopped
    private var recordingMarkTimestamp: Long = 0      // System time when record was pressed
    private var frozenPreRollStartPts: Long = -1      // Pre-roll start PTS, frozen when Record pressed
    private var currentOutputFile: File? = null
    private var exportThread: Thread? = null          // Background thread for export
    private var isExporting = false                   // Export in progress flag
    private var maxRecordingDurationMs: Long = 0      // Max recording duration, auto-stops when reached
    private var recordingAutoStopTimer: Timer? = null // Timer for auto-stop
    
    // Legacy fields kept for compatibility during transition
    private var recordingMuxer: MediaMuxer? = null
    private var recordingVideoTrack: Int = -1
    private var recordingAudioTrack: Int = -1
    private var prerollWritten = false
    private var recordingBasePtsUs: Long = -1
    private var recordingStartTimeUs: Long = -1
    private var lastPrerollVideoPts: Long = -1
    private var lastPrerollAudioPts: Long = -1
    private var liveVideoSampleCount: Int = 0
    private var liveAudioSampleCount: Int = 0
    
    // CRITICAL: FPS-dependent timing constants
    private var videoDeltaUs: Long = 33333L // Microseconds per frame (default 30fps, updated based on currentFps)
    private val audioDeltaUs: Long = 23220L // Microseconds per audio frame (constant for 44.1kHz AAC)
    
    // Settings and state
    private var isProUser = false
    private var bufferDurationMs: Long = 5000
    private var isBufferInitialized = false
    private var currentRamTier: String = "mid"
    private var currentBufferMode: String = "ram"
    private var usingFallbackVideoProfile: Boolean = false
    private var activeVideoEncoderSettings: VideoEncoderSettings? = null
    private val minValidFileBytes: Long = 50L * 1024L
    
    // Legacy buffer management (keeping for UI indicators)
    private var bufferImageReader: ImageReader? = null
    private val bufferFrames = LinkedList<ByteArray>()
    private val maxBufferFrames = 30 // For UI indicators
    private var bufferSeconds = 0
    private val bufferTimer = Timer()
    private var bufferUpdateTask: TimerTask? = null

    private fun nowUs(): Long = System.nanoTime() / 1000
    
    /**
     * Updates videoDeltaUs based on currentFps.
     * CRITICAL for proper video timing at different frame rates.
     * Must be called whenever currentFps changes.
     */
    private fun updateVideoDelta() {
        val fps = if (currentFps > 0) currentFps else 30
        videoDeltaUs = 1_000_000L / fps.toLong()
        Log.d(TAG, "🎬 Video delta updated: ${videoDeltaUs}µs per frame (${fps} fps)")
    }
    
    // Settings
    private var currentResolution = "1080P"
    private var currentFps = 30
    private var currentCodec = "H.264"
    private var preRollSeconds = 3
    private var stabilizationEnabled = true
    private var flashMode = "off"
    private var cameraFacing = CameraCharacteristics.LENS_FACING_BACK
    
    // Helper to check if front camera is active
    private fun isFrontCamera(): Boolean = cameraFacing == CameraCharacteristics.LENS_FACING_FRONT
    
    // Zoom
    private var currentZoomLevel = 1.0f
    private var maxZoom = 1.0f
    private var minZoom = 1.0f
    
    // Focus
    private var isFocusLocked = false
    private var focusPointX = 0.5f  // Normalized 0-1, center by default
    private var focusPointY = 0.5f  // Normalized 0-1, center by default
    
    // Session generation counter - prevents stale onConfigured callbacks from crashing
    // Incremented each time we start creating a new session; callbacks check this to avoid races
    @Volatile private var sessionGeneration: Int = 0
    
    // Current recording info
    private var currentRecordingId: String? = null
    private var recordingStartTime: Long = 0
    private var liveRecordingFile: File? = null
    private var pendingBufferFile: File? = null // Temporary file holding buffered samples

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        textureRegistry = flutterPluginBinding.textureRegistry
        
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flashback_cam/camera")
        channel.setMethodCallHandler(this)
        
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flashback_cam/camera_events")
        eventChannel.setStreamHandler(this)
        
        cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        
        // Initialize storage manager for low-storage handling
        storageManager = StorageManager(context)
        currentStorageMode = storageManager!!.getCurrentStorageMode()
        
        // Clean up any old buffer files from previous sessions
        storageManager?.cleanupOldBufferDirectories()
        
        // Initialize disk-based rolling buffer with context and storage manager
        // This allows the buffer to use the app's cache directory for segment storage
        rollingBuffer.initialize(context, useRam = false, manager = storageManager)
        
        // Set up storage full callback to handle write failures gracefully
        rollingBuffer.setStorageFullCallback {
            Handler(Looper.getMainLooper()).post {
                handleStorageFullDuringRecording()
            }
        }
        
        Log.d(TAG, "CameraPlugin attached, disk buffer initialized, storageMode=$currentStorageMode")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        dispose()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        Log.d(TAG, "Event sink connected")
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        Log.d(TAG, "Event sink disconnected")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "Method call received: ${call.method}")
        
        when (call.method) {
            "initialize" -> initialize(call, result)
            "createPreview" -> createPreview(result)
            "disposePreview" -> disposePreview(call, result)
            "startPreview" -> startPreview(result)
            "startBuffer" -> startBuffer(result)
            "stopBuffer" -> stopBuffer(result)
            "startRecording" -> startRecording(result)
            "stopRecording" -> stopRecording(result)
            "switchCamera" -> switchCamera(result)
            "setFlashMode" -> setFlashMode(call, result)
            "setZoom" -> setZoom(call, result)
            "getMaxZoom" -> getMaxZoom(result)
            "setFocusPoint" -> setFocusPoint(call, result)
            "lockFocus" -> lockFocus(call, result)
            "unlockFocus" -> unlockFocus(result)
            "isFocusLocked" -> result.success(isFocusLocked)
            "updateSettings" -> updateSettings(call, result)
            "updateSubscription" -> updateSubscription(call, result)
            "getDeviceCapabilities" -> getDeviceCapabilities(result)
            "checkDetailedCapabilities" -> checkDetailedCapabilities(result)
            "getDebugInfo" -> getDebugInfo(result)
            // Storage management methods
            "getStorageStatus" -> getStorageStatus(result)
            "checkBufferStorageSpace" -> checkBufferStorageSpace(call, result)
            "checkRecordingStorageSpace" -> checkRecordingStorageSpace(call, result)
            "getAdjustedSettingsForStorage" -> getAdjustedSettingsForStorage(call, result)
            "cleanupBufferFiles" -> cleanupBufferFiles(result)
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
    
    /**
     * Returns debug information about the DVR-style recording pipeline.
     * Useful for developers to diagnose issues with buffer and recording.
     */
    private fun getDebugInfo(result: MethodChannel.Result) {
        try {
            val bufferDuration = rollingBuffer.getDurationSeconds()
            val bufferSamples = rollingBuffer.getSampleCount()
            val videoSamples = rollingBuffer.getVideoSampleCount()
            val audioSamples = rollingBuffer.getAudioSampleCount()
            
            val debugInfo = hashMapOf<String, Any>(
                // Pipeline state
                "pipelineType" to "DVR-style (O(1) record press, background export)",
                "isBuffering" to isBuffering,
                "isBufferInitialized" to isBufferInitialized,
                "isRecording" to isRecording,
                "isExporting" to isExporting,
                
                // Buffer state
                "bufferDurationSeconds" to bufferDuration,
                "bufferSampleCount" to bufferSamples,
                "bufferVideoSamples" to videoSamples,
                "bufferAudioSamples" to audioSamples,
                "selectedBufferSeconds" to selectedBufferSeconds,
                
                // Recording state
                "recordingStartPtsUs" to recordingStartGlobalPtsUs,
                "recordingStopPtsUs" to recordingStopGlobalPtsUs,
                "currentRecordingId" to (currentRecordingId ?: "none"),
                
                // Encoder state
                "videoEncoderReady" to (videoEncoder != null),
                "audioEncoderReady" to (audioEncoder != null),
                "videoFormatReady" to (videoFormat != null),
                "audioFormatReady" to (audioFormat != null),
                
                // Settings
                "currentResolution" to currentResolution,
                "currentFps" to currentFps,
                "currentCodec" to currentCodec,
                "videoDeltaUs" to videoDeltaUs,
                
                // Device info
                "ramTier" to currentRamTier,
                "bufferMode" to currentBufferMode,
                "maxZoom" to maxZoom,
                
                // Storage info
                "storageMode" to currentStorageMode.name.lowercase()
            )
            
            result.success(debugInfo)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get debug info", e)
            result.success(hashMapOf<String, Any>())
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // STORAGE MANAGEMENT METHODS - Exposed to Flutter for low-storage handling
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /**
     * Get current storage status for Flutter UI.
     */
    private fun getStorageStatus(result: MethodChannel.Result) {
        try {
            val manager = storageManager
            if (manager == null) {
                result.error("STORAGE_ERROR", "Storage manager not initialized", null)
                return
            }
            
            val status = manager.getStorageStatus()
            currentStorageMode = manager.getCurrentStorageMode()
            result.success(status)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get storage status", e)
            result.error("STORAGE_ERROR", "Failed to get storage status: ${e.message}", null)
        }
    }
    
    /**
     * Check if there's enough storage space to start buffering.
     */
    private fun checkBufferStorageSpace(call: MethodCall, result: MethodChannel.Result) {
        try {
            val manager = storageManager
            if (manager == null) {
                result.error("STORAGE_ERROR", "Storage manager not initialized", null)
                return
            }
            
            val resolution = call.argument<String>("resolution") ?: currentResolution
            val fps = call.argument<Int>("fps") ?: currentFps
            
            val checkResult = manager.checkBufferStartSpace(resolution, fps)
            currentStorageMode = checkResult.storageMode
            
            result.success(mapOf(
                "hasEnoughSpace" to checkResult.hasEnoughSpace,
                "availableBytes" to checkResult.availableBytes,
                "requiredBytes" to checkResult.requiredBytes,
                "availableMB" to (checkResult.availableBytes / 1024 / 1024),
                "requiredMB" to (checkResult.requiredBytes / 1024 / 1024),
                "storageMode" to checkResult.storageMode.name.lowercase(),
                "message" to (checkResult.message ?: "")
            ))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check buffer storage space", e)
            result.error("STORAGE_ERROR", "Failed to check storage: ${e.message}", null)
        }
    }
    
    /**
     * Check if there's enough storage space to start recording.
     */
    private fun checkRecordingStorageSpace(call: MethodCall, result: MethodChannel.Result) {
        try {
            val manager = storageManager
            if (manager == null) {
                result.error("STORAGE_ERROR", "Storage manager not initialized", null)
                return
            }
            
            val resolution = call.argument<String>("resolution") ?: currentResolution
            val fps = call.argument<Int>("fps") ?: currentFps
            val bufferDurationSeconds = call.argument<Int>("bufferDurationSeconds") ?: selectedBufferSeconds
            val expectedRecordingSeconds = call.argument<Int>("expectedRecordingSeconds") ?: 60 // Default 1 minute
            
            val checkResult = manager.checkRecordingStartSpace(
                resolution, fps, bufferDurationSeconds, expectedRecordingSeconds
            )
            currentStorageMode = checkResult.storageMode
            
            result.success(mapOf(
                "hasEnoughSpace" to checkResult.hasEnoughSpace,
                "availableBytes" to checkResult.availableBytes,
                "requiredBytes" to checkResult.requiredBytes,
                "availableMB" to (checkResult.availableBytes / 1024 / 1024),
                "requiredMB" to (checkResult.requiredBytes / 1024 / 1024),
                "storageMode" to checkResult.storageMode.name.lowercase(),
                "message" to (checkResult.message ?: "")
            ))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check recording storage space", e)
            result.error("STORAGE_ERROR", "Failed to check storage: ${e.message}", null)
        }
    }
    
    /**
     * Get adjusted settings for low storage mode.
     */
    private fun getAdjustedSettingsForStorage(call: MethodCall, result: MethodChannel.Result) {
        try {
            val manager = storageManager
            if (manager == null) {
                result.error("STORAGE_ERROR", "Storage manager not initialized", null)
                return
            }
            
            val resolution = call.argument<String>("resolution") ?: currentResolution
            val fps = call.argument<Int>("fps") ?: currentFps
            val bufferSeconds = call.argument<Int>("bufferSeconds") ?: selectedBufferSeconds
            
            val adjustedSettings = manager.getAdjustedSettingsForLowStorage(resolution, fps, bufferSeconds)
            currentStorageMode = if (adjustedSettings["adjusted"] == true) StorageMode.LOW else StorageMode.NORMAL
            
            result.success(adjustedSettings)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get adjusted settings", e)
            result.error("STORAGE_ERROR", "Failed to get adjusted settings: ${e.message}", null)
        }
    }
    
    /**
     * Manually cleanup buffer files. Called when stopping buffer or during maintenance.
     */
    private fun cleanupBufferFiles(result: MethodChannel.Result) {
        try {
            storageManager?.cleanupBufferFiles()
            storageManager?.cleanupOldBufferDirectories()
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cleanup buffer files", e)
            result.error("STORAGE_ERROR", "Failed to cleanup: ${e.message}", null)
        }
    }
    
    /**
     * Handle storage full condition detected during recording.
     * Gracefully stops recording and saves partial video.
     */
    private fun handleStorageFullDuringRecording() {
        Log.e(TAG, "═══════════════════════════════════════════════════════════")
        Log.e(TAG, "STORAGE FULL - Stopping recording gracefully")
        Log.e(TAG, "═══════════════════════════════════════════════════════════")
        
        if (isRecording) {
            // Mark stop timestamp
            recordingStopGlobalPtsUs = nowUs()
            val recordingDurationUs = recordingStopGlobalPtsUs - recordingStartGlobalPtsUs
            
            // Clear recording flag
            isRecording = false
            
            // Cancel auto-stop timer
            recordingAutoStopTimer?.cancel()
            recordingAutoStopTimer = null
            
            // Notify Flutter with error
            sendEvent("recordingError", mapOf(
                "code" to "STORAGE_FULL",
                "error" to "Recording stopped: storage is full. Your video has been saved up to this point."
            ))
            
            // Try to export what we have
            if (recordingDurationUs > 1_000_000L) { // At least 1 second recorded
                Log.d(TAG, "Attempting to save partial recording (${recordingDurationUs / 1_000_000.0}s)")
                startBackgroundExport()
            } else {
                Log.w(TAG, "Recording too short to save (${recordingDurationUs / 1_000_000.0}s)")
                sendEvent("recordingStopped", mapOf("id" to currentRecordingId))
            }
        }
        
        // Also stop buffering to prevent further disk writes
        if (isBuffering) {
            isBuffering = false
            isBufferInitialized = false
            shutdownContinuousBuffer()
            
            sendEvent("lowStorage", mapOf(
                "message" to "Buffer stopped due to low storage"
            ))
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        try {
            currentResolution = call.argument<String>("resolution") ?: "1080P"
            currentFps = call.argument<Int>("fps") ?: 30
            currentCodec = call.argument<String>("codec") ?: "H.264"
            preRollSeconds = call.argument<Int>("preRollSeconds") ?: 3
            stabilizationEnabled = call.argument<Boolean>("stabilization") ?: true

            // CRITICAL: Update video delta based on FPS
            updateVideoDelta()

            applyCaptureProfileFromCurrentState()
            updatePreviewDefaults()
            Log.d(TAG, "Initialized with resolution: $currentResolution, FPS: $currentFps, Preview size: ${previewSize.width}x${previewSize.height}, videoDeltaUs: ${videoDeltaUs}µs")
            
            startBackgroundThread()
            openCamera()
            
            // Don't return success immediately - let camera open first
            // The openCamera callback will handle session creation
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize camera", e)
            result.error("INIT_ERROR", "Failed to initialize camera: ${e.message}", null)
        }
    }

    private fun createPreview(result: MethodChannel.Result) {
        try {
            textureEntry = textureRegistry.createSurfaceTexture()
            val surfaceTexture = textureEntry!!.surfaceTexture()
            surfaceTexture.setDefaultBufferSize(previewSize.width, previewSize.height)
            previewSurface = Surface(surfaceTexture)
            
            Log.d(TAG, "Camera preview created with texture ID: ${textureEntry!!.id()}")
            result.success(textureEntry!!.id())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create preview", e)
            result.error("PREVIEW_ERROR", "Failed to create preview: ${e.message}", null)
        }
    }

    private fun startPreview(result: MethodChannel.Result) {
        try {
            // If preview session already exists, just update it
            if (captureSession != null) {
                updatePreview()
                Log.d(TAG, "Preview restarted (session exists)")
                result.success(null)
                return
            }
            
            // If camera device exists but no session, create one
            if (cameraDevice != null && previewSurface != null) {
                Log.d(TAG, "Creating preview session...")
                createCameraPreviewSession()
                
                // Wait a bit for session to configure
                backgroundHandler?.postDelayed({
                    if (captureSession != null) {
                        Log.d(TAG, "Preview started successfully")
                        result.success(null)
                    } else {
                        Log.w(TAG, "Preview session still not ready after wait")
                        result.success(null) // Don't fail, session will be ready soon
                    }
                }, 300)
            } else {
                Log.w(TAG, "Cannot start preview: camera=${cameraDevice != null}, surface=${previewSurface != null}")
                // Don't fail if camera is still opening, it will auto-start preview
                result.success(null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start preview", e)
            result.error("PREVIEW_ERROR", "Failed to start preview: ${e.message}", null)
        }
    }

    private fun createBufferPreviewSession() {
        try {
            val camera = cameraDevice ?: return
            val surfaces = mutableListOf<Surface>()
            
            // Add preview surface for display
            previewSurface?.let { 
                surfaces.add(it) 
                Log.d(TAG, "Added preview surface to buffer session")
            }
            
            // Add video encoder surface for continuous encoding
            videoEncoderSurface?.let {
                surfaces.add(it)
                Log.d(TAG, "Added video encoder surface to buffer session")
            }
            
            // Add buffer surface for UI indicators (legacy)
            bufferImageReader?.surface?.let { 
                surfaces.add(it)
                Log.d(TAG, "Added buffer surface to buffer session")
            }
            
            // Capture current generation to detect stale callbacks
            val myGeneration = ++sessionGeneration
            Log.d(TAG, "Creating buffer session (generation $myGeneration)")
            
            camera.createCaptureSession(surfaces, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    // Guard: skip if this callback is from an outdated session creation
                    if (myGeneration != sessionGeneration) {
                        Log.w(TAG, "Ignoring stale onConfigured callback (gen $myGeneration, current $sessionGeneration)")
                        try { session.close() } catch (_: Exception) {}
                        return
                    }
                    // Guard: skip if camera was closed
                    if (cameraDevice == null) {
                        Log.w(TAG, "Camera closed before session configured, aborting")
                        try { session.close() } catch (_: Exception) {}
                        return
                    }
                    
                    captureSession = session
                    
                    previewRequestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                    previewSurface?.let { previewRequestBuilder?.addTarget(it) }
                    videoEncoderSurface?.let {
                        previewRequestBuilder?.addTarget(it)
                        Log.d(TAG, "Added video encoder surface to preview request")
                    }
                    bufferImageReader?.surface?.let {
                        previewRequestBuilder?.addTarget(it)
                        Log.d(TAG, "Added buffer surface to preview request")
                    }

                    previewRequestBuilder?.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                    val fpsRange = activeFpsRange ?: Range(currentFps, currentFps)
                    previewRequestBuilder?.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange)
                    Log.d(TAG, "Set FPS range to: $fpsRange")
                    if (stabilizationEnabled) {
                        previewRequestBuilder?.set(
                            CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE,
                            CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_ON
                        )
                    }

                    // Apply current zoom level if not at default
                    if (currentZoomLevel > 1.0f) {
                        val characteristics = cameraCharacteristics
                        val sensorArraySize = characteristics?.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
                        if (sensorArraySize != null) {
                            val cropWidth = sensorArraySize.width() / currentZoomLevel
                            val cropHeight = sensorArraySize.height() / currentZoomLevel
                            val cropLeft = ((sensorArraySize.width() - cropWidth) / 2).toInt()
                            val cropTop = ((sensorArraySize.height() - cropHeight) / 2).toInt()
                            val cropRegion = android.graphics.Rect(
                                cropLeft,
                                cropTop,
                                (cropLeft + cropWidth).toInt(),
                                (cropTop + cropHeight).toInt()
                            )
                            previewRequestBuilder?.set(CaptureRequest.SCALER_CROP_REGION, cropRegion)
                            Log.d(TAG, "🔍 Applied zoom level $currentZoomLevel to buffer session, cropRegion=$cropRegion")
                        }
                    }

                    previewRequest = previewRequestBuilder?.build()
                    previewRequest?.let { req ->
                        try {
                            session.setRepeatingRequest(req, null, backgroundHandler)
                        } catch (e: IllegalStateException) {
                            // Session was closed between check and setRepeatingRequest (rare race)
                            Log.w(TAG, "Session closed before setRepeatingRequest: ${e.message}")
                            return
                        }
                    }
                    
                    // ⚠️ CRITICAL: Start BOTH video and audio encoders together AFTER session is configured!
                    // This ensures perfect A/V sync across all resolutions and FPS settings
                    val syncStartTimeUs = nowUs()
                    Log.d(TAG, "🎬 ═══ STARTING ENCODERS TOGETHER ═══")
                    Log.d(TAG, "🎬 Sync timestamp: ${syncStartTimeUs}µs (resolution: $currentResolution, fps: $currentFps)")
                    
                    // Start video encoder
                    if (videoEncoder != null && videoEncoderSurface != null) {
                        try {
                            val encoder = videoEncoder
                            if (encoder != null) {
                                try {
                                    encoder.start()
                                    encoderHandler?.post { drainVideoEncoderLoop() }
                                    Log.d(TAG, "🎬 ✅ Video encoder STARTED")
                                } catch (e: IllegalStateException) {
                                    // Encoder already started, just continue draining
                                    Log.d(TAG, "🎬 Video encoder already running, continuing")
                                    encoderHandler?.post { drainVideoEncoderLoop() }
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Failed to start video encoder", e)
                        }
                    }
                    
                    // Start audio encoder and recording simultaneously
                    if (audioEncoder != null && audioRecord != null) {
                        try {
                            // Start audio encoder
                            audioEncoder?.start()
                            Log.d(TAG, "🎬 ✅ Audio encoder STARTED")
                            
                            // Start audio recording
                            audioRecord?.startRecording()
                            val recordingState = audioRecord?.recordingState
                            Log.d(TAG, "🎬 ✅ AudioRecord started - state: $recordingState")
                            
                            if (recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                                isAudioCapturing = true
                                // Start feeding audio to encoder
                                audioHandler?.post { feedAudioToEncoder() }
                                // Start draining audio encoder output
                                encoderHandler?.post { drainAudioEncoderLoop() }
                                Log.d(TAG, "🎬 ✅ Audio feed and drain loops started")
                            } else {
                                Log.e(TAG, "❌ AudioRecord failed to start recording! State: $recordingState")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Failed to start audio encoder", e)
                        }
                    }
                    
                    Log.d(TAG, "🎬 ═══ ENCODERS STARTED - A/V SYNC LOCKED ═══")
                    
                    Log.d(TAG, "Buffer preview session started with continuous encoding")
                    sendEvent("previewStarted", null)
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(TAG, "Failed to configure buffer preview session")
                }
            }, backgroundHandler)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create buffer preview session", e)
        }
    }

    private fun disposePreview(call: MethodCall, result: MethodChannel.Result) {
        try {
            previewSurface?.release()
            previewSurface = null
            textureEntry?.release()
            textureEntry = null
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to dispose preview", e)
            result.error("DISPOSE_ERROR", "Failed to dispose preview: ${e.message}", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun openCamera() {
        try {
            val cameraId = getCameraId()
            updatePreviewDefaults()
            if (!cameraOpenCloseLock.tryAcquire(2500, TimeUnit.MILLISECONDS)) {
                throw RuntimeException("Time out waiting to lock camera opening.")
            }
            
            cameraManager?.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraOpenCloseLock.release()
                    cameraDevice = camera
                    
                    // Notify Flutter that camera hardware is ready
                    sendEvent("cameraOpened", null)
                    
                    // Only create session if preview surface already exists
                    // Otherwise wait for startPreview() to be called
                    if (previewSurface != null) {
                        if (isBuffering) {
                            createBufferPreviewSession()
                        } else {
                            createCameraPreviewSession()
                        }
                        Log.d(TAG, "Camera opened - preview session created immediately")
                    } else {
                        Log.d(TAG, "Camera opened - waiting for preview surface before creating session")
                    }
                }

                override fun onDisconnected(camera: CameraDevice) {
                    cameraOpenCloseLock.release()
                    camera.close()
                    cameraDevice = null
                    Log.w(TAG, "Camera disconnected")
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    cameraOpenCloseLock.release()
                    camera.close()
                    cameraDevice = null
                    Log.e(TAG, "Camera error: $error")
                }
            }, backgroundHandler)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open camera", e)
        }
    }

    private fun getCameraId(): String {
        val cameraManager = this.cameraManager ?: throw IllegalStateException("Camera manager not initialized")
        
        for (cameraId in cameraManager.cameraIdList) {
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
            if (facing == cameraFacing) {
                cameraCharacteristics = characteristics
                initializeZoomCapabilities(characteristics)
                return cameraId
            }
        }
        val fallbackId = cameraManager.cameraIdList[0]
        cameraCharacteristics = cameraManager.getCameraCharacteristics(fallbackId)
        initializeZoomCapabilities(cameraCharacteristics!!)
        return fallbackId
    }

    private fun updatePreviewDefaults() {
        previewSize = selectPreviewSize(currentResolution)
        activeFpsRange = selectFpsRange(currentFps)
        applyPreviewSizeToSurface()
        Log.d(TAG, "Preview defaults -> size: ${previewSize.width}x${previewSize.height}, fpsRange: $activeFpsRange")
    }

    private fun applyPreviewSizeToSurface() {
        try {
            textureEntry?.surfaceTexture()?.setDefaultBufferSize(previewSize.width, previewSize.height)
        } catch (_: Exception) {
            // Texture might not exist yet; safe to ignore.
        }
    }

    private fun selectPreviewSize(resolution: String): Size {
        val totalRamMb = getTotalRamMb()
        val isLowRamDevice = totalRamMb < 4096 // Devices with less than 4GB RAM
        
        // Use 720p preview for low-RAM devices to reduce GPU/memory pressure
        val defaultSize = if (isLowRamDevice) Size(1280, 720) else Size(1920, 1080)
        
        val map = cameraCharacteristics?.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?: return defaultSize
        val availableSizes = map.getOutputSizes(SurfaceTexture::class.java) ?: return defaultSize
        if (availableSizes.isEmpty()) return defaultSize
        val normalized = resolution.uppercase(Locale.US)
        
        // FRONT CAMERA: Always use 720p for preview (front cameras have lower quality sensors)
        if (isFrontCamera()) {
            Log.d(TAG, "📷 Front camera detected: forcing 720p preview")
            val targetSize = Size(1280, 720)
            val aspectRatio = targetSize.width.toFloat() / targetSize.height.toFloat()
            val ratioTolerance = 0.02f
            val ratioMatches = availableSizes.filter { size ->
                val ratio = size.width.toFloat() / size.height.toFloat()
                abs(ratio - aspectRatio) <= ratioTolerance
            }
            val filtered = if (ratioMatches.isNotEmpty()) ratioMatches else availableSizes.toList()
            val notBigger = filtered.filter { it.width <= targetSize.width && it.height <= targetSize.height }
            return when {
                notBigger.isNotEmpty() -> notBigger.maxByOrNull { it.width * it.height } ?: Size(1280, 720)
                else -> filtered.minByOrNull { abs((it.width * it.height) - (targetSize.width * targetSize.height)) }
                    ?: Size(1280, 720)
            }
        }
        
        // For low-RAM devices, cap preview at 720p regardless of recording resolution
        val targetSize = if (isLowRamDevice) {
            Size(1280, 720)
        } else {
            when (normalized) {
                "4K", "UHD" -> Size(3840, 2160)
                "720P" -> Size(1280, 720)
                else -> Size(1920, 1080)
            }
        }
        
        if (isLowRamDevice) {
            Log.d(TAG, "Low-RAM device (${totalRamMb}MB): Using 720p preview for better performance")
        }
        val aspectRatio = targetSize.width.toFloat() / targetSize.height.toFloat()
        val ratioTolerance = 0.02f
        val ratioMatches = availableSizes.filter { size ->
            val ratio = size.width.toFloat() / size.height.toFloat()
            abs(ratio - aspectRatio) <= ratioTolerance
        }
        val filtered = if (ratioMatches.isNotEmpty()) ratioMatches else availableSizes.toList()
        val notBigger = filtered.filter { it.width <= targetSize.width && it.height <= targetSize.height }
        return when {
            notBigger.isNotEmpty() -> notBigger.maxByOrNull { it.width * it.height } ?: defaultSize
            else -> filtered.minByOrNull { abs((it.width * it.height) - (targetSize.width * targetSize.height)) }
                ?: defaultSize
        }
    }

    private fun selectFpsRange(targetFps: Int): Range<Int> {
        val available = cameraCharacteristics?.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
        if (available.isNullOrEmpty()) {
            Log.w(TAG, "No FPS ranges available, using default [$targetFps, $targetFps]")
            return Range(targetFps, targetFps)
        }
        
        Log.d(TAG, "Available FPS ranges: ${available.joinToString { "[${it.lower}, ${it.upper}]" }}")
        
        // For 60fps, we need a range that has upper bound >= 60
        // Prefer fixed ranges [60,60] or ranges that allow 60fps like [30,60]
        if (targetFps == 60) {
            // First try to find [60, 60] fixed range
            val fixed60 = available.find { it.lower == 60 && it.upper == 60 }
            if (fixed60 != null) {
                Log.d(TAG, "Found fixed 60fps range: [${fixed60.lower}, ${fixed60.upper}]")
                return fixed60
            }
            
            // Next try any range where upper >= 60 (like [30, 60])
            val rangeWith60 = available.filter { it.upper >= 60 }
                .minByOrNull { it.upper - it.lower } // Prefer narrower ranges
            if (rangeWith60 != null) {
                Log.d(TAG, "Found range supporting 60fps: [${rangeWith60.lower}, ${rangeWith60.upper}]")
                return rangeWith60
            }
            
            Log.w(TAG, "No 60fps range found! Using best available range")
        }
        
        // For 30fps or fallback, find the best matching range
        val bestRange = available.minByOrNull { range ->
            val clamped = targetFps.coerceIn(range.lower, range.upper)
            val delta = abs(clamped - targetFps)
            (delta * 100) + (range.upper - range.lower)
        } ?: Range(targetFps, targetFps)
        
        Log.d(TAG, "Selected FPS range: [${bestRange.lower}, ${bestRange.upper}] for target $targetFps")
        return bestRange
    }

    private fun createCameraPreviewSession() {
        try {
            val camera = cameraDevice ?: return
            val surfaces = mutableListOf<Surface>()
            
            // Add preview surface
            previewSurface?.let { 
                surfaces.add(it)
                Log.d(TAG, "Added preview surface to session")
            }
            
            // Create buffer ImageReader (not needed since we use encoder)
            /*bufferImageReader = ImageReader.newInstance(
                previewSize.width, previewSize.height, 
                ImageFormat.YUV_420_888, maxBufferFrames
            )
            
            bufferImageReader?.setOnImageAvailableListener({ reader ->
                val image = reader.acquireLatestImage()
                image?.let { processBufferFrame(it) }
            }, backgroundHandler)
            
            bufferImageReader?.surface?.let { surfaces.add(it) }*/
            
            previewRequestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            surfaces.forEach { previewRequestBuilder?.addTarget(it) }
            
            // Capture current generation to detect stale callbacks
            val myGeneration = ++sessionGeneration
            Log.d(TAG, "Creating preview session (generation $myGeneration)")
            
            camera.createCaptureSession(surfaces, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    // Guard: skip if this callback is from an outdated session creation
                    if (myGeneration != sessionGeneration) {
                        Log.w(TAG, "Ignoring stale onConfigured callback (gen $myGeneration, current $sessionGeneration)")
                        try { session.close() } catch (_: Exception) {}
                        return
                    }
                    // Guard: skip if camera was closed
                    if (cameraDevice == null) {
                        Log.w(TAG, "Camera closed before session configured, aborting")
                        try { session.close() } catch (_: Exception) {}
                        return
                    }
                    
                    captureSession = session
                    updatePreview()
                    Log.d(TAG, "Capture session configured successfully with ${surfaces.size} surfaces (preview-only)")
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(TAG, "Failed to configure capture session")
                }
            }, backgroundHandler)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create camera preview session", e)
        }
    }

    private fun updatePreview() {
        try {
            val session = captureSession ?: return
            val builder = previewRequestBuilder ?: return
            
            // CRITICAL FIX: Ensure encoder surface stays in targets during preview updates
            if (isBuffering || isRecording) {
                videoEncoderSurface?.let { 
                    builder.addTarget(it)
                    Log.d(TAG, "updatePreview: Ensured video encoder surface is in targets for continuous encoding")
                }
            }
            
            // Auto focus
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            
            // Set FPS range for preview to match selected FPS
            val fpsRange = activeFpsRange ?: Range(currentFps, currentFps)
            builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange)
            Log.d(TAG, "Preview FPS range set to: $fpsRange")
            
            // Flash mode
            when (flashMode) {
                "on" -> builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH)
                "off" -> builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
            }
            
            // Image stabilization
            if (stabilizationEnabled) {
                builder.set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, 
                    CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_ON)
            }
            
            // Apply zoom if set
            if (currentZoomLevel > 1.0f) {
                val characteristics = cameraCharacteristics
                val sensorArraySize = characteristics?.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
                if (sensorArraySize != null) {
                    val cropWidth = sensorArraySize.width() / currentZoomLevel
                    val cropHeight = sensorArraySize.height() / currentZoomLevel
                    val cropLeft = ((sensorArraySize.width() - cropWidth) / 2).toInt()
                    val cropTop = ((sensorArraySize.height() - cropHeight) / 2).toInt()
                    
                    val cropRegion = android.graphics.Rect(
                        cropLeft,
                        cropTop,
                        (cropLeft + cropWidth).toInt(),
                        (cropTop + cropHeight).toInt()
                    )
                    builder.set(CaptureRequest.SCALER_CROP_REGION, cropRegion)
                }
            }
            
            previewRequest = builder.build()
            try {
                session.setRepeatingRequest(previewRequest!!, null, backgroundHandler)
            } catch (e: IllegalStateException) {
                // Session was closed (camera switched, disposed, etc.) - not an error
                Log.w(TAG, "Session closed during updatePreview: ${e.message}")
                return
            }
            
            sendEvent("previewStarted", null)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update preview", e)
        }
    }

    private fun processBufferFrame(image: Image) {
        try {
            // Convert image to byte array (simplified)
            val buffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            
            synchronized(bufferFrames) {
                bufferFrames.offer(bytes)
                if (bufferFrames.size > maxBufferFrames) {
                    bufferFrames.poll()
                }
            }
            
            image.close()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to process buffer frame", e)
            image.close()
        }
    }

    private fun startBuffer(result: MethodChannel.Result) {
        try {
            if (isBuffering) {
                result.success(null)
                return
            }
            
            // ═══════════════════════════════════════════════════════════════════
            // STORAGE CHECK - Verify sufficient space before starting buffer
            // ═══════════════════════════════════════════════════════════════════
            val manager = storageManager
            if (manager != null) {
                val storageCheck = manager.checkBufferStartSpace(currentResolution, currentFps)
                currentStorageMode = storageCheck.storageMode
                
                if (!storageCheck.hasEnoughSpace) {
                    Log.e(TAG, "❌ Insufficient storage to start buffer: " +
                            "available=${storageCheck.availableBytes / 1024 / 1024}MB, " +
                            "required=${storageCheck.requiredBytes / 1024 / 1024}MB")
                    
                    result.error(
                        "INSUFFICIENT_STORAGE",
                        storageCheck.message ?: "Not enough storage for buffer. Please free up space or reduce quality.",
                        mapOf(
                            "availableMB" to (storageCheck.availableBytes / 1024 / 1024),
                            "requiredMB" to (storageCheck.requiredBytes / 1024 / 1024),
                            "storageMode" to storageCheck.storageMode.name.lowercase()
                        )
                    )
                    return
                }
                
                Log.d(TAG, "✅ Storage check passed: ${storageCheck.availableBytes / 1024 / 1024}MB available, mode=$currentStorageMode")
            }
            
            isBuffering = true
            bufferSeconds = 0

            // ═══════════════════════════════════════════════════════════════════
            // START FOREGROUND SERVICE - Shows notification to user
            // Required by Google Play policy for continuous camera use
            // ═══════════════════════════════════════════════════════════════════
            BufferForegroundService.start(context, preRollSeconds)

            activeCaptureProfile?.let {
                Log.d(
                    TAG,
                    "[Buffer] Applying profile -> tier=${it.ramTier}, res=${it.resolution}, fps=${it.fps}, codec=${it.codec}, buffer=${it.bufferSeconds}s, mode=${it.bufferMode}"
                )
            }
            
            // Reinitialize the rolling buffer with storage manager
            rollingBuffer.initialize(context, useRam = false, manager = storageManager)
            
            // Initialize continuous pre-roll buffer
            initializeContinuousBuffer()
            
            // Start buffer timer - this creates the animated buffer ring
            bufferUpdateTask?.cancel()
            bufferUpdateTask = object : TimerTask() {
                override fun run() {
                    if (isBuffering) {
                        bufferSeconds++
                        sendEvent("bufferUpdate", mapOf(
                            "seconds" to bufferSeconds,
                            "isBuffering" to true,
                            "bufferDuration" to (bufferDurationMs / 1000).toInt()
                        ))
                    }
                }
            }
            bufferTimer.schedule(bufferUpdateTask, 1000, 1000)
            
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start buffer", e)
            result.error("BUFFER_ERROR", "Failed to start buffer: ${e.message}", null)
        }
    }
    
    private fun initializeContinuousBuffer() {
        try {
            if (isBufferInitialized) {
                Log.d(TAG, "Buffer already initialized; skipping re-init")
                return
            }
            // Use preRollSeconds from settings as selectedBufferSeconds
            selectedBufferSeconds = preRollSeconds
            val bufferDurationUs = (selectedBufferSeconds * 1_000_000).toLong()
            
            Log.d(TAG, "🎬 ═══════════ INITIALIZING BUFFER ═══════════")
            Log.d(TAG, "   Target buffer duration: ${selectedBufferSeconds}s (${bufferDurationUs}us)")
            
            // Update rolling buffer max duration
            rollingBuffer.updateMaxDuration(bufferDurationUs)
            // Note: Do NOT call rollingBuffer.clear() here!
            // The buffer was already initialized in startBuffer() with the proper directory.
            // Calling clear() would destroy the bufferDir and prevent disk writes.
            
            // Create encoder thread
            encoderThread = HandlerThread("EncoderThread").apply { start() }
            encoderHandler = Handler(encoderThread!!.looper)
            
            // Initialize video encoder
            Log.d(TAG, "   Initializing video encoder...")
            initializeVideoEncoder()
            
            // Initialize audio encoder
            Log.d(TAG, "   Initializing audio encoder...")
            initializeAudioEncoder()
            
            // Start buffer monitoring with periodic logging
            startBufferMonitoring()
            
            isBufferInitialized = true
            
            Log.d(TAG, "✅ Buffer initialized with encoders")
            Log.d(TAG, "   videoEncoder: ${if (videoEncoder != null) "ready" else "FAILED"}")
            Log.d(TAG, "   audioEncoder: ${if (audioEncoder != null) "ready" else "FAILED"}")
            Log.d(TAG, "   videoEncoderSurface: ${if (videoEncoderSurface != null) "created" else "FAILED"}")
            Log.d(TAG, "══════════════════════════════════════════════")
            
            // 🔍 CRITICAL: If camera is already open, close and recreate session with encoder surface
            if (cameraDevice != null && videoEncoderSurface != null) {
                Log.d(TAG, "⚠️ Camera already open! Closing current session and recreating with encoder surface...")
                
                backgroundHandler?.post {
                    try {
                        // Close existing session (generation guard in createBufferPreviewSession
                        // handles the race if this close happens after a new session started)
                        captureSession?.close()
                        captureSession = null
                        
                        // Recreate with encoder surface included
                        createBufferPreviewSession()
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error recreating session", e)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to initialize continuous buffer", e)
            e.printStackTrace()
        }
    }

    private fun shutdownContinuousBuffer() {
        try {
            if (!isBufferInitialized) {
                rollingBuffer.clear()
                return
            }

            Log.d(TAG, "Shutting down continuous buffer and encoders")
            isBufferInitialized = false
            rollingBuffer.clear()
            bufferLoggingTimer?.cancel()
            bufferLoggingTimer = null

            // Stop audio capture first so encoder stops receiving data
            isAudioCapturing = false
            
            // Wait for threads to finish processing
            Thread.sleep(100)
            
            try {
                audioRecord?.let {
                    if (it.state == AudioRecord.STATE_INITIALIZED) {
                        it.stop()
                    }
                    it.release()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop AudioRecord", e)
            } finally {
                audioRecord = null
            }

            try {
                audioEncoder?.let {
                    try {
                        it.stop()
                    } catch (_: IllegalStateException) {
                        // Encoder may already be stopped
                    }
                    it.release()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to release audio encoder", e)
            } finally {
                audioEncoder = null
                audioFormat = null  // Reset format for next cycle
            }

            try {
                videoEncoder?.let {
                    try {
                        it.stop()
                    } catch (_: IllegalStateException) {
                        // Encoder may already be stopped
                    }
                    it.release()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to release video encoder", e)
            } finally {
                videoEncoder = null
                videoFormat = null  // Reset format for next cycle
            }

            try {
                videoEncoderSurface?.release()
            } catch (_: Exception) {
                // Surface may already be released
            }
            videoEncoderSurface = null

            // Properly quit threads and wait for them to finish
            encoderThread?.quitSafely()
            encoderThread?.join(500)  // Wait up to 500ms for thread to finish
            encoderThread = null
            encoderHandler = null

            audioThread?.quitSafely()
            audioThread?.join(500)  // Wait up to 500ms for thread to finish
            audioThread = null
            audioHandler = null

            audioDrainCount = 0
            audioFeedCount = 0
            liveVideoSampleCount = 0
            liveAudioSampleCount = 0

            Log.d(TAG, "Continuous buffer stopped and threads cleaned up")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to shut down buffer", e)
        }
    }
    
    private fun initializeVideoEncoder() {
        try {
            val candidates = buildVideoEncoderCandidateSettings()
            var configured = false
            usingFallbackVideoProfile = false

            for ((index, settings) in candidates.withIndex()) {
                try {
                    releaseVideoEncoder()
                    configureVideoEncoder(settings)
                    usingFallbackVideoProfile = settings.isFallback
                    activeVideoEncoderSettings = settings
                    configured = true
                    Log.i(
                        TAG,
                        "[Record] using format: container=MP4, videoCodec=${settings.codec}, audioCodec=AAC, width=${settings.width}, height=${settings.height}, fps=${settings.fps}, bitrate=${settings.bitRate / 1_000_000}Mbps"
                    )
                    if (settings.isFallback && index > 0) {
                        Log.w(TAG, "[Fallback] High-profile encoder failed, using safe profile ${settings.summary}")
                    }
                    break
                } catch (e: Exception) {
                    Log.e(TAG, "[VideoEncoder] Failed to configure (${settings.summary})", e)
                }
            }

            if (!configured) {
                throw IllegalStateException("Unable to configure video encoder with any profile")
            }
            
            Log.d(TAG, "🎬 Video encoder created, surface ready. Encoder state: CONFIGURED (not started yet)")
            Log.d(TAG, "   Waiting for camera session to include this surface before starting encoder...")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize video encoder", e)
        }
    }

    private fun buildVideoEncoderCandidateSettings(): List<VideoEncoderSettings> {
        val candidates = mutableListOf<VideoEncoderSettings>()
        val totalRamMb = getTotalRamMb()
        
        // FRONT CAMERA: Always use 720p recording (front cameras have limited capabilities)
        val effectiveResolution = if (isFrontCamera()) {
            Log.d(TAG, "📷 Front camera: forcing 720p recording (was: $currentResolution)")
            "720P"
        } else {
            currentResolution
        }
        
        // Front camera: also cap FPS at 30 for stability
        val effectiveFps = if (isFrontCamera() && currentFps > 30) {
            Log.d(TAG, "📷 Front camera: capping FPS at 30 (was: $currentFps)")
            30
        } else {
            currentFps
        }
        
        Log.d(TAG, "[VideoEncoder] Building candidates for: ${effectiveResolution}@${effectiveFps}fps, RAM: ${totalRamMb}MB")
        
        // Primary: User's selected settings (or forced 720p for front camera)
        createVideoEncoderSettings(
            resolutionLabel = effectiveResolution,
            fps = effectiveFps,
            codec = currentCodec,
            isFallback = false
        )?.let { 
            candidates.add(it)
            Log.d(TAG, "[VideoEncoder] Primary candidate: ${it.summary}")
        }

        // Fallback: Safe settings (but preserve FPS if supported)
        candidates.add(buildSafeFallbackVideoSettings())
        return candidates
    }

    private fun createVideoEncoderSettings(
        resolutionLabel: String,
        fps: Int,
        codec: String,
        isFallback: Boolean
    ): VideoEncoderSettings? {
        val (width, height) = resolutionLabelToSize(resolutionLabel) ?: return null
        val bitRate = determineBitRate(resolutionLabel, width, height)
        val sanitizedFps = if (fps > 0) fps else 30
        val mimeType = codecToMime(codec)
        return VideoEncoderSettings(width, height, sanitizedFps, bitRate, codec, mimeType, isFallback)
    }

    private fun determineBitRate(label: String, width: Int, height: Int): Int {
        // Base bitrate for 30fps
        val baseBitrate = when (label.uppercase(Locale.US)) {
            "4K", "2160P" -> 45_000_000
            "1440P" -> 24_000_000
            "1080P" -> 12_000_000
            "720P" -> 6_000_000
            else -> (width * height * 4.5).toInt() // rough fallback
        }
        // Increase bitrate for 60fps (roughly 1.5-2x more data)
        val fpsFactor = if (currentFps >= 60) 1.8 else 1.0
        val finalBitrate = (baseBitrate * fpsFactor).toInt()
        Log.d(TAG, "[VideoEncoder] Bitrate: ${finalBitrate / 1_000_000}Mbps for ${label}@${currentFps}fps")
        return finalBitrate
    }

    private fun buildSafeFallbackVideoSettings(): VideoEncoderSettings {
        // FRONT CAMERA: Always fallback to 720p@30fps
        if (isFrontCamera()) {
            Log.d(TAG, "[VideoEncoder] Front camera fallback: 720P@30fps")
            return createVideoEncoderSettings("720P", 30, "H.264", true)
                ?: VideoEncoderSettings(1280, 720, 30, 6_000_000, "H.264", MediaFormat.MIMETYPE_VIDEO_AVC, true)
        }
        
        val supportedResolutions = ensureCameraCharacteristics()?.let { collectSupportedResolutions(it) } ?: emptyList()
        val fallbackRes = when {
            supportedResolutions.contains("1080P") -> "1080P"
            supportedResolutions.contains("720P") -> "720P"
            else -> supportedResolutions.lastOrNull() ?: "720P"
        }
        // Preserve user's FPS choice - only fallback resolution, not FPS
        // If 60fps fails, we'll fall back to 30fps in a subsequent candidate
        val fps = if (currentFps > 0) currentFps else 30
        Log.d(TAG, "[VideoEncoder] Fallback candidate: ${fallbackRes}@${fps}fps")
        return createVideoEncoderSettings(fallbackRes, fps, "H.264", true)
            ?: VideoEncoderSettings(1920, 1080, currentFps.coerceIn(24, 60), 12_000_000, "H.264", MediaFormat.MIMETYPE_VIDEO_AVC, true)
    }

    private fun resolutionLabelToSize(label: String): Pair<Int, Int>? {
        return when (label.uppercase(Locale.US)) {
            "4K", "2160P" -> 3840 to 2160
            "1440P" -> 2560 to 1440
            "1080P" -> 1920 to 1080
            "720P" -> 1280 to 720
            else -> 1920 to 1080
        }
    }

    private fun codecToMime(codec: String): String {
        return if (codec.equals("HEVC", ignoreCase = true)) {
            MediaFormat.MIMETYPE_VIDEO_HEVC
        } else {
            MediaFormat.MIMETYPE_VIDEO_AVC
        }
    }

    private fun configureVideoEncoder(settings: VideoEncoderSettings) {
        val format = MediaFormat.createVideoFormat(settings.mimeType, settings.width, settings.height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, settings.bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, settings.fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

        videoEncoder = MediaCodec.createEncoderByType(settings.mimeType)
        videoEncoder?.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        videoEncoderSurface = videoEncoder?.createInputSurface()
        Log.d(TAG, "Video encoder config: ${settings.summary}")
    }

    private fun releaseVideoEncoder() {
        try {
            videoEncoderSurface?.release()
        } catch (_: Exception) {
        }
        videoEncoderSurface = null
        try {
            videoEncoder?.stop()
        } catch (_: Exception) {
        }
        try {
            videoEncoder?.release()
        } catch (_: Exception) {
        }
        videoEncoder = null
    }
    
    private fun initializeAudioEncoder() {
        try {
            Log.d(TAG, "[Audio Init] Starting audio encoder initialization...")
            
            // Check microphone permission first
            if (ActivityCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "❌ Microphone permission not granted, cannot initialize audio encoder")
                return
            }
            
            // Ensure any previous instances are cleaned up
            audioRecord?.release()
            audioRecord = null
            audioEncoder?.release()
            audioEncoder = null
            audioFormat = null
            
            val sampleRate = 44100
            val channelCount = 1 // Mono
            val channelConfig = AndroidAudioFormat.CHANNEL_IN_MONO
            val audioEncoding = AndroidAudioFormat.ENCODING_PCM_16BIT
            
            // Calculate buffer size
            val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioEncoding)
            if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
                Log.e(TAG, "❌ AudioRecord.getMinBufferSize failed: $minBufferSize")
                return
            }
            val bufferSize = minBufferSize * 2
            Log.d(TAG, "[Audio Init] Buffer size calculated: $bufferSize bytes (min=$minBufferSize)")
            
            // Create AudioRecord
            audioRecord = AudioRecord(
                android.media.MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                audioEncoding,
                bufferSize
            )
            
            // Validate AudioRecord initialization
            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "❌ AudioRecord failed to initialize! State: ${audioRecord?.state}")
                audioRecord?.release()
                audioRecord = null
                return
            }
            
            Log.d(TAG, "✅ AudioRecord initialized successfully")
            
            // Create audio format - simplified configuration
            val audioFormat = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC,
                sampleRate,
                channelCount
            ).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, 64000) // 64 kbps
            }
            
            // Create and configure audio encoder
            val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
            val codecInfo = codecList.findEncoderForFormat(audioFormat)
            Log.d(TAG, "Selected audio codec: $codecInfo")
            
            audioEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            Log.d(TAG, "✅ Audio encoder created: ${audioEncoder?.name}")
            audioEncoder?.configure(audioFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            Log.d(TAG, "✅ Audio encoder configured (not started yet)")
            
            // Store the audio format for later muxing
            this.audioFormat = audioFormat
            
            Log.d(TAG, "✅ Audio encoder created and configured")
            
            // Start audio capture thread - ensure old thread is completely gone
            if (audioThread != null) {
                Log.w(TAG, "[Audio Init] ⚠️ Audio thread still exists, cleaning up first...")
                audioThread?.quitSafely()
                audioThread?.join(500)
                audioThread = null
                audioHandler = null
            }
            
            audioThread = HandlerThread("AudioCaptureThread").apply { start() }
            audioHandler = Handler(audioThread!!.looper)
            Log.d(TAG, "[Audio Init] ✅ Audio capture thread created")
            
            // Reset counters
            audioFeedCount = 0
            audioDrainCount = 0
            
            // Don't start recording yet - wait for camera session to be ready
            Log.d(TAG, "[Audio Init] ⏸️ Audio encoder ready but not started - waiting for camera session")
            
            Log.d(TAG, "✅ Audio encoder initialized: ${sampleRate}Hz mono AAC")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize audio encoder", e)
        }
    }
    
    private var audioFeedCount = 0
    private var audioDrainCount = 0
    
    private fun feedAudioToEncoder() {
        try {
            val encoder = audioEncoder ?: return
            val recorder = audioRecord ?: return
            
            // ALWAYS capture audio to buffer (both during idle and recording)
            if (!isAudioCapturing) {
                audioHandler?.postDelayed({ feedAudioToEncoder() }, 100)
                return
            }
            
            if (audioFeedCount == 0 || audioFeedCount % 50 == 0) {
                Log.d(TAG, "[Audio Feed] Attempt #$audioFeedCount - AudioRecord state: ${recorder.recordingState}")
            }
            
            val inputBufferId = encoder.dequeueInputBuffer(0) // Non-blocking
            if (inputBufferId >= 0) {
                val inputBuffer = encoder.getInputBuffer(inputBufferId)
                if (inputBuffer != null) {
                    inputBuffer.clear()
                    val readBytes = recorder.read(inputBuffer, inputBuffer.capacity())
                    
                    if (readBytes > 0) {
                        val presentationTimeUs = nowUs()
                        encoder.queueInputBuffer(inputBufferId, 0, readBytes, presentationTimeUs, 0)
                        
                        audioFeedCount++
                        if (audioFeedCount <= 5 || audioFeedCount % 100 == 0) {
                            Log.d(TAG, "[Audio Feed] ✅ #$audioFeedCount: $readBytes bytes read, PTS=${presentationTimeUs}µs")
                        }
                    } else {
                        encoder.queueInputBuffer(inputBufferId, 0, 0, 0, 0)
                        if (audioFeedCount < 10) {
                            Log.w(TAG, "[Audio Feed] ⚠️ AudioRecord.read returned $readBytes bytes (no data available)")
                        }
                    }
                } else {
                    Log.w(TAG, "[Audio Feed] ⚠️ Could not get input buffer $inputBufferId")
                }
            } else {
                if (audioFeedCount < 10) {
                    Log.w(TAG, "[Audio Feed] ⚠️ No input buffer available from encoder (result: $inputBufferId)")
                }
            }
            
            // Continue feeding if still capturing
            if (isAudioCapturing) {
                audioHandler?.post { feedAudioToEncoder() }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "[Audio Feed] ❌ Exception in feedAudioToEncoder", e)
            if (isAudioCapturing) {
                audioHandler?.postDelayed({ feedAudioToEncoder() }, 100)
            }
        }
    }
    
    private fun drainVideoEncoderLoop() {
        try {
            val encoder = videoEncoder ?: return
            if (!isBufferInitialized) return

            val bufferInfo = MediaCodec.BufferInfo()
            var processedAnything = false

            while (isBufferInitialized && videoEncoder === encoder) {
                val outputBufferId = encoder.dequeueOutputBuffer(bufferInfo, 0)

                when {
                    outputBufferId == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        break
                    }
                    outputBufferId == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val newFormat = encoder.outputFormat
                        val hasCsd0 = try { newFormat?.getByteBuffer("csd-0") != null } catch (_: Exception) { false }
                        val hasCsd1 = try { newFormat?.getByteBuffer("csd-1") != null } catch (_: Exception) { false }
                        Log.d(TAG, "Video encoder format changed: $newFormat")
                        Log.d(TAG, "Video format CSD buffers: csd-0=$hasCsd0, csd-1=$hasCsd1")
                        
                        // Only update videoFormat if it has valid CSD data
                        if (hasCsd0 && hasCsd1) {
                            videoFormat = newFormat
                            Log.d(TAG, "✅ Video format updated with valid CSD data")
                        } else {
                            Log.w(TAG, "⚠️ Video format missing CSD buffers, waiting for complete format")
                        }
                    }
                    outputBufferId >= 0 -> {
                        processedAnything = true
                        val outputBuffer = encoder.getOutputBuffer(outputBufferId)
                        if (outputBuffer != null && bufferInfo.size > 0) {
                            val data = ByteArray(bufferInfo.size)
                            outputBuffer.position(bufferInfo.offset)
                            outputBuffer.get(data)

                            val globalPtsUs = nowUs()
                            val adjustedBufferInfo = MediaCodec.BufferInfo().apply {
                                set(0, bufferInfo.size, globalPtsUs, bufferInfo.flags)
                            }

                            val videoSampleCount = rollingBuffer.getVideoSampleCount() + 1
                            if (videoSampleCount <= 5 || videoSampleCount % 100 == 0) {
                                Log.d(TAG, "📹 Video sample #$videoSampleCount: size=${bufferInfo.size}, globalPTS=${globalPtsUs}µs")
                            }

                            val sample = EncodedSample(data, adjustedBufferInfo, isVideo = true, globalPtsUs = globalPtsUs)
                            rollingBuffer.addSample(sample)

                            // DVR-style: All samples go to rolling buffer only
                            // No live writing to muxer - export happens in background after record stop
                        }

                        encoder.releaseOutputBuffer(outputBufferId, false)
                    }
                }
            }

            if (isBufferInitialized && videoEncoder === encoder) {
                val delayMs = if (processedAnything) 0L else 10L
                encoderHandler?.postDelayed({ drainVideoEncoderLoop() }, delayMs)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error draining video encoder", e)
            if (isBufferInitialized) {
                encoderHandler?.postDelayed({ drainVideoEncoderLoop() }, 100)
            }
        }
    }
    
    private fun drainAudioEncoderLoop() {
        try {
            val encoder = audioEncoder ?: return
            if (!isBufferInitialized) return

            val bufferInfo = MediaCodec.BufferInfo()
            var processedAnything = false

            while (isBufferInitialized && audioEncoder === encoder) {
                val outputBufferId = encoder.dequeueOutputBuffer(bufferInfo, 0)

                when {
                    outputBufferId == MediaCodec.INFO_TRY_AGAIN_LATER -> break
                    outputBufferId == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        audioFormat = encoder.outputFormat
                        // Note: AAC encoders often don't provide CSD buffers upfront
                        // CSD data may be embedded in the first encoded frame instead
                        Log.d(TAG, "Audio encoder format changed: $audioFormat")
                    }
                    outputBufferId >= 0 -> {
                        processedAnything = true
                        val outputBuffer = encoder.getOutputBuffer(outputBufferId)
                        if (outputBuffer != null && bufferInfo.size > 0) {
                            val data = ByteArray(bufferInfo.size)
                            outputBuffer.position(bufferInfo.offset)
                            outputBuffer.get(data)

                            val globalPtsUs = nowUs()
                            val adjustedBufferInfo = MediaCodec.BufferInfo().apply {
                                set(0, bufferInfo.size, globalPtsUs, bufferInfo.flags)
                            }

                            audioDrainCount++
                            if (audioDrainCount <= 10 || audioDrainCount % 100 == 0) {
                                val isConfig = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                                Log.d(TAG, "[Audio Drain] ✅ #$audioDrainCount: size=${bufferInfo.size}b, PTS=${globalPtsUs}µs, isConfig=$isConfig")
                            }

                            val sample = EncodedSample(data, adjustedBufferInfo, isVideo = false, globalPtsUs = globalPtsUs)
                            rollingBuffer.addSample(sample)

                            // DVR-style: All samples go to rolling buffer only
                            // No live writing to muxer - export happens in background after record stop
                        }

                        encoder.releaseOutputBuffer(outputBufferId, false)
                    }
                }
            }

            if (isBufferInitialized && audioEncoder === encoder) {
                val delayMs = if (processedAnything) 0L else 10L
                encoderHandler?.postDelayed({ drainAudioEncoderLoop() }, delayMs)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error draining audio encoder", e)
            if (isBufferInitialized) {
                encoderHandler?.postDelayed({ drainAudioEncoderLoop() }, 100)
            }
        }
    }
    
    private fun startBufferMonitoring() {
        bufferLoggingTimer?.cancel()
        bufferLoggingTimer = Timer()
        bufferLoggingTimer?.schedule(object : TimerTask() {
            override fun run() {
                if (isBufferInitialized) {
                    val duration = rollingBuffer.getDurationSeconds()
                    val sampleCount = rollingBuffer.getSampleCount()
                    val videoCount = rollingBuffer.getVideoSampleCount()
                    val audioCount = rollingBuffer.getAudioSampleCount()
                    val memoryUsageMB = rollingBuffer.getMemoryUsageBytes() / (1024.0 * 1024.0)
                    val diskUsageMB = rollingBuffer.getDiskUsageBytes() / (1024.0 * 1024.0)
                    
                    Log.d(TAG, "Buffer state: target=${selectedBufferSeconds}s, " +
                            "buffered=${String.format("%.2f", duration)}s, " +
                            "samples=${sampleCount} (V=$videoCount, A=$audioCount), " +
                            "disk=${String.format("%.1f", diskUsageMB)}MB, " +
                            "ram=${String.format("%.1f", memoryUsageMB)}MB")
                }
            }
        }, 1000, 1000) // Log every second
    }
    
    private fun startContinuousEncoding() {
        // This method is now deprecated - encoding starts automatically when encoders are initialized
        // Keeping for backward compatibility but it does nothing
        Log.d(TAG, "startContinuousEncoding called (deprecated - encoders start automatically)")
    }

    private fun stopBuffer(result: MethodChannel.Result) {
        try {
            if (!isBuffering) {
                result.success(null)
                return
            }
            isBuffering = false
            bufferUpdateTask?.cancel()
            bufferUpdateTask = null
            
            // ═══════════════════════════════════════════════════════════════════
            // STOP FOREGROUND SERVICE - Remove notification
            // ═══════════════════════════════════════════════════════════════════
            BufferForegroundService.stop(context)
            
            synchronized(bufferFrames) {
                bufferFrames.clear()
            }
            shutdownContinuousBuffer()
            
            // ═══════════════════════════════════════════════════════════════════
            // CLEANUP - Delete buffer files when stopping buffer
            // ═══════════════════════════════════════════════════════════════════
            rollingBuffer.cleanup()
            storageManager?.cleanupBufferFiles()
            Log.d(TAG, "Buffer files cleaned up")
            
            backgroundHandler?.post {
                try {
                    captureSession?.close()
                    captureSession = null
                    createCameraPreviewSession()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to recreate preview session after stopping buffer", e)
                }
            }
            
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop buffer", e)
            result.error("BUFFER_ERROR", "Failed to stop buffer: ${e.message}", null)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // DVR-STYLE RECORDING: O(1) Record Press, Background Export on Stop
    // - Record press: Just mark timestamp (instant, no pipeline interruption)
    // - Recording: Continue writing to rolling buffer as normal
    // - Record stop: Export pre-roll + live samples in background thread
    // ═══════════════════════════════════════════════════════════════════════════════
    
    private fun startRecording(result: MethodChannel.Result) {
        try {
            if (isRecording) {
                result.error("ALREADY_RECORDING", "Recording already in progress", null)
                return
            }
            
            // CRITICAL: Ensure buffer is running before recording can start
            if (!isBuffering || !isBufferInitialized) {
                Log.e(TAG, "[Record] ❌ Cannot start recording: Buffer not active (isBuffering=$isBuffering, isBufferInitialized=$isBufferInitialized)")
                result.error("BUFFER_NOT_ACTIVE", "Start buffer first to enable recording with pre-roll", null)
                return
            }
            
            // Check if previous export is still running
            if (isExporting) {
                Log.w(TAG, "[Record] ⚠️ Previous export still running, waiting...")
                result.error("EXPORT_IN_PROGRESS", "Previous recording is still being saved", null)
                return
            }
            
            // ═══════════════════════════════════════════════════════════════════
            // STORAGE CHECK - Verify sufficient space before starting recording
            // ═══════════════════════════════════════════════════════════════════
            val manager = storageManager
            if (manager != null) {
                // Calculate expected recording duration based on max recording time for current settings
                val expectedRecordingSeconds = when {
                    currentResolution == "4K" && currentFps >= 60 -> 5 * 60   // 5 minutes
                    currentResolution == "4K" && currentFps <= 30 -> 10 * 60  // 10 minutes
                    currentResolution == "1080P" && currentFps >= 60 -> 10 * 60 // 10 minutes
                    currentResolution == "1080P" && currentFps <= 30 -> 15 * 60 // 15 minutes
                    else -> 10 * 60 // Default: 10 minutes
                }
                
                val storageCheck = manager.checkRecordingStartSpace(
                    currentResolution, currentFps, selectedBufferSeconds, expectedRecordingSeconds
                )
                currentStorageMode = storageCheck.storageMode
                
                if (!storageCheck.hasEnoughSpace) {
                    Log.e(TAG, "[Record] ❌ Insufficient storage to start recording: " +
                            "available=${storageCheck.availableBytes / 1024 / 1024}MB, " +
                            "required=${storageCheck.requiredBytes / 1024 / 1024}MB")
                    
                    result.error(
                        "INSUFFICIENT_STORAGE",
                        storageCheck.message ?: "Not enough storage to safely record. Try reducing resolution, frame rate, or buffer duration.",
                        mapOf(
                            "availableMB" to (storageCheck.availableBytes / 1024 / 1024),
                            "requiredMB" to (storageCheck.requiredBytes / 1024 / 1024),
                            "storageMode" to storageCheck.storageMode.name.lowercase()
                        )
                    )
                    return
                }
                
                Log.d(TAG, "[Record] ✅ Storage check passed: ${storageCheck.availableBytes / 1024 / 1024}MB available")
            }
            
            // ═══════════════════════════════════════════════════════════════════
            // O(1) RECORD START - Just mark timestamp, NO heavy work!
            // ═══════════════════════════════════════════════════════════════════
            
            // Generate fresh recording ID
            currentRecordingId = UUID.randomUUID().toString()
            recordingStartTime = System.currentTimeMillis()
            
            // Mark the global PTS when recording started - this is the key for DVR-style recording
            recordingStartGlobalPtsUs = nowUs()
            recordingMarkTimestamp = System.currentTimeMillis()
            
            // ═══════════════════════════════════════════════════════════════════
            // CRITICAL: Get the ACTUAL oldest sample PTS from the buffer
            // This is the real start of the pre-roll content, not a calculated value!
            // ═══════════════════════════════════════════════════════════════════
            val bufferOldestPts = rollingBuffer.getOldestSamplePts()
            val bufferNewestPts = rollingBuffer.getNewestSamplePts()
            val bufferDuration = rollingBuffer.getDurationSeconds()
            
            // Use the actual oldest sample in the buffer as the pre-roll start
            // This ensures we capture ALL buffered content, regardless of how long buffer ran
            frozenPreRollStartPts = if (bufferOldestPts > 0) bufferOldestPts else recordingStartGlobalPtsUs
            
            val actualPrerollSec = if (bufferOldestPts > 0 && bufferNewestPts > 0) {
                (bufferNewestPts - bufferOldestPts) / 1_000_000.0
            } else {
                0.0
            }
            
            // ═══════════════════════════════════════════════════════════════════
            // CRITICAL: Expand buffer max duration to hold pre-roll + live recording
            // Without this, the rolling buffer would trim pre-roll samples during recording!
            // Max recording time depends on resolution/fps (lower bitrate = longer recording)
            // ═══════════════════════════════════════════════════════════════════
            val maxLiveRecordingMinutes = when {
                currentResolution == "4K" && currentFps >= 60 -> 5   // 4K60: ~5.7MB/s → 5 min max
                currentResolution == "4K" && currentFps <= 30 -> 10  // 4K30: ~2.8MB/s → 10 min max
                currentResolution == "1080P" && currentFps >= 60 -> 10 // 1080p60: ~1.5MB/s → 10 min max
                currentResolution == "1080P" && currentFps <= 30 -> 15 // 1080p30: ~0.75MB/s → 15 min max
                else -> 10 // Default: 10 minutes
            }
            val maxLiveRecordingUs = maxLiveRecordingMinutes.toLong() * 60 * 1_000_000L
            val expandedBufferDurationUs = (selectedBufferSeconds * 1_000_000L) + maxLiveRecordingUs
            rollingBuffer.updateMaxDuration(expandedBufferDurationUs)
            Log.d(TAG, "[Record] Buffer expanded to ${expandedBufferDurationUs / 1_000_000}s (${maxLiveRecordingMinutes}min max for $currentResolution@${currentFps}fps)")
            
            // Set recording flag - buffer will continue writing samples as normal
            isRecording = true
            
            // Capture device orientation for video metadata
            recordingOrientation = getDeviceOrientationForRecording()
            
            // Log buffer state for debugging
            val bufferSamples = rollingBuffer.getSampleCount()
            val videoCount = rollingBuffer.getVideoSampleCount()
            val audioCount = rollingBuffer.getAudioSampleCount()
            
            Log.d(TAG, "═══════════════════════════════════════════════════════════")
            Log.d(TAG, "[Record] 🎬 RECORDING STARTED (O(1) - instant)")
            Log.d(TAG, "[Record] - ID: $currentRecordingId")
            Log.d(TAG, "[Record] - Record start PTS: ${recordingStartGlobalPtsUs}µs")
            Log.d(TAG, "[Record] - Buffer oldest PTS: ${bufferOldestPts}µs")
            Log.d(TAG, "[Record] - Buffer newest PTS: ${bufferNewestPts}µs")
            Log.d(TAG, "[Record] - Frozen pre-roll start: ${frozenPreRollStartPts}µs")
            Log.d(TAG, "[Record] - Buffer duration: ${String.format("%.2f", bufferDuration)}s")
            Log.d(TAG, "[Record] - Actual pre-roll available: ${String.format("%.2f", actualPrerollSec)}s")
            Log.d(TAG, "[Record] - Buffer samples: $bufferSamples (video=$videoCount, audio=$audioCount)")
            Log.d(TAG, "[Record] - Selected buffer setting: ${selectedBufferSeconds}s")
            Log.d(TAG, "[Record] - Orientation: $recordingOrientation°")
            Log.d(TAG, "[Record] - Max recording duration: ${maxLiveRecordingMinutes} minutes")
            Log.d(TAG, "═══════════════════════════════════════════════════════════")
            
            // Setup auto-stop timer for max recording duration
            maxRecordingDurationMs = maxLiveRecordingMinutes.toLong() * 60 * 1000
            recordingAutoStopTimer?.cancel()
            recordingAutoStopTimer = Timer()
            recordingAutoStopTimer?.schedule(object : TimerTask() {
                override fun run() {
                    if (isRecording) {
                        Log.d(TAG, "⏱️ Max recording duration reached (${maxLiveRecordingMinutes}min) - auto-stopping")
                        // Send event to Flutter to notify user and trigger stop
                        sendEvent("maxDurationReached", mapOf(
                            "maxMinutes" to maxLiveRecordingMinutes,
                            "resolution" to currentResolution,
                            "fps" to currentFps
                        ))
                        // Auto-stop recording on main handler
                        backgroundHandler?.post {
                            stopRecording(object : MethodChannel.Result {
                                override fun success(result: Any?) {
                                    Log.d(TAG, "Auto-stop recording completed successfully")
                                }
                                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                    Log.e(TAG, "Auto-stop recording failed: $errorMessage")
                                }
                                override fun notImplemented() {}
                            })
                        }
                    }
                }
            }, maxRecordingDurationMs)
            Log.d(TAG, "[Record] Auto-stop timer set for ${maxLiveRecordingMinutes} minutes")
            
            // Instant response - recording has started
            result.success(currentRecordingId)
            
            // Notify Flutter that recording started
            sendEvent("recordingStarted", mapOf(
                "id" to currentRecordingId,
                "prerollAvailable" to actualPrerollSec
            ))
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start recording", e)
            isRecording = false
            result.error("RECORDING_ERROR", "Failed to start recording: ${e.message}", null)
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // LEGACY METHODS - Kept for reference but no longer used in DVR-style recording
    // ═══════════════════════════════════════════════════════════════════════════════
    
    // DEPRECATED: Old sync pre-roll approach - replaced by DVR-style background export
    @Deprecated("Use startBackgroundExport instead")
    private fun startRecordingWithPreroll() {
        Log.w(TAG, "startRecordingWithPreroll is DEPRECATED - using DVR-style recording now")
        // No longer used - recording now uses DVR-style export
    }

    // DEPRECATED: Old sync pre-roll approach - replaced by DVR-style background export  
    @Deprecated("Use performBackgroundExport instead")
    private fun startRecordingWithPrerollInternal(attempt: Int) {
        Log.w(TAG, "startRecordingWithPrerollInternal is DEPRECATED - using DVR-style recording now")
        // No longer used - recording now uses DVR-style export
    }

    private fun areEncoderFormatsReady(): Boolean {
        // Just check if we have formats - CSD will be extracted if needed
        if (videoFormat == null) {
            Log.d(TAG, "[Record] Video format not ready")
            return false
        }
        
        if (audioFormat == null) {
            Log.d(TAG, "[Record] Audio format not ready")
            return false
        }
        
        return true
    }

    private fun captureEncoderFormatsIfAvailable() {
        if (videoFormat == null) {
            try {
                videoEncoder?.outputFormat?.let {
                    videoFormat = it
                    Log.d(TAG, "[Record] Captured video format while waiting: $it")
                }
            } catch (_: IllegalStateException) {
                // Encoder not ready yet
            }
        }

        if (audioFormat == null) {
            try {
                audioEncoder?.outputFormat?.let {
                    audioFormat = it
                    Log.d(TAG, "[Record] Captured audio format while waiting: $it")
                }
            } catch (_: IllegalStateException) {
                // Encoder not ready yet
            }
        }
    }

    /**
     * Ensures video format has CSD (Codec Specific Data) buffers.
     * If format doesn't have CSD, extracts it from first CODEC_CONFIG frame.
     */
    private fun ensureVideoFormatHasCsd(format: MediaFormat?, videoSamples: List<EncodedSample>): MediaFormat? {
        if (format == null) return null
        
        // Check if format already has CSD buffers
        val hasCsd0 = try { format.getByteBuffer("csd-0") != null } catch (_: Exception) { false }
        val hasCsd1 = try { format.getByteBuffer("csd-1") != null } catch (_: Exception) { false }
        
        if (hasCsd0 && hasCsd1) {
            Log.d(TAG, "[Record] ✅ Video format has CSD buffers from encoder")
            return format
        }
        
        // CSD missing - try to extract from first CODEC_CONFIG frame
        Log.w(TAG, "[Record] ⚠️ Video format missing CSD, searching encoded frames...")
        
        val csdFrame = videoSamples.firstOrNull { 
            (it.info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0 
        }
        
        if (csdFrame != null) {
            Log.d(TAG, "[Record] Found CODEC_CONFIG frame, size=${csdFrame.data.size}b")
            
            // For H.264, CSD contains SPS and PPS NAL units
            // They're separated by start codes (0x00000001 or 0x000001)
            val csdData = csdFrame.data
            val spsAndPps = extractSpsAndPps(csdData)
            
            if (spsAndPps != null) {
                val (sps, pps) = spsAndPps
                Log.d(TAG, "[Record] ✅ Extracted SPS (${sps.size}b) and PPS (${pps.size}b) from CODEC_CONFIG")
                
                // Create new format with CSD
                val newFormat = MediaFormat.createVideoFormat(
                    format.getString(MediaFormat.KEY_MIME) ?: MediaFormat.MIMETYPE_VIDEO_AVC,
                    format.getInteger(MediaFormat.KEY_WIDTH),
                    format.getInteger(MediaFormat.KEY_HEIGHT)
                )
                
                // Copy all keys from original format
                try {
                    if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                        newFormat.setInteger(MediaFormat.KEY_FRAME_RATE, format.getInteger(MediaFormat.KEY_FRAME_RATE))
                    }
                    if (format.containsKey(MediaFormat.KEY_BIT_RATE)) {
                        newFormat.setInteger(MediaFormat.KEY_BIT_RATE, format.getInteger(MediaFormat.KEY_BIT_RATE))
                    }
                    if (format.containsKey(MediaFormat.KEY_I_FRAME_INTERVAL)) {
                        newFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, format.getInteger(MediaFormat.KEY_I_FRAME_INTERVAL))
                    }
                    if (format.containsKey(MediaFormat.KEY_COLOR_FORMAT)) {
                        newFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT, format.getInteger(MediaFormat.KEY_COLOR_FORMAT))
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "[Record] Some format keys not copied: ${e.message}")
                }
                
                // Add CSD buffers
                newFormat.setByteBuffer("csd-0", ByteBuffer.wrap(sps))
                newFormat.setByteBuffer("csd-1", ByteBuffer.wrap(pps))
                
                return newFormat
            }
        }
        
        Log.e(TAG, "[Record] ❌ Could not extract CSD from frames")
        return null
    }
    
    /**
     * Extracts SPS and PPS NAL units from H.264 CSD buffer.
     * H.264 CSD format: [start code] [SPS] [start code] [PPS]
     * Start codes: 0x00000001 (4 bytes) or 0x000001 (3 bytes)
     */
    private fun extractSpsAndPps(csdData: ByteArray): Pair<ByteArray, ByteArray>? {
        try {
            val startCodes = mutableListOf<Int>()
            
            // Find all start codes
            for (i in 0 until csdData.size - 3) {
                if (csdData[i] == 0.toByte() && csdData[i + 1] == 0.toByte()) {
                    if (csdData[i + 2] == 0.toByte() && csdData[i + 3] == 1.toByte()) {
                        startCodes.add(i) // 4-byte start code
                    } else if (csdData[i + 2] == 1.toByte()) {
                        startCodes.add(i) // 3-byte start code
                    }
                }
            }
            
            if (startCodes.size < 2) {
                Log.w(TAG, "[Record] Found ${startCodes.size} start codes, need at least 2")
                return null
            }
            
            // First NAL unit is SPS (starts after first start code)
            val firstStartCodeLen = if (csdData[startCodes[0] + 2] == 0.toByte()) 4 else 3
            val spsStart = startCodes[0] + firstStartCodeLen
            val spsEnd = startCodes[1]
            val sps = csdData.copyOfRange(spsStart, spsEnd)
            
            // Second NAL unit is PPS (starts after second start code)
            val secondStartCodeLen = if (csdData[startCodes[1] + 2] == 0.toByte()) 4 else 3
            val ppsStart = startCodes[1] + secondStartCodeLen
            val ppsEnd = if (startCodes.size > 2) startCodes[2] else csdData.size
            val pps = csdData.copyOfRange(ppsStart, ppsEnd)
            
            // Validate NAL unit types
            // SPS = 0x67 (NAL type 7), PPS = 0x68 (NAL type 8)
            val spsType = (sps[0].toInt() and 0x1F)
            val ppsType = (pps[0].toInt() and 0x1F)
            
            if (spsType != 7 || ppsType != 8) {
                Log.w(TAG, "[Record] Invalid NAL types: SPS=$spsType (expected 7), PPS=$ppsType (expected 8)")
                return null
            }
            
            return Pair(sps, pps)
        } catch (e: Exception) {
            Log.e(TAG, "[Record] Failed to extract SPS/PPS", e)
            return null
        }
    }

    private fun stopRecording(result: MethodChannel.Result) {
        try {
            if (!isRecording) {
                Log.w(TAG, "stopRecording called with no active recording; ignoring")
                result.success(null)
                return
            }
            
            // Cancel auto-stop timer if running
            recordingAutoStopTimer?.cancel()
            recordingAutoStopTimer = null
            
            // ═══════════════════════════════════════════════════════════════════
            // DVR-STYLE RECORD STOP - Mark timestamp, then export in background
            // ═══════════════════════════════════════════════════════════════════
            
            // Mark the global PTS when recording stopped
            recordingStopGlobalPtsUs = nowUs()
            val recordingDurationUs = recordingStopGlobalPtsUs - recordingStartGlobalPtsUs
            
            Log.d(TAG, "═══════════════════════════════════════════════════════════")
            Log.d(TAG, "[Record] 🛑 RECORDING STOPPED")
            Log.d(TAG, "[Record] - Stop PTS: ${recordingStopGlobalPtsUs}µs")
            Log.d(TAG, "[Record] - Recording duration: ${recordingDurationUs / 1_000_000.0}s")
            Log.d(TAG, "═══════════════════════════════════════════════════════════")
            
            // Clear recording flag immediately
            isRecording = false
            
            // Send immediate response to Flutter
            sendEvent("recordingStopped", mapOf("id" to currentRecordingId))
            result.success(null)
            
            // Start background export
            startBackgroundExport()
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop recording", e)
            isRecording = false
            result.error("RECORDING_ERROR", "Failed to stop recording: ${e.message}", null)
        }
    }
    
    /**
     * DVR-style background export - extracts pre-roll + live samples and muxes them
     * This runs completely in the background, never blocking the camera pipeline
     */
    private fun startBackgroundExport() {
        if (isExporting) {
            Log.w(TAG, "[Export] ⚠️ Export already in progress")
            return
        }
        
        isExporting = true
        
        // Capture all needed state before starting the background thread
        val recordingId = currentRecordingId ?: return
        val startPts = recordingStartGlobalPtsUs
        val stopPts = recordingStopGlobalPtsUs
        val orientation = recordingOrientation
        val startTime = recordingStartTime
        val fps = currentFps
        val resolution = currentResolution
        val codec = currentCodec
        val preRollSec = preRollSeconds
        
        // ═══════════════════════════════════════════════════════════════════
        // USE FROZEN PRE-ROLL START PTS - This was captured when Record started
        // This ensures we get the exact pre-roll content that existed at that moment
        // ═══════════════════════════════════════════════════════════════════
        val preRollStartPts = frozenPreRollStartPts
        
        // Calculate actual durations
        val preRollDurationSec = (startPts - preRollStartPts) / 1_000_000.0
        val liveDurationSec = (stopPts - startPts) / 1_000_000.0
        val totalDurationSec = (stopPts - preRollStartPts) / 1_000_000.0
        
        Log.d(TAG, "[Export] 📦 Starting background export...")
        Log.d(TAG, "[Export] - Recording ID: $recordingId")
        Log.d(TAG, "[Export] - Frozen pre-roll start PTS: ${preRollStartPts}µs")
        Log.d(TAG, "[Export] - Record start PTS: ${startPts}µs")
        Log.d(TAG, "[Export] - Record stop PTS: ${stopPts}µs")
        Log.d(TAG, "[Export] - Pre-roll duration: ${String.format("%.2f", preRollDurationSec)}s")
        Log.d(TAG, "[Export] - Live duration: ${String.format("%.2f", liveDurationSec)}s")
        Log.d(TAG, "[Export] - Total timeline: ${String.format("%.2f", totalDurationSec)}s")
        
        // NOTE: Do NOT restore buffer duration here!
        // We must keep the expanded buffer until export has finished reading samples.
        // Buffer will be restored inside the export thread after streaming is complete.
        
        exportThread = Thread {
            try {
                performBackgroundExport(
                    recordingId = recordingId,
                    preRollStartPts = preRollStartPts,
                    recordStartPts = startPts,
                    recordStopPts = stopPts,
                    orientation = orientation,
                    startTime = startTime,
                    fps = fps,
                    resolution = resolution,
                    codec = codec,
                    preRollSec = preRollSec
                )
            } catch (e: Exception) {
                Log.e(TAG, "[Export] ❌ Background export failed", e)
                sendEvent("recordingError", mapOf("error" to "Export failed: ${e.message}"))
            } finally {
                isExporting = false
                
                // Reset recording state
                recordingStartGlobalPtsUs = -1
                recordingStopGlobalPtsUs = -1
                recordingMarkTimestamp = 0
                frozenPreRollStartPts = -1
            }
        }
        exportThread?.name = "DVR-Export-Thread"
        exportThread?.start()
    }
    
    /**
     * Performs the actual export work in background thread.
     * Uses STREAMING approach - reads samples from disk in batches to avoid OOM at 4K 60fps.
     * This is critical for 30s buffer at 4K 60fps which contains ~170MB of encoded data.
     */
    private fun performBackgroundExport(
        recordingId: String,
        preRollStartPts: Long,
        recordStartPts: Long,
        recordStopPts: Long,
        orientation: Int,
        startTime: Long,
        fps: Int,
        resolution: String,
        codec: String,
        preRollSec: Int
    ) {
        Log.d(TAG, "[Export] 🔄 Background STREAMING export started on ${Thread.currentThread().name}")
        
        // Send initial progress
        sendEvent("finalizeProgress", mapOf("progress" to 0.1))
        
        // Step 1: Get sample counts and metadata without loading data into RAM
        val totalSamples = rollingBuffer.getSampleCountInRange(preRollStartPts, recordStopPts)
        val videoSampleCount = rollingBuffer.getVideoSampleCountInRange(preRollStartPts, recordStopPts)
        
        Log.d(TAG, "[Export] Total samples in range: $totalSamples (video: $videoSampleCount)")
        
        if (videoSampleCount == 0) {
            Log.e(TAG, "[Export] ❌ No video samples found in recording timeline")
            sendEvent("recordingError", mapOf("error" to "No video data captured"))
            return
        }
        
        sendEvent("finalizeProgress", mapOf("progress" to 0.15))
        
        // Step 2: Validate encoder formats
        if (!areEncoderFormatsReady()) {
            Log.e(TAG, "[Export] ❌ Encoder formats not ready")
            sendEvent("recordingError", mapOf("error" to "Encoder formats not ready"))
            return
        }
        
        // Step 3: Get first keyframe for CSD without loading all samples
        val firstKeyframeSample = rollingBuffer.getFirstKeyframeSample(preRollStartPts, recordStopPts)
        if (firstKeyframeSample == null) {
            Log.e(TAG, "[Export] ❌ No keyframe found in recording range")
            sendEvent("recordingError", mapOf("error" to "No keyframe found"))
            return
        }
        
        val firstKeyframePts = firstKeyframeSample.globalPtsUs
        Log.d(TAG, "[Export] First keyframe at PTS: $firstKeyframePts")
        
        sendEvent("finalizeProgress", mapOf("progress" to 0.2))
        
        // Step 4: Create output file
        val outputFile = getOutputFile()
        currentOutputFile = outputFile
        Log.d(TAG, "[Export] Output file: ${outputFile.absolutePath}")
        
        try {
            // Step 5: Ensure video format has CSD from keyframe
            val videoFormatWithCsd = ensureVideoFormatHasCsd(videoFormat, listOf(firstKeyframeSample))
            if (videoFormatWithCsd == null) {
                Log.e(TAG, "[Export] ❌ Failed to get valid video format with CSD")
                outputFile.delete()
                sendEvent("recordingError", mapOf("error" to "Invalid video format"))
                return
            }
            
            // Step 6: Create muxer and add tracks
            val muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            
            val videoTrackIndex = muxer.addTrack(videoFormatWithCsd)
            Log.d(TAG, "[Export] ✅ Video track added: index=$videoTrackIndex")
            
            val audioTrackIndex = if (audioFormat != null) {
                try {
                    muxer.addTrack(audioFormat!!)
                } catch (e: Exception) {
                    Log.w(TAG, "[Export] ⚠️ Failed to add audio track", e)
                    -1
                }
            } else {
                -1
            }
            
            muxer.setOrientationHint(orientation)
            muxer.start()
            Log.d(TAG, "[Export] ✅ Muxer started")
            
            sendEvent("finalizeProgress", mapOf("progress" to 0.3))
            
            // Step 7: Stream samples from disk and write to muxer
            // This avoids loading all samples into RAM at once
            val localVideoDeltaUs = 1_000_000L / fps.toLong()
            val localAudioDeltaUs = 23220L // AAC @ 44.1kHz
            
            var nextVideoPts = 0L
            var nextAudioPts = 0L
            var videoWriteCount = 0
            var audioWriteCount = 0
            var samplesProcessed = 0
            var foundFirstKeyframe = false
            
            // Use streaming to process samples in batches of 30
            // This keeps memory usage bounded regardless of buffer size
            rollingBuffer.streamSamplesInRange(
                startPtsUs = preRollStartPts,
                endPtsUs = recordStopPts,
                batchSize = 30
            ) { batch ->
                for (sample in batch) {
                    // Skip samples until we reach the first keyframe
                    if (!foundFirstKeyframe) {
                        if (sample.isVideo && (sample.info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0) {
                            foundFirstKeyframe = true
                            Log.d(TAG, "[Export] Found first keyframe at sample $samplesProcessed")
                        } else if (sample.isVideo) {
                            // Skip non-keyframe video samples before first keyframe
                            samplesProcessed++
                            continue
                        }
                    }
                    
                    if (sample.isVideo) {
                        // Write video sample
                        val bufferInfo = MediaCodec.BufferInfo()
                        bufferInfo.set(0, sample.data.size, nextVideoPts, sample.info.flags)
                        
                        val byteBuffer = ByteBuffer.wrap(sample.data)
                        muxer.writeSampleData(videoTrackIndex, byteBuffer, bufferInfo)
                        
                        videoWriteCount++
                        nextVideoPts += localVideoDeltaUs
                    } else if (audioTrackIndex >= 0 && foundFirstKeyframe) {
                        // Write audio sample (only after first keyframe)
                        val bufferInfo = MediaCodec.BufferInfo()
                        bufferInfo.set(0, sample.data.size, nextAudioPts, sample.info.flags)
                        
                        val byteBuffer = ByteBuffer.wrap(sample.data)
                        muxer.writeSampleData(audioTrackIndex, byteBuffer, bufferInfo)
                        
                        audioWriteCount++
                        nextAudioPts += localAudioDeltaUs
                    }
                    
                    samplesProcessed++
                }
                
                // Update progress based on samples processed
                val progress = 0.3 + (0.5 * samplesProcessed / totalSamples.coerceAtLeast(1))
                sendEvent("finalizeProgress", mapOf("progress" to progress.coerceAtMost(0.8)))
            }
            
            // ═══════════════════════════════════════════════════════════════════
            // CRITICAL: Now that streaming is complete, restore buffer to normal duration
            // This was expanded when Record started to preserve pre-roll during recording
            // ═══════════════════════════════════════════════════════════════════
            val normalBufferDurationUs = selectedBufferSeconds * 1_000_000L
            rollingBuffer.updateMaxDuration(normalBufferDurationUs)
            Log.d(TAG, "[Export] Buffer restored to normal ${selectedBufferSeconds}s duration after streaming complete")
            
            val totalDurationSec = nextVideoPts / 1_000_000.0
            Log.d(TAG, "[Export] ✅ Streamed: $videoWriteCount video + $audioWriteCount audio samples (${String.format("%.2f", totalDurationSec)}s)")
            
            if (videoWriteCount == 0) {
                Log.e(TAG, "[Export] ❌ No video samples were written")
                muxer.stop()
                muxer.release()
                outputFile.delete()
                sendEvent("recordingError", mapOf("error" to "No video data written"))
                return
            }
            
            sendEvent("finalizeProgress", mapOf("progress" to 0.85))
            
            // Step 8: Finalize muxer
            try {
                muxer.stop()
                muxer.release()
                Log.d(TAG, "[Export] ✅ Muxer finalized")
            } catch (e: Exception) {
                Log.e(TAG, "[Export] ❌ Error finalizing muxer", e)
                outputFile.delete()
                sendEvent("recordingError", mapOf("error" to "Failed to finalize: ${e.message}"))
                return
            }
            
            sendEvent("finalizeProgress", mapOf("progress" to 0.9))
            
            // Step 9: Validate output file
            if (!outputFile.exists() || outputFile.length() < minValidFileBytes) {
                Log.e(TAG, "[Export] ❌ Output file invalid: exists=${outputFile.exists()}, size=${outputFile.length()}")
                outputFile.delete()
                sendEvent("recordingError", mapOf("error" to "Recording file too small"))
                return
            }
            
            // Step 10: Generate thumbnail
            val thumbnailPath = generateVideoThumbnail(outputFile)
            
            // Step 11: Refresh MediaStore
            refreshMediaStore(outputFile)
            
            sendEvent("finalizeProgress", mapOf("progress" to 1.0))
            
            // Step 12: Send completion event
            val videoData = mapOf(
                "id" to recordingId,
                "filePath" to outputFile.absolutePath,
                "thumbnailPath" to thumbnailPath,
                "duration" to (totalDurationSec * 1000).toLong(),
                "resolution" to resolution,
                "fps" to fps,
                "codec" to codec,
                "preRollSeconds" to preRollSec,
                "size" to outputFile.length(),
                "timestamp" to outputFile.lastModified()
            )
            
            Log.d(TAG, "[Export] ═══════════════════════════════════════════════════════")
            Log.d(TAG, "[Export] ✅ STREAMING EXPORT COMPLETE")
            Log.d(TAG, "[Export] - File: ${outputFile.absolutePath}")
            Log.d(TAG, "[Export] - Size: ${outputFile.length() / 1024.0 / 1024.0} MB")
            Log.d(TAG, "[Export] - Duration: ${String.format("%.2f", totalDurationSec)}s")
            Log.d(TAG, "[Export] - Video samples: $videoWriteCount")
            Log.d(TAG, "[Export] - Audio samples: $audioWriteCount")
            Log.d(TAG, "[Export] ═══════════════════════════════════════════════════════")
            
            sendEvent("finalizeCompleted", mapOf("video" to videoData))
            
        } catch (e: Exception) {
            Log.e(TAG, "[Export] ❌ Export error", e)
            outputFile.delete()
            sendEvent("recordingError", mapOf("error" to "Export failed: ${e.message}"))
        }
    }
    
    // DEPRECATED: Old sync finalize approach - replaced by DVR-style background export
    @Deprecated("Use startBackgroundExport instead")
    private fun stopRecordingAndFinalize() {
        Log.w(TAG, "stopRecordingAndFinalize is DEPRECATED - using DVR-style export now")
        // No longer used - recording now uses DVR-style export via startBackgroundExport
    }

    private fun finalizeRecordingWithPreroll(liveRecordingFile: File, bufferFile: File?) {
        try {
            Log.d(TAG, "Finalizing recording with pre-roll buffer")

            // Create final output file with unique name
            val finalOutputFile = getOutputFile()
            Log.d(TAG, "Final output file: ${finalOutputFile.absolutePath}")

            if (bufferFile == null || !bufferFile.exists() || bufferFile.length() == 0L) {
                // No pre-roll buffer, just use live recording
                Log.w(TAG, "No buffer file available, using live recording only")
                
                if (liveRecordingFile.exists() && liveRecordingFile.length() > 0) {
                    liveRecordingFile.copyTo(finalOutputFile, overwrite = true)
                    liveRecordingFile.delete()
                    
                    Log.d(TAG, "Recording finalized (no buffer): ${finalOutputFile.absolutePath}, size: ${finalOutputFile.length()}")
                    sendVideoCompletedEvent(finalOutputFile)
                } else {
                    Log.e(TAG, "Live recording file is empty or doesn't exist")
                    sendEvent("recordingError", mapOf("error" to "Recording file is empty"))
                }
                return
            }

            // Concatenate buffer + live recording using MediaMuxer
            Log.d(TAG, "Concatenating buffer (${bufferFile.length()} bytes) + live recording (${liveRecordingFile.length()} bytes)")
            
            concatenateVideoFilesWithMuxer(bufferFile, liveRecordingFile, finalOutputFile)

            // Clean up temporary files
            bufferFile.delete()
            liveRecordingFile.delete()
            Log.d(TAG, "Deleted temporary files")

            Log.d(TAG, "Recording finalized with pre-roll: ${finalOutputFile.absolutePath}, size: ${finalOutputFile.length()}")
            sendVideoCompletedEvent(finalOutputFile)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to finalize recording with pre-roll", e)
            // Try to at least save the live recording
            try {
                val finalOutputFile = getOutputFile()
                if (liveRecordingFile.exists() && liveRecordingFile.length() > 0) {
                    liveRecordingFile.copyTo(finalOutputFile, overwrite = true)
                    sendVideoCompletedEvent(finalOutputFile)
                }
            } catch (fallbackError: Exception) {
                Log.e(TAG, "Fallback save also failed", fallbackError)
                sendEvent("recordingError", mapOf("error" to "Failed to save recording"))
            }
        } finally {
            resumePreviewAfterRecording()
        }
    }
    
    private fun concatenateVideoFilesWithMuxer(bufferFile: File, liveFile: File, outputFile: File) {
        try {
            // For now, use simple approach: just copy live file since proper muxing is complex
            // TODO: Implement proper frame-by-frame concatenation with MediaExtractor + MediaMuxer
            
            // Extract samples from buffer file
            val bufferExtractor = android.media.MediaExtractor()
            bufferExtractor.setDataSource(bufferFile.absolutePath)
            
            // Extract samples from live file
            val liveExtractor = android.media.MediaExtractor()
            liveExtractor.setDataSource(liveFile.absolutePath)
            
            // Create output muxer
            val muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            
            // Track indices
            val trackIndices = mutableMapOf<Int, Int>()
            
            // Add tracks from buffer file
            for (i in 0 until bufferExtractor.trackCount) {
                val format = bufferExtractor.getTrackFormat(i)
                val trackIndex = muxer.addTrack(format)
                trackIndices[i] = trackIndex
            }
            
            // Start muxer
            muxer.start()
            
            // Write buffer samples
            val bufferInfo = MediaCodec.BufferInfo()
            val buffer = ByteBuffer.allocate(1024 * 1024) // 1MB buffer
            
            for (trackIndex in 0 until bufferExtractor.trackCount) {
                bufferExtractor.selectTrack(trackIndex)
            }
            
            var lastPts = 0L
            while (true) {
                val sampleSize = bufferExtractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break
                
                val trackIndex = bufferExtractor.sampleTrackIndex
                val pts = bufferExtractor.sampleTime
                val flags = bufferExtractor.sampleFlags
                
                bufferInfo.set(0, sampleSize, pts, flags)
                muxer.writeSampleData(trackIndices[trackIndex]!!, buffer, bufferInfo)
                
                lastPts = max(lastPts, pts)
                bufferExtractor.advance()
            }
            
            Log.d(TAG, "Wrote buffer samples, last PTS: $lastPts")
            
            // Write live recording samples with adjusted timestamps
            for (trackIndex in 0 until liveExtractor.trackCount) {
                liveExtractor.selectTrack(trackIndex)
            }
            
            val ptsOffset = lastPts + 33333 // ~1 frame at 30fps to avoid overlap
            while (true) {
                val sampleSize = liveExtractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break
                
                val trackIndex = liveExtractor.sampleTrackIndex
                val pts = liveExtractor.sampleTime + ptsOffset
                val flags = liveExtractor.sampleFlags
                
                bufferInfo.set(0, sampleSize, pts, flags)
                muxer.writeSampleData(trackIndices[trackIndex]!!, buffer, bufferInfo)
                
                liveExtractor.advance()
            }
            
            Log.d(TAG, "Wrote live recording samples with offset: $ptsOffset")
            
            // Cleanup
            muxer.stop()
            muxer.release()
            bufferExtractor.release()
            liveExtractor.release()
            
            Log.d(TAG, "Concatenation complete: ${outputFile.absolutePath}, size: ${outputFile.length()}")
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to concatenate with muxer, falling back to live only", e)
            // Fallback: just copy live file
            liveFile.copyTo(outputFile, overwrite = true)
        }
    }
    
    private fun sendVideoCompletedEvent(outputFile: File) {
        val recordingId = currentRecordingId ?: UUID.randomUUID().toString()
        
        Log.d(TAG, "sendVideoCompletedEvent: Starting for ${outputFile.absolutePath}")
        Log.d(TAG, "sendVideoCompletedEvent: File exists: ${outputFile.exists()}, size: ${outputFile.length()}")

        if (!outputFile.exists()) {
            Log.e(TAG, "[Record] invalid file reference, skipping gallery insert")
            sendEvent("recordingError", mapOf("error" to "RECORDING_FILE_MISSING"))
            return
        }

        val sizeBytes = outputFile.length()
        if (sizeBytes < minValidFileBytes) {
            Log.w(TAG, "[Record] invalid file (size too small: ${sizeBytes} bytes), not adding to gallery")
            outputFile.delete()
            sendEvent("recordingError", mapOf("error" to "RECORDING_FILE_TOO_SMALL"))
            return
        }
        refreshMediaStore(outputFile)
        
        // Generate thumbnail for the video
        val thumbnailPath = generateVideoThumbnail(outputFile)
        Log.d(TAG, "sendVideoCompletedEvent: Thumbnail path result: $thumbnailPath")
        
        val videoData = mapOf(
            "id" to recordingId,
            "filePath" to outputFile.absolutePath,
            "thumbnailPath" to thumbnailPath,
            "duration" to (System.currentTimeMillis() - recordingStartTime),
            "resolution" to currentResolution,
            "fps" to currentFps,
            "codec" to currentCodec,
            "preRollSeconds" to preRollSeconds,
            "size" to outputFile.length(),
            "timestamp" to recordingStartTime
        )
        
        Log.i(TAG, "[Record] finalize SUCCESS: path=${outputFile.absolutePath}, sizeBytes=${outputFile.length()}")
        Log.d(TAG, "sendVideoCompletedEvent: Sending event with data: $videoData")
        sendEvent("finalizeCompleted", mapOf("video" to videoData))
    }
    
    private fun generateVideoThumbnail(videoFile: File): String? {
        try {
            Log.d(TAG, "==================== THUMBNAIL GENERATION START ====================")
            Log.d(TAG, "generateVideoThumbnail: Starting for ${videoFile.absolutePath}")
            Log.d(TAG, "generateVideoThumbnail: File exists: ${videoFile.exists()}, size: ${videoFile.length()}")
            
            if (!videoFile.exists()) {
                Log.e(TAG, "Video file does not exist, cannot generate thumbnail")
                return null
            }
            
            if (videoFile.length() == 0L) {
                Log.e(TAG, "Video file is empty, cannot generate thumbnail")
                return null
            }
            
            val retriever = MediaMetadataRetriever()
            
            try {
                retriever.setDataSource(videoFile.absolutePath)
                Log.d(TAG, "generateVideoThumbnail: MediaMetadataRetriever initialized successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to set data source for MediaMetadataRetriever", e)
                retriever.release()
                return null
            }
            
            // Get duration to determine best time to extract frame
            val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val duration = durationStr?.toLongOrNull() ?: 0L
            Log.d(TAG, "generateVideoThumbnail: Video duration: ${duration}ms")
            
            if (duration == 0L) {
                Log.w(TAG, "Video duration is 0, trying to extract first frame")
            }
            
            // Try to get frame at 500ms, if that fails try 0ms (first frame)
            var bitmap = retriever.getFrameAtTime(
                500_000L, // 0.5 seconds in microseconds
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            )
            
            if (bitmap == null) {
                Log.w(TAG, "Failed to get frame at 500ms, trying first frame")
                bitmap = retriever.getFrameAtTime(
                    0L,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                )
            }
            
            Log.d(TAG, "generateVideoThumbnail: Bitmap extracted: ${bitmap != null}")
            if (bitmap != null) {
                Log.d(TAG, "generateVideoThumbnail: Bitmap size: ${bitmap.width}x${bitmap.height}")
            }
            
            retriever.release()
            
            if (bitmap != null) {
                // Create thumbnail file
                val thumbDir = File(context.getExternalFilesDir(null), "thumbnails")
                Log.d(TAG, "generateVideoThumbnail: Thumbnail directory: ${thumbDir.absolutePath}")
                
                if (!thumbDir.exists()) {
                    val created = thumbDir.mkdirs()
                    Log.d(TAG, "generateVideoThumbnail: Created thumbnail directory: $created")
                }
                
                val thumbFile = File(thumbDir, "${videoFile.nameWithoutExtension}_thumb.jpg")
                Log.d(TAG, "generateVideoThumbnail: Saving to: ${thumbFile.absolutePath}")
                
                // Save bitmap as JPEG
                var success = false
                thumbFile.outputStream().use { out ->
                    success = bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                    Log.d(TAG, "generateVideoThumbnail: Bitmap compressed: $success")
                }
                bitmap.recycle()
                
                if (success && thumbFile.exists()) {
                    Log.d(TAG, "==================== THUMBNAIL GENERATED SUCCESSFULLY ====================")
                    Log.d(TAG, "Thumbnail path: ${thumbFile.absolutePath}")
                    Log.d(TAG, "Thumbnail file exists: ${thumbFile.exists()}, size: ${thumbFile.length()}")
                    return thumbFile.absolutePath
                } else {
                    Log.e(TAG, "Failed to save thumbnail file")
                    return null
                }
            } else {
                Log.w(TAG, "Failed to extract video frame for thumbnail - bitmap is null after all attempts")
                return null
            }
        } catch (e: Exception) {
            Log.e(TAG, "==================== THUMBNAIL GENERATION FAILED ====================")
            Log.e(TAG, "Error generating thumbnail", e)
            e.printStackTrace()
            return null
        }
    }

    private fun refreshMediaStore(file: File) {
        try {
            MediaScannerConnection.scanFile(
                context,
                arrayOf(file.absolutePath),
                arrayOf("video/mp4")
            ) { path, uri ->
                Log.d(TAG, "[Record] MediaStore scan complete: path=$path uri=$uri")
            }
        } catch (e: Exception) {
            Log.e(TAG, "[Record] Failed to refresh MediaStore", e)
        }
    }
    
    private fun concatenateVideoFiles(inputFiles: List<File>, outputFile: File) {
        try {
            Log.d(TAG, "Concatenating ${inputFiles.size} video files")
            
            // Verify all input files exist and are not empty
            val validFiles = inputFiles.filter { file ->
                val exists = file.exists()
                val size = if (exists) file.length() else 0
                Log.d(TAG, "Input file: ${file.name}, exists: $exists, size: $size")
                exists && size > 0
            }
            
            if (validFiles.isEmpty()) {
                Log.e(TAG, "No valid input files to concatenate")
                throw IOException("No valid input files")
            }
            
            // For now, use simple file copy of the last (live recording) file
            // TODO: Implement proper video concatenation with MediaMuxer for pre-roll support
            val mainFile = validFiles.lastOrNull()
            if (mainFile != null) {
                mainFile.copyTo(outputFile, overwrite = true)
                Log.d(TAG, "Video saved: ${outputFile.absolutePath}, size: ${outputFile.length()}")
            } else {
                throw IOException("No main recording file found")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to concatenate video files", e)
            throw e
        }
    }

    private fun setupMediaRecorder() {
        // Create a temporary file for live recording
        val timestamp = System.currentTimeMillis()
        liveRecordingFile = File(context.getExternalFilesDir(null), "live_${timestamp}.mp4")
        
        mediaRecorder = MediaRecorder().apply {
            // Set audio source FIRST
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setVideoSource(MediaRecorder.VideoSource.SURFACE)
            
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            
            setOutputFile(liveRecordingFile!!.absolutePath)
            
            // Configure video - increase bitrate for 60fps to prevent quality loss
            val bitrateFactor = if (currentFps >= 60) 2.0 else 1.0
            when (currentResolution) {
                "4K" -> {
                    setVideoSize(3840, 2160)
                    setVideoEncodingBitRate((50_000_000 * bitrateFactor).toInt())
                }
                "1080P" -> {
                    setVideoSize(1920, 1080)
                    // 60fps needs higher bitrate: 20Mbps instead of 10Mbps
                    setVideoEncodingBitRate((10_000_000 * bitrateFactor).toInt())
                }
                else -> {
                    setVideoSize(1920, 1080)
                    setVideoEncodingBitRate((8_000_000 * bitrateFactor).toInt())
                }
            }
            
            // CRITICAL: Set frame rate before encoder
            setVideoFrameRate(currentFps)
            
            // For 60fps, also set capture rate to ensure proper timing
            if (currentFps >= 60) {
                setCaptureRate(currentFps.toDouble())
                Log.d(TAG, "Set capture rate to $currentFps for high framerate recording")
            }
            
            setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            
            // Configure audio
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioEncodingBitRate(128000)
            setAudioSamplingRate(44100)
            
            prepare()
        }
        
        Log.d(TAG, "MediaRecorder configured: ${currentResolution}@${currentFps}fps, file: ${liveRecordingFile!!.absolutePath}")
    }

    private fun createRecordingSession() {
        try {
            val camera = cameraDevice ?: return
            val surfaces = mutableListOf<Surface>()
            
            // Add preview surface
            previewSurface?.let { 
                surfaces.add(it) 
                Log.d(TAG, "Added preview surface to session")
            }
            
            // Add recording surface
            mediaRecorder?.surface?.let { 
                surfaces.add(it)
                Log.d(TAG, "Added recording surface to session")
            }
            
            // Add buffer surface
            bufferImageReader?.surface?.let { 
                surfaces.add(it)
                Log.d(TAG, "Added buffer surface to session")
            }
            
            camera.createCaptureSession(surfaces, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    captureSession = session
                    
                    val builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                    
                    // Add all targets to the request
                    previewSurface?.let { builder.addTarget(it) }
                    mediaRecorder?.surface?.let { 
                        builder.addTarget(it)
                        Log.d(TAG, "Added recording surface to preview request")
                    }
                    bufferImageReader?.surface?.let { 
                        builder.addTarget(it)
                        Log.d(TAG, "Added buffer surface to preview request")
                    }
                    
                    // Configure capture request
                    builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                    
                    // Set FPS range for recording - use the proper selected range
                    val fpsRange = selectFpsRange(currentFps)
                    builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange)
                    Log.d(TAG, "Recording FPS range set to: [${fpsRange.lower}, ${fpsRange.upper}] for target $currentFps fps")
                    
                    if (stabilizationEnabled) {
                        builder.set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, 
                            CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_ON)
                    }
                    
                    val request = builder.build()
                    session.setRepeatingRequest(request, null, backgroundHandler)
                    
                    Log.d(TAG, "Preview started with recording: $isRecording, buffering: $isBuffering")
                    Log.d(TAG, "Capture session configured successfully")
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(TAG, "Failed to configure capture session")
                }
            }, backgroundHandler)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create recording session", e)
        }
    }

    private fun finalizeRecording(outputFile: File?) {
        Thread {
            try {
                val recordingId = currentRecordingId ?: return@Thread
                
                if (outputFile == null || !outputFile.exists()) {
                    Log.e(TAG, "[Record] ERROR: Output file not found: ${outputFile?.absolutePath ?: "null"}")
                    sendEvent("recordingError", mapOf("error" to "Recording file not found"))
                    currentRecordingId = null
                    recordingStartTime = 0
                    currentOutputFile = null
                    return@Thread
                }
                
                val fileSizeBytes = outputFile.length()
                val fileSizeKB = fileSizeBytes / 1024.0
                val fileSizeMB = fileSizeKB / 1024.0
                
                Log.d(TAG, "[Record] ═══════════════════════════════════════════════════════")
                Log.d(TAG, "[Record] FINALIZATION SUMMARY:")
                Log.d(TAG, "[Record] - Recording ID: $recordingId")
                Log.d(TAG, "[Record] - File path: ${outputFile.absolutePath}")
                Log.d(TAG, "[Record] - File name: ${outputFile.name}")
                Log.d(TAG, "[Record] - File exists: ${outputFile.exists()}")
                Log.d(TAG, "[Record] - File size: ${String.format("%.2f", fileSizeMB)} MB ($fileSizeBytes bytes)")
                Log.d(TAG, "[Record] - File last modified: ${outputFile.lastModified()}")
                Log.d(TAG, "[Record] - Duration: ${(System.currentTimeMillis() - recordingStartTime) / 1000.0}s")
                Log.d(TAG, "[Record] - Timestamp for video data: $recordingStartTime")
                Log.d(TAG, "[Record] ═══════════════════════════════════════════════════════")

                if (fileSizeBytes < minValidFileBytes) {
                    Log.w(TAG, "[Record] invalid file (size too small: ${fileSizeBytes} bytes), not adding to gallery")
                    outputFile.delete()
                    sendEvent("recordingError", mapOf("error" to "RECORDING_FILE_TOO_SMALL"))
                    resumePreviewAfterRecording()
                    currentRecordingId = null
                    recordingStartTime = 0
                    currentOutputFile = null
                    return@Thread
                }
                
                // Simulate finalization progress
                for (i in 1..5) {
                    Thread.sleep(200)
                    sendEvent("finalizeProgress", mapOf("progress" to (i * 0.2)))
                }

                // Generate thumbnail before sending event
                Log.d(TAG, "[Record] Generating thumbnail for finalized video")
                val thumbnailPath = generateVideoThumbnail(outputFile)
                Log.d(TAG, "[Record] Thumbnail generation result: $thumbnailPath")

                // Use file's last modified time as the definitive timestamp
                val fileTimestamp = outputFile.lastModified()
                val actualDuration = System.currentTimeMillis() - recordingStartTime

                val videoData = mapOf(
                    "id" to recordingId,
                    "filePath" to outputFile.absolutePath,
                    "thumbnailPath" to thumbnailPath,
                    "duration" to actualDuration,
                    "resolution" to currentResolution,
                    "fps" to currentFps,
                    "codec" to currentCodec,
                    "preRollSeconds" to preRollSeconds,
                    "size" to outputFile.length(),
                    "timestamp" to fileTimestamp  // Use file's actual timestamp, not recordingStartTime
                )

                Log.d(TAG, "[Record] Video data being sent:")
                Log.d(TAG, "[Record]   - id: $recordingId")
                Log.d(TAG, "[Record]   - filePath: ${outputFile.absolutePath}")
                Log.d(TAG, "[Record]   - thumbnailPath: $thumbnailPath")
                Log.d(TAG, "[Record]   - timestamp: $fileTimestamp (file modified time)")
                Log.d(TAG, "[Record]   - size: ${outputFile.length()} bytes")
                Log.d(TAG, "[Record] Sending finalizeCompleted event")

                refreshMediaStore(outputFile)
                Log.i(TAG, "[Record] finalize SUCCESS: path=${outputFile.absolutePath}, sizeBytes=${outputFile.length()}")
                sendEvent("finalizeCompleted", mapOf("video" to videoData))
                
                // Reset recording state
                currentRecordingId = null
                recordingStartTime = 0
                currentOutputFile = null
                
                // Restart preview session
                resumePreviewAfterRecording()
                
            } catch (e: Exception) {
                Log.e(TAG, "[Record] finalize ERROR", e)
                sendEvent("recordingError", mapOf("error" to "Failed to save recording: ${e.message}"))
            }
        }.start()
    }

    private fun resumePreviewAfterRecording() {
        backgroundHandler?.post {
            if (!isRecording) {
                try {
                    // If buffer was running before recording, recreate buffer session
                    // Otherwise just recreate preview session
                    if (isBuffering) {
                        Log.d(TAG, "Resuming buffer session after recording")
                        createBufferPreviewSession()
                    } else {
                        Log.d(TAG, "Resuming preview session after recording")
                        createCameraPreviewSession()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to resume preview after recording", e)
                }
            }
        }
    }

    private fun getOutputFile(): File {
        // Generate unique filename using human-readable timestamp for testing
        val timestamp = System.currentTimeMillis()
        val dateFormat = java.text.SimpleDateFormat("yyyy-MM-dd_HH-mm-ss-SSS", java.util.Locale.US)
        val dateStr = dateFormat.format(java.util.Date(timestamp))
        val uniqueId = UUID.randomUUID().toString().take(6)
        val fileName = "rec_${dateStr}_${uniqueId}.mp4"
        val file = File(context.getExternalFilesDir(null), fileName)
        Log.d(TAG, "[Record] Generated output file: ${file.name}")
        return file
    }

    private fun switchCamera(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "🔄 switchCamera called: isBuffering=$isBuffering, isBufferInitialized=$isBufferInitialized")
            Log.d(TAG, "🔄 Current settings: resolution=$currentResolution, fps=$currentFps")
            
            val wasBuffering = isBuffering
            val wasBufferInitialized = isBufferInitialized
            val oldCameraFacing = cameraFacing
            
            cameraFacing = if (cameraFacing == CameraCharacteristics.LENS_FACING_BACK) {
                CameraCharacteristics.LENS_FACING_FRONT
            } else {
                CameraCharacteristics.LENS_FACING_BACK
            }
            
            val isSwitchingToFront = isFrontCamera()
            Log.d(TAG, "🔄 New camera facing: ${if (isSwitchingToFront) "FRONT" else "BACK"}")
            
            // Log resolution change for front camera
            if (isSwitchingToFront) {
                Log.d(TAG, "🔄 FRONT CAMERA: Will use 720p@30fps (overriding user setting: ${currentResolution}@${currentFps}fps)")
            } else {
                Log.d(TAG, "🔄 BACK CAMERA: Will use user settings ${currentResolution}@${currentFps}fps")
            }
            
            // CRITICAL: If buffer was active, we need to stop encoders before switching cameras
            // The encoder surfaces are tied to the old camera session and can't be reused
            if (wasBuffering && wasBufferInitialized) {
                Log.d(TAG, "🔄 Buffer active - stopping encoders before camera switch")
                
                // Stop audio capture first
                isAudioCapturing = false
                
                // Stop and release video encoder
                try {
                    videoEncoder?.stop()
                } catch (e: Exception) {
                    Log.w(TAG, "Error stopping video encoder: ${e.message}")
                }
                try {
                    videoEncoder?.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Error releasing video encoder: ${e.message}")
                }
                videoEncoder = null
                
                // Release video encoder surface
                try {
                    videoEncoderSurface?.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Error releasing video encoder surface: ${e.message}")
                }
                videoEncoderSurface = null
                
                // Stop and release audio encoder
                try {
                    audioRecord?.stop()
                } catch (e: Exception) {
                    Log.w(TAG, "Error stopping audio record: ${e.message}")
                }
                try {
                    audioRecord?.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Error releasing audio record: ${e.message}")
                }
                audioRecord = null
                
                try {
                    audioEncoder?.stop()
                } catch (e: Exception) {
                    Log.w(TAG, "Error stopping audio encoder: ${e.message}")
                }
                try {
                    audioEncoder?.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Error releasing audio encoder: ${e.message}")
                }
                audioEncoder = null
                
                // Quit encoder threads
                try {
                    encoderThread?.quitSafely()
                    encoderThread?.join(300)
                } catch (e: Exception) {
                    Log.w(TAG, "Error stopping encoder thread: ${e.message}")
                }
                encoderThread = null
                encoderHandler = null
                
                try {
                    audioThread?.quitSafely()
                    audioThread?.join(300)
                } catch (e: Exception) {
                    Log.w(TAG, "Error stopping audio thread: ${e.message}")
                }
                audioThread = null
                audioHandler = null
                
                // Clear buffer and reset initialization flag
                rollingBuffer.clear()
                isBufferInitialized = false
                
                Log.d(TAG, "🔄 Encoders and threads stopped and released")
            }
            
            closeCamera()
            
            // Update camera characteristics for the new camera
            cameraCharacteristics = null
            
            openCamera()
            
            // If buffer was active, reinitialize it after camera switch
            if (wasBuffering) {
                Log.d(TAG, "🔄 Reinitializing buffer for new camera")
                // Post to background handler to allow camera to open first
                backgroundHandler?.postDelayed({
                    try {
                        // Reinitialize the buffer with new encoders for the new camera
                        initializeContinuousBuffer()
                        Log.d(TAG, "🔄 Buffer reinitialized successfully for new camera")
                    } catch (e: Exception) {
                        Log.e(TAG, "🔄 Failed to reinitialize buffer: ${e.message}")
                    }
                }, 500) // Give camera time to open and create session
            }
            
            result.success(null)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to switch camera", e)
            result.error("SWITCH_ERROR", "Failed to switch camera: ${e.message}", null)
        }
    }

    private fun setFlashMode(call: MethodCall, result: MethodChannel.Result) {
        try {
            flashMode = call.argument<String>("mode") ?: "off"
            updatePreview()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set flash mode", e)
            result.error("FLASH_ERROR", "Failed to set flash mode: ${e.message}", null)
        }
    }

    private fun initializeZoomCapabilities(characteristics: CameraCharacteristics) {
        try {
            val maxZoomValue = characteristics.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM)
            maxZoom = maxZoomValue ?: 1.0f
            minZoom = 1.0f
            currentZoomLevel = 1.0f
            Log.d(TAG, "🔍 Zoom capabilities initialized: min=$minZoom, max=$maxZoom")
            Log.d(TAG, "🔍 Zoom range available: ${if (maxZoom > 1.0f) "YES" else "NO"}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to initialize zoom capabilities", e)
            maxZoom = 1.0f
            minZoom = 1.0f
            currentZoomLevel = 1.0f
        }
    }

    private fun setZoom(call: MethodCall, result: MethodChannel.Result) {
        try {
            val zoomLevel = call.argument<Double>("zoom")?.toFloat() ?: 1.0f
            Log.d(TAG, "🔍 setZoom called: requested=$zoomLevel, min=$minZoom, max=$maxZoom")
            currentZoomLevel = zoomLevel.coerceIn(minZoom, maxZoom)
            Log.d(TAG, "🔍 setZoom: clamped zoom level=$currentZoomLevel")
            applyZoom()
            Log.d(TAG, "🔍 setZoom: zoom applied successfully, returning $currentZoomLevel")
            result.success(currentZoomLevel.toDouble())
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to set zoom", e)
            result.error("ZOOM_ERROR", "Failed to set zoom: ${e.message}", null)
        }
    }

    private fun getMaxZoom(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "🔍 getMaxZoom called: returning maxZoom=$maxZoom")
            result.success(maxZoom.toDouble())
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to get max zoom", e)
            result.error("ZOOM_ERROR", "Failed to get max zoom: ${e.message}", null)
        }
    }

    private fun applyZoom() {
        try {
            Log.d(TAG, "🔍 applyZoom: Starting, currentZoomLevel=$currentZoomLevel")
            
            val characteristics = cameraCharacteristics
            if (characteristics == null) {
                Log.w(TAG, "🔍 applyZoom: characteristics is null, returning")
                return
            }
            
            val session = captureSession
            if (session == null) {
                Log.w(TAG, "🔍 applyZoom: captureSession is null, returning")
                return
            }
            
            val builder = previewRequestBuilder
            if (builder == null) {
                Log.w(TAG, "🔍 applyZoom: previewRequestBuilder is null, returning")
                return
            }

            // Get the active sensor array size
            val sensorArraySize = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
            if (sensorArraySize == null) {
                Log.w(TAG, "🔍 applyZoom: sensorArraySize is null, returning")
                return
            }

            Log.d(TAG, "🔍 applyZoom: sensorArraySize=$sensorArraySize")

            // Calculate crop region for zoom
            val cropWidth = sensorArraySize.width() / currentZoomLevel
            val cropHeight = sensorArraySize.height() / currentZoomLevel
            val cropLeft = ((sensorArraySize.width() - cropWidth) / 2).toInt()
            val cropTop = ((sensorArraySize.height() - cropHeight) / 2).toInt()

            val cropRegion = android.graphics.Rect(
                cropLeft,
                cropTop,
                (cropLeft + cropWidth).toInt(),
                (cropTop + cropHeight).toInt()
            )

            Log.d(TAG, "🔍 applyZoom: cropRegion=$cropRegion")

            // CRITICAL FIX: Ensure encoder surface is added if buffering/recording
            // Note: We don't remove targets, just ensure encoder surface is present
            if (isBuffering || isRecording) {
                videoEncoderSurface?.let { 
                    builder.addTarget(it)
                    Log.d(TAG, "🔍 applyZoom: Ensured video encoder surface is in targets for continuous encoding")
                }
            }

            // Apply crop region to the request builder
            builder.set(CaptureRequest.SCALER_CROP_REGION, cropRegion)

            // Update the repeating request
            previewRequest = builder.build()
            session.setRepeatingRequest(previewRequest!!, null, backgroundHandler)

            Log.d(TAG, "✅ Zoom applied successfully: level=$currentZoomLevel, cropRegion=$cropRegion")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to apply zoom", e)
            e.printStackTrace()
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FOCUS CONTROL - Tap to focus and focus lock
    // ═══════════════════════════════════════════════════════════════════════════════

    /**
     * Set focus point at normalized coordinates (0.0-1.0).
     * Triggers auto-focus at the specified point.
     */
    private fun setFocusPoint(call: MethodCall, result: MethodChannel.Result) {
        try {
            val x = call.argument<Double>("x")?.toFloat() ?: 0.5f
            val y = call.argument<Double>("y")?.toFloat() ?: 0.5f
            
            focusPointX = x.coerceIn(0f, 1f)
            focusPointY = y.coerceIn(0f, 1f)
            
            Log.d(TAG, "📍 setFocusPoint: ($focusPointX, $focusPointY)")
            
            val success = triggerFocusAtPoint(focusPointX, focusPointY, lockAfterFocus = false)
            result.success(success)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to set focus point", e)
            result.error("FOCUS_ERROR", "Failed to set focus point: ${e.message}", null)
        }
    }

    /**
     * Lock focus at the current focus point or a specified point.
     */
    private fun lockFocus(call: MethodCall, result: MethodChannel.Result) {
        try {
            // If coordinates provided, focus there first
            call.argument<Double>("x")?.let { x ->
                call.argument<Double>("y")?.let { y ->
                    focusPointX = x.toFloat().coerceIn(0f, 1f)
                    focusPointY = y.toFloat().coerceIn(0f, 1f)
                }
            }
            
            Log.d(TAG, "🔒 lockFocus at: ($focusPointX, $focusPointY)")
            
            val success = triggerFocusAtPoint(focusPointX, focusPointY, lockAfterFocus = true)
            if (success) {
                isFocusLocked = true
            }
            result.success(success)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to lock focus", e)
            result.error("FOCUS_ERROR", "Failed to lock focus: ${e.message}", null)
        }
    }

    /**
     * Unlock focus and return to continuous auto-focus mode.
     */
    private fun unlockFocus(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "🔓 unlockFocus")
            
            val success = resetToContinuousAutoFocus()
            if (success) {
                isFocusLocked = false
            }
            result.success(success)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to unlock focus", e)
            result.error("FOCUS_ERROR", "Failed to unlock focus: ${e.message}", null)
        }
    }

    /**
     * Trigger auto-focus at a specific point on the sensor.
     * @param x Normalized x coordinate (0-1)
     * @param y Normalized y coordinate (0-1)
     * @param lockAfterFocus If true, focus will be locked after focusing
     */
    private fun triggerFocusAtPoint(x: Float, y: Float, lockAfterFocus: Boolean): Boolean {
        val characteristics = cameraCharacteristics ?: run {
            Log.e(TAG, "❌ triggerFocusAtPoint: cameraCharacteristics is null")
            return false
        }
        val session = captureSession ?: run {
            Log.e(TAG, "❌ triggerFocusAtPoint: captureSession is null")
            return false
        }
        val builder = previewRequestBuilder ?: run {
            Log.e(TAG, "❌ triggerFocusAtPoint: previewRequestBuilder is null")
            return false
        }
        
        // Check if the device supports AF regions
        val maxAfRegions = characteristics.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AF) ?: 0
        Log.d(TAG, "📍 Device supports $maxAfRegions AF regions")
        
        if (maxAfRegions == 0) {
            Log.w(TAG, "Device doesn't support AF regions, using simple trigger")
            return triggerSimpleFocus(lockAfterFocus)
        }
        
        // Get sensor array size for coordinate mapping
        val sensorArraySize = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
            ?: run {
                Log.e(TAG, "❌ triggerFocusAtPoint: sensorArraySize is null")
                return false
            }
        
        // Account for current zoom crop region
        val cropRegion = builder.get(CaptureRequest.SCALER_CROP_REGION) ?: sensorArraySize
        
        // Calculate focus region size (use ~5% of crop region for more precise focus area)
        val focusRegionWidth = (cropRegion.width() * 0.05f).toInt().coerceAtLeast(50)
        val focusRegionHeight = (cropRegion.height() * 0.05f).toInt().coerceAtLeast(50)
        
        // Map normalized coordinates to crop region
        val focusCenterX = cropRegion.left + (x * cropRegion.width()).toInt()
        val focusCenterY = cropRegion.top + (y * cropRegion.height()).toInt()
        
        // Create focus region rectangle, clamped to sensor bounds
        val focusLeft = (focusCenterX - focusRegionWidth / 2).coerceIn(sensorArraySize.left, sensorArraySize.right - focusRegionWidth)
        val focusTop = (focusCenterY - focusRegionHeight / 2).coerceIn(sensorArraySize.top, sensorArraySize.bottom - focusRegionHeight)
        val focusRight = (focusLeft + focusRegionWidth).coerceAtMost(sensorArraySize.right)
        val focusBottom = (focusTop + focusRegionHeight).coerceAtMost(sensorArraySize.bottom)
        
        val focusRegion = android.graphics.Rect(focusLeft, focusTop, focusRight, focusBottom)
        val meteringRectangle = android.hardware.camera2.params.MeteringRectangle(
            focusRegion,
            android.hardware.camera2.params.MeteringRectangle.METERING_WEIGHT_MAX
        )
        
        Log.d(TAG, "📍 Focus region: $focusRegion (sensor: $sensorArraySize, crop: $cropRegion)")
        Log.d(TAG, "📍 Focus center: ($focusCenterX, $focusCenterY), normalized: ($x, $y)")
        
        try {
            // Step 1: Set AF regions on the builder
            builder.set(CaptureRequest.CONTROL_AF_REGIONS, arrayOf(meteringRectangle))
            
            // Also set AE regions for exposure metering at the same point
            val maxAeRegions = characteristics.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AE) ?: 0
            if (maxAeRegions > 0) {
                builder.set(CaptureRequest.CONTROL_AE_REGIONS, arrayOf(meteringRectangle))
                Log.d(TAG, "📍 AE regions also set")
            }
            
            // Step 2: Set AF mode to AUTO (required for AF_TRIGGER to work)
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_AUTO)
            
            // Step 3: First, cancel any ongoing AF
            builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_CANCEL)
            session.capture(builder.build(), null, backgroundHandler)
            Log.d(TAG, "📍 AF cancel sent")
            
            // Step 4: Update repeating request with new AF regions (important!)
            builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
            previewRequest = builder.build()
            session.setRepeatingRequest(previewRequest!!, null, backgroundHandler)
            Log.d(TAG, "📍 Repeating request updated with AF regions")
            
            // Step 5: Trigger AF start
            builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_START)
            session.capture(builder.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(
                    session: CameraCaptureSession,
                    request: CaptureRequest,
                    captureResult: TotalCaptureResult
                ) {
                    val afState = captureResult.get(CaptureResult.CONTROL_AF_STATE)
                    Log.d(TAG, "📍 AF trigger sent, initial state: $afState")
                }
            }, backgroundHandler)
            
            // Step 6: Reset trigger to IDLE and optionally return to continuous AF
            backgroundHandler?.postDelayed({
                try {
                    builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
                    
                    if (!lockAfterFocus && !isFocusLocked) {
                        // Return to continuous AF after 3 seconds
                        backgroundHandler?.postDelayed({
                            try {
                                if (!isFocusLocked) {
                                    builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                                    builder.set(CaptureRequest.CONTROL_AF_REGIONS, null)
                                    builder.set(CaptureRequest.CONTROL_AE_REGIONS, null)
                                    previewRequest = builder.build()
                                    captureSession?.setRepeatingRequest(previewRequest!!, null, backgroundHandler)
                                    Log.d(TAG, "📍 Returned to continuous AF")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed to return to continuous AF", e)
                            }
                        }, 2500)
                    } else {
                        // Keep focus locked - just update the repeating request
                        previewRequest = builder.build()
                        captureSession?.setRepeatingRequest(previewRequest!!, null, backgroundHandler)
                        Log.d(TAG, "📍 Focus locked at point")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to reset AF trigger", e)
                }
            }, 500)
            
            Log.d(TAG, "✅ Focus trigger initiated successfully")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to trigger focus at point", e)
            e.printStackTrace()
            return false
        }
    }

    /**
     * Simple focus trigger for devices that don't support AF regions.
     */
    private fun triggerSimpleFocus(lockAfterFocus: Boolean): Boolean {
        val session = captureSession ?: return false
        val builder = previewRequestBuilder ?: return false
        
        try {
            // Set AF mode to AUTO
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_AUTO)
            
            // Cancel any ongoing AF
            builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_CANCEL)
            session.capture(builder.build(), null, backgroundHandler)
            
            // Update repeating request with AUTO mode
            builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
            previewRequest = builder.build()
            session.setRepeatingRequest(previewRequest!!, null, backgroundHandler)
            
            // Trigger AF start
            builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_START)
            session.capture(builder.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(
                    session: CameraCaptureSession,
                    request: CaptureRequest,
                    captureResult: TotalCaptureResult
                ) {
                    val afState = captureResult.get(CaptureResult.CONTROL_AF_STATE)
                    Log.d(TAG, "📍 Simple AF trigger sent, state: $afState")
                }
            }, backgroundHandler)
            
            // Reset trigger and optionally return to continuous
            backgroundHandler?.postDelayed({
                try {
                    builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
                    
                    if (!lockAfterFocus && !isFocusLocked) {
                        backgroundHandler?.postDelayed({
                            try {
                                if (!isFocusLocked) {
                                    builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                                    previewRequest = builder.build()
                                    captureSession?.setRepeatingRequest(previewRequest!!, null, backgroundHandler)
                                    Log.d(TAG, "📍 Returned to continuous AF (simple)")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Failed to return to continuous AF", e)
                            }
                        }, 2500)
                    } else {
                        previewRequest = builder.build()
                        captureSession?.setRepeatingRequest(previewRequest!!, null, backgroundHandler)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to reset AF trigger", e)
                }
            }, 500)
            
            Log.d(TAG, "✅ Simple focus trigger initiated")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to trigger simple focus", e)
            return false
        }
    }

    /**
     * Reset to continuous auto-focus mode.
     */
    private fun resetToContinuousAutoFocus(): Boolean {
        val session = captureSession ?: return false
        val builder = previewRequestBuilder ?: return false
        
        try {
            // Clear focus regions
            builder.set(CaptureRequest.CONTROL_AF_REGIONS, null)
            builder.set(CaptureRequest.CONTROL_AE_REGIONS, null)
            
            // Set continuous AF mode
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_CANCEL)
            
            // Apply changes
            session.capture(builder.build(), null, backgroundHandler)
            
            builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
            previewRequest = builder.build()
            session.setRepeatingRequest(previewRequest!!, null, backgroundHandler)
            
            Log.d(TAG, "🔓 Reset to continuous auto-focus")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reset to continuous AF", e)
            return false
        }
    }

    private fun updateSettings(call: MethodCall, result: MethodChannel.Result) {
        try {
            var needsPreviewUpdate = false
            var resolutionChanged = false
            var fpsChanged = false
            
            call.argument<String>("resolution")?.let { 
                currentResolution = it
                resolutionChanged = true
                needsPreviewUpdate = true
            }
            call.argument<Int>("fps")?.let { 
                currentFps = it
                fpsChanged = true
                needsPreviewUpdate = true // FPS change requires preview update
                // CRITICAL: Update video delta when FPS changes
                updateVideoDelta()
            }
            call.argument<String>("codec")?.let { currentCodec = it }
            call.argument<Int>("preRollSeconds")?.let { 
                preRollSeconds = it
                // Update buffer duration if currently buffering
                if (isBuffering) {
                    selectedBufferSeconds = preRollSeconds
                    val bufferDurationUs = (selectedBufferSeconds * 1_000_000).toLong()
                    rollingBuffer.updateMaxDuration(bufferDurationUs)
                    Log.d(TAG, "📝 Updated buffer duration to ${selectedBufferSeconds}s while buffering")
                }
            }
            call.argument<Boolean>("stabilization")?.let { 
                stabilizationEnabled = it
                needsPreviewUpdate = true // Stabilization change requires preview update
            }
            
            applyCaptureProfileFromCurrentState()

            if (resolutionChanged || needsPreviewUpdate) {
                updatePreviewDefaults()
            }
            
            // Recreate session to apply new FPS or stabilization settings
            if (needsPreviewUpdate && captureSession != null) {
                // Close current session first
                captureSession?.close()
                captureSession = null
                
                // If FPS or resolution changed, we need to re-initialize the video encoder
                if (fpsChanged || resolutionChanged) {
                    Log.d(TAG, "⚙️ FPS/Resolution changed - reinitializing video encoder for ${currentResolution}@${currentFps}fps")
                    releaseVideoEncoder()
                    initializeVideoEncoder()
                }
                
                // Recreate the appropriate session based on current mode
                if (isBuffering) {
                    Log.d(TAG, "Recreating buffer preview session with new FPS: $currentFps, videoDeltaUs: ${videoDeltaUs}µs")
                    createBufferPreviewSession()
                } else {
                    Log.d(TAG, "Recreating preview session with new FPS: $currentFps")
                    createCameraPreviewSession()
                }
            }
            
            sendEvent("settingsUpdated", null)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update settings", e)
            result.error("SETTINGS_ERROR", "Failed to update settings: ${e.message}", null)
        }
    }

    private fun checkDetailedCapabilities(result: MethodChannel.Result) {
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                val characteristics = cameraManager.getCameraCharacteristics(id)
                characteristics.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: run {
                result.success(hashMapOf(
                    "supports4K" to false,
                    "supports1080p60fps" to false,
                    "supports4K60fps" to false,
                    "supports1080p30fps" to true
                ))
                return
            }
            
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val streamConfigMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            
            if (streamConfigMap == null) {
                Log.e(TAG, "Stream configuration map is null")
                result.success(hashMapOf(
                    "supports4K" to false,
                    "supports1080p60fps" to false,
                    "supports4K60fps" to false,
                    "supports1080p30fps" to true
                ))
                return
            }
            
            // Get all supported sizes for MediaRecorder
            val outputSizes = streamConfigMap.getOutputSizes(MediaRecorder::class.java)
            
            // Check for 4K support (3840x2160)
            val supports4K = outputSizes?.any { size ->
                size.width == 3840 && size.height == 2160
            } ?: false
            
            // Check for 1080p support (1920x1080)
            val supports1080p = outputSizes?.any { size ->
                size.width == 1920 && size.height == 1080
            } ?: false
            
            Log.d(TAG, "Available sizes: ${outputSizes?.joinToString { "${it.width}x${it.height}" }}")
            
            // Get FPS ranges
            val normalFpsRanges = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
            
            Log.d(TAG, "Normal FPS ranges: ${normalFpsRanges?.joinToString { "[${it.lower}, ${it.upper}]" }}")
            
            // Check 60fps support - look for ranges where upper bound is at least 60
            // A range like [60,60] or [30,60] indicates 60fps support
            val has60fpsRange = normalFpsRanges?.any { range ->
                range.upper >= 60
            } ?: false
            
            // Also check high-speed video sizes for 60fps support
            val highSpeedSizes = try {
                streamConfigMap.highSpeedVideoSizes?.toList() ?: emptyList()
            } catch (e: Exception) {
                emptyList()
            }
            
            val highSpeedFpsRanges1080p = try {
                val size1080p = android.util.Size(1920, 1080)
                if (highSpeedSizes.any { it.width == 1920 && it.height == 1080 }) {
                    streamConfigMap.getHighSpeedVideoFpsRangesFor(size1080p)?.toList() ?: emptyList()
                } else {
                    emptyList()
                }
            } catch (e: Exception) {
                emptyList()
            }
            
            val highSpeedFpsRanges4K = try {
                val size4K = android.util.Size(3840, 2160)
                if (highSpeedSizes.any { it.width == 3840 && it.height == 2160 }) {
                    streamConfigMap.getHighSpeedVideoFpsRangesFor(size4K)?.toList() ?: emptyList()
                } else {
                    emptyList()
                }
            } catch (e: Exception) {
                emptyList()
            }
            
            Log.d(TAG, "High-speed video sizes: ${highSpeedSizes.joinToString { "${it.width}x${it.height}" }}")
            Log.d(TAG, "High-speed 1080p FPS ranges: ${highSpeedFpsRanges1080p.joinToString { "[${it.lower}, ${it.upper}]" }}")
            Log.d(TAG, "High-speed 4K FPS ranges: ${highSpeedFpsRanges4K.joinToString { "[${it.lower}, ${it.upper}]" }}")
            
            // Determine 60fps support for each resolution
            // ONLY check normal FPS ranges - high-speed capture requires a different API
            // that we don't support yet. High-speed ranges are logged for reference only.
            // Device must have 60fps in NORMAL capture mode, not just high-speed mode.
            val supports1080p60fpsFromRanges = has60fpsRange
            val supports4K60fpsFromRanges = has60fpsRange
            
            Log.d(TAG, "60fps from normal ranges: $has60fpsRange (high-speed only NOT counted)")
            Log.d(TAG, "High-speed 1080p has 60fps: ${highSpeedFpsRanges1080p.any { it.upper >= 60 }} (requires constrainedHighSpeedCaptureSession)")
            Log.d(TAG, "High-speed 4K has 60fps: ${highSpeedFpsRanges4K.any { it.upper >= 60 }} (requires constrainedHighSpeedCaptureSession)")
            
            var supports1080p60fps = supports1080p && supports1080p60fpsFromRanges
            var supports4K60fps = supports4K && supports4K60fpsFromRanges
            
            // Additional verification with MediaCodec capabilities
            if (supports1080p60fps) {
                supports1080p60fps = checkMediaRecorderSupport(1920, 1080, 60)
            }
            
            if (supports4K60fps) {
                supports4K60fps = checkMediaRecorderSupport(3840, 2160, 60)
            }
            
            val capabilities = hashMapOf<String, Boolean>(
                "supports4K" to supports4K,
                "supports1080p60fps" to supports1080p60fps,
                "supports4K60fps" to supports4K60fps,
                "supports1080p30fps" to supports1080p
            )
            
            Log.d(TAG, "✅ Final capabilities (normal capture mode only): $capabilities")
            Log.d(TAG, "   Note: High-speed capture (120fps+) requires different API and is not supported")
            result.success(capabilities)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error checking detailed capabilities", e)
            result.success(hashMapOf(
                "supports4K" to false,
                "supports1080p60fps" to false,
                "supports4K60fps" to false,
                "supports1080p30fps" to true
            ))
        }
    }

    private fun checkMediaRecorderSupport(width: Int, height: Int, fps: Int): Boolean {
        return try {
            // For 60fps, check if the ENCODER can handle it
            // Note: Camera FPS capability is checked separately via normal FPS ranges
            // High-speed profiles are NOT used since they require constrainedHighSpeedCaptureSession
            if (fps == 60) {
                // Skip high-speed profile check - we don't support high-speed capture mode
                // Only check MediaCodec encoder capabilities
                val codecSupports60fps = try {
                    val codecList = android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS)
                    val mimeType = "video/avc" // H.264
                    var supports = false
                    
                    for (codecInfo in codecList.codecInfos) {
                        if (!codecInfo.isEncoder) continue
                        
                        try {
                            val capabilities = codecInfo.getCapabilitiesForType(mimeType)
                            val videoCapabilities = capabilities.videoCapabilities
                            
                            if (videoCapabilities != null) {
                                // Check if this resolution and framerate is supported
                                val supportedFrameRates = videoCapabilities.getSupportedFrameRatesFor(width, height)
                                if (supportedFrameRates != null && supportedFrameRates.upper >= fps) {
                                    Log.d(TAG, "✅ ${codecInfo.name} supports ${width}x${height}@${fps}fps (range: ${supportedFrameRates.lower}-${supportedFrameRates.upper})")
                                    supports = true
                                    break
                                }
                            }
                        } catch (e: Exception) {
                            // This codec doesn't support the mime type
                            continue
                        }
                    }
                    supports
                } catch (e: Exception) {
                    Log.w(TAG, "MediaCodec capability check failed: ${e.message}")
                    false
                }
                
                Log.d(TAG, "60fps encoder check for ${width}x${height}: codecSupports=$codecSupports60fps")
                Log.d(TAG, "Note: Camera must also support 60fps in NORMAL mode (not high-speed) for this to work")
                return codecSupports60fps
            }
            
            // For 30fps, just check basic support
            true
        } catch (e: Exception) {
            Log.w(TAG, "❌ Capability test failed for ${width}x${height}@${fps}fps: ${e.message}")
            false
        }
    }

    private fun getDeviceCapabilities(result: MethodChannel.Result) {
        try {
            val totalRamMb = getTotalRamMb()
            val ramTier = classifyRamTier(totalRamMb)

            val characteristics = ensureCameraCharacteristics()
            val supportedResolutions = collectSupportedResolutions(characteristics)
            val supportedFpsValues = collectSupportedFps(characteristics)
            val supportedCodecs = collectSupportedCodecs()
            val preferredBufferMode = resolveBufferModeForTier(ramTier)

            val capabilities = hashMapOf<String, Any>(
                "ramMB" to totalRamMb,
                "supportedResolutions" to ArrayList(supportedResolutions),
                "supportedFps" to ArrayList(supportedFpsValues),
                "supportedCodecs" to ArrayList(supportedCodecs),
                "deviceTier" to ramTier,
                "preferredBufferMode" to preferredBufferMode
            )

            Log.i(
                TAG,
                "[DeviceTier][$ramTier] RAM=${totalRamMb}MB buffer=$preferredBufferMode res=$supportedResolutions fps=$supportedFpsValues codecs=$supportedCodecs"
            )

            result.success(capabilities)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get device capabilities", e)
            result.error("CAPABILITIES_ERROR", "Failed to get capabilities: ${e.message}", null)
        }
    }

    private fun closeCamera() {
        try {
            cameraOpenCloseLock.acquire()
            captureSession?.close()
            captureSession = null
            cameraDevice?.close()
            cameraDevice = null
            bufferImageReader?.close()
            bufferImageReader = null
        } catch (e: InterruptedException) {
            throw RuntimeException("Interrupted while trying to lock camera closing.", e)
        } finally {
            cameraOpenCloseLock.release()
        }
    }

    private fun ensureCameraCharacteristics(): CameraCharacteristics? {
        if (cameraCharacteristics != null) return cameraCharacteristics
        return try {
            val cameraId = getCameraId()
            val characteristics = cameraManager?.getCameraCharacteristics(cameraId)
            cameraCharacteristics = characteristics
            characteristics
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load camera characteristics", e)
            null
        }
    }

    private fun collectSupportedResolutions(characteristics: CameraCharacteristics?): List<String> {
        val buckets = linkedSetOf<String>()
        val streamConfig = characteristics?.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val sizes = streamConfig?.getOutputSizes(MediaRecorder::class.java)
            ?: streamConfig?.getOutputSizes(SurfaceTexture::class.java)

        sizes?.forEach { size ->
            when {
                size.width >= 3800 || size.height >= 2100 -> buckets.add("4K")
                size.width >= 1900 || size.height >= 1050 -> buckets.add("1080P")
                size.width >= 1200 || size.height >= 700 -> buckets.add("720P")
            }
        }

        if (buckets.isEmpty()) {
            buckets.add("1080P")
            buckets.add("720P")
        }

        val preferredOrder = listOf("4K", "1080P", "720P")
        return buckets.sortedWith(compareBy { value ->
            val index = preferredOrder.indexOf(value)
            if (index >= 0) index else preferredOrder.size
        })
    }

    private fun collectSupportedFps(characteristics: CameraCharacteristics?): List<Int> {
        val ranges = characteristics?.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
        val fpsSet = sortedSetOf<Int>()

        Log.d(TAG, "[FPS Detection] Raw FPS ranges from device: ${ranges?.joinToString { "[${it.lower}, ${it.upper}]" }}")

        ranges?.forEach { range ->
            // Add exact upper FPS value if it's in common recording values
            val upperFps = range.upper
            when {
                upperFps >= 60 -> {
                    fpsSet.add(60)
                    if (upperFps >= 120) fpsSet.add(120)
                }
                upperFps >= 30 -> fpsSet.add(30)
                upperFps >= 24 -> fpsSet.add(24)
            }
        }

        if (fpsSet.isEmpty()) {
            fpsSet.add(30)
        }

        Log.d(TAG, "[FPS Detection] Supported FPS values: $fpsSet")
        return fpsSet.toList()
    }

    private fun collectSupportedCodecs(): List<String> {
        val codecs = linkedSetOf("H.264")
        try {
            val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
            codecList.codecInfos.filter { it.isEncoder }.forEach { info ->
                info.supportedTypes.forEach { type ->
                    when (type) {
                        MediaFormat.MIMETYPE_VIDEO_HEVC -> codecs.add("HEVC")
                        MediaFormat.MIMETYPE_VIDEO_AVC -> codecs.add("H.264")
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to enumerate codecs", e)
        }

        return codecs.toList()
    }

    private fun getTotalRamMb(): Int {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            (memoryInfo.totalMem / (1024 * 1024)).toInt()
        } catch (e: Exception) {
            Log.w(TAG, "Unable to read total RAM", e)
            4096
        }
    }

    private fun classifyRamTier(ramMb: Int): String = when {
        ramMb >= 6144 -> "high"
        ramMb >= 3072 -> "mid"
        else -> "low"
    }

    private fun resolveBufferModeForTier(ramTier: String): String = if (ramTier == "high") "ram" else "disk"

    private fun selectAutoResolution(ramTier: String, options: List<String>): String {
        return when (ramTier) {
            "high" -> options.firstOrNull() ?: "1080P"
            "mid" -> when {
                options.contains("1080P") -> "1080P"
                else -> options.lastOrNull() ?: "1080P"
            }
            else -> when {
                options.contains("720P") -> "720P"
                options.contains("1080P") -> "1080P"
                else -> options.lastOrNull() ?: "720P"
            }
        }
    }

    private fun applyCaptureProfileFromCurrentState() {
        val profile = selectCaptureProfile(
            requestedResolution = currentResolution,
            requestedFps = currentFps,
            requestedCodec = currentCodec,
            requestedPreRollSeconds = preRollSeconds
        )
        applyCaptureProfile(profile)
    }

    private fun selectCaptureProfile(
        requestedResolution: String,
        requestedFps: Int,
        requestedCodec: String,
        requestedPreRollSeconds: Int
    ): CaptureProfile {
        val totalRamMb = getTotalRamMb()
        val ramTier = classifyRamTier(totalRamMb)
        val bufferMode = resolveBufferModeForTier(ramTier)
        val downgradeReasons = mutableListOf<String>()
        val characteristics = ensureCameraCharacteristics()
        val supportedResolutions = collectSupportedResolutions(characteristics)
        
        Log.d(TAG, "📊 [CaptureProfile] Requested: ${requestedResolution}@${requestedFps}fps, RAM: ${totalRamMb}MB ($ramTier tier)")
        val supportedFpsValues = collectSupportedFps(characteristics)
        val supportedCodecs = collectSupportedCodecs()

        val normalizedResolution = requestedResolution.uppercase(Locale.US)
        val resolvedResolution = when (normalizedResolution) {
            "AUTO" -> {
                val autoResolution = selectAutoResolution(ramTier, supportedResolutions)
                if (supportedResolutions.isNotEmpty() && autoResolution != supportedResolutions.first()) {
                    downgradeReasons.add("Auto resolution chose $autoResolution for $ramTier-tier device")
                }
                autoResolution
            }
            else -> {
                if (supportedResolutions.contains(normalizedResolution)) {
                    normalizedResolution
                } else {
                    val fallback = when {
                        ramTier == "low" && supportedResolutions.contains("720P") -> "720P"
                        supportedResolutions.contains("1080P") -> "1080P"
                        else -> supportedResolutions.lastOrNull() ?: "1080P"
                    }
                    downgradeReasons.add("Resolution fallback: $normalizedResolution -> $fallback")
                    fallback
                }
            }
        }

        val requestedFpsSanitized = requestedFps.takeIf { it > 0 } ?: 30
        val sortedFps = supportedFpsValues.sorted()
        var resolvedFps = sortedFps.lastOrNull { it <= requestedFpsSanitized }
            ?: sortedFps.lastOrNull()
            ?: 30

        Log.d(TAG, "📊 [CaptureProfile] FPS: requested=$requestedFpsSanitized, supported=$sortedFps, resolved=$resolvedFps")

        // Don't limit FPS based on RAM tier - let the user choose
        // The encoder will handle it or fallback if needed
        // Only log warnings for potential issues
        if (ramTier == "low" && resolvedFps > 30) {
            Log.w(TAG, "⚠️ High FPS ($resolvedFps) on low-tier device may affect performance")
        }

        if (!supportedFpsValues.contains(requestedFpsSanitized) && resolvedFps != requestedFpsSanitized) {
            downgradeReasons.add("Requested FPS $requestedFpsSanitized not available, using $resolvedFps")
        }

        val normalizedCodec = requestedCodec.uppercase(Locale.US)
        var resolvedCodec = when (normalizedCodec) {
            "AUTO" -> if (ramTier == "high" && supportedCodecs.contains("HEVC")) "HEVC" else "H.264"
            else -> if (supportedCodecs.contains(normalizedCodec)) normalizedCodec else "H.264"
        }

        if (ramTier != "high" && resolvedCodec == "HEVC") {
            downgradeReasons.add("Codec forced to H.264 for $ramTier-tier device")
            resolvedCodec = "H.264"
        }

        // Allow user's requested buffer duration without clamping
        // The rolling buffer will handle memory efficiently regardless of duration
        val bufferClamp = requestedPreRollSeconds

        // Only log if we would have clamped (for debugging)
        val wouldClamp = when (ramTier) {
            "high" -> requestedPreRollSeconds > 30
            "mid" -> requestedPreRollSeconds > 20
            else -> requestedPreRollSeconds > 10
        }
        if (wouldClamp) {
            Log.d(TAG, "Note: Using ${requestedPreRollSeconds}s buffer on $ramTier-tier device (user selected)")
        }

        return CaptureProfile(
            resolution = resolvedResolution,
            fps = resolvedFps,
            codec = resolvedCodec,
            bufferSeconds = bufferClamp,
            bufferMode = bufferMode,
            ramTier = ramTier,
            downgradeReasons = downgradeReasons
        )
    }

    private fun applyCaptureProfile(profile: CaptureProfile) {
        currentResolution = profile.resolution
        currentFps = profile.fps
        currentCodec = profile.codec
        selectedBufferSeconds = profile.bufferSeconds
        preRollSeconds = profile.bufferSeconds
        bufferDurationMs = profile.bufferSeconds * 1000L
        rollingBuffer.updateMaxDuration(profile.bufferSeconds * 1_000_000L)
        activeCaptureProfile = profile
        currentRamTier = profile.ramTier
        currentBufferMode = profile.bufferMode

        val reasons = if (profile.downgradeReasons.isEmpty()) "native" else profile.downgradeReasons.joinToString("; ")
        Log.i(
            TAG,
            "[CaptureProfile] tier=${profile.ramTier}, mode=${profile.bufferMode}, res=${profile.resolution}, fps=${profile.fps}, codec=${profile.codec}, buffer=${profile.bufferSeconds}s, reasons=$reasons"
        )
    }

    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("CameraBackground").also { it.start() }
        backgroundHandler = Handler(backgroundThread?.looper ?: Looper.getMainLooper())
    }

    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
            backgroundThread = null
            backgroundHandler = null
        } catch (e: InterruptedException) {
            Log.e(TAG, "Error stopping background thread", e)
        }
    }

    private fun sendEvent(type: String, data: Any?) {
        Handler(Looper.getMainLooper()).post {
            try {
                val event = mutableMapOf<String, Any?>("type" to type)
                data?.let { 
                    if (it is Map<*, *>) {
                        event.putAll(it as Map<String, Any?>)
                    }
                }
                eventSink?.success(event)
                Log.d(TAG, "Event sent: $type")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send event: $type", e)
            }
        }
    }
    
    private fun updateSubscription(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<String, Any>
            val newIsProUser = args?.get("isProUser") as? Boolean ?: false
            
            if (newIsProUser != isProUser) {
                isProUser = newIsProUser
                val oldBufferDuration = bufferDurationMs
                // Keep using the current preRollSeconds setting, don't override based on subscription
                // bufferDurationMs should be controlled by user's selected buffer duration, not subscription tier
                
                Log.d(TAG, "Subscription updated: pro=$isProUser, current buffer=${bufferDurationMs}ms (based on preRollSeconds: $preRollSeconds)")
                
                sendEvent("subscriptionUpdated", mapOf(
                    "isProUser" to isProUser,
                    "bufferDuration" to (bufferDurationMs / 1000).toInt()
                ))
            }
            
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update subscription", e)
            result.error("SUBSCRIPTION_ERROR", "Failed to update subscription: ${e.message}", null)
        }
    }

    private fun dispose() {
        try {
            // Clean up continuous buffer and encoders
            isBufferInitialized = false
            isAudioCapturing = false
            bufferLoggingTimer?.cancel()
            bufferLoggingTimer = null
            
            // Stop and release audio recorder
            try {
                audioRecord?.stop()
                audioRecord?.release()
                audioRecord = null
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping audio recorder", e)
            }
            
            // Stop audio thread
            audioHandler?.removeCallbacksAndMessages(null)
            audioThread?.quitSafely()
            audioThread = null
            audioHandler = null
            
            // Stop and release encoders
            try {
                videoEncoder?.stop()
                videoEncoder?.release()
                videoEncoder = null
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping video encoder", e)
            }
            
            try {
                audioEncoder?.stop()
                audioEncoder?.release()
                audioEncoder = null
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping audio encoder", e)
            }
            
            videoEncoderSurface?.release()
            videoEncoderSurface = null
            
            // Stop encoder thread
            encoderHandler?.removeCallbacksAndMessages(null)
            encoderThread?.quitSafely()
            encoderThread = null
            encoderHandler = null
            
            // Clear and cleanup rolling buffer
            rollingBuffer.cleanup()
            
            // ═══════════════════════════════════════════════════════════════════
            // CLEANUP - Delete all buffer files when app closes
            // ═══════════════════════════════════════════════════════════════════
            storageManager?.cleanupBufferFiles()
            storageManager?.cleanupOldBufferDirectories()
            Log.d(TAG, "Buffer files cleaned up on dispose")
            
            // Clean up pending buffer file
            pendingBufferFile?.delete()
            pendingBufferFile = null
            
            // Clean up pre-roll directory
            val bufferDir = File(context.filesDir, "preroll_buffer")
            if (bufferDir.exists()) {
                bufferDir.listFiles()?.forEach { it.delete() }
                bufferDir.delete()
            }
            
            stopBuffer(object : MethodChannel.Result {
                override fun success(result: Any?) {}
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
                override fun notImplemented() {}
            })
            
            bufferUpdateTask?.cancel()
            bufferTimer.cancel()
            
            if (isRecording) {
                stopRecording(object : MethodChannel.Result {
                    override fun success(result: Any?) {}
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
                    override fun notImplemented() {}
                })
            }
            
            closeCamera()
            stopBackgroundThread()
            
            previewSurface?.release()
            previewSurface = null
            textureEntry?.release()
            textureEntry = null
            
            Log.d(TAG, "CameraPlugin disposed")
        } catch (e: Exception) {
            Log.e(TAG, "Error during dispose", e)
        }
    }
    
    /**
     * Get device orientation for recording metadata.
     * This does NOT rotate the preview - only sets metadata for proper video playback.
     */
    private fun getDeviceOrientationForRecording(): Int {
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val display = windowManager.defaultDisplay
        val rotation = display.rotation
        
        // Get camera sensor orientation
        val cameraId = getCameraId()
        val characteristics = cameraManager?.getCameraCharacteristics(cameraId)
        val sensorOrientation = characteristics?.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
        
        // Calculate the orientation for the video file based on device rotation
        // This ensures the video plays correctly in gallery apps
        val orientation = when (rotation) {
            Surface.ROTATION_0 -> sensorOrientation        // Portrait
            Surface.ROTATION_90 -> 0                        // Landscape (left)
            Surface.ROTATION_180 -> (sensorOrientation + 180) % 360  // Upside down
            Surface.ROTATION_270 -> 180                     // Landscape (right)
            else -> sensorOrientation
        }
        
        Log.d(TAG, "[Orientation] Display rotation=$rotation, sensor=$sensorOrientation\u00b0, final=$orientation\u00b0")
        return orientation
    }
}

data class CaptureProfile(
    val resolution: String,
    val fps: Int,
    val codec: String,
    val bufferSeconds: Int,
    val bufferMode: String,
    val ramTier: String,
    val downgradeReasons: List<String> = emptyList()
)

data class VideoEncoderSettings(
    val width: Int,
    val height: Int,
    val fps: Int,
    val bitRate: Int,
    val codec: String,
    val mimeType: String,
    val isFallback: Boolean
) {
    val summary: String
        get() = "${width}x$height@${fps}fps ${codec} ${bitRate / 1_000_000}Mbps (fallback=$isFallback)"
}
