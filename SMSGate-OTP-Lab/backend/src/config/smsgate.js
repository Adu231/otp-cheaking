/**
 * SMSGate Configuration
 * Manages SMS Gateway for Android connection parameters
 */

const smsgateConfig = {
  baseURL: (process.env.SMSGATE_BASE_URL || 'https://api.sms-gate.app').replace(/\/+$/, ''),
  username: process.env.SMSGATE_USERNAME || '',
  password: process.env.SMSGATE_PASSWORD || '',
  deviceId: process.env.SMSGATE_DEVICE_ID || null,
  simNumber: process.env.SMSGATE_SIM_NUMBER ? parseInt(process.env.SMSGATE_SIM_NUMBER, 10) : null,
  timeoutMs: 15000,

  /**
   * Check if SMSGate credentials are fully configured
   * @returns {boolean}
   */
  isConfigured() {
    return Boolean(this.username && this.password);
  },

  /**
   * Get basic auth header value
   * @returns {string}
   */
  getBasicAuthHeader() {
    if (!this.isConfigured()) {
      throw new Error(
        'SMSGate credentials are missing. Please set SMSGATE_USERNAME and SMSGATE_PASSWORD in backend/.env'
      );
    }
    const token = Buffer.from(`${this.username}:${this.password}`).toString('base64');
    return `Basic ${token}`;
  }
};

module.exports = smsgateConfig;

