import type { ReactNode } from "react";
import { render, screen } from "@testing-library/react";
import { AppShell, MantineProvider } from "@mantine/core";
import { Header } from "@/components/Header";
import { Sidebar } from "@/components/Sidebar";
import { useAuth } from "@/lib/auth";
import { useNotify } from "@/lib/notify";
import { useTheme } from "@/lib/theme";
import { api } from "@/lib/api";

jest.mock("@/lib/auth", () => ({
  useAuth: jest.fn(),
}));

jest.mock("@/lib/notify", () => ({
  useNotify: jest.fn(),
}));

jest.mock("@/lib/theme", () => ({
  useTheme: jest.fn(),
}));

jest.mock("@/lib/api", () => ({
  api: jest.fn(),
}));

jest.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: jest.fn() }),
  usePathname: () => "/dashboard",
}));

const mockUseAuth = useAuth as unknown as jest.Mock;
const mockUseNotify = useNotify as unknown as jest.Mock;
const mockUseTheme = useTheme as unknown as jest.Mock;
const mockApi = api as unknown as jest.Mock;

function renderInAppShell(node: ReactNode) {
  return render(
    <MantineProvider>
      <AppShell header={{ height: 95 }} navbar={{ width: 260, breakpoint: "sm" }}>
        {node}
        <AppShell.Main />
      </AppShell>
    </MantineProvider>,
  );
}

describe("RBAC guard UI", () => {
  beforeEach(() => {
    mockUseAuth.mockReset();
    mockUseNotify.mockReturnValue({ setError: jest.fn(), setSuccess: jest.fn() });
    mockUseTheme.mockReturnValue({ theme: "light", toggle: jest.fn() });
    mockApi.mockResolvedValue({ enabled: false });
  });

  it("hides admin tab when user cannot access admin area", () => {
    mockUseAuth.mockReturnValue({
      state: {
        status: "authenticated",
        user: { email: "ops@example.com", role: "operations" },
      },
      logout: jest.fn(),
      devToolsEnabled: false,
      setDevToolsEnabled: jest.fn(),
    });

    renderInAppShell(
      <Header activeTab="banking" setActiveTab={jest.fn()} canAccessAdmin={false} />,
    );

    expect(screen.queryByRole("tab", { name: /admin/i })).not.toBeInTheDocument();
  });

  it("shows only permitted admin navigation links", () => {
    mockUseAuth.mockReturnValue({
      state: {
        status: "authenticated",
        user: { email: "ops@example.com", role: "operations" },
      },
      hasAnyPermission: () => true,
      hasPermission: (permission: string) => permission === "role.read",
    });

    renderInAppShell(<Sidebar activeTab="admin" />);

    expect(screen.getByRole("link", { name: "Roles" })).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Users" })).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Permissions" })).not.toBeInTheDocument();
  });

  it("falls back to banking navigation when admin area is not accessible", () => {
    mockUseAuth.mockReturnValue({
      state: {
        status: "authenticated",
        user: { email: "reader@example.com", role: "read_only" },
      },
      hasAnyPermission: () => false,
      hasPermission: () => false,
    });

    renderInAppShell(<Sidebar activeTab="admin" />);

    expect(screen.getByRole("link", { name: "Dashboard" })).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Users" })).not.toBeInTheDocument();
  });
});
