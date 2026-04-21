"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { capitalize, formatAmount, formatTimestamp, truncateID } from "@/lib/format";
import type { LedgerEntry } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

export default function LedgerPage() {
  const { setError } = useNotify();
  const [accountId, setAccountId] = useState("");
  const [entries, setEntries] = useState<LedgerEntry[]>([]);
  const [loaded, setLoaded] = useState(false);

  const filter = async () => {
    if (!accountId) return;
    try {
      const resp = await api<ListResponse<LedgerEntry>>(
        "GET",
        `/accounts/${accountId}/entries`,
      );
      setEntries(resp.items ?? []);
      setLoaded(true);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <div className="ledger-view">
      <div className="section-header">
        <h3>Ledger Entries</h3>
      </div>

      <div className="filter-card">
        <label>Filter by Account ID:</label>
        <input
          type="text"
          id="ledger-account-filter"
          className="form-input"
          placeholder="Enter account ID"
          value={accountId}
          onChange={(e) => setAccountId(e.target.value)}
        />
        <button type="button" className="btn btn-primary" onClick={filter}>
          Filter
        </button>
      </div>

      {!loaded || entries.length === 0 ? (
        <div className="empty-state-large">
          {loaded ? "No ledger entries found" : "Select an account to view ledger entries"}
        </div>
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Entry ID</th>
              <th>Transaction ID</th>
              <th>Account ID</th>
              <th>Type</th>
              <th>Amount</th>
              <th>Description</th>
              <th>Posted At</th>
            </tr>
          </thead>
          <tbody>
            {entries.map((e) => (
              <tr key={e.entry_id}>
                <td className="cell-mono">{truncateID(e.entry_id)}</td>
                <td className="cell-mono">{truncateID(e.txn_id)}</td>
                <td className="cell-mono">{truncateID(e.account_id)}</td>
                <td>
                  <span className={`type-badge ${e.entry_type}`}>{capitalize(e.entry_type)}</span>
                </td>
                <td className="cell-balance">{formatAmount(e.amount, e.currency)}</td>
                <td>{e.description}</td>
                <td>{formatTimestamp(e.posted_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
