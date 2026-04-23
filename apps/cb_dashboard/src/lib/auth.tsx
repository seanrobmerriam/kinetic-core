"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  api,
  clearSessionId,
  clearStoredSessionId,
  loadStoredSessionId,
  persistSessionId,
  probeApiBase,
  setSessionId,
  setUnauthorizedHandler,
} from "@/lib/api";
import type { AuthUser } from "@/lib/types";

type AuthState =
  | { status: "loading"; user: null; error: string }
  | { status: "unauthenticated"; user: null; error: string }
  | { status: "authenticated"; user: AuthUser; error: string };

interface AuthContextValue {
  state: AuthState;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  devToolsEnabled: boolean;
  setDevToolsEnabled: (enabled: boolean) => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const [state, setState] = useState<AuthState>({ status: "loading", user: null, error: "" });
  const [devToolsEnabled, setDevToolsEnabled] = useState<boolean>(false);
  const bootstrapped = useRef<boolean>(false);

  const handleUnauthorized = useCallback(
    (message: string) => {
      clearStoredSessionId();
      clearSessionId();
      setDevToolsEnabled(false);
      setState({ status: "unauthenticated", user: null, error: message });
      router.replace("/login");
    },
    [router],
  );

  useEffect(() => {
    setUnauthorizedHandler(handleUnauthorized);
    return () => setUnauthorizedHandler(null);
  }, [handleUnauthorized]);

  useEffect(() => {
    if (bootstrapped.current) return;
    bootstrapped.current = true;
    (async () => {
      // Pin the working API base before any auth call goes out, so a
      // transient failure on /auth/me cannot lock the client onto an
      // unreachable port.
      await probeApiBase();
      const stored = loadStoredSessionId();
      if (!stored) {
        setState({ status: "unauthenticated", user: null, error: "" });
        return;
      }
      setSessionId(stored);
      try {
        const result = await api<{ user: AuthUser }>("GET", "/auth/me");
        setState({ status: "authenticated", user: result.user, error: "" });
      } catch {
        clearStoredSessionId();
        clearSessionId();
        setState({
          status: "unauthenticated",
          user: null,
          error: "Session expired. Please sign in again.",
        });
      }
    })();
  }, []);

  const login = useCallback(async (email: string, password: string) => {
    if (!email || !password) {
      setState({
        status: "unauthenticated",
        user: null,
        error: "Email and password are required",
      });
      return;
    }
    setState({ status: "loading", user: null, error: "" });
    try {
      const result = await api<{ session_id: string; user: AuthUser }>(
        "POST",
        "/auth/login",
        { email, password },
      );
      persistSessionId(result.session_id);
      setSessionId(result.session_id);
      setState({ status: "authenticated", user: result.user, error: "" });
    } catch (err) {
      setState({
        status: "unauthenticated",
        user: null,
        error: (err as Error).message,
      });
    }
  }, []);

  const logout = useCallback(async () => {
    try {
      await api("POST", "/auth/logout");
    } catch {
      /* ignore */
    }
    clearStoredSessionId();
    clearSessionId();
    setDevToolsEnabled(false);
    setState({ status: "unauthenticated", user: null, error: "" });
    router.replace("/login");
  }, [router]);

  const value = useMemo<AuthContextValue>(
    () => ({ state, login, logout, devToolsEnabled, setDevToolsEnabled }),
    [state, login, logout, devToolsEnabled],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return ctx;
}
