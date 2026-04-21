"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { MaterialIcon } from "./MaterialIcon";

const NAV_ITEMS = [
  { id: "dashboard", label: "Dashboard", icon: "dashboard" },
  { id: "customers", label: "Customers", icon: "group" },
  { id: "accounts", label: "Accounts", icon: "account_balance" },
  { id: "transactions", label: "Transactions", icon: "swap_horiz" },
  { id: "ledger", label: "Ledger", icon: "book" },
  { id: "products", label: "Products", icon: "inventory_2" },
  { id: "loans", label: "Loans", icon: "request_quote" },
  { id: "settings", label: "Settings", icon: "settings" },
] as const;

const QUICK_ACTIONS = [
  { id: "transfer", label: "Transfer Funds", icon: "swap_horiz" },
  { id: "deposit", label: "Deposit / Withdraw", icon: "payments" },
] as const;

export function Sidebar() {
  const pathname = usePathname() ?? "";

  const isActive = (id: string) => {
    if (id === "accounts") {
      return pathname.startsWith("/accounts");
    }
    return pathname === `/${id}`;
  };

  return (
    <aside className="sidebar fixed inset-y-0 left-0 z-30 flex w-64 flex-col bg-slate-900 text-slate-300">
      <div className="flex items-center gap-3 px-6 pt-7 pb-6">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-indigo-500 to-violet-500 text-white shadow-md">
          <MaterialIcon name="account_balance" className="text-[22px]" />
        </div>
        <div className="leading-tight">
          <div className="text-base font-semibold text-white tracking-tight">IronLedger</div>
          <div className="text-[11px] font-medium uppercase tracking-wider text-slate-500">
            Core Banking
          </div>
        </div>
      </div>

      <div className="px-6 pb-2 text-[10px] font-semibold uppercase tracking-[0.12em] text-slate-500">
        Menu
      </div>
      <nav className="flex flex-1 flex-col gap-1 px-3">
        {NAV_ITEMS.map((item) => {
          const active = isActive(item.id);
          return (
            <Link
              key={item.id}
              href={`/${item.id}`}
              data-testid={`nav-${item.id}`}
              className={`group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-colors ${
                active
                  ? "bg-gradient-to-r from-indigo-500/90 to-violet-500/90 text-white shadow-sm"
                  : "text-slate-400 hover:bg-slate-800/70 hover:text-white"
              }`}
            >
              <MaterialIcon
                name={item.icon}
                className={`text-[20px] ${active ? "text-white" : "text-slate-500 group-hover:text-white"}`}
              />
              <span>{item.label}</span>
            </Link>
          );
        })}
      </nav>

      <div className="px-6 pt-4 pb-2 text-[10px] font-semibold uppercase tracking-[0.12em] text-slate-500">
        Quick Actions
      </div>
      <div className="flex flex-col gap-2 px-3 pb-6">
        {QUICK_ACTIONS.map((a) => (
          <Link
            key={a.id}
            href={`/${a.id}`}
            data-testid={`quick-${a.id}`}
            className="flex items-center gap-3 rounded-xl border border-slate-700/60 bg-slate-800/40 px-3 py-2.5 text-sm font-medium text-slate-200 transition-colors hover:border-indigo-400/40 hover:bg-slate-800 hover:text-white"
          >
            <MaterialIcon name={a.icon} className="text-[18px] text-indigo-300" />
            <span>{a.label}</span>
          </Link>
        ))}
      </div>
    </aside>
  );
}
