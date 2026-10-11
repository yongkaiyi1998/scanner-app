package com.example.scanner_app

import android.app.Activity
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

internal class DocumentScannerChannel(
    private val activity: FragmentActivity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "scanner_app/document_scanner")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val pages = ConcurrentHashMap<String, Uri>()
    private val streams = mutableMapOf<String, InputStream>()
    private var pending: MethodChannel.Result? = null
    private var closed = false
    private val initializationTimeout = Runnable { fail("initialization") }
    private val maxBytes = 40L * 1024 * 1024

    private val launcher = activity.registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult(),
    ) { response ->
        if (pending == null) return@registerForActivityResult
        if (response.resultCode == Activity.RESULT_CANCELED) {
            complete(null)
        } else if (response.resultCode != Activity.RESULT_OK) {
            fail("unexpected")
        } else {
            try {
                val result = GmsDocumentScanningResult.fromActivityResultIntent(response.data)
                val resultPages = result?.pages
                if (resultPages.isNullOrEmpty()) {
                    fail("invalid_result")
                } else {
                    val tokens = resultPages.map { page ->
                        val uri = page.imageUri
                        require(uri.scheme == "content" || uri.scheme == "file")
                        val token = UUID.randomUUID().toString()
                        pages[token] = uri
                        token
                    }
                    complete(tokens) // Preserve every returned page, regardless of requested limit.
                }
            } catch (_: Exception) {
                pages.clear()
                fail("invalid_result")
            }
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scan" -> start(result)
                "pageLength", "readPage" -> {
                    val token = call.arguments as? String
                    val uri = token?.let { pages[it] }
                    if (uri == null) {
                        result.error("invalid_result", "Scan input is unavailable", null)
                    } else {
                        worker.execute {
                            try {
                                val value: Any = if (call.method == "pageLength") {
                                    // Do not trust provider metadata; count bounded bytes off the UI thread.
                                    activity.contentResolver.openInputStream(uri).use { input ->
                                        requireNotNull(input)
                                        val buffer = ByteArray(256 * 1024)
                                        var count = 0L
                                        while (count <= maxBytes) {
                                            val read = input.read(buffer)
                                            if (read < 0) break
                                            count += read
                                        }
                                        count
                                    }
                                } else {
                                    val input = streams.getOrPut(token!!) {
                                        requireNotNull(activity.contentResolver.openInputStream(uri))
                                    }
                                    val buffer = ByteArray(256 * 1024)
                                    val count = input.read(buffer)
                                    if (count < 0) ByteArray(0) else buffer.copyOf(count)
                                }
                                main.post { result.success(value) }
                            } catch (_: Exception) {
                                main.post { result.error("invalid_result", "Scan input is unreadable", null) }
                            }
                        }
                    }
                }
                "releasePages" -> worker.execute {
                    release()
                    main.post { result.success(null) }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun start(result: MethodChannel.Result) {
        if (closed || pending != null || pages.isNotEmpty()) {
            result.error("interrupted", "Scanner is busy or unavailable", null)
            return
        }
        if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(activity) != ConnectionResult.SUCCESS) {
            result.error("unavailable", "Google Play services is unavailable", null)
            return
        }
        pending = result
        main.postDelayed(initializationTimeout, 120_000)
        try {
            val options = GmsDocumentScannerOptions.Builder()
                .setGalleryImportAllowed(false)
                .setPageLimit(10)
                .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_BASE)
                .build()
            GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
                .addOnSuccessListener { sender ->
                    if (closed || pending !== result) return@addOnSuccessListener
                    main.removeCallbacks(initializationTimeout)
                    try {
                        launcher.launch(IntentSenderRequest.Builder(sender).build())
                    } catch (_: Exception) {
                        fail("unexpected")
                    }
                }
                .addOnFailureListener { error ->
                    if (pending !== result) return@addOnFailureListener
                    fail(if (error is MlKitException && error.errorCode == MlKitException.UNSUPPORTED) "unsupported" else "initialization")
                }
        } catch (_: Exception) {
            fail("initialization")
        }
    }

    private fun complete(value: Any?) {
        main.removeCallbacks(initializationTimeout)
        val result = pending
        pending = null
        result?.success(value)
    }

    private fun fail(code: String) {
        main.removeCallbacks(initializationTimeout)
        val result = pending
        pending = null
        result?.error(code, "Document scanner could not complete", null)
    }

    private fun release() {
        streams.values.forEach { try { it.close() } catch (_: Exception) { } }
        streams.clear()
        pages.clear()
    }

    fun close() {
        closed = true
        fail("interrupted")
        channel.setMethodCallHandler(null)
        worker.execute { release() }
        worker.shutdown()
        launcher.unregister()
    }
}
