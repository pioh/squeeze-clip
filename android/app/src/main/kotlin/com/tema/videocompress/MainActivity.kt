package com.tema.videocompress

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.ActivityNotFoundException
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val methodChannelName = "video_compress_app/native"
    private val eventChannelName = "video_compress_app/progress"
    private val notificationChannelId = "compression_status"
    private val progressNotificationId = 4001
    private val doneNotificationId = 4002

    private var pendingResult: MethodChannel.Result? = null
    private var progressSink: EventChannel.EventSink? = null
    private var activeTransformer: Transformer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    private var startedAtMs: Long = 0L
    private var activeDurationMs: Long = 0L
    private var activeTempFile: File? = null
    private var cancelRequested: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler(::handleCall)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                        progressSink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        progressSink = null
                    }
                },
            )
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "describeSource" -> {
                val raw = call.argument<String>("source")
                if (raw.isNullOrBlank()) {
                    result.error("bad_source", "Missing source", null)
                    return
                }
                val info = describeSource(normalizeSource(raw))
                if (info == null) {
                    result.error("bad_source", "Cannot read source", null)
                } else {
                    result.success(info)
                }
            }

            "getLatestCameraVideo" -> {
                val latest = getRecentVideos(1, "camera").firstOrNull()
                if (latest == null) {
                    result.error("not_found", "No camera video found", null)
                } else {
                    result.success(latest)
                }
            }

            "getRecentCameraVideos" -> {
                val limit = call.argument<Int>("limit") ?: 6
                val source = call.argument<String>("source") ?: "camera"
                result.success(getRecentVideos(limit, source))
            }

            "getThumbnail" -> {
                val raw = call.argument<String>("source")
                if (raw.isNullOrBlank()) {
                    result.error("bad_source", "Missing source", null)
                    return
                }
                val bytes = buildThumbnail(normalizeSource(raw))
                if (bytes == null) {
                    result.error("thumb_failed", "Cannot build thumbnail", null)
                } else {
                    result.success(bytes)
                }
            }

            "compressVideo" -> {
                if (pendingResult != null) {
                    result.error("busy", "Compression already running", null)
                    return
                }
                val raw = call.argument<String>("source")
                if (raw.isNullOrBlank()) {
                    result.error("bad_source", "Missing source", null)
                    return
                }
                val quality = call.argument<String>("quality") ?: "balanced"
                val customHeight = call.argument<Int>("customHeight") ?: 1440
                val suffix = call.argument<String>("suffix") ?: "_tg"
                pendingResult = result
                compressVideo(normalizeSource(raw), quality, suffix, customHeight)
            }

            "cancelCompression" -> {
                cancelCompression()
                result.success(null)
            }

            "openVideo" -> {
                val raw = call.argument<String>("source")
                if (raw.isNullOrBlank()) {
                    result.error("bad_source", "Missing source", null)
                    return
                }
                openVideo(normalizeSource(raw))
                result.success(null)
            }

            "shareVideos" -> {
                val rawSources = call.argument<List<String>>("sources").orEmpty()
                if (rawSources.isEmpty()) {
                    result.error("bad_source", "Missing sources", null)
                    return
                }
                val telegramOnly = call.argument<Boolean>("telegramOnly") ?: false
                shareVideos(rawSources.map(::normalizeSource), telegramOnly)
                result.success(null)
            }

            "findExistingCompressed" -> {
                val raw = call.argument<String>("source")
                if (raw.isNullOrBlank()) {
                    result.error("bad_source", "Missing source", null)
                    return
                }
                val suffix = call.argument<String>("suffix") ?: "_tg"
                result.success(findExistingCompressed(normalizeSource(raw), suffix))
            }

            else -> result.notImplemented()
        }
    }

    private fun normalizeSource(raw: String): SourceRef {
        val uri = runCatching { Uri.parse(raw) }.getOrNull()
        return if (raw.startsWith("content://") || uri?.scheme == "content") {
            SourceRef.Content(resolveContentUri(uri ?: Uri.parse(raw)))
        } else {
            SourceRef.FileRef(File(raw))
        }
    }

    private fun resolveContentUri(uri: Uri): Uri {
        if (uri.authority == "com.android.providers.media.documents") {
            val docId = DocumentsContract.getDocumentId(uri)
            val parts = docId.split(":")
            if (parts.size == 2) {
                val id = parts[1].toLongOrNull()
                return when (parts[0]) {
                    "video" -> id?.let { ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, it) } ?: uri
                    "image" -> id?.let { ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, it) } ?: uri
                    else -> uri
                }
            }
        }
        return uri
    }

    private fun getRecentVideos(limit: Int, source: String): List<Map<String, String>> {
        val result = mutableListOf<Map<String, String>>()
        val collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.RELATIVE_PATH,
            MediaStore.Video.Media.SIZE,
        )
        val (selection, args) = when (source.lowercase(Locale.US)) {
            "telegram" -> {
                val clauses = listOf(
                    "${MediaStore.Video.Media.RELATIVE_PATH} LIKE ?",
                    "${MediaStore.Video.Media.RELATIVE_PATH} LIKE ?",
                )
                clauses.joinToString(" OR ", prefix = "(", postfix = ")") to arrayOf(
                    "%Telegram/%",
                    "%Movies/Telegram/%",
                )
            }
            "downloads" -> {
                "${MediaStore.Video.Media.RELATIVE_PATH} LIKE ?" to arrayOf("Download/%")
            }
            else -> {
                "${MediaStore.Video.Media.RELATIVE_PATH} LIKE ?" to arrayOf("DCIM/Camera/%")
            }
        }
        val order = "${MediaStore.Video.Media.DATE_TAKEN} DESC, ${MediaStore.Video.Media.DATE_ADDED} DESC"

        contentResolver.query(collection, projection, selection, args, order)?.use { cursor ->
            while (cursor.moveToNext() && result.size < limit) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID))
                val name =
                    cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)) ?: "video"
                val relativePath =
                    cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Video.Media.RELATIVE_PATH)) ?: "DCIM/Camera/"
                val sizeBytes = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE))
                val uri = ContentUris.withAppendedId(collection, id)
                result += mapOf(
                    "source" to uri.toString(),
                    "name" to name,
                    "subtitle" to relativePath,
                    "sizeBytes" to sizeBytes.toString(),
                )
            }
        }
        return result
    }

    private fun describeSource(source: SourceRef): Map<String, String>? {
        val meta = readMetadata(source)
        return when (source) {
            is SourceRef.FileRef -> {
                if (!source.file.exists()) return null
                mapOf(
                    "source" to source.file.absolutePath,
                    "name" to source.file.name,
                    "subtitle" to (source.file.parent ?: ""),
                    "sizeBytes" to source.file.length().toString(),
                    "durationMs" to meta.durationMs.toString(),
                    "width" to meta.width.toString(),
                    "height" to meta.height.toString(),
                    "bitrate" to meta.bitrate.toString(),
                    "fps" to meta.fps.toString(),
                )
            }

            is SourceRef.Content -> {
                val projection = arrayOf(
                    MediaStore.MediaColumns.DISPLAY_NAME,
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    MediaStore.MediaColumns.SIZE,
                )
                contentResolver.query(source.uri, projection, null, null, null)?.use { cursor ->
                    if (!cursor.moveToFirst()) return null
                    val name =
                        cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)) ?: "video"
                    val relativePath =
                        cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)) ?: "DCIM/Camera/"
                    val sizeBytes = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE))
                    return mapOf(
                        "source" to source.uri.toString(),
                        "name" to name,
                        "subtitle" to relativePath,
                        "sizeBytes" to sizeBytes.toString(),
                        "durationMs" to meta.durationMs.toString(),
                        "width" to meta.width.toString(),
                        "height" to meta.height.toString(),
                        "bitrate" to meta.bitrate.toString(),
                        "fps" to meta.fps.toString(),
                    )
                }
                null
            }
        }
    }

    private fun buildThumbnail(source: SourceRef): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            when (source) {
                is SourceRef.FileRef -> retriever.setDataSource(source.file.absolutePath)
                is SourceRef.Content -> retriever.setDataSource(this, source.uri)
            }
            val frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: return null
            val scaled = Bitmap.createScaledBitmap(frame, 320, 180, true)
            ByteArrayOutputStream().use { stream ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 82, stream)
                stream.toByteArray()
            }
        } catch (_: Exception) {
            null
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun compressVideo(source: SourceRef, quality: String, suffix: String, customHeight: Int) {
        cancelRequested = false
        val inputUri = when (source) {
            is SourceRef.Content -> source.uri
            is SourceRef.FileRef -> Uri.fromFile(source.file)
        }

        val inputInfo = describeSource(source)
        if (inputInfo == null) {
            finishWithError("bad_source", "Cannot inspect source")
            return
        }

        val baseName = inputInfo["name"].orEmpty().substringBeforeLast('.', inputInfo["name"].orEmpty())
        val tempFile = File(cacheDir, "${baseName}_${System.currentTimeMillis()}.mp4")
        activeTempFile = tempFile
        val targetHeight = when (quality) {
            "high" -> 1920
            "small" -> 960
            "custom" -> customHeight.coerceIn(320, 4320)
            else -> 1280
        }

        val editedMediaItem = EditedMediaItem.Builder(MediaItem.fromUri(inputUri))
            .setEffects(
                Effects(
                    emptyList(),
                    listOf(Presentation.createForHeight(targetHeight)),
                ),
            )
            .build()

        val transformer = Transformer.Builder(this)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(
                object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        stopProgressUpdates()
                        try {
                            if (cancelRequested) {
                                tempFile.delete()
                                finishWithError("cancelled", "Compression cancelled")
                                return
                            }
                            val output = persistOutput(source, inputInfo, tempFile, suffix)
                            tempFile.delete()
                            showCompletionNotification("Compression finished: ${output["name"].orEmpty()}", normalizeSource(output["source"].orEmpty()))
                            pendingResult?.success(output)
                        } catch (e: Exception) {
                            finishWithError("persist_failed", e.message ?: "Persist failed")
                        } finally {
                            pendingResult = null
                            activeTransformer = null
                            activeTempFile = null
                            cancelRequested = false
                        }
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        stopProgressUpdates()
                        tempFile.delete()
                        if (cancelRequested) {
                            finishWithError("cancelled", "Compression cancelled")
                        } else {
                            finishWithError("transform_failed", exportException.localizedMessage ?: "Compression failed")
                        }
                        activeTransformer = null
                        activeTempFile = null
                        cancelRequested = false
                    }
                },
            )
            .build()

        activeDurationMs = runCatching {
            val retriever = MediaMetadataRetriever()
            try {
                when (source) {
                    is SourceRef.FileRef -> retriever.setDataSource(source.file.absolutePath)
                    is SourceRef.Content -> retriever.setDataSource(this, source.uri)
                }
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            } finally {
                runCatching { retriever.release() }
            }
        }.getOrDefault(0L)

        activeTransformer = transformer
        startedAtMs = System.currentTimeMillis()
        showProgressNotification(0, "Preparing ${inputInfo["name"].orEmpty()}...")
        startProgressUpdates()
        transformer.start(editedMediaItem, tempFile.absolutePath)
    }

    private fun persistOutput(
        source: SourceRef,
        inputInfo: Map<String, String>,
        tempFile: File,
        suffix: String,
    ): Map<String, String> {
        val originalName = inputInfo["name"].orEmpty()
        val outName = buildOutputName(originalName, suffix)

        return when (source) {
            is SourceRef.FileRef -> {
                val outFile = File(source.file.parentFile, outName)
                tempFile.copyTo(outFile, overwrite = true)
                mapOf(
                    "source" to outFile.absolutePath,
                    "name" to outFile.name,
                    "subtitle" to (outFile.parent ?: ""),
                    "sizeBytes" to outFile.length().toString(),
                    "durationMs" to readMetadata(SourceRef.FileRef(outFile)).durationMs.toString(),
                    "width" to readMetadata(SourceRef.FileRef(outFile)).width.toString(),
                    "height" to readMetadata(SourceRef.FileRef(outFile)).height.toString(),
                    "bitrate" to readMetadata(SourceRef.FileRef(outFile)).bitrate.toString(),
                    "fps" to readMetadata(SourceRef.FileRef(outFile)).fps.toString(),
                )
            }

            is SourceRef.Content -> {
                val projection = arrayOf(MediaStore.MediaColumns.RELATIVE_PATH)
                var relativePath = "DCIM/Camera/"
                contentResolver.query(source.uri, projection, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        relativePath =
                            cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH))
                                ?: relativePath
                    }
                }

                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, outName)
                    put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                    put(MediaStore.Video.Media.RELATIVE_PATH, relativePath)
                    put(MediaStore.Video.Media.DATE_TAKEN, System.currentTimeMillis())
                }
                val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                val outUri = contentResolver.insert(collection, values)
                    ?: throw IOException("Cannot create output file")

                contentResolver.openOutputStream(outUri)?.use { out ->
                    FileInputStream(tempFile).use { input ->
                        input.copyTo(out)
                    }
                } ?: throw IOException("Cannot write output")

                mapOf(
                    "source" to outUri.toString(),
                    "name" to outName,
                    "subtitle" to relativePath,
                    "sizeBytes" to tempFile.length().toString(),
                    "durationMs" to readMetadata(SourceRef.Content(outUri)).durationMs.toString(),
                    "width" to readMetadata(SourceRef.Content(outUri)).width.toString(),
                    "height" to readMetadata(SourceRef.Content(outUri)).height.toString(),
                    "bitrate" to readMetadata(SourceRef.Content(outUri)).bitrate.toString(),
                    "fps" to readMetadata(SourceRef.Content(outUri)).fps.toString(),
                )
            }
        }
    }

    private fun findExistingCompressed(source: SourceRef, suffix: String): Map<String, String>? {
        val inputInfo = describeSource(source) ?: return null
        val originalName = inputInfo["name"].orEmpty()
        val outName = buildOutputName(originalName, suffix)

        return when (source) {
            is SourceRef.FileRef -> {
                val outFile = File(source.file.parentFile, outName)
                if (!outFile.exists()) null else describeSource(SourceRef.FileRef(outFile))
            }

            is SourceRef.Content -> {
                val projection = arrayOf(MediaStore.MediaColumns.RELATIVE_PATH)
                var relativePath = "DCIM/Camera/"
                contentResolver.query(source.uri, projection, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        relativePath =
                            cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH))
                                ?: relativePath
                    }
                }

                val collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                val queryProjection = arrayOf(
                    MediaStore.Video.Media._ID,
                    MediaStore.Video.Media.DISPLAY_NAME,
                    MediaStore.Video.Media.RELATIVE_PATH,
                    MediaStore.Video.Media.SIZE,
                )
                val selection =
                    "${MediaStore.Video.Media.DISPLAY_NAME} = ? AND ${MediaStore.Video.Media.RELATIVE_PATH} = ?"
                val args = arrayOf(outName, relativePath)

                contentResolver.query(collection, queryProjection, selection, args, "${MediaStore.Video.Media.DATE_ADDED} DESC")
                    ?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID))
                            val uri = ContentUris.withAppendedId(collection, id)
                            return describeSource(SourceRef.Content(uri))
                        }
                    }
                null
            }
        }
    }

    private fun startProgressUpdates() {
        stopProgressUpdates()
        progressRunnable =
            object : Runnable {
                override fun run() {
                    val transformer = activeTransformer ?: return
                    val holder = ProgressHolder()
                    val progressState = transformer.getProgress(holder)
                    val elapsedMs = (System.currentTimeMillis() - startedAtMs).coerceAtLeast(1L)
                    val fraction = (holder.progress / 100.0).coerceIn(0.0, 1.0)
                    val processedMs = (activeDurationMs * fraction).toLong()
                    val speed = if (elapsedMs > 0) processedMs.toDouble() / elapsedMs.toDouble() else 0.0
                    val remainingMs = (activeDurationMs - processedMs).coerceAtLeast(0L)
                    val etaMs = if (speed > 0.001) (remainingMs / speed).toLong() else -1L

                    progressSink?.success(
                        mapOf(
                            "progress" to fraction,
                            "progressState" to progressState,
                            "speed" to String.format(Locale.US, "%.2fx", speed),
                            "elapsedMs" to elapsedMs,
                            "etaMs" to etaMs,
                        ),
                    )
                    showProgressNotification(
                        (fraction * 100).toInt(),
                        "${String.format(Locale.US, "%.0f", fraction * 100)}%  •  ${String.format(Locale.US, "%.2fx", speed)}  •  ETA ${formatClock(etaMs)}",
                    )
                    handler.postDelayed(this, 300)
                }
            }
        handler.post(progressRunnable!!)
    }

    private fun stopProgressUpdates() {
        progressRunnable?.let(handler::removeCallbacks)
        progressRunnable = null
        NotificationManagerCompat.from(this).cancel(progressNotificationId)
        progressSink?.success(
            mapOf(
                "progress" to 1.0,
                "progressState" to -1,
                "speed" to "done",
                "elapsedMs" to (System.currentTimeMillis() - startedAtMs).coerceAtLeast(0L),
                "etaMs" to 0L,
            ),
        )
    }

    private fun openVideo(source: SourceRef) {
        val uri = when (source) {
            is SourceRef.Content -> source.uri
            is SourceRef.FileRef -> FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                source.file,
            )
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "video/*")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(Intent.createChooser(intent, "Open video"))
    }

    private fun cancelCompression() {
        cancelRequested = true
        stopProgressUpdates()
        activeTransformer?.cancel()
        activeTransformer = null
        activeTempFile?.delete()
        activeTempFile = null
        showCompletionNotification("Compression cancelled", null)
    }

    private fun shareVideos(sources: List<SourceRef>, telegramOnly: Boolean) {
        val uris = ArrayList<Uri>()
        sources.forEach { source ->
            val uri = when (source) {
                is SourceRef.Content -> source.uri
                is SourceRef.FileRef -> FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    source.file,
                )
            }
            uris += uri
        }

        val intent = Intent().apply {
            action = if (uris.size == 1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE
            type = "video/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            if (uris.size == 1) {
                putExtra(Intent.EXTRA_STREAM, uris.first())
            } else {
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            }
            if (telegramOnly) {
                `package` = "org.telegram.messenger"
            }
        }

        try {
            startActivity(if (telegramOnly) intent else Intent.createChooser(intent, "Share video"))
        } catch (e: ActivityNotFoundException) {
            if (telegramOnly) {
                intent.`package` = null
                startActivity(Intent.createChooser(intent, "Share video"))
            } else {
                throw e
            }
        }
    }

    private fun readMetadata(source: SourceRef): VideoMeta {
        val retriever = MediaMetadataRetriever()
        return try {
            when (source) {
                is SourceRef.FileRef -> retriever.setDataSource(source.file.absolutePath)
                is SourceRef.Content -> retriever.setDataSource(this, source.uri)
            }
            VideoMeta(
                durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L,
                width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0,
                height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0,
                bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull() ?: 0L,
                fps = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toFloatOrNull() ?: 0f,
            )
        } catch (_: Exception) {
            VideoMeta()
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun finishWithError(code: String, message: String) {
        pendingResult?.error(code, message, null)
        pendingResult = null
        if (code != "cancelled") {
            showCompletionNotification(message, null)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            notificationChannelId,
            "Compression status",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows current video compression progress and completion status"
        }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    private fun showProgressNotification(progress: Int, text: String) {
        if (!canPostNotifications()) return
        val notification = NotificationCompat.Builder(this, notificationChannelId)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle("SqueezeClip is compressing")
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(100, progress.coerceIn(0, 100), false)
            .setContentIntent(buildOpenAppPendingIntent())
            .build()
        NotificationManagerCompat.from(this).notify(progressNotificationId, notification)
    }

    private fun showCompletionNotification(title: String, source: SourceRef?) {
        if (!canPostNotifications()) return
        val builder = NotificationCompat.Builder(this, notificationChannelId)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle("SqueezeClip")
            .setContentText(title)
            .setAutoCancel(true)
            .setContentIntent(source?.let(::buildOpenVideoPendingIntent) ?: buildOpenAppPendingIntent())
        if (source != null) {
            builder.addAction(
                0,
                "Open",
                buildOpenVideoPendingIntent(source),
            )
            builder.addAction(
                0,
                "Telegram",
                buildSharePendingIntent(source, telegramOnly = true),
            )
        }
        NotificationManagerCompat.from(this).notify(doneNotificationId, builder.build())
    }

    private fun buildOpenAppPendingIntent(): PendingIntent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            this,
            1001,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildOpenVideoPendingIntent(source: SourceRef): PendingIntent {
        val uri = when (source) {
            is SourceRef.Content -> source.uri
            is SourceRef.FileRef -> FileProvider.getUriForFile(this, "$packageName.fileprovider", source.file)
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "video/*")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return PendingIntent.getActivity(
            this,
            1002,
            Intent.createChooser(intent, "Open video"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildSharePendingIntent(source: SourceRef, telegramOnly: Boolean): PendingIntent {
        val uri = when (source) {
            is SourceRef.Content -> source.uri
            is SourceRef.FileRef -> FileProvider.getUriForFile(this, "$packageName.fileprovider", source.file)
        }
        val intent = Intent().apply {
            action = Intent.ACTION_SEND
            type = "video/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            if (telegramOnly) {
                `package` = "org.telegram.messenger"
            }
        }
        return PendingIntent.getActivity(
            this,
            if (telegramOnly) 1003 else 1004,
            if (telegramOnly) intent else Intent.createChooser(intent, "Share video"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun canPostNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun formatClock(ms: Long): String {
        if (ms <= 0L) return "--:--"
        val totalSeconds = (ms / 1000).toInt()
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60
        return if (hours > 0) {
            String.format(Locale.US, "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.US, "%02d:%02d", minutes, seconds)
        }
    }

    private fun buildOutputName(originalName: String, suffix: String): String {
        val cleanSuffix = suffix.trim().ifBlank { "_tg" }
        return "${originalName.substringBeforeLast('.', originalName)}${cleanSuffix}.mp4"
    }
}

private sealed class SourceRef {
    data class Content(val uri: Uri) : SourceRef()
    data class FileRef(val file: File) : SourceRef()
}

private data class VideoMeta(
    val durationMs: Long = 0L,
    val width: Int = 0,
    val height: Int = 0,
    val bitrate: Long = 0L,
    val fps: Float = 0f,
)
