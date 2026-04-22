"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  Anchor,
  Badge,
  Box,
  Card,
  Group,
  Paper,
  SegmentedControl,
  SimpleGrid,
  Stack,
  Table,
  Text,
  ThemeIcon,
  Title,
  UnstyledButton,
  useMantineTheme,
} from "@mantine/core";
import {
  IconArrowDown,
  IconArrowRight,
  IconArrowUp,
  IconBook,
  IconBuildingBank,
  IconCashBanknote,
  IconClock,
  IconCoin,
  IconReceipt,
  IconRepeat,
  IconReportMoney,
  IconShield,
  IconUsers,
  IconWallet,
  type Icon,
} from "@tabler/icons-react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { formatAmount, formatNumber, formatTimestamp } from "@/lib/format";
import type { Account, LedgerEntry, Party, Transaction } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

const quickActions = [
  { label: "Accounts", href: "/accounts", icon: IconBuildingBank, color: "indigo" },
  { label: "Customers", href: "/customers", icon: IconUsers, color: "violet" },
  { label: "Transfers", href: "/transfer", icon: IconRepeat, color: "blue" },
  { label: "Payments", href: "/payments", icon: IconCoin, color: "red" },
  { label: "Deposit", href: "/deposit", icon: IconCashBanknote, color: "green" },
  { label: "Transactions", href: "/transactions", icon: IconReceipt, color: "teal" },
  { label: "Loans", href: "/loans", icon: IconReportMoney, color: "orange" },
  { label: "Ledger", href: "/ledger", icon: IconBook, color: "cyan" },
  { label: "Compliance", href: "/compliance", icon: IconShield, color: "pink" },
] as const;

function QuickActionsGrid() {
  const theme = useMantineTheme();
  return (
    <Card withBorder radius="md" padding="lg" style={{ backgroundColor: "light-dark(var(--mantine-color-gray-0), var(--mantine-color-dark-7))" }}>
      <Group justify="space-between">
        <Text fw={500} fz="lg">Quick Actions</Text>
        <Anchor component={Link} href="/accounts" c="inherit" size="xs">View all</Anchor>
      </Group>
      <SimpleGrid cols={3} mt="md" spacing="md">
        {quickActions.map(({ label, href, icon: Icon, color }) => (
          <UnstyledButton
            key={label}
            component={Link}
            href={href}
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              textAlign: "center",
              borderRadius: "var(--mantine-radius-md)",
              height: 90,
              backgroundColor: "light-dark(var(--mantine-color-white), var(--mantine-color-dark-6))",
              transition: "box-shadow 150ms ease, transform 100ms ease",
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLElement).style.boxShadow = "var(--mantine-shadow-sm)";
              (e.currentTarget as HTMLElement).style.transform = "scale(1.02)";
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLElement).style.boxShadow = "";
              (e.currentTarget as HTMLElement).style.transform = "";
            }}
          >
            <Icon color={theme.colors[color][6]} size={32} stroke={1.5} />
            <Text size="xs" mt={7}>{label}</Text>
          </UnstyledButton>
        ))}
      </SimpleGrid>
    </Card>
  );
}

type TabKey = "accounts" | "ledger" | "payments";

interface AccountRow extends Account {
  party_name: string;
}

interface KpiProps {
  label: string;
  value: string;
  hint?: string;
  Icon: Icon;
  tone: "indigo" | "teal" | "orange" | "violet";
}

function Kpi({ label, value, hint, Icon, tone }: KpiProps) {
  return (
    <Card withBorder shadow="sm" radius="md" padding="lg">
      <Group justify="space-between" align="flex-start" wrap="nowrap">
        <Stack gap={4}>
          <Text size="xs" c="dimmed" tt="uppercase" fw={700}>
            {label}
          </Text>
          <Title order={3} fw={600} lh={1.2}>
            {value}
          </Title>
          {hint && (
            <Text size="xs" c="dimmed">
              {hint}
            </Text>
          )}
        </Stack>
        <ThemeIcon
          variant="light"
          color={tone}
          size={44}
          radius="md"
        >
          <Icon size={22} stroke={1.7} />
        </ThemeIcon>
      </Group>
    </Card>
  );
}

