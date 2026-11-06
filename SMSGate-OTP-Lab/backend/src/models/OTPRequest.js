const mongoose = require('mongoose');

const otpRequestSchema = new mongoose.Schema(
  {
    mobileNumber: {
      type: String,
      required: [true, 'Mobile number is required'],
      index: true,
      trim: true
    },
    otpHash: {
      type: String,
      required: [true, 'OTP hash is required']
    },
    expiresAt: {
      type: Date,
      required: [true, 'Expiration time is required'],
      index: true
    },
    attempts: {
      type: Number,
      default: 0
    },
    isUsed: {
      type: Boolean,
      default: false
    },
    createdAt: {
      type: Date,
      default: Date.now,
      index: true
    }
  },
  {
    timestamps: false
  }
);

// Method to safely sanitize representation
otpRequestSchema.methods.toJSON = function () {
  const obj = this.toObject();
  delete obj.otpHash;
  return obj;
};

const OTPRequest = mongoose.model('OTPRequest', otpRequestSchema);

module.exports = OTPRequest;

