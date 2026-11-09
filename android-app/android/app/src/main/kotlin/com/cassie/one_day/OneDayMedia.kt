package com.cassie.one_day

import android.content.ContentValues
import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.graphics.Typeface
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

@OptIn(UnstableApi::class)
class OneDayMedia(private val context: Context) {
    private var exporting: Transformer? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "render" -> render(call, result)
            "saveToGallery" -> saveToGallery(call, result)
            else -> result.notImplemented()
        }
    }

    private fun privateFile(path: String): File {
        val file = File(path).canonicalFile
        val root = context.filesDir.canonicalFile
        require(file.path.startsWith(root.path + File.separator)) {
            "Media must stay inside app storage"
        }
        return file
    }

    private fun render(call: MethodCall, result: MethodChannel.Result) {
        if (exporting != null) {
            result.error("BUSY", "A film is already exporting", null)
            return
        }
        val paths = call.argument<List<String>>("paths")
        val labels = call.argument<List<String>>("labels")
        val outputPath = call.argument<String>("output")
        val orientation = call.argument<String>("orientation")
        if (paths.isNullOrEmpty() || labels?.size != paths.size || outputPath == null) {
            result.error("INPUT", "Invalid film input", null)
            return
        }
        try {
            val output = privateFile(outputPath)
            val inputFiles = paths.map(::privateFile)
            require(inputFiles.all { it.isFile && it.length() > 0 }) { "A source clip is missing" }
            output.parentFile?.mkdirs()
            val pending = File(output.path + ".pending.mp4")
            if (pending.exists()) pending.delete()

            val portrait = orientation != "landscape"
            val width = if (portrait) 720 else 1280
            val height = if (portrait) 1280 else 720
            val items = inputFiles.mapIndexed { index, file ->
                val effects = mutableListOf<androidx.media3.common.Effect>(
                    Presentation.createForWidthAndHeight(
                        width, height, Presentation.LAYOUT_SCALE_TO_FIT
                    )
                )
                val label = labels[index].trim()
                if (label.isNotEmpty()) {
                    val caption = SpannableString(label.take(80))
                    caption.setSpan(
                        ForegroundColorSpan(Color.WHITE), 0, caption.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    caption.setSpan(
                        StyleSpan(Typeface.BOLD), 0, caption.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    val placement = StaticOverlaySettings.Builder()
                        .setBackgroundFrameAnchor(0f, -0.78f)
                        .build()
                    effects.add(
                        OverlayEffect(listOf(TextOverlay.createStaticTextOverlay(caption, placement)))
                    )
                }
                EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(file)))
                    .setEffects(Effects(emptyList(), effects))
                    .build()
            }
            val sequence = EditedMediaItemSequence.withAudioAndVideoFrom(items)
            val composition = Composition.Builder(sequence).build()
            val transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        exporting = null
                        try {
                            if (!pending.isFile || pending.length() == 0L) {
                                throw IllegalStateException("Export produced no film")
                            }
                            if (!pending.renameTo(output)) {
                                throw IllegalStateException("Could not save completed film")
                            }
                            result.success(output.path)
                        } catch (error: Exception) {
                            pending.delete()
                            result.error("EXPORT", error.message, null)
                        }
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exception: ExportException
                    ) {
                        exporting = null
                        pending.delete()
                        result.error("EXPORT", exception.message, null)
                    }
                })
                .build()
            exporting = transformer
            transformer.start(composition, pending.path)
        } catch (error: Exception) {
            exporting = null
            result.error("EXPORT", error.message, null)
        }
    }

    private fun saveToGallery(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("INPUT", "Missing film path", null)
            return
        }
        try {
            val film = privateFile(path)
            require(film.isFile && film.length() > 0) { "Film not found" }
            val base = (call.argument<String>("title") ?: "1Day")
                .replace(Regex("[^\\p{L}\\p{N} _-]"), "")
                .take(48)
                .ifBlank { "1Day" }
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, "${base}_1Day.mp4")
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/1Day")
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
            }
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }
            val uri = context.contentResolver.insert(collection, values)
                ?: throw IllegalStateException("Could not create gallery entry")
            try {
                context.contentResolver.openOutputStream(uri)?.use { output ->
                    film.inputStream().use { input -> input.copyTo(output) }
                } ?: throw IllegalStateException("Could not open gallery entry")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    context.contentResolver.update(uri, ContentValues().apply {
                        put(MediaStore.Video.Media.IS_PENDING, 0)
                    }, null, null)
                }
                result.success(uri.toString())
            } catch (error: Exception) {
                context.contentResolver.delete(uri, null, null)
                throw error
            }
        } catch (error: Exception) {
            result.error("GALLERY", error.message, null)
        }
    }

    fun dispose() {
        exporting?.cancel()
        exporting = null
    }
}
