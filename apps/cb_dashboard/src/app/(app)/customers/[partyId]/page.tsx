"use client";

import Link from "next/link";
import { use, useEffect, useState } from "react";
import {
  Anchor,
  Badge,
  Button,
  Card,
  Divider,
  Group,
  Modal,
  Paper,
  SimpleGrid,
  Spoiler,
  Stack,
  Text,
  Title,
} from "@mantine/core";
import { IconArrowLeft } from "@tabler/icons-react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatAmount, formatDate, truncateID } from "@/lib/format";
import type { Account, Party } from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

interface ListResponse<T> {
  items: T[];
}

function statusColor(s: string) {
  if (s === "active") return "teal";
  if (s === "suspended" || s === "frozen") return "yellow";
  if (s === "closed") return "gray";
  return "gray";
}

function kycColor(s: string) {
  if (s === "approved") return "teal";
  if (s === "pending") return "yellow";
  if (s === "rejected") return "red";
  return "gray";
}

function InfoField({
  label,
  value,
}: {
  label: string;
  value: React.ReactNode;
}) {
  return (
    <div>
      <Text size="xs" c="dimmed" tt="uppercase" fw={700} mb={2}>
        {label}
      </Text>
      <Text size="sm">{value ?? "—"}</Text>
    </div>
  );
}

