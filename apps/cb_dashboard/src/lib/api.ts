"use client";

const SESSION_STORAGE_KEY = "ironledger.session_id";

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
    // Network failure — try alternate port once.
    if (!hasRetried) {
      const alt = alternateBase(apiBase);
      if (alt && alt !== apiBase) {
        console.warn(`[IronLedger] API fetch failed, retrying ${alt}`);
        apiBase = alt;
        return apiCall<T>(method, path, body, true);
      }
    }
    throw new Error(`fetch error: ${(err as Error).message}`);
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
