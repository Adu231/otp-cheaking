import React, { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { authApi } from '../services/api';

const Register = () => {
  const navigate = useNavigate();

  const [formData, setFormData] = useState({
    name: '',
    mobileNumber: '',
    password: '',
    confirmPassword: ''
  });

  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  const [fieldErrors, setFieldErrors] = useState({});

  const validateIndianMobile = (number) => {
    const cleaned = number.replace(/[\s\-()]/g, '');
    return /^(?:\+91|91|0)?([6-9]\d{9})$/.test(cleaned);
  };

  const validateForm = () => {
    const errors = {};

    if (!formData.name.trim() || formData.name.trim().length < 2) {
      errors.name = 'Please enter your full name (at least 2 characters).';
    }

    if (!formData.mobileNumber.trim()) {
      errors.mobileNumber = 'Mobile number is required.';
    } else if (!validateIndianMobile(formData.mobileNumber.trim())) {
      errors.mobileNumber = 'Please enter a valid 10-digit Indian mobile number (e.g. 9876543210).';
    }

    if (!formData.password) {
      errors.password = 'Password is required.';
    } else if (formData.password.length < 6) {
      errors.password = 'Password must be at least 6 characters.';
    }

    if (formData.password !== formData.confirmPassword) {
      errors.confirmPassword = 'Passwords do not match.';
    }

    setFieldErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
    // Clear field-specific error as user types
    if (fieldErrors[name]) {
      setFieldErrors((prev) => ({ ...prev, [name]: '' }));
    }
    setErrorMessage('');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setErrorMessage('');

    if (!validateForm()) {
      return;
    }

    setLoading(true);

    try {
      const response = await authApi.register({
        name: formData.name.trim(),
        mobileNumber: formData.mobileNumber.trim(),
        password: formData.password
      });

      const { data } = response.data;

      // Navigate to OTP verification only after backend successfully accepts SMS dispatch
      navigate('/verify-otp', {
        state: {
          mobileNumber: data.mobileNumber,
          maskedMobileNumber: data.maskedMobileNumber,
          messageId: data.messageId
        }
      });
    } catch (error) {
      const serverMessage =
        error.response?.data?.message ||
        error.response?.data?.error ||
        error.message ||
        'Failed to complete registration.';
      setErrorMessage(serverMessage);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="main-content">
      <div className="card">
        <h2 className="card-title">Create Account</h2>
        <p className="card-subtitle">
          Register to test real SMS OTP delivery via SMSGate
        </p>

        {errorMessage && (
          <div className="alert alert-error">
            <span>⚠️</span>
            <div>{errorMessage}</div>
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label className="form-label" htmlFor="name">
              Full Name
            </label>
            <input
              id="name"
              type="text"
              name="name"
              className="form-input"
              placeholder="e.g. Aditya Sharma"
              value={formData.name}
              onChange={handleChange}
              disabled={loading}
              autoComplete="name"
            />
            {fieldErrors.name && <div className="form-hint" style={{ color: 'var(--color-error)' }}>{fieldErrors.name}</div>}
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="mobileNumber">
              Indian Mobile Number
            </label>
            <input
              id="mobileNumber"
              type="tel"
              name="mobileNumber"
              className="form-input"
              placeholder="e.g. 9876543210 or +919876543210"
              value={formData.mobileNumber}
              onChange={handleChange}
              disabled={loading}
              autoComplete="tel"
            />
            <div className="form-hint">
              10-digit Indian number. SMS will be delivered to this SIM via Android SMSGate.
            </div>
            {fieldErrors.mobileNumber && (
              <div className="form-hint" style={{ color: 'var(--color-error)' }}>
                {fieldErrors.mobileNumber}
              </div>
            )}
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="password">
              Password
            </label>
            <input
              id="password"
              type="password"
              name="password"
              className="form-input"
              placeholder="Minimum 6 characters"
              value={formData.password}
              onChange={handleChange}
              disabled={loading}
              autoComplete="new-password"
            />
            {fieldErrors.password && (
              <div className="form-hint" style={{ color: 'var(--color-error)' }}>
                {fieldErrors.password}
              </div>
            )}
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="confirmPassword">
              Confirm Password
            </label>
            <input
              id="confirmPassword"
              type="password"
              name="confirmPassword"
              className="form-input"
              placeholder="Re-enter password"
              value={formData.confirmPassword}
              onChange={handleChange}
              disabled={loading}
              autoComplete="new-password"
            />
            {fieldErrors.confirmPassword && (
              <div className="form-hint" style={{ color: 'var(--color-error)' }}>
                {fieldErrors.confirmPassword}
              </div>
            )}
          </div>

          <button type="submit" className="btn btn-primary" disabled={loading}>
            {loading ? (
              <>
                <span className="spinner"></span>
                <span>Sending OTP via SMSGate...</span>
              </>
            ) : (
              'Register & Send OTP'
            )}
          </button>
        </form>

        <div className="card-footer">
          Already have a verified account? <Link to="/login">Login here</Link>
        </div>
      </div>
    </div>
  );
};

export default Register;

