"use client";

import { useState } from "react";
import {
  Card,
  Grid,
  Group,
  Paper,
  Select,
  Stack,
  Text,
  Title,
  Button,
  Progress,
  Alert,
} from "@mantine/core";
import { IconDownload, IconAlertCircle } from "@/components/icons";
import { exportResource } from "@/lib/api";
import { useNotify } from "@/lib/notify";

const RESOURCES = [
  { value: "parties", label: "Customers / Parties", description: "All party records with status and contact info" },
  { value: "accounts", label: "Accounts", description: "All account records with balances and status" },
  { value: "transactions", label: "Transactions", description: "All transaction records in the system" },
  { value: "ledger", label: "Ledger Entries", description: "All ledger postings with running balances" },
  { value: "events", label: "Domain Events", description: "All domain events for audit trail" },
];

export default function ExportsPage() {
  const { setError, setSuccess } = useNotify();
  const [selected, setSelected] = useState<string | null>(null);
  const [downloading, setDownloading] = useState(false);
  const [lastDownload, setLastDownload] = useState<{ resource: string; ts: number } | null>(null);

  const handleDownload = async () => {
    if (!selected) return;
    setDownloading(true);
    try {
      const blob = await exportResource(selected as "parties" | "accounts" | "transactions" | "ledger" | "events");
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `${selected}.csv`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      setLastDownload({ resource: selected, ts: Date.now() });
      setSuccess(`Export complete: ${selected}.csv`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Export failed";
      setError(msg);
    } finally {
      setDownloading(false);
    }
  };

  return (
    <Stack gap="lg">
      <div>
        <Title order={2}>Bulk Exports</Title>
        <Text c="dimmed" size="sm">
          Download system data as CSV files. Exports include all records.
        </Text>
      </div>

      <Alert icon={<IconAlertCircle size={16} />} color="blue" variant="light">
        Exports are generated on-demand. For large datasets this may take a moment.
      </Alert>

      <Grid>
        {RESOURCES.map((r) => (
          <Grid.Col key={r.value} span={{ base: 12, sm: 6, md: 4 }}>
            <Paper
              withBorder
              p="md"
              radius="md"
              onClick={() => setSelected(r.value)}
              style={{
                cursor: "pointer",
                borderColor: selected === r.value ? "var(--mantine-color-blue-5)" : undefined,
                background: selected === r.value ? "var(--mantine-color-blue-0)" : undefined,
              }}
            >
              <Group justify="space-between" mb="xs">
                <Text fw={600}>{r.label}</Text>
                {selected === r.value && (
                  <IconDownload size={16} style={{ color: "var(--mantine-color-blue-5)" }} />
                )}
              </Group>
              <Text size="xs" c="dimmed">
                {r.description}
              </Text>
            </Paper>
          </Grid.Col>
        ))}
      </Grid>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Group>
          <Select
            label="Resource"
            placeholder="Select a resource to export"
            data={RESOURCES.map((r) => ({ value: r.value, label: r.label }))}
            value={selected}
            onChange={(v) => setSelected(v)}
            style={{ minWidth: 240 }}
          />
          <div style={{ paddingTop: 24 }}>
            <Button
              leftSection={<IconDownload size={16} />}
              onClick={handleDownload}
              disabled={!selected || downloading}
              loading={downloading}
            >
              Download CSV
            </Button>
          </div>
        </Group>
        {downloading && (
          <Progress value={100} animated mt="md" label="Generating export…" color="blue" />
        )}
        {lastDownload && !downloading && (
          <Text size="xs" c="dimmed" mt="sm">
            Last export: {lastDownload.resource}.csv
          </Text>
        )}
      </Card>
    </Stack>
  );
}