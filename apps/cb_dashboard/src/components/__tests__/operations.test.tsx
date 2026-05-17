/**
 * Tests for operations dashboard components
 */

import { renderWithProviders, screen } from "@/test-utils/render";
import { SLOCard } from "../SLOCard";
import { AlertItem, AlertsList } from "../AlertItem";
import type { SLOObjective, SLOAlert } from "@/lib/types/operations";

describe("SLOCard", () => {
  it("renders healthy objective", () => {
    const objective: SLOObjective = {
      id: "auth_login",
      sli: "availability",
      status: "healthy",
      target_pct: 99.95,
      description: "Authentication login success ratio",
      value: {
        availability_pct: 99.98,
        total_requests: 1000,
        error_5xx: 2,
      },
    };

    renderWithProviders(<SLOCard objective={objective} />);
    expect(screen.getAllByText("Healthy").length).toBeGreaterThan(0);
    expect(screen.getByText("Authentication login success ratio")).toBeInTheDocument();
  });

  it("renders breached objective", () => {
    const objective: SLOObjective = {
      id: "funds_transfer",
      sli: "availability",
      status: "breached",
      target_pct: 99.90,
      description: "Transfer processing success ratio",
      value: {
        availability_pct: 99.85,
        total_requests: 500,
        error_5xx: 75,
      },
    };

    renderWithProviders(<SLOCard objective={objective} />);
    expect(screen.getByText("Breached")).toBeInTheDocument();
  });

  it("renders insufficient data objective", () => {
    const objective: SLOObjective = {
      id: "core_reads",
      sli: "availability",
      status: "insufficient_data",
      target_pct: 99.50,
      description: "Core read API success ratio",
      value: {
        availability_pct: 100.0,
        total_requests: 5,
        error_5xx: 0,
      },
    };

    renderWithProviders(<SLOCard objective={objective} />);
    expect(screen.getByText("Insufficient Data")).toBeInTheDocument();
  });

  it("renders dependency health objective", () => {
    const objective: SLOObjective = {
      id: "platform_dependencies",
      sli: "dependency_health",
      status: "healthy",
      target_status: "ok",
      description: "Dependency health and latency budget",
      value: {
        dependency_status: "ok",
        max_latency_ms: 100,
        checks: [
          {
            service: "mnesia",
            status: "ok",
            latency_ms: 50,
          },
        ],
      },
    };

    renderWithProviders(<SLOCard objective={objective} />);
    expect(screen.getAllByText("Healthy").length).toBeGreaterThan(0);
    expect(screen.getByText("mnesia: OK (50ms)")).toBeInTheDocument();
  });
});

describe("AlertItem", () => {
  it("renders firing alert", () => {
    const alert: SLOAlert = {
      alert_id: "auth_login_breached",
      objective: "auth_login",
      severity: "critical",
      state: "firing",
      message: "Availability below target: 99.900% < 99.950%",
    };

    renderWithProviders(<AlertItem alert={alert} />);
    expect(screen.getByText("Critical")).toBeInTheDocument();
    expect(screen.getByText("Firing")).toBeInTheDocument();
    expect(screen.getByText("auth_login")).toBeInTheDocument();
  });

  it("renders resolved alert", () => {
    const alert: SLOAlert = {
      alert_id: "auth_login_resolved",
      objective: "auth_login",
      severity: "info",
      state: "resolved",
      message: "Objective within target",
    };

    renderWithProviders(<AlertItem alert={alert} />);
    expect(screen.getByText("Info")).toBeInTheDocument();
    expect(screen.getByText("Resolved")).toBeInTheDocument();
  });
});

describe("AlertsList", () => {
  it("renders no alerts message when list is empty", () => {
    renderWithProviders(<AlertsList alerts={[]} />);
    expect(screen.getByText("All systems operational")).toBeInTheDocument();
  });

  it("groups alerts by state", () => {
    const alerts: SLOAlert[] = [
      {
        alert_id: "auth_login_firing",
        objective: "auth_login",
        severity: "critical",
        state: "firing",
        message: "Critical issue",
      },
      {
        alert_id: "funds_transfer_monitoring",
        objective: "funds_transfer",
        severity: "info",
        state: "monitoring",
        message: "Monitoring in progress",
      },
      {
        alert_id: "core_reads_resolved",
        objective: "core_reads",
        severity: "info",
        state: "resolved",
        message: "Issue resolved",
      },
    ];

    renderWithProviders(<AlertsList alerts={alerts} />);
    expect(screen.getByText(/Active Alerts/)).toBeInTheDocument();
    expect(screen.getAllByText(/Monitoring/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Resolved/).length).toBeGreaterThan(0);
  });
});
