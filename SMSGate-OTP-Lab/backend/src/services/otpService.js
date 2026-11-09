const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const OTPRequest = require('../models/OTPRequest');
const SMSLog = require('../models/SMSLog');
const User = require('../models/User');
const generateOTP = require('../utils/generateOTP');
const smsGateService = require('./smsGateService');
const smsgateConfig = require('../config/smsgate');

const OTP_EXPIRATION_MINUTES = 5;
const RESEND_COOLDOWN_SECONDS = 60;
const MAX_VERIFICATION_ATTEMPTS = 5;
const MAX_RESENDS_PER_HOUR = 5;
const BCRYPT_SALT_ROUNDS = 10;

class OTPService {
  /**
   * Generate an OTP, persist the hashed OTP request, and dispatch via SMSGate.
   *
   * @param {string} mobileNumber Normalized E.164 mobile number (+91XXXXXXXXXX)
   * @returns {Promise<{ messageId: string|null, state: string, expiresAt: Date }>}
   */
  async generateAndSendOTP(mobileNumber) {
    if (!mobileNumber) {
      throw new Error('Mobile number is required to send OTP.');
    }

    // 1. Generate cryptographically secure 6-digit OTP
    const rawOTP = generateOTP();

    // 2. Hash OTP using bcrypt before storing
    const otpHash = await bcrypt.hash(rawOTP, BCRYPT_SALT_ROUNDS);
    const expiresAt = new Date(Date.now() + OTP_EXPIRATION_MINUTES * 60 * 1000);

    // 3. Invalidate previous active OTPs for this mobile number
    await OTPRequest.updateMany(
      { mobileNumber, isUsed: false, expiresAt: { $gt: new Date() } },
      { $set: { isUsed: true } }
    );

    // 4. Create new OTPRequest record
    const otpRecord = new OTPRequest({
      mobileNumber,
      otpHash,
      expiresAt,
      attempts: 0,
      isUsed: false
    });
    await otpRecord.save();

    // 5. Construct required message text (clean format without DLT-blocked keywords)
    const message = `Hello, code: ${rawOTP}`;

    // 6. Check Provider: In-House Android Gateway vs SMSGate Cloud
    const useInHouseGateway =
      process.env.SMS_PROVIDER === 'android-gateway' || !smsgateConfig.isConfigured();

    if (useInHouseGateway) {
      const messageId = `gw_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
      const smsLogEntry = new SMSLog({
        mobileNumber,
        provider: 'AndroidGateway',
        providerMessageId: messageId,
        message,
        messageStatus: 'Queued'
      });
      await smsLogEntry.save();

      console.log(`[OTP Service] Task ${messageId} queued for In-House Android Gateway dispatch.`);

      return {
        messageId,
        state: 'Queued',
        expiresAt
      };
    }

    // 7. Dispatch via SMSGate Cloud
    let smsResult = null;
    let smsLogEntry = new SMSLog({
      mobileNumber,
      provider: smsGateService.providerName,
      message,
      messageStatus: 'Initiating'
    });

    try {
      smsResult = await smsGateService.sendSMS({
        to: mobileNumber,
        message
      });

      smsLogEntry.providerMessageId = smsResult.messageId;
      smsLogEntry.messageStatus = smsResult.state || 'Pending';
      await smsLogEntry.save();

      return {
        messageId: smsResult.messageId,
        state: smsResult.state,
        expiresAt
      };
    } catch (smsError) {
      // Record failure in SMSLog
      smsLogEntry.messageStatus = 'Failed';
      smsLogEntry.errorMessage = smsError.message;
      await smsLogEntry.save();

      // Invalidate the OTP request so it cannot be used if SMS failed to dispatch
      otpRecord.isUsed = true;
      await otpRecord.save();

      // Re-throw to inform caller that SMS sending failed
      throw smsError;
    }
  }

  /**
   * Resend an OTP to a mobile number with cooldown and limit checks.
   *
   * @param {string} mobileNumber
   * @returns {Promise<{ messageId: string|null, state: string, expiresAt: Date }>}
   */
  async resendOTP(mobileNumber) {
    // 1. Check user exists
    const user = await User.findOne({ mobileNumber });
    if (!user) {
      const err = new Error('No registration found for this mobile number.');
      err.statusCode = 404;
      throw err;
    }

    if (user.isVerified) {
      const err = new Error('This mobile number is already verified. Please log in.');
      err.statusCode = 400;
      throw err;
    }

    // 2. Enforce 60-second cooldown
    const latestRequest = await OTPRequest.findOne({ mobileNumber }).sort({ createdAt: -1 });

    if (latestRequest) {
      const elapsedSeconds = Math.floor((Date.now() - new Date(latestRequest.createdAt).getTime()) / 1000);
      if (elapsedSeconds < RESEND_COOLDOWN_SECONDS) {
        const remaining = RESEND_COOLDOWN_SECONDS - elapsedSeconds;
        const err = new Error(`Please wait ${remaining} second${remaining > 1 ? 's' : ''} before requesting another OTP.`);
        err.statusCode = 429;
        throw err;
      }
    }

    // 3. Enforce maximum resends within 1 hour
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    const recentRequestsCount = await OTPRequest.countDocuments({
      mobileNumber,
      createdAt: { $gte: oneHourAgo }
    });

    if (recentRequestsCount >= MAX_RESENDS_PER_HOUR) {
      const err = new Error('Too many OTP requests in a short period. Please try again after 1 hour.');
      err.statusCode = 429;
      throw err;
    }

    // 4. Generate and send new OTP
    return await this.generateAndSendOTP(mobileNumber);
  }

  /**
   * Verify an OTP securely against the latest active OTP request.
   *
   * @param {string} mobileNumber
   * @param {string} inputOTP
   * @returns {Promise<{ verified: boolean, message: string }>}
   */
  async verifyOTP(mobileNumber, inputOTP) {
    const cleanOTP =
      inputOTP && typeof inputOTP === 'string' ? inputOTP.trim().toUpperCase() : '';

    if (!cleanOTP || !/^[A-Z]{6}$/.test(cleanOTP)) {
      const err = new Error('Please enter a valid 6-character OTP code (A-Z).');
      err.statusCode = 400;
      throw err;
    }

    // 1. Find the latest active OTP request
    const activeRequest = await OTPRequest.findOne({
      mobileNumber,
      isUsed: false,
      expiresAt: { $gt: new Date() }
    }).sort({ createdAt: -1 });

    if (!activeRequest) {
      const err = new Error('OTP is invalid or has expired. Please request a new OTP.');
      err.statusCode = 400;
      throw err;
    }

    // 2. Check maximum verification attempts
    if (activeRequest.attempts >= MAX_VERIFICATION_ATTEMPTS) {
      activeRequest.isUsed = true;
      await activeRequest.save();

      const err = new Error('Maximum verification attempts exceeded. Please request a new OTP.');
      err.statusCode = 400;
      throw err;
    }

    // 3. Securely compare OTP using bcrypt
    const isMatch = await bcrypt.compare(cleanOTP, activeRequest.otpHash);

    if (!isMatch) {
      activeRequest.attempts += 1;
      await activeRequest.save();

      const remainingAttempts = MAX_VERIFICATION_ATTEMPTS - activeRequest.attempts;
      const err = new Error(
        remainingAttempts > 0
          ? `Incorrect OTP. You have ${remainingAttempts} attempt${remainingAttempts > 1 ? 's' : ''} remaining.`
          : 'Incorrect OTP. Maximum verification attempts exceeded. Please request a new OTP.'
      );
      err.statusCode = 400;
      throw err;
    }

    // 4. OTP is correct: mark request as used
    activeRequest.isUsed = true;
    await activeRequest.save();

    // 5. Mark user as verified
    const user = await User.findOneAndUpdate(
      { mobileNumber },
      { $set: { isVerified: true } },
      { new: true }
    );

    if (!user) {
      const err = new Error('User not found.');
      err.statusCode = 404;
      throw err;
    }

    return {
      verified: true,
      message: 'Mobile number verified successfully. You can now log in.'
    };
  }

  /**
   * Check message status via in-house Android Gateway logs or SMSGate API
   *
   * @param {string} messageId
   * @returns {Promise<any>}
   */
  async checkDeliveryStatus(messageId) {
    const existingLog = await SMSLog.findOne({ providerMessageId: messageId });
    if (existingLog && existingLog.provider === 'AndroidGateway') {
      return {
        id: messageId,
        provider: 'AndroidGateway',
        state: existingLog.messageStatus,
        states: { [existingLog.messageStatus]: existingLog.updatedAt },
        errorMessage: existingLog.errorMessage,
        recipients: [
          {
            phoneNumber: existingLog.mobileNumber,
            state: existingLog.messageStatus
          }
        ]
      };
    }

    const statusResult = await smsGateService.getMessageStatus(messageId);

    // Update corresponding SMSLog entry if present
    if (statusResult.state) {
      await SMSLog.findOneAndUpdate(
        { providerMessageId: messageId },
        {
          $set: {
            messageStatus: statusResult.state,
            updatedAt: new Date()
          }
        }
      );
    }

    return statusResult;
  }
}

module.exports = new OTPService();

