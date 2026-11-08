const express = require('express');
const cors = require('cors');
const authRoutes = require('./routes/authRoutes');
const otpRoutes = require('./routes/otpRoutes');
const gatewayRoutes = require('./routes/gatewayRoutes');
const { apiLimiter } = require('./middleware/rateLimiter');
const { sendError } = require('./utils/responseHandler');
const smsgateConfig = require('./config/smsgate');

const app = express();

// Trust reverse proxy (e.g. Render) for secure client IP detection in express-rate-limit
app.set('trust proxy', 1);

// 1. CORS Configuration
const allowedOrigin = process.env.FRONTEND_URL || 'http://localhost:5173';
app.use(
  cors({
    origin: (origin, callback) => {
      // Allow requests with no origin (like mobile apps, curl, or postman)
      if (!origin || origin === allowedOrigin || origin === 'http://localhost:5173' || origin === 'http://127.0.0.1:5173') {
        callback(null, true);
      } else {
        callback(null, true); // Permissive for local development convenience
      }
    },
    credentials: true
  })
);

// 2. Body Parser
app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ extended: true, limit: '10kb' }));

// 3. Global Rate Limiter
app.use('/api', apiLimiter);

// 4. Health Check / Status Route
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'SMSGate OTP Lab Backend',
    smsgateConfigured: smsgateConfig.isConfigured(),
    timestamp: new Date().toISOString()
  });
});

// 5. Mount API Routes
app.use('/api/auth', authRoutes);
app.use('/api/otp', otpRoutes);
app.use('/api/gateway', gatewayRoutes);

// 6. 404 Not Found Handler
app.use((req, res) => {
  sendError(res, `Route ${req.method} ${req.originalUrl} not found.`, null, 404);
});

// 7. Global Error Handler
app.use((err, req, res, next) => {
  console.error('[Unhandled Error]', err);
  const status = err.statusCode || err.status || 500;
  const message = err.message || 'Internal Server Error';
  sendError(res, message, null, status);
});

module.exports = app;

