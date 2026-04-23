"use client";

import Link from "next/link";
import { use, useEffect, useMemo, useState } from "react";
import {
  Anchor,
  Badge,
  Button,
  Card,
  Group,
  NumberInput,
  Paper,
  SimpleGrid,
  Stack,
  Text,
  TextInput,
  Title,
  Spoiler,
  Divider,
} from "@mantine/core";
import {
  IconArrowLeft,
  IconKey,
  IconFiles,
  IconMessageCircle,
} from "@tabler/icons-react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import {
  capitalize,
  formatAmount,
  formatDate,
  formatTimestamp,
} from "@/lib/format";
import type { Account, AccountHold, Party, Transaction } from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";
import { StatementDownload } from "@/components/StatementDownload";

interface ListResponse<T> {
  items: T[];
}

function statusColor(s: string) {
  if (s === "active" || s === "posted") return "teal";
  if (s === "frozen" || s === "pending") return "yellow";
  if (s === "closed" || s === "released" || s === "reversed") return "gray";
  if (s === "failed") return "red";
  return "gray";
}

function InfoField({
  label,
  value,
}: {
  label: string;
  value: React.ReactNode;
}) {
  return (
    <div>
      <Text size="xs" c="dimmed" tt="uppercase" fw={700} mb={2}>
        {label}
      </Text>
      <Text size="sm">{value ?? "—"}</Text>
    </div>
  );
}

function formatAddress(party: Party): string | null {
  const a = party.address;
  if (!a) return null;
  const parts = [
    a.line1,
    a.line2,
    a.city,
    [a.state, a.postal_code].filter(Boolean).join(" "),
    a.country,
  ].filter(Boolean);
  return parts.length > 0 ? parts.join(", ") : null;
}

