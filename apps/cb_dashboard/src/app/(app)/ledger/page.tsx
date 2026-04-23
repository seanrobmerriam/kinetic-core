"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  Anchor,
  Badge,
  Button,
  Card,
  Group,
  Loader,
  Paper,
  Select,
  Stack,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import {
  capitalize,
  formatAmount,
  formatTimestamp,
  truncateID,
} from "@/lib/format";
import type { LedgerEntry } from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

interface ListResponse<T> {
  items: T[];
}

const entryColumns: ColumnDef<LedgerEntry>[] = [
  {
    key: "entry_id",
    label: "Entry ID",
    getValue: (e) => e.entry_id,
    render: (e) => truncateID(e.entry_id),
    ff: "monospace",
  },
  {
    key: "txn_id",
    label: "Transaction ID",
    getValue: (e) => e.txn_id,
    render: (e) => (
      <Anchor
        component={Link}
        href={`/transactions/${e.txn_id}`}
        size="sm"
        ff="monospace"
      >
        {truncateID(e.txn_id)}
      </Anchor>
    ),
    ff: "monospace",
  },
  {
    key: "account_id",
    label: "Account ID",
    getValue: (e) => e.account_id,
    render: (e) => truncateID(e.account_id),
    ff: "monospace",
  },
  {
    key: "type",
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
  {
    key: "actions",
    label: "",
    sortable: false,
    render: (e) => (
      <Button
        component={Link}
        href={`/transactions/${e.txn_id}`}
        size="xs"
        variant="subtle"
      >
        View
      </Button>
    ),
  },
];

export default function LedgerPage() {
  const { setError } = useNotify();

  const [latestEntries, setLatestEntries] = useState<LedgerEntry[]>([]);
  const [latestLoading, setLatestLoading] = useState(true);
  const [latestError, setLatestError] = useState<string | null>(null);

  const [accountId, setAccountId] = useState("");
  const [txnId, setTxnId] = useState("");
  const [entryType, setEntryType] = useState<string | null>(null);
  const [entries, setEntries] = useState<LedgerEntry[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [filterLoading, setFilterLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const resp = await api<ListResponse<LedgerEntry>>(
          "GET",
          "/ledger/entries/latest?limit=20",
        );
        if (!cancelled) {
          setLatestEntries(resp.items ?? []);
          setLatestLoading(false);
        }
      } catch (err) {
        if (!cancelled) {
          setLatestError((err as Error).message);
          setLatestLoading(false);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const filter = async () => {
    setFilterLoading(true);
    try {
      let results: LedgerEntry[];
      if (accountId.trim()) {
        const resp = await api<ListResponse<LedgerEntry>>(
          "GET",
          `/accounts/${accountId.trim()}/entries`,
        );
        results = resp.items ?? [];
      } else {
        results = [...latestEntries];
      }
      if (txnId.trim()) {
        const needle = txnId.trim().toLowerCase();
        results = results.filter((e) =>
          e.txn_id.toLowerCase().includes(needle),
        );
      }
      if (entryType && entryType !== "all") {
        results = results.filter((e) => e.entry_type === entryType);
      }
      setEntries(results);
      setLoaded(true);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setFilterLoading(false);
    }
  };

  const clearFilters = () => {
    setAccountId("");
    setTxnId("");
    setEntryType(null);
    setEntries([]);
    setLoaded(false);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter") void filter();
  };

  return (
    <Stack gap="xl">
      <section aria-labelledby="account-filter-heading">
        <Stack gap="md">
          <Title id="account-filter-heading" order={3}>
            Filter Ledger Entries
          </Title>

          <Card withBorder shadow="sm" radius="md" padding="lg">
            <Stack gap="md">
              <Group grow wrap="wrap">
                <TextInput
                  id="ledger-account-filter"
                  label="Account ID"
                  placeholder="Filter by account ID"
                  value={accountId}
                  onChange={(e) => setAccountId(e.currentTarget.value)}
                  onKeyDown={handleKeyDown}
                />
                <TextInput
                  id="ledger-txn-filter"
                  label="Transaction ID"
                  placeholder="Filter by transaction ID"
                  value={txnId}
                  onChange={(e) => setTxnId(e.currentTarget.value)}
                  onKeyDown={handleKeyDown}
                />
                <Select
                  label="Entry Type"
                  placeholder="All types"
                  value={entryType}
                  onChange={setEntryType}
                  data={[
                    { value: "all", label: "All types" },
                    { value: "debit", label: "Debit" },
                    { value: "credit", label: "Credit" },
                  ]}
                  clearable
                />
              </Group>
              <Group>
                <Button onClick={() => void filter()} loading={filterLoading}>
                  Apply Filters
                </Button>
                <Button variant="subtle" onClick={clearFilters}>
                  Clear
                </Button>
              </Group>
            </Stack>
          </Card>

          {loaded &&
            (entries.length === 0 ? (
              <Card withBorder padding="xl" radius="md">
                <Text c="dimmed" ta="center">
                  No ledger entries match the filters
                </Text>
              </Card>
            ) : (
              <Paper withBorder radius="md" shadow="sm">
                <SortableTable
                  data={entries}
                  columns={entryColumns}
                  rowKey={(e) => e.entry_id}
                  searchPlaceholder="Search entries…"
                  emptyMessage="No ledger entries found"
                  minWidth={950}
                />
              </Paper>
            ))}
        </Stack>
      </section>

      <section aria-labelledby="latest-entries-heading">
        <Stack gap="md">
          <Title id="latest-entries-heading" order={3}>
            Latest Transactions
          </Title>

          {latestLoading ? (
            <Card withBorder padding="xl" radius="md">
              <Group justify="center">
                <Loader size="sm" />
                <Text c="dimmed">Loading latest transactions…</Text>
              </Group>
            </Card>
          ) : latestError ? (
            <Card withBorder padding="xl" radius="md">
              <Text c="red" ta="center" role="alert">
                {latestError}
              </Text>
            </Card>
          ) : latestEntries.length === 0 ? (
            <Card withBorder padding="xl" radius="md">
              <Text c="dimmed" ta="center">
                No ledger entries found
              </Text>
            </Card>
          ) : (
            <Paper withBorder radius="md" shadow="sm">
              <SortableTable
                data={latestEntries}
                columns={entryColumns}
                rowKey={(e) => e.entry_id}
                searchPlaceholder="Search latest entries…"
                emptyMessage="No ledger entries found"
                minWidth={950}
              />
            </Paper>
          )}
        </Stack>
      </section>
    </Stack>
  );
}
