"use client";

import { useEffect, useState } from "react";
import {
  Badge,
  Button,
  Card,
  Group,
  Paper,
  Select,
  Stack,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { formatAmount, formatTimestamp, truncateID } from "@/lib/format";
import type { Account, Party, PaymentOrder } from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

interface ListResponse<T> {
  items: T[];
}

function statusColor(s: string) {
  if (s === "completed") return "teal";
  if (s === "pending" || s === "processing") return "yellow";
  if (s === "failed" || s === "cancelled") return "red";
  return "gray";
}

export default function PaymentsPage() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();

  const [orders, setOrders] = useState<PaymentOrder[]>([]);
  const [parties, setParties] = useState<Party[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);

  const [partyId, setPartyId] = useState<string | null>(null);
  const [sourceId, setSourceId] = useState<string | null>(null);
  const [destId, setDestId] = useState<string | null>(null);
  const [amount, setAmount] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const partyList = partyResp.items ?? [];
        const allAccounts: Account[] = [];
        for (const p of partyList) {
          try {
            const accResp = await api<ListResponse<Account>>(
              "GET",
              `/parties/${p.party_id}/accounts`,
            );
            allAccounts.push(...(accResp.items ?? []));
          } catch {
            /* skip */
          }
        }
        if (!cancelled) {
          setParties(partyList);
          setAccounts(allAccounts);
        }
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const partyAccounts = accounts.filter((a) => a.party_id === partyId);
  const otherAccounts = accounts.filter((a) => a.party_id !== partyId);

  const initiate = async () => {
    if (!partyId || !sourceId || !destId || !amount || submitting) return;
    const amountInt = Math.round(parseFloat(amount) * 100);
    if (isNaN(amountInt) || amountInt <= 0) {
      setError("Invalid amount");
      return;
    }
    setSubmitting(true);
    try {
      const ikey = `pay-${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const order = await api<PaymentOrder>("POST", "/payment-orders", {
        idempotency_key: ikey,
        party_id: partyId,
        source_account_id: sourceId,
        dest_account_id: destId,
        amount: amountInt,
      });
      setOrders((prev) => [order, ...prev]);
      setSuccess("Payment order initiated");
      setSourceId(null);
      setDestId(null);
      setAmount("");
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  const cancel = async (id: string) => {
    try {
      const updated = await api<PaymentOrder>(
        "POST",
        `/payment-orders/${id}/cancel`,
        {},
      );
      setOrders((prev) => prev.map((o) => (o.payment_id === id ? updated : o)));
      setSuccess("Payment cancelled");
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const retry = async (id: string) => {
    try {
      const updated = await api<PaymentOrder>(
        "POST",
        `/payment-orders/${id}/retry`,
        {},
      );
      setOrders((prev) => prev.map((o) => (o.payment_id === id ? updated : o)));
      setSuccess("Payment retried");
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const partyOptions = parties.map((p) => ({
    value: p.party_id,
    label: p.full_name,
  }));

  const sourceOptions = partyAccounts.map((a) => ({
    value: a.account_id,
    label: `${a.name} (${formatAmount(a.balance, a.currency)})`,
  }));

  const destOptions = [
    ...otherAccounts,
    ...partyAccounts.filter((a) => a.account_id !== sourceId),
  ].map((a) => ({
    value: a.account_id,
    label: `${a.name} (${a.currency})`,
  }));

  return (
    <Stack gap="lg">
      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={4} mb="md">
          Initiate Payment Order
        </Title>
        <Stack>
          <Group grow>
            <Select
              label="Party"
              placeholder="Select party"
              data={partyOptions}
              value={partyId}
              onChange={setPartyId}
              searchable
            />
            <Select
              label="From Account"
              placeholder="Source account"
              data={sourceOptions}
              value={sourceId}
              onChange={setSourceId}
              disabled={!partyId}
            />
          </Group>
          <Group grow>
            <Select
              label="To Account"
              placeholder="Destination account"
              data={destOptions}
              value={destId}
              onChange={setDestId}
              disabled={!partyId}
            />
            <TextInput
              label="Amount"
              placeholder="0.00"
              value={amount}
              onChange={(e) => setAmount(e.currentTarget.value)}
              type="number"
              min="0"
              step="0.01"
            />
          </Group>
          <Group>
            <Button
              onClick={initiate}
              loading={submitting}
              disabled={!partyId || !sourceId || !destId || !amount}
            >
              Initiate Payment
            </Button>
          </Group>
        </Stack>
      </Card>

      {orders.length > 0 && (
        <Paper withBorder radius="md" shadow="sm">
          <Text fw={600} p="md" pb={0}>
            Recent Orders (This Session)
          </Text>
          <OrderTable orders={orders} onCancel={cancel} onRetry={retry} />
        </Paper>
      )}

      {orders.length === 0 && (
        <Paper withBorder radius="md" shadow="sm" p="xl">
          <Stack align="center" gap="xs">
            <Text c="dimmed" size="sm">
              Initiate a payment order above. Orders created this session will
              appear here.
            </Text>
            <Text c="dimmed" size="xs">
              Use the Exception Queue in Compliance to manage failed orders.
            </Text>
          </Stack>
        </Paper>
      )}
    </Stack>
  );
}

function OrderTable({
  orders,
  onCancel,
  onRetry,
}: {
  orders: PaymentOrder[];
  onCancel: (id: string) => void;
  onRetry: (id: string) => void;
}) {
  const cols: ColumnDef<PaymentOrder>[] = [
    {
      key: "id",
      label: "ID",
      getValue: (o) => o.payment_id,
      render: (o) => truncateID(o.payment_id),
      ff: "monospace",
    },
    {
      key: "amount",
      label: "Amount",
      getValue: (o) => o.amount,
      render: (o) => formatAmount(o.amount, o.currency),
      ta: "right",
      ff: "monospace",
      fw: 500,
    },
    {
      key: "stp",
      label: "STP",
      getValue: (o) => o.stp_decision ?? "",
      render: (o) => (
        <Badge variant="light" color="gray" radius="sm">
          {o.stp_decision || "—"}
        </Badge>
      ),
    },
    {
      key: "status",
      label: "Status",
      getValue: (o) => o.status,
      render: (o) => (
        <Badge variant="light" color={statusColor(o.status)} radius="sm">
          {o.status}
        </Badge>
      ),
    },
    {
      key: "retries",
      label: "Retries",
      getValue: (o) => o.retry_count ?? 0,
    },
    {
      key: "created",
      label: "Created",
      getValue: (o) => o.created_at,
      render: (o) => formatTimestamp(o.created_at),
      c: "dimmed",
    },
    {
      key: "actions",
      label: "Actions",
      sortable: false,
      getValue: () => "",
      render: (o) => (
        <Group gap="xs">
          {(o.status === "pending" || o.status === "processing") && (
            <Button
              size="xs"
              variant="light"
              color="red"
              onClick={() => onCancel(o.payment_id)}
            >
              Cancel
            </Button>
          )}
          {o.status === "failed" && (
            <Button
              size="xs"
              variant="light"
              color="yellow"
              onClick={() => onRetry(o.payment_id)}
            >
              Retry
            </Button>
          )}
        </Group>
      ),
    },
  ];

  return (
    <SortableTable
      data={orders}
      columns={cols}
      rowKey={(o) => o.payment_id}
      searchPlaceholder="Search orders..."
      emptyMessage="No orders"
      minWidth={800}
    />
  );
}
