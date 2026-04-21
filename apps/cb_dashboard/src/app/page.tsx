"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";

export default function Home() {
  const router = useRouter();
  const { state } = useAuth();

  useEffect(() => {
    if (state.status === "authenticated") {
      router.replace("/dashboard");
    } else if (state.status === "unauthenticated") {
      router.replace("/login");
    }
  }, [state.status, router]);

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
