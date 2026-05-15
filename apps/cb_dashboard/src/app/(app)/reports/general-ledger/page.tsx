"use client";

import { useState } from "react";
import {
  Anchor,
  Badge,
  Button,
  Card,
  Group,
  Loader,
  Pagination,
  Paper,
  Select,
  Stack,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import Link from "next/link";
import { getGeneralLedger, type GeneralLedgerEntry } from "@/lib/api";
import { capitalize, formatAmount, formatTimestamp, truncateID } from "@/lib/format";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

const columns: ColumnDef<GeneralLedgerEntry>[] = [
  {
    key: "entry_id",
    label: "Entry ID",
    getValue: (e) => e.entry_id,
    render: (e) => <Text ff="monospace" fz="sm">{truncateID(e.entry_id)}</Text>,
  },
  {
    key: "txn_id",
    label: "Transaction",
    getValue: (e) => e.txn_id,
    render: (e) => (
      <Anchor component={Link} href={`/transactions/${e.txn_id}`} ff="monospace" fz="sm">
        {truncateID(e.txn_id)}
      </Anchor>
    ),
  },
  {
    key: "account_id",
    label: "Account",
    getValue: (e) => e.account_id,
    render: (e) => <Text ff="monospace" fz="sm">{truncateID(e.account_id)}</Text>,
  },
  {
    key: "entry_type",
    label: "Type",
    getValue: (e) => e.entry_type,
    render: (e) => (
      <Badge
        variant="light"
        color={e.entry_type === "debit" ? "red" : "teal"}
        radius="sm"
      >
        {capitalize(e.entry_type)}
      </Badge>
    ),
  },
  {
    key: "amount",
    label: "Amount",
    getValue: (e) => e.amount,
    render: (e) => formatAmount(e.amount, e.currency),
    ta: "right",
    ff: "monospace",
    fw: 500,
  },
  {
    key: "description",
    label: "Description",
    getValue: (e) => e.description,
  },
  {
    key: "posted_at",
    label: "Posted At",
    getValue: (e) => e.posted_at,
    render: (e) => formatTimestamp(e.posted_at),
  },
];

export default function GeneralLedgerPage() {
  const [accountId, setAccountId] = useState("");
  const [entryType, setEntryType] = useState<string | null>(null);
  const [currency, setCurrency] = useState<string | null>(null);
  const [fromMs, setFromMs] = useState("");
  const [toMs, setToMs] = useState("");
  const [page, setPage] = useState(1);
  const pageSize = 20;

  const [entries, setEntries] = useState<GeneralLedgerEntry[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = async (pg: number) => {
    setLoading(true);
    setError(null);
    try {
      const params: Parameters<typeof getGeneralLedger>[0] = {
        page: pg,
        page_size: pageSize,
      };
      if (accountId.trim()) params.account_id = accountId.trim();
      if (entryType) params.entry_type = entryType as "debit" | "credit";
      if (currency) params.currency = currency;
      if (fromMs.trim()) params.from_ms = parseInt(fromMs.trim(), 10);
      if (toMs.trim()) params.to_ms = parseInt(toMs.trim(), 10);
      const resp = await getGeneralLedger(params);
      setEntries(resp.items ?? []);
      setTotal(resp.total ?? 0);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  };

  const handleSearch = () => {
    setPage(1);
    void load(1);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter") void handleSearch();
  };

  const totalPages = Math.ceil(total / pageSize);

  return (
    <Stack gap="xl">
      <Stack gap="md">
        <Title order={2}>General Ledger</Title>
        <Text c="dimmed" size="sm">
          Full ledger entry log with filtering by account, type, currency, and date range.
        </Text>
      </Stack>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Stack gap="md">
          <Group grow wrap="wrap">
            <TextInput
              label="Account ID"
              placeholder="Filter by account ID…"
              value={accountId}
              onChange={(e) => setAccountId(e.currentTarget.value)}
              onKeyDown={handleKeyDown}
            />
            <Select
              label="Entry Type"
              placeholder="All types"
              value={entryType}
              onChange={setEntryType}
              data={[
                { value: "debit", label: "Debit" },
                { value: "credit", label: "Credit" },
              ]}
              clearable
            />
            <Select
              label="Currency"
              placeholder="All currencies"
              value={currency}
              onChange={(val) => setCurrency(val)}
              data={["USD", "EUR", "GBP", "CAD", "AUD"]}
              clearable
            />
          </Group>
          <Group grow wrap="wrap">
            <TextInput
              label="From (ms epoch)"
              placeholder="Start timestamp in ms…"
              value={fromMs}
              onChange={(e) => setFromMs(e.currentTarget.value)}
              onKeyDown={handleKeyDown}
            />
            <TextInput
              label="To (ms epoch)"
              placeholder="End timestamp in ms…"
              value={toMs}
              onChange={(e) => setToMs(e.currentTarget.value)}
              onKeyDown={handleKeyDown}
            />
          </Group>
          <Group>
            <Button onClick={() => void load(page)} loading={loading}>
              Apply Filters
            </Button>
            <Button variant="subtle" onClick={() => {
              setAccountId("");
              setEntryType(null);
              setCurrency(null);
              setFromMs("");
              setToMs("");
              setPage(1);
              void load(1);
            }}>
              Clear
            </Button>
          </Group>
        </Stack>
      </Card>

      {error && (
        <Card withBorder radius="md" padding="lg">
          <Text c="red" role="alert">{error}</Text>
        </Card>
      )}

      {loading ? (
        <Card withBorder radius="md" padding="xl">
          <Group justify="center">
            <Loader size="sm" />
            <Text c="dimmed">Loading ledger entries…</Text>
          </Group>
        </Card>
      ) : entries.length === 0 && !error ? (
        <Card withBorder radius="md" padding="xl">
          <Text c="dimmed" ta="center">No ledger entries match the filters</Text>
        </Card>
      ) : (
        <>
          <Paper withBorder radius="md" shadow="sm">
            <SortableTable
              data={entries}
              columns={columns}
              rowKey={(e) => e.entry_id}
              searchPlaceholder="Search entries…"
              emptyMessage="No ledger entries found"
              minWidth={950}
            />
          </Paper>

          {totalPages > 1 && (
            <Group justify="center">
              <Pagination
                total={totalPages}
                value={page}
                onChange={(p) => { setPage(p); void load(p); }}
              />
              <Text c="dimmed" size="sm">
                {total} entries total
              </Text>
            </Group>
          )}
        </>
      )}
    </Stack>
  );
}