import { createContext, useContext, useMemo, useState } from 'react';
import { api, setAccessToken } from '../api/client.js';

const AuthContext = createContext(null);

function readStoredUser() {
  try {
    return JSON.parse(localStorage.getItem('clinic_user') || 'null');
  } catch {
    return null;
  }
}

export function AuthProvider({ children }) {
  const [token, setToken] = useState(() => localStorage.getItem('clinic_token'));
  const [user, setUser] = useState(readStoredUser);

  function signIn(authResponse) {
    localStorage.setItem('clinic_token', authResponse.token);
    const nextUser = {
      userId: authResponse.userId,
      email: authResponse.email,
      role: authResponse.role,
    };
    localStorage.setItem('clinic_user', JSON.stringify(nextUser));
    setAccessToken(authResponse.token);
    setToken(authResponse.token);
    setUser(nextUser);
  }

  function signOut() {
    localStorage.removeItem('clinic_token');
    localStorage.removeItem('clinic_user');
    setAccessToken(null);
    setToken(null);
    setUser(null);
  }

  const value = useMemo(() => ({ token, user, signIn, signOut }), [token, user]);
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return value;
}

export async function signInWithCredentials(email, password, signIn) {
  const response = await api.post('/auth/login', { email, password });
  signIn(response.data);
}