export default function CustomerDetailPage({
  params,
}: {
  params: Promise<{ partyId: string }>;
}) {
  const { partyId } = use(params);
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [party, setParty] = useState<Party | null>(null);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [reactivateOpen, setReactivateOpen] = useState(false);
  const [reactivateBusy, setReactivateBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const p = await api<Party>("GET", `/parties/${partyId}`);
        if (!cancelled) setParty(p);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
      try {
        const resp = await api<ListResponse<Account>>(
          "GET",
          `/parties/${partyId}/accounts`,
        );
        if (!cancelled) setAccounts(resp.items ?? []);
      } catch {
        /* ignore — party may have no accounts yet */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [partyId, tick, setError]);

  const action = async (path: string, msg: string) => {
    try {
      await api("POST", path);
      setSuccess(msg);
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const reactivate = async () => {
    setReactivateBusy(true);
    try {
      await api("POST", `/parties/${partyId}/reactivate`);
      setSuccess("Customer reactivated");
      setReactivateOpen(false);
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setReactivateBusy(false);
    }
  };

  const acctColumns: ColumnDef<Account>[] = [
    {
      key: "id",
      label: "Account ID",
      getValue: (a) => a.account_id,
      render: (a) => truncateID(a.account_id),
      ff: "monospace",
    },
    { key: "name", label: "Name", getValue: (a) => a.name, fw: 500 },
    { key: "currency", label: "Currency", getValue: (a) => a.currency },
    {
      key: "balance",
      label: "Balance",
      getValue: (a) => a.balance,
      render: (a) => formatAmount(a.balance, a.currency),
      ta: "right",
      ff: "monospace",
      fw: 500,
    },
    {
      key: "status",
      label: "Status",
      getValue: (a) => a.status,
      render: (a) => (
        <Badge variant="light" color={statusColor(a.status)} radius="sm">
          {capitalize(a.status)}
        </Badge>
      ),
    },
    {
      key: "actions",
      label: "Actions",
      sortable: false,
      render: (a) => (
        <Button
          component={Link}
          href={`/accounts/${a.account_id}`}
          size="xs"
          variant="light"
        >
          View
        </Button>
      ),
    },
  ];

  if (!party) {
    return (
      <Stack gap="lg">
        <Anchor component={Link} href="/customers" size="sm">
          <Group gap={4}>
            <IconArrowLeft size={14} />
            Back to Customers
          </Group>
        </Anchor>
        <Text c="dimmed">Loading customer…</Text>
      </Stack>
    );
  }

  return (
    <Stack gap="lg">
      <Anchor component={Link} href="/customers" size="sm">
        <Group gap={4}>
          <IconArrowLeft size={14} />
          Back to Customers
        </Group>
      </Anchor>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Group justify="space-between" align="flex-start">
          <div>
            <Title order={3}>{party.full_name}</Title>
            <Text size="xs" c="dimmed" ff="monospace" mt={4}>
              ID: {party.party_id}
            </Text>
          </div>
          <Group gap="xs">
            {party.kyc_status && (
              <Badge variant="outline" color={kycColor(party.kyc_status)} radius="sm">
                KYC: {capitalize(party.kyc_status)}
              </Badge>
            )}
            <Badge size="lg" variant="light" color={statusColor(party.status)} radius="sm">
              {capitalize(party.status)}
            </Badge>
          </Group>
        </Group>
      </Card>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={5} mb="md">
          Customer Information
        </Title>
        <Divider mb="md" />
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
          <InfoField label="Full Name" value={party.full_name} />
          <InfoField label="Email" value={party.email} />
          <InfoField label="Phone" value={party.phone ?? "Not on file"} />
          <InfoField
            label="Date of Birth"
            value={party.date_of_birth ?? "Not on file"}
          />
          <InfoField
            label="SSN (Last 4)"
            value={
              party.ssn_last4 ? (
                <Spoiler
                  maxHeight={0}
                  showLabel="Reveal"
                  hideLabel="Hide"
                  styles={{
                    root: { display: "inline-flex", alignItems: "center", gap: 6 },
                    control: { fontSize: "var(--mantine-font-size-xs)" },
                  }}
                >
                  <Text component="span" size="sm" ff="monospace">
                    ••••{party.ssn_last4}
                  </Text>
                </Spoiler>
              ) : (
                "Not on file"
              )
            }
          />
          <InfoField label="Member Since" value={formatDate(party.created_at)} />
          {party.address?.line1 && (
            <InfoField label="Address" value={party.address.line1} />
          )}
          {party.address?.city && (
            <InfoField label="City" value={party.address.city} />
          )}
          {party.address?.state && (
            <InfoField label="State" value={party.address.state} />
          )}
          {party.address?.postal_code && (
            <InfoField label="Postal Code" value={party.address.postal_code} />
          )}
          {party.address?.country && (
            <InfoField label="Country" value={party.address.country} />
          )}
        </SimpleGrid>
      </Card>

      <Group>
        {party.status === "active" && (
          <Button
            color="yellow"
            variant="light"
            onClick={() => action(`/parties/${partyId}/suspend`, "Customer suspended")}
          >
            Suspend Customer
          </Button>
        )}
        {party.status === "suspended" && (
          <Button
            color="teal"
            variant="light"
            onClick={() => setReactivateOpen(true)}
          >
            Reactivate Customer
          </Button>
        )}
        {party.status !== "closed" && (
          <Button
            color="red"
            variant="light"
            onClick={() => action(`/parties/${partyId}/close`, "Customer closed")}
          >
            Close Customer
          </Button>
        )}
      </Group>

      <Modal
        opened={reactivateOpen}
        onClose={() => (reactivateBusy ? null : setReactivateOpen(false))}
        title="Reactivate customer?"
        centered
        closeOnClickOutside={!reactivateBusy}
        closeOnEscape={!reactivateBusy}
      >
        <Stack gap="md">
          <Text size="sm">
            This will restore <Text component="span" fw={600}>{party.full_name}</Text>{" "}
            to <Badge variant="light" color="teal" radius="sm">Active</Badge> status.
          </Text>
          <Text size="sm" c="dimmed">
            An audit-trail entry will be recorded against this party. Suspended-state
            restrictions (transaction holds, channel limits) will be removed.
          </Text>
          <Group justify="flex-end" gap="sm">
            <Button
              variant="default"
              onClick={() => setReactivateOpen(false)}
              disabled={reactivateBusy}
            >
              Cancel
            </Button>
            <Button color="teal" onClick={reactivate} loading={reactivateBusy}>
              Reactivate
            </Button>
          </Group>
        </Stack>
      </Modal>

      <div>
        <Title order={4} mb="sm">
          Accounts
        </Title>
        <Paper withBorder radius="md" shadow="sm">
          <SortableTable
            data={accounts}
            columns={acctColumns}
            rowKey={(a) => a.account_id}
            searchPlaceholder="Search accounts…"
            emptyMessage="No accounts found"
            minWidth={700}
          />
        </Paper>
      </div>
    </Stack>
  );
}
