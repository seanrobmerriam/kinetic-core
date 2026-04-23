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
  IconChevronRight,
  IconCode,
  IconFiles,
  IconKey,
  IconLayoutDashboard,
  IconReceipt,
  IconReportMoney,
  IconSettings,
  IconShield,
  IconShieldCheck,
  IconSitemap,
  IconTransfer,
  IconUsers,
  type Icon,
} from "@/components/icons";
import { useAuth } from "@/lib/auth";
import { NavLinksGroup } from "./NavLinksGroup";
import classes from "./Sidebar.module.css";

interface NavItem {
  label: string;
  icon: Icon;
  href?: string;
  initiallyOpened?: boolean;
  links?: { label: string; href: string }[];
}

const BANKING_ITEMS: NavItem[] = [
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
];

const ADMIN_ITEMS: NavItem[] = [
  { label: "Users", icon: IconUsers, href: "/users" },
  { label: "Roles", icon: IconShield, href: "/roles" },
  { label: "Permissions", icon: IconKey, href: "/permissions" },
  { label: "Settings", icon: IconSettings, href: "/settings" },
  { label: "Developer", icon: IconCode, href: "/developer" },
  {
    label: "System",
    icon: IconSitemap,
    links: [
      { label: "Channels", href: "/channels" },
      { label: "Products", href: "/products" },
    ],
  },
  { label: "Logs", icon: IconFiles, href: "/logs" },
];

export function Sidebar({ activeTab }: { activeTab: string }) {
  const { state } = useAuth();
  const email =
    state.status === "authenticated" && state.user ? state.user.email : "";
  const initial = email ? email.charAt(0).toUpperCase() : "?";
  const role =
    state.status === "authenticated" && state.user ? state.user.role : "";

  const items = activeTab === "admin" ? ADMIN_ITEMS : BANKING_ITEMS;

  return (
    <AppShell.Navbar
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100%",
        overflow: "hidden",
      }}
    >
      <ScrollArea style={{ flex: 1 }} px="md" py="xs">
        <Box py={4}>
          {items.map((item) => (
            <NavLinksGroup {...item} key={item.label} />
          ))}
        </Box>
      </ScrollArea>

      {/* Footer: user button */}
      <Divider />
      <Box p="md">
        <UnstyledButton
          component={Link}
          href="/settings"
          className={classes.userButton}
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
