import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, errorMessage } from '../api/client.js';
import PageMessage from '../components/PageMessage.jsx';

function formatDate(value) {
  return new Date(value).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
}

export default function AppointmentsPage() {
  const [appointments, setAppointments] = useState([]);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [loading, setLoading] = useState(true);
  const [cancelling, setCancelling] = useState(null);

  const loadAppointments = useCallback(async () => {
    setError('');
    try {
      const { data } = await api.get('/appointments/my');
      setAppointments(data);
    } catch (requestError) {
      setError(errorMessage(requestError));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadAppointments(); }, [loadAppointments]);

  async function cancel(appointmentId) {
    setCancelling(appointmentId);
    setError('');
    setMessage('');
    try {
      await api.post(`/appointments/${appointmentId}/cancel`);
      setMessage('Appointment cancelled.');
      await loadAppointments();
    } catch (requestError) {
      setError(errorMessage(requestError));
    } finally {
      setCancelling(null);
    }
  }

  return (
    <section>
      <div className="page-heading"><div><p className="eyebrow">Your schedule</p><h1>My appointments</h1></div></div>
      <PageMessage kind="error">{error}</PageMessage>
      <PageMessage>{message}</PageMessage>
      {loading ? <p className="muted">Loading appointments…</p> : appointments.length === 0
        ? <div className="empty-state">You have no appointments yet. <Link to="/doctors">Find a doctor</Link>.</div>
        : <div className="appointment-list">
          {appointments.map((appointment) => (
            <article className="appointment-card" key={appointment.id}>
              <div>
                <p className="eyebrow">Appointment #{appointment.id}</p>
                <h2>{formatDate(appointment.startTime)}</h2>
                <p className="muted">Doctor #{appointment.doctorId} · Slot #{appointment.slotId}</p>
              </div>
              <div className="appointment-actions">
                <span className={`status-pill ${appointment.status.toLowerCase()}`}>{appointment.status.toLowerCase()}</span>
                {appointment.status === 'CONFIRMED' && (
                  <button className="button danger" onClick={() => cancel(appointment.id)}
                    disabled={cancelling === appointment.id}>
                    {cancelling === appointment.id ? 'Cancelling…' : 'Cancel'}
                  </button>
                )}
              </div>
            </article>
          ))}
        </div>}
    </section>
  );
}
