"use client";

import Link from "next/link";
import { use, useEffect, useState } from "react";
import {
  Alert,
  Anchor,
  Badge,
  Button,
  Card,
  Divider,
  Group,
  SimpleGrid,
  Stack,
  Text,
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
import type { Account, Party, PaymentOrder } from "@/lib/types";

function statusColor(s: string) {
  if (s === "completed" || s === "settled") return "teal";
  if (s === "pending" || s === "processing" || s === "queued") return "yellow";
  if (s === "failed" || s === "cancelled") return "red";
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
    <Anchor component={Link} href="/payments" size="sm">
      <Group gap={4}>
        <IconArrowLeft size={14} />
        Back to Payments
      </Group>
    </Anchor>
  );
}

export default function PaymentDetailPage({
  params,
}: {
  params: Promise<{ paymentId: string }>;
}) {
  const { paymentId } = use(params);
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();

  const [order, setOrder] = useState<PaymentOrder | null>(null);
  const [party, setParty] = useState<Party | null>(null);
  const [sourceAccount, setSourceAccount] = useState<Account | null>(null);
  const [destAccount, setDestAccount] = useState<Account | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionBusy, setActionBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!cancelled) {
        setLoading(true);
        setLoadError(null);
      }
      try {
        const o = await api<PaymentOrder>(
          "GET",
          `/payment-orders/${paymentId}`,
        );
        if (cancelled) return;
        setOrder(o);

        const sideLoads: Promise<void>[] = [];
        if (o.party_id) {
          sideLoads.push(
            api<Party>("GET", `/parties/${o.party_id}`)
              .then((p) => {
                if (!cancelled) setParty(p);
              })
              .catch(() => {}),
          );
        }
        if (o.source_account_id) {
          sideLoads.push(
            api<Account>("GET", `/accounts/${o.source_account_id}`)
              .then((a) => {
                if (!cancelled) setSourceAccount(a);
              })
              .catch(() => {}),
          );
        }
        if (o.dest_account_id) {
          sideLoads.push(
            api<Account>("GET", `/accounts/${o.dest_account_id}`)
              .then((a) => {
                if (!cancelled) setDestAccount(a);
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
  }, [paymentId, tick]);

  const cancel = async () => {
    if (!order) return;
    setActionBusy(true);
    try {
      const updated = await api<PaymentOrder>(
        "POST",
        `/payment-orders/${order.payment_id}/cancel`,
        {},
      );
      setOrder(updated);
      setSuccess("Payment cancelled");
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setActionBusy(false);
    }
  };

  const retry = async () => {
    if (!order) return;
    setActionBusy(true);
    try {
      const updated = await api<PaymentOrder>(
        "POST",
        `/payment-orders/${order.payment_id}/retry`,
        {},
      );
      setOrder(updated);
      setSuccess("Payment retry initiated");
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setActionBusy(false);
    }
  };

  if (loading && !order) {
    return (
      <Stack gap="lg">
        <BackLink />
        <Text c="dimmed">Loading payment…</Text>
      </Stack>
    );
  }

  if (loadError || !order) {
    return (
      <Stack gap="lg">
        <BackLink />
        <Alert color="red" title="Could not load payment">
          {loadError ?? "Payment not found."}
        </Alert>
      </Stack>
    );
  }

  const cancellable = ["pending", "queued", "processing"].includes(order.status);
  const retryable = order.status === "failed";

  return (
    <Stack gap="lg">
      <BackLink />

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Group justify="space-between" align="flex-start" wrap="nowrap">
          <div>
            <Title order={3}>Payment Order</Title>
            <Text size="xs" c="dimmed" ff="monospace" mt={4}>
              ID: {order.payment_id}
            </Text>
          </div>
          <Group gap="xs">
            <Badge size="lg" variant="light" color={statusColor(order.status)} radius="sm">
              {capitalize(order.status)}
            </Badge>
            {cancellable && (
              <Button color="red" variant="light" size="sm" onClick={cancel} loading={actionBusy}>
                Cancel
              </Button>
            )}
            {retryable && (
              <Button color="yellow" variant="light" size="sm" onClick={retry} loading={actionBusy}>
                Retry
              </Button>
            )}
          </Group>
        </Group>
      </Card>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={5} mb="md">Payment Details</Title>
        <Divider mb="md" />
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
          <InfoField label="Amount" value={formatAmount(order.amount, order.currency)} mono />
          <InfoField label="Currency" value={order.currency} />
          <InfoField label="Description" value={order.description ?? "—"} />
          <InfoField
            label="Party"
            value={
              party ? (
                <Anchor component={Link} href={`/customers/${party.party_id}`} size="sm">
                  {party.full_name}
                </Anchor>
              ) : (
                order.party_id
              )
            }
            mono={!party}
          />
          <InfoField
            label="Source Account"
            value={
              order.source_account_id ? (
                <Anchor component={Link} href={`/accounts/${order.source_account_id}`} size="sm" ff="monospace">
                  {sourceAccount?.name
                    ? `${sourceAccount.name} (${order.source_account_id})`
                    : order.source_account_id}
                </Anchor>
              ) : (
                "—"
              )
            }
          />
          <InfoField
            label="Destination Account"
            value={
              order.dest_account_id ? (
                <Anchor component={Link} href={`/accounts/${order.dest_account_id}`} size="sm" ff="monospace">
                  {destAccount?.name
                    ? `${destAccount.name} (${order.dest_account_id})`
                    : order.dest_account_id}
                </Anchor>
              ) : (
                "—"
              )
            }
          />
          <InfoField label="STP Decision" value={order.stp_decision ?? "—"} />
          <InfoField label="Retry Count" value={String(order.retry_count ?? 0)} />
          <InfoField label="Failure Reason" value={order.failure_reason ?? "—"} />
          <InfoField label="Idempotency Key" value={order.idempotency_key ?? "—"} mono />
          <InfoField label="Created" value={formatTimestamp(order.created_at)} />
          <InfoField label="Updated" value={formatTimestamp(order.updated_at)} />
        </SimpleGrid>
      </Card>

      {order.status === "failed" && (
        <Alert color="yellow" title="Payment failed">
          {order.failure_reason
            ? `Reason: ${order.failure_reason}.`
            : "No failure reason recorded."}{" "}
          Use Retry to re-attempt, or open an exception in Compliance for manual handling.
        </Alert>
      )}
    </Stack>
  );
}
