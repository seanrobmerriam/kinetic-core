"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  Anchor,
  Badge,
  Button,
  Card,
  Group,
  NumberInput,
  Paper,
  Select,
  SimpleGrid,
  Stack,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import {
  capitalize,
  formatAmount,
  formatTimestamp,
  parseAmount,
  truncateID,
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

export default function LoansPage() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [parties, setParties] = useState<Party[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [products, setProducts] = useState<LoanProduct[]>([]);
  const [loans, setLoans] = useState<Loan[]>([]);
  const [partyId, setPartyId] = useState<string | null>("");
  const [productId, setProductId] = useState<string | null>("");
  const [accountId, setAccountId] = useState<string | null>("");
  const [principal, setPrincipal] = useState("");
  const [term, setTerm] = useState<string | number>("");
  const [selectedLoan, setSelectedLoan] = useState<Loan | null>(null);
  const [repayments, setRepayments] = useState<LoanRepayment[]>([]);
  const [repayAmount, setRepayAmount] = useState("");
  const [repayType, setRepayType] = useState<string | null>("partial");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const partyResp = await api<ListResponse<Party>>("GET", "/parties");
        const ps = partyResp.items ?? [];
        if (!cancelled) setParties(ps);
        let allAccounts: Account[] = [];
        for (const p of ps) {
          try {
            const accResp = await api<ListResponse<Account>>(
              "GET",
              `/parties/${p.party_id}/accounts`,
            );
            if (accResp.items) allAccounts = allAccounts.concat(accResp.items);
          } catch {
            /* skip */
          }
        }
        if (!cancelled) setAccounts(allAccounts);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
      try {
        const lp = await api<ListResponse<LoanProduct>>(
          "GET",
          "/loan-products",
        );
        if (!cancelled) setProducts(lp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  useEffect(() => {
    if (!partyId) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setLoans([]);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const resp = await api<ListResponse<Loan>>(
          "GET",
          `/loans?party_id=${partyId}`,
        );
        if (!cancelled) setLoans(resp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [partyId, tick, setError]);

  const partyAccounts = useMemo(
    () => accounts.filter((a) => a.party_id === partyId),
    [accounts, partyId],
  );

  const productName = (id: string) =>
    products.find((p) => p.product_id === id)?.name ?? truncateID(id);

  const createLoan = async () => {
    if (!partyId) {
      setError("Select a customer first");
      return;
    }
    let principalAmt: number;
    try {
      principalAmt = parseAmount(principal);
    } catch {
      setError("Invalid principal amount");
      return;
    }
    const termMonths = typeof term === "number" ? term : parseInt(term, 10);
    if (!Number.isFinite(termMonths)) {
      setError("Invalid loan term");
      return;
    }
    try {
      await api("POST", "/loans", {
        party_id: partyId,
        product_id: productId,
        account_id: accountId,
        principal: principalAmt,
        term_months: termMonths,
      });
      setSuccess("Loan created");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const loadLoan = async (loanId: string) => {
    try {
      const loan = await api<Loan>("GET", `/loans/${loanId}`);
      setSelectedLoan(loan);
      const repaymentsResp = await api<ListResponse<LoanRepayment>>(
        "GET",
        `/loans/${loanId}/repayments`,
      );
      setRepayments(repaymentsResp.items ?? []);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const approve = async (loanId: string) => {
    try {
      await api("POST", `/loans/${loanId}/approve`);
      setSuccess("Loan approved");
      bump();
      if (selectedLoan?.loan_id === loanId) await loadLoan(loanId);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const disburse = async (loanId: string) => {
    try {
      await api("POST", `/loans/${loanId}/disburse`);
      setSuccess("Loan disbursed");
      bump();
      if (selectedLoan?.loan_id === loanId) await loadLoan(loanId);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const recordRepayment = async () => {
    if (!selectedLoan) return;
    let amt: number;
    try {
      amt = parseAmount(repayAmount);
    } catch {
      setError("Invalid repayment amount");
      return;
    }
    try {
      await api("POST", `/loans/${selectedLoan.loan_id}/repayments`, {
        amount: amt,
        payment_type: repayType,
      });
      setSuccess("Repayment recorded");
      setRepayAmount("");
      await loadLoan(selectedLoan.loan_id);
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const productCols: ColumnDef<LoanProduct>[] = [
    { key: "name", label: "Name", getValue: (p) => p.name },
    { key: "currency", label: "Currency", getValue: (p) => p.currency },
    {
      key: "amount_range",
      label: "Amount Range",
      getValue: (p) => p.min_amount,
      render: (p) =>
        `${formatAmount(p.min_amount, p.currency)} \u2013 ${formatAmount(p.max_amount, p.currency)}`,
    },
    {
      key: "term_range",
      label: "Term Range",
      getValue: (p) => p.min_term_months,
      render: (p) => `${p.min_term_months}\u2013${p.max_term_months} mo`,
    },
    {
      key: "rate",
      label: "Rate",
      getValue: (p) => p.interest_rate_bps,
      render: (p) => `${p.interest_rate_bps} bps`,
    },
    {
      key: "type",
      label: "Type",
      getValue: (p) => p.interest_type,
      render: (p) => capitalize(p.interest_type),
    },
    {
      key: "status",
      label: "Status",
      getValue: (p) => p.status,
      render: (p) => capitalize(p.status),
    },
  ];

  const loanCols: ColumnDef<Loan>[] = [
    {
      key: "id",
      label: "Loan",
      getValue: (l) => l.loan_id,
      render: (l) => (
        <Anchor
          component={Link}
          href={`/loans/${l.loan_id}`}
          size="sm"
          ff="monospace"
        >
          {truncateID(l.loan_id)}
        </Anchor>
      ),
      ff: "monospace",
    },
    {
      key: "product",
      label: "Product",
      getValue: (l) => productName(l.product_id),
    },
    {
      key: "principal",
      label: "Principal",
      getValue: (l) => l.principal,
      render: (l) => formatAmount(l.principal, l.currency),
    },
    {
      key: "outstanding",
      label: "Outstanding",
      getValue: (l) => l.outstanding_balance,
      render: (l) => formatAmount(l.outstanding_balance, l.currency),
    },
    {
      key: "monthly",
      label: "Monthly",
      getValue: (l) => l.monthly_payment,
      render: (l) => formatAmount(l.monthly_payment, l.currency),
    },
    {
      key: "status",
      label: "Status",
      getValue: (l) => l.status,
      render: (l) => (
        <Badge variant="light" radius="sm">
          {capitalize(l.status)}
        </Badge>
      ),
    },
    {
      key: "actions",
      label: "Actions",
      sortable: false,
      render: (l) => (
        <Group gap="xs">
          <Button
            size="xs"
            variant="light"
            component={Link}
            href={`/loans/${l.loan_id}`}
          >
            View
          </Button>
          {l.status === "pending" && (
            <Button
              size="xs"
              color="teal"
              variant="light"
              onClick={() => approve(l.loan_id)}
            >
              Approve
            </Button>
          )}
          {l.status === "approved" && (
            <Button
              size="xs"
              color="yellow"
              variant="light"
              onClick={() => disburse(l.loan_id)}
            >
              Disburse
            </Button>
          )}
        </Group>
      ),
    },
  ];

  return (
    <Stack gap="lg">
      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={4} mb="md">
          Current Loan Products
        </Title>
        <SortableTable
          data={products}
          columns={productCols}
          rowKey={(p) => p.product_id}
          searchPlaceholder="Search loan products..."
          emptyMessage="No loan products available"
          minWidth={700}
        />
      </Card>

      <Group align="flex-end">
        <Select
          id="loan-party-select"
          label="Customer"
          placeholder="Select customer"
          searchable
          data={parties.map((p) => ({
            value: p.party_id,
            label: `${p.full_name} (${p.email})`,
          }))}
          value={partyId}
          onChange={(v) => {
            setPartyId(v);
            setSelectedLoan(null);
            setRepayments([]);
          }}
          style={{ flex: 1, maxWidth: 400 }}
        />
        <Button variant="light" onClick={bump}>
          Refresh Loans
        </Button>
      </Group>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={4} mb="md">
          Create Loan
        </Title>
        <Stack>
          <Select
            id="loan-create-product"
            label="Loan Product"
            placeholder="Select product"
            data={products.map((p) => ({
              value: p.product_id,
              label: `${p.name} (${p.currency})`,
            }))}
            value={productId}
            onChange={setProductId}
          />
          <Select
            id="loan-create-account"
            label="Disbursement Account"
            placeholder="Select account"
            data={partyAccounts.map((a) => ({
              value: a.account_id,
              label: `${a.name} (${a.currency})`,
            }))}
            value={accountId}
            onChange={setAccountId}
          />
          <TextInput
            id="loan-create-principal"
            label="Principal"
            placeholder="1000.00"
            value={principal}
            onChange={(e) => setPrincipal(e.currentTarget.value)}
          />
          <NumberInput
            id="loan-create-term"
            label="Term (months)"
            placeholder="12"
            value={term}
            onChange={setTerm}
          />
          <Group>
            <Button id="create-loan-button" onClick={createLoan}>
              Create Loan
            </Button>
          </Group>
        </Stack>
      </Card>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={4} mb="md">
          Loans
        </Title>
        <SortableTable
          data={loans}
          columns={loanCols}
          rowKey={(l) => l.loan_id}
          searchPlaceholder="Search loans..."
          emptyMessage={
            partyId
              ? "No loans for the selected customer"
              : "Select a customer to view loans"
          }
          minWidth={900}
        />
      </Card>

      {selectedLoan && (
        <Card withBorder shadow="sm" radius="md" padding="lg">
          <Title order={4} mb="md">
            Loan Details and Repayments
          </Title>
          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="md" mb="md">
            <Paper p="md" withBorder radius="md">
              <Text size="xs" c="dimmed" tt="uppercase" fw={700}>
                Loan ID
              </Text>
              <Text mt={4} ff="monospace">
                {truncateID(selectedLoan.loan_id)}
              </Text>
            </Paper>
            <Paper p="md" withBorder radius="md">
              <Text size="xs" c="dimmed" tt="uppercase" fw={700}>
                Outstanding
              </Text>
              <Text mt={4} fw={600}>
                {formatAmount(
                  selectedLoan.outstanding_balance,
                  selectedLoan.currency,
                )}
              </Text>
            </Paper>
            <Paper p="md" withBorder radius="md">
              <Text size="xs" c="dimmed" tt="uppercase" fw={700}>
                Status
              </Text>
              <Text mt={4}>{capitalize(selectedLoan.status)}</Text>
            </Paper>
          </SimpleGrid>

          <Stack mb="md">
            <TextInput
              id="loan-repayment-amount"
              label="Repayment Amount"
              placeholder="50.00"
              value={repayAmount}
              onChange={(e) => setRepayAmount(e.currentTarget.value)}
            />
            <Select
              id="loan-repayment-type"
              label="Payment Type"
              data={["partial", "full"]}
              value={repayType}
              onChange={setRepayType}
            />
            <Group>
              <Button id="record-loan-repayment-button" onClick={recordRepayment}>
                Record Repayment
              </Button>
            </Group>
          </Stack>

          {(() => {
            const currency = selectedLoan.currency;
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
                key: "status",
                label: "Status",
                getValue: (r) => r.status,
                render: (r) => capitalize(r.status),
              },
              {
                key: "paid_at",
                label: "Paid At",
                getValue: (r) => r.paid_at,
                render: (r) => formatTimestamp(r.paid_at),
              },
            ];
            return (
              <SortableTable
                data={repayments}
                columns={repayCols}
                rowKey={(r) => r.repayment_id}
                searchPlaceholder="Search repayments..."
                emptyMessage="No repayments recorded yet"
                minWidth={700}
              />
            );
          })()}
        </Card>
      )}
    </Stack>
  );
}
