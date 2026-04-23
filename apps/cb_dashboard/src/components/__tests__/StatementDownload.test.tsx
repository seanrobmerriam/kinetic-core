import { act } from "react";
import { renderWithProviders, screen, fireEvent, waitFor } from "@/test-utils/render";
import { StatementDownload } from "@/components/StatementDownload";
import { api, ApiError } from "@/lib/api";
import { useNotify } from "@/lib/notify";

jest.mock("@/lib/api", () => {
  const actual = jest.requireActual("@/lib/api");
  return {
    ...actual,
    api: jest.fn(),
  };
});

const mockApi = api as unknown as jest.Mock;

function NotifyProbe() {
  const { error, success } = useNotify();
  return (
    <div>
      <div data-testid="notify-error">{error}</div>
      <div data-testid="notify-success">{success}</div>
    </div>
  );
}

function openPopover() {
  fireEvent.click(screen.getByRole("button", { name: /download statement/i }));
}

async function setRange(from: string, to: string) {
  const fromInput = await screen.findByTestId("statement-from");
  const toInput = await screen.findByTestId("statement-to");
  fireEvent.change(fromInput, { target: { value: from } });
  fireEvent.change(toInput, { target: { value: to } });
}

describe("StatementDownload", () => {
  beforeEach(() => {
    mockApi.mockReset();
  });

  it("disables Download when from is after to", async () => {
    renderWithProviders(
      <StatementDownload accountId="acc1" accountName="Checking" />,
    );
    openPopover();
    await setRange("2024-02-10", "2024-02-01");
    const downloadBtn = await screen.findByTestId("statement-submit");
    expect(downloadBtn).toHaveAttribute("data-disabled");
    expect(
      await screen.findByText(/start date must be on or before/i),
    ).toBeInTheDocument();
    fireEvent.click(downloadBtn);
    expect(mockApi).not.toHaveBeenCalled();
  });

  it("calls the statement endpoint and triggers a download on success", async () => {
    mockApi.mockResolvedValue({
      account_id: "acc1",
      party_id: "p1",
      name: "Checking",
      currency: "USD",
      current_balance: 0,
      opening_balance: 0,
      closing_balance: 100,
      entries: [
        {
          entry_id: "e1",
          txn_id: "t1",
          account_id: "acc1",
          entry_type: "credit",
          amount: 100,
          currency: "USD",
          description: "Test",
          posted_at: 1700000000000,
          running_balance: 100,
        },
      ],
      total: 1,
      page: 1,
      page_size: 200,
      from: 0,
      to: 0,
    });

    const trigger = jest.fn();
    renderWithProviders(
      <StatementDownload
        accountId="acc1"
        accountName="Checking"
        triggerDownload={trigger}
      />,
    );
    openPopover();
    await setRange("2024-02-01", "2024-02-29");

    await act(async () => {
      fireEvent.click(await screen.findByTestId("statement-submit"));
    });

    await waitFor(() => expect(mockApi).toHaveBeenCalledTimes(1));
    const [method, path] = mockApi.mock.calls[0];
    expect(method).toBe("GET");
    expect(path).toMatch(/^\/accounts\/acc1\/statement\?/);
    expect(path).toContain("page=1");
    expect(path).toContain("page_size=200");
    expect(path).toContain(`from=${new Date(2024, 1, 1, 0, 0, 0, 0).getTime()}`);
    expect(path).toContain(`to=${new Date(2024, 1, 29, 23, 59, 59, 999).getTime()}`);
    expect(trigger).toHaveBeenCalledTimes(1);
    const [blob, filename] = trigger.mock.calls[0];
    expect(blob).toBeInstanceOf(Blob);
    expect(filename).toBe("Checking_statement_2024-02-01_to_2024-02-29.csv");
  });

  it("surfaces an error toast when the API fails", async () => {
    mockApi.mockRejectedValue(new ApiError("boom", 500));
    renderWithProviders(
      <>
        <StatementDownload
          accountId="acc1"
          accountName="Checking"
          triggerDownload={jest.fn()}
        />
        <NotifyProbe />
      </>,
    );
    openPopover();
    await setRange("2024-02-01", "2024-02-29");

    await act(async () => {
      fireEvent.click(await screen.findByTestId("statement-submit"));
    });

    await waitFor(() =>
      expect(screen.getByTestId("notify-error")).toHaveTextContent(
        /statement download failed: boom/i,
      ),
    );
  });
});
