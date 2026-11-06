import React from 'react';
import { Link } from 'react-router-dom';

const Home = () => {
  return (
    <div className="main-content">
      <div className="card hero-card">
        <div className="hero-icon">📱</div>
        <h1 className="card-title">SMSGate OTP Lab</h1>
        <p className="card-subtitle">
          Test real SMS delivery using Android SMS Gateway.
        </p>

        <div className="hero-actions">
          <Link to="/register" className="btn btn-primary">
            Register New User
          </Link>
          <Link to="/login" className="btn btn-secondary">
            Login
          </Link>
        </div>
      </div>
    </div>
  );
};

export default Home;

