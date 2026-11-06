const express = require('express');
const router = express.Router();
const authController = require('../controllers/authController');
const authMiddleware = require('../middleware/authMiddleware');
const { authLimiter } = require('../middleware/rateLimiter');

// Public auth endpoints
router.post('/register', authLimiter, authController.register);
router.post('/login', authLimiter, authController.login);

// Protected auth endpoints
router.get('/me', authMiddleware, authController.getCurrentUser);

module.exports = router;

