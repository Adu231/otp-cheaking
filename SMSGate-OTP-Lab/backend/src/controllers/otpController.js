const otpService = require('../services/otpService');
const {
  sendSuccess,
  sendError,
  normalizeIndianMobile,
  maskMobileNumber
} = require('../utils/responseHandler');

/**
 * Handle OTP Verification
 * POST /api/otp/verify
 */
const verifyOTP = async (req, res) => {
  try {
    const { mobileNumber, otp } = req.body;

    if (!mobileNumber || !otp) {
      return sendError(res, 'Mobile number and OTP are required.', null, 400);
    }

    const mobileCheck = normalizeIndianMobile(mobileNumber);
    if (!mobileCheck.isValid) {
      return sendError(res, mobileCheck.error, null, 400);
    }

    const result = await otpService.verifyOTP(mobileCheck.normalized, otp);

    return sendSuccess(res, result.message, {
      mobileNumber: mobileCheck.normalized,
      isVerified: true
    });
  } catch (error) {
    const statusCode = error.statusCode || 500;
    return sendError(res, error.message || 'OTP verification failed.', null, statusCode);
  }
};

/**
 * Handle OTP Resend Request
 * POST /api/otp/resend
 */
const resendOTP = async (req, res) => {
  try {
    const { mobileNumber } = req.body;

    if (!mobileNumber) {
      return sendError(res, 'Mobile number is required.', null, 400);
    }

    const mobileCheck = normalizeIndianMobile(mobileNumber);
    if (!mobileCheck.isValid) {
      return sendError(res, mobileCheck.error, null, 400);
    }

    const normalizedMobile = mobileCheck.normalized;

    const result = await otpService.resendOTP(normalizedMobile);

    return sendSuccess(res, 'A new verification OTP has been sent via SMS.', {
      mobileNumber: normalizedMobile,
      maskedMobileNumber: maskMobileNumber(normalizedMobile),
      messageId: result.messageId,
      gatewayStatus: result.state
    });
  } catch (error) {
    const statusCode = error.statusCode || 500;
    return sendError(res, error.message || 'Failed to resend OTP.', null, statusCode);
  }
};

/**
 * Check Real-Time SMSGate Message Delivery Status
 * GET /api/otp/status/:messageId
 */
const getDeliveryStatus = async (req, res) => {
  try {
    const { messageId } = req.params;

    if (!messageId) {
      return sendError(res, 'Message ID is required.', null, 400);
    }

    const statusData = await otpService.checkDeliveryStatus(messageId);

    return sendSuccess(res, 'SMSGate status retrieved.', statusData);
  } catch (error) {
    const statusCode = error.statusCode || 500;
    return sendError(res, error.message || 'Failed to fetch status from SMSGate.', null, statusCode);
  }
};

module.exports = {
  verifyOTP,
  resendOTP,
  getDeliveryStatus
};

