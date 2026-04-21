"use client";

import { useEffect, useMemo, useState } from "react";
import {
  Badge,
  Button,
  Paper,
  SegmentedControl,
  Stack,
  Table,
  TextInput,
} from "@mantine/core";
import { IconSearch } from "@tabler/icons-react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import {
  capitalize,
  formatAmount,
  formatTimestamp,
  truncateID,
} from "@/lib/format";
import type { Account, Party, Transaction } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

const STATUSES = [
  { label: "All", value: "all" },
  { label: "Pending", value: "pending" },
  { label: "Posted", value: "posted" },
  { label: "Failed", value: "failed" },
];

function statusColor(s: string) {
  if (s === "posted") return "teal";
  if (s === "pending") return "yellow";
  if (s === "failed") return "red";
  return "gray";
}

export default function TransactionsPage() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState<string>("all");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const parties = partyResp.items ?? [];
        let allAccounts: Account[] = [];
        for (const p of parties) {
          try {
            const accResp = await api<ListResponse<Account>>(
              "GET",
              `/parties/${p.party_id}/accounts`,
            );
            if (accResp.items) allAccounts = allAccounts.concat(accResp.items);
          } catch {
            /* skip */
          }
        }
        const seen = new Set<string>();
        const allTxns: Transaction[] = [];
        for (const acc of allAccounts) {
          try {
            const txResp = await api<ListResponse<Transaction>>(
              "GET",
              `/accounts/${acc.account_id}/transactions`,
            );
            for (const t of txResp.items ?? []) {
              if (!seen.has(t.txn_id)) {
                seen.add(t.txn_id);
                allTxns.push(t);
              }
            }
          } catch {
            /* skip */
          }
        }
        if (!cancelled) setTransactions(allTxns);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const filtered = useMemo(() => {
    let list = transactions;
    if (filterStatus && filterStatus !== "all")
      list = list.filter((t) => t.status === filterStatus);
    if (search) {
      const q = search.toLowerCase();
      list = list.filter(
        (t) =>
          t.description.toLowerCase().includes(q) ||
          t.txn_id.toLowerCase().includes(q),
      );
    }
    return list;
  }, [transactions, search, filterStatus]);

  const reverse = async (id: string) => {
    try {
      await api("POST", `/transactions/${id}/reverse`);
      setSuccess("Transaction reversed");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <Stack gap="lg">
      <TextInput
        leftSection={<IconSearch size={16} />}
        placeholder="Search transactions..."
        value={search}
        onChange={(e) => setSearch(e.currentTarget.value)}
        maw={400}
      />

      <SegmentedControl
        value={filterStatus}
        onChange={setFilterStatus}
        data={STATUSES}
      />

      <Paper withBorder radius="md" shadow="sm">
        <Table.ScrollContainer minWidth={800}>
          <Table verticalSpacing="sm" highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>ID</Table.Th>
                <Table.Th>Date</Table.Th>
                <Table.Th>Type</Table.Th>
                <Table.Th>Description</Table.Th>
                <Table.Th ta="right">Amount</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.map((t) => (
                <Table.Tr key={t.txn_id}>
                  <Table.Td ff="monospace">{truncateID(t.txn_id)}</Table.Td>
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
                  <Table.Td>
                    {t.status === "posted" && (
                      <Button
                        size="xs"
                        variant="light"
                        color="yellow"
                        onClick={() => reverse(t.txn_id)}
                      >
                        Reverse
                      </Button>
                    )}
                  </Table.Td>
                </Table.Tr>
              ))}
              {filtered.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={7} ta="center" py="xl" c="dimmed">
                    No transactions found
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Paper>
    </Stack>
  );
}
