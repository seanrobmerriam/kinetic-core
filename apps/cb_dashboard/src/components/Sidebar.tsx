"use client";

import Link from "next/link";
import {
  AppShell,
  Avatar,
  Box,
  Divider,
  Group,
  ScrollArea,
  Text,
  UnstyledButton,
} from "@mantine/core";
import {
  IconBook,
  IconBuildingBank,
  IconCash,
  IconChevronRight,
  IconCode,
  IconLayoutDashboard,
  IconReceipt,
  IconReportMoney,
  IconSettings,
  IconShieldCheck,
  IconSitemap,
  IconTransfer,
  IconUsers,
  IconWallet,
  type Icon,
} from "@/components/icons";
import { useAuth } from "@/lib/auth";
import { NavLinksGroup } from "./NavLinksGroup";

interface NavItem {
  label: string;
  icon: Icon;
  href?: string;
  initiallyOpened?: boolean;
  links?: { label: string; href: string }[];
}

const NAV_ITEMS: NavItem[] = [
  { label: "Dashboard", icon: IconLayoutDashboard, href: "/dashboard" },
  { label: "Customers", icon: IconUsers, href: "/customers" },
  { label: "Accounts", icon: IconBuildingBank, href: "/accounts" },
  { label: "Transactions", icon: IconReceipt, href: "/transactions" },
  { label: "Ledger", icon: IconBook, href: "/ledger" },
  {
    label: "Payments & Funds",
    icon: IconTransfer,
    links: [
      { label: "Payments", href: "/payments" },
      { label: "Transfer Funds", href: "/transfer" },
      { label: "Deposit / Withdraw", href: "/deposit" },
    ],
  },
  { label: "Loans", icon: IconReportMoney, href: "/loans" },
  { label: "Compliance", icon: IconShieldCheck, href: "/compliance" },
  { label: "Developer", icon: IconCode, href: "/developer" },
  {
    label: "System",
    icon: IconSettings,
    links: [
      { label: "Channels", href: "/channels" },
      { label: "Products", href: "/products" },
      { label: "Settings", href: "/settings" },
    ],
  },
];

export function Sidebar() {
  const { state } = useAuth();
  const email =
    state.status === "authenticated" && state.user ? state.user.email : "";
  const initial = email ? email.charAt(0).toUpperCase() : "?";
  const role =
    state.status === "authenticated" && state.user ? state.user.role : "";

  const links = NAV_ITEMS.map((item) => (
    <NavLinksGroup {...item} key={item.label} />
  ));

  return (
    <AppShell.Navbar
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100%",
        overflow: "hidden",
      }}
    >
      {/* Header */}
      <Box
        p="md"
        style={{
          borderBottom:
            "1px solid light-dark(var(--mantine-color-gray-3), var(--mantine-color-dark-4))",
        }}
      >
        <Group justify="space-between" wrap="nowrap">
          <Box>
            <Text fw={700} size="md" lh={1.1}>
              Menu
            </Text>
            <Text size="xs" c="dimmed" tt="uppercase" fw={600}>
              Banking Solution
            </Text>
          </Box>
        </Group>
      </Box>

      {/* Scrollable nav links */}
      <ScrollArea style={{ flex: 1 }} px="md" py="xs">
        <Box py={4}>{links}</Box>
      </ScrollArea>

      {/* Footer: user button */}
      <Divider />
      <Box p="md">
        <UnstyledButton
          component={Link}
          href="/settings"
          style={{
            display: "block",
            width: "100%",
            padding: "var(--mantine-spacing-xs)",
            borderRadius: "var(--mantine-radius-sm)",
          }}
        >
          <Group gap="md" align="center" wrap="nowrap">
            <Avatar
              color="indigo"
              radius="xl"
              size="md"
              variant="gradient"
              gradient={{ from: "indigo", to: "violet" }}
            >
              {initial}
            </Avatar>
            <Box style={{ flex: 1, minWidth: 0 }}>
              <Text size="sm" fw={500} truncate>
                {email || "User"}
              </Text>
              <Text size="xs" c="dimmed" tt="capitalize">
                {role || "Staff"}
              </Text>
            </Box>
            <IconChevronRight size={14} stroke={1.5} />
          </Group>
        </UnstyledButton>
      </Box>
    </AppShell.Navbar>
  );
}
