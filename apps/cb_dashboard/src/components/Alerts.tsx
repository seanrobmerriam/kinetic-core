"use client";

import { useNotify } from "@/lib/notify";

export function Alerts() {
  const { error, success } = useNotify();
  return (
    <>
      {error && (
        <div className="alert alert-error" data-testid="error-banner">
          {error}
        </div>
      )}
      {success && (
        <div className="alert alert-success" data-testid="success-banner">
          {success}
        </div>
      )}
    </>
  );
}

export function Loading({ label = "Loading..." }: { label?: string }) {
  return (
    <div className="loading-spinner" data-testid="loading">
      {label}
    </div>
  );
}
