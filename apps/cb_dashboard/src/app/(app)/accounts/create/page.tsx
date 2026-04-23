"use client";

import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  Button,
  Card,
  Group,
  Select,
  Stack,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import type { Party } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

const ACCOUNT_TYPES = [
  { value: "checking", label: "Checking" },
  { value: "savings", label: "Savings" },
  { value: "money_market", label: "Money Market" },
  { value: "cd", label: "Certificate of Deposit" },
];

const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF"];

export default function CreateAccountPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { setError, setSuccess } = useNotify();

  const [parties, setParties] = useState<Party[]>([]);
  const [loading, setLoading] = useState(false);

  const [partyId, setPartyId] = useState<string>(
    searchParams?.get("party") ?? "",
  );
  const [accountType, setAccountType] = useState<string | null>("checking");
  const [accountName, setAccountName] = useState("");
  const [currency, setCurrency] = useState<string | null>("USD");

  useEffect(() => {
    api<ListResponse<Party>>("GET", "/parties")
      .then((r) => setParties(r.items ?? []))
      .catch((err) => setError((err as Error).message));
  }, [setError]);

  const handleSubmit = async () => {
    if (!partyId) {
      setError("Select a customer");
      return;
    }
    if (!accountName.trim()) {
      setError("Account name is required");
      return;
    }
    setLoading(true);
    try {
      const account = await api<{ account_id: string }>("POST", "/accounts", {
        party_id: partyId,
        name: accountName.trim(),
        currency: currency ?? "USD",
      });
      setSuccess("Account created successfully");
      router.push(`/accounts/${account.account_id}`);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Stack gap="lg" maw={560}>
      <div>
        <Title order={2}>Create Account</Title>
        <Text c="dimmed" size="sm" mt={4}>
          Open a new bank account for a customer.
        </Text>
      </div>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Stack gap="md">
          <Select
            label="Customer"
            placeholder="Select customer"
            data={parties.map((p) => ({
              value: p.party_id,
              label: `${p.full_name} (${p.email})`,
            }))}
            value={partyId}
            onChange={(v) => setPartyId(v ?? "")}
            searchable
            required
          />

          <Select
            label="Account Type"
            data={ACCOUNT_TYPES}
            value={accountType}
            onChange={setAccountType}
            required
          />

          <TextInput
            label="Account Name"
            placeholder={
              accountType === "checking"
                ? "Main Checking"
                : accountType === "savings"
                  ? "Primary Savings"
                  : "Account Name"
            }
            value={accountName}
            onChange={(e) => setAccountName(e.currentTarget.value)}
            required
          />

          <Select
            label="Currency"
            data={CURRENCIES}
            value={currency}
            onChange={setCurrency}
            required
          />

          <Group mt="sm">
            <Button onClick={handleSubmit} loading={loading}>
              Create Account
            </Button>
            <Button variant="subtle" onClick={() => router.back()}>
              Cancel
            </Button>
          </Group>
        </Stack>
      </Card>
    </Stack>
  );
}
