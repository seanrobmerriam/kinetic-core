"use client";

import { useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { parseAmount } from "@/lib/format";

const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CHF"];

interface FormProps {
  prefix: "deposit" | "withdraw";
  endpoint: string;
  bodyKey: "source_account_id" | "dest_account_id";
  label: string;
  buttonClass: string;
  successMessage: string;
}

function MoveForm({ prefix, endpoint, bodyKey, label, buttonClass, successMessage }: FormProps) {
  const { setError, setSuccess } = useNotify();
  const [account, setAccount] = useState("");
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
      await api("POST", endpoint, {
        idempotency_key: `web-${Date.now()}`,
        [bodyKey]: account,
        amount: amt,
        currency,
        description: desc,
      });
      setSuccess(successMessage);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="form-card">
      <h3>{label}</h3>
      <div className="form-stack">
        <label>
          Account ID
          <input
            id={`${prefix}-account`}
            type="text"
            className="form-input"
            placeholder="Enter account ID"
            value={account}
            onChange={(e) => setAccount(e.target.value)}
          />
        </label>
        <label>
          Amount
          <input
            id={`${prefix}-amount`}
            type="text"
            className="form-input"
            placeholder="Enter amount"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </label>
        <label>
          Currency
          <select
            id={`${prefix}-currency`}
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
        </label>
        <label>
          Description
          <input
            id={`${prefix}-desc`}
            type="text"
            className="form-input"
            placeholder="Enter description"
            value={desc}
            onChange={(e) => setDesc(e.target.value)}
          />
        </label>
        <button
          type="button"
          className={`btn ${buttonClass} btn-lg`}
          onClick={submit}
          disabled={submitting}
        >
          {label}
        </button>
      </div>
    </div>
  );
}

export default function DepositWithdrawPage() {
  return (
    <div className="deposit-view">
      <Link className="btn btn-ghost back-btn" href="/dashboard">
        ← Back
      </Link>
      <h2>Deposit / Withdraw</h2>

      <div className="two-col-forms">
        <MoveForm
          prefix="deposit"
          endpoint="/transactions/deposit"
          bodyKey="dest_account_id"
          label="Deposit"
          buttonClass="btn-success"
          successMessage="Deposit successful!"
        />
        <MoveForm
          prefix="withdraw"
          endpoint="/transactions/withdraw"
          bodyKey="source_account_id"
          label="Withdraw"
          buttonClass="btn-warning"
          successMessage="Withdrawal successful!"
        />
      </div>
    </div>
  );
}
