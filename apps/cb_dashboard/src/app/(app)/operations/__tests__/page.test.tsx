import { act } from "react";
import { renderWithProviders, screen, waitFor } from "@/test-utils/render";
import { pollSLOSnapshot } from "@/lib/api/operations";
import OperationsPage from "../page";
import type { SLOSnapshot } from "@/lib/types/operations";

jest.mock("@/lib/api/operations", () => ({
  pollSLOSnapshot: jest.fn(),
}));

const mockPollSLOSnapshot = pollSLOSnapshot as jest.MockedFunction<
  typeof pollSLOSnapshot
>;

function buildSnapshot(): SLOSnapshot {
  return {
    generated_at_ms: Date.now(),
    objectives: [
      {
        id: "auth_login",
        sli: "availability",
        status: "healthy",
        target_pct: 99.95,
        description: "Authentication login success ratio",
        value: {
          availability_pct: 99.99,
          total_requests: 100,
          error_5xx: 1,
        },
      },
      {
        id: "platform_dependencies",
        sli: "dependency_health",
        status: "healthy",
        target_status: "ok",
        description: "Dependency health and latency budget",
        value: {
          dependency_status: "ok",
          max_latency_ms: 25,
          checks: [
            {
              service: "mnesia",
              status: "ok",
              latency_ms: 25,
            },
          ],
        },
      },
    ],
    alerts: [
      {
        alert_id: "auth_login:resolved",
        objective: "auth_login",
        severity: "info",
        state: "resolved",
        message: "Objective within target",
      },
    ],
  };
}

describe("OperationsPage", () => {
  beforeEach(() => {
    mockPollSLOSnapshot.mockReset();
  });

  it("renders SLO objectives and service health checks", async () => {
    mockPollSLOSnapshot.mockResolvedValue(buildSnapshot());

    await act(async () => {
      renderWithProviders(<OperationsPage />);
    });

    await waitFor(() => {
      expect(
        screen.getByRole("heading", { name: /operations dashboard/i }),
      ).toBeInTheDocument();
    });

    expect(screen.getByText(/real-time service health and slo indicators/i)).toBeInTheDocument();
    expect(screen.getByText("Authentication login success ratio")).toBeInTheDocument();
    expect(screen.getByText("mnesia: OK (25ms)")).toBeInTheDocument();
  });

  it("shows a retry state when snapshot cannot be loaded", async () => {
    mockPollSLOSnapshot.mockResolvedValue(null);

    await act(async () => {
      renderWithProviders(<OperationsPage />);
    });

    await waitFor(() => {
      expect(
        screen.getByText(/unable to load operations data/i),
      ).toBeInTheDocument();
    });

    expect(screen.getByRole("button", { name: /retry/i })).toBeInTheDocument();
  });
});
