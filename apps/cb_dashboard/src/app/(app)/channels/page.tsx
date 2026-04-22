"use client";

import { useEffect, useState } from "react";
import {
  Badge,
  Button,
  Card,
  Group,
  NumberInput,
  Paper,
  SegmentedControl,
  Select,
  Stack,
  Table,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatTimestamp } from "@/lib/format";
import type { ChannelActivity, ChannelLimit } from "@/lib/types";

type Tab = "limits" | "activity";

const CHANNELS = ["web", "mobile", "branch", "atm"];
const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CHF", "AUD", "CAD", "SGD", "HKD", "NZD"];

function channelColor(ch: string) {
  if (ch === "web") return "indigo";
  if (ch === "mobile") return "violet";
  if (ch === "branch") return "teal";
  if (ch === "atm") return "orange";
  return "gray";
}

export default function ChannelsPage() {
  const [tab, setTab] = useState<Tab>("limits");
  return (
    <Stack gap="lg">
      <SegmentedControl
        value={tab}
        onChange={(v) => setTab(v as Tab)}
        data={[
          { label: "Channel Limits", value: "limits" },
          { label: "Activity Log", value: "activity" },
        ]}
        maw={280}
      />
      {tab === "limits" ? <ChannelLimitsTab /> : <ChannelActivityTab />}
    </Stack>
  );
}

