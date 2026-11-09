import React, { useState, useEffect, useRef } from 'react';
import { useLocation, useNavigate, Link } from 'react-router-dom';
import { otpApi } from '../services/api';

const RESEND_COOLDOWN_SECONDS = 60;

const VerifyOTP = () => {
  const location = useLocation();
  const navigate = useNavigate();

  // Mobile number passed from Register page or Login page
  const initialMobile = location.state?.mobileNumber || '';
  const initialMasked = location.state?.maskedMobileNumber || initialMobile;
  const initialMessageId = location.state?.messageId || '';

  const [mobileNumber, setMobileNumber] = useState(initialMobile);
  const [maskedMobile, setMaskedMobile] = useState(initialMasked);
  const [lastMessageId, setLastMessageId] = useState(initialMessageId);

  // 6 individual OTP digit boxes
  const [otpDigits, setOtpDigits] = useState(['', '', '', '', '', '']);
  const inputRefs = useRef([]);

  const [verifying, setVerifying] = useState(false);
  const [resending, setResending] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  const [successMessage, setSuccessMessage] = useState('');
  const [isVerified, setIsVerified] = useState(false);

  // Cooldown countdown timer
  const [cooldown, setCooldown] = useState(RESEND_COOLDOWN_SECONDS);

  useEffect(() => {
    let timer = null;
    if (cooldown > 0) {
      timer = setInterval(() => {
        setCooldown((prev) => (prev > 0 ? prev - 1 : 0));
      }, 1000);
    }
    return () => {
      if (timer) clearInterval(timer);
    };
  }, [cooldown]);

  const handleOtpChange = (index, value) => {
    // Only accept uppercase English alphabet letters (A-Z), auto-convert lowercase to uppercase
    const cleaned = value.toUpperCase().replace(/[^A-Z]/g, '');

    // Handle paste of complete 6-letter code
    if (cleaned.length > 1) {
      const pasted = cleaned.slice(0, 6).split('');
      const newDigits = [...otpDigits];
      pasted.forEach((d, idx) => {
        newDigits[idx] = d;
      });
      setOtpDigits(newDigits);
      const nextIndex = Math.min(pasted.length, 5);
      inputRefs.current[nextIndex]?.focus();
      return;
    }

    const newDigits = [...otpDigits];
    newDigits[index] = cleaned;
    setOtpDigits(newDigits);
    setErrorMessage('');

    // Auto-focus next input box if letter entered
    if (cleaned && index < 5) {
      inputRefs.current[index + 1]?.focus();
    }
  };

  const handleKeyDown = (index, e) => {
    if (e.key === 'Backspace' && !otpDigits[index] && index > 0) {
      inputRefs.current[index - 1]?.focus();
    }
  };

  const fullOTP = otpDigits.join('');

  const handleVerify = async (e) => {
    e.preventDefault();
    setErrorMessage('');
    setSuccessMessage('');

    if (!mobileNumber) {
      setErrorMessage('Mobile number is missing. Please return to registration.');
      return;
    }

    if (fullOTP.length !== 6) {
      setErrorMessage('Please enter all 6 letters of the OTP.');
      return;
    }

    setVerifying(true);

    try {
      const response = await otpApi.verify({
        mobileNumber,
        otp: fullOTP
      });

      setIsVerified(true);
      setSuccessMessage(
        response.data?.message || 'Mobile number verified successfully! You can now log in.'
      );
    } catch (error) {
      const serverMessage =
        error.response?.data?.message ||
        error.response?.data?.error ||
        error.message ||
        'OTP verification failed.';
      setErrorMessage(serverMessage);
    } finally {
      setVerifying(false);
    }
  };

  const handleResend = async () => {
    if (cooldown > 0 || resending) return;

    setErrorMessage('');
    setSuccessMessage('');
    setResending(true);

    try {
      const response = await otpApi.resend({ mobileNumber });
      const { data } = response.data;

      setCooldown(RESEND_COOLDOWN_SECONDS);
      setOtpDigits(['', '', '', '', '', '']);
      inputRefs.current[0]?.focus();

      if (data?.messageId) {
        setLastMessageId(data.messageId);
      }

      setSuccessMessage('A fresh OTP has been sent via SMSGate to your mobile number.');
    } catch (error) {
      const serverMessage =
        error.response?.data?.message ||
        error.response?.data?.error ||
        error.message ||
        'Failed to resend OTP.';
      setErrorMessage(serverMessage);
    } finally {
      setResending(false);
    }
  };

  return (
    <div className="main-content">
      <div className="card">
        <h2 className="card-title">Verify Phone Number</h2>
        <p className="card-subtitle">
          Enter the 6-letter verification code sent via SMS
        </p>

        {maskedMobile && (
          <div style={{ textAlign: 'center' }}>
            <span className="masked-phone-badge">{maskedMobile}</span>
          </div>
        )}

        {errorMessage && (
          <div className="alert alert-error">
            <span>⚠️</span>
            <div>{errorMessage}</div>
          </div>
        )}

        {successMessage && (
          <div className="alert alert-success">
            <span>✅</span>
            <div>{successMessage}</div>
          </div>
        )}

        {!mobileNumber ? (
          <div style={{ textAlign: 'center', marginTop: '1rem' }}>
            <p className="form-hint" style={{ marginBottom: '1rem' }}>
              No active verification session found. Please register first.
            </p>
            <Link to="/register" className="btn btn-primary">
              Go to Registration
            </Link>
          </div>
        ) : isVerified ? (
          <div style={{ marginTop: '1.5rem' }}>
            <Link to="/login" className="btn btn-primary">
              Proceed to Login
            </Link>
          </div>
        ) : (
          <form onSubmit={handleVerify}>
            <div className="otp-input-container">
              {otpDigits.map((digit, idx) => (
                <input
                  key={idx}
                  ref={(el) => (inputRefs.current[idx] = el)}
                  type="text"
                  inputMode="text"
                  maxLength={1}
                  className="otp-box"
                  style={{ textTransform: 'uppercase' }}
                  value={digit}
                  onChange={(e) => handleOtpChange(idx, e.target.value)}
                  onKeyDown={(e) => handleKeyDown(idx, e)}
                  disabled={verifying || isVerified}
                  autoFocus={idx === 0}
                />
              ))}
            </div>

            <button
              type="submit"
              className="btn btn-primary"
              disabled={verifying || fullOTP.length !== 6}
            >
              {verifying ? (
                <>
                  <span className="spinner"></span>
                  <span>Verifying Code...</span>
                </>
              ) : (
                'Verify OTP'
              )}
            </button>

            <div className="resend-section">
              <span className="resend-cooldown">
                {cooldown > 0
                  ? `Resend available in ${cooldown}s`
                  : "Didn't receive the SMS?"}
              </span>
              <button
                type="button"
                className="resend-link"
                onClick={handleResend}
                disabled={cooldown > 0 || resending}
              >
                {resending ? 'Sending...' : 'Resend OTP'}
              </button>
            </div>
          </form>
        )}

        <div className="card-footer">
          Entered the wrong number? <Link to="/register">Register again</Link>
        </div>
      </div>
    </div>
  );
};

export default VerifyOTP;

