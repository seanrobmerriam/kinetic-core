"use client";

import { useEffect, useState } from "react";
import {
  Badge,
  Button,
  Card,
  Group,
  Loader,
  Paper,
  Select,
  SimpleGrid,
  Stack,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { getTrialBalance, type TrialBalanceEntry } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { formatAmount } from "@/lib/format";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

const columns: ColumnDef<TrialBalanceEntry>[] = [
  {
    key: "account_id",
    label: "Account ID",
    getValue: (e) => e.account_id,
    ff: "monospace",
  },
  {
    key: "account_name",
    label: "Account Name",
    getValue: (e) => e.account_name,
  },
  {
    key: "debit",
    label: "Debit (Minor Units)",
    getValue: (e) => e.debit_balance_minor,
    render: (e) => formatAmount(e.debit_balance_minor, e.currency),
    ta: "right",
    ff: "monospace",
  },
  {
    key: "credit",
    label: "Credit (Minor Units)",
    getValue: (e) => e.credit_balance_minor,
    render: (e) => formatAmount(e.credit_balance_minor, e.currency),
    ta: "right",
    ff: "monospace",
  },
  {
    key: "balanced",
    label: "Status",
    sortable: false,
    render: (e) => {
      const diff = e.debit_balance_minor - e.credit_balance_minor;
      if (diff === 0) {
        return <Badge color="teal" variant="light" radius="sm">Balanced</Badge>;
      }
      return <Badge color="red" variant="light" radius="sm">Off by {Math.abs(diff)}</Badge>;
    },
  },
];

export default function TrialBalancePage() {
  const { setError } = useNotify();
  const [currency, setCurrency] = useState<string | null>("USD");
  const [asOfDate, setAsOfDate] = useState("");
  const [entries, setEntries] = useState<TrialBalanceEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setLocalError] = useState<string | null>(null);
  const [generatedAt, setGeneratedAt] = useState<number | null>(null);

  const load = async () => {
    if (!currency) return;
    setLoading(true);
    setLocalError(null);
    try {
      const params: { currency?: string; as_of_date?: string } = { currency };
      if (asOfDate.trim()) params.as_of_date = asOfDate.trim();
      const resp = await getTrialBalance(params);
      setEntries(resp.accounts ?? []);
      setGeneratedAt(resp.generated_at ?? null);
    } catch (err) {
      setLocalError((err as Error).message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const totalDebits = entries.reduce((s, e) => s + e.debit_balance_minor, 0);
  const totalCredits = entries.reduce((s, e) => s + e.credit_balance_minor, 0);
  const balanced = totalDebits === totalCredits;

  return (
    <Stack gap="xl">
      <Stack gap="md">
        <Title order={2}>Trial Balance</Title>
        <Text c="dimmed" size="sm">
          Per-account debit and credit breakdown. Use the date filter for a
          point-in-time view.
        </Text>
      </Stack>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Stack gap="md">
          <Group grow wrap="wrap">
            <Select
              label="Currency"
              value={currency}
              onChange={(val) => { if (val) setCurrency(val); }}
              data={["USD", "EUR", "GBP", "CAD", "AUD"]}
              placeholder="Select currency…"
            />
            <TextInput
              label="As-of Date"
              placeholder="YYYY-MM-DD"
              value={asOfDate}
              onChange={(e) => setAsOfDate(e.currentTarget.value)}
              description="Leave blank for current balances"
            />
          </Group>
          <Button onClick={() => void load()} loading={loading}>
            Refresh
          </Button>
        </Stack>
      </Card>

      {error && (
        <Card withBorder radius="md" padding="lg">
          <Text c="red" role="alert">{error}</Text>
        </Card>
      )}

      {generatedAt && (
        <Text c="dimmed" size="xs">
          Generated at: {new Date(generatedAt).toLocaleString()}
        </Text>
      )}

      {entries.length > 0 && (
        <>
          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="md">
            <Card withBorder radius="md" padding="md">
              <Text size="xs" c="dimmed" tt="uppercase">Total Debits</Text>
              <Text fw={700} ff="monospace" fz="lg">
                {formatAmount(totalDebits, currency ?? "USD")}
              </Text>
            </Card>
            <Card withBorder radius="md" padding="md">
              <Text size="xs" c="dimmed" tt="uppercase">Total Credits</Text>
              <Text fw={700} ff="monospace" fz="lg">
                {formatAmount(totalCredits, currency ?? "USD")}
              </Text>
            </Card>
            <Card withBorder radius="md" padding="md">
              <Text size="xs" c="dimmed" tt="uppercase">Status</Text>
              <Badge
                color={balanced ? "teal" : "red"}
                variant="light"
                size="lg"
                mt={4}
              >
                {balanced ? "Balanced" : `Off by ${totalDebits - totalCredits}`}
              </Badge>
            </Card>
          </SimpleGrid>

          <Paper withBorder radius="md" shadow="sm">
            <SortableTable
              data={entries}
              columns={columns}
              rowKey={(e) => e.account_id}
              searchPlaceholder="Search accounts…"
              emptyMessage="No accounts found"
              minWidth={700}
            />
          </Paper>
        </>
      )}

      {!loading && entries.length === 0 && !error && (
        <Card withBorder radius="md" padding="xl">
          <Text c="dimmed" ta="center">
            No trial balance data available for {currency}.
          </Text>
        </Card>
      )}
    </Stack>
  );
}