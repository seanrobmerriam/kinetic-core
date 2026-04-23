"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  Badge,
  Button,
  Group,
  Stack,
  Text,
  TextInput,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { formatAmount, formatTimestamp, truncateID } from "@/lib/format";
import type { Account, Party, Transaction } from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";
import { IconPlus, IconSearch } from "@/components/icons";

interface ListResponse<T> {
  items: T[];
}

function statusColor(s: string) {
  if (s === "posted") return "teal";
  if (s === "pending") return "yellow";
  if (s === "failed") return "red";
  return "gray";
}

export default function TransferPage() {
  const { setError } = useNotify();
  const { tick } = useRefresh();
  const [transfers, setTransfers] = useState<Transaction[]>([]);
  const [accountMap, setAccountMap] = useState<Record<string, string>>({});
  const [search, setSearch] = useState("");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [partyResp, accountsResp] = await Promise.all([
          api<ListResponse<Party>>("GET", "/parties"),
          api<{ accounts: Account[] } | ListResponse<Account>>("GET", "/accounts?page_size=100"),
        ]);

        const parties: Party[] = partyResp.items ?? [];
        const partyMap: Record<string, string> = {};
        for (const p of parties) partyMap[p.party_id] = p.full_name ?? p.party_id;

        const rawAccounts = "accounts" in accountsResp
          ? accountsResp.accounts
          : (accountsResp as ListResponse<Account>).items ?? [];

        const accMap: Record<string, string> = {};
        for (const a of rawAccounts) {
          accMap[a.account_id] = `${partyMap[a.party_id] ?? "Unknown"} — ${a.name}`;
        }

        // Fetch transactions for all accounts in parallel (capped at 50 accounts)
        const sliced = rawAccounts.slice(0, 50);
        const txResults = await Promise.allSettled(
          sliced.map((a) =>
            api<ListResponse<Transaction>>("GET", `/accounts/${a.account_id}/transactions`)
          )
        );

        const seen = new Set<string>();
        const allTransfers: Transaction[] = [];
        for (const r of txResults) {
          if (r.status !== "fulfilled") continue;
          for (const t of r.value.items ?? []) {
            if (
              !seen.has(t.txn_id) &&
              (t.txn_type === "transfer_in" || t.txn_type === "transfer_out" || t.txn_type === "transfer")
            ) {
              seen.add(t.txn_id);
              allTransfers.push(t);
            }
          }
        }

        if (!cancelled) {
          setTransfers(allTransfers);
          setAccountMap(accMap);
        }
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => { cancelled = true; };
  }, [tick, setError]);

  const filtered = useMemo(() => {
    const q = search.toLowerCase();
    if (!q) return transfers;
    return transfers.filter(
      (t) =>
        t.txn_id.toLowerCase().includes(q) ||
        (accountMap[t.source_account_id] ?? "").toLowerCase().includes(q) ||
        (accountMap[t.dest_account_id] ?? "").toLowerCase().includes(q) ||
        t.status.toLowerCase().includes(q) ||
        t.currency.toLowerCase().includes(q)
    );
  }, [transfers, search, accountMap]);

  const columns: ColumnDef<Transaction>[] = [
    {
      key: "txn_id",
      label: "ID",
      getValue: (t) => t.txn_id,
      render: (t) => (
        <Text component={Link} href={`/transfers/${t.txn_id}`} size="sm" ff="monospace" c="blue">
          {truncateID(t.txn_id)}
        </Text>
      ),
    },
    {
      key: "source_account_id",
      label: "From Account",
      getValue: (t) => accountMap[t.source_account_id] ?? t.source_account_id,
      render: (t) => (
        <Text component={Link} href={`/accounts/${t.source_account_id}`} size="sm" c="blue">
          {accountMap[t.source_account_id] ?? truncateID(t.source_account_id)}
        </Text>
      ),
    },
    {
      key: "dest_account_id",
      label: "To Account",
      getValue: (t) => accountMap[t.dest_account_id] ?? t.dest_account_id,
      render: (t) => (
        <Text component={Link} href={`/accounts/${t.dest_account_id}`} size="sm" c="blue">
          {accountMap[t.dest_account_id] ?? truncateID(t.dest_account_id)}
        </Text>
      ),
    },
    {
      key: "amount",
      label: "Amount",
      getValue: (t) => t.amount,
      render: (t) => formatAmount(t.amount, t.currency),
    },
    {
      key: "status",
      label: "Status",
      getValue: (t) => t.status,
      render: (t) => (
        <Badge color={statusColor(t.status)} variant="light" size="sm">
          {t.status}
        </Badge>
      ),
    },
    {
      key: "created_at",
      label: "Date",
      getValue: (t) => t.created_at,
      render: (t) => formatTimestamp(t.created_at),
    },
  ];

  return (
    <Stack gap="lg">
      <Group justify="space-between" align="center">
        <Text fw={600} size="xl">Internal Transfers</Text>
        <Button
          component={Link}
          href="/transfer/create"
          leftSection={<IconPlus size={16} />}
        >
          Create Internal Transfer
        </Button>
      </Group>

      <TextInput
        placeholder="Search by ID, account, status, currency…"
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => setSearch(e.currentTarget.value)}
        maw={400}
      />

      <SortableTable
        data={filtered}
        columns={columns}
        rowKey={(t) => t.txn_id}
        emptyMessage="No internal transfers found."
        minWidth={900}
      />
    </Stack>
  );
}
