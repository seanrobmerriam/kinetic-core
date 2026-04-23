"use client";

import Link from "next/link";
import { use, useEffect, useMemo, useState } from "react";
import {
  Alert,
  Anchor,
  Badge,
  Button,
  Card,
  Divider,
  Group,
  Modal,
  Paper,
  SimpleGrid,
  Stack,
  Text,
  Title,
} from "@mantine/core";
import {
  IconAlertTriangle,
  IconArrowLeft,
} from "@tabler/icons-react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import {
  capitalize,
  formatAmount,
  formatTimestamp,
} from "@/lib/format";
import {
  canReverse,
  entriesAreBalanced,
  isReversed,
} from "@/lib/transaction";
import type { LedgerEntry, Transaction } from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

interface EntriesResponse {
  items: LedgerEntry[];
}

function statusColor(s: string) {
  if (s === "posted") return "teal";
  if (s === "pending") return "yellow";
  if (s === "reversed") return "gray";
  if (s === "failed") return "red";
  return "gray";
}

function entryTypeColor(t: string) {
  if (t === "credit") return "teal";
  if (t === "debit") return "red";
  return "gray";
}

function InfoField({
  label,
  value,
  mono,
}: {
  label: string;
  value: React.ReactNode;
  mono?: boolean;
}) {
  return (
    <div>
      <Text size="xs" c="dimmed" tt="uppercase" fw={700} mb={2}>
        {label}
      </Text>
      <Text size="sm" ff={mono ? "monospace" : undefined}>
        {value ?? "—"}
      </Text>
    </div>
  );
}

