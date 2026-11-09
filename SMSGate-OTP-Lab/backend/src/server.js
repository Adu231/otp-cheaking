const path = require('path');
const dotenv = require('dotenv');

// Load environment variables from backend/.env if present
dotenv.config({ path: path.join(__dirname, '../.env') });

const app = require('./app');
const connectDatabase = require('./config/database');
const smsgateConfig = require('./config/smsgate');

const PORT = process.env.PORT || 5000;

const startServer = async () => {
  console.log('----------------------------------------------------');
  console.log('🚀 SMSGate OTP Lab - Backend Initializing');
  console.log('----------------------------------------------------');

  // Connect to MongoDB Atlas
  await connectDatabase();

  // Validate SMSGate Configuration
  if (smsgateConfig.isConfigured()) {
    console.log(`[SMSGate] Configured to target: ${smsgateConfig.baseURL}`);
    console.log(`[SMSGate] Connected with username: ${smsgateConfig.username}`);
  } else {
    console.warn(
      '\x1b[33m%s\x1b[0m',
      '[SMSGate WARNING] SMSGATE_USERNAME and/or SMSGATE_PASSWORD are not set in backend/.env.'
    );
    console.warn(
      '\x1b[33m%s\x1b[0m',
      '[SMSGate WARNING] The server will run, but OTP SMS requests will fail until configured.'
    );
  }

  // Start Express HTTP Server
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`[HTTP Server] Listening on http://localhost:${PORT}`);
    console.log(`[HTTP Server] Health check available at: http://localhost:${PORT}/api/health`);
    console.log('----------------------------------------------------');
  });
};

startServer().catch((err) => {
  console.error('[FATAL SERVER ERROR]', err);
  process.exit(1);
});

