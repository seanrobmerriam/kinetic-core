"use client";

import { useState } from "react";
import {
  Badge,
  Button,
  Card,
  Group,
  Paper,
  Stack,
  Table,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import {
  capitalize,
  formatAmount,
  formatTimestamp,
  truncateID,
} from "@/lib/format";
import type { LedgerEntry } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

export default function LedgerPage() {
  const { setError } = useNotify();
  const [accountId, setAccountId] = useState("");
  const [entries, setEntries] = useState<LedgerEntry[]>([]);
  const [loaded, setLoaded] = useState(false);

  const filter = async () => {
    if (!accountId) return;
    try {
      const resp = await api<ListResponse<LedgerEntry>>(
        "GET",
        `/accounts/${accountId}/entries`,
      );
      setEntries(resp.items ?? []);
      setLoaded(true);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <Stack gap="lg">
      <Title order={3}>Ledger Entries</Title>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Group align="flex-end" wrap="nowrap">
          <TextInput
            id="ledger-account-filter"
            label="Filter by Account ID"
            placeholder="Enter account ID"
            value={accountId}
            onChange={(e) => setAccountId(e.currentTarget.value)}
            style={{ flex: 1 }}
          />
          <Button onClick={filter}>Filter</Button>
        </Group>
      </Card>

      {!loaded || entries.length === 0 ? (
        <Card withBorder padding="xl" radius="md">
          <Text c="dimmed" ta="center">
            {loaded
              ? "No ledger entries found"
              : "Select an account to view ledger entries"}
          </Text>
        </Card>
      ) : (
        <Paper withBorder radius="md" shadow="sm">
          <Table.ScrollContainer minWidth={900}>
            <Table verticalSpacing="sm" highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Entry ID</Table.Th>
                  <Table.Th>Transaction ID</Table.Th>
                  <Table.Th>Account ID</Table.Th>
                  <Table.Th>Type</Table.Th>
                  <Table.Th ta="right">Amount</Table.Th>
                  <Table.Th>Description</Table.Th>
                  <Table.Th>Posted At</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {entries.map((e) => (
                  <Table.Tr key={e.entry_id}>
                    <Table.Td ff="monospace">{truncateID(e.entry_id)}</Table.Td>
                    <Table.Td ff="monospace">{truncateID(e.txn_id)}</Table.Td>
                    <Table.Td ff="monospace">
                      {truncateID(e.account_id)}
                    </Table.Td>
                    <Table.Td>
                      <Badge
                        variant="light"
                        color={e.entry_type === "debit" ? "red" : "teal"}
                        radius="sm"
                      >
                        {capitalize(e.entry_type)}
                      </Badge>
                    </Table.Td>
                    <Table.Td ta="right" ff="monospace" fw={500}>
                      {formatAmount(e.amount, e.currency)}
                    </Table.Td>
                    <Table.Td>{e.description}</Table.Td>
                    <Table.Td>{formatTimestamp(e.posted_at)}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}
    </Stack>
  );
}
