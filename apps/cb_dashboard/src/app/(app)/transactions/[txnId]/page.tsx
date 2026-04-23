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
  Table,
  TagsInput,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import {
  IconAlertTriangle,
  IconArrowLeft,
} from "@/components/icons";
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
import type { LedgerEntry, Transaction, TransactionReceipt, TransactionTag } from "@/lib/types";
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
  const [tags, setTags] = useState<TransactionTag | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  // Reverse modal
  const [reverseOpen, setReverseOpen] = useState(false);
  const [reverseBusy, setReverseBusy] = useState(false);

  // Receipt modal
  const [receiptOpen, setReceiptOpen] = useState(false);
  const [receipt, setReceipt] = useState<TransactionReceipt | null>(null);
  const [receiptLoading, setReceiptLoading] = useState(false);

  // Tags edit modal
  const [tagsOpen, setTagsOpen] = useState(false);
  const [editCategory, setEditCategory] = useState("");
  const [editTags, setEditTags] = useState<string[]>([]);
  const [tagsBusy, setTagsBusy] = useState(false);

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
      await Promise.allSettled([
        api<EntriesResponse>("GET", `/transactions/${txnId}/entries`).then((r) => {
          if (!cancelled) setEntries(r.items ?? []);
        }),
        api<TransactionTag>("GET", `/transactions/${txnId}/tags`).then((r) => {
          if (!cancelled) setTags(r);
        }),
      ]);
      if (!cancelled) setLoading(false);
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

  const openReceipt = async () => {
    setReceiptLoading(true);
    setReceiptOpen(true);
    try {
      const r = await api<TransactionReceipt>(
        "GET",
        `/transactions/${txnId}/receipt`,
      );
      setReceipt(r);
    } catch (err) {
      setError((err as Error).message);
      setReceiptOpen(false);
    } finally {
      setReceiptLoading(false);
    }
  };

  const openTagsEdit = () => {
    setEditCategory(tags?.category ?? "");
    setEditTags(tags?.tags ?? []);
    setTagsOpen(true);
  };

  const saveTags = async () => {
    setTagsBusy(true);
    try {
      const updated = await api<TransactionTag>(
        "PUT",
        `/transactions/${txnId}/tags`,
        { category: editCategory || undefined, tags: editTags },
      );
      setTags(updated);
      setSuccess("Tags saved");
      setTagsOpen(false);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setTagsBusy(false);
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

      {/* Header */}
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
            <Button
              variant="light"
              size="sm"
              onClick={openReceipt}
            >
              Receipt
            </Button>
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

      {/* Details */}
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

      {/* Tags & Category */}
      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Group justify="space-between" mb="md">
          <Title order={5}>Tags &amp; Category</Title>
          <Button size="xs" variant="light" onClick={openTagsEdit}>
            {tags ? "Edit tags" : "Add tags"}
          </Button>
        </Group>
        <Divider mb="md" />
        {tags ? (
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="md">
            <InfoField label="Category" value={tags.category ?? "—"} />
            <InfoField
              label="Tags"
              value={
                tags.tags.length > 0 ? (
                  <Group gap={4} mt={2}>
                    {tags.tags.map((tag) => (
                      <Badge key={tag} variant="outline" radius="sm" size="sm">
                        {tag}
                      </Badge>
                    ))}
                  </Group>
                ) : (
                  "—"
                )
              }
            />
          </SimpleGrid>
        ) : (
          <Text size="sm" c="dimmed">
            No tags set. Click &ldquo;Add tags&rdquo; to categorise this
            transaction.
          </Text>
        )}
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

      {/* Ledger Entries */}
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

      {/* Reverse modal */}
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

      {/* Receipt modal */}
      <Modal
        opened={receiptOpen}
        onClose={() => setReceiptOpen(false)}
        title="Transaction Receipt"
        size="lg"
        centered
      >
        {receiptLoading || !receipt ? (
          <Text c="dimmed" size="sm">Loading receipt…</Text>
        ) : (
          <Stack gap="md">
            <SimpleGrid cols={2} spacing="sm">
              <InfoField label="Transaction ID" value={receipt.txn_id} mono />
              <InfoField label="Type" value={capitalize(receipt.txn_type)} />
              <InfoField
                label="Status"
                value={
                  <Badge variant="light" color={statusColor(receipt.status)} radius="sm">
                    {capitalize(receipt.status)}
                  </Badge>
                }
              />
              <InfoField
                label="Amount"
                value={formatAmount(receipt.amount, receipt.currency)}
                mono
              />
              <InfoField label="Currency" value={receipt.currency} />
              <InfoField label="Channel" value={receipt.channel ?? "—"} />
              <InfoField label="Description" value={receipt.description ?? "—"} />
              <InfoField label="Created" value={formatTimestamp(receipt.created_at)} />
              <InfoField label="Posted" value={formatTimestamp(receipt.posted_at ?? 0)} />
              <InfoField label="Source Account" value={receipt.source_account_id ?? "—"} mono />
              <InfoField label="Destination Account" value={receipt.dest_account_id ?? "—"} mono />
            </SimpleGrid>

            {receipt.ledger_entries.length > 0 && (
              <>
                <Divider label="Ledger Entries" labelPosition="left" />
                <Table striped withTableBorder fz="sm">
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Account</Table.Th>
                      <Table.Th>Type</Table.Th>
                      <Table.Th ta="right">Amount</Table.Th>
                      <Table.Th>Posted</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {receipt.ledger_entries.map((e) => (
                      <Table.Tr key={e.entry_id}>
                        <Table.Td ff="monospace">{e.account_id}</Table.Td>
                        <Table.Td>
                          <Badge
                            variant="light"
                            color={entryTypeColor(e.entry_type)}
                            radius="sm"
                            size="sm"
                          >
                            {capitalize(e.entry_type)}
                          </Badge>
                        </Table.Td>
                        <Table.Td ta="right" ff="monospace">
                          {formatAmount(e.amount, e.currency)}
                        </Table.Td>
                        <Table.Td>{formatTimestamp(e.posted_at)}</Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </>
            )}
          </Stack>
        )}
      </Modal>

      {/* Tags edit modal */}
      <Modal
        opened={tagsOpen}
        onClose={() => (tagsBusy ? undefined : setTagsOpen(false))}
        title="Edit Tags &amp; Category"
        centered
        withCloseButton={!tagsBusy}
      >
        <Stack gap="md">
          <TextInput
            label="Category"
            placeholder="e.g. payroll, utilities, transfer"
            value={editCategory}
            onChange={(e) => setEditCategory(e.currentTarget.value)}
            aria-label="Transaction category"
          />
          <TagsInput
            label="Tags"
            placeholder="Type a tag and press Enter"
            value={editTags}
            onChange={setEditTags}
            aria-label="Transaction tags"
          />
          <Group justify="flex-end">
            <Button
              variant="default"
              onClick={() => setTagsOpen(false)}
              disabled={tagsBusy}
            >
              Cancel
            </Button>
            <Button onClick={saveTags} loading={tagsBusy}>
              Save
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
