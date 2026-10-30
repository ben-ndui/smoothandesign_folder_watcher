package com.smoothandesign.smoothandesign_folder_watcher

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.io.File
import java.io.FileOutputStream

private const val REQUEST_CODE_PICK_DIRECTORY = 53291

/**
 * Choisir un dossier (Storage Access Framework) et lister son contenu sur
 * Android.
 *
 * Un fichier listé est adressé par son `content://` URI, pas un chemin
 * disque réel (SAF ne donne jamais de vrai chemin) — [copyToLocalFile]
 * copie le fichier choisi dans le cache de l'app pour obtenir un chemin
 * réel exploitable par le reste de l'app (upload, etc.).
 *
 * Pas de surveillance native ici : un `ContentObserver` sur un arbre SAF
 * n'est fiable que sur certains fournisseurs. Le polling est géré côté
 * Dart, uniforme avec iOS. Voir smoothandesign_folder_watcher.dart.
 */
class SmoothandesignFolderWatcherPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pendingResult: Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "smoothandesign_folder_watcher/methods")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "pickDirectory" -> pickDirectory(result)
            "listFiles" -> {
                val bookmark = call.argument<ByteArray>("bookmark")
                if (bookmark == null) {
                    result.error("INVALID_ARGUMENTS", "bookmark manquant", null)
                } else {
                    listFiles(bookmark, result)
                }
            }
            "copyToLocalFile" -> {
                val fileUri = call.argument<String>("fileUri")
                if (fileUri == null) {
                    result.error("INVALID_ARGUMENTS", "fileUri manquant", null)
                } else {
                    copyToLocalFile(fileUri, result)
                }
            }
            "startWatching", "stopWatching" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun pickDirectory(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Impossible d'ouvrir le sélecteur", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        currentActivity.startActivityForResult(intent, REQUEST_CODE_PICK_DIRECTORY)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_PICK_DIRECTORY) return false

        val result = pendingResult
        pendingResult = null
        val uri = data?.data
        val currentActivity = activity
        if (resultCode != Activity.RESULT_OK || uri == null || currentActivity == null) {
            result?.success(null)
            return true
        }

        currentActivity.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION
        )

        val doc = DocumentFile.fromTreeUri(currentActivity, uri)
        val displayPath = doc?.name ?: uri.toString()
        result?.success(
            mapOf(
                "path" to displayPath,
                "bookmark" to uri.toString().toByteArray(Charsets.UTF_8)
            )
        )
        return true
    }

    private fun listFiles(bookmark: ByteArray, result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Contexte indisponible", null)
            return
        }
        val uri = Uri.parse(String(bookmark, Charsets.UTF_8))
        val doc = DocumentFile.fromTreeUri(currentActivity, uri)
        if (doc == null || !doc.isDirectory) {
            result.error("ACCESS_DENIED", "Accès au dossier refusé", null)
            return
        }

        val files = doc.listFiles()
            .filter { it.isFile }
            .map { file ->
                mapOf(
                    "name" to (file.name ?: ""),
                    // content:// URI, pas un chemin disque — voir copyToLocalFile.
                    "path" to file.uri.toString(),
                    "modifiedAtEpochSeconds" to (file.lastModified() / 1000.0),
                    "sizeBytes" to file.length().toInt()
                )
            }
        result.success(files)
    }

    private fun copyToLocalFile(fileUriString: String, result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Contexte indisponible", null)
            return
        }
        try {
            val uri = Uri.parse(fileUriString)
            val fileName = DocumentFile.fromSingleUri(currentActivity, uri)?.name ?: "fichier"
            val destFile = File(currentActivity.cacheDir, fileName)
            currentActivity.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destFile).use { output -> input.copyTo(output) }
            } ?: run {
                result.error("COPY_FAILED", "Impossible de lire le fichier", null)
                return
            }
            result.success(destFile.absolutePath)
        } catch (e: Exception) {
            result.error("COPY_FAILED", e.message, null)
        }
    }
}
