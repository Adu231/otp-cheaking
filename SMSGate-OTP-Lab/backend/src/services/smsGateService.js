const axios = require('axios');
const smsgateConfig = require('../config/smsgate');

/**
 * SMSGate Provider Service
 * Handles direct integration with the SMS Gateway for Android REST API
 * Documentation: https://docs.sms-gate.app/integration/api/
 */
class SMSGateService {
  constructor() {
    this.providerName = 'SMSGate';
  }

  /**
   * Internal helper to create an Axios client with SMSGate Basic Auth headers
   */
  getClient() {
    if (!smsgateConfig.isConfigured()) {
      throw new Error(
        'SMSGate is not configured. Please set SMSGATE_USERNAME and SMSGATE_PASSWORD in backend/.env'
      );
    }

    return axios.create({
      baseURL: smsgateConfig.baseURL,
      headers: {
        'Content-Type': 'application/json',
        Authorization: smsgateConfig.getBasicAuthHeader()
      },
      timeout: smsgateConfig.timeoutMs
    });
  }

  /**
   * Send SMS via SMSGate REST API
   * POST /3rdparty/v1/messages
   *
   * @param {Object} params
   * @param {string} params.to E.164 formatted recipient phone number (+91XXXXXXXXXX)
   * @param {string} params.message Message content string
   * @returns {Promise<{ success: boolean, messageId: string|null, state: string, raw: any }>}
   */
  async sendSMS({ to, message }) {
    if (!to) {
      throw new Error('Recipient phone number is required.');
    }
    if (!message) {
      throw new Error('Message text is required.');
    }

    const client = this.getClient();

    const payload = {
      textMessage: {
        text: message
      },
      phoneNumbers: [to],
      ttl: 300
    };

    // Attach specific device ID or SIM number if configured
    if (smsgateConfig.deviceId) {
      payload.deviceId = smsgateConfig.deviceId;
    }
    if (smsgateConfig.simNumber) {
      payload.simNumber = smsgateConfig.simNumber;
    }

    try {
      console.log(`[SMSGate] Dispatching SMS request to ${to} via ${smsgateConfig.baseURL}...`);

      const response = await client.post('/3rdparty/v1/messages', payload);

      const data = response.data || {};
      const messageId = data.id || null;
      // Note: State at acceptance is typically 'Pending' or 'Processed'.
      // This indicates acceptance by SMSGate server, NOT final delivery to recipient.
      const state = data.state || 'Pending';

      console.log(`[SMSGate] SMS request accepted by gateway. ID: ${messageId}, Initial State: ${state}`);

      return {
        success: true,
        provider: this.providerName,
        messageId,
        state,
        raw: data
      };
    } catch (error) {
      let errorMessage = 'Failed to send SMS through SMSGate.';

      if (error.response) {
        const status = error.response.status;
        const respData = error.response.data;

        if (status === 401) {
          errorMessage = 'SMSGate authentication failed. Please verify SMSGATE_USERNAME and SMSGATE_PASSWORD.';
        } else if (status === 400) {
          errorMessage = `SMSGate bad request: ${respData?.message || JSON.stringify(respData)}`;
        } else if (status === 404) {
          errorMessage = 'SMSGate endpoint not found. Verify SMSGATE_BASE_URL.';
        } else {
          errorMessage = `SMSGate responded with HTTP ${status}: ${respData?.message || error.message}`;
        }
      } else if (error.code === 'ECONNABORTED') {
        errorMessage = 'SMSGate request timed out. Gateway did not respond in time.';
      } else if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
        errorMessage = `Unable to connect to SMSGate at ${smsgateConfig.baseURL}. Check network connection or server URL.`;
      } else {
        errorMessage = error.message || errorMessage;
      }

      console.error(`[SMSGate Error] ${errorMessage}`);

      const failureError = new Error(errorMessage);
      failureError.statusCode = error.response?.status || 502;
      failureError.originalError = error;
      throw failureError;
    }
  }

  /**
   * Retrieve current message delivery status from SMSGate
   * GET /3rdparty/v1/messages/{id}
   *
   * Documented States:
   * - Pending: Enqueued on gateway server, awaiting Android phone sync
   * - Processed: Android device received message and handed to Android SMS API
   * - Sent: SMS Center (SMSC) accepted the SMS
   * - Delivered: Recipient handset confirmed receipt
   * - Failed: Terminal error during transmission
   * - Cancelling / Cancelled: Request was revoked
   *
   * @param {string} messageId SMSGate message ID
   * @returns {Promise<{ id: string, state: string, states: any, recipients: any[] }>}
   */
  async getMessageStatus(messageId) {
    if (!messageId) {
      throw new Error('Message ID is required to query SMSGate status.');
    }

    const client = this.getClient();

    try {
      const response = await client.get(`/3rdparty/v1/messages/${encodeURIComponent(messageId)}`);
      const data = response.data || {};

      return {
        id: data.id || messageId,
        state: data.state || 'Unknown',
        states: data.states || {},
        recipients: data.recipients || [],
        raw: data
      };
    } catch (error) {
      let errorMessage = `Failed to fetch SMSGate message status for ID ${messageId}.`;

      if (error.response) {
        if (error.response.status === 404) {
          errorMessage = `Message ID ${messageId} not found in SMSGate.`;
        } else {
          errorMessage = `SMSGate responded with HTTP ${error.response.status}: ${error.response.data?.message || error.message}`;
        }
      } else {
        errorMessage = error.message || errorMessage;
      }

      console.error(`[SMSGate Status Error] ${errorMessage}`);

      const statusError = new Error(errorMessage);
      statusError.statusCode = error.response?.status || 502;
      throw statusError;
    }
  }
}

// Export singleton instance for modular use
module.exports = new SMSGateService();

