"use client";

import { createContext, useCallback, useContext, useMemo, useState } from "react";

interface RefreshContextValue {
  tick: number;
  bump: () => void;
}

const RefreshContext = createContext<RefreshContextValue | null>(null);

export function RefreshProvider({ children }: { children: React.ReactNode }) {
  const [tick, setTick] = useState(0);
  const bump = useCallback(() => setTick((n) => n + 1), []);
  const value = useMemo(() => ({ tick, bump }), [tick, bump]);
  return <RefreshContext.Provider value={value}>{children}</RefreshContext.Provider>;
}

export function useRefresh(): RefreshContextValue {
  const ctx = useContext(RefreshContext);
  if (!ctx) {
    throw new Error("useRefresh must be used within a RefreshProvider");
  }
  return ctx;
}
