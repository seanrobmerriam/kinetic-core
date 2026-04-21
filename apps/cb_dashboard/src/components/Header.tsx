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

function pageTitle(pathname: string): string {
  if (pathname.startsWith("/accounts/") && pathname.length > "/accounts/".length) {
    return PAGE_TITLES["account-detail"];
  }
  const segment = pathname.split("/")[1] || "dashboard";
  return PAGE_TITLES[segment] ?? "Dashboard";
}

export function Header({ onRefresh }: { onRefresh?: () => void }) {
  const pathname = usePathname() ?? "/";
  const router = useRouter();
  const { state, logout, devToolsEnabled, setDevToolsEnabled } = useAuth();
  const { theme, toggle } = useTheme();
  const { setError, setSuccess } = useNotify();
  const [mockImporting, setMockImporting] = useState(false);

  // Probe dev tools capability once after auth.
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

  return (
    <header className="main-header">
      <div className="header-title">
        <h2 className="page-title">{pageTitle(pathname)}</h2>
      </div>
      <div className="header-actions">
        {state.status === "authenticated" && state.user && (
          <div className="header-btn" data-testid="current-user">
            {state.user.email} ({capitalize(state.user.role)})
          </div>
        )}
        {devToolsEnabled && (
          <button
            type="button"
            className="header-btn"
            title="Import mock data"
            data-testid="mock-import-button"
            onClick={importMock}
            disabled={mockImporting}
          >
            <MaterialIcon
              name={mockImporting ? "hourglass_top" : "upload"}
              className="header-icon"
            />
          </button>
        )}
        <button
          type="button"
          className="header-btn"
          title="Toggle theme"
          data-testid="theme-toggle"
          onClick={toggle}
        >
          <MaterialIcon
            name={theme === "dark" ? "light_mode" : "dark_mode"}
            className="header-icon"
          />
        </button>
        <button type="button" className="header-btn" title="Refresh" onClick={refresh}>
          <MaterialIcon name="autorenew" className="header-icon" />
        </button>
        <button
          type="button"
          className="header-btn"
          title="Sign out"
          data-testid="logout-button"
          onClick={() => void logout()}
        >
          <MaterialIcon name="logout" className="header-icon" />
        </button>
      </div>
    </header>
  );
}
