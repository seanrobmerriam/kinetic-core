import {
  canReverse,
  entriesAreBalanced,
  isReversed,
} from "@/lib/transaction";
import type { LedgerEntry } from "@/lib/types";

function entry(
  partial: Partial<LedgerEntry> & {
    entry_type: "debit" | "credit";
    amount: number;
    currency: string;
  },
): LedgerEntry {
  return {
    entry_id: "e",
    txn_id: "t",
    account_id: "a",
    description: "",
    posted_at: 0,
    ...partial,
  };
}

describe("entriesAreBalanced", () => {
  it("reports unbalanced for empty entries (cannot prove balance)", () => {
    const r = entriesAreBalanced([]);
    expect(r.balanced).toBe(false);
    expect(r.sums).toEqual({});
  });

  it("balances simple debit + credit pair in same currency", () => {
    const r = entriesAreBalanced([
      entry({ entry_type: "debit", amount: 1000, currency: "USD" }),
      entry({ entry_type: "credit", amount: 1000, currency: "USD" }),
    ]);
    expect(r.balanced).toBe(true);
    expect(r.sums.USD).toEqual({ debits: 1000, credits: 1000, diff: 0 });
  });

  it("flags unbalanced when sums diverge", () => {
    const r = entriesAreBalanced([
      entry({ entry_type: "debit", amount: 1000, currency: "USD" }),
      entry({ entry_type: "credit", amount: 999, currency: "USD" }),
    ]);
    expect(r.balanced).toBe(false);
    expect(r.sums.USD.diff).toBe(-1);
  });

  it("balances per currency independently", () => {
    const r = entriesAreBalanced([
      entry({ entry_type: "debit", amount: 500, currency: "USD" }),
      entry({ entry_type: "credit", amount: 500, currency: "USD" }),
      entry({ entry_type: "debit", amount: 200, currency: "EUR" }),
      entry({ entry_type: "credit", amount: 200, currency: "EUR" }),
    ]);
    expect(r.balanced).toBe(true);
    expect(Object.keys(r.sums)).toEqual(expect.arrayContaining(["USD", "EUR"]));
  });

  it("flags unbalanced when one currency balances and another does not", () => {
    const r = entriesAreBalanced([
      entry({ entry_type: "debit", amount: 500, currency: "USD" }),
      entry({ entry_type: "credit", amount: 500, currency: "USD" }),
      entry({ entry_type: "debit", amount: 200, currency: "EUR" }),
      entry({ entry_type: "credit", amount: 100, currency: "EUR" }),
    ]);
    expect(r.balanced).toBe(false);
    expect(r.sums.USD.diff).toBe(0);
    expect(r.sums.EUR.diff).toBe(-100);
  });
});

describe("canReverse / isReversed", () => {
  it("canReverse only when posted", () => {
    expect(canReverse({ status: "posted" })).toBe(true);
    expect(canReverse({ status: "pending" })).toBe(false);
    expect(canReverse({ status: "reversed" })).toBe(false);
    expect(canReverse({ status: "failed" })).toBe(false);
  });

  it("isReversed only when status reversed", () => {
    expect(isReversed({ status: "reversed" })).toBe(true);
    expect(isReversed({ status: "posted" })).toBe(false);
  });
});
