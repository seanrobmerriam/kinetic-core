import { render, waitFor } from "@testing-library/react";
import { MantineProvider } from "@mantine/core";
import AppLayout from "../layout";
import { useAuth } from "@/lib/auth";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { usePathname } from "next/navigation";

const mockReplace = jest.fn();

jest.mock("next/navigation", () => ({
  useRouter: () => ({ replace: mockReplace, refresh: jest.fn() }),
  usePathname: jest.fn(),
}));

jest.mock("@/lib/auth", () => ({
  useAuth: jest.fn(),
}));

jest.mock("@/lib/notify", () => ({
  useNotify: jest.fn(),
}));

jest.mock("@/lib/refresh", () => ({
  useRefresh: jest.fn(),
}));

jest.mock("@/components/Header", () => ({
  Header: ({ canAccessAdmin }: { canAccessAdmin: boolean }) => (
    <div data-testid="header" data-admin={canAccessAdmin ? "yes" : "no"} />
  ),
}));

jest.mock("@/components/Sidebar", () => ({
  Sidebar: () => <div data-testid="sidebar" />,
}));

jest.mock("@/components/Alerts", () => ({
  Alerts: () => <div data-testid="alerts" />,
}));

const mockUsePathname = usePathname as unknown as jest.Mock;
const mockUseAuth = useAuth as unknown as jest.Mock;
const mockUseNotify = useNotify as unknown as jest.Mock;
const mockUseRefresh = useRefresh as unknown as jest.Mock;

describe("AppLayout RBAC route guards", () => {
  beforeEach(() => {
    mockReplace.mockReset();
    mockUsePathname.mockReset();
    mockUseNotify.mockReturnValue({ clear: jest.fn() });
    mockUseRefresh.mockReturnValue({ bump: jest.fn() });
  });

  it("redirects unauthorized users away from /users", async () => {
    mockUsePathname.mockReturnValue("/users");
    mockUseAuth.mockReturnValue({
      state: {
        status: "authenticated",
        user: { email: "ops@example.com", role: "operations" },
      },
      hasAnyPermission: () => true,
      hasPermission: (permission: string) => permission !== "user.read",
    });

    render(
      <MantineProvider>
        <AppLayout>
          <div>content</div>
        </AppLayout>
      </MantineProvider>,
    );

    await waitFor(() => {
      expect(mockReplace).toHaveBeenCalledWith("/dashboard");
    });
  });

  it("does not redirect when required permission is present", async () => {
    mockUsePathname.mockReturnValue("/roles");
    mockUseAuth.mockReturnValue({
      state: {
        status: "authenticated",
        user: { email: "ops@example.com", role: "operations" },
      },
      hasAnyPermission: () => true,
      hasPermission: () => true,
    });

    render(
      <MantineProvider>
        <AppLayout>
          <div>content</div>
        </AppLayout>
      </MantineProvider>,
    );

    await waitFor(() => {
      expect(mockReplace).not.toHaveBeenCalledWith("/dashboard");
    });
  });
});
