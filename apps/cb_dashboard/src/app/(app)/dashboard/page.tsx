"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { formatAmount, formatNumber, formatTimestamp } from "@/lib/format";
import { MaterialIcon } from "@/components/MaterialIcon";
import type { Account, LedgerEntry, Party, Transaction } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

type TabKey = "accounts" | "ledger" | "payments";

interface AccountRow extends Account {
  party_name: string;
}

const TABS: { key: TabKey; label: string; icon: string }[] = [
  { key: "accounts", label: "Accounts", icon: "account_balance" },
  { key: "ledger", label: "Ledger", icon: "book" },
  { key: "payments", label: "Payments", icon: "swap_horiz" },
];

interface CommonStats {
  totalDeposits: number;
  activeAccounts: number;
  openedToday: number;
  totalParties: number;
  totalTransactions: number;
  totalLedgerEntries: number;
  pendingPayments: number;
  totalPaymentVolume: number;
}

interface KpiProps {
  label: string;
  value: string;
  hint?: string;
  icon: string;
  tone: "indigo" | "emerald" | "amber" | "violet";
}

const TONE_STYLES: Record<KpiProps["tone"], { bubble: string; ring: string }> = {
  indigo: { bubble: "bg-indigo-50 text-indigo-600", ring: "ring-indigo-100" },
  emerald: { bubble: "bg-emerald-50 text-emerald-600", ring: "ring-emerald-100" },
  amber: { bubble: "bg-amber-50 text-amber-600", ring: "ring-amber-100" },
  violet: { bubble: "bg-violet-50 text-violet-600", ring: "ring-violet-100" },
};

function Kpi({ label, value, hint, icon, tone }: KpiProps) {
  const t = TONE_STYLES[tone];
  return (
    <div className="group relative rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition-shadow hover:shadow-md">
      <div className="flex items-start justify-between">
        <div>
          <div className="text-[11px] font-semibold uppercase tracking-[0.08em] text-slate-500">
            {label}
          </div>
          <div className="mt-2 text-2xl font-semibold tracking-tight text-slate-900">
            {value}
          </div>
          {hint ? <div className="mt-1 text-xs text-slate-500">{hint}</div> : null}
        </div>
        <div
          className={`flex h-11 w-11 items-center justify-center rounded-2xl ring-4 ${t.bubble} ${t.ring}`}
        >
          <MaterialIcon name={icon} className="text-[22px]" />
        </div>
      </div>
    </div>
  );
}

