"use client";

import Link from "next/link";
import { use, useEffect, useState } from "react";
import {
  Alert,
  Anchor,
  Badge,
  Button,
  Card,
  Divider,
  Group,
  Modal,
  Select,
  SimpleGrid,
  Stack,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { IconArrowLeft } from "@/components/icons";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import {
  capitalize,
  formatAmount,
  formatTimestamp,
  parseAmount,
} from "@/lib/format";
import type {
  Account,
  Loan,
  LoanProduct,
  LoanRepayment,
  Party,
} from "@/lib/types";
import { SortableTable } from "@/components/SortableTable";
import type { ColumnDef } from "@/components/SortableTable";

interface ListResponse<T> {
  items: T[];
}

function statusColor(s: string) {
  if (s === "active" || s === "disbursed") return "teal";
  if (s === "approved") return "blue";
  if (s === "pending") return "yellow";
  if (s === "closed" || s === "settled") return "gray";
  if (s === "rejected" || s === "defaulted") return "red";
  return "gray";
}

function InfoField({
  label,
  value,
  mono,
}: {
  label: string;
  value: React.ReactNode;
  mono?: boolean;
}) {
  return (
    <div>
      <Text size="xs" c="dimmed" tt="uppercase" fw={700} mb={2}>
        {label}
      </Text>
      <Text size="sm" ff={mono ? "monospace" : undefined}>
        {value ?? "—"}
      </Text>
    </div>
  );
}

function BackLink() {
  return (
    <Anchor component={Link} href="/loans" size="sm">
      <Group gap={4}>
        <IconArrowLeft size={14} />
        Back to Loans
      </Group>
    </Anchor>
  );
}

export default function LoanDetailPage({
  params,
}: {
  params: Promise<{ loanId: string }>;
}) {
  const { loanId } = use(params);
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();

  const [loan, setLoan] = useState<Loan | null>(null);
  const [product, setProduct] = useState<LoanProduct | null>(null);
  const [party, setParty] = useState<Party | null>(null);
  const [account, setAccount] = useState<Account | null>(null);
  const [repayments, setRepayments] = useState<LoanRepayment[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [actionBusy, setActionBusy] = useState(false);
  const [repayOpen, setRepayOpen] = useState(false);
  const [repayAmount, setRepayAmount] = useState("");
  const [repayType, setRepayType] = useState<string | null>("partial");
  const [repayBusy, setRepayBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!cancelled) {
        setLoading(true);
        setLoadError(null);
      }
      try {
        const l = await api<Loan>("GET", `/loans/${loanId}`);
        if (cancelled) return;
        setLoan(l);

        const sideLoads: Promise<unknown>[] = [];
        sideLoads.push(
          api<ListResponse<LoanRepayment>>(
            "GET",
            `/loans/${loanId}/repayments`,
          )
            .then((r) => {
              if (!cancelled) setRepayments(r.items ?? []);
            })
            .catch(() => {}),
        );
        if (l.party_id) {
          sideLoads.push(
            api<Party>("GET", `/parties/${l.party_id}`)
              .then((p) => {
                if (!cancelled) setParty(p);
              })
              .catch(() => {}),
          );
        }
        if (l.account_id) {
          sideLoads.push(
            api<Account>("GET", `/accounts/${l.account_id}`)
              .then((a) => {
                if (!cancelled) setAccount(a);
              })
              .catch(() => {}),
          );
        }
        if (l.product_id) {
          sideLoads.push(
            api<LoanProduct>("GET", `/loan-products/${l.product_id}`)
              .then((p) => {
                if (!cancelled) setProduct(p);
              })
              .catch(() => {}),
          );
        }
        await Promise.all(sideLoads);
      } catch (err) {
        if (!cancelled) setLoadError((err as Error).message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [loanId, tick]);

  const reload = async () => {
    try {
      const l = await api<Loan>("GET", `/loans/${loanId}`);
      setLoan(l);
      const r = await api<ListResponse<LoanRepayment>>(
        "GET",
        `/loans/${loanId}/repayments`,
      );
      setRepayments(r.items ?? []);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const approve = async () => {
    if (!loan) return;
    setActionBusy(true);
    try {
      await api("POST", `/loans/${loan.loan_id}/approve`);
      setSuccess("Loan approved");
      await reload();
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setActionBusy(false);
    }
  };

  const disburse = async () => {
    if (!loan) return;
    setActionBusy(true);
    try {
      await api("POST", `/loans/${loan.loan_id}/disburse`);
      setSuccess("Loan disbursed");
      await reload();
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setActionBusy(false);
    }
  };

  const recordRepayment = async () => {
    if (!loan) return;
    let amt: number;
    try {
      amt = parseAmount(repayAmount);
    } catch {
      setError("Invalid repayment amount");
      return;
    }
    setRepayBusy(true);
    try {
      await api("POST", `/loans/${loan.loan_id}/repayments`, {
        amount: amt,
        payment_type: repayType,
      });
      setSuccess("Repayment recorded");
      setRepayAmount("");
      setRepayOpen(false);
      await reload();
      bump();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setRepayBusy(false);
    }
  };

  if (loading && !loan) {
    return (
      <Stack gap="lg">
        <BackLink />
        <Text c="dimmed">Loading loan…</Text>
      </Stack>
    );
  }

  if (loadError || !loan) {
    return (
      <Stack gap="lg">
        <BackLink />
        <Alert color="red" title="Could not load loan">
          {loadError ?? "Loan not found."}
        </Alert>
      </Stack>
    );
  }

  const currency = loan.currency;
  const repayCols: ColumnDef<LoanRepayment>[] = [
    {
      key: "amount",
      label: "Amount",
      getValue: (r) => r.amount,
      render: (r) => formatAmount(r.amount, currency),
    },
    {
      key: "principal",
      label: "Principal",
      getValue: (r) => r.principal_portion,
      render: (r) => formatAmount(r.principal_portion, currency),
    },
    {
      key: "interest",
      label: "Interest",
      getValue: (r) => r.interest_portion,
      render: (r) => formatAmount(r.interest_portion, currency),
    },
    {
      key: "penalty",
      label: "Penalty",
      getValue: (r) => r.penalty,
      render: (r) => formatAmount(r.penalty, currency),
    },
    {
      key: "status",
      label: "Status",
      getValue: (r) => r.status,
      render: (r) => capitalize(r.status),
    },
    {
      key: "due",
      label: "Due",
      getValue: (r) => r.due_date,
      render: (r) => formatTimestamp(r.due_date),
    },
    {
      key: "paid_at",
      label: "Paid At",
      getValue: (r) => r.paid_at,
      render: (r) => formatTimestamp(r.paid_at),
    },
  ];

  const canApprove = loan.status === "pending";
  const canDisburse = loan.status === "approved";
  const canRepay = ["active", "disbursed"].includes(loan.status);
  const ratePct = (loan.interest_rate_bps / 100).toFixed(2);

  return (
    <Stack gap="lg">
      <BackLink />

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Group justify="space-between" align="flex-start" wrap="nowrap">
          <div>
            <Title order={3}>Loan</Title>
            <Text size="xs" c="dimmed" ff="monospace" mt={4}>
              ID: {loan.loan_id}
            </Text>
          </div>
          <Group gap="xs">
            <Badge size="lg" variant="light" color={statusColor(loan.status)} radius="sm">
              {capitalize(loan.status)}
            </Badge>
            {canApprove && (
              <Button color="teal" variant="light" size="sm" onClick={approve} loading={actionBusy}>
                Approve
              </Button>
            )}
            {canDisburse && (
              <Button color="yellow" variant="light" size="sm" onClick={disburse} loading={actionBusy}>
                Disburse
              </Button>
            )}
            {canRepay && (
              <Button variant="light" size="sm" onClick={() => setRepayOpen(true)}>
                Record repayment
              </Button>
            )}
          </Group>
        </Group>
      </Card>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={5} mb="md">Loan Details</Title>
        <Divider mb="md" />
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
          <InfoField label="Principal" value={formatAmount(loan.principal, currency)} mono />
          <InfoField
            label="Outstanding Balance"
            value={formatAmount(loan.outstanding_balance, currency)}
            mono
          />
          <InfoField
            label="Monthly Payment"
            value={formatAmount(loan.monthly_payment, currency)}
            mono
          />
          <InfoField label="Currency" value={currency} />
          <InfoField label="Interest Rate" value={`${ratePct}% (${loan.interest_rate_bps} bps)`} />
          <InfoField label="Term" value={`${loan.term_months} months`} />
          <InfoField
            label="Product"
            value={
              product ? (
                <span>{product.name}</span>
              ) : (
                <Text size="sm" ff="monospace">{loan.product_id}</Text>
              )
            }
          />
          <InfoField
            label="Borrower"
            value={
              party ? (
                <Anchor component={Link} href={`/customers/${party.party_id}`} size="sm">
                  {party.full_name}
                </Anchor>
              ) : (
                <Text size="sm" ff="monospace">{loan.party_id}</Text>
              )
            }
          />
          <InfoField
            label="Disbursement Account"
            value={
              loan.account_id ? (
                <Anchor component={Link} href={`/accounts/${loan.account_id}`} size="sm" ff="monospace">
                  {account?.name ? `${account.name} (${loan.account_id})` : loan.account_id}
                </Anchor>
              ) : (
                "—"
              )
            }
          />
          <InfoField label="Disbursed At" value={formatTimestamp(loan.disbursed_at)} />
          <InfoField label="Created" value={formatTimestamp(loan.created_at)} />
          <InfoField label="Updated" value={formatTimestamp(loan.updated_at)} />
        </SimpleGrid>
      </Card>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={5} mb="md">Repayments</Title>
        <Divider mb="md" />
        <SortableTable
          data={repayments}
          columns={repayCols}
          rowKey={(r) => r.repayment_id}
          searchPlaceholder="Search repayments..."
          emptyMessage="No repayments recorded yet"
          minWidth={800}
        />
      </Card>

      <Modal
        opened={repayOpen}
        onClose={() => (repayBusy ? undefined : setRepayOpen(false))}
        title="Record repayment"
        centered
        withCloseButton={!repayBusy}
      >
        <Stack gap="md">
          <TextInput
            id="loan-detail-repay-amount"
            label="Amount"
            placeholder="50.00"
            value={repayAmount}
            onChange={(e) => setRepayAmount(e.currentTarget.value)}
            disabled={repayBusy}
          />
          <Select
            id="loan-detail-repay-type"
            label="Payment Type"
            data={["partial", "full"]}
            value={repayType}
            onChange={setRepayType}
            disabled={repayBusy}
          />
          <Group justify="flex-end">
            <Button
              variant="default"
              onClick={() => setRepayOpen(false)}
              disabled={repayBusy}
            >
              Cancel
            </Button>
            <Button onClick={recordRepayment} loading={repayBusy}>
              Record
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}
