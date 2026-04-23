import { act } from "react";
import userEvent from "@testing-library/user-event";
import { renderWithProviders, screen, waitFor } from "@/test-utils/render";
import { api } from "@/lib/api";
import type { Party } from "@/lib/types";
import CustomerDetailPage from "../page";

jest.mock("@/lib/api", () => ({
  api: jest.fn(),
}));

const mockApi = api as jest.MockedFunction<typeof api>;

function buildParty(overrides: Partial<Party> = {}): Party {
  return {
    party_id: "party-abc-123",
    full_name: "Jane Doe",
    email: "jane@example.com",
    phone: "+15551234567",
    status: "suspended",
    kyc_status: "approved",
    date_of_birth: "1990-01-01",
    ssn_last4: "1234",
    created_at: 1700000000,
    address: {
      line1: "123 Main St",
      city: "Springfield",
      state: "IL",
      postal_code: "62701",
      country: "US",
    },
    ...overrides,
  } as Party;
}

function setupApiMock(party: Party) {
  mockApi.mockImplementation(async (method: string, path: string) => {
    if (method === "GET" && path === `/parties/${party.party_id}`) {
      return party as never;
    }
    if (method === "GET" && path === `/parties/${party.party_id}/accounts`) {
      return { items: [] } as never;
    }
    if (method === "POST" && path === `/parties/${party.party_id}/reactivate`) {
      return undefined as never;
    }
    throw new Error(`Unexpected api call: ${method} ${path}`);
  });
}

async function renderPage(party: Party) {
  const params = Promise.resolve({ partyId: party.party_id });
  let result: ReturnType<typeof renderWithProviders>;
  await act(async () => {
    result = renderWithProviders(<CustomerDetailPage params={params} />);
  });
  await waitFor(() =>
    expect(screen.getAllByText(party.full_name).length).toBeGreaterThan(0),
  );
  return result!;
}

describe("CustomerDetailPage — GAP-001 reactivate flow", () => {
  beforeEach(() => {
    mockApi.mockReset();
  });

  it("shows the Reactivate button when status is suspended", async () => {
    const party = buildParty({ status: "suspended" });
    setupApiMock(party);
    await renderPage(party);

    expect(
      screen.getByRole("button", { name: /reactivate customer/i }),
    ).toBeInTheDocument();
  });

  it("does not show the Reactivate button for active customers", async () => {
    const party = buildParty({ status: "active" });
    setupApiMock(party);
    await renderPage(party);

    expect(
      screen.queryByRole("button", { name: /reactivate customer/i }),
    ).not.toBeInTheDocument();
  });

  it("does not show the Reactivate button for closed customers", async () => {
    const party = buildParty({ status: "closed" });
    setupApiMock(party);
    await renderPage(party);

    expect(
      screen.queryByRole("button", { name: /reactivate customer/i }),
    ).not.toBeInTheDocument();
  });

  it("opens a confirmation modal when Reactivate is clicked", async () => {
    const party = buildParty({ status: "suspended" });
    setupApiMock(party);
    await renderPage(party);
    const user = userEvent.setup();

    await user.click(
      screen.getByRole("button", { name: /reactivate customer/i }),
    );

    expect(
      await screen.findByRole("dialog", { name: /reactivate customer\?/i }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /^reactivate$/i }),
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /cancel/i })).toBeInTheDocument();
  });

  it("closes the modal without calling the API on Cancel", async () => {
    const party = buildParty({ status: "suspended" });
    setupApiMock(party);
    await renderPage(party);
    const user = userEvent.setup();

    await user.click(
      screen.getByRole("button", { name: /reactivate customer/i }),
    );
    const cancelBtn = await screen.findByRole("button", { name: /cancel/i });
    await user.click(cancelBtn);

    await waitFor(() =>
      expect(
        screen.queryByRole("dialog", { name: /reactivate customer\?/i }),
      ).not.toBeInTheDocument(),
    );

    const reactivateCalls = mockApi.mock.calls.filter(
      ([method, path]) =>
        method === "POST" && path === `/parties/${party.party_id}/reactivate`,
    );
    expect(reactivateCalls).toHaveLength(0);
  });

  it("POSTs to /parties/:id/reactivate when the modal is confirmed", async () => {
    const party = buildParty({ status: "suspended" });
    setupApiMock(party);
    await renderPage(party);
    const user = userEvent.setup();

    await user.click(
      screen.getByRole("button", { name: /reactivate customer/i }),
    );
    const confirmBtn = await screen.findByRole("button", {
      name: /^reactivate$/i,
    });
    await user.click(confirmBtn);

    await waitFor(() => {
      expect(mockApi).toHaveBeenCalledWith(
        "POST",
        `/parties/${party.party_id}/reactivate`,
      );
    });
  });
});
