"use client";

import { useNotify } from "@/lib/notify";
import { MaterialIcon } from "./MaterialIcon";

export function Alerts() {
  const { error, success } = useNotify();
  return (
    <>
      {error && (
        <div
          data-testid="error-banner"
          className="mb-6 flex items-start gap-3 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700"
        >
          <MaterialIcon name="error" className="mt-0.5 text-[20px] text-rose-500" />
          <span>{error}</span>
        </div>
      )}
      {success && (
        <div
          data-testid="success-banner"
          className="mb-6 flex items-start gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700"
        >
          <MaterialIcon name="check_circle" className="mt-0.5 text-[20px] text-emerald-500" />
          <span>{success}</span>
        </div>
      )}
    </>
  );
}

export function Loading({ label = "Loading..." }: { label?: string }) {
  return (
    <div
      data-testid="loading"
      className="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-500"
    >
      <span className="inline-block h-2.5 w-2.5 animate-pulse rounded-full bg-indigo-500" />
      {label}
    </div>
  );
}
