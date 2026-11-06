const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const otpService = require('../services/otpService');
const {
  sendSuccess,
  sendError,
  normalizeIndianMobile,
  maskMobileNumber
} = require('../utils/responseHandler');

const BCRYPT_SALT_ROUNDS = 10;

/**
 * Handle User Registration
 * POST /api/auth/register
 */
const register = async (req, res) => {
  try {
    const { name, mobileNumber, password } = req.body;

    // 1. Basic field validation
    if (!name || typeof name !== 'string' || name.trim().length < 2) {
      return sendError(res, 'Full name is required (at least 2 characters).', null, 400);
    }

    if (!password || typeof password !== 'string' || password.length < 6) {
      return sendError(res, 'Password must be at least 6 characters long.', null, 400);
    }

    // 2. Validate and normalize Indian mobile number
    const mobileCheck = normalizeIndianMobile(mobileNumber);
    if (!mobileCheck.isValid) {
      return sendError(res, mobileCheck.error, null, 400);
    }
    const normalizedMobile = mobileCheck.normalized;

    // 3. Check existing user
    let user = await User.findOne({ mobileNumber: normalizedMobile });
    if (user && user.isVerified) {
      return sendError(
        res,
        'This mobile number is already registered and verified. Please log in.',
        null,
        400
      );
    }

    // 4. Hash password
    const passwordHash = await bcrypt.hash(password, BCRYPT_SALT_ROUNDS);

    if (user && !user.isVerified) {
      // Update existing unverified user record
      user.name = name.trim();
      user.passwordHash = passwordHash;
      await user.save();
    } else {
      // Create fresh unverified user
      user = new User({
        name: name.trim(),
        mobileNumber: normalizedMobile,
        passwordHash,
        isVerified: false
      });
      await user.save();
    }

    // 5. Generate OTP and dispatch via SMSGate
    // Note: If SMSGate fails, this throws and the error handler catches it.
    // The user remains unverified.
    const smsDispatch = await otpService.generateAndSendOTP(normalizedMobile);

    return sendSuccess(
      res,
      'Registration details saved. Verification OTP sent via SMS.',
      {
        mobileNumber: normalizedMobile,
        maskedMobileNumber: maskMobileNumber(normalizedMobile),
        messageId: smsDispatch.messageId,
        gatewayStatus: smsDispatch.state
      },
      201
    );
  } catch (error) {
    console.error(`[Registration Error] ${error.message}`);
    const statusCode = error.statusCode || 500;
    return sendError(res, error.message || 'Registration failed.', null, statusCode);
  }
};

/**
 * Handle User Login
 * POST /api/auth/login
 */
const login = async (req, res) => {
  try {
    const { mobileNumber, password } = req.body;

    if (!mobileNumber || !password) {
      return sendError(res, 'Mobile number and password are required.', null, 400);
    }

    // 1. Validate & normalize mobile number
    const mobileCheck = normalizeIndianMobile(mobileNumber);
    if (!mobileCheck.isValid) {
      return sendError(res, mobileCheck.error, null, 400);
    }
    const normalizedMobile = mobileCheck.normalized;

    // 2. Find user
    const user = await User.findOne({ mobileNumber: normalizedMobile });
    if (!user) {
      return sendError(res, 'Invalid mobile number or password.', null, 401);
    }

    // 3. Verify user status
    if (!user.isVerified) {
      return sendError(
        res,
        'Mobile number is not verified. Please complete OTP verification before logging in.',
        {
          mobileNumber: normalizedMobile,
          maskedMobileNumber: maskMobileNumber(normalizedMobile),
          needsVerification: true
        },
        403
      );
    }

    // 4. Check password
    const isPasswordValid = await bcrypt.compare(password, user.passwordHash);
    if (!isPasswordValid) {
      return sendError(res, 'Invalid mobile number or password.', null, 401);
    }

    // 5. Generate JWT token
    const secret = process.env.JWT_SECRET || 'smsgate_lab_dev_jwt_secret_key_123';
    const expiresIn = process.env.JWT_EXPIRES_IN || '1d';

    const token = jwt.sign(
      {
        id: user._id,
        mobileNumber: user.mobileNumber,
        name: user.name
      },
      secret,
      { expiresIn }
    );

    return sendSuccess(res, 'Login successful.', {
      token,
      user: {
        id: user._id,
        name: user.name,
        mobileNumber: user.mobileNumber
      }
    });
  } catch (error) {
    console.error(`[Login Error] ${error.message}`);
    return sendError(res, 'An error occurred during login. Please try again.', null, 500);
  }
};

/**
 * Retrieve Current Authenticated User Profile
 * GET /api/auth/me
 */
const getCurrentUser = async (req, res) => {
  try {
    const user = await User.findById(req.user.id).select('name mobileNumber isVerified createdAt');
    if (!user) {
      return sendError(res, 'User not found.', null, 404);
    }

    return sendSuccess(res, 'Profile retrieved.', {
      id: user._id,
      name: user.name,
      mobileNumber: user.mobileNumber,
      isVerified: user.isVerified,
      createdAt: user.createdAt
    });
  } catch (error) {
    return sendError(res, 'Failed to fetch user profile.', null, 500);
  }
};

module.exports = {
  register,
  login,
  getCurrentUser
};

