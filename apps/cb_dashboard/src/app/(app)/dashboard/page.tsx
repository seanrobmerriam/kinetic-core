"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { formatAmount, formatNumber } from "@/lib/format";
import { MaterialIcon } from "@/components/MaterialIcon";
import type { Account, Party } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

interface Stats {
  totalCustomers: number;
  totalAccounts: number;
  totalBalance: number;
  todayTxns: number;
}

const QUICK_ACTIONS = [
  { label: "New Customer", desc: "Add a new customer to the system", icon: "person_add", href: "/customers", color: "primary" },
  { label: "New Account", desc: "Open a new account for a customer", icon: "add_card", href: "/accounts", color: "success" },
  { label: "New Product", desc: "Create savings and loan products", icon: "inventory_2", href: "/products", color: "info" },
  { label: "Manage Loans", desc: "Create, approve, disburse and repay loans", icon: "request_quote", href: "/loans", color: "warning" },
  { label: "Transfer", desc: "Transfer funds between accounts", icon: "swap_horiz", href: "/transfer", color: "info" },
  { label: "View Transactions", desc: "Browse all transactions", icon: "receipt_long", href: "/transactions", color: "warning" },
] as const;

export default function DashboardPage() {
  const { setError } = useNotify();
  const { tick } = useRefresh();
  const [stats, setStats] = useState<Stats>({
    totalCustomers: 0,
    totalAccounts: 0,
    totalBalance: 0,
    todayTxns: 0,
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const parties = partyResp.items ?? [];
        let allAccounts: Account[] = [];
        for (const party of parties) {
          try {
            const accResp = await api<ListResponse<Account>>("GET", `/parties/${party.party_id}/accounts`);
            if (accResp.items) allAccounts = allAccounts.concat(accResp.items);
          } catch {
            /* skip */
          }
        }
        const totalBalance = allAccounts.reduce((sum, a) => sum + (a.balance ?? 0), 0);
        if (!cancelled) {
          setStats({
            totalCustomers: parties.length,
            totalAccounts: allAccounts.length,
            totalBalance,
            todayTxns: 0,
          });
        }
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const cards = [
    { title: "Total Customers", value: formatNumber(stats.totalCustomers), icon: "group", colorClass: "blue" },
    { title: "Total Accounts", value: formatNumber(stats.totalAccounts), icon: "account_balance", colorClass: "green" },
    { title: "Total Balance", value: formatAmount(stats.totalBalance, "USD"), icon: "payments", colorClass: "purple" },
    { title: "Today's Transactions", value: formatNumber(stats.todayTxns), icon: "receipt_long", colorClass: "orange" },
  ];

  return (
    <div className="dashboard-view">
      <div className="summary-cards">
        {cards.map((card) => (
          <div key={card.title} className="summary-card">
            <div className="card-header">
              <div className={`card-icon ${card.colorClass}`}>
                <MaterialIcon name={card.icon} className="icon" />
              </div>
            </div>
            <div className="card-content">
              <div className="card-value">{loading ? "—" : card.value}</div>
              <div className="card-title">{card.title}</div>
            </div>
          </div>
        ))}
      </div>

      <div className="dashboard-two-col">
        <div className="dashboard-card">
          <div className="card-header-row">
            <h3>Recent Activity</h3>
            <Link className="btn btn-link" href="/transactions">
              View All
            </Link>
          </div>
          <div className="activity-list">
            <div className="empty-state">No recent activity</div>
          </div>
        </div>

        <div className="dashboard-card">
          <h3>Quick Actions</h3>
          <div className="quick-actions-grid">
            {QUICK_ACTIONS.map((a) => (
              <Link key={a.label} className="quick-action-card" href={a.href}>
                <div className={`action-icon ${a.color}`}>
                  <MaterialIcon name={a.icon} className="icon" />
                </div>
                <div className="action-label">{a.label}</div>
                <div className="action-desc">{a.desc}</div>
              </Link>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
