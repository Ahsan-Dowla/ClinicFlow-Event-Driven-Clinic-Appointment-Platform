import { useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api, errorMessage } from '../api/client.js';
import PageMessage from '../components/PageMessage.jsx';

function todayString() {
  const now = new Date();
  now.setDate(now.getDate() + 1);
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

export default function DoctorSlotsPage() {
  const { doctorId } = useParams();
  const [doctor, setDoctor] = useState(null);
  const [date, setDate] = useState(todayString);
  const [slots, setSlots] = useState([]);
  const [hold, setHold] = useState(null);
  const [secondsLeft, setSecondsLeft] = useState(0);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [busySlot, setBusySlot] = useState(null);

  const expiresAt = useMemo(() => hold?.holdExpiresAt ? new Date(hold.holdExpiresAt).getTime() : null, [hold]);

  useEffect(() => {
    let active = true;
    api.get(`/doctors/${doctorId}`)
      .then(({ data }) => { if (active) setDoctor(data); })
      .catch((requestError) => { if (active) setError(errorMessage(requestError)); });
    return () => { active = false; };
  }, [doctorId]);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError('');
    api.get(`/doctors/${doctorId}/slots`, { params: { date, status: 'AVAILABLE' } })
      .then(({ data }) => { if (active) setSlots(data); })
      .catch((requestError) => { if (active) setError(errorMessage(requestError)); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [doctorId, date]);

  useEffect(() => {
    if (!expiresAt) return undefined;
    function updateCountdown() {
      const remaining = Math.max(0, Math.ceil((expiresAt - Date.now()) / 1000));
      setSecondsLeft(remaining);
      if (remaining === 0) {
        setHold(null);
        setMessage('Your booking hold expired. Select the slot again to create a new hold.');
      }
    }
    updateCountdown();
    const timer = window.setInterval(updateCountdown, 1000);
    return () => window.clearInterval(timer);
  }, [expiresAt]);

  async function holdSlot(slotId) {
    setBusySlot(slotId);
    setError('');
    setMessage('');
    try {
      const { data } = await api.post('/appointments/hold', { slotId });
      setHold(data);
      setMessage('Slot held. Confirm before the countdown reaches zero.');
    } catch (requestError) {
      setError(errorMessage(requestError));
    } finally {
      setBusySlot(null);
    }
  }

  async function confirmBooking() {
    if (!hold || secondsLeft <= 0) return;
    setBusySlot(hold.slotId);
    setError('');
    try {
      await api.post('/appointments/confirm', { slotId: hold.slotId });
      setHold(null);
      setMessage('Appointment confirmed.');
      const { data } = await api.get(`/doctors/${doctorId}/slots`, { params: { date, status: 'AVAILABLE' } });
      setSlots(data);
    } catch (requestError) {
      setError(errorMessage(requestError));
      if (requestError.response?.status === 409 || requestError.response?.status === 410) setHold(null);
    } finally {
      setBusySlot(null);
    }
  }

  return (
    <section>
      <Link className="back-link" to="/doctors">← All doctors</Link>
      <div className="page-heading">
        <div><p className="eyebrow">Book an appointment</p><h1>{doctor?.name || 'Doctor slots'}</h1>
          {doctor && <p className="muted">{doctor.specialization}</p>}</div>
        <label className="date-picker">Appointment date
          <input type="date" value={date} onChange={(event) => { setDate(event.target.value); setHold(null); setMessage(''); }} />
        </label>
      </div>
      <PageMessage kind="error">{error}</PageMessage>
      <PageMessage>{message}</PageMessage>
      {hold && secondsLeft > 0 && (
        <div className="hold-banner">
          <div><strong>Slot held for you</strong><span>Confirm within the remaining time.</span></div>
          <strong className="countdown" aria-live="polite">
            {Math.floor(secondsLeft / 60)}:{String(secondsLeft % 60).padStart(2, '0')}
          </strong>
          <button className="button primary" onClick={confirmBooking} disabled={busySlot !== null}>
            {busySlot === hold.slotId ? 'Confirming…' : 'Confirm appointment'}
          </button>
        </div>
      )}
      {loading ? <p className="muted">Loading available times…</p> : slots.length === 0
        ? <p className="empty-state">No available times for this date. Try another date.</p>
        : <div className="slot-list">
          {slots.map((slot) => (
            <article className="slot-row" key={slot.id}>
              <div><strong>{new Date(slot.startTime).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}</strong>
                <span className="muted"> to {new Date(slot.endTime).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}</span></div>
              <button className="button secondary" onClick={() => holdSlot(slot.id)}
                disabled={busySlot !== null || hold?.slotId === slot.id}>
                {busySlot === slot.id ? 'Holding…' : hold?.slotId === slot.id ? 'Held' : 'Book'}
              </button>
            </article>
          ))}
        </div>}
    </section>
  );
}
