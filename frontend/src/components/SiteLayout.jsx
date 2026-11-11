import { Link, NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext.jsx';

export default function SiteLayout() {
  const { user, signOut } = useAuth();
  const navigate = useNavigate();

  function handleSignOut() {
    signOut();
    navigate('/login');
  }

  return (
    <div className="app-shell">
      <header className="site-header">
        <Link className="brand" to="/">Clinic Booking</Link>
        {user ? (
          <nav className="site-nav" aria-label="Main navigation">
            <NavLink to="/doctors">Doctors</NavLink>
            {user.role === 'PATIENT' && <NavLink to="/appointments">My appointments</NavLink>}
            {(user.role === 'DOCTOR' || user.role === 'ADMIN') && <NavLink to="/doctor-dashboard">Dashboard</NavLink>}
            {user.role === 'PATIENT' && <NavLink to="/notifications">Notifications</NavLink>}
            <span className="nav-user">{user.email}</span>
            <button className="button secondary small" onClick={handleSignOut}>Sign out</button>
          </nav>
        ) : (
          <nav className="site-nav" aria-label="Account navigation">
            <NavLink to="/login">Sign in</NavLink>
            <NavLink to="/register">Register</NavLink>
          </nav>
        )}
      </header>
      <main className="page-content"><Outlet /></main>
      <footer className="site-footer">Appointments made easier for patients and clinics.</footer>
    </div>
  );
}