function StatusPill({ status }: { status: string }) {
  const s = status?.toLowerCase() ?? "";
  let cls = "bg-slate-100 text-slate-600";
  let label = status || "—";
  if (s === "active" || s === "posted" || s === "open") {
    cls = "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200/60";
    if (s === "active" || s === "open") label = "Active";
    else label = "Posted";
  } else if (s === "pending") {
    cls = "bg-amber-50 text-amber-700 ring-1 ring-amber-200/60";
    label = "Pending";
  } else if (s === "suspended" || s === "frozen" || s === "reversed" || s === "failed") {
    cls = "bg-rose-50 text-rose-700 ring-1 ring-rose-200/60";
  } else if (s === "closed") {
    cls = "bg-slate-100 text-slate-500";
  }
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-[11px] font-semibold ${cls}`}
    >
      {label}
    </span>
  );
}

function shortId(prefix: string, id: string): string {
  if (!id) return "—";
  const compact = id.replace(/-/g, "");
  const tail = compact.slice(-6).toUpperCase();
  return `${prefix}-${tail}`;
}

function accountTypeCode(name: string, currency: string): string {
  const n = (name || "").toLowerCase();
  if (n.includes("savings")) return "SAV";
  if (n.includes("escrow")) return "ESC";
  if (n.includes("trust")) return "TRU";
  if (n.includes("loan")) return "LOA";
  if (n.includes("operating") || n.includes("ops")) return "OPS";
  if (n.includes("checking") || n.includes("dda")) return "DDA";
  return (currency || "GEN").toUpperCase().slice(0, 3);
}

function EmptyRow({ colSpan, label }: { colSpan: number; label: string }) {
  return (
    <tr>
      <td colSpan={colSpan} className="py-12 text-center text-sm text-slate-400">
        {label}
      </td>
    </tr>
  );
}

export default function DashboardPage() {
  const { setError } = useNotify();
  const { tick } = useRefresh();
  const [tab, setTab] = useState<TabKey>("accounts");

  const [parties, setParties] = useState<Party[]>([]);
  const [accounts, setAccounts] = useState<AccountRow[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [ledger, setLedger] = useState<LedgerEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const partyList = partyResp.items ?? [];

        const accountRows: AccountRow[] = [];
        const txns: Transaction[] = [];
        const seenTxns = new Set<string>();
        const ledgerEntries: LedgerEntry[] = [];

        for (const party of partyList) {
          try {
            const accResp = await api<ListResponse<Account>>(
              "GET",
              `/parties/${party.party_id}/accounts`,
            );
            for (const a of accResp.items ?? []) {
              accountRows.push({ ...a, party_name: party.full_name });
            }
          } catch {
            /* skip */
          }
        }

        for (const acc of accountRows.slice(0, 50)) {
          try {
            const txResp = await api<ListResponse<Transaction>>(
              "GET",
              `/accounts/${acc.account_id}/transactions`,
            );
            for (const t of txResp.items ?? []) {
              if (!seenTxns.has(t.txn_id)) {
                seenTxns.add(t.txn_id);
                txns.push(t);
              }
            }
          } catch {
            /* skip */
          }
        }

        for (const acc of accountRows.slice(0, 25)) {
          try {
            const lResp = await api<ListResponse<LedgerEntry>>(
              "GET",
              `/accounts/${acc.account_id}/entries`,
            );
            for (const e of lResp.items ?? []) {
              ledgerEntries.push(e);
            }
          } catch {
            /* skip */
          }
        }

        if (cancelled) return;
        setParties(partyList);
        setAccounts(accountRows);
        setTransactions(
          txns.sort((a, b) => (b.created_at ?? 0) - (a.created_at ?? 0)),
        );
        setLedger(
          ledgerEntries.sort((a, b) => (b.posted_at ?? 0) - (a.posted_at ?? 0)),
        );
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

  const stats = useMemo<CommonStats>(() => {
    const totalDeposits = accounts.reduce((sum, a) => sum + (a.balance ?? 0), 0);
    const activeAccounts = accounts.filter(
      (a) => (a.status ?? "").toLowerCase() === "active",
    ).length;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayMs = today.getTime();
    const openedToday = accounts.filter(
      (a) => (a.created_at ?? 0) * 1000 >= todayMs,
    ).length;
    const pendingPayments = transactions.filter(
      (t) => (t.status ?? "").toLowerCase() === "pending",
    ).length;
    const totalPaymentVolume = transactions
      .filter((t) => (t.status ?? "").toLowerCase() === "posted")
      .reduce((s, t) => s + (t.amount ?? 0), 0);
    return {
      totalDeposits,
      activeAccounts,
      openedToday,
      totalParties: parties.length,
      totalTransactions: transactions.length,
      totalLedgerEntries: ledger.length,
      pendingPayments,
      totalPaymentVolume,
    };
  }, [accounts, parties, transactions, ledger]);

  return (
    <div className="space-y-8">
      {/* KPI row */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Kpi
          label="Total Deposits"
          value={formatAmount(stats.totalDeposits, "USD")}
          hint={`Across ${formatNumber(stats.activeAccounts)} active accounts`}
          icon="account_balance_wallet"
          tone="indigo"
        />
        <Kpi
          label="Customers"
          value={formatNumber(stats.totalParties)}
          hint={`${formatNumber(stats.openedToday)} opened today`}
          icon="group"
          tone="violet"
        />
        <Kpi
          label="Payments Volume"
          value={formatAmount(stats.totalPaymentVolume, "USD")}
          hint={`${formatNumber(stats.totalTransactions)} payments total`}
          icon="payments"
          tone="emerald"
        />
        <Kpi
          label="Pending Approvals"
          value={formatNumber(stats.pendingPayments)}
          hint="Payments awaiting action"
          icon="pending_actions"
          tone="amber"
        />
      </div>

      {/* Activity card with segmented tabs */}
      <div className="rounded-2xl border border-slate-200 bg-white shadow-sm">
        <div className="flex flex-col gap-4 border-b border-slate-100 px-6 py-5 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h3 className="text-base font-semibold tracking-tight text-slate-900">
              Recent Activity
            </h3>
            <p className="text-sm text-slate-500">
              Latest movement across your portfolio
            </p>
          </div>

          <div
            role="tablist"
            aria-label="Dashboard sections"
            className="inline-flex rounded-xl border border-slate-200 bg-slate-50 p-1"
          >
            {TABS.map((t) => {
              const active = t.key === tab;
              return (
                <button
                  key={t.key}
                  type="button"
                  role="tab"
                  aria-selected={active}
                  data-testid={`dashboard-tab-${t.key}`}
                  onClick={() => setTab(t.key)}
                  className={`inline-flex items-center gap-2 rounded-lg px-3.5 py-1.5 text-sm font-medium transition-all ${
                    active
                      ? "bg-white text-slate-900 shadow-sm ring-1 ring-slate-200/80"
                      : "text-slate-500 hover:text-slate-800"
                  }`}
                >
                  <MaterialIcon name={t.icon} className="text-[18px]" />
                  {t.label}
                </button>
              );
            })}
          </div>
        </div>

        <div className="px-2 pb-2 sm:px-4 sm:pb-4">
          {tab === "accounts" ? (
            <AccountsTab loading={loading} accounts={accounts} />
          ) : tab === "ledger" ? (
            <LedgerTab loading={loading} ledger={ledger} accounts={accounts} />
          ) : (
            <PaymentsTab loading={loading} transactions={transactions} accounts={accounts} />
          )}
        </div>
      </div>
    </div>
  );
}

function TableHead({ children }: { children: React.ReactNode }) {
  return (
    <thead>
      <tr className="text-left text-[11px] font-semibold uppercase tracking-[0.08em] text-slate-500">
        {children}
      </tr>
    </thead>
  );
}

function AccountsTab({
  loading,
  accounts,
}: {
  loading: boolean;
  accounts: AccountRow[];
}) {
  const top = accounts.slice(0, 8);
  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <TableHead>
          <th className="px-4 pb-3 pt-4 font-semibold">Account</th>
          <th className="px-4 pb-3 pt-4 font-semibold">Customer</th>
          <th className="px-4 pb-3 pt-4 font-semibold">Type</th>
          <th className="px-4 pb-3 pt-4 text-right font-semibold">Balance</th>
          <th className="px-4 pb-3 pt-4 text-right font-semibold">Status</th>
        </TableHead>
        <tbody>
          {loading && accounts.length === 0 ? (
            <EmptyRow colSpan={5} label="Loading accounts…" />
          ) : top.length === 0 ? (
            <EmptyRow colSpan={5} label="No accounts yet" />
          ) : (
            top.map((a) => (
              <tr
                key={a.account_id}
                className="border-t border-slate-100 transition-colors hover:bg-slate-50/60"
              >
                <td className="px-4 py-3.5">
                  <Link
                    href={`/accounts/${a.account_id}`}
                    className="flex flex-col leading-tight"
                  >
                    <span className="font-medium text-slate-900">{a.name}</span>
                    <span className="font-mono text-[11px] text-slate-400">
                      {shortId("ACC", a.account_id)}
                    </span>
                  </Link>
                </td>
                <td className="px-4 py-3.5 text-slate-600">{a.party_name}</td>
                <td className="px-4 py-3.5">
                  <span className="inline-flex rounded-md bg-slate-100 px-2 py-0.5 text-[11px] font-semibold text-slate-600">
                    {accountTypeCode(a.name, a.currency)}
                  </span>
                </td>
                <td className="px-4 py-3.5 text-right font-mono font-medium text-slate-900">
                  {formatAmount(a.balance, a.currency)}
                </td>
                <td className="px-4 py-3.5 text-right">
                  <StatusPill status={a.status} />
                </td>
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}

function LedgerTab({
  loading,
  ledger,
  accounts,
}: {
  loading: boolean;
  ledger: LedgerEntry[];
  accounts: AccountRow[];
}) {
  const accountById = new Map(accounts.map((a) => [a.account_id, a] as const));
  const top = ledger.slice(0, 10);

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <TableHead>
          <th className="px-4 pb-3 pt-4 font-semibold">Entry</th>
          <th className="px-4 pb-3 pt-4 font-semibold">Account</th>
          <th className="px-4 pb-3 pt-4 font-semibold">Type</th>
          <th className="px-4 pb-3 pt-4 text-right font-semibold">Amount</th>
          <th className="px-4 pb-3 pt-4 text-right font-semibold">Posted</th>
        </TableHead>
        <tbody>
          {loading && ledger.length === 0 ? (
            <EmptyRow colSpan={5} label="Loading ledger…" />
          ) : top.length === 0 ? (
            <EmptyRow colSpan={5} label="No ledger entries yet" />
          ) : (
            top.map((e) => {
              const acc = accountById.get(e.account_id);
              const isDebit = e.entry_type === "debit";
              return (
                <tr
                  key={e.entry_id}
                  className="border-t border-slate-100 transition-colors hover:bg-slate-50/60"
                >
                  <td className="px-4 py-3.5 font-mono text-[12px] text-slate-600">
                    {shortId("ENT", e.entry_id)}
                  </td>
                  <td className="px-4 py-3.5 text-slate-700">
                    {acc?.name ?? shortId("ACC", e.account_id)}
                  </td>
                  <td className="px-4 py-3.5">
                    <span
                      className={`inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[11px] font-semibold ${
                        isDebit
                          ? "bg-rose-50 text-rose-700 ring-1 ring-rose-200/60"
                          : "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200/60"
                      }`}
                    >
                      <MaterialIcon
                        name={isDebit ? "arrow_downward" : "arrow_upward"}
                        className="text-[12px]"
                      />
                      {(e.entry_type || "").toUpperCase()}
                    </span>
                  </td>
                  <td
                    className={`px-4 py-3.5 text-right font-mono font-medium ${
                      isDebit ? "text-rose-600" : "text-emerald-600"
                    }`}
                  >
                    {isDebit ? "-" : "+"}
                    {formatAmount(e.amount, e.currency)}
                  </td>
                  <td className="px-4 py-3.5 text-right text-slate-500">
                    {formatTimestamp(e.posted_at)}
                  </td>
                </tr>
              );
            })
          )}
        </tbody>
      </table>
    </div>
  );
}

function PaymentsTab({
  loading,
  transactions,
  accounts,
}: {
  loading: boolean;
  transactions: Transaction[];
  accounts: AccountRow[];
}) {
  const accountById = new Map(accounts.map((a) => [a.account_id, a] as const));
  const top = transactions.slice(0, 10);

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <TableHead>
          <th className="px-4 pb-3 pt-4 font-semibold">Transaction</th>
          <th className="px-4 pb-3 pt-4 font-semibold">Type</th>
          <th className="px-4 pb-3 pt-4 font-semibold">From → To</th>
          <th className="px-4 pb-3 pt-4 text-right font-semibold">Amount</th>
          <th className="px-4 pb-3 pt-4 text-right font-semibold">Status</th>
        </TableHead>
        <tbody>
          {loading && transactions.length === 0 ? (
            <EmptyRow colSpan={5} label="Loading payments…" />
          ) : top.length === 0 ? (
            <EmptyRow colSpan={5} label="No payments yet" />
          ) : (
            top.map((t) => {
              const src = accountById.get(t.source_account_id);
              const dst = accountById.get(t.dest_account_id);
              return (
                <tr
                  key={t.txn_id}
                  className="border-t border-slate-100 transition-colors hover:bg-slate-50/60"
                >
                  <td className="px-4 py-3.5 font-mono text-[12px] text-slate-600">
                    {shortId("TXN", t.txn_id)}
                  </td>
                  <td className="px-4 py-3.5">
                    <span className="inline-flex rounded-md bg-slate-100 px-2 py-0.5 text-[11px] font-semibold uppercase text-slate-600">
                      {t.txn_type}
                    </span>
                  </td>
                  <td className="px-4 py-3.5 text-slate-700">
                    <span className="text-slate-900">
                      {src?.name ??
                        (t.source_account_id ? shortId("ACC", t.source_account_id) : "—")}
                    </span>
                    <MaterialIcon
                      name="arrow_right_alt"
                      className="mx-1 align-middle text-[16px] text-slate-400"
                    />
                    <span className="text-slate-900">
                      {dst?.name ??
                        (t.dest_account_id ? shortId("ACC", t.dest_account_id) : "—")}
                    </span>
                  </td>
                  <td className="px-4 py-3.5 text-right font-mono font-medium text-slate-900">
                    {formatAmount(t.amount, t.currency)}
                  </td>
                  <td className="px-4 py-3.5 text-right">
                    <StatusPill status={t.status} />
                  </td>
                </tr>
              );
            })
          )}
        </tbody>
      </table>
    </div>
  );
}
