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
  Table,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { IconArrowLeft } from "@tabler/icons-react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import {
  capitalize,
  formatAmount,
  formatDate,
  formatTimestamp,
} from "@/lib/format";
import type { Account, AccountHold, Transaction } from "@/lib/types";

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

export default function AccountDetailPage({
  params,
}: {
  params: Promise<{ accountId: string }>;
}) {
  const { accountId } = use(params);
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [account, setAccount] = useState<Account | null>(null);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [holds, setHolds] = useState<AccountHold[]>([]);
  const [holdAmount, setHoldAmount] = useState<string | number>("");
  const [holdReason, setHoldReason] = useState("");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const partyResp = await api<ListResponse<{ party_id: string }>>(
          "GET",
          "/parties",
        );
        const parties = partyResp.items ?? [];
        let found: Account | null = null;
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
              break;
            }
          } catch {
            /* skip */
          }
        }
        if (!cancelled) setAccount(found);
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
          <Badge size="lg" variant="light" color={statusColor(account.status)}>
            {capitalize(account.status)}
          </Badge>
        </Group>
      </Card>

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
      </Group>

      <div>
        <Title order={4} mb="sm">
          Recent Transactions
        </Title>
        <Paper withBorder radius="md" shadow="sm">
          <Table.ScrollContainer minWidth={700}>
            <Table verticalSpacing="sm" highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Type</Table.Th>
                  <Table.Th>Description</Table.Th>
                  <Table.Th ta="right">Amount</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {transactions.length === 0 ? (
                  <Table.Tr>
                    <Table.Td colSpan={5} ta="center" py="xl" c="dimmed">
                      No transactions yet
                    </Table.Td>
                  </Table.Tr>
                ) : (
                  transactions.map((t) => (
                    <Table.Tr key={t.txn_id}>
                      <Table.Td>{formatTimestamp(t.created_at)}</Table.Td>
                      <Table.Td>
                        <Badge variant="light" color="gray" radius="sm">
                          {capitalize(t.txn_type)}
                        </Badge>
                      </Table.Td>
                      <Table.Td>{t.description}</Table.Td>
                      <Table.Td ta="right" ff="monospace" fw={500}>
                        {formatAmount(t.amount, t.currency)}
                      </Table.Td>
                      <Table.Td>
                        <Badge
                          variant="light"
                          color={statusColor(t.status)}
                          radius="sm"
                        >
                          {capitalize(t.status)}
                        </Badge>
                      </Table.Td>
                    </Table.Tr>
                  ))
                )}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
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
          <Table.ScrollContainer minWidth={700}>
            <Table verticalSpacing="sm" highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th ta="right">Amount</Table.Th>
                  <Table.Th>Reason</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Placed</Table.Th>
                  <Table.Th>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {holds.length === 0 ? (
                  <Table.Tr>
                    <Table.Td colSpan={5} ta="center" py="xl" c="dimmed">
                      No holds on this account
                    </Table.Td>
                  </Table.Tr>
                ) : (
                  holds.map((h) => (
                    <Table.Tr key={h.hold_id}>
                      <Table.Td ta="right" ff="monospace" fw={500}>
                        {formatAmount(h.amount, account.currency)}
                      </Table.Td>
                      <Table.Td>{h.reason}</Table.Td>
                      <Table.Td>
                        <Badge
                          variant="light"
                          color={statusColor(h.status)}
                          radius="sm"
                        >
                          {capitalize(h.status)}
                        </Badge>
                      </Table.Td>
                      <Table.Td>{formatTimestamp(h.placed_at)}</Table.Td>
                      <Table.Td>
                        {h.status === "active" && (
                          <Button
                            size="xs"
                            variant="subtle"
                            onClick={() => releaseHold(h.hold_id)}
                          >
                            Release
                          </Button>
                        )}
                      </Table.Td>
                    </Table.Tr>
                  ))
                )}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      </div>
    </Stack>
  );
}
