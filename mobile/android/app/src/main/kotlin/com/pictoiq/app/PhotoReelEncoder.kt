package com.pictoiq.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.opengl.EGL14
import android.opengl.EGLExt
import android.opengl.GLES20
import android.opengl.GLUtils
import android.util.Log
import android.view.Surface
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min

internal class PhotoReelEncoder {
    fun create(imagePaths: List<String>, outputPath: String, audioPath: String?): String {
        require(imagePaths.isNotEmpty()) { "Choose at least one photo." }
        if (audioPath == null) return createVideoOnly(imagePaths, outputPath)

        val outputFile = File(outputPath)
        val videoFile = File(outputPath + ".video.mp4")
        val audioFile = File(outputPath + ".audio.m4a")
        try {
            createVideoOnly(imagePaths, videoFile.absolutePath)
            encodeAudio(audioPath, audioFile.absolutePath, imagePaths.size * PHOTO_DURATION_US)
            muxVideoAndAudio(
                videoFile.absolutePath,
                audioFile.absolutePath,
                outputFile.absolutePath,
                imagePaths.size * PHOTO_DURATION_US,
            )
            return outputFile.absolutePath
        } finally {
            videoFile.delete()
            audioFile.delete()
        }
    }

    private fun createVideoOnly(imagePaths: List<String>, outputPath: String): String {
        require(imagePaths.isNotEmpty()) { "Choose at least one photo." }
        val outputFile = File(outputPath)
        outputFile.parentFile?.let {
            if (!it.exists() && !it.mkdirs()) {
                throw IllegalStateException("Could not prepare the reel output folder.")
            }
        }
        if (outputFile.exists() && !outputFile.delete()) {
            throw IllegalStateException("Could not replace the previous reel.")
        }

        var codec: MediaCodec? = null
        var inputSurface: Surface? = null
        var eglSurface: EglInputSurface? = null
        var muxer: MediaMuxer? = null
        var codecStarted = false
        var muxerStarted = false
        var trackIndex = -1
        var sawEndOfStream = false
        val bufferInfo = MediaCodec.BufferInfo()

        try {
            val format = MediaFormat.createVideoFormat(MIME_TYPE, WIDTH, HEIGHT).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
                )
                setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
                setInteger(MediaFormat.KEY_FRAME_RATE, FRAME_RATE)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }
            val activeCodec = MediaCodec.createEncoderByType(MIME_TYPE)
            codec = activeCodec
            activeCodec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val activeInputSurface = activeCodec.createInputSurface()
            inputSurface = activeInputSurface
            val renderer = EglInputSurface(activeInputSurface, WIDTH, HEIGHT)
            eglSurface = renderer
            val activeMuxer = MediaMuxer(
                outputFile.absolutePath,
                MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4,
            )
            muxer = activeMuxer
            activeCodec.start()
            codecStarted = true

