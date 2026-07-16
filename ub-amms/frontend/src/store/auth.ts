import { create } from "zustand";
import { api } from "../api/client";
import type { User } from "../types";

interface AuthState {
  user: User | null;
  loading: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
}

function storedUser(): User | null {
  const value = localStorage.getItem("ub_amms_user");
  try {
    return value ? (JSON.parse(value) as User) : null;
  } catch {
    return null;
  }
}

export const useAuthStore = create<AuthState>((set) => ({
  user: storedUser(),
  loading: false,
  login: async (username, password) => {
    set({ loading: true });
    try {
      const body = new URLSearchParams({ username, password });
      const { data } = await api.post("/auth/login", body, {
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
      });
      localStorage.setItem("ub_amms_token", data.access_token);
      localStorage.setItem("ub_amms_user", JSON.stringify(data.user));
      set({ user: data.user });
    } finally {
      set({ loading: false });
    }
  },
  logout: () => {
    localStorage.removeItem("ub_amms_token");
    localStorage.removeItem("ub_amms_user");
    set({ user: null });
  },
}));
