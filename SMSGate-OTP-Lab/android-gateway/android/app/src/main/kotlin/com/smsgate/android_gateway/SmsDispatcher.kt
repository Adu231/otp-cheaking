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
import android.util.Log
import androidx.core.content.ContextCompat
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

object SmsDispatcher {
    const val TAG = "SMSDispatcher"

    const val ACTION_SMS_SENT = "com.smsgate.android_gateway.SMS_SENT_STATUS"
    const val ACTION_SMS_DELIVERED = "com.smsgate.android_gateway.SMS_DELIVERED_STATUS"

    interface SmsCallback {
        fun onSent(taskId: String, success: Boolean, resultCode: Int, errorCode: Int, errorMessage: String?)
        fun onDelivered(taskId: String, success: Boolean, resultCode: Int, errorMessage: String?)
    }

    private var isReceiverRegistered = false
    private val callbacks = ConcurrentHashMap<String, SmsCallback>()
    private val requestCounter = AtomicInteger(1000)

    // Track total parts and received sent callbacks for multipart messages
    private val multipartSentTracker = ConcurrentHashMap<String, AtomicInteger>()
    private val multipartTotalTracker = ConcurrentHashMap<String, Int>()

    private val sentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val taskId = intent?.getStringExtra("taskId") ?: return
            val partIndex = intent.getIntExtra("partIndex", 0)
            val totalParts = intent.getIntExtra("totalParts", 1)
            val errorCode = intent.getIntExtra("errorCode", -1)

            Log.i(
                TAG,
                "[SENT-CALLBACK] Task $taskId (Part $partIndex/$totalParts): resultCode=$resultCode, errorCode=$errorCode"
            )

            val callback = callbacks[taskId]
            val success = (resultCode == Activity.RESULT_OK)

            if (!success) {
                // If any part fails, the message dispatch failed
                val errorDetail = mapResultCodeToMessage(resultCode, errorCode)
                Log.e(TAG, "[SENT-CALLBACK] Task $taskId FAILED: $errorDetail")
                cleanupTask(taskId)
                callback?.onSent(taskId, false, resultCode, errorCode, errorDetail)
                return
            }

