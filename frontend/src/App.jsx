import { Navigate, Route, Routes } from 'react-router-dom';
import ProtectedRoute from './components/ProtectedRoute.jsx';
import SiteLayout from './components/SiteLayout.jsx';
import AppointmentsPage from './pages/AppointmentsPage.jsx';
import DoctorDashboardPage from './pages/DoctorDashboardPage.jsx';
import DoctorSlotsPage from './pages/DoctorSlotsPage.jsx';
import DoctorsPage from './pages/DoctorsPage.jsx';
import LoginPage from './pages/LoginPage.jsx';
import NotificationsPage from './pages/NotificationsPage.jsx';
import RegisterPage from './pages/RegisterPage.jsx';

export default function App() {
  return (
    <Routes>
      <Route element={<SiteLayout />}>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/register" element={<RegisterPage />} />
        <Route element={<ProtectedRoute />}>
          <Route index element={<Navigate to="/doctors" replace />} />
          <Route path="/doctors" element={<DoctorsPage />} />
          <Route path="/doctors/:doctorId/slots" element={<DoctorSlotsPage />} />
          <Route path="/appointments" element={<AppointmentsPage />} />
          <Route path="/notifications" element={<NotificationsPage />} />
        </Route>
        <Route element={<ProtectedRoute roles={['DOCTOR', 'ADMIN']} />}>
          <Route path="/doctor-dashboard" element={<DoctorDashboardPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
