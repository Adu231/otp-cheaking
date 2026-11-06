const jwt = require('jsonwebtoken');
const { sendError } = require('../utils/responseHandler');

/**
 * JWT Authentication Middleware
 * Protects endpoints requiring a verified logged-in session
 */
const authMiddleware = (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return sendError(res, 'Authentication token missing or invalid.', null, 401);
    }

    const token = authHeader.split(' ')[1];

    if (!token) {
      return sendError(res, 'Authentication token missing.', null, 401);
    }

    const secret = process.env.JWT_SECRET;
    if (!secret) {
      console.error('[SECURITY WARNING] JWT_SECRET is not defined in backend/.env');
      return sendError(res, 'Server configuration error.', null, 500);
    }

    const decoded = jwt.verify(token, secret);
    req.user = decoded;
    next();
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return sendError(res, 'Session expired. Please log in again.', null, 401);
    }
    return sendError(res, 'Invalid authentication token.', null, 401);
  }
};

module.exports = authMiddleware;

