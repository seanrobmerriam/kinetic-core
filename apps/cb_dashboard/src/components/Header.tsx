"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useAuth } from "@/lib/auth";
import { useNotify } from "@/lib/notify";
import { useTheme } from "@/lib/theme";
import { api } from "@/lib/api";
import { capitalize } from "@/lib/format";
import { MaterialIcon } from "./MaterialIcon";

const PAGE_TITLES: Record<string, string> = {
  dashboard: "Dashboard",
  customers: "Customers",
  accounts: "Accounts",
  "account-detail": "Account Details",
  transactions: "Transactions",
  ledger: "Ledger",
  products: "Products",
  loans: "Loans",
  settings: "Settings",
  transfer: "Transfer Funds",
  deposit: "Deposit / Withdraw",
};

const PAGE_SUBTITLES: Record<string, string> = {
  dashboard: "Operational overview",
  customers: "Manage parties and onboarding",
  accounts: "Customer accounts and balances",
  "account-detail": "Account activity and holds",
  transactions: "Payments across all accounts",
  ledger: "Posted ledger entries",
  products: "Savings and loan products",
  loans: "Loan origination and servicing",
  settings: "Workspace preferences",
  transfer: "Move money between accounts",
  deposit: "Cash in and out",
};

function pageKey(pathname: string): string {
  if (pathname.startsWith("/accounts/") && pathname.length > "/accounts/".length) {
    return "account-detail";
  }
  return pathname.split("/")[1] || "dashboard";
}

interface IconButtonProps {
  icon: string;
  title: string;
  onClick?: () => void;
  disabled?: boolean;
  testId?: string;
}

function IconButton({ icon, title, onClick, disabled, testId }: IconButtonProps) {
  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      onClick={onClick}
      disabled={disabled}
      data-testid={testId}
      className="inline-flex h-10 w-10 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-600 transition-colors hover:border-slate-300 hover:bg-slate-50 hover:text-slate-900 disabled:cursor-not-allowed disabled:opacity-50"
    >
      <MaterialIcon name={icon} className="text-[20px]" />
    </button>
  );
}

export function Header({ onRefresh }: { onRefresh?: () => void }) {
  const pathname = usePathname() ?? "/";
  const router = useRouter();
  const { state, logout, devToolsEnabled, setDevToolsEnabled } = useAuth();
  const { theme, toggle } = useTheme();
  const { setError, setSuccess } = useNotify();
  const [mockImporting, setMockImporting] = useState(false);

  useEffect(() => {
    if (state.status !== "authenticated") return;
    let cancelled = false;
    (async () => {
      try {
        const result = await api<{ enabled: boolean }>("GET", "/dev/mock-import");
        if (!cancelled) setDevToolsEnabled(Boolean(result?.enabled));
      } catch {
        if (!cancelled) setDevToolsEnabled(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [state.status, setDevToolsEnabled]);

  const importMock = async () => {
    if (mockImporting || !devToolsEnabled) return;
    setMockImporting(true);
    try {
      const resp = await api<{ summary: Record<string, number> }>(
        "POST",
        "/dev/mock-import",
        {},
      );
      const created = resp?.summary?.transactions_created ?? 0;
      const existing = resp?.summary?.transactions_existing ?? 0;
      setSuccess(
        `Mock data imported (transactions created: ${created}, existing: ${existing})`,
      );
      onRefresh?.();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setMockImporting(false);
    }
  };

  const refresh = () => {
    if (onRefresh) {
      onRefresh();
    } else {
      router.refresh();
    }
  };

  const key = pageKey(pathname);
  const title = PAGE_TITLES[key] ?? "Dashboard";
  const subtitle = PAGE_SUBTITLES[key] ?? "";
  const userInitial = state.status === "authenticated" && state.user
    ? state.user.email.charAt(0).toUpperCase()
    : "?";

  return (
    <header className="sticky top-0 z-20 flex h-20 items-center gap-4 border-b border-slate-200 bg-white/80 px-8 backdrop-blur">
      <div className="flex flex-col">
        <h2 className="text-xl font-semibold tracking-tight text-slate-900">{title}</h2>
        {subtitle ? <p className="text-sm text-slate-500">{subtitle}</p> : null}
      </div>

      <div className="ml-auto flex items-center gap-2">
        {state.status === "authenticated" && state.user && (
          <div
            data-testid="current-user"
            className="hidden items-center gap-3 rounded-full border border-slate-200 bg-white px-2 py-1.5 pr-4 sm:flex"
          >
            <div className="flex h-7 w-7 items-center justify-center rounded-full bg-gradient-to-br from-indigo-500 to-violet-500 text-xs font-semibold text-white">
              {userInitial}
            </div>
            <div className="leading-tight">
              <div className="text-xs font-semibold text-slate-800">{state.user.email}</div>
              <div className="text-[10px] uppercase tracking-wide text-slate-500">
                {capitalize(state.user.role)}
              </div>
            </div>
          </div>
        )}
        {devToolsEnabled && (
          <IconButton
            icon={mockImporting ? "hourglass_top" : "upload"}
            title="Import mock data"
            testId="mock-import-button"
            onClick={importMock}
            disabled={mockImporting}
          />
        )}
        <IconButton
          icon={theme === "dark" ? "light_mode" : "dark_mode"}
          title="Toggle theme"
          testId="theme-toggle"
          onClick={toggle}
        />
        <IconButton icon="autorenew" title="Refresh" onClick={refresh} />
        <IconButton
          icon="logout"
          title="Sign out"
          testId="logout-button"
          onClick={() => void logout()}
        />
      </div>
    </header>
  );
}
