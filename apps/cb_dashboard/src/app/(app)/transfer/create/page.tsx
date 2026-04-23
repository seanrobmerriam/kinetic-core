"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Anchor,
  Button,
  Card,
  Group,
  NumberInput,
  Select,
  Stack,
  Text,
  Textarea,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { IconArrowLeft } from "@/components/icons";
import type { Account, Party } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD"];

export default function TransferCreatePage() {
  const router = useRouter();
  const { setError, setSuccess } = useNotify();

  const [accounts, setAccounts] = useState<Account[]>([]);
  const [partyMap, setPartyMap] = useState<Record<string, string>>({});
  const [sourceId, setSourceId] = useState<string | null>(null);
  const [destId, setDestId] = useState<string | null>(null);
  const [amount, setAmount] = useState<string | number>("");
  const [currency, setCurrency] = useState<string | null>("USD");
  const [description, setDescription] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [partyResp, accountsResp] = await Promise.all([
          api<ListResponse<Party>>("GET", "/parties"),
          api<{ accounts: Account[] } | ListResponse<Account>>("GET", "/accounts?page_size=500"),
        ]);

        const parties: Party[] = partyResp.items ?? [];
        const pm: Record<string, string> = {};
        for (const p of parties) pm[p.party_id] = p.full_name ?? p.party_id;

        const rawAccounts = "accounts" in accountsResp
          ? accountsResp.accounts
          : (accountsResp as ListResponse<Account>).items ?? [];

        if (!cancelled) {
          setPartyMap(pm);
          setAccounts(rawAccounts);
        }
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => { cancelled = true; };
  }, [setError]);

  const accountOptions = accounts.map((a) => ({
    value: a.account_id,
    label: `${partyMap[a.party_id] ?? "Unknown"} — ${a.name} (${a.currency})`,
  }));

  const destOptions = accountOptions.filter((o) => o.value !== sourceId);

  const handleSubmit = async () => {
    if (!sourceId || !destId) {
      setError("Please select both source and destination accounts.");
      return;
    }
    if (!amount || Number(amount) <= 0) {
      setError("Amount must be greater than zero.");
      return;
    }
    if (!currency) {
      setError("Please select a currency.");
      return;
    }

    const minorUnits = Math.round(Number(amount) * 100);

    setSubmitting(true);
    try {
      await api("POST", "/transactions/transfer", {
        idempotency_key: `web-${Date.now()}`,
        source_account_id: sourceId,
        dest_account_id: destId,
        amount: minorUnits,
        currency,
        description,
      });
      setSuccess("Transfer initiated successfully.");
      router.push("/transfer");
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Stack gap="lg" maw={640}>
      <Anchor component={Link} href="/transfer" size="sm">
        <Group gap={4}>
          <IconArrowLeft size={14} />
          Back to Transfers
        </Group>
      </Anchor>

      <Title order={3}>Create Internal Transfer</Title>
      <Text c="dimmed" size="sm">
        Move funds between two accounts within the bank.
      </Text>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Stack gap="md">
          <Select
            label="Source Account"
            placeholder="Select source account"
            data={accountOptions}
            value={sourceId}
            onChange={setSourceId}
            searchable
            required
          />

          <Select
            label="Destination Account"
            placeholder="Select destination account"
            data={destOptions}
            value={destId}
            onChange={setDestId}
            searchable
            required
            disabled={!sourceId}
          />

          <Group grow>
            <NumberInput
              label="Amount"
              placeholder="0.00"
              min={0.01}
              decimalScale={2}
              fixedDecimalScale
              value={amount}
              onChange={setAmount}
              required
            />
            <Select
              label="Currency"
              data={CURRENCIES}
              value={currency}
              onChange={setCurrency}
              required
            />
          </Group>

          <Textarea
            label="Description"
            placeholder="Optional memo or reference"
            value={description}
            onChange={(e) => setDescription(e.currentTarget.value)}
            rows={3}
          />

          <Group justify="flex-end" mt="md">
            <Button variant="default" component={Link} href="/transfer">
              Cancel
            </Button>
            <Button
              onClick={handleSubmit}
              loading={submitting}
              disabled={!sourceId || !destId || !amount || submitting}
            >
              Submit Transfer
            </Button>
          </Group>
        </Stack>
      </Card>
    </Stack>
  );
}
