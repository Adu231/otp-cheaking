const mongoose = require('mongoose');

const smsLogSchema = new mongoose.Schema(
  {
    mobileNumber: {
      type: String,
      required: [true, 'Mobile number is required'],
      trim: true,
      index: true
    },
    provider: {
      type: String,
      default: 'SMSGate',
      trim: true,
      index: true
    },
    providerMessageId: {
      type: String,
      default: null,
      trim: true,
      index: true
    },
    message: {
      type: String,
      default: null
    },
    messageStatus: {
      type: String,
      default: 'Pending',
      trim: true,
      index: true
    },
    errorMessage: {
      type: String,
      default: null
    },
    dispatchClaimedAt: {
      type: Date,
      default: null,
      index: true
    },
    claimedBy: {
      type: String,
      default: null
    },
    createdAt: {
      type: Date,
      default: Date.now,
      index: true
    },
    updatedAt: {
      type: Date,
      default: Date.now
    }
  },
  {
    timestamps: false
  }
);

smsLogSchema.pre('save', function (next) {
  this.updatedAt = new Date();
  next();
});

const SMSLog = mongoose.model('SMSLog', smsLogSchema);

module.exports = SMSLog;
