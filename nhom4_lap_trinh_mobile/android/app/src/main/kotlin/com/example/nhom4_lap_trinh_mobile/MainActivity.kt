package com.example.nhom4_lap_trinh_mobile

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val MEDIA_SAVE_CHANNEL = "com.example.nhom4_lap_trinh_mobile/media_save"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_SAVE_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "saveImageToDownloadsAndGallery") {
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName") ?: "signed_certificate.jpg"
                val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"

                if (bytes == null || bytes.isEmpty()) {
                    result.error("INVALID_ARGS", "Dữ liệu tệp rỗng", null)
                    return@setMethodCallHandler
                }

                try {
                    val downloadsOk = saveBytesToDownloads(bytes, fileName, mimeType)
                    val galleryOk = if (mimeType.startsWith("image/")) {
                        saveBytesToGallery(bytes, fileName, mimeType)
                    } else {
                        false
                    }

                    result.success(
                        mapOf(
                            "downloadsSaved" to downloadsOk,
                            "gallerySaved" to galleryOk,
                            "downloadsPath" to "Download/CertChain/$fileName",
                            "galleryPath" to if (galleryOk) "Pictures/CertChain/$fileName" else null
                        )
                    )
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message ?: "Không thể lưu tệp", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun saveBytesToDownloads(bytes: ByteArray, fileName: String, mimeType: String): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/CertChain"
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return false
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: return false
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        } else {
            @Suppress("DEPRECATION")
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "CertChain"
            )
            if (!dir.exists()) dir.mkdirs()
            val outFile = File(dir, fileName)
            outFile.writeBytes(bytes)
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(outFile.absolutePath),
                arrayOf(mimeType),
                null
            )
            true
        }
    }

    private fun saveBytesToGallery(bytes: ByteArray, fileName: String, mimeType: String): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_PICTURES}/CertChain"
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: return false
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: return false
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        } else {
            @Suppress("DEPRECATION")
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                "CertChain"
            )
            if (!dir.exists()) dir.mkdirs()
            val outFile = File(dir, fileName)
            outFile.writeBytes(bytes)
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(outFile.absolutePath),
                arrayOf(mimeType),
                null
            )
            true
        }
    }
}
