import { useEffect, useState } from 'react';
import { api, errorMessage } from '../api/client.js';
import { useAuth } from '../auth/AuthContext.jsx';
import PageMessage from '../components/PageMessage.jsx';

function localDateString(date) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

function formatDate(value) {
  return new Date(value).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
}

export default function DoctorDashboardPage() {
  const { user } = useAuth();
  const [doctors, setDoctors] = useState([]);
  const [doctorId, setDoctorId] = useState('');
  const [appointments, setAppointments] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    api.get('/doctors')
      .then(({ data }) => {
        if (!active) return;
        setDoctors(data);
        const ownDoctor = data.find((doctor) => doctor.userId === user.userId);
        if (ownDoctor) setDoctorId(String(ownDoctor.id));
        else if (user.role === 'ADMIN' && data.length > 0) setDoctorId(String(data[0].id));
      })
      .catch((requestError) => { if (active) setError(errorMessage(requestError)); });
    return () => { active = false; };
  }, [user]);

  useEffect(() => {
    if (!doctorId) {
      setLoading(false);
      return undefined;
    }
    let active = true;
    setLoading(true);
    api.get(`/appointments/doctor/${doctorId}`)
      .then(({ data }) => { if (active) setAppointments(data); })
      .catch((requestError) => { if (active) setError(errorMessage(requestError)); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [doctorId]);

  const today = localDateString(new Date());
  const upcoming = appointments.filter((appointment) =>
    appointment.status === 'CONFIRMED' && appointment.startTime.slice(0, 10) >= today);

  return (
    <section>
      <div className="page-heading">
        <div><p className="eyebrow">Clinic schedule</p><h1>Doctor dashboard</h1></div>
        {user.role === 'ADMIN' && doctors.length > 0 && (
          <label className="date-picker">Doctor
            <select value={doctorId} onChange={(event) => setDoctorId(event.target.value)}>
              {doctors.map((doctor) => <option value={doctor.id} key={doctor.id}>{doctor.name}</option>)}
            </select>
          </label>
        )}
      </div>
      <PageMessage kind="error">{error}</PageMessage>
      {!loading && !doctorId && !error && <p className="empty-state">No doctor profile is linked to your account.</p>}
      {loading ? <p className="muted">Loading appointments…</p> : doctorId && upcoming.length === 0
        ? <p className="empty-state">No upcoming appointments.</p>
        : doctorId && <div className="appointment-list">
          {upcoming.map((appointment) => (
            <article className="appointment-card" key={appointment.id}>
              <div><p className="eyebrow">{appointment.startTime.slice(0, 10) === today ? "Today's appointment" : 'Upcoming'}</p>
                <h2>{formatDate(appointment.startTime)}</h2>
                <p className="muted">Patient #{appointment.patientId} · Appointment #{appointment.id}</p>
              </div>
              <span className="status-pill confirmed">confirmed</span>
            </article>
          ))}
        </div>}
    </section>
  );
}
