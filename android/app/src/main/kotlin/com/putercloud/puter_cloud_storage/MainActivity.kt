package com.putercloud.puter_cloud_storage

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/**
 * Hosts the Flutter UI and implements the one platform capability the app
 * needs: moving files across the boundary between the app and the device.
 *
 * Deliberately hand-written rather than delegated to a plugin. The obvious
 * plugins pin `compileSdk 34` against this app's 36 (docs/build-assessment.md
 * §4.4–4.5), and the whole surface is three operations over APIs that have been
 * stable since Android 4.4.
 *
 * Everything here uses the **Storage Access Framework**, which grants access to
 * exactly the URI the user picked. That is why the app declares no storage
 * permission at all — not even on Android 13, where `READ_MEDIA_*` would
 * otherwise be needed to reach the user's files.
 */
class MainActivity : FlutterActivity() {

    /** The Dart call waiting on a picker or export result, if any. */
    private var pendingResult: MethodChannel.Result? = null

    /**
     * The file being exported.
     *
     * Held across the picker round trip because `onActivityResult` delivers only
     * the destination URI, and the bytes have to come from somewhere.
     */
    private var pendingExportSource: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFiles" -> pickFiles(result)
                    "exportFile" -> exportFile(
                        call.argument<String>("path"),
                        call.argument<String>("fileName"),
                        call.argument<String>("mimeType"),
                        result,
                    )
                    "openFile" -> openFile(
                        call.argument<String>("path"),
                        call.argument<String>("mimeType"),
                        result,
                    )
                    "openUrl" -> openUrl(call.argument<String>("url"), result)
                    "discardStagedUpload" -> discardStagedUpload(
                        call.argument<String>("path"),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    // ---------------------------------------------------------------- picking

    /**
     * Let the user choose files, then copy each into the app cache.
     *
     * The copy is not an optimisation, it is the point: Dart's `dart:io` cannot
     * read a `content://` URI, and the transport streams uploads from a real
     * file. Copying first turns a SAF URI into something the uploader can
     * `openRead()`.
     *
     * The cache is the right home for it — the OS reclaims that space on its
     * own, and an abandoned upload leaves nothing permanent behind.
     */
    private fun pickFiles(result: MethodChannel.Result) {
        if (!claim(result)) return

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        try {
            startActivityForResult(intent, REQUEST_PICK)
        } catch (error: ActivityNotFoundException) {
            clearPending()
            result.error("unavailable", "No file picker is available.", null)
        }
    }

    private fun handlePickedFiles(data: Intent?) {
        val uris = mutableListOf<Uri>()
        data?.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                uris.add(clip.getItemAt(index).uri)
            }
        }
        data?.data?.let { if (uris.isEmpty()) uris.add(it) }

