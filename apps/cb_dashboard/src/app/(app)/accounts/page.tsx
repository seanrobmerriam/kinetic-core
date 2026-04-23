"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  Badge,
  Button,
  Group,
  Paper,
  SegmentedControl,
  Stack,
  Text,
  Title,
} from "@mantine/core";
import { IconPlus } from "@/components/icons";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatAmount, formatDate, truncateID } from "@/lib/format";
import type { Account, Party } from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

interface ListResponse<T> {
  items: T[];
  total?: number;
}

const STATUSES = [
  { label: "All", value: "all" },
  { label: "Active", value: "active" },
  { label: "Frozen", value: "frozen" },
  { label: "Closed", value: "closed" },
];

function statusColor(s: string) {
  if (s === "active") return "teal";
  if (s === "frozen") return "yellow";
  if (s === "closed") return "gray";
  return "gray";
}

export default function AccountsPage() {
  const { setError } = useNotify();
  const { tick } = useRefresh();
  const [partyMap, setPartyMap] = useState<Record<string, Party>>({});
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [filterStatus, setFilterStatus] = useState<string>("all");

  useEffect(() => {
    let cancelled = false;
    Promise.all([
      api<ListResponse<Account>>("GET", "/accounts?page_size=500"),
      api<ListResponse<Party>>("GET", "/parties"),
    ])
      .then(([acctResp, partyResp]) => {
        if (cancelled) return;
        setAccounts(acctResp.items ?? []);
        const map: Record<string, Party> = {};
        for (const p of partyResp.items ?? []) map[p.party_id] = p;
        setPartyMap(map);
      })
      .catch((err) => {
        if (!cancelled) setError((err as Error).message);
      });
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const filtered = useMemo(() => {
    if (filterStatus === "all") return accounts;
    return accounts.filter((a) => a.status === filterStatus);
  }, [accounts, filterStatus]);

  const acctColumns: ColumnDef<Account>[] = [
    {
      key: "id",
      label: "Account ID",
      getValue: (a) => a.account_id,
      render: (a) => (
        <Text ff="monospace" size="sm">
          {truncateID(a.account_id)}
        </Text>
      ),
    },
    {
      key: "customer",
      label: "Customer",
      getValue: (a) => partyMap[a.party_id]?.full_name ?? a.party_id,
      render: (a) => {
        const party = partyMap[a.party_id];
        return party ? (
          <Text
            component={Link}
            href={`/customers/${a.party_id}`}
            size="sm"
            c="blue"
          >
            {party.full_name}
          </Text>
        ) : (
          <Text ff="monospace" size="sm" c="dimmed">
            {truncateID(a.party_id)}
          </Text>
        );
      },
    },
    { key: "name", label: "Name", getValue: (a) => a.name, fw: 500 },
    { key: "currency", label: "Currency", getValue: (a) => a.currency },
    {
      key: "balance",
      label: "Balance",
      getValue: (a) => a.balance,
      render: (a) => (
        <Text ff="monospace" size="sm" fw={500} ta="right">
          {formatAmount(a.balance, a.currency)}
        </Text>
      ),
      ta: "right",
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
      key: "created_at",
      label: "Opened",
      getValue: (a) => a.created_at,
      render: (a) => (
        <Text size="sm" c="dimmed">
          {formatDate(a.created_at)}
        </Text>
      ),
    },
    {
      key: "actions",
      label: "",
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

  return (
    <Stack gap="lg">
      <Group justify="space-between" align="flex-end">
        <div>
          <Title order={2}>Accounts</Title>
          <Text c="dimmed" size="sm" mt={4}>
            {accounts.length} account{accounts.length !== 1 ? "s" : ""} total
          </Text>
        </div>
        <Button
          component={Link}
          href="/accounts/create"
          leftSection={<IconPlus size={16} />}
        >
          Create Account
        </Button>
      </Group>

      <SegmentedControl
        value={filterStatus}
        onChange={setFilterStatus}
        data={STATUSES}
      />

      <Paper withBorder radius="md" shadow="sm">
        <SortableTable
          data={filtered}
          columns={acctColumns}
          rowKey={(a) => a.account_id}
          searchPlaceholder="Search by name, customer, currency…"
          emptyMessage="No accounts found"
          minWidth={900}
        />
      </Paper>
    </Stack>
  );
}
