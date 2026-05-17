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
  hasPermission: (permission: string) => boolean;
  hasAnyPermission: (permissions: string[]) => boolean;
  devToolsEnabled: boolean;
  setDevToolsEnabled: (enabled: boolean) => void;
}

const LEGACY_ROLE_PERMISSIONS: Record<string, string[]> = {
  operations: ["user.read", "user.write", "role.read", "permission.read"],
  read_only: ["user.read", "role.read", "permission.read"],
};

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

  const hasPermission = useCallback(
    (permission: string) => {
      if (state.status !== "authenticated") return false;
      if (state.user.role === "admin") return true;

      const explicitPermissions = state.user.permissions ?? [];
      if (explicitPermissions.includes(permission)) return true;

      const legacyPermissions = LEGACY_ROLE_PERMISSIONS[state.user.role] ?? [];
      return legacyPermissions.includes(permission);
    },
    [state],
  );

  const hasAnyPermission = useCallback(
    (permissions: string[]) => permissions.some((permission) => hasPermission(permission)),
    [hasPermission],
  );

  const value = useMemo<AuthContextValue>(
    () => ({
      state,
      login,
      logout,
      hasPermission,
      hasAnyPermission,
      devToolsEnabled,
      setDevToolsEnabled,
    }),
    [state, login, logout, hasPermission, hasAnyPermission, devToolsEnabled],
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
