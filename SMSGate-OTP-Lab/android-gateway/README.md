# In-House Android SMS Gateway (Flutter)

A standalone Android application built with **Flutter and Dart** that turns any Android smartphone with an active SIM card into an automated SMS gateway for our Node.js backend.

This replaces reliance on third-party SMS applications, giving full control over SMS dispatch, SIM card slot selection, and real-time delivery status reports (`Pending`, `Sent`, `Delivered`, `Failed`).

---

## 1. Architecture Overview

```
                      +-----------------------------+
                      |   Node.js Express Backend   |
                      | (https://otp-cheaking-1...  |
                      |         onrender.com)       |
                      +--------------+--------------+
                                     ^
                HTTP Polling /       | Delivery Status
             GET /api/gateway/pending| POST /api/gateway/status
                                     v
                      +-----------------------------+
                      |   Flutter Android Gateway   |
                      |   (BackendSyncService)      |
                      +--------------+--------------+
                                     |
                       Platform MethodChannel
                     (com.smsgate.android_gateway/sms)
                                     v
                      +-----------------------------+
                      |  Native Android Layer (KT)  |
                      |     (MainActivity.kt)       |
                      |   Android OS SmsManager     |
                      +--------------+--------------+
                                     |
                               SIM 1 / SIM 2
                                     v
                        Recipient Handset (+91...)
```

---

## 2. Key Features

1. **Native SIM Card Dispatch**:
   - Uses Android's native `SmsManager` directly through a Kotlin `MethodChannel`.
   - Supports multi-SIM devices with dual SIM slot selection (SIM 1 / SIM 2).
   - Handles multi-part text messages seamlessly.

2. **Accurate Sent & Delivered Status Tracking**:
   - Implements native Android `PendingIntent` and `BroadcastReceiver` listening for:
     - `ACTION_SMS_SENT`: `Activity.RESULT_OK` (Sent), or carrier failure codes (`RESULT_ERROR_NO_SERVICE`, `RESULT_ERROR_RADIO_OFF`, etc.).
     - `ACTION_SMS_DELIVERED`: Confirms the destination handset acknowledged the message.
   - Dispatches status events back to Flutter and relays them to the Node.js backend.

3. **Runtime Android Permissions**:
   - Handled via `PermissionService` using `permission_handler`:
     - `SEND_SMS`: Required to send real SMS through the SIM.
     - `READ_PHONE_STATE`: Required to inspect active SIM cards.
     - `POST_NOTIFICATIONS`: Required on Android 13+ for foreground service notifications.
     - Battery Optimization Exemption: Keeps the gateway alive without being killed by Android Doze.

4. **Configurable Backend Synchronization**:
   - Pre-configured to target our live Render backend (`https://otp-cheaking-1.onrender.com`), or customizable to a local PC server.
   - Configurable dispatch polling interval (2s - 30s).
   - Optional gateway device secret authentication token.

5. **Clean & Scalable Structure**:
   - **`core/`**: Central constants and theme definitions.
   - **`models/`**: Strongly typed data models (`SmsMessage`, `GatewayStats`).
   - **`services/`**: Independent, modular services (`PermissionService`, `SmsDispatcherService`, `BackendSyncService`).
   - **`screens/`**: Dashboard view and gateway configuration screen.
   - **`widgets/`**: Reusable status badges and live activity tiles.

---

## 3. Project Structure

```
SMSGate-OTP-Lab/android-gateway/
├── android/
│   ├── app/
│   │   ├── src/
│   │   │   └── main/
│   │   │       ├── kotlin/com/smsgate/android_gateway/
│   │   │       │   └── MainActivity.kt       # Native SmsManager & BroadcastReceivers
│   │   │       ├── res/values/styles.xml
│   │   │       └── AndroidManifest.xml       # SMS & Phone State permissions
│   │   └── build.gradle
│   ├── build.gradle
│   ├── settings.gradle
│   └── gradle.properties
├── lib/
│   ├── core/
│   │   ├── constants/app_constants.dart      # MethodChannel & default URLs
│   │   └── theme/app_theme.dart              # Modern Material 3 styling
│   ├── models/
│   │   ├── sms_message.dart                  # SMS data model & status enum
│   │   └── gateway_stats.dart                # Counters (Sent, Delivered, Failed)
│   ├── services/
│   │   ├── permission_service.dart           # Runtime SMS & Phone permission checks
│   │   ├── sms_dispatcher_service.dart       # Dart <-> Kotlin MethodChannel bridge
│   │   └── backend_sync_service.dart         # Polling & status reporting with Node.js
│   ├── screens/
│   │   ├── home_screen.dart                  # Gateway dashboard & activity log
│   │   └── settings_screen.dart              # Backend IP & SIM slot configuration
│   ├── widgets/
│   │   ├── status_badge.dart                 # Color-coded status pills
│   │   └── sms_log_tile.dart                 # Live outgoing SMS list item
│   └── main.dart                             # App entry point & dependency wiring
├── .gitignore
├── pubspec.yaml                              # Flutter dependencies
├── analysis_options.yaml                     # Dart linter rules
└── README.md
```

---

## 4. How to Connect with Node.js Backend

When ready, add these two simple endpoints to your Node.js backend:

1. **`GET /api/gateway/pending`**:
   - Returns un-dispatched OTP requests awaiting transmission.
   - Response example:
     ```json
     {
       "tasks": [
         {
           "id": "otp_req_101",
           "phoneNumber": "+919876543210",
           "message": "Your verification code is: 123456. Valid for 5 minutes."
         }
       ]
     }
     ```

2. **`POST /api/gateway/status`**:
   - Receives final status updates directly from the phone.
   - Request body:
     ```json
     {
       "messageId": "otp_req_101",
       "status": "Sent",
       "errorMessage": null,
       "timestamp": "2026-11-06T18:00:00Z"
     }
     ```

---

## 5. How to Run on an Android Phone

1. Connect your Android phone via USB and enable **USB Debugging** (in Developer Options).
2. Ensure your phone has an active SIM card with SMS sending balance.
3. Open a terminal in `SMSGate-OTP-Lab/android-gateway`:
   ```bash
   flutter pub get
   flutter run -d <your-device-id>
   ```
4. On the app home screen:
   - Tap **Grant** on the permission banner.
   - The app defaults to our live backend: `https://otp-cheaking-1.onrender.com`.
   - Toggle the **Gateway Dispatcher** switch to ON.

