"use client";

import { useEffect, useState } from "react";
import {
  Badge,
  Button,
  Card,
  Group,
  Paper,
  SegmentedControl,
  Select,
  Stack,
  Text,
  Textarea,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatTimestamp, truncateID } from "@/lib/format";
import type { ExceptionItem, Party } from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

type Tab = "exceptions" | "kyc";

function exceptionStatusColor(s: string) {
  if (s === "resolved") return "teal";
  if (s === "pending") return "yellow";
  return "gray";
}

export default function CompliancePage() {
  const [tab, setTab] = useState<Tab>("exceptions");
  return (
    <Stack gap="lg">
      <SegmentedControl
        value={tab}
        onChange={(v) => setTab(v as Tab)}
        data={[
          { label: "Exception Queue", value: "exceptions" },
          { label: "KYC Management", value: "kyc" },
        ]}
        maw={320}
      />
      {tab === "exceptions" ? <ExceptionQueue /> : <KycManagement />}
    </Stack>
  );
}

function ExceptionQueue() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [items, setItems] = useState<ExceptionItem[]>([]);
  const [resolving, setResolving] = useState<string | null>(null);
  const [resolution, setResolution] = useState<string | null>(null);
  const [notes, setNotes] = useState("");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const resp = await api<ExceptionItem[]>("GET", "/exceptions");
        if (!cancelled) setItems(resp ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const openResolve = (id: string) => {
    setResolving(id);
    setResolution(null);
    setNotes("");
  };

  const submitResolve = async () => {
    if (!resolving || !resolution) return;
    try {
      await api("POST", `/exceptions/${resolving}/resolve`, {
        resolution,
        notes,
      });
      setSuccess("Exception resolved");
      setResolving(null);
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <Stack gap="md">
      {resolving && (
        <Card withBorder shadow="sm" radius="md" padding="lg">
          <Title order={5} mb="md">
            Resolve Exception
          </Title>
          <Stack>
            <Select
              label="Resolution"
              placeholder="Select resolution"
              data={[
                { value: "approved", label: "Approved" },
                { value: "rejected", label: "Rejected" },
                { value: "escalated", label: "Escalated" },
              ]}
              value={resolution}
              onChange={setResolution}
            />
            <Textarea
              label="Notes"
              placeholder="Resolution notes…"
              value={notes}
              onChange={(e) => setNotes(e.currentTarget.value)}
              rows={3}
            />
            <Group>
              <Button onClick={submitResolve} disabled={!resolution}>
                Submit Resolution
              </Button>
              <Button variant="subtle" onClick={() => setResolving(null)}>
                Cancel
              </Button>
            </Group>
          </Stack>
        </Card>
      )}

      <Paper withBorder radius="md" shadow="sm">
        <SortableTable
          data={items}
          columns={[
            {
              key: "item_id",
              label: "Item ID",
              getValue: (item) => item.item_id,
              render: (item) => truncateID(item.item_id),
              ff: "monospace",
            },
            {
              key: "payment_id",
              label: "Payment ID",
              getValue: (item) => item.payment_id ?? "",
              render: (item) =>
                item.payment_id ? truncateID(item.payment_id) : "—",
              ff: "monospace",
            },
            {
              key: "reason",
              label: "Reason",
              getValue: (item) => item.reason ?? "",
              render: (item) => item.reason || "—",
            },
            {
              key: "status",
              label: "Status",
              getValue: (item) => item.status,
              render: (item) => (
                <Badge
                  variant="light"
                  color={exceptionStatusColor(item.status)}
                  radius="sm"
                >
                  {capitalize(item.status)}
                </Badge>
              ),
            },
            {
              key: "resolution",
              label: "Resolution",
              getValue: (item) => item.resolution ?? "",
              render: (item) =>
                item.resolution ? capitalize(item.resolution) : "—",
            },
            {
              key: "created_at",
              label: "Created",
              getValue: (item) => item.created_at,
              render: (item) => formatTimestamp(item.created_at),
              c: "dimmed",
            },
            {
              key: "actions",
              label: "Actions",
              sortable: false,
              getValue: () => "",
              render: (item) =>
                item.status === "pending" ? (
                  <Button
                    size="xs"
                    variant="light"
                    onClick={() => openResolve(item.item_id)}
                  >
                    Resolve
                  </Button>
                ) : null,
            },
          ] satisfies ColumnDef<ExceptionItem>[]}
          rowKey={(item) => item.item_id}
          searchPlaceholder="Search exceptions..."
          emptyMessage="No exception items found"
          minWidth={700}
        />
      </Paper>
    </Stack>
  );
}

interface KycResponse {
  party_id: string;
  kyc_status: string;
  risk_tier: string;
  updated_at: number;
}

function KycManagement() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [parties, setParties] = useState<Party[]>([]);
  const [kyc, setKyc] = useState<Record<string, KycResponse>>({});
  const [selected, setSelected] = useState<string | null>(null);
  const [kycStatus, setKycStatus] = useState<string | null>(null);
  const [riskTier, setRiskTier] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const resp = await api<{ items: Party[] }>("GET", "/parties");
        const list = resp.items ?? [];
        if (!cancelled) setParties(list);
        const kycMap: Record<string, KycResponse> = {};
        await Promise.all(
          list.map(async (p) => {
            try {
              const k = await api<KycResponse>(
                "GET",
                `/parties/${p.party_id}/kyc`,
              );
              kycMap[p.party_id] = k;
            } catch {
              /* skip */
            }
          }),
        );
        if (!cancelled) setKyc(kycMap);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const selectParty = (id: string) => {
    setSelected(id);
    const existing = kyc[id];
    setKycStatus(existing?.kyc_status ?? null);
    setRiskTier(existing?.risk_tier ?? null);
  };

  const save = async () => {
    if (!selected || !kycStatus || !riskTier || submitting) return;
    setSubmitting(true);
    try {
      const updated = await api<KycResponse>(
        "PATCH",
        `/parties/${selected}/kyc`,
        { kyc_status: kycStatus, risk_tier: riskTier },
      );
      setKyc((prev) => ({ ...prev, [selected]: updated }));
      setSuccess("KYC updated");
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  function kycColor(s: string) {
    if (s === "approved") return "teal";
    if (s === "pending") return "yellow";
    if (s === "rejected") return "red";
    if (s === "not_started") return "gray";
    return "gray";
  }

  function tierColor(t: string) {
    if (t === "low") return "teal";
    if (t === "medium") return "yellow";
    if (t === "high") return "red";
    return "gray";
  }

  return (
    <Stack gap="md">
      {selected && (
        <Card withBorder shadow="sm" radius="md" padding="lg">
          <Title order={5} mb="md">
            Update KYC — {parties.find((p) => p.party_id === selected)?.full_name}
          </Title>
          <Stack>
            <Group grow>
              <Select
                label="KYC Status"
                data={[
                  { value: "not_started", label: "Not Started" },
                  { value: "pending", label: "Pending" },
                  { value: "approved", label: "Approved" },
                  { value: "rejected", label: "Rejected" },
                ]}
                value={kycStatus}
                onChange={setKycStatus}
              />
              <Select
                label="Risk Tier"
                data={[
                  { value: "low", label: "Low" },
                  { value: "medium", label: "Medium" },
                  { value: "high", label: "High" },
                ]}
                value={riskTier}
                onChange={setRiskTier}
              />
            </Group>
            <Group>
              <Button onClick={save} loading={submitting} disabled={!kycStatus || !riskTier}>
                Save
              </Button>
              <Button variant="subtle" onClick={() => setSelected(null)}>
                Cancel
              </Button>
            </Group>
          </Stack>
        </Card>
      )}

      <Paper withBorder radius="md" shadow="sm">
        {(() => {
          const kycCols: ColumnDef<Party>[] = [
            {
              key: "full_name",
              label: "Customer",
              getValue: (p) => p.full_name,
              fw: 500,
            },
            {
              key: "email",
              label: "Email",
              getValue: (p) => p.email,
            },
            {
              key: "kyc_status",
              label: "KYC Status",
              getValue: (p) => kyc[p.party_id]?.kyc_status ?? "",
              render: (p) => {
                const k = kyc[p.party_id];
                return k ? (
                  <Badge
                    variant="light"
                    color={kycColor(k.kyc_status)}
                    radius="sm"
                  >
                    {capitalize(k.kyc_status)}
                  </Badge>
                ) : (
                  <Text size="sm" c="dimmed">—</Text>
                );
              },
            },
            {
              key: "risk_tier",
              label: "Risk Tier",
              getValue: (p) => kyc[p.party_id]?.risk_tier ?? "",
              render: (p) => {
                const k = kyc[p.party_id];
                return k ? (
                  <Badge
                    variant="light"
                    color={tierColor(k.risk_tier)}
                    radius="sm"
                  >
                    {capitalize(k.risk_tier)}
                  </Badge>
                ) : (
                  <Text size="sm" c="dimmed">—</Text>
                );
              },
            },
            {
              key: "actions",
              label: "Actions",
              sortable: false,
              getValue: () => "",
              render: (p) => (
                <Button
                  size="xs"
                  variant="light"
                  onClick={() => selectParty(p.party_id)}
                >
                  Update KYC
                </Button>
              ),
            },
          ];
          return (
            <SortableTable
              data={parties}
              columns={kycCols}
              rowKey={(p) => p.party_id}
              searchPlaceholder="Search customers..."
              emptyMessage="No customers found"
              minWidth={600}
            />
          );
        })()}
      </Paper>
    </Stack>
  );
}
