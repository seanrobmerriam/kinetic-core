"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatAmount, parseAmount } from "@/lib/format";
import type { LoanProduct, SavingsProduct } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

export default function ProductsPage() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [savings, setSavings] = useState<SavingsProduct[]>([]);
  const [loans, setLoans] = useState<LoanProduct[]>([]);

  // Savings form
  const [sName, setSName] = useState("");
  const [sDesc, setSDesc] = useState("");
  const [sRate, setSRate] = useState("");
  const [sMin, setSMin] = useState("");
  const [sCurrency, setSCurrency] = useState("USD");
  const [sInterestType, setSInterestType] = useState("simple");
  const [sCompounding, setSCompounding] = useState("daily");

  // Loan form
  const [lName, setLName] = useState("");
  const [lDesc, setLDesc] = useState("");
  const [lMin, setLMin] = useState("");
  const [lMax, setLMax] = useState("");
  const [lMinTerm, setLMinTerm] = useState("");
  const [lMaxTerm, setLMaxTerm] = useState("");
  const [lRate, setLRate] = useState("");
  const [lCurrency, setLCurrency] = useState("USD");
  const [lInterestType, setLInterestType] = useState("flat");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const sResp = await api<ListResponse<SavingsProduct>>("GET", "/savings-products");
        if (!cancelled) setSavings(sResp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
      try {
        const lResp = await api<ListResponse<LoanProduct>>("GET", "/loan-products");
        if (!cancelled) setLoans(lResp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const createSavings = async () => {
    const rateBps = parseInt(sRate, 10);
    if (!Number.isFinite(rateBps)) {
      setError("Invalid interest rate");
      return;
    }
    let minBalance: number;
    try {
      minBalance = parseAmount(sMin);
    } catch {
      setError("Invalid minimum balance");
      return;
    }
    try {
      await api("POST", "/savings-products", {
        name: sName,
        description: sDesc,
        currency: sCurrency,
        interest_rate_bps: rateBps,
        interest_type: sInterestType,
        compounding_period: sCompounding,
        minimum_balance: minBalance,
      });
      setSuccess("Savings product created");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const createLoan = async () => {
    const minTerm = parseInt(lMinTerm, 10);
    const maxTerm = parseInt(lMaxTerm, 10);
    const rateBps = parseInt(lRate, 10);
    if (!Number.isFinite(minTerm) || !Number.isFinite(maxTerm)) {
      setError("Invalid loan product term");
      return;
    }
    if (!Number.isFinite(rateBps)) {
      setError("Invalid loan product rate");
      return;
    }
    let minAmt: number;
    let maxAmt: number;
    try {
      minAmt = parseAmount(lMin);
      maxAmt = parseAmount(lMax);
    } catch {
      setError("Invalid loan product amounts");
      return;
    }
    try {
      await api("POST", "/loan-products", {
        name: lName,
        description: lDesc,
        currency: lCurrency,
        min_amount: minAmt,
        max_amount: maxAmt,
        min_term_months: minTerm,
        max_term_months: maxTerm,
        interest_rate_bps: rateBps,
        interest_type: lInterestType,
      });
      setSuccess("Loan product created");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <div className="products-view">
      <div className="view-toolbar">
        <h3>Product Management</h3>
        <button type="button" className="btn btn-secondary" onClick={bump}>
          Refresh Products
        </button>
      </div>

      <div className="two-col-forms">
        <div className="form-card">
          <h3>Create Savings Product</h3>
          <div className="form-stack">
            <label>
              Name
              <input
                id="savings-name"
                type="text"
                className="form-input"
                placeholder="High Yield Savings"
                value={sName}
                onChange={(e) => setSName(e.target.value)}
              />
            </label>
            <label>
              Description
              <input
                id="savings-description"
                type="text"
                className="form-input"
                placeholder="Product description"
                value={sDesc}
                onChange={(e) => setSDesc(e.target.value)}
              />
            </label>
            <label>
              Interest Rate (bps)
              <input
                id="savings-rate-bps"
                type="number"
                className="form-input"
                placeholder="450"
                value={sRate}
                onChange={(e) => setSRate(e.target.value)}
              />
            </label>
            <label>
              Minimum Balance
              <input
                id="savings-minimum-balance"
                type="text"
                className="form-input"
                placeholder="100.00"
                value={sMin}
                onChange={(e) => setSMin(e.target.value)}
              />
            </label>
            <label>
              Currency
              <select
                id="savings-currency"
                className="form-select"
                value={sCurrency}
                onChange={(e) => setSCurrency(e.target.value)}
              >
                {["USD", "EUR", "GBP", "JPY"].map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Interest Type
              <select
                id="savings-interest-type"
                className="form-select"
                value={sInterestType}
                onChange={(e) => setSInterestType(e.target.value)}
              >
                {["simple", "compound"].map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Compounding Period
              <select
                id="savings-compounding-period"
                className="form-select"
                value={sCompounding}
                onChange={(e) => setSCompounding(e.target.value)}
              >
                {["daily", "monthly", "quarterly", "annually"].map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </label>
            <button
              id="create-savings-product-button"
              type="button"
              className="btn btn-primary"
              onClick={createSavings}
            >
              Create Savings Product
            </button>
          </div>
        </div>

        <div className="form-card">
          <h3>Create Loan Product</h3>
          <div className="form-stack">
            <label>
              Name
              <input
                id="loan-product-name"
                type="text"
                className="form-input"
                placeholder="Starter Loan"
                value={lName}
                onChange={(e) => setLName(e.target.value)}
              />
            </label>
            <label>
              Description
              <input
                id="loan-product-description"
                type="text"
                className="form-input"
                placeholder="Loan product description"
                value={lDesc}
                onChange={(e) => setLDesc(e.target.value)}
              />
            </label>
            <label>
              Min Amount
              <input
                id="loan-product-min-amount"
                type="text"
                className="form-input"
                placeholder="100.00"
                value={lMin}
                onChange={(e) => setLMin(e.target.value)}
              />
            </label>
            <label>
              Max Amount
              <input
                id="loan-product-max-amount"
                type="text"
                className="form-input"
                placeholder="5000.00"
                value={lMax}
                onChange={(e) => setLMax(e.target.value)}
              />
            </label>
            <label>
              Min Term (months)
              <input
                id="loan-product-min-term"
                type="number"
                className="form-input"
                placeholder="6"
                value={lMinTerm}
                onChange={(e) => setLMinTerm(e.target.value)}
              />
            </label>
            <label>
              Max Term (months)
              <input
                id="loan-product-max-term"
                type="number"
                className="form-input"
                placeholder="24"
                value={lMaxTerm}
                onChange={(e) => setLMaxTerm(e.target.value)}
              />
            </label>
            <label>
              Interest Rate (bps)
              <input
                id="loan-product-rate-bps"
                type="number"
                className="form-input"
                placeholder="1200"
                value={lRate}
                onChange={(e) => setLRate(e.target.value)}
              />
            </label>
            <label>
              Currency
              <select
                id="loan-product-currency"
                className="form-select"
                value={lCurrency}
                onChange={(e) => setLCurrency(e.target.value)}
              >
                {["USD", "EUR", "GBP", "JPY"].map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Interest Type
              <select
                id="loan-product-interest-type"
                className="form-select"
                value={lInterestType}
                onChange={(e) => setLInterestType(e.target.value)}
              >
                {["flat", "declining"].map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </label>
            <button
              id="create-loan-product-button"
              type="button"
              className="btn btn-primary"
              onClick={createLoan}
            >
              Create Loan Product
            </button>
          </div>
        </div>
      </div>

      <div className="dashboard-card">
        <h3>Savings Products</h3>
        {savings.length === 0 ? (
          <div className="empty-state">No savings products yet</div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Currency</th>
                <th>Rate</th>
                <th>Type</th>
                <th>Minimum Balance</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {savings.map((p) => (
                <tr key={p.product_id}>
                  <td>{p.name}</td>
                  <td>{p.currency}</td>
                  <td>{p.interest_rate_bps} bps</td>
                  <td>
                    {capitalize(p.interest_type)} / {capitalize(p.compounding_period)}
                  </td>
                  <td>{formatAmount(p.minimum_balance, p.currency)}</td>
                  <td>{capitalize(p.status)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="dashboard-card">
        <h3>Loan Products</h3>
        {loans.length === 0 ? (
          <div className="empty-state">No loan products yet</div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Currency</th>
                <th>Amount Range</th>
                <th>Term Range</th>
                <th>Rate</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {loans.map((p) => (
                <tr key={p.product_id}>
                  <td>{p.name}</td>
                  <td>{p.currency}</td>
                  <td>
                    {formatAmount(p.min_amount, p.currency)} -{" "}
                    {formatAmount(p.max_amount, p.currency)}
                  </td>
                  <td>
                    {p.min_term_months}-{p.max_term_months} mo
                  </td>
                  <td>
                    {p.interest_rate_bps} bps {capitalize(p.interest_type)}
                  </td>
                  <td>{capitalize(p.status)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
