package com.smsgate.android_gateway

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.smsgate.android_gateway/sms"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // Register central SmsDispatcher receivers with RECEIVER_EXPORTED
        SmsDispatcher.registerReceivers(this)
        attachServiceListener()

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSMS" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")
                    val messageId = call.argument<String>("messageId") ?: System.currentTimeMillis().toString()
                    val simSlot = call.argument<Int>("simSlot") ?: 0

                    if (phoneNumber.isNullOrEmpty() || message.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENTS", "Phone number and message cannot be empty", null)
                        return@setMethodCallHandler
                    }

                    val dispatched = SmsDispatcher.sendSMS(
                        this,
                        messageId,
                        phoneNumber,
                        message,
                        simSlot,
                        object : SmsDispatcher.SmsCallback {
                            override fun onSent(
                                taskId: String,
                                success: Boolean,
                                resultCode: Int,
                                errorCode: Int,
                                errorMessage: String?
                            ) {
                                runOnUiThread {
                                    val status = if (success) "Sent" else "Failed"
                                    methodChannel?.invokeMethod(
                                        "onSmsStatusUpdated",
                                        mapOf(
                                            "messageId" to taskId,
                                            "status" to status,
                                            "errorMessage" to errorMessage
                                        )
                                    )
                                }
                            }

                            override fun onDelivered(
                                taskId: String,
                                success: Boolean,
                                resultCode: Int,
                                errorMessage: String?
                            ) {
                                runOnUiThread {
                                    val status = if (success) "Delivered" else "DeliveryFailed"
                                    methodChannel?.invokeMethod(
                                        "onSmsStatusUpdated",
                                        mapOf(
                                            "messageId" to taskId,
                                            "status" to status
                                        )
                                    )
                                }
                            }
                        }
                    )

                    result.success(
                        mapOf(
                            "success" to dispatched,
                            "messageId" to messageId,
                            "status" to if (dispatched) "Sending" else "Failed"
                        )
                    )
                }
                "getSimCards" -> {
                    try {
                        val simList = getActiveSimCards()
                        result.success(simList)
                    } catch (e: Exception) {
                        result.error("SIM_FETCH_FAILED", e.localizedMessage, null)
                    }
                }
                "canSendSms" -> {
                    val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                    val isCapable = telephonyManager?.isSmsCapable ?: true
                    result.success(isCapable)
                }
                "isServiceRunning" -> {
                    result.success(GatewayForegroundService.isRunning)
                }
                "getConnectionStatus" -> {
                    result.success(
                        mapOf(
                            "isConnected" to GatewayForegroundService.isConnected,
                            "message" to GatewayForegroundService.lastConnectionStatus
                        )
                    )
                }
                "startForegroundService" -> {
                    try {
                        saveServiceEnabled(true)
                        val serviceIntent = Intent(this, GatewayForegroundService::class.java).apply {
                            action = GatewayForegroundService.ACTION_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_START_FAILED", e.localizedMessage, null)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        saveServiceEnabled(false)
                        val serviceIntent = Intent(this, GatewayForegroundService::class.java).apply {
                            action = GatewayForegroundService.ACTION_STOP
                        }
                        stopService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_STOP_FAILED", e.localizedMessage, null)
                    }
                }
                "syncNativeConfig" -> {
                    val backendUrl = call.argument<String>("backendUrl")
                    val deviceToken = call.argument<String>("deviceToken")
                    val pollingInterval = call.argument<Int>("pollingInterval")
                    val simSlot = call.argument<Int>("simSlot")

                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val editor = prefs.edit()
                    if (backendUrl != null) editor.putString("flutter.backend_server_url", backendUrl)
                    if (deviceToken != null && deviceToken.isNotEmpty()) editor.putString("flutter.gateway_device_token", deviceToken)
                    if (pollingInterval != null) editor.putInt("flutter.polling_interval_seconds", pollingInterval)
                    if (simSlot != null) editor.putInt("flutter.default_sim_slot", simSlot)
                    editor.apply()

                    result.success(true)
                }
                "isBatteryOptimizationIgnored" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        val isIgnored = powerManager?.isIgnoringBatteryOptimizations(packageName) ?: true
                        result.success(isIgnored)
                    } else {
                        result.success(true)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("BATTERY_OPT_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveServiceEnabled(enabled: Boolean) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("flutter.gateway_service_enabled", enabled).apply()
    }

    private fun attachServiceListener() {
        GatewayForegroundService.serviceListener = object : GatewayForegroundService.ServiceListener {
            override fun onStatusUpdate(messageId: String, status: String, errorMessage: String?) {
                runOnUiThread {
                    methodChannel?.invokeMethod(
                        "onSmsStatusUpdated",
                        mapOf(
                            "messageId" to messageId,
                            "status" to status,
                            "errorMessage" to errorMessage
                        )
                    )
                }
            }

            override fun onConnectionChanged(isConnected: Boolean, message: String) {
                runOnUiThread {
                    methodChannel?.invokeMethod(
                        "onConnectionStatusChanged",
                        mapOf(
                            "isConnected" to isConnected,
                            "message" to message
                        )
                    )
                }
            }

            override fun onMessageDispatched(taskMap: Map<String, Any>) {
                runOnUiThread {
                    methodChannel?.invokeMethod("onMessageDispatched", taskMap)
                }
            }
        }
    }

    private fun getActiveSimCards(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            try {
                val list = subManager?.activeSubscriptionInfoList
                if (list != null) {
                    for (info: SubscriptionInfo in list) {
                        val carrier = info.carrierName?.toString() ?: "Unknown"
                        val display = info.displayName?.toString() ?: "SIM ${info.simSlotIndex + 1}"
                        val isAirtel = carrier.contains("airtel", ignoreCase = true) || display.contains("airtel", ignoreCase = true)
                        result.add(
                            mapOf(
                                "slotIndex" to info.simSlotIndex,
                                "carrierName" to carrier,
                                "displayName" to display,
                                "subscriptionId" to info.subscriptionId,
                                "isAirtel" to isAirtel
                            )
                        )
                    }
                }
            } catch (e: SecurityException) {
                Log.w("MainActivity", "READ_PHONE_STATE permission not granted: ${e.message}")
            }
        }
        return result
    }

    override fun onDestroy() {
        GatewayForegroundService.serviceListener = null
        super.onDestroy()
    }
}
