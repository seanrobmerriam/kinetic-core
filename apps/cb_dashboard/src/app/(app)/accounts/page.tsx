"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
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
  TextInput,
  Title,
} from "@mantine/core";
import { IconSearch } from "@tabler/icons-react";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { capitalize, formatAmount, truncateID } from "@/lib/format";
import type { Account, Party } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
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
  const searchParams = useSearchParams();
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [parties, setParties] = useState<Party[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState<string>("all");
  const [partyId, setPartyId] = useState<string>(
    searchParams?.get("party") ?? "",
  );
  const [name, setName] = useState("");
  const [currency, setCurrency] = useState<string | null>("USD");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const ps = partyResp.items ?? [];
        if (!cancelled) setParties(ps);
        let all: Account[] = [];
        for (const p of ps) {
          try {
            const accResp = await api<ListResponse<Account>>(
              "GET",
              `/parties/${p.party_id}/accounts`,
            );
            if (accResp.items) all = all.concat(accResp.items);
          } catch {
            /* skip */
          }
        }
        if (!cancelled) setAccounts(all);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const filtered = useMemo(() => {
    let list = accounts;
    if (filterStatus && filterStatus !== "all")
      list = list.filter((a) => a.status === filterStatus);
    if (search) {
      const q = search.toLowerCase();
      list = list.filter(
        (a) =>
          a.name.toLowerCase().includes(q) ||
          a.account_id.toLowerCase().includes(q),
      );
    }
    return list;
  }, [accounts, search, filterStatus]);

  const create = async () => {
    if (!partyId) {
      setError("Select a customer first");
      return;
    }
    if (!name) {
      setError("Account name is required");
      return;
    }
    try {
      await api("POST", "/accounts", {
        party_id: partyId,
        name,
        currency,
      });
      setSuccess("Account created");
      setName("");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <Stack gap="lg">
      <TextInput
        leftSection={<IconSearch size={16} />}
        placeholder="Search accounts..."
        value={search}
        onChange={(e) => setSearch(e.currentTarget.value)}
        maw={400}
      />

      <Card
        withBorder
        shadow="sm"
        radius="md"
        padding="lg"
        data-testid="create-account-form"
      >
        <Title order={4} mb="md">
          Open New Account
        </Title>
        <Stack>
          <Select
            id="account-party-select"
            label="Customer"
            placeholder="Select customer"
            data={parties.map((p) => ({
              value: p.party_id,
              label: `${p.full_name} (${p.email})`,
            }))}
            value={partyId}
            onChange={(v) => setPartyId(v ?? "")}
            searchable
          />
          <TextInput
            id="account-name"
            label="Account Name"
            placeholder="Main Checking"
            value={name}
            onChange={(e) => setName(e.currentTarget.value)}
          />
          <Select
            id="account-currency"
            label="Currency"
            data={["USD", "EUR", "GBP", "JPY"]}
            value={currency}
            onChange={setCurrency}
          />
          <Group>
            <Button id="create-account-button" onClick={create}>
              Create Account
            </Button>
          </Group>
        </Stack>
      </Card>

      <SegmentedControl
        value={filterStatus}
        onChange={setFilterStatus}
        data={STATUSES}
      />

      <Paper withBorder radius="md" shadow="sm">
        <Table.ScrollContainer minWidth={700}>
          <Table verticalSpacing="sm" highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Account ID</Table.Th>
                <Table.Th>Name</Table.Th>
                <Table.Th>Currency</Table.Th>
                <Table.Th ta="right">Balance</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.map((a) => (
                <Table.Tr key={a.account_id}>
                  <Table.Td ff="monospace">{truncateID(a.account_id)}</Table.Td>
                  <Table.Td fw={500}>{a.name}</Table.Td>
                  <Table.Td>{a.currency}</Table.Td>
                  <Table.Td ta="right" ff="monospace" fw={500}>
                    {formatAmount(a.balance, a.currency)}
                  </Table.Td>
                  <Table.Td>
                    <Badge
                      variant="light"
                      color={statusColor(a.status)}
                      radius="sm"
                    >
                      {capitalize(a.status)}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Button
                      component={Link}
                      href={`/accounts/${a.account_id}`}
                      size="xs"
                      variant="light"
                    >
                      View
                    </Button>
                  </Table.Td>
                </Table.Tr>
              ))}
              {filtered.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={6} ta="center" py="xl" c="dimmed">
                    No accounts found
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
