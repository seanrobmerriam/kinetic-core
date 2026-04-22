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
  Table,
  Text,
  Textarea,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatTimestamp, truncateID } from "@/lib/format";
import type { ExceptionItem, Party } from "@/lib/types";

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
        <Table.ScrollContainer minWidth={700}>
          <Table verticalSpacing="sm" highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Item ID</Table.Th>
                <Table.Th>Payment ID</Table.Th>
                <Table.Th>Reason</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Resolution</Table.Th>
                <Table.Th>Created</Table.Th>
                <Table.Th>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {items.map((item) => (
                <Table.Tr key={item.item_id}>
                  <Table.Td ff="monospace">{truncateID(item.item_id)}</Table.Td>
                  <Table.Td ff="monospace">
                    {item.payment_id ? truncateID(item.payment_id) : "—"}
                  </Table.Td>
                  <Table.Td>{item.reason || "—"}</Table.Td>
                  <Table.Td>
                    <Badge
                      variant="light"
                      color={exceptionStatusColor(item.status)}
                      radius="sm"
                    >
                      {capitalize(item.status)}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    {item.resolution ? capitalize(item.resolution) : "—"}
                  </Table.Td>
                  <Table.Td c="dimmed">
                    {formatTimestamp(item.created_at)}
                  </Table.Td>
                  <Table.Td>
                    {item.status === "pending" && (
                      <Button
                        size="xs"
                        variant="light"
                        onClick={() => openResolve(item.item_id)}
                      >
                        Resolve
                      </Button>
                    )}
                  </Table.Td>
                </Table.Tr>
              ))}
              {items.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={7} ta="center" py="xl" c="dimmed">
                    No exception items found
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
        "PUT",
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
    if (s === "verified") return "teal";
    if (s === "pending") return "yellow";
    if (s === "rejected") return "red";
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
                  { value: "pending", label: "Pending" },
                  { value: "verified", label: "Verified" },
                  { value: "rejected", label: "Rejected" },
                  { value: "expired", label: "Expired" },
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
        <Table.ScrollContainer minWidth={600}>
          <Table verticalSpacing="sm" highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Customer</Table.Th>
                <Table.Th>Email</Table.Th>
                <Table.Th>KYC Status</Table.Th>
                <Table.Th>Risk Tier</Table.Th>
                <Table.Th>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {parties.map((p) => {
                const k = kyc[p.party_id];
                return (
                  <Table.Tr key={p.party_id}>
                    <Table.Td fw={500}>{p.full_name}</Table.Td>
                    <Table.Td>{p.email}</Table.Td>
                    <Table.Td>
                      {k ? (
                        <Badge
                          variant="light"
                          color={kycColor(k.kyc_status)}
                          radius="sm"
                        >
                          {capitalize(k.kyc_status)}
                        </Badge>
                      ) : (
                        <Text size="sm" c="dimmed">
                          —
                        </Text>
                      )}
                    </Table.Td>
                    <Table.Td>
                      {k ? (
                        <Badge
                          variant="light"
                          color={tierColor(k.risk_tier)}
                          radius="sm"
                        >
                          {capitalize(k.risk_tier)}
                        </Badge>
                      ) : (
                        <Text size="sm" c="dimmed">
                          —
                        </Text>
                      )}
                    </Table.Td>
                    <Table.Td>
                      <Button
                        size="xs"
                        variant="light"
                        onClick={() => selectParty(p.party_id)}
                      >
                        Update KYC
                      </Button>
                    </Table.Td>
                  </Table.Tr>
                );
              })}
              {parties.length === 0 && (
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
