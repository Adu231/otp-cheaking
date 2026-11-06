const crypto = require('crypto');

/**
 * Generate a cryptographically secure 6-digit numeric OTP.
 * Ranges from 100000 to 999999 inclusive.
 * @returns {string} 6-digit OTP string
 */
const generateOTP = () => {
  const otpNumber = crypto.randomInt(100000, 1000000);
  return otpNumber.toString();
};

module.exports = generateOTP;

