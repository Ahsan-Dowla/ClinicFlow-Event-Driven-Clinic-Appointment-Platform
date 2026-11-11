import { useState } from 'react';
import { Link, Navigate, useNavigate } from 'react-router-dom';
import { errorMessage } from '../api/client.js';
import { signInWithCredentials, useAuth } from '../auth/AuthContext.jsx';
import PageMessage from '../components/PageMessage.jsx';

export default function LoginPage() {
  const { token, user, signIn } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  if (token && user) return <Navigate to="/doctors" replace />;

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      await signInWithCredentials(email, password, signIn);
      navigate('/doctors');
    } catch (requestError) {
      setError(errorMessage(requestError));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="auth-card">
      <p className="eyebrow">Welcome back</p>
      <h1>Sign in</h1>
      <p className="muted">Use your clinic booking account to continue.</p>
      <PageMessage kind="error">{error}</PageMessage>
      <form className="form-stack" onSubmit={submit}>
        <label>Email
          <input type="email" autoComplete="email" required value={email}
            onChange={(event) => setEmail(event.target.value)} />
        </label>
        <label>Password
          <input type="password" autoComplete="current-password" required value={password}
            onChange={(event) => setPassword(event.target.value)} />
        </label>
        <button className="button primary full-width" type="submit" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
      <p className="form-footnote">New to the clinic? <Link to="/register">Create an account</Link></p>
    </section>
  );
}
