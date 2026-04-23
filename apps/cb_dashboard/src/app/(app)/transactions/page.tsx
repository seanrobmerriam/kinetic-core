"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  Badge,
  Button,
  Group,
  Paper,
  SegmentedControl,
  Stack,
  TextInput,
} from "@mantine/core";
import { IconSearch } from "@/components/icons";
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
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

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
  const [filterStatus, setFilterStatus] = useState<string>("all");
  const [search, setSearch] = useState("");

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
    return list;
  }, [transactions, filterStatus]);

  const reverse = async (id: string) => {
    try {
      await api("POST", `/transactions/${id}/reverse`);
      setSuccess("Transaction reversed");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const txColumns: ColumnDef<Transaction>[] = [
    {
      key: "id",
      label: "ID",
      getValue: (t) => t.txn_id,
      render: (t) => truncateID(t.txn_id),
      ff: "monospace",
    },
    {
      key: "date",
      label: "Date",
      getValue: (t) => t.created_at,
      render: (t) => formatTimestamp(t.created_at),
    },
    {
      key: "type",
      label: "Type",
      getValue: (t) => t.txn_type,
      render: (t) => (
        <Badge variant="light" color="gray" radius="sm">
          {capitalize(t.txn_type)}
        </Badge>
      ),
    },
    { key: "description", label: "Description", getValue: (t) => t.description },
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
        <Badge variant="light" color={statusColor(t.status)} radius="sm">
          {capitalize(t.status)}
        </Badge>
      ),
    },
    {
      key: "actions",
      label: "Actions",
      sortable: false,
      render: (t) => (
        <Group gap="xs" wrap="nowrap">
          <Button
            component={Link}
            href={`/transactions/${t.txn_id}`}
            size="xs"
            variant="light"
          >
            View
          </Button>
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
        </Group>
      ),
    },
  ];

  return (
    <Stack gap="lg">
      <TextInput
        leftSection={<IconSearch size={16} stroke={1.5} />}
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
        <SortableTable
          data={filtered}
          columns={txColumns}
          rowKey={(t) => t.txn_id}
          searchPlaceholder="Search transactions..."
          emptyMessage="No transactions found"
          minWidth={800}
          searchValue={search}
          onSearchChange={setSearch}
        />
      </Paper>
    </Stack>
  );
}
