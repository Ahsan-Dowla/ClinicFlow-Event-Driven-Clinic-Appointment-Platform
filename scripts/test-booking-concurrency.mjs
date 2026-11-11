const gatewayUrl = (process.env.GATEWAY_URL || 'http://localhost:8081').replace(/\/$/, '');
const email = process.env.PATIENT_EMAIL;
const password = process.env.PATIENT_PASSWORD;
const slotId = Number(process.env.CONCURRENCY_SLOT_ID);
const contenderCount = 20;

if (!email || !password || !Number.isSafeInteger(slotId) || slotId <= 0) {
  throw new Error('Set PATIENT_EMAIL, PATIENT_PASSWORD, and a fresh CONCURRENCY_SLOT_ID before running.');
}

async function request(path, token, body) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  return fetch(`${gatewayUrl}${path}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
}

const loginResponse = await request('/auth/login', null, { email, password });
if (!loginResponse.ok) {
  throw new Error(`Login failed with HTTP ${loginResponse.status}. Check the patient credentials.`);
}
const { token } = await loginResponse.json();

const results = await Promise.all(Array.from({ length: contenderCount }, async (_, index) => {
  const holdResponse = await request('/appointments/hold', token, { slotId });
  if (!holdResponse.ok) {
    return { contender: index + 1, holdStatus: holdResponse.status, confirmStatus: 'not attempted' };
  }
  const confirmResponse = await request('/appointments/confirm', token, { slotId });
  return { contender: index + 1, holdStatus: holdResponse.status, confirmStatus: confirmResponse.status };
}));

console.table(results);
const held = results.filter((result) => result.holdStatus === 200).length;
const confirmed = results.filter((result) => result.confirmStatus === 201).length;
const conflicts = results.filter((result) => result.holdStatus === 409).length;
if (held !== 1 || confirmed !== 1 || conflicts !== contenderCount - 1) {
  throw new Error(
    `Expected one hold, one confirmation, and ${contenderCount - 1} HTTP 409 conflicts; ` +
    `observed holds=${held}, confirmations=${confirmed}, conflicts=${conflicts}.`,
  );
}
console.log(`RESULT_JSON:${JSON.stringify({ contenders: contenderCount, holds: held, confirmed, conflicts })}`);
console.log(`PASS: ${contenderCount} parallel contenders produced one confirmation and ${conflicts} HTTP 409 conflicts.`);
