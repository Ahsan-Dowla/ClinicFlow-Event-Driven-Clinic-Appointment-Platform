import { useEffect, useState } from 'react';
import { api, errorMessage } from '../api/client.js';
import PageMessage from '../components/PageMessage.jsx';

export default function NotificationsPage() {
  const [notifications, setNotifications] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    api.get('/notifications/my')
      .then(({ data }) => { if (active) setNotifications(data); })
      .catch((requestError) => { if (active) setError(errorMessage(requestError)); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, []);

  return (
    <section>
      <div className="page-heading"><div><p className="eyebrow">Updates</p><h1>My notifications</h1></div></div>
      <PageMessage kind="error">{error}</PageMessage>
      {loading ? <p className="muted">Loading notifications…</p> : notifications.length === 0
        ? <p className="empty-state">No notifications yet. Booking updates will appear here.</p>
        : <div className="notification-list">
          {notifications.map((notification) => (
            <article className="notification-card" key={notification.id}>
              <div className="notification-icon" aria-hidden="true">
                {notification.type === 'CONFIRMATION' ? '✓' : notification.type === 'REMINDER' ? '◷' : '↗'}
              </div>
              <div><p className="eyebrow">{notification.type.toLowerCase()}</p>
                <p>{notification.message}</p>
                <span className="muted">{new Date(notification.createdAt).toLocaleString()}</span></div>
            </article>
          ))}
        </div>}
    </section>
  );
}
