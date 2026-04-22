"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Badge,
  Button,
  Card,
  Group,
  Paper,
  Stack,
  TextInput,
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
  const router = useRouter();
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [parties, setParties] = useState<Party[]>([]);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [submitting, setSubmitting] = useState(false);

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

  const create = async () => {
    if (!name || !email || submitting) return;
    setSubmitting(true);
    try {
      await api("POST", "/parties", { full_name: name, email });
      setSuccess("Customer created");
      setName("");
      setEmail("");
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

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
            size="xs"
            variant="subtle"
            onClick={() => router.push(`/accounts?party=${party.party_id}`)}
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
      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={4} mb="md">
          New Customer
        </Title>
        <Stack>
          <Group grow>
            <TextInput
              id="customer-name"
              label="Full Name"
              placeholder="Full name"
              value={name}
              onChange={(e) => setName(e.currentTarget.value)}
            />
            <TextInput
              id="customer-email"
              label="Email"
              placeholder="user@example.com"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.currentTarget.value)}
            />
          </Group>
          <Group>
            <Button
              id="create-customer-button"
              onClick={create}
              disabled={submitting}
              loading={submitting}
            >
              Create Customer
            </Button>
          </Group>
        </Stack>
      </Card>

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
