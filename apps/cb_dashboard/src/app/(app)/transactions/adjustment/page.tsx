"use client";

import { useState } from "react";
import {
  Alert,
  Button,
  Card,
  Divider,
  Group,
  NumberInput,
  Stack,
  Text,
  Textarea,
  TextInput,
  Title,
} from "@mantine/core";
import { useRouter } from "next/navigation";
import { createAdjustment, type AdjustmentPayload } from "@/lib/api";
import { useNotify } from "@/lib/notify";

export default function AdjustmentPage() {
  const router = useRouter();
  const { setError, setSuccess } = useNotify();

  const [idempotencyKey, setIdempotencyKey] = useState("");
  const [accountId, setAccountId] = useState("");
  const [amountMajor, setAmountMajor] = useState<number | "">(100);
  const [currency, setCurrency] = useState<string>("USD");
  const [description, setDescription] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<{ txn_id: string } | null>(null);
  const [validationError, setValidationError] = useState<string | null>(null);

  const validate = (): boolean => {
    if (!idempotencyKey.trim()) {
      setValidationError("Idempotency key is required.");
      return false;
    }
    if (!accountId.trim()) {
      setValidationError("Account ID is required.");
      return false;
    }
    if (!amountMajor || Number(amountMajor) <= 0) {
      setValidationError("Amount must be greater than zero.");
      return false;
    }
    if (description.trim().length < 10) {
      setValidationError("Reason/description must be at least 10 characters.");
      return false;
    }
    setValidationError(null);
    return true;
  };

  const submit = async () => {
    if (!validate()) return;
    setSubmitting(true);
    try {
      const amountMinor = Math.round(Number(amountMajor) * 100);
      const payload: AdjustmentPayload = {
        idempotency_key: idempotencyKey.trim(),
        account_id: accountId.trim(),
        amount: amountMinor,
        currency,
        description: description.trim(),
      };
      const resp = await createAdjustment(payload);
      setResult({ txn_id: resp.txn_id });
      setSuccess(`Adjustment posted — txn ${resp.txn_id}`);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  const clear = () => {
    setIdempotencyKey("");
    setAccountId("");
    setAmountMajor(100);
    setCurrency("USD");
    setDescription("");
    setResult(null);
    setValidationError(null);
  };

  if (result) {
    return (
      <Stack gap="xl">
        <Title order={2}>Adjustment Posted</Title>
        <Card withBorder radius="md" padding="lg">
          <Stack gap="md">
            <Text size="sm">
              The manual adjustment has been recorded successfully.
            </Text>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase">Transaction ID</Text>
              <Text ff="monospace">{result.txn_id}</Text>
            </div>
            <Divider />
            <Group>
              <Button
                variant="subtle"
                onClick={() => router.push(`/transactions/${result.txn_id}`)}
              >
                View Transaction →
              </Button>
              <Button variant="default" onClick={clear}>
                New Adjustment
              </Button>
            </Group>
          </Stack>
        </Card>
      </Stack>
    );
  }

  return (
    <Stack gap="xl">
      <Stack gap="md">
        <Title order={2}>Manual Ledger Adjustment</Title>
        <Text c="dimmed" size="sm">
          Create a break-fix journal entry. Both debit and credit legs are
          recorded; reason must be at least 10 characters. Ops_admin only.
        </Text>
      </Stack>

      {validationError && (
        <Alert color="red" title="Validation Error">
          {validationError}
        </Alert>
      )}

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Stack gap="md">
          <TextInput
            label="Idempotency Key"
            placeholder="unique-key-12345"
            value={idempotencyKey}
            onChange={(e) => setIdempotencyKey(e.currentTarget.value)}
            required
          />
          <TextInput
            label="Account ID"
            placeholder="Account to adjust…"
            value={accountId}
            onChange={(e) => setAccountId(e.currentTarget.value)}
            required
          />
          <Group grow>
            <NumberInput
              label="Amount (major units)"
              placeholder="Enter amount…"
              value={amountMajor}
              onChange={(val) => setAmountMajor(val as number | "")}
              min={0}
              decimalScale={2}
              required
            />
            <TextInput
              label="Currency"
              placeholder="USD"
              value={currency}
              onChange={(e) => setCurrency(e.currentTarget.value.toUpperCase())}
              required
            />
          </Group>
          <Textarea
            label="Reason / Description"
            placeholder="Describe why this adjustment is being made (min 10 chars)…"
            value={description}
            onChange={(e) => setDescription(e.currentTarget.value)}
            rows={3}
            required
          />
          <Group>
            <Button onClick={() => void submit()} loading={submitting}>
              Post Adjustment
            </Button>
            <Button variant="subtle" onClick={clear}>
              Clear
            </Button>
          </Group>
        </Stack>
      </Card>
    </Stack>
  );
}