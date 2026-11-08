package com.smsgate.android_gateway

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SMSGateBootReceiver"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_SERVICE_ENABLED = "flutter.gateway_service_enabled"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        Log.d(TAG, "Received broadcast action: $action")

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val isEnabled = prefs.getBoolean(KEY_SERVICE_ENABLED, false)

            Log.d(TAG, "Gateway autostart on boot enabled: $isEnabled")

            if (isEnabled) {
                // Verify SEND_SMS permission before starting background service
                val hasSmsPermission = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.SEND_SMS
                ) == PackageManager.PERMISSION_GRANTED

                if (hasSmsPermission) {
                    val serviceIntent = Intent(context, GatewayForegroundService::class.java).apply {
                        this.action = GatewayForegroundService.ACTION_START
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ContextCompat.startForegroundService(context, serviceIntent)
                        } else {
                            context.startService(serviceIntent)
                        }
                        Log.i(TAG, "Successfully restarted GatewayForegroundService after boot")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start GatewayForegroundService on boot: ${e.message}", e)
                    }
                } else {
                    Log.w(TAG, "Cannot start service on boot: SEND_SMS permission not granted")
                }
            }
        }
    }
}

