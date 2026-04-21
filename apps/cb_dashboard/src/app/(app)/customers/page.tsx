"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatDate } from "@/lib/format";
import type { Party } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

export default function CustomersPage() {
  const router = useRouter();
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [parties, setParties] = useState<Party[]>([]);
  const [search, setSearch] = useState("");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const resp = await api<ListResponse<Party>>("GET", "/parties");
        if (!cancelled) setParties(resp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const filtered = useMemo(() => {
    if (!search) return parties;
    const q = search.toLowerCase();
    return parties.filter(
      (p) =>
        p.full_name.toLowerCase().includes(q) ||
        p.email.toLowerCase().includes(q),
    );
  }, [parties, search]);

  const create = async () => {
    if (!name || !email || submitting) return;
    setSubmitting(true);
    try {
      await api("POST", "/parties", { full_name: name, email });
      setSuccess("Customer created");
      setName("");
      setEmail("");
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  const suspend = async (id: string) => {
    try {
      await api("POST", `/parties/${id}/suspend`);
      setSuccess("Customer suspended");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const close = async (id: string) => {
    try {
      await api("POST", `/parties/${id}/close`);
      setSuccess("Customer closed");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <div className="customers-view">
      <div className="view-toolbar">
        <div className="search-wrapper">
          <input
            type="text"
            className="search-input"
            placeholder="Search customers..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      <div className="form-card">
        <h3>New Customer</h3>
        <div className="form-grid">
          <input
            type="text"
            id="customer-name"
            placeholder="Full Name"
            className="form-input"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
          <input
            type="email"
            id="customer-email"
            placeholder="Email Address"
            className="form-input"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </div>
        <div className="form-actions">
          <button
            id="create-customer-button"
            type="button"
            className="btn btn-primary"
            onClick={create}
            disabled={submitting}
          >
            Create Customer
          </button>
        </div>
      </div>

      <table className="data-table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Email</th>
            <th>Status</th>
            <th>Created</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {filtered.map((party) => (
            <tr key={party.party_id}>
              <td className="cell-primary">{party.full_name}</td>
              <td>{party.email}</td>
              <td>
                <span className={`status-badge ${party.status}`}>
                  {capitalize(party.status)}
                </span>
              </td>
              <td>{formatDate(party.created_at)}</td>
              <td>
                <button
                  type="button"
                  className="btn btn-sm btn-ghost"
                  onClick={() => router.push(`/accounts?party=${party.party_id}`)}
                >
                  View
                </button>
                {party.status === "active" && (
                  <button
                    type="button"
                    className="btn btn-sm btn-warning"
                    onClick={() => suspend(party.party_id)}
                  >
                    Suspend
                  </button>
                )}
                <button
                  type="button"
                  className="btn btn-sm btn-danger"
                  onClick={() => close(party.party_id)}
                >
                  Close
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {filtered.length === 0 && (
        <div className="empty-state-large">No customers found</div>
      )}
    </div>
  );
}
