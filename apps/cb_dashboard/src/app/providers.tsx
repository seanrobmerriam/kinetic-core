"use client";

import { AuthProvider } from "@/lib/auth";
import { NotifyProvider } from "@/lib/notify";
import { RefreshProvider } from "@/lib/refresh";

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <AuthProvider>
      <NotifyProvider>
        <RefreshProvider>{children}</RefreshProvider>
      </NotifyProvider>
    </AuthProvider>
  );
}
