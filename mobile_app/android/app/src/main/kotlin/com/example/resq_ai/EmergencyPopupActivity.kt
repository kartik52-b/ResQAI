package com.example.resq_ai

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import io.flutter.embedding.android.FlutterActivity

/**
 * Full-screen native Android emergency popup.
 *
 * Opens over the lock screen when an emergency is detected.
 * Shows "ARE YOU ALRIGHT?" with a 120-second countdown.
 *
 * Buttons:
 * - I'M OK → cancel emergency, close popup
 * - I NEED HELP → trigger emergency workflow immediately
 *
 * Timeout → auto-trigger emergency workflow.
 *
 * Communicates with ResQMonitoringService via broadcasts:
 * - ACTION_EMERGENCY_OK   → user pressed I'M OK
 * - ACTION_EMERGENCY_HELP → user pressed I NEED HELP
 * - ACTION_EMERGENCY_TIMEOUT → countdown expired
 */
class EmergencyPopupActivity : AppCompatActivity() {

    companion object {
        const val TAG = "ResQ_EmergencyPopup"
        const val EXTRA_EMERGENCY_EVENT_ID = "emergency_event_id"
        const val EXTRA_COUNTDOWN_SECONDS = "countdown_seconds"

        const val ACTION_EMERGENCY_OK = "com.example.resq_ai.EMERGENCY_OK"
        const val ACTION_EMERGENCY_HELP = "com.example.resq_ai.EMERGENCY_HELP"
        const val ACTION_EMERGENCY_TIMEOUT = "com.example.resq_ai.EMERGENCY_TIMEOUT"
        const val ACTION_DISMISS_POPUP = "com.example.resq_ai.DISMISS_POPUP"

        const val DEFAULT_COUNTDOWN_SECONDS = 120

        private const val COUNTDOWN_TICK_MS = 1000L

        /** Track whether a popup is currently active to prevent duplicates. */
        @Volatile
        var isShowing = false
            private set
    }

    private var countdownTimer: CountDownTimer? = null
    private var eventId: String = ""
    private var remainingSeconds = DEFAULT_COUNTDOWN_SECONDS
    private val handler = Handler(Looper.getMainLooper())
    private var dismissed = false

    // Receiver to dismiss popup when emergency is resolved from Flutter
    private val dismissReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_DISMISS_POPUP) {
                val targetEventId = intent.getStringExtra(EXTRA_EMERGENCY_EVENT_ID)
                if (targetEventId == null || targetEventId == eventId) {
                    Log.d(TAG, "Received dismiss broadcast — closing popup")
                    dismissed = true
                    finishAndRemoveTask()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Prevent duplicate popups
        if (isShowing) {
            Log.w(TAG, "Popup already showing — closing duplicate instance")
            finishAndRemoveTask()
            return
        }

        // Keep screen on and show over lock screen
        setupWindow()

        setContentView(R.layout.activity_emergency_popup)

        // Parse extras
        eventId = intent.getStringExtra(EXTRA_EMERGENCY_EVENT_ID)
            ?: "emergency-${System.currentTimeMillis()}"
        val countdownSeconds = intent.getIntExtra(EXTRA_COUNTDOWN_SECONDS, DEFAULT_COUNTDOWN_SECONDS)
        remainingSeconds = countdownSeconds

        isShowing = true
        Log.d(TAG, "Emergency popup opened — event: $eventId, countdown: ${countdownSeconds}s")

        // Wire up buttons
        val btnImOk = findViewById<Button>(R.id.btnImOk)
        val btnINeedHelp = findViewById<Button>(R.id.btnINeedHelp)
        val tvCountdown = findViewById<TextView>(R.id.tvCountdown)

        btnImOk.setOnClickListener {
            Log.d(TAG, "User pressed I'M OK — cancelling emergency")
            dismissed = true
            broadcastResult(ACTION_EMERGENCY_OK)
            countdownTimer?.cancel()
            dismissPopup()
        }

        btnINeedHelp.setOnClickListener {
            Log.d(TAG, "User pressed I NEED HELP — triggering emergency")
            dismissed = true
            broadcastResult(ACTION_EMERGENCY_HELP)
            countdownTimer?.cancel()
            dismissPopup()
        }

        // Start countdown
        startCountdown(tvCountdown, countdownSeconds)

        // Register dismiss receiver
        val filter = IntentFilter(ACTION_DISMISS_POPUP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(dismissReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(dismissReceiver, filter)
        }
    }

    private fun setupWindow() {
        // Show over lock screen
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }

        // Keep screen on
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun startCountdown(tvCountdown: TextView, totalSeconds: Int) {
        countdownTimer?.cancel()

        countdownTimer = object : CountDownTimer(
            totalSeconds * 1000L,
            COUNTDOWN_TICK_MS
        ) {
            override fun onTick(millisUntilFinished: Long) {
                if (dismissed) {
                    cancel()
                    return
                }

                remainingSeconds = ((millisUntilFinished + 500) / 1000).toInt()
                val minutes = remainingSeconds / 60
                val seconds = remainingSeconds % 60
                tvCountdown.text = String.format("%02d:%02d", minutes, seconds)
            }

            override fun onFinish() {
                if (dismissed) return
                Log.d(TAG, "Countdown expired — auto-confirming emergency")
                remainingSeconds = 0
                tvCountdown.text = "00:00"
                broadcastResult(ACTION_EMERGENCY_TIMEOUT)
                dismissPopup()
            }
        }.start()
    }

    private fun broadcastResult(action: String) {
        val intent = Intent(action).apply {
            putExtra(EXTRA_EMERGENCY_EVENT_ID, eventId)
            setPackage(packageName)
        }
        sendBroadcast(intent)
        Log.d(TAG, "Broadcast sent: $action (event: $eventId)")
    }

    private fun dismissPopup() {
        isShowing = false
        countdownTimer?.cancel()
        handler.postDelayed({
            try {
                if (!isFinishing) {
                    finishAndRemoveTask()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error dismissing popup: ${e.message}")
            }
        }, 300)
    }

    override fun onDestroy() {
        isShowing = false
        countdownTimer?.cancel()
        try {
            unregisterReceiver(dismissReceiver)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    // Prevent back button from dismissing the emergency popup
    @Deprecated("Use OnBackPressedCallback instead")
    override fun onBackPressed() {
        // Do nothing — user must choose I'M OK or I NEED HELP
    }
}
