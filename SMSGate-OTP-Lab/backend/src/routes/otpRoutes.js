const express = require('express');
const router = express.Router();
const otpController = require('../controllers/otpController');
const { otpLimiter } = require('../middleware/rateLimiter');

// OTP endpoints
router.post('/verify', otpLimiter, otpController.verifyOTP);
router.post('/resend', otpLimiter, otpController.resendOTP);

// Delivery status tracking endpoint
router.get('/status/:messageId', otpController.getDeliveryStatus);

module.exports = router;

