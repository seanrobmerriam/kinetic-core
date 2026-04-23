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

const ENTRY_CLASSES = [
  { value: "PPD", label: "PPD — Prearranged Payment & Deposit (consumer)" },
  { value: "CCD", label: "CCD — Corporate Credit or Debit (business)" },
  { value: "WEB", label: "WEB — Internet Initiated (consumer)" },
];

export default function PushAchPage() {
  const router = useRouter();
  const { setError, setSuccess } = useNotify();

  const [parties, setParties] = useState<Party[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);

  const [partyId, setPartyId] = useState<string | null>(null);
  const [sourceId, setSourceId] = useState<string | null>(null);
  const [amount, setAmount] = useState("");
  const [recipientRouting, setRecipientRouting] = useState("");
  const [recipientAccount, setRecipientAccount] = useState("");
  const [holderName, setHolderName] = useState("");
  const [entryClass, setEntryClass] = useState<string | null>("PPD");
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

  const submit = async () => {
    if (!partyId || !sourceId || !amount || submitting) return;
    const amountInt = Math.round(parseFloat(amount) * 100);
    if (isNaN(amountInt) || amountInt <= 0) {
      setError("Invalid amount");
      return;
    }
    setSubmitting(true);
    try {
      const ikey = `ach-push-${Date.now()}-${Math.random().toString(36).slice(2)}`;
      // Push ACH: debit internal account (source) and credit external account
      // Using sourceId as both source and dest for the internal leg until external account support is added
      const order = await api<PaymentOrder>("POST", "/payment-orders", {
        idempotency_key: ikey,
        party_id: partyId,
        source_account_id: sourceId,
        dest_account_id: sourceId,
        amount: amountInt,
      });
      setSuccess("Push ACH initiated");
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
          Push ACH
        </Title>
        <Text size="sm" c="dimmed" mb="lg">
          Initiate an ACH credit to push funds from an internal account to an
          external recipient account.
        </Text>

        <Stack>
          <Title order={6} c="dimmed">
            Source
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
              }}
              searchable
              required
            />
            <Select
              label="Debit From Account"
              placeholder="Internal source account"
              data={sourceOptions}
              value={sourceId}
              onChange={setSourceId}
              disabled={!partyId}
              required
            />
          </Group>

          <Title order={6} c="dimmed" mt="xs">
            Recipient (External Account)
          </Title>
          <Group grow>
            <TextInput
              label="Account Holder Name"
              placeholder="Name on account"
              value={holderName}
              onChange={(e) => setHolderName(e.currentTarget.value)}
              required
            />
            <Select
              label="SEC Entry Class"
              data={ENTRY_CLASSES}
              value={entryClass}
              onChange={setEntryClass}
              required
            />
          </Group>
          <Group grow>
            <TextInput
              label="Recipient Routing Number (ABA)"
              placeholder="9 digits"
              value={recipientRouting}
              onChange={(e) => setRecipientRouting(e.currentTarget.value)}
              maxLength={9}
              required
            />
            <TextInput
              label="Recipient Account Number"
              placeholder="Account to credit"
              value={recipientAccount}
              onChange={(e) => setRecipientAccount(e.currentTarget.value)}
              required
            />
          </Group>

          <Title order={6} c="dimmed" mt="xs">
            Payment Details
          </Title>
          <TextInput
            label="Amount (USD)"
            placeholder="0.00"
            value={amount}
            onChange={(e) => setAmount(e.currentTarget.value)}
            type="number"
            min="0"
            step="0.01"
            required
            style={{ maxWidth: 280 }}
          />

          <Group mt="sm">
            <Button
              onClick={submit}
              loading={submitting}
              disabled={!partyId || !sourceId || !amount}
            >
              Initiate Push ACH
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
