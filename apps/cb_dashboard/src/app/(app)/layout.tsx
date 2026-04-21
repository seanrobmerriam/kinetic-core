"use client";

import { useEffect, useRef } from "react";
import { usePathname, useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { Sidebar } from "@/components/Sidebar";
import { Header } from "@/components/Header";
import { Alerts } from "@/components/Alerts";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const { state } = useAuth();
  const { clear } = useNotify();
  const { bump } = useRefresh();
  const lastPath = useRef<string | null>(null);

  useEffect(() => {
    if (lastPath.current !== pathname) {
      lastPath.current = pathname;
      clear();
    }
  }, [pathname, clear]);

  useEffect(() => {
    if (state.status === "unauthenticated") {
      router.replace("/login");
    }
  }, [state.status, router]);

  if (state.status !== "authenticated") {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-50">
        <div
          data-testid="loading"
          className="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white px-6 py-4 text-sm text-slate-500 shadow-sm"
        >
          <span className="inline-block h-3 w-3 animate-pulse rounded-full bg-indigo-500" />
          Loading…
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-slate-50">
      <Sidebar />
      <div className="ml-64 flex min-h-screen flex-col">
        <Header
          onRefresh={() => {
            bump();
            router.refresh();
          }}
        />
        <main className="flex-1 px-8 py-8">
          <Alerts />
          {children}
        </main>
      </div>
    </div>
  );
}
