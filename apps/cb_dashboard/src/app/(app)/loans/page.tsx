"use client";

import { useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatAmount, formatTimestamp, parseAmount, truncateID } from "@/lib/format";
import type { Account, Loan, LoanProduct, LoanRepayment, Party } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

export default function LoansPage() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [parties, setParties] = useState<Party[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [products, setProducts] = useState<LoanProduct[]>([]);
  const [loans, setLoans] = useState<Loan[]>([]);
  const [partyId, setPartyId] = useState("");
  const [productId, setProductId] = useState("");
  const [accountId, setAccountId] = useState("");
  const [principal, setPrincipal] = useState("");
  const [term, setTerm] = useState("");
  const [selectedLoan, setSelectedLoan] = useState<Loan | null>(null);
  const [repayments, setRepayments] = useState<LoanRepayment[]>([]);
  const [repayAmount, setRepayAmount] = useState("");
  const [repayType, setRepayType] = useState("partial");

  // Bootstrap: parties, accounts, loan products
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const ps = partyResp.items ?? [];
        if (!cancelled) setParties(ps);
        let allAccounts: Account[] = [];
        for (const p of ps) {
          try {
            const accResp = await api<ListResponse<Account>>("GET", `/parties/${p.party_id}/accounts`);
            if (accResp.items) allAccounts = allAccounts.concat(accResp.items);
          } catch {
            /* skip */
          }
        }
        if (!cancelled) setAccounts(allAccounts);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
      try {
        const lp = await api<ListResponse<LoanProduct>>("GET", "/loan-products");
        if (!cancelled) setProducts(lp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  // Loans for selected party
  useEffect(() => {
    if (!partyId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setLoans([]);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const resp = await api<ListResponse<Loan>>("GET", `/loans?party_id=${partyId}`);
        if (!cancelled) setLoans(resp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [partyId, tick, setError]);

  const partyAccounts = useMemo(
    () => accounts.filter((a) => a.party_id === partyId),
    [accounts, partyId],
  );

  const productName = (id: string) => products.find((p) => p.product_id === id)?.name ?? truncateID(id);

  const createLoan = async () => {
    if (!partyId) {
      setError("Select a customer first");
      return;
    }
    let principalAmt: number;
    try {
      principalAmt = parseAmount(principal);
    } catch {
      setError("Invalid principal amount");
      return;
    }
    const termMonths = parseInt(term, 10);
    if (!Number.isFinite(termMonths)) {
      setError("Invalid loan term");
      return;
    }
    try {
      await api("POST", "/loans", {
        party_id: partyId,
        product_id: productId,
        account_id: accountId,
        principal: principalAmt,
        term_months: termMonths,
      });
      setSuccess("Loan created");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const loadLoan = async (loanId: string) => {
    try {
      const loan = await api<Loan>("GET", `/loans/${loanId}`);
      setSelectedLoan(loan);
      const repaymentsResp = await api<ListResponse<LoanRepayment>>(
        "GET",
        `/loans/${loanId}/repayments`,
      );
      setRepayments(repaymentsResp.items ?? []);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const approve = async (loanId: string) => {
    try {
      await api("POST", `/loans/${loanId}/approve`);
      setSuccess("Loan approved");
      bump();
      if (selectedLoan?.loan_id === loanId) await loadLoan(loanId);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const disburse = async (loanId: string) => {
    try {
      await api("POST", `/loans/${loanId}/disburse`);
      setSuccess("Loan disbursed");
      bump();
      if (selectedLoan?.loan_id === loanId) await loadLoan(loanId);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const recordRepayment = async () => {
    if (!selectedLoan) return;
    let amt: number;
    try {
      amt = parseAmount(repayAmount);
    } catch {
      setError("Invalid repayment amount");
      return;
    }
    try {
      await api("POST", `/loans/${selectedLoan.loan_id}/repayments`, {
        amount: amt,
        payment_type: repayType,
      });
      setSuccess("Repayment recorded");
      setRepayAmount("");
      await loadLoan(selectedLoan.loan_id);
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <div className="loans-view">
      <div className="view-toolbar">
        <label>
          Customer
          <select
            id="loan-party-select"
            className="form-select"
            value={partyId}
            onChange={(e) => {
              setPartyId(e.target.value);
              setSelectedLoan(null);
              setRepayments([]);
            }}
          >
            <option value="">Select customer</option>
            {parties.map((p) => (
              <option key={p.party_id} value={p.party_id}>
                {p.full_name} ({p.email})
              </option>
            ))}
          </select>
        </label>
        <button type="button" className="btn btn-secondary" onClick={bump}>
          Refresh Loans
        </button>
      </div>

      <div className="form-card">
        <h3>Create Loan</h3>
        <div className="form-stack">
          <label>
            Loan Product
            <select
              id="loan-create-product"
              className="form-select"
              value={productId}
              onChange={(e) => setProductId(e.target.value)}
            >
              <option value="">Select product</option>
              {products.map((p) => (
                <option key={p.product_id} value={p.product_id}>
                  {p.name} ({p.currency})
                </option>
              ))}
            </select>
          </label>
          <label>
            Disbursement Account
            <select
              id="loan-create-account"
              className="form-select"
              value={accountId}
              onChange={(e) => setAccountId(e.target.value)}
            >
              <option value="">Select account</option>
              {partyAccounts.map((a) => (
                <option key={a.account_id} value={a.account_id}>
                  {a.name} ({a.currency})
                </option>
              ))}
            </select>
          </label>
          <label>
            Principal
            <input
              id="loan-create-principal"
              type="text"
              className="form-input"
              placeholder="1000.00"
              value={principal}
              onChange={(e) => setPrincipal(e.target.value)}
            />
          </label>
          <label>
            Term (months)
            <input
              id="loan-create-term"
              type="number"
              className="form-input"
              placeholder="12"
              value={term}
              onChange={(e) => setTerm(e.target.value)}
            />
          </label>
          <button
            id="create-loan-button"
            type="button"
            className="btn btn-primary"
            onClick={createLoan}
          >
            Create Loan
          </button>
        </div>
      </div>

      <div className="dashboard-card">
        <h3>Loans</h3>
        {loans.length === 0 ? (
          <div className="empty-state">
            {partyId ? "No loans for the selected customer" : "Select a customer to view loans"}
          </div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>Loan</th>
                <th>Product</th>
                <th>Principal</th>
                <th>Outstanding</th>
                <th>Monthly Payment</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loans.map((l) => (
                <tr key={l.loan_id}>
                  <td>{truncateID(l.loan_id)}</td>
                  <td>{productName(l.product_id)}</td>
                  <td>{formatAmount(l.principal, l.currency)}</td>
                  <td>{formatAmount(l.outstanding_balance, l.currency)}</td>
                  <td>{formatAmount(l.monthly_payment, l.currency)}</td>
                  <td>{capitalize(l.status)}</td>
                  <td>
                    <button
                      type="button"
                      className="btn btn-sm btn-primary"
                      onClick={() => loadLoan(l.loan_id)}
                    >
                      View
                    </button>
                    {l.status === "pending" && (
                      <button
                        type="button"
                        className="btn btn-sm btn-success"
                        onClick={() => approve(l.loan_id)}
                      >
                        Approve
                      </button>
                    )}
                    {l.status === "approved" && (
                      <button
                        type="button"
                        className="btn btn-sm btn-warning"
                        onClick={() => disburse(l.loan_id)}
                      >
                        Disburse
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {selectedLoan && (
        <div className="dashboard-card">
          <h3>Loan Details and Repayments</h3>
          <div className="detail-stats">
            <div className="detail-stat">
              <div className="stat-label">Loan ID</div>
              <div className="stat-value">{truncateID(selectedLoan.loan_id)}</div>
            </div>
            <div className="detail-stat">
              <div className="stat-label">Outstanding</div>
              <div className="stat-value">
                {formatAmount(selectedLoan.outstanding_balance, selectedLoan.currency)}
              </div>
            </div>
            <div className="detail-stat">
              <div className="stat-label">Status</div>
              <div className="stat-value">{capitalize(selectedLoan.status)}</div>
            </div>
          </div>

          <div className="form-stack">
            <label>
              Repayment Amount
              <input
                id="loan-repayment-amount"
                type="text"
                className="form-input"
                placeholder="50.00"
                value={repayAmount}
                onChange={(e) => setRepayAmount(e.target.value)}
              />
            </label>
            <label>
              Payment Type
              <select
                id="loan-repayment-type"
                className="form-select"
                value={repayType}
                onChange={(e) => setRepayType(e.target.value)}
              >
                {["partial", "full"].map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </label>
            <button
              id="record-loan-repayment-button"
              type="button"
              className="btn btn-primary"
              onClick={recordRepayment}
            >
              Record Repayment
            </button>
          </div>

          {repayments.length === 0 ? (
            <div className="empty-state">No repayments recorded yet</div>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Amount</th>
                  <th>Principal</th>
                  <th>Interest</th>
                  <th>Status</th>
                  <th>Paid At</th>
                </tr>
              </thead>
              <tbody>
                {repayments.map((r) => (
                  <tr key={r.repayment_id}>
                    <td>{formatAmount(r.amount, selectedLoan.currency)}</td>
                    <td>{formatAmount(r.principal_portion, selectedLoan.currency)}</td>
                    <td>{formatAmount(r.interest_portion, selectedLoan.currency)}</td>
                    <td>{capitalize(r.status)}</td>
                    <td>{formatTimestamp(r.paid_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
    </div>
  );
}
