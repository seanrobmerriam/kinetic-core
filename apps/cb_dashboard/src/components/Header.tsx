"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import {
  ActionIcon,
  AppShell,
  Avatar,
  Badge,
  Group,
  Text,
  Title,
  Tooltip,
} from "@mantine/core";
import {
  IconLogout,
  IconMoon,
  IconRefresh,
  IconSun,
  IconUpload,
} from "@tabler/icons-react";
import { useAuth } from "@/lib/auth";
import { useNotify } from "@/lib/notify";
import { useTheme } from "@/lib/theme";
import { api } from "@/lib/api";
import { capitalize } from "@/lib/format";

const PAGE_TITLES: Record<string, string> = {
  dashboard: "Dashboard",
  customers: "Customers",
  accounts: "Accounts",
  "account-detail": "Account Details",
  transactions: "Transactions",
  ledger: "Ledger",
  products: "Products",
  loans: "Loans",
  settings: "Settings",
  transfer: "Transfer Funds",
  deposit: "Deposit / Withdraw",
};

const PAGE_SUBTITLES: Record<string, string> = {
  dashboard: "Operational overview",
  customers: "Manage parties and onboarding",
  accounts: "Customer accounts and balances",
  "account-detail": "Account activity and holds",
  transactions: "Payments across all accounts",
  ledger: "Posted ledger entries",
  products: "Savings and loan products",
  loans: "Loan origination and servicing",
  settings: "Workspace preferences",
  transfer: "Move money between accounts",
  deposit: "Cash in and out",
};

function pageKey(pathname: string): string {
  if (pathname.startsWith("/accounts/") && pathname.length > "/accounts/".length) {
    return "account-detail";
  }
  return pathname.split("/")[1] || "dashboard";
}

export function Header({ onRefresh }: { onRefresh?: () => void }) {
  const pathname = usePathname() ?? "/";
  const router = useRouter();
  const { state, logout, devToolsEnabled, setDevToolsEnabled } = useAuth();
  const { theme, toggle } = useTheme();
  const { setError, setSuccess } = useNotify();
  const [mockImporting, setMockImporting] = useState(false);

  useEffect(() => {
    if (state.status !== "authenticated") return;
    let cancelled = false;
    (async () => {
      try {
        const result = await api<{ enabled: boolean }>("GET", "/dev/mock-import");
        if (!cancelled) setDevToolsEnabled(Boolean(result?.enabled));
      } catch {
        if (!cancelled) setDevToolsEnabled(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [state.status, setDevToolsEnabled]);

  const importMock = async () => {
    if (mockImporting || !devToolsEnabled) return;
    setMockImporting(true);
    try {
      const resp = await api<{ summary: Record<string, number> }>(
        "POST",
        "/dev/mock-import",
        {},
      );
      const created = resp?.summary?.transactions_created ?? 0;
      const existing = resp?.summary?.transactions_existing ?? 0;
      setSuccess(
        `Mock data imported (transactions created: ${created}, existing: ${existing})`,
      );
      onRefresh?.();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setMockImporting(false);
    }
  };

  const refresh = () => {
    if (onRefresh) onRefresh();
    else router.refresh();
  };

  const key = pageKey(pathname);
  const title = PAGE_TITLES[key] ?? "Dashboard";
  const subtitle = PAGE_SUBTITLES[key] ?? "";
  const userInitial =
    state.status === "authenticated" && state.user
      ? state.user.email.charAt(0).toUpperCase()
      : "?";

  return (
    <AppShell.Header>
      <Group h="100%" px="lg" justify="space-between" wrap="nowrap">
        <div>
          <Title order={3} fw={600}>
            {title}
          </Title>
          {subtitle && (
            <Text size="sm" c="dimmed">
              {subtitle}
            </Text>
          )}
        </div>

        <Group gap="xs" wrap="nowrap">
          {state.status === "authenticated" && state.user && (
            <Group
              gap="xs"
              data-testid="current-user"
              wrap="nowrap"
              visibleFrom="sm"
            >
              <Avatar
                color="indigo"
                radius="xl"
                size="sm"
                variant="gradient"
                gradient={{ from: "indigo", to: "violet" }}
              >
                {userInitial}
              </Avatar>
              <div>
                <Text size="xs" fw={600} lh={1.1}>
                  {state.user.email}
                </Text>
                <Badge size="xs" variant="light" color="gray">
                  {capitalize(state.user.role)}
                </Badge>
              </div>
            </Group>
          )}

          {devToolsEnabled && (
            <Tooltip label="Import mock data">
              <ActionIcon
                variant="default"
                size="lg"
                data-testid="mock-import-button"
                onClick={importMock}
                disabled={mockImporting}
                loading={mockImporting}
              >
                <IconUpload size={18} />
              </ActionIcon>
            </Tooltip>
          )}

          <Tooltip label="Toggle theme">
            <ActionIcon
              variant="default"
              size="lg"
              data-testid="theme-toggle"
              onClick={toggle}
            >
              {theme === "dark" ? <IconSun size={18} /> : <IconMoon size={18} />}
            </ActionIcon>
          </Tooltip>

          <Tooltip label="Refresh">
            <ActionIcon variant="default" size="lg" onClick={refresh}>
              <IconRefresh size={18} />
            </ActionIcon>
          </Tooltip>

          <Tooltip label="Sign out">
            <ActionIcon
              variant="default"
              size="lg"
              data-testid="logout-button"
              onClick={() => void logout()}
            >
              <IconLogout size={18} />
            </ActionIcon>
          </Tooltip>
        </Group>
      </Group>
    </AppShell.Header>
  );
}
