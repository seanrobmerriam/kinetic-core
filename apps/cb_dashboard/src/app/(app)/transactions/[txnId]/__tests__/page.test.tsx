import { act } from "react";
import userEvent from "@testing-library/user-event";
import { renderWithProviders, screen, waitFor } from "@/test-utils/render";
import { api } from "@/lib/api";
import type { LedgerEntry, Transaction } from "@/lib/types";
import TransactionDetailPage from "../page";

jest.mock("@/lib/api", () => ({
  api: jest.fn(),
}));

const mockApi = api as jest.MockedFunction<typeof api>;

function buildTxn(overrides: Partial<Transaction> = {}): Transaction {
  return {
    txn_id: "txn-aaa-111",
    idempotency_key: "key-001",
    txn_type: "transfer",
    status: "posted",
    amount: 12500,
    currency: "USD",
    source_account_id: "acct-src",
    dest_account_id: "acct-dst",
    description: "Coffee fund transfer",
    created_at: 1700000000,
    posted_at: 1700000010,
    ...overrides,
  } as Transaction;
}

function entry(overrides: Partial<LedgerEntry>): LedgerEntry {
  return {
    entry_id: "entry-x",
    txn_id: "txn-aaa-111",
    account_id: "acct-src",
    entry_type: "debit",
    amount: 12500,
    currency: "USD",
    description: "",
    posted_at: 1700000010,
    ...overrides,
  } as LedgerEntry;
}

const balancedEntries: LedgerEntry[] = [
  entry({ entry_id: "e1", account_id: "acct-src", entry_type: "debit", amount: 12500 }),
  entry({ entry_id: "e2", account_id: "acct-dst", entry_type: "credit", amount: 12500 }),
];

const unbalancedEntries: LedgerEntry[] = [
  entry({ entry_id: "e1", account_id: "acct-src", entry_type: "debit", amount: 10000 }),
  entry({ entry_id: "e2", account_id: "acct-dst", entry_type: "credit", amount: 12500 }),
];

function setupApiMock(txn: Transaction, entries: LedgerEntry[]) {
  mockApi.mockImplementation(async (method: string, path: string) => {
    if (method === "GET" && path === `/transactions/${txn.txn_id}`) {
      return txn as never;
    }
    if (method === "GET" && path === `/transactions/${txn.txn_id}/entries`) {
      return { items: entries, total: entries.length, page: 1, page_size: 50 } as never;
    }
    if (method === "POST" && path === `/transactions/${txn.txn_id}/reverse`) {
      return { txn_id: "rev-1" } as never;
    }
    throw new Error(`Unexpected api call: ${method} ${path}`);
  });
}

async function renderPage(txn: Transaction) {
  const params = Promise.resolve({ txnId: txn.txn_id });
  let result: ReturnType<typeof renderWithProviders>;
  await act(async () => {
    result = renderWithProviders(<TransactionDetailPage params={params} />);
  });
  await waitFor(() =>
    expect(
      screen.getAllByText(new RegExp(txn.txn_id)).length,
    ).toBeGreaterThan(0),
  );
  return result!;
}

describe("TransactionDetailPage — GAP-003+004", () => {
  beforeEach(() => {
    mockApi.mockReset();
  });

  it("renders header, details, and ledger entries from the API", async () => {
    const txn = buildTxn();
    setupApiMock(txn, balancedEntries);
    await renderPage(txn);

    expect(
      screen.getByRole("heading", { name: /^transaction$/i }),
    ).toBeInTheDocument();
    expect(screen.getByText(/Coffee fund transfer/i)).toBeInTheDocument();
    // Both entry IDs appear in the entries table
    expect(screen.getByText("e1")).toBeInTheDocument();
    expect(screen.getByText("e2")).toBeInTheDocument();
  });

  it("does not show a balance warning when entries balance", async () => {
    const txn = buildTxn();
    setupApiMock(txn, balancedEntries);
    await renderPage(txn);

    expect(
      screen.queryByText(/ledger entries do not balance/i),
    ).not.toBeInTheDocument();
  });

  it("shows a red warning when entries do not balance", async () => {
    const txn = buildTxn();
    setupApiMock(txn, unbalancedEntries);
    await renderPage(txn);

    expect(
      await screen.findByText(/ledger entries do not balance/i),
    ).toBeInTheDocument();
  });

  it("shows the Reverse button when status is posted", async () => {
    const txn = buildTxn({ status: "posted" });
    setupApiMock(txn, balancedEntries);
    await renderPage(txn);

    expect(
      screen.getByRole("button", { name: /reverse transaction/i }),
    ).toBeInTheDocument();
  });

  it("hides the Reverse button when status is reversed", async () => {
    const txn = buildTxn({ status: "reversed" });
    setupApiMock(txn, balancedEntries);
    await renderPage(txn);

    expect(
      screen.queryByRole("button", { name: /reverse transaction/i }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByText(/this transaction has been reversed/i),
    ).toBeInTheDocument();
  });

  it("hides the Reverse button when status is pending", async () => {
    const txn = buildTxn({ status: "pending" });
    setupApiMock(txn, balancedEntries);
    await renderPage(txn);

    expect(
      screen.queryByRole("button", { name: /reverse transaction/i }),
    ).not.toBeInTheDocument();
  });

  it("opens a confirmation dialog and POSTs to /reverse on confirm", async () => {
    const txn = buildTxn({ status: "posted" });
    setupApiMock(txn, balancedEntries);
    await renderPage(txn);
    const user = userEvent.setup();

    await user.click(
      screen.getByRole("button", { name: /reverse transaction/i }),
    );
    expect(
      await screen.findByRole("dialog", { name: /reverse transaction\?/i }),
    ).toBeInTheDocument();

    const confirmBtn = await screen.findByRole("button", {
      name: /^reverse$/i,
    });
    await user.click(confirmBtn);

    await waitFor(() => {
      expect(mockApi).toHaveBeenCalledWith(
        "POST",
        `/transactions/${txn.txn_id}/reverse`,
      );
    });
  });

  it("does not call /reverse when the user cancels the confirmation", async () => {
    const txn = buildTxn({ status: "posted" });
    setupApiMock(txn, balancedEntries);
    await renderPage(txn);
    const user = userEvent.setup();

    await user.click(
      screen.getByRole("button", { name: /reverse transaction/i }),
    );
    const cancelBtn = await screen.findByRole("button", { name: /cancel/i });
    await user.click(cancelBtn);

    await waitFor(() =>
      expect(
        screen.queryByRole("dialog", { name: /reverse transaction\?/i }),
      ).not.toBeInTheDocument(),
    );

    const reverseCalls = mockApi.mock.calls.filter(
      ([method, path]) =>
        method === "POST" && path === `/transactions/${txn.txn_id}/reverse`,
    );
    expect(reverseCalls).toHaveLength(0);
  });
});
