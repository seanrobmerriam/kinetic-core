"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  Anchor,
  Badge,
  Button,
  Card,
  Grid,
  Group,
  Paper,
  Stack,
  Text,
  Title,
  useMantineTheme,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import {
  IconBuildingBank,
  IconDownload,
  IconTransfer,
  IconUpload,
} from "@/components/icons";
import { formatAmount, formatTimestamp, truncateID } from "@/lib/format";
import type { PaymentOrder } from "@/lib/types";
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

const PAYMENT_ACTIONS = [
  {
    href: "/payments/domestic-wire",
    icon: IconBuildingBank,
    color: "blue",
    label: "Send Domestic Wire",
    description: "ABA routing — US banks",
  },
  {
    href: "/payments/international-wire",
    icon: IconTransfer,
    color: "indigo",
    label: "Send International Wire",
    description: "SWIFT / IBAN cross-border",
  },
  {
    href: "/payments/pull-ach",
    icon: IconDownload,
    color: "teal",
    label: "Pull ACH",
    description: "Debit external account",
  },
  {
    href: "/payments/push-ach",
    icon: IconUpload,
    color: "cyan",
    label: "Push ACH",
    description: "Credit external account",
  },
];

export default function PaymentsPage() {
  const { setError, setSuccess } = useNotify();
  const theme = useMantineTheme();

  const [orders, setOrders] = useState<PaymentOrder[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const resp = await api<ListResponse<PaymentOrder>>(
          "GET",
          "/payment-orders",
        );
        if (!cancelled) setOrders(resp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [setError]);

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

  return (
    <Stack gap="lg">
      {/* Payment type action cards */}
      <Grid>
        {PAYMENT_ACTIONS.map(({ href, icon: Icon, color, label, description }) => (
          <Grid.Col key={href} span={{ base: 12, xs: 6, sm: 3 }}>
            <Card
              component={Link}
              href={href}
              withBorder
              shadow="sm"
              radius="md"
              padding="lg"
              style={{ textDecoration: "none", height: "100%" }}
            >
              <Stack gap="sm">
                <Icon
                  color={theme.colors[color]?.[6] ?? theme.primaryColor}
                  size={32}
                  stroke={1.5}
                />
                <div>
                  <Text fw={600} size="sm">
                    {label}
                  </Text>
                  <Text size="xs" c="dimmed">
                    {description}
                  </Text>
                </div>
              </Stack>
            </Card>
          </Grid.Col>
        ))}
      </Grid>

      {/* All payment orders table */}
      <Paper withBorder radius="md" shadow="sm">
        <Group justify="space-between" px="md" pt="md" pb={0}>
          <Title order={5}>Payment Orders</Title>
        </Group>
        <OrderTable
          orders={orders}
          loading={loading}
          onCancel={cancel}
          onRetry={retry}
        />
      </Paper>
    </Stack>
  );
}

function OrderTable({
  orders,
  loading,
  onCancel,
  onRetry,
}: {
  orders: PaymentOrder[];
  loading: boolean;
  onCancel: (id: string) => void;
  onRetry: (id: string) => void;
}) {
  const cols: ColumnDef<PaymentOrder>[] = [
    {
      key: "id",
      label: "ID",
      getValue: (o) => o.payment_id,
      render: (o) => (
        <Anchor
          component={Link}
          href={`/payments/${o.payment_id}`}
          size="sm"
          ff="monospace"
        >
          {truncateID(o.payment_id)}
        </Anchor>
      ),
      ff: "monospace",
    },
    {
      key: "party",
      label: "Party",
      getValue: (o) => o.party_id,
      render: (o) => (
        <Anchor
          component={Link}
          href={`/customers/${o.party_id}`}
          size="sm"
          ff="monospace"
        >
          {truncateID(o.party_id)}
        </Anchor>
      ),
      ff: "monospace",
    },
    {
      key: "source",
      label: "From",
      getValue: (o) => o.source_account_id,
      render: (o) => (
        <Anchor
          component={Link}
          href={`/accounts/${o.source_account_id}`}
          size="sm"
          ff="monospace"
        >
          {truncateID(o.source_account_id)}
        </Anchor>
      ),
      ff: "monospace",
    },
    {
      key: "dest",
      label: "To",
      getValue: (o) => o.dest_account_id,
      render: (o) => (
        <Anchor
          component={Link}
          href={`/accounts/${o.dest_account_id}`}
          size="sm"
          ff="monospace"
        >
          {truncateID(o.dest_account_id)}
        </Anchor>
      ),
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
      searchPlaceholder="Search by ID, party, status…"
      emptyMessage={loading ? "Loading…" : "No payment orders found"}
      minWidth={1000}
    />
  );
}
