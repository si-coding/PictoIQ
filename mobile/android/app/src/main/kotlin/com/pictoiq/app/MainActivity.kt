package com.pictoiq.app

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val reelExecutor = Executors.newSingleThreadExecutor()
    private var pendingAudioPicker: MethodChannel.Result? = null
    @Volatile
    private var reelProgressSink: EventChannel.EventSink? = null
    @Volatile
    private var cancelReelRequested = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pictoiq.app/video_reel/progress",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                reelProgressSink = events
            }

            override fun onCancel(arguments: Any?) {
                reelProgressSink = null
            }
        })
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pictoiq.app/video_reel",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickReelAudio" -> pickReelAudio(result)
                "discardReelAudio" -> {
                    deletePickedAudio(call.argument<String>("audioPath"))
                    result.success(null)
                }
                "cancelBestMomentsReel" -> {
                    cancelReelRequested = true
                    result.success(null)
                }
                "createBestMomentsReel" -> createBestMomentsReel(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun pickReelAudio(result: MethodChannel.Result) {
        if (pendingAudioPicker != null) {
            result.error("picker_busy", "An audio file picker is already open.", null)
            return
        }
        pendingAudioPicker = result
        try {
            startActivityForResult(
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "audio/*"
                },
                AUDIO_PICK_REQUEST,
            )
        } catch (error: Exception) {
            pendingAudioPicker = null
            result.error("audio_picker_failed", error.message, null)
        }
    }

    private fun createBestMomentsReel(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val imagePaths = call.argument<List<String>>("imagePaths")
        val outputPath = call.argument<String>("outputPath")
        val audioPath = call.argument<String>("audioPath")
        val secondsPerPhoto = call.argument<Int>("secondsPerPhoto") ?: 3
        val transitionMillis = call.argument<Int>("transitionMillis") ?: 400
        val title = call.argument<String>("title").orEmpty().take(60)
        val titleStyle = call.argument<String>("titleStyle") ?: "clean"
        if (imagePaths.isNullOrEmpty() || outputPath.isNullOrBlank()) {
            result.error("invalid_arguments", "Photos and output path are required.", null)
            return
        }
        if (secondsPerPhoto !in 2..6 || transitionMillis !in setOf(0, 250, 400, 500, 750, 1000)) {
            result.error("invalid_arguments", "Reel timing settings are out of range.", null)
            return
        }
        if (titleStyle !in setOf("clean", "bold", "elegant")) {
            result.error("invalid_arguments", "The title style is not supported.", null)
            return
        }

        cancelReelRequested = false
        reportReelProgress(0.0)
        reelExecutor.execute {
            try {
                val path = PhotoReelEncoder().create(
                    imagePaths,
                    outputPath,
                    audioPath,
                    secondsPerPhoto,
                    transitionMillis,
                    title,
                    titleStyle,
                    shouldCancel = { cancelReelRequested },
                ) { progress -> reportReelProgress(progress) }
                Handler(Looper.getMainLooper()).post {
                    reelProgressSink?.success(1.0)
                    result.success(path)
                }
            } catch (error: CancellationException) {
                Handler(Looper.getMainLooper()).post {
                    result.error(
                        "reel_creation_cancelled",
                        "Reel creation was cancelled.",
                        null,
                    )
                }
            } catch (error: Exception) {
                Handler(Looper.getMainLooper()).post {
                    result.error(
                        "reel_creation_failed",
                        error.message ?: "The reel could not be created.",
                        null,
                    )
                }
            } finally {
                deletePickedAudio(audioPath)
            }
        }
    }

    private fun deletePickedAudio(path: String?) {
        if (path == null) return
        try {
            val audioFile = File(path).canonicalFile
            if (
                audioFile.parentFile == cacheDir.canonicalFile &&
                audioFile.name.startsWith("pictoiq_reel_audio_")
            ) {
                audioFile.delete()
            }
        } catch (error: Exception) {
            android.util.Log.w("PictoIq", "Could not remove the temporary audio copy.", error)
        }
    }

    private fun reportReelProgress(progress: Double) {
        Handler(Looper.getMainLooper()).post {
            reelProgressSink?.success(progress.coerceIn(0.0, 1.0))
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != AUDIO_PICK_REQUEST) return

        val pending = pendingAudioPicker
        pendingAudioPicker = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending?.success(null)
            return
        }

        val copiedFile = File(cacheDir, "pictoiq_reel_audio_${System.nanoTime()}")
        try {
            val source = contentResolver.openInputStream(data.data!!)
                ?: throw IllegalStateException("The selected audio file could not be opened.")
            source.use { input ->
                FileOutputStream(copiedFile).use { output -> input.copyTo(output) }
            }
            pending?.success(copiedFile.absolutePath)
        } catch (error: Exception) {
            copiedFile.delete()
            pending?.error("audio_file_unavailable", error.message, null)
        }
    }

    override fun onDestroy() {
        reelProgressSink = null
        pendingAudioPicker?.error("activity_closed", "The audio picker was closed.", null)
        pendingAudioPicker = null
        reelExecutor.shutdown()
        try {
            if (!reelExecutor.awaitTermination(1, TimeUnit.SECONDS)) {
                reelExecutor.shutdownNow()
            }
        } catch (error: InterruptedException) {
            reelExecutor.shutdownNow()
            Thread.currentThread().interrupt()
        }
        super.onDestroy()
    }

    private companion object {
        const val AUDIO_PICK_REQUEST = 7124
    }
}
