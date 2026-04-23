"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  Badge,
  Button,
  Group,
  Pagination,
  Paper,
  Select,
  Stack,
  Text,
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
import type { Transaction } from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

interface SearchResponse {
  items: Transaction[];
  total: number;
  page: number;
  page_size: number;
}

const PAGE_SIZE = 50;

const STATUS_OPTIONS = [
  { label: "All statuses", value: "" },
  { label: "Posted", value: "posted" },
  { label: "Pending", value: "pending" },
  { label: "Failed", value: "failed" },
  { label: "Reversed", value: "reversed" },
];

const TYPE_OPTIONS = [
  { label: "All types", value: "" },
  { label: "Deposit", value: "deposit" },
  { label: "Withdrawal", value: "withdrawal" },
  { label: "Transfer", value: "transfer" },
  { label: "Adjustment", value: "adjustment" },
  { label: "Reversal", value: "reversal" },
];

function statusColor(s: string) {
  if (s === "posted") return "teal";
  if (s === "pending") return "yellow";
  if (s === "failed") return "red";
  if (s === "reversed") return "gray";
  return "gray";
}

export default function TransactionsPage() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [filterStatus, setFilterStatus] = useState("");
  const [filterType, setFilterType] = useState("");
  const [search, setSearch] = useState("");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const params = new URLSearchParams({
          page: String(page),
          page_size: String(PAGE_SIZE),
        });
        if (filterStatus) params.set("status", filterStatus);
        if (filterType) params.set("type", filterType);
        const resp = await api<SearchResponse>(
          "GET",
          `/transactions?${params.toString()}`,
        );
        if (!cancelled) {
          setTransactions(resp.items ?? []);
          setTotal(resp.total ?? 0);
        }
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, page, filterStatus, filterType, setError]);

  const reverse = async (id: string) => {
    try {
      await api("POST", `/transactions/${id}/reverse`);
      setSuccess("Transaction reversed");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

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
      <Group align="flex-end" gap="sm" wrap="wrap">
        <TextInput
          leftSection={<IconSearch size={16} stroke={1.5} />}
          placeholder="Search transactions..."
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          style={{ flex: 1, minWidth: 200 }}
          aria-label="Search transactions"
        />
        <Select
          data={STATUS_OPTIONS}
          value={filterStatus}
          onChange={(v) => { setFilterStatus(v ?? ""); setPage(1); }}
          placeholder="All statuses"
          w={160}
          aria-label="Filter by status"
          clearable
        />
        <Select
          data={TYPE_OPTIONS}
          value={filterType}
          onChange={(v) => { setFilterType(v ?? ""); setPage(1); }}
          placeholder="All types"
          w={160}
          aria-label="Filter by type"
          clearable
        />
      </Group>

      <Paper withBorder radius="md" shadow="sm">
        <SortableTable
          data={transactions}
          columns={txColumns}
          rowKey={(t) => t.txn_id}
          searchPlaceholder="Search transactions..."
          emptyMessage="No transactions found"
          minWidth={800}
          searchValue={search}
          onSearchChange={setSearch}
        />
      </Paper>

      <Group justify="space-between" align="center">
        <Text size="sm" c="dimmed">
          {total} transaction{total !== 1 ? "s" : ""}
        </Text>
        <Pagination
          value={page}
          onChange={setPage}
          total={totalPages}
          size="sm"
        />
      </Group>
    </Stack>
  );
}