function StatusBadge({ status }: { status: string }) {
  const s = (status ?? "").toLowerCase();
  let color = "gray";
  if (s === "active" || s === "posted" || s === "open") color = "teal";
  else if (s === "pending") color = "yellow";
  else if (
    s === "suspended" ||
    s === "frozen" ||
    s === "reversed" ||
    s === "failed"
  )
    color = "red";
  else if (s === "closed") color = "gray";
  return (
    <Badge variant="light" color={color} radius="sm">
      {status || "—"}
    </Badge>
  );
}

function shortId(prefix: string, id: string): string {
  if (!id) return "—";
  const compact = id.replace(/-/g, "");
  return `${prefix}-${compact.slice(-6).toUpperCase()}`;
}

function accountTypeCode(name: string, currency: string): string {
  const n = (name || "").toLowerCase();
  if (n.includes("savings")) return "SAV";
  if (n.includes("escrow")) return "ESC";
  if (n.includes("trust")) return "TRU";
  if (n.includes("loan")) return "LOA";
  if (n.includes("operating") || n.includes("ops")) return "OPS";
  if (n.includes("checking") || n.includes("dda")) return "DDA";
  return (currency || "GEN").toUpperCase().slice(0, 3);
}

export default function DashboardPage() {
  const { setError } = useNotify();
  const { tick } = useRefresh();
  const [tab, setTab] = useState<TabKey>("accounts");

  const [parties, setParties] = useState<Party[]>([]);
  const [accounts, setAccounts] = useState<AccountRow[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [ledger, setLedger] = useState<LedgerEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const partyList = partyResp.items ?? [];
        const accountRows: AccountRow[] = [];
        const txns: Transaction[] = [];
        const seenTxns = new Set<string>();
        const ledgerEntries: LedgerEntry[] = [];

        for (const party of partyList) {
          try {
            const accResp = await api<ListResponse<Account>>(
              "GET",
              `/parties/${party.party_id}/accounts`,
            );
            for (const a of accResp.items ?? []) {
              accountRows.push({ ...a, party_name: party.full_name });
            }
          } catch {
            /* skip */
          }
        }

        for (const acc of accountRows.slice(0, 50)) {
          try {
            const txResp = await api<ListResponse<Transaction>>(
              "GET",
              `/accounts/${acc.account_id}/transactions`,
            );
            for (const t of txResp.items ?? []) {
              if (!seenTxns.has(t.txn_id)) {
                seenTxns.add(t.txn_id);
                txns.push(t);
              }
            }
          } catch {
            /* skip */
          }
        }

        for (const acc of accountRows.slice(0, 25)) {
          try {
            const lResp = await api<ListResponse<LedgerEntry>>(
              "GET",
              `/accounts/${acc.account_id}/entries`,
            );
            for (const e of lResp.items ?? []) ledgerEntries.push(e);
          } catch {
            /* skip */
          }
        }

        if (cancelled) return;
        setParties(partyList);
        setAccounts(accountRows);
        setTransactions(
          txns.sort((a, b) => (b.created_at ?? 0) - (a.created_at ?? 0)),
        );
        setLedger(
          ledgerEntries.sort((a, b) => (b.posted_at ?? 0) - (a.posted_at ?? 0)),
        );
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const stats = useMemo(() => {
    const totalDeposits = accounts.reduce((s, a) => s + (a.balance ?? 0), 0);
    const activeAccounts = accounts.filter(
      (a) => (a.status ?? "").toLowerCase() === "active",
    ).length;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayMs = today.getTime();
    const openedToday = accounts.filter(
      (a) => (a.created_at ?? 0) * 1000 >= todayMs,
    ).length;
    const pendingPayments = transactions.filter(
      (t) => (t.status ?? "").toLowerCase() === "pending",
    ).length;
    const totalPaymentVolume = transactions
      .filter((t) => (t.status ?? "").toLowerCase() === "posted")
      .reduce((s, t) => s + (t.amount ?? 0), 0);
    return {
      totalDeposits,
      activeAccounts,
      openedToday,
      totalParties: parties.length,
      totalTransactions: transactions.length,
      totalLedgerEntries: ledger.length,
      pendingPayments,
      totalPaymentVolume,
    };
  }, [accounts, parties, transactions, ledger]);

  return (
    <Stack gap="lg">
      <QuickActionsGrid />
      <SimpleGrid cols={{ base: 1, sm: 2, lg: 4 }} spacing="md">
        <Kpi
          label="Total Deposits"
          value={formatAmount(stats.totalDeposits, "USD")}
          hint={`Across ${formatNumber(stats.activeAccounts)} active accounts`}
          Icon={IconWallet}
          tone="indigo"
        />
        <Kpi
          label="Customers"
          value={formatNumber(stats.totalParties)}
          hint={`${formatNumber(stats.openedToday)} opened today`}
          Icon={IconUsers}
          tone="violet"
        />
        <Kpi
          label="Payments Volume"
          value={formatAmount(stats.totalPaymentVolume, "USD")}
          hint={`${formatNumber(stats.totalTransactions)} payments total`}
          Icon={IconBuildingBank}
          tone="teal"
        />
        <Kpi
          label="Pending Approvals"
          value={formatNumber(stats.pendingPayments)}
          hint="Payments awaiting action"
          Icon={IconClock}
          tone="orange"
        />
      </SimpleGrid>

      <Paper withBorder radius="md" shadow="sm">
        <Group
          p="lg"
          justify="space-between"
          align="center"
          wrap="wrap"
          gap="sm"
        >
          <div>
            <Title order={4} fw={600}>
              Recent Activity
            </Title>
            <Text size="sm" c="dimmed">
              Latest movement across your portfolio
            </Text>
          </div>
          <SegmentedControl
            value={tab}
            onChange={(v) => setTab(v as TabKey)}
            data={[
              { label: "Accounts", value: "accounts" },
              { label: "Ledger", value: "ledger" },
              { label: "Payments", value: "payments" },
            ]}
          />
        </Group>
        <Box px="md" pb="md" data-testid={`dashboard-tab-${tab}`}>
          {tab === "accounts" ? (
            <AccountsTab loading={loading} accounts={accounts} />
          ) : tab === "ledger" ? (
            <LedgerTab loading={loading} ledger={ledger} accounts={accounts} />
          ) : (
            <PaymentsTab
              loading={loading}
              transactions={transactions}
              accounts={accounts}
            />
          )}
        </Box>
      </Paper>
    </Stack>
  );
}

function EmptyRow({ colSpan, label }: { colSpan: number; label: string }) {
  return (
    <Table.Tr>
      <Table.Td colSpan={colSpan} ta="center" py="xl" c="dimmed">
        {label}
      </Table.Td>
    </Table.Tr>
  );
}

function AccountsTab({
  loading,
  accounts,
}: {
  loading: boolean;
  accounts: AccountRow[];
}) {
  const top = accounts.slice(0, 8);
  return (
    <Table.ScrollContainer minWidth={700}>
      <Table verticalSpacing="sm" highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Account</Table.Th>
            <Table.Th>Customer</Table.Th>
            <Table.Th>Type</Table.Th>
            <Table.Th ta="right">Balance</Table.Th>
            <Table.Th ta="right">Status</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {loading && accounts.length === 0 ? (
            <EmptyRow colSpan={5} label="Loading accounts…" />
          ) : top.length === 0 ? (
            <EmptyRow colSpan={5} label="No accounts yet" />
          ) : (
            top.map((a) => (
              <Table.Tr key={a.account_id}>
                <Table.Td>
                  <Anchor
                    component={Link}
                    href={`/accounts/${a.account_id}`}
                    underline="never"
                  >
                    <Text fw={500}>{a.name}</Text>
                    <Text size="xs" c="dimmed" ff="monospace">
                      {shortId("ACC", a.account_id)}
                    </Text>
                  </Anchor>
                </Table.Td>
                <Table.Td>{a.party_name}</Table.Td>
                <Table.Td>
                  <Badge variant="light" color="gray" radius="sm">
                    {accountTypeCode(a.name, a.currency)}
                  </Badge>
                </Table.Td>
                <Table.Td ta="right" ff="monospace" fw={500}>
                  {formatAmount(a.balance, a.currency)}
                </Table.Td>
                <Table.Td ta="right">
                  <StatusBadge status={a.status} />
                </Table.Td>
              </Table.Tr>
            ))
          )}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}

function LedgerTab({
  loading,
  ledger,
  accounts,
}: {
  loading: boolean;
  ledger: LedgerEntry[];
  accounts: AccountRow[];
}) {
  const accountById = new Map(accounts.map((a) => [a.account_id, a] as const));
  const top = ledger.slice(0, 10);
  return (
    <Table.ScrollContainer minWidth={700}>
      <Table verticalSpacing="sm" highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Entry</Table.Th>
            <Table.Th>Account</Table.Th>
            <Table.Th>Type</Table.Th>
            <Table.Th ta="right">Amount</Table.Th>
            <Table.Th ta="right">Posted</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {loading && ledger.length === 0 ? (
            <EmptyRow colSpan={5} label="Loading ledger…" />
          ) : top.length === 0 ? (
            <EmptyRow colSpan={5} label="No ledger entries yet" />
          ) : (
            top.map((e) => {
              const acc = accountById.get(e.account_id);
              const isDebit = e.entry_type === "debit";
              return (
                <Table.Tr key={e.entry_id}>
                  <Table.Td ff="monospace">
                    {shortId("ENT", e.entry_id)}
                  </Table.Td>
                  <Table.Td>{acc?.name ?? shortId("ACC", e.account_id)}</Table.Td>
                  <Table.Td>
                    <Badge
                      variant="light"
                      color={isDebit ? "red" : "teal"}
                      leftSection={
                        isDebit ? (
                          <IconArrowDown size={12} />
                        ) : (
                          <IconArrowUp size={12} />
                        )
                      }
                      radius="sm"
                    >
                      {(e.entry_type || "").toUpperCase()}
                    </Badge>
                  </Table.Td>
                  <Table.Td
                    ta="right"
                    ff="monospace"
                    fw={500}
                    c={isDebit ? "red" : "teal"}
                  >
                    {isDebit ? "-" : "+"}
                    {formatAmount(e.amount, e.currency)}
                  </Table.Td>
                  <Table.Td ta="right" c="dimmed">
                    {formatTimestamp(e.posted_at)}
                  </Table.Td>
                </Table.Tr>
              );
            })
          )}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}

function PaymentsTab({
  loading,
  transactions,
  accounts,
}: {
  loading: boolean;
  transactions: Transaction[];
  accounts: AccountRow[];
}) {
  const accountById = new Map(accounts.map((a) => [a.account_id, a] as const));
  const top = transactions.slice(0, 10);
  return (
    <Table.ScrollContainer minWidth={800}>
      <Table verticalSpacing="sm" highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Transaction</Table.Th>
            <Table.Th>Type</Table.Th>
            <Table.Th>From → To</Table.Th>
            <Table.Th ta="right">Amount</Table.Th>
            <Table.Th ta="right">Status</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {loading && transactions.length === 0 ? (
            <EmptyRow colSpan={5} label="Loading payments…" />
          ) : top.length === 0 ? (
            <EmptyRow colSpan={5} label="No payments yet" />
          ) : (
            top.map((t) => {
              const src = accountById.get(t.source_account_id);
              const dst = accountById.get(t.dest_account_id);
              return (
                <Table.Tr key={t.txn_id}>
                  <Table.Td ff="monospace">{shortId("TXN", t.txn_id)}</Table.Td>
                  <Table.Td>
                    <Badge variant="light" color="gray" radius="sm" tt="uppercase">
                      {t.txn_type}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Group gap={6} wrap="nowrap">
                      <Text size="sm">
                        {src?.name ??
                          (t.source_account_id
                            ? shortId("ACC", t.source_account_id)
                            : "—")}
                      </Text>
                      <IconArrowRight size={14} stroke={1.7} />
                      <Text size="sm">
                        {dst?.name ??
                          (t.dest_account_id
                            ? shortId("ACC", t.dest_account_id)
                            : "—")}
                      </Text>
                    </Group>
                  </Table.Td>
                  <Table.Td ta="right" ff="monospace" fw={500}>
                    {formatAmount(t.amount, t.currency)}
                  </Table.Td>
                  <Table.Td ta="right">
                    <StatusBadge status={t.status} />
                  </Table.Td>
                </Table.Tr>
              );
            })
          )}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}
