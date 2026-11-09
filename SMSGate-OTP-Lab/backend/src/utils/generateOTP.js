const crypto = require('crypto');

const CHARSET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/**
 * Generate a cryptographically secure 6-character alphabet-only OTP (A-Z).
 * Contains only uppercase English letters, no numbers or special characters.
 * @returns {string} 6-character uppercase alphabet OTP string
 */
const generateOTP = () => {
  let otp = '';
  for (let i = 0; i < 6; i++) {
    const randomIndex = crypto.randomInt(0, CHARSET.length);
    otp += CHARSET[randomIndex];
  }
  return otp;
};

module.exports = generateOTP;
