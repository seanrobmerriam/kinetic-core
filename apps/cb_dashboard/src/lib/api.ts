"use client";

import type { Party } from "./types";

const SESSION_STORAGE_KEY = "kinetic_core.session_id";

const PRIMARY_PORT = 18081;
const FALLBACK_PORT = 8081;

function envBase(): string {
  const fromEnv = process.env.NEXT_PUBLIC_API_BASE;
  return typeof fromEnv === "string" ? fromEnv.trim().replace(/\/+$/, "") : "";
}

function defaultBase(): string {
  const override = envBase();
  if (override) return override;
  if (typeof window === "undefined") {
    return `http://127.0.0.1:${PRIMARY_PORT}/api/v1`;
  }
  const { protocol, hostname } = window.location;
  return `${protocol || "http:"}//${hostname || "127.0.0.1"}:${PRIMARY_PORT}/api/v1`;
}

function alternateBase(current: string): string {
  if (envBase()) return "";
  if (typeof window === "undefined") return "";
  const { protocol, hostname } = window.location;
  if (current.includes(`:${PRIMARY_PORT}/api/v1`)) {
    return `${protocol}//${hostname}:${FALLBACK_PORT}/api/v1`;
  }
  if (current.includes(`:${FALLBACK_PORT}/api/v1`)) {
    return `${protocol}//${hostname}:${PRIMARY_PORT}/api/v1`;
  }
  return "";
}

let apiBase: string = defaultBase();
let sessionId: string = "";
let unauthorizedHandler: ((message: string) => void) | null = null;

export function getApiBase(): string {
  return apiBase;
}

export function setSessionId(id: string): void {
  sessionId = id;
}

export function clearSessionId(): void {
  sessionId = "";
}

export function getSessionId(): string {
  return sessionId;
}

export function loadStoredSessionId(): string {
  if (typeof window === "undefined") return "";
  try {
    return window.localStorage.getItem(SESSION_STORAGE_KEY) ?? "";
  } catch {
    return "";
  }
}

export function persistSessionId(id: string): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(SESSION_STORAGE_KEY, id);
  } catch {
    /* ignore */
  }
}

export function clearStoredSessionId(): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.removeItem(SESSION_STORAGE_KEY);
  } catch {
    /* ignore */
  }
}

export function setUnauthorizedHandler(handler: ((message: string) => void) | null): void {
  unauthorizedHandler = handler;
}

function isLoginUrl(path: string): boolean {
  return path === "/auth/login";
}

export class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

export async function api<T = unknown>(
  method: string,
  path: string,
  body?: unknown,
): Promise<T> {
  return apiCall<T>(method, path, body, false);
}

let probeInFlight: Promise<void> | null = null;

// Probe the API base on startup so we pin the working port BEFORE any
// user-driven request runs. Idempotent: subsequent calls return the same
// in-flight promise. Safe to call from a useEffect on mount.
export function probeApiBase(): Promise<void> {
  if (probeInFlight) return probeInFlight;
  probeInFlight = (async () => {
    if (envBase()) return; // explicit override — trust it.
    const candidates = [apiBase, alternateBase(apiBase)].filter(
      (b): b is string => Boolean(b),
    );
    for (const candidate of candidates) {
      try {
        // Health endpoint is mounted at the host root, not under /api/v1.
        const healthUrl = candidate.replace(/\/api\/v\d+$/, "") + "/health";
        const res = await fetch(healthUrl, { method: "GET" });
        if (res.ok) {
          apiBase = candidate;
          return;
        }
      } catch {
        // try next candidate
      }
    }
  })();
  return probeInFlight;
}