            fun drain(endOfStream: Boolean): Boolean {
                var idleAttempts = 0
                while (true) {
                    val timeoutUs = if (endOfStream) 1_000_000L else 0L
                    when (val index = activeCodec.dequeueOutputBuffer(bufferInfo, timeoutUs)) {
                        MediaCodec.INFO_TRY_AGAIN_LATER -> {
                            if (!endOfStream || ++idleAttempts >= 30) return false
                        }
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            check(!muxerStarted) { "The encoder changed format more than once." }
                            trackIndex = activeMuxer.addTrack(activeCodec.outputFormat)
                            activeMuxer.start()
                            muxerStarted = true
                        }
                        MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> Unit
                        else -> if (index >= 0) {
                            val encoded = activeCodec.getOutputBuffer(index)
                                ?: throw IllegalStateException("The encoder returned an empty output buffer.")
                            val isConfig =
                                bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                            if (!isConfig && bufferInfo.size > 0) {
                                check(muxerStarted) { "The encoder produced video before its format." }
                                encoded.position(bufferInfo.offset)
                                encoded.limit(bufferInfo.offset + bufferInfo.size)
                                activeMuxer.writeSampleData(trackIndex, encoded, bufferInfo)
                            }
                            val finished =
                                bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            activeCodec.releaseOutputBuffer(index, false)
                            if (finished) return true
                        }
                    }
                }
            }

            val frame = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(frame)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            var previous: Bitmap? = null
            var current = decodePhoto(imagePaths.first())
            try {
                for (photoIndex in imagePaths.indices) {
                    if (photoIndex > 0) {
                        val next = decodePhoto(imagePaths[photoIndex])
                        previous?.recycle()
                        previous = current
                        current = next
                    }
                    for (frameIndex in 0 until FRAMES_PER_PHOTO) {
                        val transition = if (frameIndex < FADE_FRAMES) {
                            frameIndex.toFloat() / (FADE_FRAMES - 1)
                        } else {
                            1f
                        }
                        canvas.drawColor(Color.BLACK)
                        if (previous != null && transition < 1f) {
                            drawPhoto(canvas, previous, 1f - transition, paint)
                        }
                        drawPhoto(canvas, current, transition, paint)
                        renderer.draw(
                            frame,
                            (photoIndex * FRAMES_PER_PHOTO + frameIndex) * FRAME_DURATION_NS,
                        )
                        drain(endOfStream = false)
                    }
                }
            } finally {
                previous?.recycle()
                current.recycle()
                frame.recycle()
            }

            activeCodec.signalEndOfInputStream()
            sawEndOfStream = drain(endOfStream = true)
            check(sawEndOfStream) { "The video encoder did not finish in time." }
            check(muxerStarted) { "The video encoder did not produce a video track." }
            return outputFile.absolutePath
        } catch (error: Exception) {
            if (outputFile.exists()) outputFile.delete()
            throw error
        } finally {
            eglSurface?.release()
            inputSurface?.release()
            if (codecStarted) {
                try {
                    codec?.stop()
                } catch (error: Exception) {
                    Log.w(TAG, "Could not stop the video encoder cleanly.", error)
                }
            }
            codec?.release()
            if (muxerStarted) {
                try {
                    muxer?.stop()
                } catch (error: Exception) {
                    Log.w(TAG, "Could not stop the reel muxer cleanly.", error)
                }
            }
            muxer?.release()
        }
    }

    private fun decodePhoto(path: String): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IllegalArgumentException("A selected photo could not be decoded.")
        }
        var sampleSize = 1
        while (
            bounds.outWidth / sampleSize > MAX_DECODE_EDGE ||
            bounds.outHeight / sampleSize > MAX_DECODE_EDGE
        ) {
            sampleSize *= 2
        }
        val decoded = BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply { inSampleSize = sampleSize },
        ) ?: throw IllegalArgumentException("A selected photo could not be decoded.")

        val rotation = when (ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (rotation == 0f) return decoded
        val rotated = Bitmap.createBitmap(
            decoded,
            0,
            0,
            decoded.width,
            decoded.height,
            Matrix().apply { postRotate(rotation) },
            true,
        )
        decoded.recycle()
        return rotated
    }

    private fun drawPhoto(canvas: Canvas, bitmap: Bitmap, opacity: Float, paint: Paint) {
        paint.alpha = (opacity.coerceIn(0f, 1f) * 255).toInt()
        val scale = minOf(
            WIDTH.toFloat() / bitmap.width,
            HEIGHT.toFloat() / bitmap.height,
        )
        val left = (WIDTH - bitmap.width * scale) / 2f
        val top = (HEIGHT - bitmap.height * scale) / 2f
        canvas.save()
        canvas.translate(left, top)
        canvas.scale(scale, scale)
        canvas.drawBitmap(bitmap, 0f, 0f, paint)
        canvas.restore()
    }

    private fun encodeAudio(audioPath: String, outputPath: String, durationUs: Long) {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var decoderStarted = false
        var encoderStarted = false
        var muxerStarted = false
        var decoderInputEnded = false
        var encoderInputEnded = false
        var encoderOutputEnded = false
        val decoderInfo = MediaCodec.BufferInfo()
        val encoderInfo = MediaCodec.BufferInfo()
        var audioTrack = -1

        try {
            extractor.setDataSource(audioPath)
            val sourceTrack = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: throw IllegalArgumentException("The selected file has no audio track.")
            val sourceFormat = extractor.getTrackFormat(sourceTrack)
            val sourceMime = sourceFormat.getString(MediaFormat.KEY_MIME)
                ?: throw IllegalArgumentException("The selected audio format is unknown.")
            val sampleRate = sourceFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = sourceFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            require(channels in 1..2) {
                "Choose a mono or stereo audio file for the reel."
            }
            val bytesPerFrame = channels * 2
            extractor.selectTrack(sourceTrack)

            val activeDecoder = MediaCodec.createDecoderByType(sourceMime)
            decoder = activeDecoder
            activeDecoder.configure(sourceFormat, null, null, 0)
            activeDecoder.start()
            decoderStarted = true

            val aacFormat = MediaFormat.createAudioFormat(AUDIO_AAC_MIME, sampleRate, channels).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, AUDIO_BIT_RATE)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 64 * 1024)
            }
            val activeEncoder = MediaCodec.createEncoderByType(AUDIO_AAC_MIME)
            encoder = activeEncoder
            activeEncoder.configure(aacFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val audioMuxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = audioMuxer
            activeEncoder.start()
            encoderStarted = true

            fun drainEncoder(endOfStream: Boolean): Boolean {
                var idleAttempts = 0
                while (true) {
                    when (
                        val index = activeEncoder.dequeueOutputBuffer(
                            encoderInfo,
                            if (endOfStream) 10_000L else 0L,
                        )
                    ) {
                        MediaCodec.INFO_TRY_AGAIN_LATER -> {
                            if (!endOfStream || ++idleAttempts >= 30) return false
                        }
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            check(!muxerStarted) { "The audio encoder changed format more than once." }
                            audioTrack = audioMuxer.addTrack(activeEncoder.outputFormat)
                            audioMuxer.start()
                            muxerStarted = true
                        }
                        MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> Unit
                        else -> if (index >= 0) {
                            val buffer = activeEncoder.getOutputBuffer(index)
                                ?: throw IllegalStateException("The audio encoder returned an empty buffer.")
                            val isConfig =
                                encoderInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                            if (!isConfig && encoderInfo.size > 0) {
                                check(muxerStarted) { "The audio encoder produced data before its format." }
                                buffer.position(encoderInfo.offset)
                                buffer.limit(encoderInfo.offset + encoderInfo.size)
                                audioMuxer.writeSampleData(audioTrack, buffer, encoderInfo)
                            }
                            val finished =
                                encoderInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            activeEncoder.releaseOutputBuffer(index, false)
                            if (finished) return true
                        }
                    }
                }
            }

            fun feedPcm(buffer: ByteBuffer, info: MediaCodec.BufferInfo) {
                val remainingUs = durationUs - info.presentationTimeUs
                if (remainingUs <= 0L || info.size == 0) return
                buffer.position(info.offset)
                val availableBytes = min(info.size, buffer.remaining())
                val durationBytes = (remainingUs * sampleRate / 1_000_000L) * bytesPerFrame
                val usableBytes = min(availableBytes.toLong(), durationBytes)
                    .toInt() / bytesPerFrame * bytesPerFrame
                val endPosition = buffer.position() + usableBytes
                var submittedFrames = 0L

                while (buffer.position() < endPosition) {
                    var inputIndex = activeEncoder.dequeueInputBuffer(10_000L)
                    while (inputIndex < 0) {
                        drainEncoder(endOfStream = false)
                        inputIndex = activeEncoder.dequeueInputBuffer(10_000L)
                    }
                    val input = activeEncoder.getInputBuffer(inputIndex)
                        ?: throw IllegalStateException("The audio encoder has no input buffer.")
                    input.clear()
                    val count =
                        min(input.remaining(), endPosition - buffer.position()) /
                            bytesPerFrame * bytesPerFrame
                    check(count > 0) { "The audio encoder returned a buffer that is too small." }
                    val oldLimit = buffer.limit()
                    buffer.limit(buffer.position() + count)
                    input.put(buffer)
                    buffer.limit(oldLimit)
                    val presentationTimeUs = info.presentationTimeUs +
                        submittedFrames * 1_000_000L / sampleRate
                    activeEncoder.queueInputBuffer(
                        inputIndex,
                        0,
                        count,
                        presentationTimeUs,
                        0,
                    )
                    submittedFrames += count / bytesPerFrame
                    drainEncoder(endOfStream = false)
                }
            }

            while (!encoderOutputEnded) {
                if (!decoderInputEnded) {
                    val inputIndex = activeDecoder.dequeueInputBuffer(10_000L)
                    if (inputIndex >= 0) {
                        val input = activeDecoder.getInputBuffer(inputIndex)
                            ?: throw IllegalStateException("The audio decoder has no input buffer.")
                        val sampleTime = extractor.sampleTime
                        if (sampleTime < 0L || sampleTime >= durationUs) {
                            activeDecoder.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                0L,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            decoderInputEnded = true
                        } else {
                            input.clear()
                            val size = extractor.readSampleData(input, 0)
                            if (size < 0) {
                                activeDecoder.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    0,
                                    0L,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                decoderInputEnded = true
                            } else {
                                activeDecoder.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    size,
                                    sampleTime,
                                    extractor.sampleFlags,
                                )
                                extractor.advance()
                            }
                        }
                    }
                }

                val outputIndex = activeDecoder.dequeueOutputBuffer(decoderInfo, 10_000L)
                when {
                    outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val decodedFormat = activeDecoder.outputFormat
                        val decodedSampleRate = decodedFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        val decodedChannels = decodedFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        val pcmEncoding = if (
                            decodedFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)
                        ) {
                            decodedFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        } else {
                            android.media.AudioFormat.ENCODING_PCM_16BIT
                        }
                        require(
                            decodedSampleRate == sampleRate &&
                                decodedChannels == channels &&
                                pcmEncoding == android.media.AudioFormat.ENCODING_PCM_16BIT,
                        ) {
                            "This audio format cannot be converted for the reel."
                        }
                    }
                    outputIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> Unit
                    outputIndex >= 0 -> {
                        val pcm = activeDecoder.getOutputBuffer(outputIndex)
                            ?: throw IllegalStateException("The audio decoder returned an empty buffer.")
                        if (decoderInfo.size > 0) feedPcm(pcm, decoderInfo)
                        val decoderEos =
                            decoderInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        activeDecoder.releaseOutputBuffer(outputIndex, false)
                        if (decoderEos) {
                            if (!encoderInputEnded) {
                                val inputIndex = activeEncoder.dequeueInputBuffer(10_000L)
                                check(inputIndex >= 0) { "The audio encoder is not accepting input." }
                                activeEncoder.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    0,
                                    durationUs,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                encoderInputEnded = true
                            }
                        }
                    }
                }
                if (encoderInputEnded) {
                    encoderOutputEnded = drainEncoder(endOfStream = true)
                }
            }
            check(muxerStarted) { "The selected audio could not be encoded." }
        } finally {
            extractor.release()
            if (decoderStarted) {
                try {
                    decoder?.stop()
                } catch (error: Exception) {
                    Log.w(TAG, "Could not stop the audio decoder cleanly.", error)
                }
            }
            decoder?.release()
            if (encoderStarted) {
                try {
                    encoder?.stop()
                } catch (error: Exception) {
                    Log.w(TAG, "Could not stop the audio encoder cleanly.", error)
                }
            }
            encoder?.release()
            if (muxerStarted) {
                try {
                    muxer?.stop()
                } catch (error: Exception) {
                    Log.w(TAG, "Could not stop the audio muxer cleanly.", error)
                }
            }
            muxer?.release()
        }
    }

    private fun muxVideoAndAudio(
        videoPath: String,
        audioPath: String,
        outputPath: String,
        durationUs: Long,
    ) {
        val videoExtractor = MediaExtractor()
        val audioExtractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            videoExtractor.setDataSource(videoPath)
            audioExtractor.setDataSource(audioPath)
            val videoTrack = findTrack(videoExtractor, "video/")
            val audioTrack = findTrack(audioExtractor, "audio/")
            val combined = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = combined
            val outputVideoTrack = combined.addTrack(videoExtractor.getTrackFormat(videoTrack))
            val outputAudioTrack = combined.addTrack(audioExtractor.getTrackFormat(audioTrack))
            videoExtractor.selectTrack(videoTrack)
            audioExtractor.selectTrack(audioTrack)
            combined.start()
            muxerStarted = true

            val videoBuffer = ByteBuffer.allocate(VIDEO_MUX_BUFFER_SIZE)
            val audioBuffer = ByteBuffer.allocate(AUDIO_MUX_BUFFER_SIZE)
            var videoTime = videoExtractor.sampleTime
            var audioTime = audioExtractor.sampleTime
            while (
                (videoTime >= 0L && videoTime < durationUs) ||
                (audioTime >= 0L && audioTime < durationUs)
            ) {
                val writeVideo = audioTime < 0L ||
                    audioTime >= durationUs ||
                    (videoTime >= 0L && videoTime <= audioTime)
                if (writeVideo && videoTime >= 0L && videoTime < durationUs) {
                    writeExtractorSample(
                        videoExtractor,
                        combined,
                        outputVideoTrack,
                        videoBuffer,
                    )
                    videoTime = videoExtractor.sampleTime
                } else if (audioTime >= 0L && audioTime < durationUs) {
                    writeExtractorSample(
                        audioExtractor,
                        combined,
                        outputAudioTrack,
                        audioBuffer,
                    )
                    audioTime = audioExtractor.sampleTime
                }
            }
        } catch (error: Exception) {
            File(outputPath).delete()
            throw error
        } finally {
            videoExtractor.release()
            audioExtractor.release()
            if (muxerStarted) {
                try {
                    muxer?.stop()
                } catch (error: Exception) {
                    Log.w(TAG, "Could not stop the combined reel muxer cleanly.", error)
                }
            }
            muxer?.release()
        }
    }

    private fun findTrack(extractor: MediaExtractor, mimePrefix: String): Int =
        (0 until extractor.trackCount).firstOrNull { index ->
            extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                ?.startsWith(mimePrefix) == true
        } ?: throw IllegalStateException("A reel track is missing.")

    private fun writeExtractorSample(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        track: Int,
        buffer: ByteBuffer,
    ) {
        buffer.clear()
        val size = extractor.readSampleData(buffer, 0)
        check(size > 0) { "A reel track contains an unreadable sample." }
        val info = MediaCodec.BufferInfo().apply {
            set(0, size, extractor.sampleTime, extractor.sampleFlags)
        }
        muxer.writeSampleData(track, buffer, info)
        extractor.advance()
    }

    private class EglInputSurface(
        private val surface: Surface,
        private val width: Int,
        private val height: Int,
    ) {
        private val display: android.opengl.EGLDisplay
        private val context: android.opengl.EGLContext
        private val window: android.opengl.EGLSurface
        private val program: Int
        private val texture = IntArray(1)
        private val positionAttribute: Int
        private val textureAttribute: Int
        private val samplerUniform: Int
        private val vertices = directFloatBuffer(
            floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f),
        )
        private val textureCoordinates = directFloatBuffer(
            floatArrayOf(0f, 1f, 1f, 1f, 0f, 0f, 1f, 0f),
        )

        init {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            check(display != EGL14.EGL_NO_DISPLAY) { "Could not initialize the video display." }
            check(EGL14.eglInitialize(display, IntArray(2), 0, IntArray(2), 0)) {
                "Could not initialize video rendering."
            }
            val configAttributes = intArrayOf(
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL_RECORDABLE_ANDROID, 1,
                EGL14.EGL_NONE,
            )
            val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
            val configCount = IntArray(1)
            check(
                EGL14.eglChooseConfig(
                    display,
                    configAttributes,
                    0,
                    configs,
                    0,
                    configs.size,
                    configCount,
                    0,
                ) && configCount[0] > 0,
            ) { "No compatible video renderer is available." }
            val config = configs[0]!!
            context = EGL14.eglCreateContext(
                display,
                config,
                EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
                0,
            )
            check(context != EGL14.EGL_NO_CONTEXT) { "Could not create the video renderer." }
            window = EGL14.eglCreateWindowSurface(
                display,
                config,
                surface,
                intArrayOf(EGL14.EGL_NONE),
                0,
            )
            check(window != EGL14.EGL_NO_SURFACE) { "Could not open the video output surface." }
            check(EGL14.eglMakeCurrent(display, window, window, context)) {
                "Could not activate the video renderer."
            }
            EGL14.eglSwapInterval(display, 0)
            program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            positionAttribute = GLES20.glGetAttribLocation(program, "aPosition")
            textureAttribute = GLES20.glGetAttribLocation(program, "aTextureCoord")
            samplerUniform = GLES20.glGetUniformLocation(program, "uTexture")
            GLES20.glGenTextures(1, texture, 0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture[0])
            GLES20.glTexParameteri(
                GLES20.GL_TEXTURE_2D,
                GLES20.GL_TEXTURE_MIN_FILTER,
                GLES20.GL_LINEAR,
            )
            GLES20.glTexParameteri(
                GLES20.GL_TEXTURE_2D,
                GLES20.GL_TEXTURE_MAG_FILTER,
                GLES20.GL_LINEAR,
            )
            GLES20.glTexParameteri(
                GLES20.GL_TEXTURE_2D,
                GLES20.GL_TEXTURE_WRAP_S,
                GLES20.GL_CLAMP_TO_EDGE,
            )
            GLES20.glTexParameteri(
                GLES20.GL_TEXTURE_2D,
                GLES20.GL_TEXTURE_WRAP_T,
                GLES20.GL_CLAMP_TO_EDGE,
            )
        }

        fun draw(bitmap: Bitmap, presentationTimeNs: Long) {
            GLES20.glViewport(0, 0, width, height)
            GLES20.glUseProgram(program)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture[0])
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
            GLES20.glEnableVertexAttribArray(positionAttribute)
            GLES20.glVertexAttribPointer(
                positionAttribute,
                2,
                GLES20.GL_FLOAT,
                false,
                0,
                vertices.position(0),
            )
            GLES20.glEnableVertexAttribArray(textureAttribute)
            GLES20.glVertexAttribPointer(
                textureAttribute,
                2,
                GLES20.GL_FLOAT,
                false,
                0,
                textureCoordinates.position(0),
            )
            GLES20.glUniform1i(samplerUniform, 0)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            EGLExt.eglPresentationTimeANDROID(display, window, presentationTimeNs)
            check(EGL14.eglSwapBuffers(display, window)) {
                "Could not write a frame to the reel."
            }
        }

        fun release() {
            GLES20.glDeleteTextures(1, texture, 0)
            GLES20.glDeleteProgram(program)
            EGL14.eglMakeCurrent(
                display,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_CONTEXT,
            )
            EGL14.eglDestroySurface(display, window)
            EGL14.eglDestroyContext(display, context)
            EGL14.eglTerminate(display)
        }

        private fun createProgram(vertexSource: String, fragmentSource: String): Int {
            val vertex = compileShader(GLES20.GL_VERTEX_SHADER, vertexSource)
            val fragment = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
            return GLES20.glCreateProgram().also { result ->
                GLES20.glAttachShader(result, vertex)
                GLES20.glAttachShader(result, fragment)
                GLES20.glLinkProgram(result)
                val status = IntArray(1)
                GLES20.glGetProgramiv(result, GLES20.GL_LINK_STATUS, status, 0)
                check(status[0] == GLES20.GL_TRUE) {
                    "Could not link the video renderer: ${GLES20.glGetProgramInfoLog(result)}"
                }
                GLES20.glDeleteShader(vertex)
                GLES20.glDeleteShader(fragment)
            }
        }

        private fun compileShader(type: Int, source: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val status = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
            check(status[0] == GLES20.GL_TRUE) {
                "Could not prepare the video renderer: ${GLES20.glGetShaderInfoLog(shader)}"
            }
            return shader
        }

        private fun directFloatBuffer(values: FloatArray) =
            ByteBuffer.allocateDirect(values.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
                .put(values)
                .apply { position(0) }
    }

    private companion object {
        const val TAG = "PhotoReelEncoder"
        const val MIME_TYPE = "video/avc"
        const val WIDTH = 1080
        const val HEIGHT = 1920
        const val FRAME_RATE = 30
        const val FRAMES_PER_PHOTO = FRAME_RATE * 3
        const val FADE_FRAMES = 12
        const val MAX_DECODE_EDGE = 1920
        const val BIT_RATE = 12_000_000
        const val AUDIO_BIT_RATE = 192_000
        const val AUDIO_AAC_MIME = "audio/mp4a-latm"
        const val PHOTO_DURATION_US = 3_000_000L
        const val VIDEO_MUX_BUFFER_SIZE = 16 * 1024 * 1024
        const val AUDIO_MUX_BUFFER_SIZE = 1024 * 1024
        const val FRAME_DURATION_NS = 1_000_000_000L / FRAME_RATE
        const val EGL_RECORDABLE_ANDROID = 0x3142
        const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec2 aTextureCoord;
            varying vec2 vTextureCoord;
            void main() {
                gl_Position = aPosition;
                vTextureCoord = aTextureCoord;
            }
        """
        const val FRAGMENT_SHADER = """
            precision mediump float;
            varying vec2 vTextureCoord;
            uniform sampler2D uTexture;
            void main() {
                gl_FragColor = texture2D(uTexture, vTextureCoord);
            }
        """
    }
}
