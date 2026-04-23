"use client";

import { useState } from "react";
import Link from "next/link";
import {
  Anchor,
  Button,
  Card,
  Group,
  Select,
  Stack,
  TextInput,
  Title,
} from "@mantine/core";
import { IconArrowLeft } from "@/components/icons";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { parseAmount } from "@/lib/format";

const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CHF"];

export default function TransferPage() {
  const { setError, setSuccess } = useNotify();
  const [source, setSource] = useState("");
  const [dest, setDest] = useState("");
  const [amount, setAmount] = useState("");
  const [currency, setCurrency] = useState<string | null>("USD");
  const [desc, setDesc] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const submit = async () => {
    let amt: number;
    try {
      amt = parseAmount(amount);
    } catch {
      setError("Invalid amount format");
      return;
    }
    setSubmitting(true);
    try {
      await api("POST", "/transactions/transfer", {
        idempotency_key: `web-${Date.now()}`,
        source_account_id: source,
        dest_account_id: dest,
        amount: amt,
        currency,
        description: desc,
      });
      setSuccess("Transfer successful!");
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Stack gap="lg" maw={600}>
      <Anchor component={Link} href="/dashboard" size="sm">
        <Group gap={4}>
          <IconArrowLeft size={14} />
          Back
        </Group>
      </Anchor>
      <Title order={3}>Transfer Funds</Title>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Stack>
          <TextInput
            id="transfer-source"
            label="Source Account ID"
            placeholder="Enter source account ID"
            value={source}
            onChange={(e) => setSource(e.currentTarget.value)}
          />
          <TextInput
            id="transfer-dest"
            label="Destination Account ID"
            placeholder="Enter destination account ID"
            value={dest}
            onChange={(e) => setDest(e.currentTarget.value)}
          />
          <TextInput
            id="transfer-amount"
            label="Amount"
            placeholder="Enter amount (e.g., 100.00)"
            value={amount}
            onChange={(e) => setAmount(e.currentTarget.value)}
          />
          <Select
            id="transfer-currency"
            label="Currency"
            data={CURRENCIES}
            value={currency}
            onChange={setCurrency}
          />
          <TextInput
            id="transfer-desc"
            label="Description"
            placeholder="Enter description"
            value={desc}
            onChange={(e) => setDesc(e.currentTarget.value)}
          />
          <Button
            size="md"
            onClick={submit}
            disabled={submitting}
            loading={submitting}
          >
            Transfer Funds
          </Button>
        </Stack>
      </Card>
    </Stack>
  );
}
