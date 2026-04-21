"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { AppShell, Box, NavLink, Stack, Text, ThemeIcon } from "@mantine/core";
import {
  IconBook,
  IconBuildingBank,
  IconCash,
  IconLayoutDashboard,
  IconReceipt,
  IconReportMoney,
  IconSettings,
  IconTransfer,
  IconUsers,
  IconWallet,
  type Icon,
} from "@tabler/icons-react";

const NAV_ITEMS: { id: string; label: string; Icon: Icon }[] = [
  { id: "dashboard", label: "Dashboard", Icon: IconLayoutDashboard },
  { id: "customers", label: "Customers", Icon: IconUsers },
  { id: "accounts", label: "Accounts", Icon: IconBuildingBank },
  { id: "transactions", label: "Transactions", Icon: IconReceipt },
  { id: "ledger", label: "Ledger", Icon: IconBook },
  { id: "products", label: "Products", Icon: IconWallet },
  { id: "loans", label: "Loans", Icon: IconReportMoney },
  { id: "settings", label: "Settings", Icon: IconSettings },
];

const QUICK_ACTIONS: { id: string; label: string; Icon: Icon }[] = [
  { id: "transfer", label: "Transfer Funds", Icon: IconTransfer },
  { id: "deposit", label: "Deposit / Withdraw", Icon: IconCash },
];

export function Sidebar() {
  const pathname = usePathname() ?? "";

  const isActive = (id: string) => {
    if (id === "accounts") return pathname.startsWith("/accounts");
    return pathname === `/${id}`;
  };

  return (
    <AppShell.Navbar p="md">
      <Stack gap="xs" mb="md">
        <Box style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <ThemeIcon
            size={40}
            radius="md"
            variant="gradient"
            gradient={{ from: "indigo", to: "violet" }}
          >
            <IconBuildingBank size={22} />
          </ThemeIcon>
          <Box>
            <Text fw={700} size="md" lh={1.1}>
              IronLedger
            </Text>
            <Text size="xs" c="dimmed" tt="uppercase" fw={600}>
              Core Banking
            </Text>
          </Box>
        </Box>
      </Stack>

      <Text size="xs" c="dimmed" tt="uppercase" fw={700} mb={6} mt="sm">
        Menu
      </Text>
      <Stack gap={4}>
        {NAV_ITEMS.map((item) => (
          <NavLink
            key={item.id}
            component={Link}
            href={`/${item.id}`}
            data-testid={`nav-${item.id}`}
            label={item.label}
            leftSection={<item.Icon size={18} stroke={1.7} />}
            active={isActive(item.id)}
            variant="filled"
          />
        ))}
      </Stack>

      <Text size="xs" c="dimmed" tt="uppercase" fw={700} mb={6} mt="lg">
        Quick Actions
      </Text>
      <Stack gap={4}>
        {QUICK_ACTIONS.map((a) => (
          <NavLink
            key={a.id}
            component={Link}
            href={`/${a.id}`}
            data-testid={`quick-${a.id}`}
            label={a.label}
            leftSection={<a.Icon size={18} stroke={1.7} />}
            active={pathname === `/${a.id}`}
            variant="light"
          />
        ))}
      </Stack>
    </AppShell.Navbar>
  );
}
