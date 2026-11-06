import React from 'react';
import { Navigate } from 'react-router-dom';

/**
 * Route wrapper that ensures the user holds a valid JWT token in localStorage.
 * If not authenticated, redirects to the /login page.
 */
const ProtectedRoute = ({ children }) => {
  const token = localStorage.getItem('smsgate_lab_token');

  if (!token) {
    return <Navigate to="/login" replace />;
  }

  return children;
};

export default ProtectedRoute;