        val picked = mutableListOf<Map<String, Any?>>()
        for (uri in uris) {
            val copied = copyToCache(uri) ?: continue
            picked.add(
                mapOf(
                    "path" to copied.absolutePath,
                    "name" to displayName(uri, copied.name),
                    "size" to copied.length(),
                )
            )
        }
        pendingResult?.success(picked)
        clearPending()
    }

    /**
     * Copy a picked document into app storage under a directory of its own.
     *
     * One directory per pick, so two files with the same name chosen from
     * different folders cannot overwrite each other between selection and
     * upload.
     *
     * **`filesDir`, not `cacheDir`.** This was the cache, which Android is free
     * to empty whenever it wants space — including while an upload is sitting in
     * the queue waiting its turn. A queued upload whose source has been evicted
     * fails with "local file does not exist" and looks like a bug in the upload
     * rather than in where the file was put. The app deletes these itself once
     * each upload is done, via [discardStagedUpload].
     */
    private fun copyToCache(uri: Uri): File? {
        return try {
            val directory = File(stagingRoot(), UUID.randomUUID().toString())
            directory.mkdirs()
            val target = File(directory, displayName(uri, "upload"))
            contentResolver.openInputStream(uri).use { input ->
                if (input == null) return null
                FileOutputStream(target).use { output -> input.copyTo(output) }
            }
            target
        } catch (error: Exception) {
            null
        }
    }

    /** Where picked files are staged until their upload finishes. */
    private fun stagingRoot(): File = File(filesDir, "uploads").apply { mkdirs() }

    /**
     * Delete a staged upload once it is no longer needed.
     *
     * Called by the transfer engine after a successful upload, and when the
     * user removes a task from the queue.
     *
     * Refuses to touch anything outside the staging root. The path arrives over
     * a method channel, and a deletion helper that trusts its argument is one
     * bug away from removing something the user cares about — so this checks
     * containment rather than assuming the caller is correct.
     */
    private fun discardStagedUpload(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.success(false)
            return
        }

        val target = try {
            File(path).canonicalFile
        } catch (error: Exception) {
            result.success(false)
            return
        }
        val root = try {
            stagingRoot().canonicalFile
        } catch (error: Exception) {
            result.success(false)
            return
        }

        if (!target.path.startsWith(root.path + File.separator)) {
            result.success(false)
            return
        }

        val removed = try {
            val deleted = !target.exists() || target.delete()
            // Remove the per-pick directory too, so a long session does not
            // leave hundreds of empty folders behind.
            target.parentFile?.let { parent ->
                if (parent.path.startsWith(root.path + File.separator)) {
                    parent.delete()
                }
            }
            deleted
        } catch (error: Exception) {
            false
        }
        result.success(removed)
    }

    /** The document's display name, falling back when the provider omits one. */
    private fun displayName(uri: Uri, fallback: String): String {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, null, null, null, null)
            val index = cursor?.getColumnIndex(OpenableColumns.DISPLAY_NAME) ?: -1
            if (cursor != null && cursor.moveToFirst() && index >= 0) {
                cursor.getString(index) ?: fallback
            } else {
                fallback
            }
        } catch (error: Exception) {
            fallback
        } finally {
            cursor?.close()
        }
    }

    // ----------------------------------------------------------------- export

    /** Write a downloaded file to a location the user chooses. */
    private fun exportFile(
        sourcePath: String?,
        fileName: String?,
        mimeType: String?,
        result: MethodChannel.Result,
    ) {
        val source = sourcePath?.let { File(it) }
        if (source == null || !source.exists()) {
            result.error("missing", "The downloaded file is no longer on disk.", null)
            return
        }
        if (!claim(result)) return

        pendingExportSource = source
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType ?: "*/*"
            putExtra(Intent.EXTRA_TITLE, fileName ?: source.name)
        }

        try {
            startActivityForResult(intent, REQUEST_EXPORT)
        } catch (error: ActivityNotFoundException) {
            clearPending()
            result.error("unavailable", "No document provider is available.", null)
        }
    }

    private fun handleExportDestination(data: Intent?) {
        val source = pendingExportSource
        val uri = data?.data
        if (source == null || uri == null) {
            pendingResult?.success(false)
            clearPending()
            return
        }

        val copied = try {
            var wrote = false
            contentResolver.openOutputStream(uri).use { output ->
                if (output != null) {
                    source.inputStream().use { input -> input.copyTo(output) }
                    wrote = true
                }
            }
            wrote
        } catch (error: Exception) {
            false
        }

        pendingResult?.success(copied)
        clearPending()
    }

    // ------------------------------------------------------------------- open

    /**
     * Hand a downloaded file to whatever app can display it.
     *
     * Goes through [FileProvider] because `file://` URIs have been rejected
     * since Android 7: passing one throws `FileUriExposedException`, which would
     * crash the app at exactly the moment the user asked to see their file.
     *
     * Falls back to a chooser when nothing claims the MIME type, so an unusual
     * format still reaches the user instead of dead-ending.
     */
    private fun openFile(
        path: String?,
        mimeType: String?,
        result: MethodChannel.Result,
    ) {
        val file = path?.let { File(it) }
        if (file == null || !file.exists()) {
            result.error("missing", "The file is no longer on disk.", null)
            return
        }

        val resolved = mimeType ?: "*/*"
        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (error: Exception) {
            result.success(false)
            return
        }

        try {
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, resolved)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            )
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            try {
                val share = Intent(Intent.ACTION_SEND).apply {
                    type = resolved
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(share, file.name))
                result.success(true)
            } catch (fallback: Exception) {
                result.success(false)
            }
        }
    }

    // -------------------------------------------------------------- open a URL

    /**
     * Open an https URL in whatever browser the device has.
     *
     * Exists so links are actually tappable. The app previously told users to
     * long-press an address and copy it, which is a developer's workaround, not
     * a user interface.
     *
     * Only http and https are allowed through: this is reachable from strings
     * that came off the network, and forwarding an arbitrary scheme to
     * `ACTION_VIEW` would let a remote value launch another app's deep link.
     */
    private fun openUrl(url: String?, result: MethodChannel.Result) {
        if (url.isNullOrBlank()) {
            result.success(false)
            return
        }
        val parsed = try {
            Uri.parse(url)
        } catch (error: Exception) {
            result.success(false)
            return
        }
        val scheme = parsed.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") {
            result.success(false)
            return
        }

        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, parsed).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            result.success(false)
        } catch (error: Exception) {
            result.success(false)
        }
    }

    // ------------------------------------------------------- result plumbing

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (pendingResult == null) return
        val cancelled = resultCode != Activity.RESULT_OK

        when (requestCode) {
            REQUEST_PICK ->
                if (cancelled) {
                    pendingResult?.success(emptyList<Map<String, Any?>>())
                    clearPending()
                } else {
                    handlePickedFiles(data)
                }

            REQUEST_EXPORT ->
                if (cancelled) {
                    pendingResult?.success(false)
                    clearPending()
                } else {
                    handleExportDestination(data)
                }
        }
    }

    /**
     * Reserve the single in-flight slot.
     *
     * Only one picker can be open at a time, and only one result can own the
     * channel. Refusing the second call is honest; overwriting the first would
     * leave a Dart `await` that never completes.
     */
    private fun claim(result: MethodChannel.Result): Boolean {
        if (pendingResult != null) {
            result.error("busy", "Another file dialog is already open.", null)
            return false
        }
        pendingResult = result
        return true
    }

    private fun clearPending() {
        pendingResult = null
        pendingExportSource = null
    }

    private companion object {
        const val CHANNEL = "com.putercloud.puter_cloud_storage/files"
        const val REQUEST_PICK = 4001
        const val REQUEST_EXPORT = 4002
    }
}
