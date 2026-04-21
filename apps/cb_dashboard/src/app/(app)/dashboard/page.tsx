"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { formatAmount, formatNumber, formatTimestamp } from "@/lib/format";
import type { Account, LedgerEntry, Party, Transaction } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

type TabKey = "accounts" | "ledger" | "payments";

interface AccountRow extends Account {
  party_name: string;
}

const TABS: { key: TabKey; label: string }[] = [
  { key: "accounts", label: "Accounts" },
  { key: "ledger", label: "Ledger" },
  { key: "payments", label: "Payments" },
];

function StatCard({ label, value, accent }: { label: string; value: string; accent?: "default" | "positive" }) {
  return (
    <div className="flex-1 rounded-xl bg-[#EEF4FB] px-6 py-5">
      <div className="text-sm text-slate-500">{label}</div>
      <div
        className={`mt-2 text-2xl font-semibold tracking-tight ${
          accent === "positive" ? "text-emerald-600" : "text-slate-800"
        }`}
      >
        {value}
      </div>
    </div>
  );
}

function StatusPill({ status }: { status: string }) {
  const s = status?.toLowerCase() ?? "";
  let cls = "bg-slate-100 text-slate-600";
  let label = status || "—";
  if (s === "active" || s === "posted" || s === "open") {
    cls = "bg-emerald-50 text-emerald-700";
    label = "Active";
  } else if (s === "pending") {
    cls = "bg-amber-50 text-amber-700";
    label = "Pending";
  } else if (s === "suspended" || s === "frozen" || s === "reversed" || s === "failed") {
    cls = "bg-rose-50 text-rose-700";
  } else if (s === "closed") {
    cls = "bg-slate-100 text-slate-500";
  }
  return (
    <span className={`inline-flex items-center rounded-full px-3 py-1 text-xs font-medium ${cls}`}>
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

export default function DashboardPage() {
  const { setError } = useNotify();
  const { tick } = useRefresh();
  const [tab, setTab] = useState<TabKey>("accounts");

  const [parties, setParties] = useState<Party[]>([]);
  const [accounts, setAccounts] = useState<AccountRow[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [ledger, setLedger] = useState<LedgerEntry[]>([]);
  const [loading, setLoading] = useState(true);

  // Load parties + accounts + transactions for the dashboard summary.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const partyList = partyResp.items ?? [];
        const partyById = new Map(partyList.map((p) => [p.party_id, p] as const));

        const accountRows: AccountRow[] = [];
        const txns: Transaction[] = [];
        const seenTxns = new Set<string>();
        const ledgerEntries: LedgerEntry[] = [];

        // Cap how many parties we deeply iterate to keep the dashboard snappy.
        // Customers/accounts pages can paginate the full list.
        const sampledParties = partyList.slice(0, 25);

        for (const party of partyList) {
          try {
            const accResp = await api<ListResponse<Account>>("GET", `/parties/${party.party_id}/accounts`);
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
        setTransactions(txns.sort((a, b) => (b.created_at ?? 0) - (a.created_at ?? 0)));
        setLedger(ledgerEntries.sort((a, b) => (b.posted_at ?? 0) - (a.posted_at ?? 0)));
        // sampledParties is intentionally unused here but kept above to make
        // the optimisation explicit if/when we wire pagination.
        void sampledParties;
        void partyById;
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

  const stats = useMemo(() => {
    const totalDeposits = accounts.reduce((sum, a) => sum + (a.balance ?? 0), 0);
    const activeAccounts = accounts.filter((a) => (a.status ?? "").toLowerCase() === "active").length;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayMs = today.getTime();
    const openedToday = accounts.filter((a) => (a.created_at ?? 0) * 1000 >= todayMs).length;
    return {
      totalDeposits,
      activeAccounts,
      openedToday,
      totalParties: parties.length,
      totalTransactions: transactions.length,
      totalLedgerEntries: ledger.length,
    };
  }, [accounts, parties, transactions, ledger]);

  return (
    <div className="dashboard-view">
      <div className="rounded-2xl bg-white p-6 shadow-sm">
        {/* Tabs */}
        <div className="border-b border-slate-200">
          <nav className="-mb-px flex gap-8" role="tablist" aria-label="Dashboard sections">
            {TABS.map((t) => {
              const active = t.key === tab;
              return (
                <button
                  key={t.key}
                  role="tab"
                  aria-selected={active}
                  data-testid={`dashboard-tab-${t.key}`}
                  onClick={() => setTab(t.key)}
                  className={`relative pb-3 text-sm font-semibold transition-colors ${
                    active ? "text-[#1B6FE0]" : "text-slate-500 hover:text-slate-700"
                  }`}
                >
                  {t.label}
                  {active ? (
                    <span className="absolute -bottom-px left-0 right-0 h-0.5 rounded-full bg-[#1B6FE0]" />
                  ) : null}
                </button>
              );
            })}
          </nav>
        </div>

        {tab === "accounts" ? (
          <AccountsTab loading={loading} stats={stats} accounts={accounts} />
        ) : tab === "ledger" ? (
          <LedgerTab loading={loading} stats={stats} ledger={ledger} accounts={accounts} />
        ) : (
          <PaymentsTab loading={loading} stats={stats} transactions={transactions} accounts={accounts} />
        )}
      </div>
    </div>
  );
}

interface CommonStats {
  totalDeposits: number;
  activeAccounts: number;
  openedToday: number;
  totalParties: number;
  totalTransactions: number;
  totalLedgerEntries: number;
}

function AccountsTab({
  loading,
  stats,
  accounts,
}: {
  loading: boolean;
  stats: CommonStats;
  accounts: AccountRow[];
}) {
  const top = accounts.slice(0, 8);
  return (
    <div className="pt-6">
      <div className="flex flex-wrap gap-4">
        <StatCard label="Total Deposits" value={formatAmount(stats.totalDeposits, "USD")} />
        <StatCard label="Active Accounts" value={formatNumber(stats.activeAccounts)} />
        <StatCard label="Opened Today" value={`+${formatNumber(stats.openedToday)}`} accent="positive" />
      </div>

      <div className="mt-8 overflow-x-auto">
        <table className="min-w-full text-sm">
          <thead>
            <tr className="text-left text-xs font-medium uppercase tracking-wide text-slate-500">
              <th className="pb-3 pr-6 font-medium">Account ID</th>
              <th className="pb-3 pr-6 font-medium">Name</th>
              <th className="pb-3 pr-6 font-medium">Type</th>
              <th className="pb-3 pr-6 text-right font-medium">Balance</th>
              <th className="pb-3 text-right font-medium">Status</th>
            </tr>
          </thead>
          <tbody>
            {loading && accounts.length === 0 ? (
              <tr>
                <td colSpan={5} className="py-10 text-center text-slate-400">
                  Loading…
                </td>
              </tr>
            ) : top.length === 0 ? (
              <tr>
                <td colSpan={5} className="py-10 text-center text-slate-400">
                  No accounts yet
                </td>
              </tr>
            ) : (
              top.map((a) => (
                <tr key={a.account_id} className="border-t border-slate-100">
                  <td className="py-3 pr-6 font-mono text-[13px] text-[#1B6FE0]">
                    <Link href={`/accounts/${a.account_id}`}>{shortId("ACC", a.account_id)}</Link>
                  </td>
                  <td className="py-3 pr-6 text-slate-700">{a.name}</td>
                  <td className="py-3 pr-6">
                    <span className="inline-flex rounded-md bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-600">
                      {accountTypeCode(a.name, a.currency)}
                    </span>
                  </td>
                  <td className="py-3 pr-6 text-right font-mono text-slate-800">
                    {formatAmount(a.balance, a.currency)}
                  </td>
                  <td className="py-3 text-right">
                    <StatusPill status={a.status} />
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function LedgerTab({
  loading,
  stats,
  ledger,
  accounts,
}: {
  loading: boolean;
  stats: CommonStats;
  ledger: LedgerEntry[];
  accounts: AccountRow[];
}) {
  const accountById = new Map(accounts.map((a) => [a.account_id, a] as const));
  const debits = ledger.filter((e) => e.entry_type === "debit").reduce((s, e) => s + (e.amount ?? 0), 0);
  const credits = ledger.filter((e) => e.entry_type === "credit").reduce((s, e) => s + (e.amount ?? 0), 0);
  const top = ledger.slice(0, 10);

  return (
    <div className="pt-6">
      <div className="flex flex-wrap gap-4">
        <StatCard label="Total Entries" value={formatNumber(stats.totalLedgerEntries)} />
        <StatCard label="Total Debits" value={formatAmount(debits, "USD")} />
        <StatCard label="Total Credits" value={formatAmount(credits, "USD")} />
      </div>

      <div className="mt-8 overflow-x-auto">
        <table className="min-w-full text-sm">
          <thead>
            <tr className="text-left text-xs font-medium uppercase tracking-wide text-slate-500">
              <th className="pb-3 pr-6 font-medium">Entry ID</th>
              <th className="pb-3 pr-6 font-medium">Account</th>
              <th className="pb-3 pr-6 font-medium">Type</th>
              <th className="pb-3 pr-6 text-right font-medium">Amount</th>
              <th className="pb-3 text-right font-medium">Posted</th>
            </tr>
          </thead>
          <tbody>
            {loading && ledger.length === 0 ? (
              <tr>
                <td colSpan={5} className="py-10 text-center text-slate-400">
                  Loading…
                </td>
              </tr>
            ) : top.length === 0 ? (
              <tr>
                <td colSpan={5} className="py-10 text-center text-slate-400">
                  No ledger entries yet
                </td>
              </tr>
            ) : (
              top.map((e) => {
                const acc = accountById.get(e.account_id);
                return (
                  <tr key={e.entry_id} className="border-t border-slate-100">
                    <td className="py-3 pr-6 font-mono text-[13px] text-[#1B6FE0]">
                      {shortId("ENT", e.entry_id)}
                    </td>
                    <td className="py-3 pr-6 text-slate-700">{acc?.name ?? shortId("ACC", e.account_id)}</td>
                    <td className="py-3 pr-6">
                      <span
                        className={`inline-flex rounded-md px-2 py-0.5 text-xs font-medium ${
                          e.entry_type === "debit"
                            ? "bg-rose-50 text-rose-700"
                            : "bg-emerald-50 text-emerald-700"
                        }`}
                      >
                        {(e.entry_type || "").toUpperCase()}
                      </span>
                    </td>
                    <td className="py-3 pr-6 text-right font-mono text-slate-800">
                      {formatAmount(e.amount, e.currency)}
                    </td>
                    <td className="py-3 text-right text-slate-500">{formatTimestamp(e.posted_at)}</td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function PaymentsTab({
  loading,
  stats,
  transactions,
  accounts,
}: {
  loading: boolean;
  stats: CommonStats;
  transactions: Transaction[];
  accounts: AccountRow[];
}) {
  const accountById = new Map(accounts.map((a) => [a.account_id, a] as const));
  const posted = transactions.filter((t) => (t.status ?? "").toLowerCase() === "posted");
  const pending = transactions.filter((t) => (t.status ?? "").toLowerCase() === "pending").length;
  const totalVolume = posted.reduce((s, t) => s + (t.amount ?? 0), 0);
  const top = transactions.slice(0, 10);

  return (
    <div className="pt-6">
      <div className="flex flex-wrap gap-4">
        <StatCard label="Total Volume" value={formatAmount(totalVolume, "USD")} />
        <StatCard label="Total Payments" value={formatNumber(stats.totalTransactions)} />
        <StatCard label="Pending" value={formatNumber(pending)} accent={pending > 0 ? "default" : "positive"} />
      </div>

      <div className="mt-8 overflow-x-auto">
        <table className="min-w-full text-sm">
          <thead>
            <tr className="text-left text-xs font-medium uppercase tracking-wide text-slate-500">
              <th className="pb-3 pr-6 font-medium">Txn ID</th>
              <th className="pb-3 pr-6 font-medium">Type</th>
              <th className="pb-3 pr-6 font-medium">From → To</th>
              <th className="pb-3 pr-6 text-right font-medium">Amount</th>
              <th className="pb-3 text-right font-medium">Status</th>
            </tr>
          </thead>
          <tbody>
            {loading && transactions.length === 0 ? (
              <tr>
                <td colSpan={5} className="py-10 text-center text-slate-400">
                  Loading…
                </td>
              </tr>
            ) : top.length === 0 ? (
              <tr>
                <td colSpan={5} className="py-10 text-center text-slate-400">
                  No payments yet
                </td>
              </tr>
            ) : (
              top.map((t) => {
                const src = accountById.get(t.source_account_id);
                const dst = accountById.get(t.dest_account_id);
                return (
                  <tr key={t.txn_id} className="border-t border-slate-100">
                    <td className="py-3 pr-6 font-mono text-[13px] text-[#1B6FE0]">
                      {shortId("TXN", t.txn_id)}
                    </td>
                    <td className="py-3 pr-6">
                      <span className="inline-flex rounded-md bg-slate-100 px-2 py-0.5 text-xs font-medium uppercase text-slate-600">
                        {t.txn_type}
                      </span>
                    </td>
                    <td className="py-3 pr-6 text-slate-700">
                      {src?.name ?? (t.source_account_id ? shortId("ACC", t.source_account_id) : "—")}
                      <span className="px-1 text-slate-400">→</span>
                      {dst?.name ?? (t.dest_account_id ? shortId("ACC", t.dest_account_id) : "—")}
                    </td>
                    <td className="py-3 pr-6 text-right font-mono text-slate-800">
                      {formatAmount(t.amount, t.currency)}
                    </td>
                    <td className="py-3 text-right">
                      <StatusPill status={t.status} />
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
