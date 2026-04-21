"use client";

import { createContext, useCallback, useContext, useMemo, useState } from "react";

interface NotifyContextValue {
  error: string;
  success: string;
  setError: (msg: string) => void;
  setSuccess: (msg: string) => void;
  clear: () => void;
}

const NotifyContext = createContext<NotifyContextValue | null>(null);

export function NotifyProvider({ children }: { children: React.ReactNode }) {
  const [error, setErrorState] = useState<string>("");
  const [success, setSuccessState] = useState<string>("");

  const setError = useCallback((msg: string) => {
    setErrorState(msg);
    setSuccessState("");
  }, []);

  const setSuccess = useCallback((msg: string) => {
    setSuccessState(msg);
    setErrorState("");
  }, []);

  const clear = useCallback(() => {
    setErrorState("");
    setSuccessState("");
  }, []);

  const value = useMemo<NotifyContextValue>(
    () => ({ error, success, setError, setSuccess, clear }),
    [error, success, setError, setSuccess, clear],
  );

  return <NotifyContext.Provider value={value}>{children}</NotifyContext.Provider>;
}

export function useNotify(): NotifyContextValue {
  const ctx = useContext(NotifyContext);
  if (!ctx) {
    throw new Error("useNotify must be used within a NotifyProvider");
  }
  return ctx;
}