async function apiCall<T>(
  method: string,
  path: string,
  body: unknown,
  hasRetried: boolean,
): Promise<T> {
  const url = `${apiBase}${path}`;
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (sessionId) {
    headers["Authorization"] = `Bearer ${sessionId}`;
  }
  const init: RequestInit = { method, headers };
  if (body !== undefined && body !== null) {
    init.body = JSON.stringify(body);
  }

  let response: Response;
  try {
    response = await fetch(url, init);
  } catch (err) {
    // Network failure — optionally try the alternate port once for THIS
    // request, but only pin it as the new base if the alt actually succeeds.
    // (Mutating apiBase eagerly used to cause a permanent lockout when the
    // alt port wasn't reachable either — every subsequent call would fail
    // with the WebKit "Load failed" message.)
    if (!hasRetried) {
      const alt = alternateBase(apiBase);
      if (alt && alt !== apiBase) {
        try {
          response = await fetch(`${alt}${path}`, init);
          console.warn(`[Kinetic Core] API switched to ${alt}`);
          apiBase = alt;
        } catch {
          throw new Error(`fetch error: ${(err as Error).message}`);
        }
      } else {
        throw new Error(`fetch error: ${(err as Error).message}`);
      }
    } else {
      throw new Error(`fetch error: ${(err as Error).message}`);
    }
  }

  if (response.status === 204) {
    return undefined as T;
  }

  if (!response.ok) {
    let message = `HTTP ${response.status}`;
    try {
      const errBody = (await response.json()) as { message?: string };
      if (errBody?.message) message = errBody.message;
    } catch {
      /* ignore */
    }
    if (response.status === 401 && sessionId && !isLoginUrl(path) && unauthorizedHandler) {
      unauthorizedHandler("Session expired. Please sign in again.");
    }
    throw new ApiError(`API error: ${message}`, response.status);
  }

  try {
    return (await response.json()) as T;
  } catch {
    return undefined as T;
  }
}

// -----------------------------------------------------------------------------
// Party merge and duplicate detection
// -----------------------------------------------------------------------------

export interface DuplicateGroup {
  normalized_name: string;
  party_ids: string[];
}

export interface MergeResult {
  ok: boolean;
  merged_party: Party;
  source_party_id: string;
  target_party_id: string;
}

export interface TrialBalanceEntry {
  account_id: string;
  account_name: string;
  currency: string;
  debit_balance_minor: number;
  credit_balance_minor: number;
}

export interface TrialBalanceResponse {
  accounts: TrialBalanceEntry[];
  generated_at: number;
}

export interface GeneralLedgerEntry {
  entry_id: string;
  txn_id: string;
  account_id: string;
  entry_type: "debit" | "credit";
  amount: number;
  currency: string;
  description: string;
  posted_at: number;
}

export interface GeneralLedgerResponse {
  items: GeneralLedgerEntry[];
  total: number;
  page: number;
  page_size: number;
}

/**
 * Retrieve trial balance: per-account debit/credit breakdown.
 */
export async function getTrialBalance(params?: {
  as_of_date?: string;
  currency?: string;
}): Promise<TrialBalanceResponse> {
  const qs: string[] = [];
  if (params?.as_of_date) qs.push(`as_of_date=${params.as_of_date}`);
  if (params?.currency) qs.push(`currency=${params.currency}`);
  const query = qs.length > 0 ? `?${qs.join("&")}` : "";
  return api<TrialBalanceResponse>("GET", `/ledger/trial-balance${query}`);
}

/**
 * Retrieve paginated general ledger entries with optional filters.
 */
export async function getGeneralLedger(params?: {
  account_id?: string;
  entry_type?: "debit" | "credit";
  currency?: string;
  from_ms?: number;
  to_ms?: number;
  page?: number;
  page_size?: number;
}): Promise<GeneralLedgerResponse> {
  const qs: string[] = [];
  if (params?.account_id) qs.push(`account_id=${params.account_id}`);
  if (params?.entry_type) qs.push(`entry_type=${params.entry_type}`);
  if (params?.currency) qs.push(`currency=${params.currency}`);
  if (params?.from_ms) qs.push(`from_ms=${params.from_ms}`);
  if (params?.to_ms) qs.push(`to_ms=${params.to_ms}`);
  if (params?.page) qs.push(`page=${params.page}`);
  if (params?.page_size) qs.push(`page_size=${params.page_size}`);
  const query = qs.length > 0 ? `?${qs.join("&")}` : "";
  return api<GeneralLedgerResponse>("GET", `/ledger/general-ledger${query}`);
}

