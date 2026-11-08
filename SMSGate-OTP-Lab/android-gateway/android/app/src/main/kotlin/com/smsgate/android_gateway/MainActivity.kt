package com.smsgate.android_gateway

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.smsgate.android_gateway/sms"
    private var methodChannel: MethodChannel? = null

    private val ACTION_SMS_SENT = "com.smsgate.android_gateway.SMS_SENT"
    private val ACTION_SMS_DELIVERED = "com.smsgate.android_gateway.SMS_DELIVERED"

    private var sentReceiver: BroadcastReceiver? = null
    private var deliveredReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        registerSmsReceivers()

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

                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
                        result.error("PERMISSION_DENIED", "SEND_SMS permission is not granted by user", null)
                        return@setMethodCallHandler
                    }

                    try {
                        dispatchSMS(phoneNumber, message, messageId, simSlot)
                        result.success(mapOf("success" to true, "messageId" to messageId, "status" to "Pending"))
                    } catch (e: Exception) {
                        result.error("SMS_DISPATCH_FAILED", e.localizedMessage, null)
                    }
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
                "startForegroundService" -> {
                    try {
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
                        val serviceIntent = Intent(this, GatewayForegroundService::class.java).apply {
                            action = GatewayForegroundService.ACTION_STOP
                        }
                        stopService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_STOP_FAILED", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun normalizePhoneNumber(rawNumber: String): String {
        val cleaned = rawNumber.replace("[\\s\\-()]".toRegex(), "")
        if (cleaned.matches("^[6-9]\\d{9}$".toRegex())) {
            return "+91$cleaned"
        }
        if (cleaned.matches("^0[6-9]\\d{9}$".toRegex())) {
            return "+91${cleaned.substring(1)}"
        }
        if (cleaned.matches("^91[6-9]\\d{9}$".toRegex())) {
            return "+$cleaned"
        }
        return cleaned
    }

    private fun dispatchSMS(phoneNumber: String, message: String, messageId: String, simSlot: Int) {
        val targetPhone = normalizePhoneNumber(phoneNumber)
        val smsManager = getSmsManagerForSlot(simSlot)

        val sentIntent = Intent(ACTION_SMS_SENT).apply {
            putExtra("messageId", messageId)
        }
        val deliveredIntent = Intent(ACTION_SMS_DELIVERED).apply {
            putExtra("messageId", messageId)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val sentPI = PendingIntent.getBroadcast(this, messageId.hashCode(), sentIntent, flags)
        val deliveredPI = PendingIntent.getBroadcast(this, messageId.hashCode() + 1, deliveredIntent, flags)

        val parts = smsManager.divideMessage(message)
        if (parts.size > 1) {
            val sentIntents = ArrayList<PendingIntent>()
            val deliveredIntents = ArrayList<PendingIntent>()
            for (i in parts.indices) {
                sentIntents.add(sentPI)
                deliveredIntents.add(deliveredPI)
            }
            smsManager.sendMultipartTextMessage(targetPhone, null, parts, sentIntents, deliveredIntents)
        } else {
            smsManager.sendTextMessage(targetPhone, null, message, sentPI, deliveredPI)
        }
    }

    @Suppress("DEPRECATION")
    private fun getSmsManagerForSlot(simSlot: Int): SmsManager {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            try {
                val subList = subManager?.activeSubscriptionInfoList
                if (!subList.isNullOrEmpty()) {
                    // 1. Try exact requested slot index
                    for (info in subList) {
                        if (info.simSlotIndex == simSlot) {
                            return createSmsManagerForSub(info.subscriptionId)
                        }
                    }
                    // 2. If requested slot has no active SIM, detect active Airtel SIM
                    for (info in subList) {
                        val carrier = info.carrierName?.toString() ?: ""
                        val display = info.displayName?.toString() ?: ""
                        if (carrier.contains("airtel", ignoreCase = true) || display.contains("airtel", ignoreCase = true)) {
                            return createSmsManagerForSub(info.subscriptionId)
                        }
                    }
                    // 3. Fallback to first active SIM subscription
                    val firstActive = subList.firstOrNull()
                    if (firstActive != null) {
                        return createSmsManagerForSub(firstActive.subscriptionId)
                    }
                }
            } catch (e: SecurityException) {
                // If READ_PHONE_STATE permission is missing, fall back to default
            }
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            SmsManager.getDefault()
        }
    }

    private fun createSmsManagerForSub(subId: Int): SmsManager {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java).createForSubscriptionId(subId)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getSmsManagerForSubscriptionId(subId)
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
                        result.add(
                            mapOf(
                                "slotIndex" to info.simSlotIndex,
                                "carrierName" to (info.carrierName?.toString() ?: "Unknown"),
                                "displayName" to (info.displayName?.toString() ?: "SIM ${info.simSlotIndex + 1}"),
                                "subscriptionId" to info.subscriptionId
                            )
                        )
                    }
                }
            } catch (e: SecurityException) {
                // Permission not yet granted
            }
        }
        return result
    }

    private fun registerSmsReceivers() {
        sentReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val messageId = intent?.getStringExtra("messageId") ?: return
                val status: String
                val errorMessage: String?

                when (resultCode) {
                    Activity.RESULT_OK -> {
                        status = "Sent"
                        errorMessage = null
                    }
                    SmsManager.RESULT_ERROR_GENERIC_FAILURE -> {
                        status = "Failed"
                        errorMessage = "Generic network failure or carrier block (verify Airtel SMS balance and active SIM slot)"
                    }
                    SmsManager.RESULT_ERROR_NO_SERVICE -> {
                        status = "Failed"
                        errorMessage = "No cellular network service available on SIM"
                    }
                    SmsManager.RESULT_ERROR_NULL_PDU -> {
                        status = "Failed"
                        errorMessage = "Null PDU (format rejected by SMSC)"
                    }
                    SmsManager.RESULT_ERROR_RADIO_OFF -> {
                        status = "Failed"
                        errorMessage = "Cellular radio is off or Airplane mode is active"
                    }
                    else -> {
                        status = "Failed"
                        errorMessage = "Unknown carrier error code: $resultCode"
                    }
                }

                methodChannel?.invokeMethod(
                    "onSmsStatusUpdated",
                    mapOf("messageId" to messageId, "status" to status, "errorMessage" to errorMessage)
                )
            }
        }

        deliveredReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val messageId = intent?.getStringExtra("messageId") ?: return
                val status = if (resultCode == Activity.RESULT_OK) "Delivered" else "DeliveryFailed"

                methodChannel?.invokeMethod(
                    "onSmsStatusUpdated",
                    mapOf("messageId" to messageId, "status" to status)
                )
            }
        }

        val sentFilter = IntentFilter(ACTION_SMS_SENT)
        val deliveredFilter = IntentFilter(ACTION_SMS_DELIVERED)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(sentReceiver, sentFilter, Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(deliveredReceiver, deliveredFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(sentReceiver, sentFilter)
            registerReceiver(deliveredReceiver, deliveredFilter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        sentReceiver?.let { unregisterReceiver(it) }
        deliveredReceiver?.let { unregisterReceiver(it) }
    }
}

