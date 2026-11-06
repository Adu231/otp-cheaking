/**
 * Standardized API Response Handlers and Data Formatters
 */

/**
 * Send successful response
 * @param {import('express').Response} res
 * @param {string} message
 * @param {any} data
 * @param {number} statusCode
 */
const sendSuccess = (res, message, data = null, statusCode = 200) => {
  const response = {
    success: true,
    message
  };

  if (data !== null && data !== undefined) {
    response.data = data;
  }

  return res.status(statusCode).json(response);
};

/**
 * Send error response
 * @param {import('express').Response} res
 * @param {string} message
 * @param {any} error
 * @param {number} statusCode
 */
const sendError = (res, message, error = null, statusCode = 500) => {
  const response = {
    success: false,
    message
  };

  if (error !== null && error !== undefined) {
    // Avoid leaking stack traces or sensitive internals
    response.error = typeof error === 'string' ? error : error.message || error;
  }

  return res.status(statusCode).json(response);
};

/**
 * Validate and normalize Indian mobile number to E.164 format (+91XXXXXXXXXX)
 * Accepts:
 *  - 10 digits starting with 6, 7, 8, or 9 (e.g. 9876543210)
 *  - With 0 prefix (e.g. 09876543210)
 *  - With 91 prefix (e.g. 919876543210)
 *  - With +91 prefix (e.g. +919876543210)
 * @param {string} input
 * @returns {{ isValid: boolean, normalized: string|null, error: string|null }}
 */
const normalizeIndianMobile = (input) => {
  if (!input || typeof input !== 'string') {
    return { isValid: false, normalized: null, error: 'Mobile number is required' };
  }

  const cleaned = input.replace(/[\s\-()]/g, '');
  const match = cleaned.match(/^(?:\+91|91|0)?([6-9]\d{9})$/);

  if (!match) {
    return {
      isValid: false,
      normalized: null,
      error: 'Please enter a valid 10-digit Indian mobile number (e.g. 9876543210)'
    };
  }

  const tenDigit = match[1];
  return {
    isValid: true,
    normalized: `+91${tenDigit}`,
    error: null
  };
};

/**
 * Mask mobile number for safe display (e.g., +91 ****** 4567)
 * @param {string} mobileNumber
 * @returns {string}
 */
const maskMobileNumber = (mobileNumber) => {
  if (!mobileNumber || typeof mobileNumber !== 'string') return '';
  const digits = mobileNumber.replace(/\D/g, '');
  if (digits.length < 10) return mobileNumber;

  const last4 = digits.slice(-4);
  return `+91 ****** ${last4}`;
};

module.exports = {
  sendSuccess,
  sendError,
  normalizeIndianMobile,
  maskMobileNumber
};

