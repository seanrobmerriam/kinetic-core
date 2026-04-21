"use client";

import Link from "next/link";
import { use, useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatAmount, formatDate, formatTimestamp } from "@/lib/format";
import type { Account, AccountHold, Transaction } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

export default function AccountDetailPage({
  params,
}: {
  params: Promise<{ accountId: string }>;
}) {
  const { accountId } = use(params);
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [account, setAccount] = useState<Account | null>(null);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [holds, setHolds] = useState<AccountHold[]>([]);
  const [holdAmount, setHoldAmount] = useState("");
  const [holdReason, setHoldReason] = useState("");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        // Fetch account via parties → accounts (no GET /accounts/:id endpoint).
        const partyResp = await api<ListResponse<{ party_id: string }>>("GET", "/parties");
        const parties = partyResp.items ?? [];
        let found: Account | null = null;
        for (const p of parties) {
          try {
            const accResp = await api<ListResponse<Account>>("GET", `/parties/${p.party_id}/accounts`);
            const match = (accResp.items ?? []).find((a) => a.account_id === accountId);
            if (match) {
              found = match;
              break;
            }
          } catch {
            /* skip */
          }
        }
        if (!cancelled) setAccount(found);
        try {
          const txResp = await api<ListResponse<Transaction>>("GET", `/accounts/${accountId}/transactions`);
          if (!cancelled) setTransactions(txResp.items ?? []);
        } catch {
          /* ignore */
        }
        try {
          const holdResp = await api<ListResponse<AccountHold>>("GET", `/accounts/${accountId}/holds`);
          if (!cancelled) setHolds(holdResp.items ?? []);
        } catch {
          /* ignore */
        }
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [accountId, tick, setError]);

  const availableBalance = useMemo(() => {
    const held = holds.filter((h) => h.status === "active").reduce((s, h) => s + h.amount, 0);
    return (account?.balance ?? 0) - held;
  }, [account, holds]);

  const action = async (path: string, msg: string) => {
    try {
      await api("POST", path);
      setSuccess(msg);
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const placeHold = async () => {
    const amt = parseInt(holdAmount, 10);
    if (!Number.isFinite(amt) || !holdReason) return;
    try {
      await api("POST", `/accounts/${accountId}/holds`, { amount: amt, reason: holdReason });
      setSuccess("Hold placed");
      setHoldAmount("");
      setHoldReason("");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const releaseHold = async (holdId: string) => {
    try {
      await api("DELETE", `/accounts/${accountId}/holds/${holdId}`);
      setSuccess("Hold released");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  if (!account) {
    return (
      <div className="account-detail-view">
        <Link className="btn btn-ghost back-btn" href="/accounts">
          ← Back to Accounts
        </Link>
        <div className="empty-state-large">Loading account…</div>
      </div>
    );
  }

  return (
    <div className="account-detail-view">
      <Link className="btn btn-ghost back-btn" href="/accounts">
        ← Back to Accounts
      </Link>

      <div className="account-header-card">
        <div className="account-header-top">
          <h2 className="account-name">{account.name}</h2>
          <span className={`status-badge-lg ${account.status}`}>
            {capitalize(account.status)}
          </span>
        </div>
        <div className="account-id">Account ID: {account.account_id}</div>
      </div>

      <div className="detail-stats">
        <div className="detail-stat">
          <div className="stat-label">Current Balance</div>
          <div className="stat-value-lg">{formatAmount(account.balance, account.currency)}</div>
        </div>
        <div className="detail-stat">
          <div className="stat-label">Currency</div>
          <div className="stat-value">{account.currency}</div>
        </div>
        <div className="detail-stat">
          <div className="stat-label">Created</div>
          <div className="stat-value">{formatDate(account.created_at)}</div>
        </div>
      </div>

      <div className="account-actions">
        {account.status === "active" && (
          <button
            type="button"
            className="btn btn-warning"
            onClick={() => action(`/accounts/${accountId}/freeze`, "Account frozen")}
          >
            Freeze Account
          </button>
        )}
        {account.status === "frozen" && (
          <button
            type="button"
            className="btn btn-success"
            onClick={() => action(`/accounts/${accountId}/unfreeze`, "Account unfrozen")}
          >
            Unfreeze Account
          </button>
        )}
        <button
          type="button"
          className="btn btn-danger"
          onClick={() => action(`/accounts/${accountId}/close`, "Account closed")}
        >
          Close Account
        </button>
      </div>

      <div className="detail-section">
        <h3>Recent Transactions</h3>
        {transactions.length === 0 ? (
          <div className="empty-state">No transactions yet</div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Type</th>
                <th>Description</th>
                <th>Amount</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {transactions.map((t) => (
                <tr key={t.txn_id}>
                  <td>{formatTimestamp(t.created_at)}</td>
                  <td>
                    <span className={`type-badge ${t.txn_type}`}>{capitalize(t.txn_type)}</span>
                  </td>
                  <td>{t.description}</td>
                  <td className="cell-balance">{formatAmount(t.amount, t.currency)}</td>
                  <td>
                    <span className={`status-badge ${t.status}`}>{capitalize(t.status)}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="detail-section">
        <div className="card-header-row">
          <h3>Funds Holds</h3>
          <span className="stat-label">
            Available: {formatAmount(availableBalance, account.currency)}
          </span>
        </div>

        <div className="form-card">
          <h4>Place New Hold</h4>
          <div className="form-grid">
            <input
              type="number"
              id="hold-amount-input"
              className="form-input"
              placeholder="Amount (minor units)"
              value={holdAmount}
              onChange={(e) => setHoldAmount(e.target.value)}
            />
            <input
              type="text"
              id="hold-reason-input"
              className="form-input"
              placeholder="Reason"
              value={holdReason}
              onChange={(e) => setHoldReason(e.target.value)}
            />
          </div>
          <button type="button" className="btn btn-warning" onClick={placeHold}>
            Place Hold
          </button>
        </div>

        {holds.length === 0 ? (
          <div className="empty-state">No holds on this account</div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>Amount</th>
                <th>Reason</th>
                <th>Status</th>
                <th>Placed</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {holds.map((h) => (
                <tr key={h.hold_id}>
                  <td className="cell-balance">{formatAmount(h.amount, account.currency)}</td>
                  <td>{h.reason}</td>
                  <td>
                    <span className={`status-badge ${h.status}`}>{capitalize(h.status)}</span>
                  </td>
                  <td>{formatTimestamp(h.placed_at)}</td>
                  <td>
                    {h.status === "active" && (
                      <button
                        type="button"
                        className="btn btn-sm btn-ghost"
                        onClick={() => releaseHold(h.hold_id)}
                      >
                        Release
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
