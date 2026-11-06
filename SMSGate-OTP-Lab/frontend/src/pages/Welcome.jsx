import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { authApi } from '../services/api';

const Welcome = () => {
  const navigate = useNavigate();
  const [userName, setUserName] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchUserData = async () => {
      try {
        const response = await authApi.getMe();
        if (response.data?.data?.name) {
          setUserName(response.data.data.name);
        }
      } catch (error) {
        // Fallback to locally stored user name if available
        const storedUser = localStorage.getItem('smsgate_lab_user');
        if (storedUser) {
          const user = JSON.parse(storedUser);
          setUserName(user.name || 'User');
        } else {
          // If token was invalid, redirect to login
          localStorage.removeItem('smsgate_lab_token');
          navigate('/login');
        }
      } finally {
        setLoading(false);
      }
    };

    fetchUserData();
  }, [navigate]);

  const handleLogout = () => {
    localStorage.removeItem('smsgate_lab_token');
    localStorage.removeItem('smsgate_lab_user');
    navigate('/login');
  };

  return (
    <div className="main-content">
      <div className="card welcome-card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '2rem 0' }}>
            <span className="spinner spinner-dark"></span>
            <p style={{ marginTop: '0.75rem', color: 'var(--color-text-muted)' }}>
              Loading profile...
            </p>
          </div>
        ) : (
          <>
            <h1 className="welcome-title">Welcome, {userName || 'User'}!</h1>
            <p className="welcome-subtitle">
              Your mobile number has been verified through SMSGate.
            </p>

            <button
              type="button"
              className="btn btn-secondary"
              onClick={handleLogout}
            >
              Logout
            </button>
          </>
        )}
      </div>
    </div>
  );
};

export default Welcome;

