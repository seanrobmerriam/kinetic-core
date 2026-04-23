"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  Anchor,
  Button,
  Card,
  Group,
  Select,
  Stack,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { IconArrowLeft } from "@/components/icons";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRouter } from "next/navigation";
import { formatAmount } from "@/lib/format";
import type { Account, Party, PaymentOrder } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

const CURRENCIES = [
  { value: "USD", label: "USD — US Dollar" },
  { value: "EUR", label: "EUR — Euro" },
  { value: "GBP", label: "GBP — British Pound" },
  { value: "JPY", label: "JPY — Japanese Yen" },
  { value: "CHF", label: "CHF — Swiss Franc" },
  { value: "CAD", label: "CAD — Canadian Dollar" },
  { value: "AUD", label: "AUD — Australian Dollar" },
  { value: "SGD", label: "SGD — Singapore Dollar" },
];

export default function InternationalWirePage() {
  const router = useRouter();
  const { setError, setSuccess } = useNotify();

  const [parties, setParties] = useState<Party[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);

  const [partyId, setPartyId] = useState<string | null>(null);
  const [sourceId, setSourceId] = useState<string | null>(null);
  const [destId, setDestId] = useState<string | null>(null);
  const [amount, setAmount] = useState("");
  const [currency, setCurrency] = useState<string | null>("USD");
  const [swiftBic, setSwiftBic] = useState("");
  const [iban, setIban] = useState("");
  const [bankName, setBankName] = useState("");
  const [country, setCountry] = useState("");
  const [purpose, setPurpose] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const partyList = partyResp.items ?? [];
        const allAccounts: Account[] = [];
        for (const p of partyList) {
          try {
            const accResp = await api<ListResponse<Account>>(
              "GET",
              `/parties/${p.party_id}/accounts`,
            );
            allAccounts.push(...(accResp.items ?? []));
          } catch {
            /* skip */
          }
        }
        if (!cancelled) {
          setParties(partyList);
          setAccounts(allAccounts);
        }
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [setError]);

  const partyAccounts = accounts.filter((a) => a.party_id === partyId);
  const destAccounts = accounts.filter(
    (a) => a.party_id !== partyId || a.account_id !== sourceId,
  );

  const submit = async () => {
    if (!partyId || !sourceId || !destId || !amount || submitting) return;
    const amountInt = Math.round(parseFloat(amount) * 100);
    if (isNaN(amountInt) || amountInt <= 0) {
      setError("Invalid amount");
      return;
    }
    setSubmitting(true);
    try {
      const ikey = `wire-intl-${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const order = await api<PaymentOrder>("POST", "/payment-orders", {
        idempotency_key: ikey,
        party_id: partyId,
        source_account_id: sourceId,
        dest_account_id: destId,
        amount: amountInt,
      });
      setSuccess("International wire initiated");
      router.push(`/payments/${order.payment_id}`);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  const partyOptions = parties.map((p) => ({
    value: p.party_id,
    label: p.full_name,
  }));

  const sourceOptions = partyAccounts.map((a) => ({
    value: a.account_id,
    label: `${a.name} (${formatAmount(a.balance, a.currency)})`,
  }));

  const destOptions = destAccounts.map((a) => ({
    value: a.account_id,
    label: `${a.name} (${a.currency})`,
  }));

  return (
    <Stack gap="lg">
      <Anchor component={Link} href="/payments" size="sm">
        <Group gap={4}>
          <IconArrowLeft size={14} />
          Back to Payments
        </Group>
      </Anchor>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={4} mb={4}>
          Send International Wire
        </Title>
        <Text size="sm" c="dimmed" mb="lg">
          Initiate a SWIFT international wire transfer. Ensure all recipient
          banking details are accurate before submitting.
        </Text>

        <Stack>
          <Title order={6} c="dimmed">
            Sender
          </Title>
          <Group grow>
            <Select
              label="Party"
              placeholder="Select party"
              data={partyOptions}
              value={partyId}
              onChange={(v) => {
                setPartyId(v);
                setSourceId(null);
                setDestId(null);
              }}
              searchable
              required
            />
            <Select
              label="From Account"
              placeholder="Source account"
              data={sourceOptions}
              value={sourceId}
              onChange={setSourceId}
              disabled={!partyId}
              required
            />
          </Group>

          <Title order={6} c="dimmed" mt="xs">
            Recipient Bank Details
          </Title>
          <Group grow>
            <TextInput
              label="SWIFT / BIC Code"
              placeholder="e.g. DEUTDEDB"
              value={swiftBic}
              onChange={(e) => setSwiftBic(e.currentTarget.value.toUpperCase())}
              maxLength={11}
            />
            <TextInput
              label="IBAN / Account Number"
              placeholder="e.g. DE89370400440532013000"
              value={iban}
              onChange={(e) => setIban(e.currentTarget.value.toUpperCase())}
            />
          </Group>
          <Group grow>
            <TextInput
              label="Receiving Bank Name"
              placeholder="Bank name"
              value={bankName}
              onChange={(e) => setBankName(e.currentTarget.value)}
            />
            <TextInput
              label="Country"
              placeholder="e.g. Germany"
              value={country}
              onChange={(e) => setCountry(e.currentTarget.value)}
            />
          </Group>

          <Title order={6} c="dimmed" mt="xs">
            Payment Details
          </Title>
          <Group grow>
            <TextInput
              label="Amount"
              placeholder="0.00"
              value={amount}
              onChange={(e) => setAmount(e.currentTarget.value)}
              type="number"
              min="0"
              step="0.01"
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
          <Group grow>
            <Select
              label="Credit Account (Internal)"
              placeholder="Destination account"
              data={destOptions}
              value={destId}
              onChange={setDestId}
              disabled={!partyId}
              required
            />
            <TextInput
              label="Purpose of Payment"
              placeholder="e.g. Trade settlement"
              value={purpose}
              onChange={(e) => setPurpose(e.currentTarget.value)}
            />
          </Group>

          <Group mt="sm">
            <Button
              onClick={submit}
              loading={submitting}
              disabled={!partyId || !sourceId || !destId || !amount}
            >
              Send International Wire
            </Button>
            <Button
              variant="subtle"
              color="gray"
              component={Link}
              href="/payments"
            >
              Cancel
            </Button>
          </Group>
        </Stack>
      </Card>
    </Stack>
  );
}
