package com.example.resq_ai

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.telephony.SmsManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {

    companion object {
        private const val TAG = "ResQ_MainActivity"
        private const val CHANNEL = "com.example.resq_ai/native_service"
        private const val SMS_PERMISSION_REQUEST = 2001
        private const val CALL_PERMISSION_REQUEST = 2002
        private const val LOCATION_PERMISSION_REQUEST = 2003
        private const val NOTIFICATION_PERMISSION_REQUEST = 2004
        private const val AUDIO_PERMISSION_REQUEST = 2005

        // Delay between continuous listening restarts (ms)
        private const val LISTEN_RESTART_DELAY_MS = 300L
    }

    private var tts: TextToSpeech? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var ttsReady = false
    private var pendingTtsText: String? = null
    private var methodChannel: MethodChannel? = null
    private var speechListening = false

    // Continuous listening state
    private var continuousListening = false
    private val handler = Handler(Looper.getMainLooper())
    private var restartRunnable: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        tts = TextToSpeech(this, this)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ResQMonitoringService.setMethodChannel(methodChannel)

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                // Dismiss emergency notification
                "dismissEmergencyNotification" -> {
                    try {
                        ResQMonitoringService.dismissEmergencyNotificationStatic(this)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to dismiss emergency notification: ${e.message}")
                    }
                    result.success(true)
                }

                // Foreground service control
                "startForegroundService" -> {
                    startMonitoringService()
                    result.success(true)
                }
                "stopForegroundService" -> {
                    stopMonitoringService()
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(ResQMonitoringService.getIsRunning())
                }
                "showEmergencyNotification" -> {
                    val title = call.argument<String>("title") ?: "Emergency"
                    val body = call.argument<String>("body") ?: "Are you alright?"
                    try {
                        val intent = Intent(this, ResQMonitoringService::class.java)
                        intent.action = "SHOW_EMERGENCY"
                        intent.putExtra("title", title)
                        intent.putExtra("body", body)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start emergency notification service: ${e.message}")
                        // Fallback: show notification directly from activity
                        showEmergencyNotificationDirect(title, body)
                    }
                    result.success(true)
                }

                // Text-to-speech
                "speak" -> {
                    val text = call.argument<String>("text") ?: ""
                    speakText(text)
                    result.success(true)
                }
                "stopSpeaking" -> {
                    tts?.stop()
                    result.success(true)
                }

                // One-shot speech recognition (for voice verification during emergency)
                "startListening" -> {
                    continuousListening = false
                    startListeningOnce()
                    result.success(true)
                }
                "stopListening" -> {
                    stopListening()
                    result.success(true)
                }
                "isListening" -> {
                    result.success(speechListening)
                }

                // Continuous speech recognition (for voice emergency trigger)
                "startContinuousListening" -> {
                    continuousListening = true
                    startListeningOnce()
                    result.success(true)
                }
                "stopContinuousListening" -> {
                    continuousListening = false
                    cancelRestart()
                    stopListening()
                    result.success(true)
                }

                // SMS
                "sendSms" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    val smsResult = sendSms(phone, message)
                    result.success(smsResult)
                }

                // Phone call
                "makeCall" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    val callResult = makeCall(phone)
                    result.success(callResult)
                }

                // Permissions
                "requestSmsPermission" -> {
                    requestPermission(Manifest.permission.SEND_SMS, SMS_PERMISSION_REQUEST)
                    result.success(true)
                }
                "requestCallPermission" -> {
                    requestPermission(Manifest.permission.CALL_PHONE, CALL_PERMISSION_REQUEST)
                    result.success(true)
                }
                "requestLocationPermission" -> {
                    requestPermission(Manifest.permission.ACCESS_FINE_LOCATION, LOCATION_PERMISSION_REQUEST)
                    result.success(true)
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        requestPermission(Manifest.permission.POST_NOTIFICATIONS, NOTIFICATION_PERMISSION_REQUEST)
                    }
                    result.success(true)
                }
                "requestAudioPermission" -> {
                    requestPermission(Manifest.permission.RECORD_AUDIO, AUDIO_PERMISSION_REQUEST)
                    result.success(true)
                }
                "checkPermission" -> {
                    val perm = call.argument<String>("permission") ?: ""
                    // Map short names to full Android permission strings
                    val fullPerm = when (perm) {
                        "audio" -> Manifest.permission.RECORD_AUDIO
                        "sms" -> Manifest.permission.SEND_SMS
                        "call" -> Manifest.permission.CALL_PHONE
                        "location" -> Manifest.permission.ACCESS_FINE_LOCATION
                        "notification" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                Manifest.permission.POST_NOTIFICATIONS
                            } else ""
                        }
                        else -> perm
                    }
                    result.success(if (fullPerm.isNotEmpty()) hasPermission(fullPerm) else true)
                }
                "openAppSettings" -> {
                    try {
                        val intent = android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        intent.data = android.net.Uri.fromParts("package", packageName, null)
                        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    } catch (_: Exception) {}
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    // --- Text-to-Speech ---

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale.US
            ttsReady = true
            pendingTtsText?.let {
                speakText(it)
                pendingTtsText = null
            }
        }
    }

    private fun speakText(text: String) {
        if (ttsReady) {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "resq_alert_${System.currentTimeMillis()}")
        } else {
            pendingTtsText = text
        }
    }

    // --- Speech Recognition ---

    private fun startListeningOnce() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.w(TAG, "Speech recognition not available on this device")
            notifyFlutter("onSpeechError", "not_available")
            return
        }

        if (!hasPermission(Manifest.permission.RECORD_AUDIO)) {
            Log.w(TAG, "RECORD_AUDIO permission not granted")
            notifyFlutter("onSpeechError", "permission_denied")
            return
        }

        // Clean up previous recognizer
        cleanupRecognizer()

        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                speechListening = true
                notifyFlutter("onListeningStarted", null)
            }

            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}

            override fun onEndOfSpeech() {
                speechListening = false
            }

            override fun onError(error: Int) {
                speechListening = false
                val errorMsg = when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH -> "no_match"
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "timeout"
                    SpeechRecognizer.ERROR_AUDIO -> "audio_error"
                    SpeechRecognizer.ERROR_CLIENT -> "client_error"
                    SpeechRecognizer.ERROR_NETWORK -> "network_error"
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network_timeout"
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
                    SpeechRecognizer.ERROR_SERVER -> "server_error"
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission_denied"
                    else -> "error_$error"
                }
                Log.w(TAG, "Speech recognition error: $errorMsg")
                notifyFlutter("onSpeechError", errorMsg)

                // In continuous mode, restart listening after a short delay
                if (continuousListening && errorMsg != "permission_denied" && errorMsg != "not_available") {
                    scheduleRestart()
                }
            }

            override fun onResults(results: Bundle?) {
                speechListening = false
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val bestMatch = matches?.firstOrNull() ?: ""
                Log.d(TAG, "Speech result: $bestMatch")
                notifyFlutter("onSpeechResult", bestMatch)

                // In continuous mode, restart listening after a short delay
                if (continuousListening) {
                    scheduleRestart()
                }
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val bestMatch = matches?.firstOrNull() ?: ""
                if (bestMatch.isNotEmpty()) {
                    notifyFlutter("onSpeechPartialResult", bestMatch)
                }
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-IN") // Support Hindi+English
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        }

        try {
            speechRecognizer?.startListening(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start listening: ${e.message}")
            notifyFlutter("onSpeechError", "start_failed")
            if (continuousListening) {
                scheduleRestart()
            }
        }
    }

    private fun scheduleRestart() {
        cancelRestart()
        restartRunnable = Runnable {
            if (continuousListening && !speechListening) {
                Log.d(TAG, "Restarting continuous speech recognition")
                startListeningOnce()
            }
        }
        handler.postDelayed(restartRunnable!!, LISTEN_RESTART_DELAY_MS)
    }

    private fun cancelRestart() {
        restartRunnable?.let { handler.removeCallbacks(it) }
        restartRunnable = null
    }

    private fun cleanupRecognizer() {
        try {
            speechRecognizer?.stopListening()
        } catch (_: Exception) {}
        try {
            speechRecognizer?.destroy()
        } catch (_: Exception) {}
        speechRecognizer = null
        speechListening = false
    }

    private fun stopListening() {
        cancelRestart()
        cleanupRecognizer()
    }

    // --- SMS ---

    private fun sendSms(phone: String, message: String): Any {
        if (!hasPermission(Manifest.permission.SEND_SMS)) {
            Log.w(TAG, "SMS permission not granted")
            return hashMapOf<String, Any>("success" to false, "error" to "SMS permission not granted")
        }

        if (phone.isEmpty()) {
            return hashMapOf<String, Any>("success" to false, "error" to "No phone number")
        }

        try {
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                this.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }

            val parts = smsManager.divideMessage(message)
            if (parts != null && parts.size > 1) {
                smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(phone, null, message, null, null)
            }

            Log.d(TAG, "SMS sent to $phone")
            return hashMapOf<String, Any>("success" to true, "error" to "")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send SMS: ${e.message}")
            return hashMapOf<String, Any>("success" to false, "error" to (e.message ?: "Unknown error"))
        }
    }

    // --- Phone Call ---

    private fun makeCall(phone: String): Any {
        if (!hasPermission(Manifest.permission.CALL_PHONE)) {
            Log.w(TAG, "CALL_PHONE permission not granted")
            return hashMapOf<String, Any>("success" to false, "error" to "Call permission not granted")
        }

        if (phone.isEmpty()) {
            return hashMapOf<String, Any>("success" to false, "error" to "No phone number")
        }

        try {
            val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$phone"))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            Log.d(TAG, "Call initiated to $phone")
            return hashMapOf<String, Any>("success" to true, "error" to "")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to make call: ${e.message}")
            return hashMapOf<String, Any>("success" to false, "error" to (e.message ?: "Unknown error"))
        }
    }

    // --- Emergency Notification (direct from activity) ---

    private fun showEmergencyNotificationDirect(title: String, body: String) {
        try {
            val channelId = ResQMonitoringService.EMERGENCY_CHANNEL_ID
            val notificationId = ResQMonitoringService.EMERGENCY_NOTIFICATION_ID

            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }

            val pendingIntent = PendingIntent.getActivity(
                this, notificationId, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = NotificationCompat.Builder(this, channelId)
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentIntent(pendingIntent)
                .setAutoCancel(false)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setFullScreenIntent(pendingIntent, true)

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(notificationId, builder.build())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show emergency notification: ${e.message}")
        }
    }

    // --- Foreground Service ---

    private fun startMonitoringService() {
        val intent = Intent(this, ResQMonitoringService::class.java).apply {
            action = ResQMonitoringService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopMonitoringService() {
        val intent = Intent(this, ResQMonitoringService::class.java).apply {
            action = ResQMonitoringService.ACTION_STOP
        }
        startService(intent)
    }

    // --- Permissions ---

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission(permission: String, requestCode: Int) {
        if (!hasPermission(permission)) {
            ActivityCompat.requestPermissions(this, arrayOf(permission), requestCode)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        val permissionName = when (requestCode) {
            SMS_PERMISSION_REQUEST -> "sms"
            CALL_PERMISSION_REQUEST -> "call"
            LOCATION_PERMISSION_REQUEST -> "location"
            NOTIFICATION_PERMISSION_REQUEST -> "notification"
            AUDIO_PERMISSION_REQUEST -> "audio"
            else -> "unknown"
        }
        Log.d(TAG, "Permission $permissionName: granted=$granted")
        notifyFlutter("onPermissionResult", mapOf("permission" to permissionName, "granted" to granted))
    }

    // --- Flutter Communication ---

    private fun notifyFlutter(method: String, arguments: Any?) {
        try {
            methodChannel?.invokeMethod(method, arguments)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to notify Flutter: ${e.message}")
        }
    }

    // --- Lifecycle ---

    override fun onDestroy() {
        continuousListening = false
        cancelRestart()
        stopListening()
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }
}