export interface TransactionEntry {
  entry_id: string;
  txn_id: string;
  account_id: string;
  entry_type: "debit" | "credit";
  amount: number;
  currency: string;
  description: string;
  posted_at: number;
}

export interface TransactionDetail {
  txn_id: string;
  idempotency_key: string;
  txn_type: string;
  status: string;
  amount: number;
  currency: string;
  source_account_id: string;
  dest_account_id: string;
  description: string;
  created_at: number;
  posted_at: number;
  entries?: TransactionEntry[];
}

export interface TransactionEntriesResponse {
  items: TransactionEntry[];
  total: number;
  page: number;
  page_size: number;
}

/**
 * Retrieve a single transaction by ID.
 */
export async function getTransaction(txnId: string): Promise<TransactionDetail> {
  return api<TransactionDetail>("GET", `/transactions/${txnId}`);
}

/**
 * Retrieve ledger entries for a specific transaction.
 */
export async function getTransactionEntries(txnId: string): Promise<TransactionEntriesResponse> {
  return api<TransactionEntriesResponse>("GET", `/transactions/${txnId}/entries`);
}

/**
 * Create a manual ledger adjustment (ops_admin only).
 * Amount is in minor units; reason must be ≥10 characters.
 */
export interface AdjustmentPayload {
  idempotency_key: string;
  account_id: string;
  amount: number;
  currency: string;
  description: string;
}

export async function createAdjustment(payload: AdjustmentPayload): Promise<TransactionDetail> {
  return api<TransactionDetail>("POST", "/transactions/adjustment", payload);
}

/**
 * Find parties that may be duplicates (same normalized name).
 * Pass name=DobOrDocument to filter candidates interactively.
 */
export async function findDuplicates(params?: {
  name?: string;
}): Promise<{ duplicates: DuplicateGroup[] }> {
  const qs = params?.name ? `?name=${encodeURIComponent(params.name)}` : "";
  return api<{ duplicates: DuplicateGroup[] }>("GET", `/parties/duplicates${qs}`);
}

/**
 * Merge a source party into a target party.
 * All accounts are transferred; source is closed.
 */
export async function mergeParties(
  sourcePartyId: string,
  targetPartyId: string,
  reason: string,
): Promise<MergeResult> {
  return api<MergeResult>("POST", `/parties/${sourcePartyId}/merge`, {
    target_party_id: targetPartyId,
    reason,
  });
}

export interface KycResponse {
  party_id: string;
  kyc_status: string;
  onboarding_status: string;
  review_notes: string | null;
  doc_refs: string[] | null;
  updated_at: number;
}

/**
 * Add a document reference to a party's KYC record.
 * docRef is typically an S3 URI like "s3://bucket/key".
 */
export async function addKycDocumentRef(partyId: string, docRef: string): Promise<KycResponse> {
  return api<KycResponse>("POST", `/parties/${partyId}/kyc/docs`, { doc_ref: docRef });
}

/**
 * Export a resource (parties | accounts | transactions | ledger | events) as CSV.
 * Returns raw CSV binary — caller handles download.
 */
export async function exportResource(
  resource: "parties" | "accounts" | "transactions" | "ledger" | "events",
  filters?: { account_id?: string; from?: number; to?: number },
): Promise<Blob> {
  const params = new URLSearchParams();
  params.set("format", "csv");
  if (filters?.account_id) params.set("account_id", filters.account_id);
  if (filters?.from) params.set("from", String(filters.from));
  if (filters?.to) params.set("to", String(filters.to));
  const qs = params.toString();
  const path = `/export/${resource}${qs ? `?${qs}` : ""}`;
  // Use fetch directly to get raw binary response
  const url = `${getApiBase()}${path}`;
  const headers: Record<string, string> = {};
  const sid = getSessionId();
  if (sid) headers["Authorization"] = `Bearer ${sid}`;
  const res = await fetch(url, { method: "GET", headers });
  if (!res.ok) {
    const body = await res.text();
    throw new ApiError(`Export failed: ${body}`, res.status);
  }
  return res.blob();
}
