"use client";

import { useEffect, useMemo, useState } from "react";
import {
  Badge,
  Button,
  Card,
  Group,
  NumberInput,
  Paper,
  Select,
  SimpleGrid,
  Stack,
  Table,
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

  return (
    <Stack gap="lg">
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
        {loans.length === 0 ? (
          <Text c="dimmed">
            {partyId
              ? "No loans for the selected customer"
              : "Select a customer to view loans"}
          </Text>
        ) : (
          <Table.ScrollContainer minWidth={900}>
            <Table verticalSpacing="sm" highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Loan</Table.Th>
                  <Table.Th>Product</Table.Th>
                  <Table.Th>Principal</Table.Th>
                  <Table.Th>Outstanding</Table.Th>
                  <Table.Th>Monthly</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {loans.map((l) => (
                  <Table.Tr key={l.loan_id}>
                    <Table.Td ff="monospace">{truncateID(l.loan_id)}</Table.Td>
                    <Table.Td>{productName(l.product_id)}</Table.Td>
                    <Table.Td>
                      {formatAmount(l.principal, l.currency)}
                    </Table.Td>
                    <Table.Td>
                      {formatAmount(l.outstanding_balance, l.currency)}
                    </Table.Td>
                    <Table.Td>
                      {formatAmount(l.monthly_payment, l.currency)}
                    </Table.Td>
                    <Table.Td>
                      <Badge variant="light" radius="sm">
                        {capitalize(l.status)}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Group gap="xs">
                        <Button
                          size="xs"
                          variant="light"
                          onClick={() => loadLoan(l.loan_id)}
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
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
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

          {repayments.length === 0 ? (
            <Text c="dimmed">No repayments recorded yet</Text>
          ) : (
            <Table.ScrollContainer minWidth={700}>
              <Table verticalSpacing="sm" highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Amount</Table.Th>
                    <Table.Th>Principal</Table.Th>
                    <Table.Th>Interest</Table.Th>
                    <Table.Th>Status</Table.Th>
                    <Table.Th>Paid At</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {repayments.map((r) => (
                    <Table.Tr key={r.repayment_id}>
                      <Table.Td>
                        {formatAmount(r.amount, selectedLoan.currency)}
                      </Table.Td>
                      <Table.Td>
                        {formatAmount(
                          r.principal_portion,
                          selectedLoan.currency,
                        )}
                      </Table.Td>
                      <Table.Td>
                        {formatAmount(
                          r.interest_portion,
                          selectedLoan.currency,
                        )}
                      </Table.Td>
                      <Table.Td>{capitalize(r.status)}</Table.Td>
                      <Table.Td>{formatTimestamp(r.paid_at)}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          )}
        </Card>
      )}
    </Stack>
  );
}
