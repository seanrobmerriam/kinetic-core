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
  ThemeIcon,
  Title,
} from "@mantine/core";
import { IconArrowLeft } from "@/components/icons";
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
import type { Account, LedgerEntry, Party, Transaction } from "@/lib/types";

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

function BackLink() {
  return (
    <Anchor component={Link} href="/transfer" size="sm">
      <Group gap={4}>
        <IconArrowLeft size={14} />
        Back to Transfers
      </Group>
    </Anchor>
  );
}

function PartyAccountPanel({
  title,
  account,
  party,
  rawAccountId,
}: {
  title: string;
  account: Account | null;
  party: Party | null;
  rawAccountId: string | null;
}) {
  return (
    <Card withBorder shadow="sm" radius="md" padding="lg">
      <Title order={5} mb="md">{title}</Title>
      <Divider mb="md" />
      <Stack gap="sm">
        <InfoField
          label="Account"
          value={
            rawAccountId ? (
              <Anchor component={Link} href={`/accounts/${rawAccountId}`} size="sm" ff="monospace">
                {account?.name ? `${account.name} (${rawAccountId})` : rawAccountId}
              </Anchor>
            ) : (
              "—"
            )
          }
        />
        {account && (
          <>
            <InfoField label="Currency" value={account.currency} />
            <InfoField
              label="Balance"
              value={formatAmount(account.balance, account.currency)}
              mono
            />
            <InfoField label="Account Status" value={capitalize(account.status ?? "—")} />
          </>
        )}
        <InfoField
          label="Party"
          value={
            party ? (
              <Anchor component={Link} href={`/customers/${party.party_id}`} size="sm">
                {party.full_name}
              </Anchor>
            ) : (
              "—"
            )
          }
        />
        {party && <InfoField label="Email" value={party.email} />}
      </Stack>
    </Card>
  );
}

