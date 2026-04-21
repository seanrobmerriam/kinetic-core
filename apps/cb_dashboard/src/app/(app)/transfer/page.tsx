"use client";

import { useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { parseAmount } from "@/lib/format";

const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CHF"];

export default function TransferPage() {
  const { setError, setSuccess } = useNotify();
  const [source, setSource] = useState("");
  const [dest, setDest] = useState("");
  const [amount, setAmount] = useState("");
  const [currency, setCurrency] = useState("USD");
  const [desc, setDesc] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const submit = async () => {
    let amt: number;
    try {
      amt = parseAmount(amount);
    } catch {
      setError("Invalid amount format");
      return;
    }
    setSubmitting(true);
    try {
      await api("POST", "/transactions/transfer", {
        idempotency_key: `web-${Date.now()}`,
        source_account_id: source,
        dest_account_id: dest,
        amount: amt,
        currency,
        description: desc,
      });
      setSuccess("Transfer successful!");
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="transfer-view">
      <Link className="btn btn-ghost back-btn" href="/dashboard">
        ← Back
      </Link>
      <h2>Transfer Funds</h2>

      <div className="form-card">
        <div className="form-grid">
          <label>Source Account ID</label>
          <input
            id="transfer-source"
            type="text"
            className="form-input"
            placeholder="Enter source account ID"
            value={source}
            onChange={(e) => setSource(e.target.value)}
          />
          <label>Destination Account ID</label>
          <input
            id="transfer-dest"
            type="text"
            className="form-input"
            placeholder="Enter destination account ID"
            value={dest}
            onChange={(e) => setDest(e.target.value)}
          />
          <label>Amount</label>
          <input
            id="transfer-amount"
            type="text"
            className="form-input"
            placeholder="Enter amount (e.g., 100.00)"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
          <label>Currency</label>
          <select
            id="transfer-currency"
            className="form-select"
            value={currency}
            onChange={(e) => setCurrency(e.target.value)}
          >
            {CURRENCIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
          <label>Description</label>
          <input
            id="transfer-desc"
            type="text"
            className="form-input"
            placeholder="Enter description"
            value={desc}
            onChange={(e) => setDesc(e.target.value)}
          />
        </div>
        <button
          type="button"
          className="btn btn-primary btn-lg"
          onClick={submit}
          disabled={submitting}
        >
          Transfer Funds
        </button>
      </div>
    </div>
  );
}
