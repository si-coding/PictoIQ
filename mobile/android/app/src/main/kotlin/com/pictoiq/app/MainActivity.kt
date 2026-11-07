package com.pictoiq.app

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val reelExecutor = Executors.newSingleThreadExecutor()
    private var pendingAudioPicker: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pictoiq.app/video_reel",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickReelAudio" -> pickReelAudio(result)
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
        if (imagePaths.isNullOrEmpty() || outputPath.isNullOrBlank()) {
            result.error("invalid_arguments", "Photos and output path are required.", null)
            return
        }

        reelExecutor.execute {
            try {
                val path = PhotoReelEncoder().create(imagePaths, outputPath, audioPath)
                Handler(Looper.getMainLooper()).post { result.success(path) }
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
