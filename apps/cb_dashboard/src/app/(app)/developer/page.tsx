"use client";

import { useEffect, useState } from "react";
import {
  Badge,
  Card,
  Code,
  Group,
  SegmentedControl,
  Stack,
  Table,
  Text,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { formatTimestamp } from "@/lib/format";

type Tab = "usage" | "webhooks" | "deprecations";

interface UsageEvent {
  event_id: string;
  key_id: string;
  method: string;
  path: string;
  recorded_at: number;
}

interface WebhookSubscription {
  subscription_id: string;
  event_type: string;
  callback_url: string;
  status: "active" | "inactive";
  created_at: number;
  updated_at: number;
}

interface DeprecationEntry {
  path: string;
  sunset_date: string;
  successor: string | null;
  description: string;
}

export default function DeveloperPage() {
  const [tab, setTab] = useState<Tab>("usage");
  return (
    <Stack gap="lg">
      <Title order={2}>Developer Hub</Title>
      <SegmentedControl
        value={tab}
        onChange={(v) => setTab(v as Tab)}
        data={[
          { label: "API Usage", value: "usage" },
          { label: "Webhooks", value: "webhooks" },
          { label: "Deprecations", value: "deprecations" },
        ]}
        maw={480}
        aria-label="Developer Hub section"
      />
      {tab === "usage" && <ApiUsagePanel />}
      {tab === "webhooks" && <WebhooksPanel />}
      {tab === "deprecations" && <DeprecationsPanel />}
    </Stack>
  );
}

function methodColor(method: string) {
  switch (method) {
    case "GET":
      return "blue";
    case "POST":
      return "green";
    case "PATCH":
    case "PUT":
      return "orange";
    case "DELETE":
      return "red";
    default:
      return "gray";
  }
}

function ApiUsagePanel() {
  const { setError } = useNotify();
  const [events, setEvents] = useState<UsageEvent[]>([]);
  const [keyId, setKeyId] = useState<string>("");

  useEffect(() => {
    api<string[]>("GET", "/api-keys")
      .then((keys) => {
        if (Array.isArray(keys) && keys.length > 0) {
          const firstId =
            typeof keys[0] === "object" && keys[0] !== null
              ? (keys[0] as { key_id: string }).key_id
              : String(keys[0]);
          setKeyId(firstId);
        }
      })
      .catch(() => setError("Failed to load API keys"));
  }, [setError]);

  useEffect(() => {
    if (!keyId) return;
    api<UsageEvent[]>("GET", `/api-keys/${keyId}/usage`)
      .then(setEvents)
      .catch(() => setError("Failed to load usage events"));
  }, [keyId, setError]);

  if (!keyId) {
    return (
      <Card withBorder p="lg">
        <Text c="dimmed">No API keys found.</Text>
      </Card>
    );
  }

  return (
    <Card withBorder p="lg">
      <Stack gap="sm">
        <Group justify="space-between">
          <Text fw={600}>Recent requests</Text>
          <Code>{keyId}</Code>
        </Group>
        {events.length === 0 ? (
          <Text c="dimmed" size="sm">
            No usage recorded yet.
          </Text>
        ) : (
          <Table striped highlightOnHover withTableBorder>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Method</Table.Th>
                <Table.Th>Path</Table.Th>
                <Table.Th>Time</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {events.map((e) => (
                <Table.Tr key={e.event_id}>
                  <Table.Td>
                    <Badge color={methodColor(e.method)} variant="light">
                      {e.method}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Code>{e.path}</Code>
                  </Table.Td>
                  <Table.Td>{formatTimestamp(e.recorded_at)}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
      </Stack>
    </Card>
  );
}

function WebhooksPanel() {
  const { setError } = useNotify();
  const [subs, setSubs] = useState<WebhookSubscription[]>([]);

  useEffect(() => {
    api<WebhookSubscription[]>("GET", "/webhooks")
      .then(setSubs)
      .catch(() => setError("Failed to load webhook subscriptions"));
  }, [setError]);

  return (
    <Card withBorder p="lg">
      <Stack gap="sm">
        <Text fw={600}>Webhook Subscriptions</Text>
        {subs.length === 0 ? (
          <Text c="dimmed" size="sm">
            No subscriptions configured.
          </Text>
        ) : (
          <Table striped highlightOnHover withTableBorder>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Event Type</Table.Th>
                <Table.Th>Callback URL</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Created</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {subs.map((s) => (
                <Table.Tr key={s.subscription_id}>
                  <Table.Td>
                    <Code>{s.event_type}</Code>
                  </Table.Td>
                  <Table.Td>
                    <Text size="sm" style={{ wordBreak: "break-all" }}>
                      {s.callback_url}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Badge
                      color={s.status === "active" ? "green" : "gray"}
                      variant="light"
                    >
                      {s.status}
                    </Badge>
                  </Table.Td>
                  <Table.Td>{formatTimestamp(s.created_at)}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
      </Stack>
    </Card>
  );
}

function DeprecationsPanel() {
  const { setError } = useNotify();
  const [entries, setEntries] = useState<DeprecationEntry[]>([]);

  useEffect(() => {
    api<DeprecationEntry[]>("GET", "/deprecations")
      .then(setEntries)
      .catch(() => setError("Failed to load deprecation notices"));
  }, [setError]);

  return (
    <Card withBorder p="lg">
      <Stack gap="sm">
        <Text fw={600}>Deprecated API Paths</Text>
        {entries.length === 0 ? (
          <Text c="dimmed" size="sm">
            No deprecated paths at this time.
          </Text>
        ) : (
          <Table striped highlightOnHover withTableBorder>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Path</Table.Th>
                <Table.Th>Sunset Date</Table.Th>
                <Table.Th>Successor</Table.Th>
                <Table.Th>Description</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {entries.map((e) => (
                <Table.Tr key={e.path}>
                  <Table.Td>
                    <Code>{e.path}</Code>
                  </Table.Td>
                  <Table.Td>
                    <Badge color="red" variant="light">
                      {e.sunset_date}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    {e.successor ? <Code>{e.successor}</Code> : <Text c="dimmed">—</Text>}
                  </Table.Td>
                  <Table.Td>
                    <Text size="sm">{e.description}</Text>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
      </Stack>
    </Card>
  );
}
