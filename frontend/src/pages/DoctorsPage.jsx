import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, errorMessage } from '../api/client.js';
import PageMessage from '../components/PageMessage.jsx';

export default function DoctorsPage() {
  const [doctors, setDoctors] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    api.get('/doctors')
      .then(({ data }) => { if (active) setDoctors(data); })
      .catch((requestError) => { if (active) setError(errorMessage(requestError)); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, []);

  return (
    <section>
      <div className="page-heading">
        <div><p className="eyebrow">Find your care team</p><h1>Our doctors</h1></div>
        <p className="muted">Choose a specialist to see available appointment times.</p>
      </div>
      <PageMessage kind="error">{error}</PageMessage>
      {loading ? <p className="muted">Loading doctors…</p> : doctors.length === 0
        ? <p className="empty-state">No doctors are available yet.</p>
        : <div className="card-grid">
          {doctors.map((doctor) => (
            <article className="doctor-card" key={doctor.id}>
              <div className="avatar" aria-hidden="true">{doctor.name?.slice(0, 1).toUpperCase()}</div>
              <div><h2>{doctor.name}</h2><p className="muted">{doctor.specialization}</p></div>
              <Link className="button primary" to={`/doctors/${doctor.id}/slots`}>View slots</Link>
            </article>
          ))}
        </div>}
    </section>
  );
}
