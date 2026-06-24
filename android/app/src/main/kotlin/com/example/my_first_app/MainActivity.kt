package com.example.my_first_app

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val channelName = "document_summary/file_reader"
    private val pickTextFileRequestCode = 4201
    private val saveTextFileRequestCode = 4202
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSaveContent: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickTextFile" -> pickTextFile(result)
                "saveTextFile" -> {
                    val arguments = call.arguments as? Map<*, *>
                    saveTextFile(
                        fileName = arguments?.get("fileName") as? String ?: "summary.txt",
                        content = arguments?.get("content") as? String ?: "",
                        result = result,
                    )
                }
                "ocrScannedPdf" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val bytes = arguments?.get("bytes") as? ByteArray

                    if (bytes == null) {
                        result.error("invalid_arguments", "Khong co du lieu PDF de OCR.", null)
                    } else {
                        ocrScannedPdf(bytes, result)
                    }
                }
                "ocrImage" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val bytes = arguments?.get("bytes") as? ByteArray

                    if (bytes == null) {
                        result.error("invalid_arguments", "Khong co du lieu anh de OCR.", null)
                    } else {
                        ocrImage(bytes, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pickTextFile(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "Dang mo trinh chon file.", null)
            return
        }

        pendingResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "text/plain",
                    "text/markdown",
                    "text/csv",
                    "application/json",
                    "application/xml",
                    "application/pdf",
                    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    "image/jpeg",
                    "image/png",
                ),
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        startActivityForResult(
            Intent.createChooser(intent, "Chon file van ban"),
            pickTextFileRequestCode,
        )
    }

    private fun saveTextFile(
        fileName: String,
        content: String,
        result: MethodChannel.Result,
    ) {
        if (pendingResult != null) {
            result.error("busy", "Dang mo trinh chon hoac luu file.", null)
            return
        }

        pendingResult = result
        pendingSaveContent = content

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/plain"
            putExtra(Intent.EXTRA_TITLE, ensureTextFileName(fileName))
        }

        startActivityForResult(
            Intent.createChooser(intent, "Luu ban tom tat"),
            saveTextFileRequestCode,
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            pickTextFileRequestCode -> {
                val result = pendingResult ?: return
                pendingResult = null

                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    result.success(null)
                    return
                }

                readTextFile(data.data!!, result)
            }
            saveTextFileRequestCode -> {
                val result = pendingResult ?: return
                val content = pendingSaveContent ?: ""
                pendingResult = null
                pendingSaveContent = null

                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    result.success(false)
                    return
                }

                writeTextFile(data.data!!, content, result)
            }
        }
    }

    private fun readTextFile(uri: Uri, result: MethodChannel.Result) {
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                input.readBytes()
            } ?: ByteArray(0)

            if (bytes.size > MAX_FILE_BYTES) {
                result.error(
                    "file_too_large",
                    "File qua lon. Hay chon file duoi 20 MB.",
                    null,
                )
                return
            }

            result.success(
                mapOf(
                    "name" to (getDisplayName(uri) ?: "Tai lieu"),
                    "content" to bytes.toString(Charsets.UTF_8),
                    "bytes" to bytes,
                ),
            )
        } catch (error: Exception) {
            result.error(
                "read_failed",
                error.localizedMessage ?: "Khong the doc file da chon.",
                null,
            )
        }
    }

    private fun writeTextFile(uri: Uri, content: String, result: MethodChannel.Result) {
        try {
            contentResolver.openOutputStream(uri)?.use { output ->
                output.write(content.toByteArray(Charsets.UTF_8))
                output.flush()
            } ?: run {
                result.error("write_failed", "Khong the mo file de luu.", null)
                return
            }

            result.success(true)
        } catch (error: Exception) {
            result.error(
                "write_failed",
                error.localizedMessage ?: "Khong the luu file tom tat.",
                null,
            )
        }
    }

    private fun ensureTextFileName(fileName: String): String {
        val trimmedName = fileName.trim().ifEmpty { "summary.txt" }

        return if (trimmedName.endsWith(".txt", ignoreCase = true)) {
            trimmedName
        } else {
            "$trimmedName.txt"
        }
    }

    private fun ocrScannedPdf(bytes: ByteArray, result: MethodChannel.Result) {
        Thread {
            val tempFile = File.createTempFile("scan_", ".pdf", cacheDir)
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

            try {
                FileOutputStream(tempFile).use { output ->
                    output.write(bytes)
                }

                val pageTexts = mutableListOf<String>()
                ParcelFileDescriptor.open(tempFile, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                    PdfRenderer(descriptor).use { renderer ->
                        val pageCount = min(renderer.pageCount, MAX_OCR_PAGES)

                        for (index in 0 until pageCount) {
                            renderer.openPage(index).use { page ->
                                val bitmap = renderPageForOcr(page)
                                val image = InputImage.fromBitmap(bitmap, 0)
                                val text = Tasks.await(recognizer.process(image)).text.trim()
                                bitmap.recycle()

                                if (text.isNotEmpty()) {
                                    pageTexts.add(text)
                                }
                            }
                        }
                    }
                }

                runOnUiThread {
                    result.success(pageTexts.joinToString("\n\n"))
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "ocr_failed",
                        error.localizedMessage ?: "Khong the OCR file PDF scan.",
                        null,
                    )
                }
            } finally {
                recognizer.close()
                tempFile.delete()
            }
        }.start()
    }

    private fun ocrImage(bytes: ByteArray, result: MethodChannel.Result) {
        Thread {
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

            try {
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    ?: throw IllegalArgumentException("Khong the doc anh da chon.")
                val image = InputImage.fromBitmap(bitmap, 0)
                val text = Tasks.await(recognizer.process(image)).text.trim()
                bitmap.recycle()

                runOnUiThread {
                    result.success(text)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "ocr_failed",
                        error.localizedMessage ?: "Khong the OCR anh da chon.",
                        null,
                    )
                }
            } finally {
                recognizer.close()
            }
        }.start()
    }

    private fun renderPageForOcr(page: PdfRenderer.Page): Bitmap {
        val longestSide = max(page.width, page.height)
        val scale = min(MAX_OCR_BITMAP_SIDE.toFloat() / longestSide, 3.0f)
            .coerceAtLeast(0.5f)
        val width = (page.width * scale).roundToInt().coerceAtLeast(1)
        val height = (page.height * scale).roundToInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

        return bitmap
    }

    private fun getDisplayName(uri: Uri): String? {
        return contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                cursor.getString(nameIndex)
            } else {
                null
            }
        }
    }

    companion object {
        private const val MAX_FILE_BYTES = 20 * 1024 * 1024
        private const val MAX_OCR_PAGES = 30
        private const val MAX_OCR_BITMAP_SIDE = 2200
    }
}
