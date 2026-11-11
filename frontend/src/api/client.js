import axios from 'axios';

const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8081';
let accessToken = localStorage.getItem('clinic_token');

export function setAccessToken(token) {
  accessToken = token;
}

export const api = axios.create({
  baseURL: apiBaseUrl.replace(/\/$/, ''),
  headers: { 'Content-Type': 'application/json' },
});

api.interceptors.request.use((config) => {
  if (accessToken) {
    config.headers.Authorization = `Bearer ${accessToken}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    const status = error.response?.status;
    if (status === 409) {
      error.userMessage = 'This slot or appointment has changed. Refresh and try again.';
    } else if (status === 410) {
      error.userMessage = 'Your booking hold expired. Hold the slot again to continue.';
    } else {
      error.userMessage = error.response?.data?.message || 'The request could not be completed.';
    }
    return Promise.reject(error);
  },
);

export function errorMessage(error) {
  return error.userMessage || error.response?.data?.message || 'The request could not be completed.';
}
