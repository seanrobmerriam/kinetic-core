import type { LedgerEntry, Transaction } from "@/lib/types";

export type EntryType = "debit" | "credit";

export interface CurrencySums {
  debits: number;
  credits: number;
  diff: number;
}

export interface BalanceCheck {
  balanced: boolean;
  sums: Record<string, CurrencySums>;
}

export function entriesAreBalanced(entries: LedgerEntry[]): BalanceCheck {
  const sums: Record<string, CurrencySums> = {};
  for (const e of entries) {
    const ccy = e.currency || "";
    const slot = sums[ccy] ?? { debits: 0, credits: 0, diff: 0 };
    if (e.entry_type === "debit") slot.debits += e.amount;
    else if (e.entry_type === "credit") slot.credits += e.amount;
    sums[ccy] = slot;
  }

  let balanced = entries.length > 0;
  for (const ccy of Object.keys(sums)) {
    const s = sums[ccy];
    s.diff = s.credits - s.debits;
    if (s.diff !== 0) balanced = false;
  }
  return { balanced, sums };
}

export function canReverse(txn: Pick<Transaction, "status">): boolean {
  return txn.status === "posted";
}

export function isReversed(txn: Pick<Transaction, "status">): boolean {
  return txn.status === "reversed";
}
