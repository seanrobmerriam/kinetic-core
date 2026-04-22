"use client";

import { useEffect, useState } from "react";
import {
  Button,
  Card,
  Group,
  Modal,
  NumberInput,
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
import { capitalize, formatAmount, parseAmount } from "@/lib/format";
import type { LoanProduct, SavingsProduct } from "@/lib/types";

interface ListResponse<T> {
  items: T[];
}

export default function ProductsPage() {
  const { setError, setSuccess } = useNotify();
  const { tick, bump } = useRefresh();
  const [savings, setSavings] = useState<SavingsProduct[]>([]);
  const [loans, setLoans] = useState<LoanProduct[]>([]);
  const [viewSavings, setViewSavings] = useState<SavingsProduct | null>(null);
  const [viewLoan, setViewLoan] = useState<LoanProduct | null>(null);

  // Savings form
  const [sName, setSName] = useState("");
  const [sDesc, setSDesc] = useState("");
  const [sRate, setSRate] = useState<string | number>("");
  const [sMin, setSMin] = useState("");
  const [sCurrency, setSCurrency] = useState<string | null>("USD");
  const [sInterestType, setSInterestType] = useState<string | null>("simple");
  const [sCompounding, setSCompounding] = useState<string | null>("daily");

  // Loan form
  const [lName, setLName] = useState("");
  const [lDesc, setLDesc] = useState("");
  const [lMin, setLMin] = useState("");
  const [lMax, setLMax] = useState("");
  const [lMinTerm, setLMinTerm] = useState<string | number>("");
  const [lMaxTerm, setLMaxTerm] = useState<string | number>("");
  const [lRate, setLRate] = useState<string | number>("");
  const [lCurrency, setLCurrency] = useState<string | null>("USD");
  const [lInterestType, setLInterestType] = useState<string | null>("flat");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const sResp = await api<ListResponse<SavingsProduct>>(
          "GET",
          "/savings-products",
        );
        if (!cancelled) setSavings(sResp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
      try {
        const lResp = await api<ListResponse<LoanProduct>>(
          "GET",
          "/loan-products",
        );
        if (!cancelled) setLoans(lResp.items ?? []);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tick, setError]);

  const createSavings = async () => {
    const rateBps =
      typeof sRate === "number" ? sRate : parseInt(sRate, 10);
    if (!Number.isFinite(rateBps)) {
      setError("Invalid interest rate");
      return;
    }
    let minBalance: number;
    try {
      minBalance = parseAmount(sMin);
    } catch {
      setError("Invalid minimum balance");
      return;
    }
    try {
      await api("POST", "/savings-products", {
        name: sName,
        description: sDesc,
        currency: sCurrency,
        interest_rate_bps: rateBps,
        interest_type: sInterestType,
        compounding_period: sCompounding,
        minimum_balance: minBalance,
      });
      setSuccess("Savings product created");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const createLoan = async () => {
    const minTerm =
      typeof lMinTerm === "number" ? lMinTerm : parseInt(lMinTerm, 10);
    const maxTerm =
      typeof lMaxTerm === "number" ? lMaxTerm : parseInt(lMaxTerm, 10);
    const rateBps =
      typeof lRate === "number" ? lRate : parseInt(lRate, 10);
    if (!Number.isFinite(minTerm) || !Number.isFinite(maxTerm)) {
      setError("Invalid loan product term");
      return;
    }
    if (!Number.isFinite(rateBps)) {
      setError("Invalid loan product rate");
      return;
    }
    let minAmt: number;
    let maxAmt: number;
    try {
      minAmt = parseAmount(lMin);
      maxAmt = parseAmount(lMax);
    } catch {
      setError("Invalid loan product amounts");
      return;
    }
    try {
      await api("POST", "/loan-products", {
        name: lName,
        description: lDesc,
        currency: lCurrency,
        min_amount: minAmt,
        max_amount: maxAmt,
        min_term_months: minTerm,
        max_term_months: maxTerm,
        interest_rate_bps: rateBps,
        interest_type: lInterestType,
      });
      setSuccess("Loan product created");
      bump();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <Stack gap="lg">
      <Group justify="space-between">
        <Title order={3}>Product Management</Title>
        <Button variant="light" onClick={bump}>
          Refresh Products
        </Button>
      </Group>

      {/* Savings Products table */}
      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={4} mb="md">
          Savings Products
        </Title>
        {savings.length === 0 ? (
          <Text c="dimmed">No savings products yet</Text>
        ) : (
          <Table.ScrollContainer minWidth={700}>
            <Table verticalSpacing="sm" highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Name</Table.Th>
                  <Table.Th>Currency</Table.Th>
                  <Table.Th>Rate</Table.Th>
                  <Table.Th>Type</Table.Th>
                  <Table.Th>Minimum Balance</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {savings.map((p) => (
                  <Table.Tr key={p.product_id}>
                    <Table.Td>{p.name}</Table.Td>
                    <Table.Td>{p.currency}</Table.Td>
                    <Table.Td>{p.interest_rate_bps} bps</Table.Td>
                    <Table.Td>
                      {capitalize(p.interest_type)} /{" "}
                      {capitalize(p.compounding_period)}
                    </Table.Td>
                    <Table.Td>
                      {formatAmount(p.minimum_balance, p.currency)}
                    </Table.Td>
                    <Table.Td>{capitalize(p.status)}</Table.Td>
                    <Table.Td>
                      <Button
                        size="xs"
                        variant="light"
                        onClick={() => setViewSavings(p)}
                        aria-label={`View savings product ${p.name}`}
                      >
                        View
                      </Button>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Card>

      {/* Create Savings Product form */}
      <SimpleGrid cols={{ base: 1, lg: 2 }} spacing="md">
        <Card withBorder shadow="sm" radius="md" padding="lg">
          <Title order={4} mb="md">
            Create Savings Product
          </Title>
          <Stack>
            <TextInput
              id="savings-name"
              label="Name"
              placeholder="High Yield Savings"
              value={sName}
              onChange={(e) => setSName(e.currentTarget.value)}
            />
            <TextInput
              id="savings-description"
              label="Description"
              value={sDesc}
              onChange={(e) => setSDesc(e.currentTarget.value)}
            />
            <NumberInput
              id="savings-rate-bps"
              label="Interest Rate (bps)"
              placeholder="450"
              value={sRate}
              onChange={setSRate}
            />
            <TextInput
              id="savings-minimum-balance"
              label="Minimum Balance"
              placeholder="100.00"
              value={sMin}
              onChange={(e) => setSMin(e.currentTarget.value)}
            />
            <Select
              id="savings-currency"
              label="Currency"
              data={["USD", "EUR", "GBP", "JPY"]}
              value={sCurrency}
              onChange={setSCurrency}
            />
            <Select
              id="savings-interest-type"
              label="Interest Type"
              data={["simple", "compound"]}
              value={sInterestType}
              onChange={setSInterestType}
            />
            <Select
              id="savings-compounding-period"
              label="Compounding Period"
              data={["daily", "monthly", "quarterly", "annually"]}
              value={sCompounding}
              onChange={setSCompounding}
            />
            <Button id="create-savings-product-button" onClick={createSavings}>
              Create Savings Product
            </Button>
          </Stack>
        </Card>
      </SimpleGrid>

      {/* Loan Products table */}
      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Title order={4} mb="md">
          Loan Products
        </Title>
        {loans.length === 0 ? (
          <Text c="dimmed">No loan products yet</Text>
        ) : (
          <Table.ScrollContainer minWidth={700}>
            <Table verticalSpacing="sm" highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Name</Table.Th>
                  <Table.Th>Currency</Table.Th>
                  <Table.Th>Amount Range</Table.Th>
                  <Table.Th>Term Range</Table.Th>
                  <Table.Th>Rate</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {loans.map((p) => (
                  <Table.Tr key={p.product_id}>
                    <Table.Td>{p.name}</Table.Td>
                    <Table.Td>{p.currency}</Table.Td>
                    <Table.Td>
                      {formatAmount(p.min_amount, p.currency)} -{" "}
                      {formatAmount(p.max_amount, p.currency)}
                    </Table.Td>
                    <Table.Td>
                      {p.min_term_months}-{p.max_term_months} mo
                    </Table.Td>
                    <Table.Td>
                      {p.interest_rate_bps} bps {capitalize(p.interest_type)}
                    </Table.Td>
                    <Table.Td>{capitalize(p.status)}</Table.Td>
                    <Table.Td>
                      <Button
                        size="xs"
                        variant="light"
                        onClick={() => setViewLoan(p)}
                        aria-label={`View loan product ${p.name}`}
                      >
                        View
                      </Button>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Card>

      {/* Create Loan Product form */}
      <SimpleGrid cols={{ base: 1, lg: 2 }} spacing="md">
        <Card withBorder shadow="sm" radius="md" padding="lg">
          <Title order={4} mb="md">
            Create Loan Product
          </Title>
          <Stack>
            <TextInput
              id="loan-product-name"
              label="Name"
              placeholder="Starter Loan"
              value={lName}
              onChange={(e) => setLName(e.currentTarget.value)}
            />
            <TextInput
              id="loan-product-description"
              label="Description"
              value={lDesc}
              onChange={(e) => setLDesc(e.currentTarget.value)}
            />
            <Group grow>
              <TextInput
                id="loan-product-min-amount"
                label="Min Amount"
                placeholder="100.00"
                value={lMin}
                onChange={(e) => setLMin(e.currentTarget.value)}
              />
              <TextInput
                id="loan-product-max-amount"
                label="Max Amount"
                placeholder="5000.00"
                value={lMax}
                onChange={(e) => setLMax(e.currentTarget.value)}
              />
            </Group>
            <Group grow>
              <NumberInput
                id="loan-product-min-term"
                label="Min Term (months)"
                value={lMinTerm}
                onChange={setLMinTerm}
              />
              <NumberInput
                id="loan-product-max-term"
                label="Max Term (months)"
                value={lMaxTerm}
                onChange={setLMaxTerm}
              />
            </Group>
            <NumberInput
              id="loan-product-rate-bps"
              label="Interest Rate (bps)"
              placeholder="1200"
              value={lRate}
              onChange={setLRate}
            />
            <Select
              id="loan-product-currency"
              label="Currency"
              data={["USD", "EUR", "GBP", "JPY"]}
              value={lCurrency}
              onChange={setLCurrency}
            />
            <Select
              id="loan-product-interest-type"
              label="Interest Type"
              data={["flat", "declining"]}
              value={lInterestType}
              onChange={setLInterestType}
            />
            <Button id="create-loan-product-button" onClick={createLoan}>
              Create Loan Product
            </Button>
          </Stack>
        </Card>
      </SimpleGrid>

      {/* Savings product detail modal */}
      <Modal
        opened={viewSavings !== null}
        onClose={() => setViewSavings(null)}
        title={viewSavings?.name ?? "Savings Product"}
        size="md"
      >
        {viewSavings && (
          <Stack gap="xs">
            <Group justify="space-between">
              <Text fw={500}>ID</Text>
              <Text c="dimmed" size="sm">{viewSavings.product_id}</Text>
            </Group>
            {viewSavings.description && (
              <Group justify="space-between">
                <Text fw={500}>Description</Text>
                <Text c="dimmed" size="sm">{viewSavings.description}</Text>
              </Group>
            )}
            <Group justify="space-between">
              <Text fw={500}>Currency</Text>
              <Text>{viewSavings.currency}</Text>
            </Group>
            <Group justify="space-between">
              <Text fw={500}>Interest Rate</Text>
              <Text>{viewSavings.interest_rate_bps} bps</Text>
            </Group>
            <Group justify="space-between">
              <Text fw={500}>Interest Type</Text>
              <Text>{capitalize(viewSavings.interest_type)}</Text>
            </Group>
            <Group justify="space-between">
              <Text fw={500}>Compounding Period</Text>
              <Text>{capitalize(viewSavings.compounding_period)}</Text>
            </Group>
            <Group justify="space-between">
              <Text fw={500}>Minimum Balance</Text>
              <Text>{formatAmount(viewSavings.minimum_balance, viewSavings.currency)}</Text>
            </Group>
            <Group justify="space-between">
              <Text fw={500}>Status</Text>
              <Text>{capitalize(viewSavings.status)}</Text>
            </Group>
          </Stack>
        )}
      </Modal>

      {/* Loan product detail modal */}
      <Modal
        opened={viewLoan !== null}
        onClose={() => setViewLoan(null)}
        title={viewLoan?.name ?? "Loan Product"}
        size="md"
      >
        {viewLoan && (
          <Stack gap="xs">
            <Group justify="space-between">
              <Text fw={500}>ID</Text>
              <Text c="dimmed" size="sm">{viewLoan.product_id}</Text>
            </Group>
            {viewLoan.description && (
              <Group justify="space-between">
                <Text fw={500}>Description</Text>
                <Text c="dimmed" size="sm">{viewLoan.description}</Text>
              </Group>
            )}
            <Group justify="space-between">
              <Text fw={500}>Currency</Text>
              <Text>{viewLoan.currency}</Text>
            </Group>
            <Group justify="space-between">
              <Text fw={500}>Amount Range</Text>
              <Text>
                {formatAmount(viewLoan.min_amount, viewLoan.currency)} –{" "}
                {formatAmount(viewLoan.max_amount, viewLoan.currency)}
              </Text>
            </Group>
            <Group justify="space-between">
              <Text fw={500}>Term Range</Text>
              <Text>{viewLoan.min_term_months}–{viewLoan.max_term_months} months</Text>
            </Group>
            <Group justify="space-between">
              <Text fw={500}>Interest Rate</Text>
              <Text>{viewLoan.interest_rate_bps} bps</Text>
            </Group>
            <Group justify="space-between">
              <Text fw={500}>Interest Type</Text>
              <Text>{capitalize(viewLoan.interest_type)}</Text>
            </Group>
            <Group justify="space-between">
              <Text fw={500}>Status</Text>
              <Text>{capitalize(viewLoan.status)}</Text>
            </Group>
          </Stack>
        )}
      </Modal>
    </Stack>
  );
}
