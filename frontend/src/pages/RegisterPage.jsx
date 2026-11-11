import { useState } from 'react';
import { Link, Navigate, useNavigate } from 'react-router-dom';
import { api, errorMessage } from '../api/client.js';
import { useAuth } from '../auth/AuthContext.jsx';
import PageMessage from '../components/PageMessage.jsx';

export default function RegisterPage() {
  const { token, user } = useAuth();
  const navigate = useNavigate();
  const [form, setForm] = useState({ name: '', email: '', phone: '', password: '' });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  if (token && user) return <Navigate to="/doctors" replace />;

  function update(event) {
    setForm({ ...form, [event.target.name]: event.target.value });
  }

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      await api.post('/auth/register', form);
      navigate('/login', { state: { message: 'Your account is ready. Sign in to continue.' } });
    } catch (requestError) {
      setError(errorMessage(requestError));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="auth-card">
      <p className="eyebrow">Create your account</p>
      <h1>Register</h1>
      <p className="muted">Registration creates a patient account.</p>
      <PageMessage kind="error">{error}</PageMessage>
      <form className="form-stack" onSubmit={submit}>
        <label>Full name
          <input name="name" autoComplete="name" required maxLength="120" value={form.name} onChange={update} />
        </label>
        <label>Email
          <input name="email" type="email" autoComplete="email" required maxLength="254"
            value={form.email} onChange={update} />
        </label>
        <label>Phone <span className="optional">(optional)</span>
          <input name="phone" type="tel" autoComplete="tel" maxLength="30" value={form.phone} onChange={update} />
        </label>
        <label>Password
          <input name="password" type="password" autoComplete="new-password" minLength="8" maxLength="72"
            required value={form.password} onChange={update} />
          <span className="field-hint">Use at least 8 characters.</span>
        </label>
        <button className="button primary full-width" type="submit" disabled={busy}>
          {busy ? 'Creating account…' : 'Create account'}
        </button>
      </form>
      <p className="form-footnote">Already registered? <Link to="/login">Sign in</Link></p>
    </section>
  );
}
