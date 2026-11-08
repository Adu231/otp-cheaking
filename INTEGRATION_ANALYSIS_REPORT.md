# SMSGate OTP Lab — Complete Read-Only Integration Analysis Report

> **Generated**: 2026-11-08  
> **Scope**: Read-only static analysis of `frontend/`, `backend/`, and `android-gateway/`. No files modified, no live SMS sent, credentials redacted.

---

## 1. Executive Summary & Overall Integration Status

- **Overall Integration Status**: **PARTIALLY BROKEN / BLOCKED BY CONFIGURATION & TIMEOUTS**
- **Architecture Flow**: `Frontend (React + Vite)` $\rightarrow$ `Backend (Node.js + Express on Render)` $\rightarrow$ `Database (MongoDB Atlas)` $\rightarrow$ `Android Gateway (Flutter + Kotlin on Android Device)` $\rightarrow$ `Cellular Carrier Network (SMS)`

Although the codebase architecture, API routing, and data contracts between all three components are largely well-designed and structurally compatible, the end-to-end request flow is currently failing due to **five concrete configuration and runtime bottlenecks**:
1. **Frontend Request Timeouts (15,000ms)** colliding with Render free-tier cold-start latencies (50–90s) and MongoDB query buffering.
2. **MongoDB Database URI Ambiguity** (`MONGODB_URI` lacks the `/otp_checking` database path, defaulting Mongoose to `test`, with potential Atlas IP whitelist restrictions).
3. **Frontend Validation Blocking Network Requests**, causing form submissions to abort on the client before dispatching an HTTP request to Chrome DevTools Fetch/XHR.
4. **Android Gateway Persistent SharedPreferences Cache** retaining legacy `http://10.0.2.2:5000` URLs across app restarts rather than adopting the new default Render URL.
5. **Android OS Cellular Subsystem Error** (`SmsManager.RESULT_ERROR_GENERIC_FAILURE`), triggered when testing on emulators, selecting an unprovisioned SIM slot, or lacking an active telecom SMS pack on the physical SIM.

---

## 2. End-to-End Architecture Diagram

```
 +-------------------------------------------------------------------------------------------------------+
 |                                          1. USER REGISTRATION FLOW                                    |
 +-------------------------------------------------------------------------------------------------------+
 [Browser: React Web App]
         |
         |  POST /api/auth/register { name, mobileNumber, password }
         |  Timeout: 15000ms (COLLISION: Render spin-up / Mongo buffering takes >15s)
         v
 [Render Cloud Backend: Node.js Express]
    https://otp-cheaking-1.onrender.com
         |
         +---> [MongoDB Atlas: cluster0.ljcpfhf.mongodb.net]
         |        - Query: User.findOne({ mobileNumber })
         |        - ISSUE: MONGODB_URI missing dbName '/otp_checking' (connects to 'test')
         |        - ISSUE: If Atlas IP Whitelist (0.0.0.0/0) missing, Mongoose buffers query indefinitely
         |
         +---> [OTP Generation & Queueing]
                  - Generates 6-digit OTP, bcrypt hash
                  - Saves OTPRequest (5 min expiry)
                  - Saves SMSLog (provider: 'AndroidGateway', status: 'Queued', id: 'gw_...')
                  - Returns HTTP 201 { messageId, gatewayStatus: 'Queued' }

 +-------------------------------------------------------------------------------------------------------+
 |                                       2. ANDROID GATEWAY DISPATCH FLOW                                |
 +-------------------------------------------------------------------------------------------------------+
 [Android Gateway: Flutter Background Service]
         |
         |  POLL: GET /api/gateway/pending (every 5 seconds)
         |  Header: x-gateway-token (if set)
         |  ISSUE: SharedPreferences may still store 'http://10.0.2.2:5000' from previous runs
         |  ISSUE: 10s poll timeout fails when Render is asleep -> "Cannot reach server"
         v
 [Render Cloud Backend]
         |
         |  Atomically claims task: SMSLog.findOneAndUpdate(Queued -> Claimed)
         |  Returns: { success: true, tasks: [ { id, phoneNumber, message, ... } ] }
         v
 [Android Gateway: Flutter Layer]
         |
         |  MethodChannel invokeMethod('sendSMS', { phoneNumber, message, simSlot })
         v
 [Android Gateway: Native Kotlin Layer (MainActivity.kt)]
         |
         |  SmsManager.sendTextMessage(phoneNumber, ..., sentPI, deliveredPI)
         |  ISSUE: Fails with RESULT_ERROR_GENERIC_FAILURE on emulator or SIM with 0 SMS balance
         v
 [Physical Cellular SIM Card / Carrier Network]
         |
         |  BroadcastReceiver: onReceive(ACTION_SMS_SENT) -> resultCode == RESULT_OK
         v
 [Android Gateway: Flutter Layer]
         |
         |  CALLBACK: POST /api/gateway/status { messageId, status: "sent" }
         v
 [Render Cloud Backend]
            Updates SMSLog(status: 'Sent')

 +-------------------------------------------------------------------------------------------------------+
 |                                       3. OTP VERIFICATION FLOW                                        |
 +-------------------------------------------------------------------------------------------------------+
 [Browser: VerifyOTP.jsx]
         |
         |  POST /api/otp/verify { mobileNumber, otp }
         v
 [Render Cloud Backend]
         |  Checks OTPRequest attempts, bcrypt.compare(otp, otpHash)
         |  Updates User.isVerified = true
         |  Returns HTTP 200 { success: true, isVerified: true }
         v
 [Browser: Login.jsx]
            POST /api/auth/login -> Returns JWT Token -> Redirects to /welcome
```

