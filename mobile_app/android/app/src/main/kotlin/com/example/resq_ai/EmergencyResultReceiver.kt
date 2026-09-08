package com.example.resq_ai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * Receives broadcasts from EmergencyPopupActivity and forwards
 * the user's choice (I'M OK / I NEED HELP / timeout) to:
 * 1. ResQMonitoringService (to update notification state)
 * 2. Flutter via MethodChannel (to trigger/cancel emergency workflow)
 */
class EmergencyResultReceiver : BroadcastReceiver() {

    companion object {
        const val TAG = "ResQ_EmergencyReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val eventId = intent.getStringExtra(EmergencyPopupActivity.EXTRA_EMERGENCY_EVENT_ID) ?: ""
        val action = intent.action ?: ""

        Log.d(TAG, "Emergency result received: action=$action, eventId=$eventId")

        when (action) {
            EmergencyPopupActivity.ACTION_EMERGENCY_OK -> {
                Log.d(TAG, "User confirmed OK — cancelling emergency")
                notifyFlutter("onEmergencyUserOk", mapOf("eventId" to eventId))
            }

            EmergencyPopupActivity.ACTION_EMERGENCY_HELP -> {
                Log.d(TAG, "User requested HELP — triggering emergency workflow")
                notifyFlutter("onEmergencyUserHelp", mapOf("eventId" to eventId))
            }

            EmergencyPopupActivity.ACTION_EMERGENCY_TIMEOUT -> {
                Log.d(TAG, "Timeout expired — auto-confirming emergency")
                notifyFlutter("onEmergencyTimeout", mapOf("eventId" to eventId))
            }
        }
    }

    private fun notifyFlutter(method: String, arguments: Map<String, String>) {
        try {
            val channel = ResQMonitoringService.getMethodChannel()
            channel?.invokeMethod(method, arguments)
            Log.d(TAG, "Flutter notified: $method")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to notify Flutter: ${e.message}")
        }
    }
}
