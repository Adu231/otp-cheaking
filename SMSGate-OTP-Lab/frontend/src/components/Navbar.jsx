import React from 'react';
import { Link, useNavigate, useLocation } from 'react-router-dom';

const Navbar = () => {
  const navigate = useNavigate();
  const location = useLocation();

  const token = localStorage.getItem('smsgate_lab_token');
  const storedUser = localStorage.getItem('smsgate_lab_user');
  const user = storedUser ? JSON.parse(storedUser) : null;

  const handleLogout = () => {
    localStorage.removeItem('smsgate_lab_token');
    localStorage.removeItem('smsgate_lab_user');
    navigate('/login');
  };

  return (
    <nav className="navbar">
      <div className="navbar-container">
        <Link to="/" className="navbar-brand">
          <span>📲 SMSGate OTP Lab</span>
          <span className="navbar-tag">Android Gateway</span>
        </Link>

        <div className="navbar-links">
          <Link
            to="/"
            className={`nav-link ${location.pathname === '/' ? 'active' : ''}`}
          >
            Home
          </Link>

          {token ? (
            <>
              <Link
                to="/welcome"
                className={`nav-link ${location.pathname === '/welcome' ? 'active' : ''}`}
              >
                Welcome
              </Link>
              <button
                onClick={handleLogout}
                className="btn btn-secondary"
                style={{ width: 'auto', padding: '0.4rem 0.85rem', fontSize: '0.85rem' }}
              >
                Logout
              </button>
            </>
          ) : (
            <>
              <Link
                to="/register"
                className={`nav-link ${location.pathname === '/register' ? 'active' : ''}`}
              >
                Register
              </Link>
              <Link
                to="/login"
                className={`nav-link ${location.pathname === '/login' ? 'active' : ''}`}
              >
                Login
              </Link>
            </>
          )}
        </div>
      </div>
    </nav>
  );
};

export default Navbar;

