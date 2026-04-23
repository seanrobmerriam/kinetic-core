// Pure helpers for building and exporting account statements.
// Kept free of DOM and React APIs so they can be unit-tested in isolation.

export interface StatementEntry {
  entry_id: string;
  txn_id: string;
  account_id: string;
  entry_type: "credit" | "debit";
  amount: number;
  currency: string;
  description: string | null;
  posted_at: number;
  running_balance: number;
}

export interface StatementResponse {
  account_id: string;
  party_id: string;
  name: string;
  currency: string;
  current_balance: number;
  opening_balance: number;
  closing_balance: number;
  entries: StatementEntry[];
  total: number;
  page: number;
  page_size: number;
  from: number | null;
  to: number | null;
}

export interface DateRange {
  from: string;
  to: string;
}

export type RangeError = "missing-from" | "missing-to" | "from-after-to";

export function validateRange(range: DateRange): RangeError | null {
  if (!range.from) return "missing-from";
  if (!range.to) return "missing-to";
  const fromMs = parseDateStartOfDay(range.from);
  const toMs = parseDateEndOfDay(range.to);
  if (fromMs > toMs) return "from-after-to";
  return null;
}

export function defaultRange(now: Date = new Date()): DateRange {
  const start = new Date(now.getFullYear(), now.getMonth(), 1);
  return {
    from: toIsoDate(start),
    to: toIsoDate(now),
  };
}

export function buildStatementPath(
  accountId: string,
  range: DateRange,
  page: number,
  pageSize: number,
): string {
  const fromMs = parseDateStartOfDay(range.from);
  const toMs = parseDateEndOfDay(range.to);
  const params = new URLSearchParams({
    from: String(fromMs),
    to: String(toMs),
    page: String(page),
    page_size: String(pageSize),
  });
  return `/accounts/${encodeURIComponent(accountId)}/statement?${params.toString()}`;
}

const CSV_HEADERS = [
  "Posted At",
  "Entry ID",
  "Transaction ID",
  "Type",
  "Amount",
  "Currency",
  "Running Balance",
  "Description",
];

export function entriesToCsv(
  entries: StatementEntry[],
  meta?: { account_name?: string; opening_balance?: number; closing_balance?: number; currency?: string },
): string {
  const lines: string[] = [];
  if (meta?.account_name) {
    lines.push(`# Account: ${csvEscape(meta.account_name)}`);
  }
  if (meta?.currency) {
    lines.push(`# Currency: ${csvEscape(meta.currency)}`);
  }
  if (meta && typeof meta.opening_balance === "number") {
    lines.push(`# Opening Balance (minor units): ${meta.opening_balance}`);
  }
  if (meta && typeof meta.closing_balance === "number") {
    lines.push(`# Closing Balance (minor units): ${meta.closing_balance}`);
  }
  lines.push(CSV_HEADERS.join(","));
  for (const e of entries) {
    lines.push(
      [
        new Date(e.posted_at).toISOString(),
        e.entry_id,
        e.txn_id,
        e.entry_type,
        String(e.amount),
        e.currency,
        String(e.running_balance),
        e.description ?? "",
      ]
        .map(csvEscape)
        .join(","),
    );
  }
  return lines.join("\r\n") + "\r\n";
}

export function csvFilename(accountName: string, range: DateRange): string {
  const safe = accountName.replace(/[^a-zA-Z0-9_-]+/g, "_").replace(/^_+|_+$/g, "") || "account";
  return `${safe}_statement_${range.from}_to_${range.to}.csv`;
}

function csvEscape(value: string): string {
  if (/[",\r\n]/.test(value)) {
    return `"${value.replace(/"/g, '""')}"`;
  }
  return value;
}

function parseDateStartOfDay(yyyyMmDd: string): number {
  const [y, m, d] = yyyyMmDd.split("-").map(Number);
  return new Date(y, (m || 1) - 1, d || 1, 0, 0, 0, 0).getTime();
}

function parseDateEndOfDay(yyyyMmDd: string): number {
  const [y, m, d] = yyyyMmDd.split("-").map(Number);
  return new Date(y, (m || 1) - 1, d || 1, 23, 59, 59, 999).getTime();
}

function toIsoDate(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}
