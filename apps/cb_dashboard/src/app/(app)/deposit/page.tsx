"use client";

import { useState } from "react";
import Link from "next/link";
import {
  Anchor,
  Button,
  Card,
  Group,
  Select,
  SimpleGrid,
  Stack,
  TextInput,
  Title,
} from "@mantine/core";
import { IconArrowLeft } from "@/components/icons";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { parseAmount } from "@/lib/format";

const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CHF"];

interface FormProps {
  prefix: "deposit" | "withdraw";
  endpoint: string;
  bodyKey: "source_account_id" | "dest_account_id";
  label: string;
  color: string;
  successMessage: string;
}

function MoveForm({
  prefix,
  endpoint,
  bodyKey,
  label,
  color,
  successMessage,
}: FormProps) {
  const { setError, setSuccess } = useNotify();
  const [account, setAccount] = useState("");
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
      await api("POST", endpoint, {
        idempotency_key: `web-${Date.now()}`,
        [bodyKey]: account,
        amount: amt,
        currency,
        description: desc,
      });
      setSuccess(successMessage);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Card withBorder shadow="sm" radius="md" padding="lg">
      <Title order={4} mb="md">
        {label}
      </Title>
      <Stack>
        <TextInput
          id={`${prefix}-account`}
          label="Account ID"
          placeholder="Enter account ID"
          value={account}
          onChange={(e) => setAccount(e.currentTarget.value)}
        />
        <TextInput
          id={`${prefix}-amount`}
          label="Amount"
          placeholder="Enter amount"
          value={amount}
          onChange={(e) => setAmount(e.currentTarget.value)}
        />
        <Select
          id={`${prefix}-currency`}
          label="Currency"
          data={CURRENCIES}
          value={currency}
          onChange={setCurrency}
        />
        <TextInput
          id={`${prefix}-desc`}
          label="Description"
          placeholder="Enter description"
          value={desc}
          onChange={(e) => setDesc(e.currentTarget.value)}
        />
        <Button
          color={color}
          onClick={submit}
          disabled={submitting}
          loading={submitting}
        >
          {label}
        </Button>
      </Stack>
    </Card>
  );
}

export default function DepositWithdrawPage() {
  return (
    <Stack gap="lg">
      <Anchor component={Link} href="/dashboard" size="sm">
        <Group gap={4}>
          <IconArrowLeft size={14} />
          Back
        </Group>
      </Anchor>
      <Title order={3}>Deposit / Withdraw</Title>

      <SimpleGrid cols={{ base: 1, lg: 2 }} spacing="md">
        <MoveForm
          prefix="deposit"
          endpoint="/transactions/deposit"
          bodyKey="dest_account_id"
          label="Deposit"
          color="teal"
          successMessage="Deposit successful!"
        />
        <MoveForm
          prefix="withdraw"
          endpoint="/transactions/withdraw"
          bodyKey="source_account_id"
          label="Withdraw"
          color="yellow"
          successMessage="Withdrawal successful!"
        />
      </SimpleGrid>
    </Stack>
  );
}
