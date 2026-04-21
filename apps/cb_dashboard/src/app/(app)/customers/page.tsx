"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Badge,
  Button,
  Card,
  Group,
  Paper,
  Stack,
  Table,
  TextInput,
  Title,
} from "@mantine/core";
import { IconSearch } from "@tabler/icons-react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatDate } from "@/lib/format";
import type { Party } from "@/lib/types";

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
  const [search, setSearch] = useState("");
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

  const filtered = useMemo(() => {
    if (!search) return parties;
    const q = search.toLowerCase();
    return parties.filter(
      (p) =>
        p.full_name.toLowerCase().includes(q) ||
        p.email.toLowerCase().includes(q),
    );
  }, [parties, search]);

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

  return (
    <Stack gap="lg">
      <TextInput
        leftSection={<IconSearch size={16} />}
        placeholder="Search customers..."
        value={search}
        onChange={(e) => setSearch(e.currentTarget.value)}
        maw={400}
      />

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
        <Table.ScrollContainer minWidth={700}>
          <Table verticalSpacing="sm" highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Name</Table.Th>
                <Table.Th>Email</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Created</Table.Th>
                <Table.Th>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.map((party) => (
                <Table.Tr key={party.party_id}>
                  <Table.Td fw={500}>{party.full_name}</Table.Td>
                  <Table.Td>{party.email}</Table.Td>
                  <Table.Td>
                    <Badge
                      variant="light"
                      color={statusColor(party.status)}
                      radius="sm"
                    >
                      {capitalize(party.status)}
                    </Badge>
                  </Table.Td>
                  <Table.Td>{formatDate(party.created_at)}</Table.Td>
                  <Table.Td>
                    <Group gap="xs">
                      <Button
                        size="xs"
                        variant="subtle"
                        onClick={() =>
                          router.push(`/accounts?party=${party.party_id}`)
                        }
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
                  </Table.Td>
                </Table.Tr>
              ))}
              {filtered.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={5} ta="center" py="xl" c="dimmed">
                    No customers found
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Paper>
    </Stack>
  );
}