export default function TransactionDetailPage({
  params,
}: {
  params: Promise<{ txnId: string }>;
}) {
  const { txnId } = use(params);
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [txn, setTxn] = useState<Transaction | null>(null);
  const [entries, setEntries] = useState<LedgerEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [reverseOpen, setReverseOpen] = useState(false);
  const [reverseBusy, setReverseBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!cancelled) {
        setLoading(true);
        setLoadError(null);
      }
      try {
        const t = await api<Transaction>("GET", `/transactions/${txnId}`);
        if (cancelled) return;
        setTxn(t);
      } catch (err) {
        if (!cancelled) {
          setLoadError((err as Error).message);
          setLoading(false);
        }
        return;
      }
      try {
        const resp = await api<EntriesResponse>(
          "GET",
          `/transactions/${txnId}/entries`,
        );
        if (!cancelled) setEntries(resp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [txnId, tick, setError]);

  const balance = useMemo(() => entriesAreBalanced(entries), [entries]);

  const reverse = async () => {
    if (!txn) return;
    setReverseBusy(true);
    try {
      await api("POST", `/transactions/${txn.txn_id}/reverse`);
      setSuccess("Transaction reversed");
      setReverseOpen(false);
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setReverseBusy(false);
    }
  };

  if (loading && !txn) {
    return (
      <Stack gap="lg">
        <BackLink />
        <Text c="dimmed">Loading transaction…</Text>
      </Stack>
    );
  }

  if (loadError || !txn) {
    return (
      <Stack gap="lg">
        <BackLink />
        <Alert color="red" title="Could not load transaction">
          {loadError ?? "Transaction not found."}
        </Alert>
      </Stack>
    );
  }

  const entryColumns: ColumnDef<LedgerEntry>[] = [
    {
      key: "entry_id",
      label: "Entry ID",
      getValue: (e) => e.entry_id,
      ff: "monospace",
    },
    {
      key: "account_id",
      label: "Account",
      getValue: (e) => e.account_id,
      render: (e) => (
        <Anchor
          component={Link}
          href={`/accounts/${e.account_id}`}
          size="sm"
          ff="monospace"
        >
          {e.account_id}
        </Anchor>
      ),
    },
    {
      key: "entry_type",
      label: "Type",
      getValue: (e) => e.entry_type,
      render: (e) => (
        <Badge variant="light" color={entryTypeColor(e.entry_type)} radius="sm">
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
    { key: "currency", label: "Currency", getValue: (e) => e.currency },
    {
      key: "posted_at",
      label: "Posted",
      getValue: (e) => e.posted_at,
      render: (e) => formatTimestamp(e.posted_at),
    },
    {
      key: "description",
      label: "Description",
      getValue: (e) => e.description ?? "",
    },
  ];

  const reversible = canReverse(txn);
  const reversed = isReversed(txn);

  return (
    <Stack gap="lg">
      <BackLink />

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Group justify="space-between" align="flex-start" wrap="nowrap">
          <div>
            <Title order={3}>Transaction</Title>
            <Text size="xs" c="dimmed" ff="monospace" mt={4}>
              ID: {txn.txn_id}
            </Text>
          </div>
          <Group gap="xs">
            <Badge variant="light" color="gray" radius="sm">
              {capitalize(txn.txn_type)}
            </Badge>
            <Badge
              size="lg"
              variant="light"
              color={statusColor(txn.status)}
              radius="sm"
            >
              {capitalize(txn.status)}
            </Badge>
            {reversible && (
              <Button
                color="yellow"
                variant="light"
                size="sm"
                onClick={() => setReverseOpen(true)}
              >
                Reverse transaction
              </Button>
            )}
          </Group>
        </Group>
      </Card>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={5} mb="md">
          Transaction Details
        </Title>
        <Divider mb="md" />
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
          <InfoField
            label="Amount"
            value={formatAmount(txn.amount, txn.currency)}
            mono
          />
          <InfoField label="Currency" value={txn.currency} />
          <InfoField label="Description" value={txn.description ?? "—"} />
          <InfoField
            label="Source Account"
            value={
              txn.source_account_id ? (
                <Anchor
                  component={Link}
                  href={`/accounts/${txn.source_account_id}`}
                  size="sm"
                  ff="monospace"
                >
                  {txn.source_account_id}
                </Anchor>
              ) : (
                "—"
              )
            }
          />
          <InfoField
            label="Destination Account"
            value={
              txn.dest_account_id ? (
                <Anchor
                  component={Link}
                  href={`/accounts/${txn.dest_account_id}`}
                  size="sm"
                  ff="monospace"
                >
                  {txn.dest_account_id}
                </Anchor>
              ) : (
                "—"
              )
            }
          />
          <InfoField
            label="Idempotency Key"
            value={txn.idempotency_key ?? "—"}
            mono
          />
          <InfoField label="Created" value={formatTimestamp(txn.created_at)} />
          <InfoField label="Posted" value={formatTimestamp(txn.posted_at)} />
        </SimpleGrid>
      </Card>

      {reversed && (
        <Alert color="gray" title="This transaction has been reversed">
          A reversing transaction has already been posted. The Reverse action is
          unavailable.
        </Alert>
      )}

      {!balance.balanced && entries.length > 0 && (
        <Alert
          color="red"
          title="Ledger entries do not balance"
          icon={<IconAlertTriangle size={18} />}
        >
          Per double-entry accounting, debits should equal credits per currency.
          {Object.entries(balance.sums).map(([ccy, s]) => (
            <Text key={ccy} size="sm" mt={4}>
              {ccy}: debits {formatAmount(s.debits, ccy)}, credits{" "}
              {formatAmount(s.credits, ccy)}, diff {formatAmount(s.diff, ccy)}
            </Text>
          ))}
        </Alert>
      )}

      <div>
        <Title order={4} mb="sm">
          Ledger Entries
        </Title>
        <Paper withBorder radius="md" shadow="sm">
          <SortableTable
            data={entries}
            columns={entryColumns}
            rowKey={(e) => e.entry_id}
            searchPlaceholder="Search entries..."
            emptyMessage="No ledger entries found"
            minWidth={900}
          />
        </Paper>
      </div>

      <Modal
        opened={reverseOpen}
        onClose={() => (reverseBusy ? undefined : setReverseOpen(false))}
        title="Reverse transaction?"
        centered
        withCloseButton={!reverseBusy}
      >
        <Stack gap="md">
          <Text size="sm">
            Reversing this transaction will create an offsetting set of ledger
            entries. The original transaction will remain in the ledger and be
            marked <Text span fw={600}>reversed</Text>. This action is recorded
            in the audit trail and cannot be undone.
          </Text>
          <Group justify="flex-end">
            <Button
              variant="default"
              onClick={() => setReverseOpen(false)}
              disabled={reverseBusy}
            >
              Cancel
            </Button>
            <Button color="yellow" onClick={reverse} loading={reverseBusy}>
              Reverse
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}

function BackLink() {
  return (
    <Anchor component={Link} href="/transactions" size="sm">
      <Group gap={4}>
        <IconArrowLeft size={14} />
        Back to Transactions
      </Group>
    </Anchor>
  );
}
