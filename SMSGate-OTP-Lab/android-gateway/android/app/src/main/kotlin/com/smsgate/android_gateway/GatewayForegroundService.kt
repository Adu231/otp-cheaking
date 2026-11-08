package com.smsgate.android_gateway

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.telephony.SmsManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.util.Collections
import java.util.LinkedHashSet
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class GatewayForegroundService : Service() {

    interface ServiceListener {
        fun onStatusUpdate(messageId: String, status: String, errorMessage: String?)
        fun onConnectionChanged(isConnected: Boolean, message: String)
        fun onMessageDispatched(taskMap: Map<String, Any>)
    }

    companion object {
        const val TAG = "SMSGatewayService"
        const val CHANNEL_ID = "sms_gateway_foreground_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "ACTION_START_GATEWAY"
        const val ACTION_STOP = "ACTION_STOP_GATEWAY"

        const val ACTION_BG_SENT = "com.smsgate.android_gateway.BG_SMS_SENT"
        const val ACTION_BG_DELIVERED = "com.smsgate.android_gateway.BG_SMS_DELIVERED"

        const val PREFS_NAME = "FlutterSharedPreferences"
        const val KEY_BACKEND_URL = "flutter.backend_server_url"
        const val KEY_DEVICE_TOKEN = "flutter.gateway_device_token"
        const val KEY_POLLING_INTERVAL = "flutter.polling_interval_seconds"
        const val KEY_DEFAULT_SIM_SLOT = "flutter.default_sim_slot"
        const val KEY_SERVICE_ENABLED = "flutter.gateway_service_enabled"

        const val DEFAULT_BACKEND_URL = "https://otp-cheaking-1.onrender.com"
        const val DEFAULT_DEVICE_TOKEN = "smsgate_gateway_secret_2026"
        const val DEFAULT_POLLING_INTERVAL = 5
        const val DEFAULT_SIM_SLOT = 0

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var isConnected: Boolean = false
            private set

        @Volatile
        var lastConnectionStatus: String = "Service idle"
            private set

        @Volatile
        var serviceListener: ServiceListener? = null
    }

    private var executor: ScheduledExecutorService? = null
    private var pollingTask: ScheduledFuture<*>? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private var sentReceiver: BroadcastReceiver? = null
    private var deliveredReceiver: BroadcastReceiver? = null

    private val inFlightTasks = Collections.synchronizedSet(HashSet<String>())
    private val dispatchedTasks = Collections.synchronizedSet(LinkedHashSet<String>())

    private var currentIntervalSeconds = DEFAULT_POLLING_INTERVAL
    private var consecutiveFailures = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "GatewayForegroundService onCreate")
        createNotificationChannel()
        registerSmsReceivers()

        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        wakeLock = powerManager?.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "SMSGate:GatewayForegroundLock"
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        Log.i(TAG, "onStartCommand with action: $action")

        when (action) {
            ACTION_STOP -> {
                stopServiceInternal()
            }
            ACTION_START -> {
                startServiceInternal()
            }
        }
        return START_STICKY
    }

    private fun startServiceInternal() {
        if (isRunning) {
            Log.d(TAG, "Service is already running")
            updateNotification("SMS Gateway Active • Polling for OTP requests...")
            return
        }

        isRunning = true
        saveServiceState(true)

        // Immediately promote to foreground to prevent ANR / foreground service start timeout
        startInForeground("SMS Gateway Active • Initializing...")

        executor = Executors.newSingleThreadScheduledExecutor()
        scheduleNextPoll(1) // Run first poll after 1 second
    }

    private fun stopServiceInternal() {
        Log.i(TAG, "Stopping GatewayForegroundService...")
        isRunning = false
        isConnected = false
        lastConnectionStatus = "Service stopped"
        saveServiceState(false)

        serviceListener?.onConnectionChanged(false, "Gateway service stopped")

        try {
            pollingTask?.cancel(true)
            executor?.shutdownNow()
            executor = null
        } catch (e: Exception) {
            Log.e(TAG, "Error shutting down executor: ${e.message}")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun saveServiceState(enabled: Boolean) {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putBoolean(KEY_SERVICE_ENABLED, enabled).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save service state: ${e.message}")
        }
    }

    private fun scheduleNextPoll(delaySeconds: Int) {
        if (!isRunning) return

        try {
            pollingTask = executor?.schedule({
                pollAndDispatch()
            }, delaySeconds.toLong(), TimeUnit.SECONDS)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule next poll: ${e.message}")
        }
    }

    private fun pollAndDispatch() {
        if (!isRunning) return

        wakeLock?.acquire(30000L) // Hold CPU awake for up to 30s during poll
        var nextDelaySeconds = currentIntervalSeconds

        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val rawBackendUrl = prefs.getString(KEY_BACKEND_URL, DEFAULT_BACKEND_URL) ?: DEFAULT_BACKEND_URL
            val backendUrl = normalizeBackendUrl(rawBackendUrl)
            val deviceToken = prefs.getString(KEY_DEVICE_TOKEN, DEFAULT_DEVICE_TOKEN) ?: DEFAULT_DEVICE_TOKEN
            val pollingInterval = prefs.getInt(KEY_POLLING_INTERVAL, DEFAULT_POLLING_INTERVAL)
            val simSlot = prefs.getInt(KEY_DEFAULT_SIM_SLOT, DEFAULT_SIM_SLOT)

            currentIntervalSeconds = if (pollingInterval > 0) pollingInterval else DEFAULT_POLLING_INTERVAL

            val endpoint = "$backendUrl/api/gateway/pending"
            val url = URL(endpoint)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 25000 // 25s for Render cold start
                readTimeout = 25000
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Accept", "application/json")
                if (deviceToken.isNotEmpty()) {
                    setRequestProperty("x-gateway-token", deviceToken)
                }
                setRequestProperty("x-gateway-id", "android-gateway")
            }

            val responseCode = conn.responseCode
            if (responseCode == 200) {
                consecutiveFailures = 0
                isConnected = true
                val responseBody = conn.inputStream.bufferedReader().use(BufferedReader::readText)
                conn.disconnect()

                val json = JSONObject(responseBody)
                val tasksArray = json.optJSONArray("tasks") ?: JSONArray()
                val taskCount = tasksArray.length()

                val statusMsg = if (taskCount > 0) {
                    "Connected: Processed $taskCount OTP SMS task${if (taskCount > 1) "s" else ""}"
                } else {
                    "Connected: Polling ($backendUrl)"
                }
                lastConnectionStatus = statusMsg
                serviceListener?.onConnectionChanged(true, statusMsg)
                updateNotification("SMS Gateway Active • $statusMsg")

                // Process tasks
                for (i in 0 until taskCount) {
                    val taskObj = tasksArray.getJSONObject(i)
                    val taskId = taskObj.optString("id")
                    val phone = taskObj.optString("phoneNumber")
                    val message = taskObj.optString("message")

                    if (taskId.isNotEmpty() && phone.isNotEmpty() && message.isNotEmpty()) {
                        if (!inFlightTasks.contains(taskId) && !dispatchedTasks.contains(taskId)) {
                            inFlightTasks.add(taskId)
                            dispatchSmsTask(taskId, phone, message, simSlot, backendUrl, deviceToken)
                        }
                    }
                }

                nextDelaySeconds = currentIntervalSeconds
            } else if (responseCode == 401) {
                conn.disconnect()
                isConnected = false
                lastConnectionStatus = "Authentication Failed (HTTP 401): Invalid Secret Token. Check Settings."
                serviceListener?.onConnectionChanged(false, lastConnectionStatus)
                updateNotification("SMS Gateway Error • HTTP 401 Unauthorized")
                nextDelaySeconds = 15 // Check again after 15s
            } else if (responseCode == 404) {
                conn.disconnect()
                isConnected = false
                lastConnectionStatus = "HTTP 404: Endpoint not found at $endpoint"
                serviceListener?.onConnectionChanged(false, lastConnectionStatus)
                updateNotification("SMS Gateway Error • Endpoint Not Found (404)")
                nextDelaySeconds = 15
            } else {
                conn.disconnect()
                isConnected = false
                lastConnectionStatus = "Server returned HTTP $responseCode"
                serviceListener?.onConnectionChanged(false, lastConnectionStatus)
                nextDelaySeconds = 10
            }
        } catch (e: SocketTimeoutException) {
            consecutiveFailures++
            isConnected = false
            lastConnectionStatus = "Server response timeout (Render cold boot). Retrying..."
            serviceListener?.onConnectionChanged(false, lastConnectionStatus)
            updateNotification("SMS Gateway Active • Waiting for backend to wake up...")
            nextDelaySeconds = calculateBackoff(currentIntervalSeconds)
        } catch (e: Exception) {
            consecutiveFailures++
            isConnected = false
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val currentUrl = prefs.getString(KEY_BACKEND_URL, DEFAULT_BACKEND_URL) ?: DEFAULT_BACKEND_URL
            lastConnectionStatus = "Cannot reach server at $currentUrl (${e.javaClass.simpleName})"
            serviceListener?.onConnectionChanged(false, lastConnectionStatus)
            updateNotification("SMS Gateway Active • Connecting to server...")
            nextDelaySeconds = calculateBackoff(currentIntervalSeconds)
        } finally {
            if (wakeLock?.isHeld == true) {
                try {
                    wakeLock?.release()
                } catch (_: Exception) {}
            }
            scheduleNextPoll(nextDelaySeconds)
        }
    }

    private fun calculateBackoff(baseInterval: Int): Int {
        val multiplier = Math.min(consecutiveFailures, 5)
        val backoff = baseInterval * (1 shl (multiplier - 1))
        return Math.min(Math.max(backoff, baseInterval), 30) // Cap backoff at 30 seconds
    }

    private fun normalizeBackendUrl(url: String): String {
        var clean = url.trim().replace(Regex("/+$"), "")
        if (clean.endsWith("/api")) {
            clean = clean.substring(0, clean.length - 4)
        }
        return clean
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

    private fun dispatchSmsTask(
        taskId: String,
        rawPhone: String,
        message: String,
        simSlot: Int,
        backendUrl: String,
        deviceToken: String
    ) {
        val targetPhone = normalizePhoneNumber(rawPhone)
        Log.i(TAG, "Dispatching SMS task $taskId to $targetPhone via SIM $simSlot")

        serviceListener?.onMessageDispatched(
            mapOf(
                "id" to taskId,
                "phoneNumber" to targetPhone,
                "message" to message,
                "status" to "sending",
                "simSlot" to simSlot,
                "timestamp" to System.currentTimeMillis()
            )
        )

        val hasPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasPermission) {
            Log.e(TAG, "Cannot dispatch SMS: SEND_SMS permission denied")
            inFlightTasks.remove(taskId)
            dispatchedTasks.add(taskId)
            reportStatus(taskId, "Failed", "SEND_SMS permission not granted on device", backendUrl, deviceToken)
            return
        }

        try {
            val smsManager = getSmsManagerForSlot(simSlot)

            val sentIntent = Intent(ACTION_BG_SENT).apply {
                putExtra("taskId", taskId)
                putExtra("backendUrl", backendUrl)
                putExtra("deviceToken", deviceToken)
                setPackage(packageName)
            }
            val deliveredIntent = Intent(ACTION_BG_DELIVERED).apply {
                putExtra("taskId", taskId)
                putExtra("backendUrl", backendUrl)
                putExtra("deviceToken", deviceToken)
                setPackage(packageName)
            }

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val sentPI = PendingIntent.getBroadcast(this, taskId.hashCode(), sentIntent, flags)
            val deliveredPI = PendingIntent.getBroadcast(this, taskId.hashCode() + 1, deliveredIntent, flags)

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
            updateNotification("SMS Gateway Active • Sent OTP to $targetPhone")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send SMS: ${e.message}", e)
            inFlightTasks.remove(taskId)
            dispatchedTasks.add(taskId)
            reportStatus(taskId, "Failed", e.localizedMessage ?: "Unknown SMS sending failure", backendUrl, deviceToken)
        }
    }

    @Suppress("DEPRECATION")
    private fun getSmsManagerForSlot(simSlot: Int): SmsManager {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            try {
                val subList = subManager?.activeSubscriptionInfoList
                if (!subList.isNullOrEmpty()) {
                    for (info in subList) {
                        if (info.simSlotIndex == simSlot) {
                            return createSmsManagerForSub(info.subscriptionId)
                        }
                    }
                    for (info in subList) {
                        val carrier = info.carrierName?.toString() ?: ""
                        val display = info.displayName?.toString() ?: ""
                        if (carrier.contains("airtel", ignoreCase = true) || display.contains("airtel", ignoreCase = true)) {
                            return createSmsManagerForSub(info.subscriptionId)
                        }
                    }
                    val firstActive = subList.firstOrNull()
                    if (firstActive != null) {
                        return createSmsManagerForSub(firstActive.subscriptionId)
                    }
                }
            } catch (_: SecurityException) {}
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

    private fun registerSmsReceivers() {
        sentReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val taskId = intent?.getStringExtra("taskId") ?: return
                val backendUrl = intent.getStringExtra("backendUrl") ?: DEFAULT_BACKEND_URL
                val deviceToken = intent.getStringExtra("deviceToken") ?: DEFAULT_DEVICE_TOKEN

                inFlightTasks.remove(taskId)
                dispatchedTasks.add(taskId)
                if (dispatchedTasks.size > 500) {
                    val first = dispatchedTasks.iterator().next()
                    dispatchedTasks.remove(first)
                }

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

                serviceListener?.onStatusUpdate(taskId, status, errorMessage)
                reportStatus(taskId, status, errorMessage, backendUrl, deviceToken)
            }
        }

        deliveredReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val taskId = intent?.getStringExtra("taskId") ?: return
                val backendUrl = intent.getStringExtra("backendUrl") ?: DEFAULT_BACKEND_URL
                val deviceToken = intent.getStringExtra("deviceToken") ?: DEFAULT_DEVICE_TOKEN

                val status = if (resultCode == Activity.RESULT_OK) "Delivered" else "DeliveryFailed"
                val errorMsg = if (resultCode == Activity.RESULT_OK) null else "Delivery report returned failure code $resultCode"

                serviceListener?.onStatusUpdate(taskId, status, errorMsg)
                reportStatus(taskId, status, errorMsg, backendUrl, deviceToken)
            }
        }

        val sentFilter = IntentFilter(ACTION_BG_SENT)
        val deliveredFilter = IntentFilter(ACTION_BG_DELIVERED)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(sentReceiver, sentFilter, Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(deliveredReceiver, deliveredFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(sentReceiver, sentFilter)
            registerReceiver(deliveredReceiver, deliveredFilter)
        }
    }

    private fun reportStatus(
        taskId: String,
        status: String,
        errorMessage: String?,
        backendUrl: String,
        deviceToken: String
    ) {
        executor?.execute {
            try {
                val cleanUrl = normalizeBackendUrl(backendUrl)
                val url = URL("$cleanUrl/api/gateway/status")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 15000
                    readTimeout = 15000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    if (deviceToken.isNotEmpty()) {
                        setRequestProperty("x-gateway-token", deviceToken)
                    }
                    setRequestProperty("x-gateway-id", "android-gateway")
                }

                val payload = JSONObject().apply {
                    put("messageId", taskId)
                    put("status", status)
                    put("errorMessage", errorMessage ?: JSONObject.NULL)
                    put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).format(java.util.Date()))
                }

                val outBytes = payload.toString().toByteArray(Charsets.UTF_8)
                conn.setFixedLengthStreamingMode(outBytes.size)
                conn.outputStream.use { os: OutputStream ->
                    os.write(outBytes)
                }

                val code = conn.responseCode
                Log.d(TAG, "Reported status for $taskId ($status) -> HTTP $code")
                conn.disconnect()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to report status to backend for $taskId: ${e.message}")
            }
        }
    }

    private fun startInForeground(statusText: String) {
        createNotificationChannel()
        val notification = buildNotification(statusText)
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        manager?.notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun buildNotification(contentText: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, pendingIntentFlags)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SMS Gateway Service Active")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SMS Gateway Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the SMS Gateway polling worker active 24/7 even when app is closed"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        Log.i(TAG, "GatewayForegroundService onDestroy")
        isRunning = false
        sentReceiver?.let { unregisterReceiver(it) }
        deliveredReceiver?.let { unregisterReceiver(it) }
        executor?.shutdownNow()
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        super.onDestroy()
    }
}
