export default function PageMessage({ children, kind = 'info' }) {
  if (!children) return null;
  return <p className={`page-message ${kind}`} role={kind === 'error' ? 'alert' : 'status'}>{children}</p>;
}
