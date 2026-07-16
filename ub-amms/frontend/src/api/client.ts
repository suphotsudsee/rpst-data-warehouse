import axios from "axios";

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL ?? "/api/v1",
  timeout: 30000,
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem("ub_amms_token");
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem("ub_amms_token");
      localStorage.removeItem("ub_amms_user");
      if (window.location.pathname !== "/login") window.location.assign("/login");
    }
    return Promise.reject(error);
  },
);
