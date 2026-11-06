const { sendError } = require('../utils/responseHandler');

/**
 * Gateway Authentication Middleware
 * Validates incoming requests from the Android SMS Gateway Flutter client
 */
const gatewayAuth = (req, res, next) => {
  const configuredToken = process.env.GATEWAY_SECRET_TOKEN;

  // Extract token from either 'x-gateway-token' header or standard Authorization header
  let clientToken = req.headers['x-gateway-token'];
  if (!clientToken && req.headers.authorization) {
    if (req.headers.authorization.startsWith('Bearer ')) {
      clientToken = req.headers.authorization.split(' ')[1];
    } else {
      clientToken = req.headers.authorization;
    }
  }

  // If a secret token is configured in backend environment variables, enforce strict matching
  if (configuredToken && configuredToken.trim().length > 0) {
    if (!clientToken || clientToken.trim() !== configuredToken.trim()) {
      return sendError(
        res,
        'Unauthorized gateway device. Invalid or missing x-gateway-token.',
        null,
        401
      );
    }
  }

  req.gatewayId = req.headers['x-gateway-id'] || 'android-gateway-client';
  next();
};

module.exports = gatewayAuth;

