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
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatTimestamp } from "@/lib/format";
import type { ChannelActivity, ChannelLimit } from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

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
        <SortableTable
          data={limits}
          columns={[
            {
              key: "channel_type",
              label: "Channel",
              getValue: (l) => l.channel_type,
              render: (l) => (
                <Badge
                  variant="light"
                  color={channelColor(l.channel_type)}
                  radius="sm"
                >
                  {capitalize(l.channel_type)}
                </Badge>
              ),
            },
            {
              key: "currency",
              label: "Currency",
              getValue: (l) => l.currency,
            },
            {
              key: "daily_limit",
              label: "Daily Limit",
              getValue: (l) => l.daily_limit,
              render: (l) =>
                l.daily_limit === 0
                  ? "Unlimited"
                  : l.daily_limit.toLocaleString(),
              ta: "right",
              ff: "monospace",
            },
            {
              key: "per_txn_limit",
              label: "Per-Txn Limit",
              getValue: (l) => l.per_txn_limit,
              render: (l) =>
                l.per_txn_limit === 0
                  ? "Unlimited"
                  : l.per_txn_limit.toLocaleString(),
              ta: "right",
              ff: "monospace",
            },
            {
              key: "updated_at",
              label: "Updated",
              getValue: (l) => l.updated_at,
              render: (l) => formatTimestamp(l.updated_at),
              c: "dimmed",
            },
            {
              key: "actions",
              label: "Actions",
              sortable: false,
              getValue: () => "",
              render: (l) => (
                <Button size="xs" variant="light" onClick={() => startEdit(l)}>
                  Edit
                </Button>
              ),
            },
          ] satisfies ColumnDef<ChannelLimit>[]}
          rowKey={(l) => `${l.channel_type}-${l.currency}`}
          searchPlaceholder="Search limits..."
          emptyMessage="No channel limits configured"
          minWidth={600}
        />
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
        <SortableTable
          data={entries}
          columns={[
            {
              key: "channel",
              label: "Channel",
              getValue: (e) => e.channel ?? "",
              render: (e) => (
                <Badge
                  variant="light"
                  color={channelColor(e.channel ?? "")}
                  radius="sm"
                >
                  {e.channel ? capitalize(e.channel) : "—"}
                </Badge>
              ),
            },
            {
              key: "action",
              label: "Action",
              getValue: (e) => e.action ?? "",
              render: (e) => e.action || "—",
            },
            {
              key: "endpoint",
              label: "Endpoint",
              getValue: (e) => e.endpoint ?? "",
              render: (e) => (
                <span
                  style={{
                    maxWidth: 200,
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                    display: "block",
                    fontFamily: "monospace",
                  }}
                >
                  {e.endpoint || "—"}
                </span>
              ),
              ff: "monospace",
            },
            {
              key: "status_code",
              label: "Status",
              getValue: (e) => e.status_code,
              render: (e) => (
                <Badge
                  variant="light"
                  color={statusCodeColor(e.status_code)}
                  radius="sm"
                >
                  {e.status_code}
                </Badge>
              ),
            },
            {
              key: "party_id",
              label: "Party",
              getValue: (e) => e.party_id ?? "",
              render: (e) =>
                e.party_id
                  ? e.party_id.slice(-8).toUpperCase()
                  : "—",
              ff: "monospace",
              c: "dimmed",
            },
            {
              key: "created_at",
              label: "Time",
              getValue: (e) => e.created_at,
              render: (e) => formatTimestamp(e.created_at),
              c: "dimmed",
            },
          ] satisfies ColumnDef<ChannelActivity>[]}
          rowKey={(e) => e.log_id}
          searchPlaceholder="Search activity..."
          emptyMessage="No activity recorded"
          minWidth={700}
        />
      </Paper>
    </Stack>
  );
}