export default function AccountDetailPage({
  params,
}: {
  params: Promise<{ accountId: string }>;
}) {
  const { accountId } = use(params);
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [account, setAccount] = useState<Account | null>(null);
  const [party, setParty] = useState<Party | null>(null);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [holds, setHolds] = useState<AccountHold[]>([]);
  const [holdAmount, setHoldAmount] = useState<string | number>("");
  const [holdReason, setHoldReason] = useState("");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const parties = partyResp.items ?? [];
        let found: Account | null = null;
        let foundParty: Party | null = null;
        for (const p of parties) {
          try {
            const accResp = await api<ListResponse<Account>>(
              "GET",
              `/parties/${p.party_id}/accounts`,
            );
            const match = (accResp.items ?? []).find(
              (a) => a.account_id === accountId,
            );
            if (match) {
              found = match;
              foundParty = p;
              break;
            }
          } catch {
            /* skip */
          }
        }
        if (!cancelled) setAccount(found);

        if (foundParty) {
          try {
            const fullParty = await api<Party>(
              "GET",
              `/parties/${foundParty.party_id}`,
            );
            if (!cancelled) setParty(fullParty);
          } catch {
            if (!cancelled) setParty(foundParty);
          }
        }

        try {
          const txResp = await api<ListResponse<Transaction>>(
            "GET",
            `/accounts/${accountId}/transactions`,
          );
          if (!cancelled) setTransactions(txResp.items ?? []);
        } catch {
          /* ignore */
        }
        try {
          const holdResp = await api<ListResponse<AccountHold>>(
            "GET",
            `/accounts/${accountId}/holds`,
          );
          if (!cancelled) setHolds(holdResp.items ?? []);
        } catch {
          /* ignore */
        }
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [accountId, tick, setError]);

  const availableBalance = useMemo(() => {
    const held = holds
      .filter((h) => h.status === "active")
      .reduce((s, h) => s + h.amount, 0);
    return (account?.balance ?? 0) - held;
  }, [account, holds]);

  const action = async (path: string, msg: string) => {
    try {
      await api("POST", path);
      setSuccess(msg);
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const placeHold = async () => {
    const amt =
      typeof holdAmount === "number" ? holdAmount : parseInt(holdAmount, 10);
    if (!Number.isFinite(amt) || !holdReason) return;
    try {
      await api("POST", `/accounts/${accountId}/holds`, {
        amount: amt,
        reason: holdReason,
      });
      setSuccess("Hold placed");
      setHoldAmount("");
      setHoldReason("");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const releaseHold = async (holdId: string) => {
    try {
      await api("DELETE", `/accounts/${accountId}/holds/${holdId}`);
      setSuccess("Hold released");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  if (!account) {
    return (
      <Stack gap="lg">
        <Anchor component={Link} href="/accounts" size="sm">
          <Group gap={4}>
            <IconArrowLeft size={14} />
            Back to Accounts
          </Group>
        </Anchor>
        <Text c="dimmed">Loading account…</Text>
      </Stack>
    );
  }

  return (
    <Stack gap="lg">
      <Anchor component={Link} href="/accounts" size="sm">
        <Group gap={4}>
          <IconArrowLeft size={14} />
          Back to Accounts
        </Group>
      </Anchor>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Group justify="space-between" align="flex-start">
          <div>
            <Title order={3}>{account.name}</Title>
            <Text size="xs" c="dimmed" ff="monospace" mt={4}>
              Account ID: {account.account_id}
            </Text>
          </div>
          <Group gap="sm" align="center">
            <StatementDownload
              accountId={account.account_id}
              accountName={account.name}
            />
            <Badge size="lg" variant="light" color={statusColor(account.status)}>
              {capitalize(account.status)}
            </Badge>
          </Group>
        </Group>
      </Card>

      {party && (
        <Card withBorder shadow="sm" radius="md" padding="lg">
          <Title order={5} mb="md">
            Customer Information
          </Title>
          <Divider mb="md" />
          <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
            <InfoField label="Full Name" value={party.full_name} />
            <InfoField label="Email" value={party.email} />
            <InfoField
              label="Phone"
              value={party.phone ?? "Not on file"}
            />
            <InfoField
              label="Date of Birth"
              value={party.date_of_birth ?? "Not on file"}
            />
            <InfoField
              label="SSN (Last 4)"
              value={
                party.ssn_last4 ? (
                  <Spoiler
                    maxHeight={0}
                    showLabel="Reveal"
                    hideLabel="Hide"
                    styles={{
                      root: { display: "inline-flex", alignItems: "center", gap: 6 },
                      control: { fontSize: "var(--mantine-font-size-xs)" },
                    }}
                  >
                    <Text component="span" size="sm" ff="monospace">
                      ••••{party.ssn_last4}
                    </Text>
                  </Spoiler>
                ) : (
                  "Not on file"
                )
              }
            />
            <InfoField
              label="Address"
              value={formatAddress(party) ?? "Not on file"}
            />
            {party.address?.city && (
              <InfoField label="City" value={party.address.city} />
            )}
            {party.address?.state && (
              <InfoField label="State" value={party.address.state} />
            )}
            {party.address?.postal_code && (
              <InfoField label="Postal Code" value={party.address.postal_code} />
            )}
            {party.address?.country && (
              <InfoField label="Country" value={party.address.country} />
            )}
          </SimpleGrid>
        </Card>
      )}

      <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="md">
        <Card withBorder shadow="sm" radius="md" padding="lg">
          <Text size="xs" c="dimmed" tt="uppercase" fw={700}>
            Current Balance
          </Text>
          <Title order={3} mt={4}>
            {formatAmount(account.balance, account.currency)}
          </Title>
        </Card>
        <Card withBorder shadow="sm" radius="md" padding="lg">
          <Text size="xs" c="dimmed" tt="uppercase" fw={700}>
            Currency
          </Text>
          <Title order={4} mt={4}>
            {account.currency}
          </Title>
        </Card>
        <Card withBorder shadow="sm" radius="md" padding="lg">
          <Text size="xs" c="dimmed" tt="uppercase" fw={700}>
            Created
          </Text>
          <Title order={4} mt={4}>
            {formatDate(account.created_at)}
          </Title>
        </Card>
      </SimpleGrid>

      <Group>
        {account.status === "active" && (
          <Button
            color="yellow"
            variant="light"
            onClick={() =>
              action(`/accounts/${accountId}/freeze`, "Account frozen")
            }
          >
            Freeze Account
          </Button>
        )}
        {account.status === "frozen" && (
          <Button
            color="teal"
            variant="light"
            onClick={() =>
              action(`/accounts/${accountId}/unfreeze`, "Account unfrozen")
            }
          >
            Unfreeze Account
          </Button>
        )}
        <Button
          color="red"
          variant="light"
          onClick={() =>
            action(`/accounts/${accountId}/close`, "Account closed")
          }
        >
          Close Account
        </Button>
        <Button
          variant="light"
          leftSection={<IconKey size={16} />}
          onClick={() => setSuccess("Change Login Credentials — coming soon")}
        >
          Change Login Credentials
        </Button>
        <Button
          variant="light"
          leftSection={<IconFiles size={16} />}
          onClick={() => setSuccess("User Documents — coming soon")}
        >
          User Documents
        </Button>
        <Button
          variant="light"
          leftSection={<IconMessageCircle size={16} />}
          onClick={() => setSuccess("Send Secure Message — coming soon")}
        >
          Send Secure Message
        </Button>
      </Group>

      <div>
        <Title order={4} mb="sm">
          Recent Transactions
        </Title>
        <Paper withBorder radius="md" shadow="sm">
          <SortableTable
            data={transactions}
            columns={[
              {
                key: "created_at",
                label: "Date",
                getValue: (t) => t.created_at,
                render: (t) => formatTimestamp(t.created_at),
              },
              {
                key: "txn_type",
                label: "Type",
                getValue: (t) => t.txn_type,
                render: (t) => (
                  <Badge variant="light" color="gray" radius="sm">
                    {capitalize(t.txn_type)}
                  </Badge>
                ),
              },
              {
                key: "description",
                label: "Description",
                getValue: (t) => t.description,
              },
              {
                key: "amount",
                label: "Amount",
                getValue: (t) => t.amount,
                render: (t) => formatAmount(t.amount, t.currency),
                ta: "right",
                ff: "monospace",
                fw: 500,
              },
              {
                key: "status",
                label: "Status",
                getValue: (t) => t.status,
                render: (t) => (
                  <Badge
                    variant="light"
                    color={statusColor(t.status)}
                    radius="sm"
                  >
                    {capitalize(t.status)}
                  </Badge>
                ),
              },
            ] satisfies ColumnDef<Transaction>[]}
            rowKey={(t) => t.txn_id}
            searchPlaceholder="Search transactions..."
            emptyMessage="No transactions yet"
            minWidth={700}
          />
        </Paper>
      </div>

      <div>
        <Group justify="space-between" mb="sm">
          <Title order={4}>Funds Holds</Title>
          <Text size="sm" c="dimmed">
            Available: {formatAmount(availableBalance, account.currency)}
          </Text>
        </Group>

        <Card withBorder shadow="sm" radius="md" padding="lg" mb="md">
          <Title order={5} mb="md">
            Place New Hold
          </Title>
          <Stack>
            <Group grow>
              <NumberInput
                id="hold-amount-input"
                label="Amount (minor units)"
                placeholder="100"
                value={holdAmount}
                onChange={setHoldAmount}
              />
              <TextInput
                id="hold-reason-input"
                label="Reason"
                placeholder="Reason"
                value={holdReason}
                onChange={(e) => setHoldReason(e.currentTarget.value)}
              />
            </Group>
            <Group>
              <Button color="yellow" onClick={placeHold}>
                Place Hold
              </Button>
            </Group>
          </Stack>
        </Card>

        <Paper withBorder radius="md" shadow="sm">
          {(() => {
            const holdCols: ColumnDef<AccountHold>[] = [
              {
                key: "amount",
                label: "Amount",
                getValue: (h) => h.amount,
                render: (h) => formatAmount(h.amount, account.currency),
                ta: "right",
                ff: "monospace",
                fw: 500,
              },
              {
                key: "reason",
                label: "Reason",
                getValue: (h) => h.reason,
              },
              {
                key: "status",
                label: "Status",
                getValue: (h) => h.status,
                render: (h) => (
                  <Badge
                    variant="light"
                    color={statusColor(h.status)}
                    radius="sm"
                  >
                    {capitalize(h.status)}
                  </Badge>
                ),
              },
              {
                key: "placed_at",
                label: "Placed",
                getValue: (h) => h.placed_at,
                render: (h) => formatTimestamp(h.placed_at),
              },
              {
                key: "actions",
                label: "Actions",
                sortable: false,
                getValue: () => "",
                render: (h) =>
                  h.status === "active" ? (
                    <Button
                      size="xs"
                      variant="subtle"
                      onClick={() => releaseHold(h.hold_id)}
                    >
                      Release
                    </Button>
                  ) : null,
              },
            ];
            return (
              <SortableTable
                data={holds}
                columns={holdCols}
                rowKey={(h) => h.hold_id}
                searchPlaceholder="Search holds..."
                emptyMessage="No holds on this account"
                minWidth={700}
              />
            );
          })()}
        </Paper>
      </div>
    </Stack>
  );
}
