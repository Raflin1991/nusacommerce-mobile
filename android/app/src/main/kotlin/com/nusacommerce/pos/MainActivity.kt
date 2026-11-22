package com.nusacommerce.pos

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val VOICE_CHANNEL = "com.nusacommerce.mobile/voice"
        private const val REQUEST_CODE_VOICE = 7105
    }

    private var voiceChannel: MethodChannel? = null
    private var pendingVoiceResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        voiceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_CHANNEL)
        voiceChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isVoiceRecognitionAvailable" -> {
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    result.success(intent.resolveActivity(packageManager) != null)
                }

                "startVoiceRecognition" -> {
                    if (pendingVoiceResult != null) {
                        result.error(
                            "VOICE_BUSY",
                            "Pengenalan suara sedang aktif. Selesaikan sesi sebelumnya terlebih dahulu.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    val rawLocale = call.argument<String>("locale")?.trim().orEmpty()
                    val locale = if (rawLocale.isNotEmpty()) rawLocale else "id-ID"
                    val rawPrompt = call.argument<String>("prompt")?.trim().orEmpty()
                    val prompt = if (rawPrompt.isNotEmpty()) {
                        rawPrompt
                    } else {
                        "Ucapkan pertanyaan untuk NusaCopilot..."
                    }

                    launchVoiceRecognizer(locale, prompt, result)
                }

                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun launchVoiceRecognizer(
        locale: String,
        prompt: String,
        result: MethodChannel.Result
    ) {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
            putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, false)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

        if (intent.resolveActivity(packageManager) == null) {
            result.error(
                "VOICE_UNAVAILABLE",
                "Layanan pengenalan suara Android tidak tersedia di perangkat ini.",
                null
            )
            return
        }

        pendingVoiceResult = result
        try {
            startActivityForResult(intent, REQUEST_CODE_VOICE)
        } catch (e: ActivityNotFoundException) {
            pendingVoiceResult = null
            result.error(
                "VOICE_UNAVAILABLE",
                "Aplikasi pengenalan suara tidak ditemukan di perangkat ini.",
                e.localizedMessage
            )
        } catch (e: Exception) {
            pendingVoiceResult = null
            result.error(
                "VOICE_LAUNCH_FAILED",
                "Gagal membuka pengenalan suara: ${e.localizedMessage ?: "unknown"}",
                null
            )
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CODE_VOICE) return

        val callback = pendingVoiceResult
        pendingVoiceResult = null
        if (callback == null) return

        if (resultCode == Activity.RESULT_OK) {
            val matches = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            val transcript = matches?.firstOrNull()?.trim().orEmpty()
            callback.success(transcript)
        } else {
            // User cancelled or dismissed speech prompt cleanly -> return empty string for fallback UX.
            callback.success("")
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        voiceChannel?.setMethodCallHandler(null)
        voiceChannel = null
        val pending = pendingVoiceResult
        pendingVoiceResult = null
        if (pending != null) {
            runCatching { pending.success("") }
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        val pending = pendingVoiceResult
        pendingVoiceResult = null
        if (pending != null) {
            runCatching { pending.success("") }
        }
        super.onDestroy()
    }
}
