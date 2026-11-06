# SMSGate OTP Lab

A dedicated experimental application designed to test and verify real-world SMS delivery using the **SMS Gateway for Android (SMSGate)** REST API, backed by a Node.js/Express service, MongoDB Atlas, and a React + Vite frontend.

---

## 1. Project Purpose

The sole objective of this laboratory project is to rigorously test whether our backend can:
1. Register a user with an Indian mobile number.
2. Generate a cryptographically secure 6-digit OTP.
3. Dispatch the OTP via the official **SMSGate REST API** (`POST /3rdparty/v1/messages`).
4. Physically deliver the SMS to the recipient phone using an Android smartphone running the SMSGate application and an active SIM card.
5. Securely verify the OTP against hashed records stored in MongoDB Atlas with rate limits and attempt tracking.
6. Authenticate verified users with JSON Web Tokens (JWT).
7. Display a minimal, protected welcome view upon login.

---

## 2. Required Software

- **Node.js**: v18.0.0 or higher
- **npm**: v9.0.0 or higher
- **MongoDB Atlas**: Free M0 cluster or self-hosted MongoDB instance
- **Android Device**: Running Android 7.0 (Nougat) or newer with:
  - An active SIM card with SMS sending quota / balance.
  - SMS Gateway for Android app installed from [docs.sms-gate.app](https://docs.sms-gate.app/) or F-Droid / GitHub Releases.
  - Stable internet connection (Wi-Fi or cellular data).

---

## 3. Project Structure

```
SMSGate-OTP-Lab/
│
├── frontend/
│   ├── public/
│   │   └── robots.txt
│   ├── src/
│   │   ├── assets/
│   │   ├── components/
│   │   │   ├── Navbar.jsx
│   │   │   └── ProtectedRoute.jsx
│   │   ├── pages/
│   │   │   ├── Home.jsx
│   │   │   ├── Register.jsx
│   │   │   ├── VerifyOTP.jsx
│   │   │   ├── Login.jsx
│   │   │   └── Welcome.jsx
│   │   ├── services/
│   │   │   └── api.js
│   │   ├── styles/
│   │   │   └── global.css
│   │   ├── App.jsx
│   │   └── main.jsx
│   ├── .env.example
│   ├── package.json
│   ├── index.html
│   └── vite.config.js
│
├── backend/
│   ├── src/
│   │   ├── config/
│   │   │   ├── database.js
│   │   │   └── smsgate.js
│   │   ├── controllers/
│   │   │   ├── authController.js
│   │   │   └── otpController.js
│   │   ├── models/
│   │   │   ├── User.js
│   │   │   ├── OTPRequest.js
│   │   │   └── SMSLog.js
│   │   ├── routes/
│   │   │   ├── authRoutes.js
│   │   │   └── otpRoutes.js
│   │   ├── services/
│   │   │   ├── smsGateService.js
│   │   │   └── otpService.js
│   │   ├── middleware/
│   │   │   ├── authMiddleware.js
│   │   │   └── rateLimiter.js
│   │   ├── utils/
│   │   │   ├── generateOTP.js
│   │   │   └── responseHandler.js
│   │   ├── app.js
│   │   └── server.js
│   ├── .env.example
│   └── package.json
│
├── README.md
└── .gitignore
```

---

## 4. How to Install Dependencies

Open two separate terminal windows or tabs: one for the backend and one for the frontend.

### A. Backend Dependencies

```bash
cd SMSGate-OTP-Lab/backend
npm install
```

### B. Frontend Dependencies

```bash
cd SMSGate-OTP-Lab/frontend
npm install
```

---

## 5. How to Configure MongoDB Atlas

1. Log into your [MongoDB Atlas](https://www.mongodb.com/atlas) account.
2. In your Cluster dashboard, click **Database Access** under Security:
   - Create a database user (e.g. `smsgate_user`) with read and write permissions (`readWriteAnyDatabase` or specific DB).
   - Note the password.
3. Click **Network Access** under Security:
   - Click **Add IP Address**.
   - For local development, choose **Allow Access From Anywhere** (`0.0.0.0/0`) or add your current external IP.
4. Go back to **Database** (Deployment) and click **Connect**:
   - Choose **Drivers** (Node.js).
   - Copy the connection string. It resembles:
     ```
     mongodb+srv://smsgate_user:<password>@cluster0.abcde.mongodb.net/smsgate_otp_lab?retryWrites=true&w=majority
     ```
   - Replace `<password>` with your database user password.

---

## 6. How to Install and Configure SMSGate on Android

1. **Download the Android App**:
   - Download the APK directly from the official SMSGate releases: [https://github.com/android-sms-gateway/android/releases](https://github.com/android-sms-gateway/android/releases) or visit [https://docs.sms-gate.app/](https://docs.sms-gate.app/).
2. **Install & Permissions**:
   - Install the APK on your dedicated Android phone.
   - When prompted, grant all required permissions:
     - **Send SMS**: Needed to dispatch OTP messages via your carrier.
     - **Read Phone State**: Needed to identify your SIM card.
     - **Battery Optimization Exemption**: Turn off battery optimization for the app so Android does not kill the background gateway worker.
3. **Keep Device Awake & Connected**:
   - Ensure the phone has an active Wi-Fi or cellular data connection so it can poll or receive push dispatches from SMSGate servers.

---

## 7. How to Choose Cloud Mode and Obtain Credentials

SMSGate operates in two primary modes:
- **Cloud Mode (Recommended)**: The Android app connects to SMSGate's secure cloud service (`https://api.sms-gate.app`). Your backend communicates with this central cloud API, and the cloud synchronizes outgoing messages directly to your connected phone.
- **Local Server Mode**: The Android app acts as an HTTP server on your local Wi-Fi network (e.g. `http://192.168.1.100:8080`).

### Using Cloud Mode:
1. Open the **SMS Gateway for Android** app on your phone.
2. Under **Mode Selection**, select **Cloud Mode**.
3. Sign in or register your account in the app.
4. Your **Username** and generated **Password / API Token** will be displayed on the app's dashboard screen or under the **Cloud Settings** section.
5. Note these credentials:
   - `SMSGATE_BASE_URL`: `https://api.sms-gate.app`
   - `SMSGATE_USERNAME`: `<your_cloud_username>`
   - `SMSGATE_PASSWORD`: `<your_cloud_password>`

---

## 8. How to Configure Environment Variables

### A. Backend Configuration

Create a `.env` file inside `SMSGate-OTP-Lab/backend/`:

```bash
# In SMSGate-OTP-Lab/backend
cp .env.example .env
```

Edit `backend/.env` with your actual credentials:

```env
PORT=5000
MONGODB_URI=mongodb+srv://smsgate_user:yourPassword@cluster0.abcde.mongodb.net/smsgate_otp_lab?retryWrites=true&w=majority
JWT_SECRET=super_secret_jwt_random_key_lab_2026
JWT_EXPIRES_IN=1d

# SMSGate Cloud Configuration
SMSGATE_BASE_URL=https://api.sms-gate.app
SMSGATE_USERNAME=your_smsgate_username
SMSGATE_PASSWORD=your_smsgate_password

FRONTEND_URL=http://localhost:5173
```

> **Note**: If you are using Local Server mode, set `SMSGATE_BASE_URL=http://<phone_local_ip>:8080`.

### B. Frontend Configuration

Create a `.env` file inside `SMSGate-OTP-Lab/frontend/`:

```bash
# In SMSGate-OTP-Lab/frontend
cp .env.example .env
```

Ensure `frontend/.env` contains:

```env
VITE_API_BASE_URL=http://localhost:5000/api
```

---

## 9. How to Start the Application

### Terminal 1 - Backend

```bash
cd SMSGate-OTP-Lab/backend
npm run dev
```

*The backend will boot up on `http://localhost:5000` and connect to MongoDB Atlas.*

### Terminal 2 - Frontend

```bash
cd SMSGate-OTP-Lab/frontend
npm run dev
```

*Vite will start the client on `http://localhost:5173`.*

---

## 10. How to Test the Complete Flow

1. **Access the Web App**:
   Open your browser to `http://localhost:5173`.
2. **Register**:
   - Click **Register New User**.
   - Enter your Full Name, Indian Mobile Number (e.g. `9876543210` or `+919876543210`), and a password.
   - Click **Register & Send OTP**.
3. **SMS Dispatch**:
   - The backend validates the input, normalizes the number to `+91XXXXXXXXXX`, hashes the password, creates an unverified user record, generates a 6-digit OTP, securely stores the bcrypt OTP hash, and calls `POST /3rdparty/v1/messages` on SMSGate.
   - You will see the app transition to the **Verify Phone Number** page displaying your masked mobile number.
4. **Physical Delivery**:
   - Check the Android phone running SMSGate. You will see an outgoing SMS queued and dispatched via your phone's SIM.
   - Check the destination phone. You will receive an SMS:
     ```
     Your SMSGate OTP Lab verification code is: 123456. Valid for 5 minutes. Do not share this code.
     ```
5. **Verify OTP**:
   - Enter the 6-digit code received on your phone into the OTP boxes.
   - Click **Verify OTP**.
   - Upon verification, the user status is set to `isVerified: true` and the "Proceed to Login" button appears.
6. **Login**:
   - Enter your registered mobile number and password.
   - Click **Login**.
7. **Welcome Page**:
   - You are redirected to the protected `/welcome` page showing:
     `Welcome, [Your Name]!`
   - Clicking **Logout** removes the session and returns you to `/login`.

---

## 11. Inspecting SMS Delivery Status & Troubleshooting

### Understanding Message States
SMSGate tracks messages through the following stages:
- **`Pending`**: Message received by SMSGate cloud server and queued for device synchronization.
- **`Processed`**: The connected Android device received the message and passed it to the Android OS SMS dispatch system.
- **`Sent`**: The mobile telecom SMS Center (SMSC) confirmed acceptance of the SMS from your SIM.
- **`Delivered`**: Carrier delivery receipt confirmed (requires SIM carrier support).
- **`Failed`**: Carrier rejected, device offline, out of SMS balance, or network error.

### Inspecting Delivery Status via API
The backend provides a dedicated tracking endpoint:
```http
GET http://localhost:5000/api/otp/status/<messageId>
```
Example using curl:
```bash
curl -X GET http://localhost:5000/api/otp/status/zXDYfTmTVf3iMd16zzdBj
```

### Checking Database Logs
Every SMS attempt is recorded in the `SMSLog` MongoDB collection with:
- `mobileNumber`
- `provider` (`SMSGate`)
- `providerMessageId`
- `messageStatus` (`Pending`, `Processed`, `Sent`, `Failed`)
- `errorMessage`

### Troubleshooting Checklist
- **401 Unauthorized from SMSGate**: Double-check `SMSGATE_USERNAME` and `SMSGATE_PASSWORD` in `backend/.env`.
- **SMS Stuck in "Pending"**:
  - Check whether the Android phone has an active internet connection.
  - Open the SMSGate app and check if it says "Connected".
  - Ensure battery optimization is disabled so Android does not sleep the background sync service.
- **SMS Failed to Send from Phone**:
  - Check whether your SIM card has SMS balance or active SMS recharge pack.
  - Ensure the default SMS app on Android doesn't block third-party SMS dispatch permissions.
- **Database Connection Warning**:
  - Ensure `MONGODB_URI` in `backend/.env` is populated and your current IP is whitelisted under Atlas Network Access.

