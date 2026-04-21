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

  // Clear banner messages on route change.
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
      <div className="app-layout">
        <div className="main-content">
          <div className="content-area">
            <div className="loading-spinner" data-testid="loading">
              Loading...
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="app-layout">
      <Sidebar />
      <div className="main-content">
        <Header
          onRefresh={() => {
            bump();
            router.refresh();
          }}
        />
        <div className="content-area">
          <Alerts />
          {children}
        </div>
      </div>
    </div>
  );
}
