"use client";

import { useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatAmount, formatTimestamp, truncateID } from "@/lib/format";
import type { Account, Party, Transaction } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

const STATUSES = ["all", "pending", "posted", "failed"] as const;

export default function TransactionsPage() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState<string>("");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const parties = partyResp.items ?? [];
        let allAccounts: Account[] = [];
        for (const p of parties) {
          try {
            const accResp = await api<ListResponse<Account>>("GET", `/parties/${p.party_id}/accounts`);
            if (accResp.items) allAccounts = allAccounts.concat(accResp.items);
          } catch {
            /* skip */
          }
        }
        const seen = new Set<string>();
        const allTxns: Transaction[] = [];
        for (const acc of allAccounts) {
          try {
            const txResp = await api<ListResponse<Transaction>>("GET", `/accounts/${acc.account_id}/transactions`);
            for (const t of txResp.items ?? []) {
              if (!seen.has(t.txn_id)) {
                seen.add(t.txn_id);
                allTxns.push(t);
              }
            }
          } catch {
            /* skip */
          }
        }
        if (!cancelled) setTransactions(allTxns);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const filtered = useMemo(() => {
    let list = transactions;
    if (filterStatus) list = list.filter((t) => t.status === filterStatus);
    if (search) {
      const q = search.toLowerCase();
      list = list.filter(
        (t) =>
          t.description.toLowerCase().includes(q) ||
          t.txn_id.toLowerCase().includes(q),
      );
    }
    return list;
  }, [transactions, search, filterStatus]);

  const reverse = async (id: string) => {
    try {
      await api("POST", `/transactions/${id}/reverse`);
      setSuccess("Transaction reversed");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <div className="transactions-view">
      <div className="view-toolbar">
        <div className="search-wrapper">
          <input
            type="text"
            className="search-input"
            placeholder="Search transactions..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      <div className="filter-bar">
        {STATUSES.map((s) => {
          const active = filterStatus === s || (s === "all" && !filterStatus);
          return (
            <button
              key={s}
              type="button"
              className={`filter-btn${active ? " active" : ""}`}
              onClick={() => setFilterStatus(s === "all" ? "" : s)}
            >
              {capitalize(s)}
            </button>
          );
        })}
      </div>

      <table className="data-table">
        <thead>
          <tr>
            <th>ID</th>
            <th>Date</th>
            <th>Type</th>
            <th>Description</th>
            <th>Amount</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {filtered.map((t) => (
            <tr key={t.txn_id}>
              <td className="cell-mono">{truncateID(t.txn_id)}</td>
              <td>{formatTimestamp(t.created_at)}</td>
              <td>
                <span className={`type-badge ${t.txn_type}`}>{capitalize(t.txn_type)}</span>
              </td>
              <td>{t.description}</td>
              <td className="cell-balance">{formatAmount(t.amount, t.currency)}</td>
              <td>
                <span className={`status-badge ${t.status}`}>{capitalize(t.status)}</span>
              </td>
              <td>
                {t.status === "posted" && (
                  <button
                    type="button"
                    className="btn btn-sm btn-warning"
                    onClick={() => reverse(t.txn_id)}
                  >
                    Reverse
                  </button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {filtered.length === 0 && (
        <div className="empty-state-large">No transactions found</div>
      )}
    </div>
  );
}
