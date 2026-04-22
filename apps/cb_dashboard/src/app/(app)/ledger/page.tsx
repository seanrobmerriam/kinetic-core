"use client";

import { useEffect, useState } from "react";
import {
  Badge,
  Button,
  Card,
  Group,
  Loader,
  Paper,
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
    render: (e) => truncateID(e.txn_id),
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
];

export default function LedgerPage() {
  const { setError } = useNotify();

  const [latestEntries, setLatestEntries] = useState<LedgerEntry[]>([]);
  const [latestLoading, setLatestLoading] = useState(true);
  const [latestError, setLatestError] = useState<string | null>(null);

  const [accountId, setAccountId] = useState("");
  const [entries, setEntries] = useState<LedgerEntry[]>([]);
  const [loaded, setLoaded] = useState(false);

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
    if (!accountId) return;
    try {
      const resp = await api<ListResponse<LedgerEntry>>(
        "GET",
        `/accounts/${accountId}/entries`,
      );
      setEntries(resp.items ?? []);
      setLoaded(true);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <Stack gap="xl">
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
                minWidth={900}
              />
            </Paper>
          )}
        </Stack>
      </section>

      <section aria-labelledby="account-filter-heading">
        <Stack gap="md">
          <Title id="account-filter-heading" order={3}>
            Ledger Entries by Account
          </Title>

          <Card withBorder shadow="sm" radius="md" padding="lg">
            <Group align="flex-end" wrap="nowrap">
              <TextInput
                id="ledger-account-filter"
                label="Filter by Account ID"
                placeholder="Enter account ID"
                value={accountId}
                onChange={(e) => setAccountId(e.currentTarget.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") filter();
                }}
                style={{ flex: 1 }}
              />
              <Button onClick={filter}>Filter</Button>
            </Group>
          </Card>

          {!loaded || entries.length === 0 ? (
            <Card withBorder padding="xl" radius="md">
              <Text c="dimmed" ta="center">
                {loaded
                  ? "No ledger entries found"
                  : "Select an account to view ledger entries"}
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
                minWidth={900}
              />
            </Paper>
          )}
        </Stack>
      </section>
    </Stack>
  );
}
