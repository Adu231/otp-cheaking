const SMSLog = require('../models/SMSLog');
const { sendSuccess, sendError, maskMobileNumber } = require('../utils/responseHandler');

const CLAIM_TIMEOUT_MS = 90 * 1000; // 90 seconds claim lease
const MAX_BATCH_TASKS = 10;

/**
 * Retrieve pending SMS tasks awaiting dispatch
 * Atomically locks and claims tasks to prevent duplicate dispatch
 * GET /api/gateway/pending
 */
const getPendingTasks = async (req, res) => {
  try {
    const claimedTasks = [];
    const claimExpiry = new Date(Date.now() - CLAIM_TIMEOUT_MS);

    // Atomically claim pending queued tasks one-by-one to avoid race conditions
    for (let i = 0; i < MAX_BATCH_TASKS; i++) {
      const task = await SMSLog.findOneAndUpdate(
        {
          provider: 'AndroidGateway',
          messageStatus: 'Queued',
          $or: [
            { dispatchClaimedAt: null },
            { dispatchClaimedAt: { $lt: claimExpiry } }
          ]
        },
        {
          $set: {
            messageStatus: 'Claimed',
            dispatchClaimedAt: new Date(),
            claimedBy: req.gatewayId || 'android-gateway'
          }
        },
        {
          sort: { createdAt: 1 },
          new: true
        }
      );

      if (!task) {
        break; // No more queued tasks to claim
      }

      // Log claim without exposing message body or OTP
      console.log(
        `[Gateway Sync] Task ${task.providerMessageId} claimed for ${maskMobileNumber(task.mobileNumber)}`
      );

      claimedTasks.push({
        id: task.providerMessageId,
        phoneNumber: task.mobileNumber,
        message: task.message,
        status: 'pending',
        timestamp: task.createdAt
      });
    }

    // Exact response structure matching Flutter client: { success: true, tasks: [...] }
    return res.status(200).json({
      success: true,
      tasks: claimedTasks
    });
  } catch (error) {
    console.error(`[Gateway Pending Error] ${error.message}`);
    return sendError(res, 'Failed to fetch pending gateway tasks.', null, 500);
  }
};

/**
 * Update SMS dispatch status reported by Android phone
 * POST /api/gateway/status
 */
const updateStatus = async (req, res) => {
  try {
    const { messageId, status, errorMessage } = req.body;

    // Validate payload
    if (!messageId || typeof messageId !== 'string' || messageId.trim().length === 0) {
      return sendError(res, 'Valid messageId is required.', null, 400);
    }

    if (!status || typeof status !== 'string') {
      return sendError(res, 'Valid status string is required.', null, 400);
    }

    // Normalize incoming status string
    let normalizedStatus;
    const lower = status.trim().toLowerCase();
    switch (lower) {
      case 'sent':
        normalizedStatus = 'Sent';
        break;
      case 'delivered':
        normalizedStatus = 'Delivered';
        break;
      case 'failed':
      case 'deliveryfailed':
        normalizedStatus = 'Failed';
        break;
      case 'sending':
        normalizedStatus = 'Sending';
        break;
      case 'pending':
        normalizedStatus = 'Pending';
        break;
      default:
        normalizedStatus = status.trim();
    }

    // Find corresponding SMSLog by providerMessageId
    const smsLog = await SMSLog.findOne({ providerMessageId: messageId.trim() });

    if (!smsLog) {
      return sendError(res, `No SMS dispatch log found for message ID: ${messageId}`, null, 404);
    }

    // Update status and error details
    smsLog.messageStatus = normalizedStatus;
    if (errorMessage && typeof errorMessage === 'string') {
      smsLog.errorMessage = errorMessage;
    }
    smsLog.updatedAt = new Date();
    await smsLog.save();

    console.log(
      `[Gateway Status] Message ${messageId} (${maskMobileNumber(smsLog.mobileNumber)}) updated to: ${normalizedStatus}`
    );

    return sendSuccess(res, 'Gateway message status updated successfully.', {
      messageId: smsLog.providerMessageId,
      status: normalizedStatus,
      updatedAt: smsLog.updatedAt
    });
  } catch (error) {
    console.error(`[Gateway Status Error] ${error.message}`);
    return sendError(res, 'Failed to update gateway status.', null, 500);
  }
};

module.exports = {
  getPendingTasks,
  updateStatus
};