export default function TransferDetailPage({
  params,
}: {
  params: Promise<{ txnId: string }>;
}) {
  const { txnId } = use(params);
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();

  const [txn, setTxn] = useState<Transaction | null>(null);
  const [entries, setEntries] = useState<LedgerEntry[]>([]);
  const [sourceAccount, setSourceAccount] = useState<Account | null>(null);
  const [destAccount, setDestAccount] = useState<Account | null>(null);
  const [sourceParty, setSourceParty] = useState<Party | null>(null);
  const [destParty, setDestParty] = useState<Party | null>(null);
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

        const sideLoads: Promise<unknown>[] = [];
        sideLoads.push(
          api<EntriesResponse>("GET", `/transactions/${txnId}/entries`)
            .then((r) => {
              if (!cancelled) setEntries(r.items ?? []);
            })
            .catch((err) => {
              if (!cancelled) setError((err as Error).message);
            }),
        );
        if (t.source_account_id) {
          sideLoads.push(
            api<Account>("GET", `/accounts/${t.source_account_id}`)
              .then(async (a) => {
                if (cancelled) return;
                setSourceAccount(a);
                if (a.party_id) {
                  try {
                    const p = await api<Party>("GET", `/parties/${a.party_id}`);
                    if (!cancelled) setSourceParty(p);
                  } catch { /* ignore */ }
                }
              })
              .catch(() => {}),
          );
        }
        if (t.dest_account_id) {
          sideLoads.push(
            api<Account>("GET", `/accounts/${t.dest_account_id}`)
              .then(async (a) => {
                if (cancelled) return;
                setDestAccount(a);
                if (a.party_id) {
                  try {
                    const p = await api<Party>("GET", `/parties/${a.party_id}`);
                    if (!cancelled) setDestParty(p);
                  } catch { /* ignore */ }
                }
              })
              .catch(() => {}),
          );
        }
        await Promise.all(sideLoads);
      } catch (err) {
        if (!cancelled) setLoadError((err as Error).message);
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
      setSuccess("Transfer reversed");
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
        <Text c="dimmed">Loading transfer…</Text>
      </Stack>
    );
  }

  if (loadError || !txn) {
    return (
      <Stack gap="lg">
        <BackLink />
        <Alert color="red" title="Could not load transfer">
          {loadError ?? "Transfer not found."}
        </Alert>
      </Stack>
    );
  }

  const reversible = canReverse(txn);
  const reversed = isReversed(txn);

  return (
    <Stack gap="lg">
      <BackLink />

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Group justify="space-between" align="flex-start" wrap="nowrap">
          <div>
            <Title order={3}>Transfer</Title>
            <Text size="xs" c="dimmed" ff="monospace" mt={4}>
              ID: {txn.txn_id}
            </Text>
          </div>
          <Group gap="xs">
            <Badge variant="light" color="gray" radius="sm">
              {capitalize(txn.txn_type)}
            </Badge>
            <Badge size="lg" variant="light" color={statusColor(txn.status)} radius="sm">
              {capitalize(txn.status)}
            </Badge>
            {reversible && (
              <Button
                color="yellow"
                variant="light"
                size="sm"
                onClick={() => setReverseOpen(true)}
              >
                Reverse transfer
              </Button>
            )}
          </Group>
        </Group>
      </Card>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={5} mb="md">Summary</Title>
        <Divider mb="md" />
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
          <InfoField
            label="Amount"
            value={formatAmount(txn.amount, txn.currency)}
            mono
          />
          <InfoField label="Currency" value={txn.currency} />
          <InfoField label="Memo" value={txn.description ?? "—"} />
          <InfoField label="Idempotency Key" value={txn.idempotency_key ?? "—"} mono />
          <InfoField label="Created" value={formatTimestamp(txn.created_at)} />
          <InfoField label="Posted" value={formatTimestamp(txn.posted_at)} />
        </SimpleGrid>
      </Card>

      <SimpleGrid cols={{ base: 1, md: 2 }} spacing="lg">
        <PartyAccountPanel
          title="From"
          account={sourceAccount}
          party={sourceParty}
          rawAccountId={txn.source_account_id ?? null}
        />
        <PartyAccountPanel
          title="To"
          account={destAccount}
          party={destParty}
          rawAccountId={txn.dest_account_id ?? null}
        />
      </SimpleGrid>

      {reversed && (
        <Alert color="gray" title="This transfer has been reversed">
          A reversing transaction has already been posted. The Reverse action is
          unavailable.
        </Alert>
      )}

      {!balance.balanced && entries.length > 0 && (
        <Alert color="red" title="Ledger entries do not balance">
          Per double-entry accounting, debits should equal credits per currency.
          {Object.entries(balance.sums).map(([ccy, s]) => (
            <Text key={ccy} size="sm" mt={4}>
              {ccy}: debits {formatAmount(s.debits, ccy)}, credits{" "}
              {formatAmount(s.credits, ccy)}, diff {formatAmount(s.diff, ccy)}
            </Text>
          ))}
        </Alert>
      )}

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Group justify="space-between" align="center" mb="md">
          <Title order={5}>Ledger Entries</Title>
          <Anchor component={Link} href={`/transactions/${txn.txn_id}`} size="sm">
            Open in Transaction view
          </Anchor>
        </Group>
        <Divider mb="md" />
        {entries.length === 0 ? (
          <Text c="dimmed" size="sm">No ledger entries.</Text>
        ) : (
          <Stack gap="xs">
            {entries.map((e) => (
              <Paper key={e.entry_id} withBorder p="sm" radius="sm">
                <Group justify="space-between" wrap="nowrap">
                  <Group gap="sm" wrap="nowrap">
                    <ThemeIcon
                      variant="light"
                      color={e.entry_type === "credit" ? "teal" : "red"}
                      size="sm"
                      radius="sm"
                    >
                      {e.entry_type === "credit" ? "+" : "−"}
                    </ThemeIcon>
                    <div>
                      <Anchor
                        component={Link}
                        href={`/accounts/${e.account_id}`}
                        size="sm"
                        ff="monospace"
                      >
                        {e.account_id}
                      </Anchor>
                      <Text size="xs" c="dimmed">
                        {capitalize(e.entry_type)} · {formatTimestamp(e.posted_at)}
                      </Text>
                    </div>
                  </Group>
                  <Text size="sm" ff="monospace" fw={500}>
                    {formatAmount(e.amount, e.currency)}
                  </Text>
                </Group>
              </Paper>
            ))}
          </Stack>
        )}
      </Card>

      <Modal
        opened={reverseOpen}
        onClose={() => (reverseBusy ? undefined : setReverseOpen(false))}
        title="Reverse transfer?"
        centered
        withCloseButton={!reverseBusy}
      >
        <Stack gap="md">
          <Text size="sm">
            Reversing this transfer will create an offsetting set of ledger entries.
            The original will remain in the ledger and be marked{" "}
            <Text span fw={600}>reversed</Text>. This action is recorded in the audit
            trail and cannot be undone.
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