            // If multipart, ensure all parts succeeded before marking as Sent
            if (totalParts > 1) {
                val counter = multipartSentTracker.computeIfAbsent(taskId) { AtomicInteger(0) }
                val completed = counter.incrementAndGet()
                if (completed >= totalParts) {
                    Log.i(TAG, "[SENT-CALLBACK] Task $taskId: All $totalParts parts transmitted successfully (RESULT_OK)")
                    cleanupTask(taskId)
                    callback?.onSent(taskId, true, resultCode, errorCode, null)
                } else {
                    Log.d(TAG, "[SENT-CALLBACK] Task $taskId: Part $completed of $totalParts transmitted")
                }
            } else {
                Log.i(TAG, "[SENT-CALLBACK] Task $taskId: Message successfully transmitted to carrier (RESULT_OK)")
                cleanupTask(taskId)
                callback?.onSent(taskId, true, resultCode, errorCode, null)
            }
        }
    }

    private val deliveredReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val taskId = intent?.getStringExtra("taskId") ?: return
            val callback = callbacks[taskId]
            val success = (resultCode == Activity.RESULT_OK)

            Log.i(TAG, "[DELIVERY-CALLBACK] Task $taskId: resultCode=$resultCode")

            if (success) {
                Log.i(TAG, "[DELIVERY-CALLBACK] Task $taskId: Confirmed delivered to recipient handset")
                callback?.onDelivered(taskId, true, resultCode, null)
            } else {
                val errorMsg = "Carrier delivery failure code: $resultCode"
                Log.w(TAG, "[DELIVERY-CALLBACK] Task $taskId: $errorMsg")
                callback?.onDelivered(taskId, false, resultCode, errorMsg)
            }
        }
    }

    private fun cleanupTask(taskId: String) {
        multipartSentTracker.remove(taskId)
        multipartTotalTracker.remove(taskId)
    }

    @Synchronized
    fun registerReceivers(context: Context) {
        if (isReceiverRegistered) return

        val appContext = context.applicationContext
        val sentFilter = IntentFilter(ACTION_SMS_SENT)
        val deliveredFilter = IntentFilter(ACTION_SMS_DELIVERED)

        try {
            // CRITICAL: On Android 13+ (API 33/34), RECEIVER_EXPORTED is mandatory
            // because the broadcast originates from the system telephony process (com.android.phone).
            // Using RECEIVER_NOT_EXPORTED causes the OS to block the broadcast!
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ContextCompat.registerReceiver(
                    appContext,
                    sentReceiver,
                    sentFilter,
                    ContextCompat.RECEIVER_EXPORTED
                )
                ContextCompat.registerReceiver(
                    appContext,
                    deliveredReceiver,
                    deliveredFilter,
                    ContextCompat.RECEIVER_EXPORTED
                )
            } else {
                appContext.registerReceiver(sentReceiver, sentFilter)
                appContext.registerReceiver(deliveredReceiver, deliveredFilter)
            }
            isReceiverRegistered = true
            Log.i(TAG, "SmsDispatcher BroadcastReceivers registered with RECEIVER_EXPORTED")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register SmsDispatcher receivers: ${e.message}", e)
        }
    }

    fun normalizePhoneNumber(rawNumber: String): String {
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

    /**
     * Resolves the active Airtel SIM subscription or user-preferred SIM slot.
     * Prioritizes the active Airtel SIM to ensure messages are submitted via the correct carrier.
     */
    fun resolveSubscription(context: Context, preferredSlot: Int): SubscriptionInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) {
            return null
        }

        val subManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            ?: return null

        val hasPermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_PHONE_STATE
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasPermission) {
            Log.w(TAG, "READ_PHONE_STATE permission not granted; cannot query SubscriptionManager")
            return null
        }

        try {
            val subList = subManager.activeSubscriptionInfoList
            if (subList.isNullOrEmpty()) {
                Log.w(TAG, "activeSubscriptionInfoList is empty or null")
                return null
            }

            Log.i(TAG, "Available Active SIM Subscriptions (${subList.size}):")
            for (info in subList) {
                Log.i(
                    TAG,
                    "  [SIM] Slot: ${info.simSlotIndex}, SubId: ${info.subscriptionId}, Carrier: '${info.carrierName}', Display: '${info.displayName}'"
                )
            }

            // 1. Look for explicit Airtel SIM first (user requirement: Ensure Airtel SIM is actually used)
            val airtelSub = subList.firstOrNull { info ->
                val carrier = info.carrierName?.toString()?.lowercase() ?: ""
                val display = info.displayName?.toString()?.lowercase() ?: ""
                carrier.contains("airtel") || display.contains("airtel")
            }

            if (airtelSub != null) {
                Log.i(
                    TAG,
                    "Selected Active Airtel SIM: SubId ${airtelSub.subscriptionId} on Slot ${airtelSub.simSlotIndex} (${airtelSub.carrierName})"
                )
                return airtelSub
            }

            // 2. Look for requested slot index
            val slotSub = subList.firstOrNull { it.simSlotIndex == preferredSlot }
            if (slotSub != null) {
                Log.i(
                    TAG,
                    "Using preferred SIM Slot $preferredSlot: SubId ${slotSub.subscriptionId} (${slotSub.carrierName})"
                )
                return slotSub
            }

            // 3. Fallback to default SMS subscription
            val defaultSmsSubId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                SubscriptionManager.getDefaultSmsSubscriptionId()
            } else {
                -1
            }
            val defaultSub = subList.firstOrNull { it.subscriptionId == defaultSmsSubId }
            if (defaultSub != null) {
                Log.i(TAG, "Using default SMS subscription: SubId ${defaultSub.subscriptionId}")
                return defaultSub
            }

            return subList.first()
        } catch (e: Exception) {
            Log.e(TAG, "Error resolving SIM subscription: ${e.message}", e)
            return null
        }
    }

    /**
     * Gets the proper SmsManager instance for the target subscription.
     */
    fun getSmsManagerForSubId(context: Context, subId: Int): SmsManager {
        val smsManager = if (subId > 0) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java).createForSubscriptionId(subId)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getSmsManagerForSubscriptionId(subId)
            }
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Log.i(TAG, "SmsManager initialized with subscriptionId: ${smsManager.subscriptionId} (requested subId: $subId)")
        }
        return smsManager
    }

    /**
     * Dispatches an SMS message through the designated SIM card and tracks real carrier callbacks.
     */
    fun sendSMS(
        context: Context,
        taskId: String,
        rawPhone: String,
        message: String,
        preferredSlot: Int,
        callback: SmsCallback?
    ): Boolean {
        registerReceivers(context)

        val targetPhone = normalizePhoneNumber(rawPhone)
        if (targetPhone.isEmpty()) {
            callback?.onSent(taskId, false, -1, -1, "Invalid recipient phone number")
            return false
        }

        val hasSmsPermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasSmsPermission) {
            val errorMsg = "SEND_SMS permission not granted by user"
            Log.e(TAG, "Cannot send SMS: $errorMsg")
            callback?.onSent(taskId, false, -1, -1, errorMsg)
            return false
        }

        if (callback != null) {
            callbacks[taskId] = callback
        }

        val targetSub = resolveSubscription(context, preferredSlot)
        val subId = targetSub?.subscriptionId ?: -1
        val slotIndex = targetSub?.simSlotIndex ?: preferredSlot
        val carrierName = targetSub?.carrierName ?: "Default"

        Log.i(
            TAG,
            "[DISPATCH-INIT] Task: $taskId | Recipient: $targetPhone | SIM: Slot $slotIndex ($carrierName, SubId: $subId)"
        )

        val smsManager = getSmsManagerForSubId(context, subId)

        // PendingIntent flags: On Android 12+ (API 31+), FLAG_MUTABLE is required so the
        // telephony service can populate 'errorCode' and status extras into the intent.
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val parts = smsManager.divideMessage(message)
        val totalParts = parts.size
        multipartTotalTracker[taskId] = totalParts
        multipartSentTracker[taskId] = AtomicInteger(0)

        Log.i(TAG, "[DISPATCH-EXEC] Message divided into $totalParts part(s)")

        try {
            if (totalParts > 1) {
                val sentIntents = ArrayList<PendingIntent>()
                val deliveredIntents = ArrayList<PendingIntent>()

                for (i in parts.indices) {
                    val reqCode = requestCounter.incrementAndGet()
                    val sentIntent = Intent(ACTION_SMS_SENT).apply {
                        putExtra("taskId", taskId)
                        putExtra("partIndex", i)
                        putExtra("totalParts", totalParts)
                        putExtra("subId", subId)
                        setPackage(context.packageName)
                    }
                    val deliveredIntent = Intent(ACTION_SMS_DELIVERED).apply {
                        putExtra("taskId", taskId)
                        putExtra("partIndex", i)
                        putExtra("totalParts", totalParts)
                        putExtra("subId", subId)
                        setPackage(context.packageName)
                    }

                    sentIntents.add(PendingIntent.getBroadcast(context, reqCode, sentIntent, piFlags))
                    deliveredIntents.add(PendingIntent.getBroadcast(context, reqCode + 50000, deliveredIntent, piFlags))
                }

                smsManager.sendMultipartTextMessage(targetPhone, null, parts, sentIntents, deliveredIntents)
            } else {
                val reqCode = requestCounter.incrementAndGet()
                val sentIntent = Intent(ACTION_SMS_SENT).apply {
                    putExtra("taskId", taskId)
                    putExtra("partIndex", 0)
                    putExtra("totalParts", 1)
                    putExtra("subId", subId)
                    setPackage(context.packageName)
                }
                val deliveredIntent = Intent(ACTION_SMS_DELIVERED).apply {
                    putExtra("taskId", taskId)
                    putExtra("partIndex", 0)
                    putExtra("totalParts", 1)
                    putExtra("subId", subId)
                    setPackage(context.packageName)
                }

                val sentPI = PendingIntent.getBroadcast(context, reqCode, sentIntent, piFlags)
                val deliveredPI = PendingIntent.getBroadcast(context, reqCode + 50000, deliveredIntent, piFlags)

                smsManager.sendTextMessage(targetPhone, null, message, sentPI, deliveredPI)
            }

            Log.i(TAG, "[DISPATCH-QUEUED] Task $taskId handed to Android Telephony service for SIM $slotIndex")
            return true
        } catch (e: Exception) {
            val errorMsg = "Exception during SmsManager submission: ${e.message}"
            Log.e(TAG, errorMsg, e)
            cleanupTask(taskId)
            callback?.onSent(taskId, false, -1, -1, errorMsg)
            return false
        }
    }

    private fun mapResultCodeToMessage(resultCode: Int, errorCode: Int): String {
        val extraCodeStr = if (errorCode != -1) " (Modem ErrorCode: $errorCode)" else ""
        return when (resultCode) {
            SmsManager.RESULT_ERROR_GENERIC_FAILURE ->
                "Generic carrier network failure$extraCodeStr - verify Airtel outgoing SMS pack balance or SIM activation"
            SmsManager.RESULT_ERROR_NO_SERVICE ->
                "No cellular network service on selected SIM$extraCodeStr"
            SmsManager.RESULT_ERROR_NULL_PDU ->
                "Null PDU rejected by SMSC$extraCodeStr"
            SmsManager.RESULT_ERROR_RADIO_OFF ->
                "Cellular radio is off or Airplane mode is active$extraCodeStr"
            SmsManager.RESULT_ERROR_LIMIT_EXCEEDED ->
                "System SMS transmission limit exceeded$extraCodeStr"
            SmsManager.RESULT_ERROR_FDN_CHECK_FAILURE ->
                "Fixed Dialing Numbers (FDN) check failure$extraCodeStr"
            SmsManager.RESULT_ERROR_SHORT_CODE_NOT_ALLOWED ->
                "Short code not allowed$extraCodeStr"
            SmsManager.RESULT_ERROR_SHORT_CODE_NEVER_ALLOWED ->
                "Short code never allowed$extraCodeStr"
            SmsManager.RESULT_RADIO_NOT_AVAILABLE ->
                "Cellular radio not available$extraCodeStr"
            SmsManager.RESULT_NETWORK_REJECT ->
                "Carrier network rejected SMS transmission$extraCodeStr"
            SmsManager.RESULT_INVALID_ARGUMENTS ->
                "Invalid arguments provided to telephony service$extraCodeStr"
            SmsManager.RESULT_INVALID_STATE ->
                "Telephony invalid state$extraCodeStr"
            SmsManager.RESULT_NO_MEMORY ->
                "Device or SIM out of memory$extraCodeStr"
            SmsManager.RESULT_INVALID_SMS_FORMAT ->
                "Invalid SMS format$extraCodeStr"
            SmsManager.RESULT_SYSTEM_ERROR ->
                "Android telephony system error$extraCodeStr"
            SmsManager.RESULT_MODEM_ERROR ->
                "Cellular modem error$extraCodeStr"
            SmsManager.RESULT_NETWORK_ERROR ->
                "Cellular network error$extraCodeStr"
            SmsManager.RESULT_ENCODING_ERROR ->
                "SMS encoding error$extraCodeStr"
            SmsManager.RESULT_INVALID_SMSC_ADDRESS ->
                "Invalid SMSC (Service Center) address on SIM$extraCodeStr"
            SmsManager.RESULT_OPERATION_NOT_ALLOWED ->
                "Operation not allowed by carrier$extraCodeStr"
            SmsManager.RESULT_INTERNAL_ERROR ->
                "Telephony internal error$extraCodeStr"
            SmsManager.RESULT_NO_RESOURCES ->
                "Telephony resources exhausted$extraCodeStr"
            SmsManager.RESULT_CANCELLED ->
                "SMS dispatch was cancelled$extraCodeStr"
            SmsManager.RESULT_REQUEST_NOT_SUPPORTED ->
                "SMS request not supported by modem$extraCodeStr"
            else ->
                "Carrier error code: $resultCode$extraCodeStr"
        }
    }
}

