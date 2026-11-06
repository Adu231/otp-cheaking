const express = require('express');
const router = express.Router();
const gatewayController = require('../controllers/gatewayController');
const gatewayAuth = require('../middleware/gatewayAuth');

// Android Gateway polling and status endpoints
router.get('/pending', gatewayAuth, gatewayController.getPendingTasks);
router.post('/status', gatewayAuth, gatewayController.updateStatus);

module.exports = router;

