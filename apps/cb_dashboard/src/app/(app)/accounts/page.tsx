"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatAmount, truncateID } from "@/lib/format";
import type { Account, Party } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

const STATUSES = ["all", "active", "frozen", "closed"] as const;

export default function AccountsPage() {
  const searchParams = useSearchParams();
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [parties, setParties] = useState<Party[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState<string>("");
  const [partyId, setPartyId] = useState<string>(searchParams?.get("party") ?? "");
  const [name, setName] = useState("");
  const [currency, setCurrency] = useState("USD");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const ps = partyResp.items ?? [];
        if (!cancelled) setParties(ps);
        let all: Account[] = [];
        for (const p of ps) {
          try {
            const accResp = await api<ListResponse<Account>>("GET", `/parties/${p.party_id}/accounts`);
            if (accResp.items) all = all.concat(accResp.items);
          } catch {
            /* skip */
          }
        }
        if (!cancelled) setAccounts(all);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const filtered = useMemo(() => {
    let list = accounts;
    if (filterStatus) list = list.filter((a) => a.status === filterStatus);
    if (search) {
      const q = search.toLowerCase();
      list = list.filter(
        (a) =>
          a.name.toLowerCase().includes(q) ||
          a.account_id.toLowerCase().includes(q),
      );
    }
    return list;
  }, [accounts, search, filterStatus]);

  const create = async () => {
    if (!partyId) {
      setError("Select a customer first");
      return;
    }
    if (!name) {
      setError("Account name is required");
      return;
    }
    try {
      await api("POST", "/accounts", {
        party_id: partyId,
        name,
        currency,
      });
      setSuccess("Account created");
      setName("");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <div className="accounts-view">
      <div className="view-toolbar">
        <div className="search-wrapper">
          <input
            type="text"
            className="search-input"
            placeholder="Search accounts..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      <div className="form-card" data-testid="create-account-form">
        <h3>Open New Account</h3>
        <div className="form-stack">
          <label>
            Customer
            <select
              id="account-party-select"
              className="form-select"
              value={partyId}
              onChange={(e) => setPartyId(e.target.value)}
            >
              <option value="">Select customer</option>
              {parties.map((p) => (
                <option key={p.party_id} value={p.party_id}>
                  {p.full_name} ({p.email})
                </option>
              ))}
            </select>
          </label>
          <label>
            Account Name
            <input
              id="account-name"
              type="text"
              className="form-input"
              placeholder="Main Checking"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </label>
          <label>
            Currency
            <select
              id="account-currency"
              className="form-select"
              value={currency}
              onChange={(e) => setCurrency(e.target.value)}
            >
              {["USD", "EUR", "GBP", "JPY"].map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </label>
          <button
            id="create-account-button"
            type="button"
            className="btn btn-primary"
            onClick={create}
          >
            Create Account
          </button>
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
            <th>Account ID</th>
            <th>Name</th>
            <th>Currency</th>
            <th>Balance</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {filtered.map((a) => (
            <tr key={a.account_id}>
              <td className="cell-mono">{truncateID(a.account_id)}</td>
              <td className="cell-primary">{a.name}</td>
              <td>{a.currency}</td>
              <td className="cell-balance">{formatAmount(a.balance, a.currency)}</td>
              <td>
                <span className={`status-badge ${a.status}`}>
                  {capitalize(a.status)}
                </span>
              </td>
              <td>
                <Link
                  className="btn btn-sm btn-primary"
                  href={`/accounts/${a.account_id}`}
                >
                  View
                </Link>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {filtered.length === 0 && (
        <div className="empty-state-large">No accounts found</div>
      )}
    </div>
  );
}
