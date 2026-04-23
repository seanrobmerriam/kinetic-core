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
          console.warn(`[IronLedger] API switched to ${alt}`);
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