---

## 3. Component Status Matrix

| Component | Status | Code Quality | Integration Health | Primary Blocker |
| :--- | :---: | :---: | :---: | :--- |
| **Frontend (`frontend/`)** | **Uncertain** | Clean React 18 / Vite | Failing during Registration API call | Axios 15s timeout vs cold backend; client-side validation aborting request |
| **Backend (`backend/`)** | **Working (Code)** | Solid Express MVC | Blocked by DB URI / environment | Missing `/otp_checking` in `MONGODB_URI`; Render spin-down latency |
| **Database (`MongoDB`)** | **Uncertain** | Schema well-modeled | Connection stalling / buffering | No database path in connection string; dynamic Render IP whitelist uncertain |
| **Android Gateway (`android-gateway/`)** | **Working (Code)** | Dual Flutter/Kotlin architecture | Blocked on device by cached URL & carrier | SharedPreferences stale URL (`10.0.2.2`); SIM carrier pack / emulator failure |

---

## 4. In-Depth Breakdown by Layer

### Layer 1: FRONTEND $\rightarrow$ BACKEND

#### 1.1 API Base URL and Axios Configuration
- **File**: [`frontend/src/services/api.js`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/frontend/src/services/api.js#L1-L11)
  ```javascript
  const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'https://otp-cheaking-1.onrender.com/api';

  const api = axios.create({
    baseURL: API_BASE_URL,
    headers: { 'Content-Type': 'application/json' },
    timeout: 15000
  });
  ```
- **File**: [`frontend/.env`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/frontend/.env#L1)
  ```env
  VITE_API_BASE_URL=https://otp-cheaking-1.onrender.com/api
  ```
- **Code Finding**: Both `.env` and the fallback in `api.js` explicitly point to the deployed Render backend `https://otp-cheaking-1.onrender.com/api`.
- **Target Verification**: The codebase is configured to target Render. However, Vite inlines `import.meta.env` at build/server start time. If the development server (`npm run dev`) was started while `VITE_API_BASE_URL` pointed to `http://localhost:5000/api`, Vite will continue to serve requests to localhost until the dev process is restarted.

#### 1.2 Register, Login, and OTP Verification API Calls
- **Register**: `authApi.register(payload)` $\rightarrow$ `POST /api/auth/register` ([api.js#L42](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/frontend/src/services/api.js#L42))
- **Login**: `authApi.login(payload)` $\rightarrow$ `POST /api/auth/login` ([api.js#L43](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/frontend/src/services/api.js#L43))
- **Verify OTP**: `otpApi.verify(payload)` $\rightarrow$ `POST /api/otp/verify` ([api.js#L48](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/frontend/src/services/api.js#L48))
- **Resend OTP**: `otpApi.resend(payload)` $\rightarrow$ `POST /api/otp/resend` ([api.js#L49](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/frontend/src/services/api.js#L49))
- **Get Status**: `otpApi.getStatus(messageId)` $\rightarrow$ `GET /api/otp/status/:messageId` ([api.js#L50](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/frontend/src/services/api.js#L50))
- **Code Finding**: All route names, HTTP methods, and payload structures match the backend controller definitions exactly.

#### 1.3 CORS Configuration
- **File**: [`backend/src/app.js`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/src/app.js#L12-L26)
  ```javascript
  const allowedOrigin = process.env.FRONTEND_URL || 'http://localhost:5173';
  app.use(
    cors({
      origin: (origin, callback) => {
        if (!origin || origin === allowedOrigin || origin === 'http://localhost:5173' || origin === 'http://127.0.0.1:5173') {
          callback(null, true);
        } else {
          callback(null, true); // Permissive for local development convenience
        }
      },
      credentials: true
    })
  );
  ```
- **Code Finding**: CORS is configured permissively with `credentials: true`. It allows requests with no origin (mobile app, curl) and all browser origins.

#### 1.4 Why Register Shows `timeout of 15000ms exceeded`
There are two distinct root causes:
1. **Render Free-Tier Spin-Down (Cold Start)**:
   Render automatically spins down free Web Services after 15 minutes of inactivity. When a new HTTP request hits the endpoint, Render takes **50 to 90 seconds** to provision the container, start Node.js, and establish database connections. Because Axios is configured with `timeout: 15000` (15 seconds) in [api.js#L10](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/frontend/src/services/api.js#L10), the browser aborts the request at exactly 15 seconds, long before Render finishes waking up.
2. **MongoDB Connection Query Buffering**:
   In [authController.js#L39](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/src/controllers/authController.js#L39), registration immediately executes:
   `let user = await User.findOne({ mobileNumber: normalizedMobile });`
   If the backend is running but cannot connect to MongoDB Atlas (e.g. Atlas IP whitelist blocking Render, or SRV resolution delay), Mongoose enters command buffering mode (`bufferCommands: true` by default). Mongoose will not reject or resolve `User.findOne` until its internal buffer timeout triggers. Meanwhile, the client's 15,000ms Axios timer expires first.

#### 1.5 Why API Requests Do Not Appear in Chrome Network Fetch/XHR
1. **Client-Side Form Validation Abort**:
   In [`frontend/src/pages/Register.jsx`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/frontend/src/pages/Register.jsx#L61-L67):
   ```javascript
   const handleSubmit = async (e) => {
     e.preventDefault();
     setErrorMessage('');

     if (!validateForm()) {
       return; // <--- HALTS HERE: NO HTTP REQUEST IS EVER DISPATCHED
     }
     ...
     await authApi.register(...)
   ```
   If any field fails `validateForm()`:
   - `name.trim().length < 2`
   - `!validateIndianMobile(mobileNumber)` (e.g., entered fewer than 10 digits, starts with 1–5, or has unhandled characters)
   - `password.length < 6`
   - `password !== confirmPassword`
   The function exits immediately on line 66. **No network request is ever sent to the browser's network stack**, resulting in a completely blank Fetch/XHR log.
2. **DevTools Filter / CORS Preflight Classification**:
   In Chrome DevTools, if the request failed at the browser preflight stage (`OPTIONS` request) due to network unreachability, Chrome may categorize the failed request under **"Other"** or **"All"**, rather than **"Fetch/XHR"**.
3. **Active DevTools Filter String**:
   If Chrome DevTools has a search filter (e.g., filtering for `localhost` when the app is contacting `onrender.com`, or filtering by status code).

---

### Layer 2: BACKEND $\rightarrow$ MONGODB

#### 2.1 MongoDB Connection Configuration & URI Inspection
- **File**: [`backend/src/config/database.js`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/src/config/database.js#L12-L30)
- **File**: [`backend/.env`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/.env#L5)
  ```env
  MONGODB_URI=mongodb+srv://adityachavan0122_db_user:[REDACTED]@cluster0.ljcpfhf.mongodb.net/
  ```

#### 2.2 Identified Database Defects
1. **Missing Database Name in Connection String (Exact Code Defect)**:
   The connection URI in `backend/.env` ends with `.mongodb.net/` with no database path specified.
   When Mongoose connects without a database name in the path or without `{ dbName: 'otp_checking' }`, **MongoDB driver defaults to the database named `test`**.
   The project requirement specifies database **`otp_checking`**. The URI must explicitly include the database name:
   `mongodb+srv://...cluster0.ljcpfhf.mongodb.net/otp_checking?retryWrites=true&w=majority`
2. **Error Swallowing & Buffer Stalling**:
   In [database.js#L26-L29](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/src/config/database.js#L26-L29):
   ```javascript
   } catch (error) {
     console.error(`[DATABASE ERROR] Failed to connect to MongoDB: ${error.message}`);
     // Do not crash the entire process so users can inspect configuration
   }
   ```
   If MongoDB Atlas is unreachable during startup, the process continues running. Because Mongoose queries buffer indefinitely by default, all incoming HTTP requests hang on database calls until client timeouts occur.
3. **MongoDB Atlas IP Access Whitelist**:
   Render web services utilize dynamic outgoing IP addresses. If the MongoDB Atlas cluster's **Network Access** does not have `0.0.0.0/0` (Allow Access from Anywhere) enabled, Atlas automatically drops all connection attempts from Render.

#### 2.3 Gateway Endpoints & Android Gateway Support
- **Endpoints Defined**:
  - `GET /api/gateway/pending` $\rightarrow$ [`backend/src/controllers/gatewayController.js#L12`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/src/controllers/gatewayController.js#L12)
  - `POST /api/gateway/status` $\rightarrow$ [`backend/src/controllers/gatewayController.js#L74`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/src/controllers/gatewayController.js#L74)
- **Provider Switching Logic**:
  In [`backend/src/services/otpService.js#L55-L57`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/src/services/otpService.js#L55-L57):
  ```javascript
  const useInHouseGateway =
    process.env.SMS_PROVIDER === 'android-gateway' || !smsgateConfig.isConfigured();
  ```
  The code is designed to automatically select `AndroidGateway` if `SMS_PROVIDER=android-gateway` is set **OR** if SMSGate cloud credentials are not provided.
- **Task Claiming Mechanism**:
  `getPendingTasks` utilizes atomic find-and-modify with a 90-second lease (`CLAIM_TIMEOUT_MS = 90 * 1000`) on `SMSLog`. This prevents duplicate SMS dispatch if multiple devices or instances poll simultaneously.

---

### Layer 3: BACKEND $\rightarrow$ ANDROID GATEWAY

#### 3.1 Authentication & Token Matching
- **Backend Middleware**: [`backend/src/middleware/gatewayAuth.js#L7-L30`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/src/middleware/gatewayAuth.js#L7-L30)
  - Reads `process.env.GATEWAY_SECRET_TOKEN`.
  - Checks header `x-gateway-token` or `Authorization: Bearer <token>`.
  - **Rule**: If `GATEWAY_SECRET_TOKEN` is set and non-empty, requests without an exact matching token receive HTTP 401. If `GATEWAY_SECRET_TOKEN` is unset or empty, all incoming requests are permitted.
- **Android Gateway Client**: [`android-gateway/lib/services/backend_sync_service.dart#L101`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/android-gateway/lib/services/backend_sync_service.dart#L101)
  - Sends `'x-gateway-token': _deviceToken` when non-empty.
- **Contract Compatibility**: Fully compatible. In `backend/.env`, `GATEWAY_SECRET_TOKEN` is currently empty (`GATEWAY_SECRET_TOKEN=`), so no token is strictly enforced until configured.

#### 3.2 Request URLs and JSON Contracts
1. **Pending Task Retrieval**:
   - **Flutter URL**: `$_backendUrl/api/gateway/pending`
   - **Backend Response**:
     ```json
     {
       "success": true,
       "tasks": [
         {
           "id": "gw_1731050000000_a1b2c3d4",
           "phoneNumber": "+919876543210",
           "message": "Your SMSGate OTP Lab verification code is: 123456. Valid for 5 minutes...",
           "status": "pending",
           "timestamp": "2026-11-08T04:00:00.000Z"
         }
       ]
     }
     ```
   - **Flutter Parsing** ([`sms_message.dart#L48-L60`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/android-gateway/lib/models/sms_message.dart#L48-L60)): Reads `id`, `phoneNumber`, `message`, `status`, `timestamp`. **Exact contract match.**
2. **Status Reporting**:
   - **Flutter URL**: `$_backendUrl/api/gateway/status`
   - **Flutter Body**:
     ```json
     {
       "messageId": "gw_...",
       "status": "sent",
       "errorMessage": null,
       "timestamp": "2026-11-08T04:00:00.000Z"
     }
     ```
   - **Backend Handler** ([`gatewayController.js#L76-L109`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/src/controllers/gatewayController.js#L76-L109)): Reads `messageId`, `status`, `errorMessage`, normalizes case (`sent` $\rightarrow$ `Sent`), and updates `SMSLog`. **Exact contract match.**

---

### Layer 4: ANDROID GATEWAY (FLUTTER APP)

#### 4.1 Why the Dashboard Displays `Cannot reach server`
- **File**: [`android-gateway/lib/services/backend_sync_service.dart`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/android-gateway/lib/services/backend_sync_service.dart#L94-L122)
  ```dart
  Future<void> _pollPendingSmsRequests() async {
    try {
      final uri = Uri.parse('$_backendUrl/api/gateway/pending');
      final response = await http.get(uri, headers: ...).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        onConnectionStatusChanged?.call(true, 'Connected to Node.js backend');
        ...
      } else {
        onConnectionStatusChanged?.call(false, 'Server returned HTTP ${response.statusCode}');
      }
    } catch (e) {
      onConnectionStatusChanged?.call(false, 'Cannot reach server at $_backendUrl');
    }
  }
  ```
- **Root Cause 1: Persistent SharedPreferences Stale URL (`http://10.0.2.2:5000`)**:
  In `_loadSettings()` ([backend_sync_service.dart#L37](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/android-gateway/lib/services/backend_sync_service.dart#L37)):
  `_backendUrl = prefs.getString(AppConstants.keyBackendUrl) ?? AppConstants.defaultBackendUrl;`
  Before the recent update, `AppConstants.defaultBackendUrl` was `http://10.0.2.2:5000`. If the app was previously launched or installed on the device/emulator, `SharedPreferences` permanently saved `http://10.0.2.2:5000`.
  Because `prefs.getString(...)` returns the saved string, the new default `https://otp-cheaking-1.onrender.com` is **ignored** on existing app data! On a physical phone, `10.0.2.2` does not exist, causing an instant `SocketException` $\rightarrow$ `Cannot reach server at http://10.0.2.2:5000`.
- **Root Cause 2: 10-Second Polling Timeout vs Render Spin-Down**:
  `_pollPendingSmsRequests()` enforces `.timeout(const Duration(seconds: 10))`. If the app targets Render while the instance is sleeping, the 10-second timeout trips before Render responds, invoking the `catch` block and displaying `Cannot reach server at https://otp-cheaking-1.onrender.com`.

#### 4.2 Why Test Send Reports `Generic network failure or carrier block`
- **File**: [`android-gateway/android/app/src/main/kotlin/com/smsgate/android_gateway/MainActivity.kt`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/android-gateway/android/app/src/main/kotlin/com/smsgate/android_gateway/MainActivity.kt#L186-L200)
  ```kotlin
  sentReceiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
          when (resultCode) {
              Activity.RESULT_OK -> {
                  status = "Sent"
                  errorMessage = null
              }
              SmsManager.RESULT_ERROR_GENERIC_FAILURE -> {
                  status = "Failed"
                  errorMessage = "Generic network failure or carrier block"
              }
  ```
- **Exact Origin**:
  This message is not a network or HTTP error. It is generated by Android's native `SmsManager` subsystem when the cellular modem or baseband layer reports `RESULT_ERROR_GENERIC_FAILURE` (error code 1).
- **Physical/Carrier Causes**:
  1. **Running on Android Emulator**: An emulator has no cellular radio or SIM card. Calling `SmsManager.sendTextMessage()` on standard AVDs always returns `RESULT_ERROR_GENERIC_FAILURE`.
  2. **SIM Slot Mismatch (Dual-SIM Devices)**:
     `MainActivity.kt` uses `getSmsManagerForSlot(simSlot)`. If the active cellular SIM with the SMS recharge is in **SIM Slot 2** (`simSlotIndex == 1`), but the app configuration defaults to **SIM 1** (`simSlot == 0`), Android attempts transmission on an inactive/empty slot and fails immediately.
  3. **No Active Outgoing SMS Balance (Indian Telecom Rules)**:
     In India (Airtel, Jio, Vi, BSNL), standard data-only packs have **0 SMS balance**. Under TRAI guidelines, telcos reject SMS transmissions immediately if the SIM lacks an active SMS recharge pack.
  4. **Unformatted Phone Numbers in Test Dialog**:
     In [home_screen.dart#L166-L175](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/android-gateway/lib/screens/home_screen.dart#L166-L175), `_showSendTestSmsDialog()` passes the user's raw string directly to `sendSms()`. If the user inputs `9876543210` without the `+91` prefix (or with spaces), carrier routing rules may reject the dispatch.

---

### Layer 5: DEPLOYMENT (RENDER)

#### 5.1 Render Environment Compatibility
- **Port Binding**: [`backend/src/server.js#L11`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/src/server.js#L11)
  `const PORT = process.env.PORT || 5000;`
  Render automatically assigns `PORT` (usually 10000). The server dynamically binds to `process.env.PORT`.
- **Start Command**: [`backend/package.json#L8`](file:///C:/Users/Adity/OneDrive/Desktop/test%20otp%20project/SMSGate-OTP-Lab/backend/package.json#L8)
  `"start": "node src/server.js"`
  Standard, correct Render web service start command.
- **Node Version**: Modern CommonJS syntax (`express@4.21.2`, `mongoose@8.9.5`). Compatible with Node 18, 20, 22 on Render.

#### 5.2 Environment Variables Audit (Local vs Render)
| Variable | `backend/.env` Value | Required on Render Dashboard | Assessment |
| :--- | :--- | :--- | :--- |
| `PORT` | `5000` | Auto-provided by Render | OK |
| `MONGODB_URI` | `...mongodb.net/` | `...mongodb.net/otp_checking?retryWrites=true&w=majority` | **DEFECT**: Missing `/otp_checking` database name |
| `JWT_SECRET` | Configured | Must match or be a strong secret | OK |
| `JWT_EXPIRES_IN`| `1d` | `1d` | OK |
| `SMS_PROVIDER` | `android-gateway` | Must be set to `android-gateway` | **CRITICAL**: If missing on Render, may attempt cloud SMS |
| `GATEWAY_SECRET_TOKEN` | *(empty)* | Optional (must match Android Gateway if set) | OK |
| `FRONTEND_URL` | `http://localhost:5173` | Your frontend hosting URL or `http://localhost:5173` | OK |

---

## 5. Prioritized Fix Plan

Follow these steps in exact order to restore full end-to-end integration:

### Priority 1: Fix MongoDB Connection URI & Atlas Access
1. **Add Database Name in `MONGODB_URI`**:
   Update `backend/.env` and the Render Dashboard Environment settings from:
   `mongodb+srv://<user>:<password>@cluster0.ljcpfhf.mongodb.net/`
   to:
   `mongodb+srv://<user>:<password>@cluster0.ljcpfhf.mongodb.net/otp_checking?retryWrites=true&w=majority`
2. **Whitelist Render Outgoing IPs in MongoDB Atlas**:
   Navigate to MongoDB Atlas $\rightarrow$ **Network Access** $\rightarrow$ **IP Access List** $\rightarrow$ Ensure `0.0.0.0/0` (Allow Access from Anywhere) is active so Render's dynamic IP addresses can establish connections.

### Priority 2: Adjust Request Timeouts & Wake Up Render Service
1. **Extend Axios Timeout**:
   In `frontend/src/services/api.js#L10`, increase timeout from `15000` (15s) to `60000` (60s) to comfortably tolerate Render free-tier cold starts.
2. **Wake the Render Service**:
   Open `https://otp-cheaking-1.onrender.com/api/health` in a browser before testing to trigger container provisioning.

### Priority 3: Clear Stale SharedPreferences on Android Gateway
1. **Reset Cached Gateway URL**:
   On the Android phone: Open **App Info** for "SMS Gateway" $\rightarrow$ **Storage & cache** $\rightarrow$ **Clear storage / Clear data**.
   Alternatively, open the in-app **Gateway Configuration** (gear icon) and explicitly enter `https://otp-cheaking-1.onrender.com`.
2. **Extend Gateway HTTP Polling Timeout**:
   In `android-gateway/lib/services/backend_sync_service.dart#L103`, change `.timeout(const Duration(seconds: 10))` to `Duration(seconds: 25)`.

### Priority 4: Configure Cellular SIM & SIM Slot on Android Device
1. **Use Physical Hardware**:
   Do not run the gateway on an Android Emulator. It must run on a physical Android handset with an active SIM card.
2. **Verify Telecom Outgoing SMS Pack**:
   Ensure the SIM card in the phone has an active outgoing SMS pack/balance (required by Indian carriers).
3. **Select Active SIM Slot**:
   If the phone is dual-SIM, open **Gateway Configuration** and ensure the SIM Slot is set to the slot containing the active SIM (SIM 1 = slot `0`, SIM 2 = slot `1`).
4. **Normalize Test Phone Number**:
   Ensure numbers entered in the manual test dialog follow the `+91XXXXXXXXXX` format.

---

## 6. Verification Checklist (What Requires Live Testing)

Since this was a strict read-only code analysis, the following items require live physical verification:

- [ ] **Live Health Probe**: Execute `curl -I https://otp-cheaking-1.onrender.com/api/health` to verify if Render returns HTTP 200.
- [ ] **Render Environment Variables**: Check the Render Dashboard to confirm `SMS_PROVIDER=android-gateway` and `MONGODB_URI` contains `/otp_checking`.
- [ ] **Atlas Network Whitelist**: Check MongoDB Atlas Network Access tab to verify `0.0.0.0/0` is present.
- [ ] **Android Physical SIM**: Test sending an ordinary SMS from the native Android Messaging app on the target phone to ensure carrier balance and SMSC configuration are working.
- [ ] **Vite Dev Server Restart**: Restart the local frontend (`npm run dev`) and hard-refresh Chrome (`Ctrl + F5`) to guarantee the newest `VITE_API_BASE_URL` bundle is active.
