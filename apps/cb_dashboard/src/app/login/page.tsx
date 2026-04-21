"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";

export default function LoginPage() {
  const router = useRouter();
  const { state, login } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  useEffect(() => {
    if (state.status === "authenticated") {
      router.replace("/dashboard");
    }
  }, [state.status, router]);

  const submit = (e: FormEvent) => {
    e.preventDefault();
    void login(email, password);
  };

  const loading = state.status === "loading";

  return (
    <div className="app-layout">
      <div className="main-content">
        <div className="content-area login-shell">
          <div className="login-hero">
            <h1 className="login-hero-title">IronLedger Dashboard</h1>
            <p className="login-hero-subtitle">
              Modern core banking operations with real-time visibility and controls.
            </p>
            <div className="login-hero-meta">Secure operator access</div>
          </div>
          <div className="login-auth">
            <div className="dashboard-card login-card" data-testid="login-form">
              <h2 className="page-title">Dashboard Sign In</h2>
              <p>Use the configured IronLedger operator credentials to continue.</p>
              {state.error && (
                <div className="alert alert-error" data-testid="error-banner">
                  {state.error}
                </div>
              )}
              {loading && (
                <div className="loading-spinner" data-testid="loading">
                  Signing in...
                </div>
              )}
              <form className="login-form" onSubmit={submit}>
                <label className="form-label" htmlFor="login-email">
                  Email
                </label>
                <input
                  className="form-input"
                  id="login-email"
                  type="email"
                  placeholder="admin@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
                <label className="form-label" htmlFor="login-password">
                  Password
                </label>
                <input
                  className="form-input"
                  id="login-password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                />
                <button
                  id="login-submit"
                  className="btn btn-primary"
                  type="submit"
                  disabled={loading}
                >
                  Sign In
                </button>
              </form>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