function ChannelLimitsTab() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [limits, setLimits] = useState<ChannelLimit[]>([]);
  const [editing, setEditing] = useState<ChannelLimit | null>(null);

  const [channel, setChannel] = useState<string | null>(null);
  const [currency, setCurrency] = useState<string | null>("USD");
  const [dailyLimit, setDailyLimit] = useState<number | string>(0);
  const [perTxnLimit, setPerTxnLimit] = useState<number | string>(0);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const resp = await api<ChannelLimit[]>("GET", "/channel-limits");
        if (!cancelled) setLimits(resp ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const startEdit = (l: ChannelLimit) => {
    setEditing(l);
    setChannel(l.channel_type);
    setCurrency(l.currency);
    setDailyLimit(l.daily_limit);
    setPerTxnLimit(l.per_txn_limit);
  };

  const startNew = () => {
    setEditing(null);
    setChannel(null);
    setCurrency("USD");
    setDailyLimit(0);
    setPerTxnLimit(0);
  };

  const save = async () => {
    if (!channel || !currency || submitting) return;
    setSubmitting(true);
    try {
      const saved = await api<ChannelLimit>(
        "PUT",
        `/channel-limits/${channel}`,
        {
          currency,
          daily_limit: Number(dailyLimit),
          per_txn_limit: Number(perTxnLimit),
        },
      );
      setLimits((prev) => {
        const idx = prev.findIndex(
          (l) => l.channel_type === saved.channel_type && l.currency === saved.currency,
        );
        if (idx >= 0) {
          const next = [...prev];
          next[idx] = saved;
          return next;
        }
        return [saved, ...prev];
      });
      setSuccess("Channel limits saved");
      setEditing(null);
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  const isFormOpen = editing !== null || channel !== null;

  return (
    <Stack gap="md">
      {!isFormOpen && (
        <Group>
          <Button variant="light" onClick={startNew}>
            Set Limits for Channel
          </Button>
        </Group>
      )}

      {isFormOpen && (
        <Card withBorder shadow="sm" radius="md" padding="lg">
          <Title order={5} mb="md">
            {editing ? "Edit Channel Limits" : "Set Channel Limits"}
          </Title>
          <Stack>
            <Group grow>
              <Select
                label="Channel"
                data={CHANNELS.map((c) => ({ value: c, label: capitalize(c) }))}
                value={channel}
                onChange={setChannel}
                disabled={!!editing}
              />
              <Select
                label="Currency"
                data={CURRENCIES}
                value={currency}
                onChange={setCurrency}
                disabled={!!editing}
              />
            </Group>
            <Group grow>
              <NumberInput
                label="Daily Limit (minor units, 0 = unlimited)"
                value={dailyLimit}
                onChange={setDailyLimit}
                min={0}
              />
              <NumberInput
                label="Per-Transaction Limit (minor units, 0 = unlimited)"
                value={perTxnLimit}
                onChange={setPerTxnLimit}
                min={0}
              />
            </Group>
            <Group>
              <Button onClick={save} loading={submitting} disabled={!channel || !currency}>
                Save
              </Button>
              <Button variant="subtle" onClick={() => { setEditing(null); setChannel(null); }}>
                Cancel
              </Button>
            </Group>
          </Stack>
        </Card>
      )}

      <Paper withBorder radius="md" shadow="sm">
        <Table.ScrollContainer minWidth={600}>
          <Table verticalSpacing="sm" highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Channel</Table.Th>
                <Table.Th>Currency</Table.Th>
                <Table.Th ta="right">Daily Limit</Table.Th>
                <Table.Th ta="right">Per-Txn Limit</Table.Th>
                <Table.Th>Updated</Table.Th>
                <Table.Th>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {limits.map((l) => (
                <Table.Tr key={`${l.channel_type}-${l.currency}`}>
                  <Table.Td>
                    <Badge
                      variant="light"
                      color={channelColor(l.channel_type)}
                      radius="sm"
                    >
                      {capitalize(l.channel_type)}
                    </Badge>
                  </Table.Td>
                  <Table.Td>{l.currency}</Table.Td>
                  <Table.Td ta="right" ff="monospace">
                    {l.daily_limit === 0 ? "Unlimited" : l.daily_limit.toLocaleString()}
                  </Table.Td>
                  <Table.Td ta="right" ff="monospace">
                    {l.per_txn_limit === 0 ? "Unlimited" : l.per_txn_limit.toLocaleString()}
                  </Table.Td>
                  <Table.Td c="dimmed">{formatTimestamp(l.updated_at)}</Table.Td>
                  <Table.Td>
                    <Button
                      size="xs"
                      variant="light"
                      onClick={() => startEdit(l)}
                    >
                      Edit
                    </Button>
                  </Table.Td>
                </Table.Tr>
              ))}
              {limits.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={6} ta="center" py="xl" c="dimmed">
                    No channel limits configured
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

function ChannelActivityTab() {
  const { setError } = useNotify();
  const { tick } = useRefresh();
  const [entries, setEntries] = useState<ChannelActivity[]>([]);
  const [filterChannel, setFilterChannel] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const params = filterChannel ? `?channel=${filterChannel}` : "";
        const resp = await api<{ entries: ChannelActivity[]; count: number }>(
          "GET",
          `/channel-activity${params}`,
        );
        if (!cancelled) setEntries(resp.entries ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, filterChannel, setError]);

  function statusCodeColor(code: number) {
    if (code >= 200 && code < 300) return "teal";
    if (code >= 400 && code < 500) return "yellow";
    if (code >= 500) return "red";
    return "gray";
  }

  return (
    <Stack gap="md">
      <Group>
        <Select
          label="Filter by channel"
          placeholder="All channels"
          data={CHANNELS.map((c) => ({ value: c, label: capitalize(c) }))}
          value={filterChannel}
          onChange={setFilterChannel}
          clearable
          maw={200}
        />
      </Group>

      <Paper withBorder radius="md" shadow="sm">
        <Table.ScrollContainer minWidth={700}>
          <Table verticalSpacing="sm" highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Channel</Table.Th>
                <Table.Th>Action</Table.Th>
                <Table.Th>Endpoint</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Party</Table.Th>
                <Table.Th>Time</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {entries.map((e) => (
                <Table.Tr key={e.log_id}>
                  <Table.Td>
                    <Badge
                      variant="light"
                      color={channelColor(e.channel ?? "")}
                      radius="sm"
                    >
                      {e.channel ? capitalize(e.channel) : "—"}
                    </Badge>
                  </Table.Td>
                  <Table.Td>{e.action || "—"}</Table.Td>
                  <Table.Td ff="monospace" style={{ maxWidth: 200, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                    {e.endpoint || "—"}
                  </Table.Td>
                  <Table.Td>
                    <Badge
                      variant="light"
                      color={statusCodeColor(e.status_code)}
                      radius="sm"
                    >
                      {e.status_code}
                    </Badge>
                  </Table.Td>
                  <Table.Td ff="monospace" c="dimmed">
                    {e.party_id ? e.party_id.slice(-8).toUpperCase() : "—"}
                  </Table.Td>
                  <Table.Td c="dimmed">{formatTimestamp(e.created_at)}</Table.Td>
                </Table.Tr>
              ))}
              {entries.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={6} ta="center" py="xl" c="dimmed">
                    No activity recorded
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
