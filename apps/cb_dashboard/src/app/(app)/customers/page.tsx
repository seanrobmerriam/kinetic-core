"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  Badge,
  Button,
  Group,
  Paper,
  Stack,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatDate } from "@/lib/format";
import type { Party } from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

interface ListResponse<T> {
  items: T[];
}

function statusColor(s: string) {
  if (s === "active") return "teal";
  if (s === "suspended") return "yellow";
  if (s === "closed") return "gray";
  return "gray";
}

export default function CustomersPage() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [parties, setParties] = useState<Party[]>([]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const resp = await api<ListResponse<Party>>("GET", "/parties");
        if (!cancelled) setParties(resp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const suspend = async (id: string) => {
    try {
      await api("POST", `/parties/${id}/suspend`);
      setSuccess("Customer suspended");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const close = async (id: string) => {
    try {
      await api("POST", `/parties/${id}/close`);
      setSuccess("Customer closed");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const columns: ColumnDef<Party>[] = [
    { key: "name", label: "Name", getValue: (p) => p.full_name, fw: 500 },
    { key: "email", label: "Email", getValue: (p) => p.email },
    {
      key: "status",
      label: "Status",
      getValue: (p) => p.status,
      render: (p) => (
        <Badge variant="light" color={statusColor(p.status)} radius="sm">
          {capitalize(p.status)}
        </Badge>
      ),
    },
    {
      key: "created",
      label: "Created",
      getValue: (p) => p.created_at,
      render: (p) => formatDate(p.created_at),
    },
    {
      key: "actions",
      label: "Actions",
      sortable: false,
      render: (party) => (
        <Group gap="xs">
          <Button
            component={Link}
            href={`/customers/${party.party_id}`}
            size="xs"
            variant="subtle"
          >
            View
          </Button>
          {party.status === "active" && (
            <Button
              size="xs"
              variant="light"
              color="yellow"
              onClick={() => suspend(party.party_id)}
            >
              Suspend
            </Button>
          )}
          <Button
            size="xs"
            variant="light"
            color="red"
            onClick={() => close(party.party_id)}
          >
            Close
          </Button>
        </Group>
      ),
    },
  ];

  return (
    <Stack gap="lg">
      <Group justify="space-between" align="center">
        <Title order={3}>Customers</Title>
        <Button component={Link} href="/customers/create">
          Create Customer
        </Button>
      </Group>

      <Paper withBorder radius="md" shadow="sm">
        <SortableTable
          data={parties}
          columns={columns}
          rowKey={(p) => p.party_id}
          searchPlaceholder="Search customers..."
          emptyMessage="No customers found"
          minWidth={700}
        />
      </Paper>
    </Stack>
  );
}
