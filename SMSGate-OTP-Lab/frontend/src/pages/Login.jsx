import React, { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { authApi } from '../services/api';

const Login = () => {
  const navigate = useNavigate();

  const [formData, setFormData] = useState({
    mobileNumber: '',
    password: ''
  });

  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  const [needsVerification, setNeedsVerification] = useState(false);
  const [unverifiedMobile, setUnverifiedMobile] = useState('');

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
    setErrorMessage('');
  };

  const handleLogin = async (e) => {
    e.preventDefault();
    setErrorMessage('');
    setNeedsVerification(false);

    if (!formData.mobileNumber.trim() || !formData.password) {
      setErrorMessage('Please enter both mobile number and password.');
      return;
    }

    setLoading(true);

    try {
      const response = await authApi.login({
        mobileNumber: formData.mobileNumber.trim(),
        password: formData.password
      });

      const { data } = response.data;

      // Store JWT token and user info
      localStorage.setItem('smsgate_lab_token', data.token);
      localStorage.setItem('smsgate_lab_user', JSON.stringify(data.user));

      navigate('/welcome');
    } catch (error) {
      const resp = error.response?.data;
      const status = error.response?.status;

      if (status === 403 && resp?.data?.needsVerification) {
        setNeedsVerification(true);
        setUnverifiedMobile(resp.data.mobileNumber);
        setErrorMessage(resp.message || 'Mobile number is not verified. Please complete OTP verification.');
      } else {
        setErrorMessage(
          resp?.message || resp?.error || error.message || 'Failed to login. Please try again.'
        );
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="main-content">
      <div className="card">
        <h2 className="card-title">Login</h2>
        <p className="card-subtitle">
          Sign in with your verified mobile number
        </p>

        {errorMessage && (
          <div className="alert alert-error">
            <span>⚠️</span>
            <div>
              {errorMessage}
              {needsVerification && (
                <div style={{ marginTop: '0.5rem' }}>
                  <button
                    type="button"
                    className="btn btn-outline"
                    style={{ fontSize: '0.85rem', padding: '0.4rem 0.75rem', width: 'auto' }}
                    onClick={() =>
                      navigate('/verify-otp', {
                        state: { mobileNumber: unverifiedMobile }
                      })
                    }
                  >
                    Verify OTP Now
                  </button>
                </div>
              )}
            </div>
          </div>
        )}

        <form onSubmit={handleLogin}>
          <div className="form-group">
            <label className="form-label" htmlFor="mobileNumber">
              Mobile Number
            </label>
            <input
              id="mobileNumber"
              type="tel"
              name="mobileNumber"
              className="form-input"
              placeholder="e.g. 9876543210"
              value={formData.mobileNumber}
              onChange={handleChange}
              disabled={loading}
              autoComplete="tel"
            />
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
              placeholder="Enter your password"
              value={formData.password}
              onChange={handleChange}
              disabled={loading}
              autoComplete="current-password"
            />
          </div>

          <button type="submit" className="btn btn-primary" disabled={loading}>
            {loading ? (
              <>
                <span className="spinner"></span>
                <span>Signing In...</span>
              </>
            ) : (
              'Login'
            )}
          </button>
        </form>

        <div className="card-footer">
          Don't have an account? <Link to="/register">Register here</Link>
        </div>
      </div>
    </div>
  );
};

export default Login;

