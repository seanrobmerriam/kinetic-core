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
  { id: "transfer", label: "Transfer Funds", color: "primary" },
  { id: "deposit", label: "Deposit / Withdraw", color: "success" },
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
    <aside className="sidebar">
      <div className="sidebar-brand">
        <h1 className="brand-title">IronLedger</h1>
        <span className="brand-subtitle">Core Banking</span>
      </div>
      <nav className="sidebar-nav">
        {NAV_ITEMS.map((item) => (
          <Link
            key={item.id}
            href={`/${item.id}`}
            className={`nav-item${isActive(item.id) ? " active" : ""}`}
            data-testid={`nav-${item.id}`}
          >
            <MaterialIcon name={item.icon} className="nav-icon" />
            <span className="nav-label">{item.label}</span>
          </Link>
        ))}
      </nav>
      <div className="sidebar-section-title">Quick Actions</div>
      {QUICK_ACTIONS.map((action) => (
        <Link
          key={action.id}
          href={`/${action.id}`}
          className={`quick-action-btn btn btn-${action.color}`}
          data-testid={`quick-${action.id}`}
        >
          {action.label}
        </Link>
      ))}
    </aside>
  );
}
