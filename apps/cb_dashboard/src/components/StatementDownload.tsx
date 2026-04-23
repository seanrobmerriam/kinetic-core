"use client";

import { useState } from "react";
import {
  Button,
  Group,
  Popover,
  Select,
  Stack,
  Text,
  TextInput,
  Tooltip,
} from "@mantine/core";
import { IconDownload } from "@/components/icons";
import { api, ApiError } from "@/lib/api";
import { useNotify } from "@/lib/notify";
import {
  buildStatementPath,
  csvFilename,
  defaultRange,
  entriesToCsv,
  validateRange,
  type DateRange,
  type StatementResponse,
} from "@/lib/statement";

const PAGE_SIZE = 200;
const MAX_PAGES = 50; // hard ceiling — 10k entries per export

interface Props {
  accountId: string;
  accountName: string;
  triggerDownload?: (blob: Blob, filename: string) => void;
}

function browserTriggerDownload(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

export function StatementDownload({
  accountId,
  accountName,
  triggerDownload = browserTriggerDownload,
}: Props) {
  const { setError, setSuccess } = useNotify();
  const [opened, setOpened] = useState(false);
  const [range, setRange] = useState<DateRange>(() => defaultRange());
  const [format, setFormat] = useState<"csv" | "pdf">("csv");
  const [downloading, setDownloading] = useState(false);

  const rangeError = validateRange(range);
  const errorMessage =
    rangeError === "missing-from"
      ? "Pick a start date."
      : rangeError === "missing-to"
        ? "Pick an end date."
        : rangeError === "from-after-to"
          ? "Start date must be on or before end date."
          : null;
  const canDownload = !rangeError && !downloading && format === "csv";

  const handleDownload = async () => {
    if (rangeError) return;
    setDownloading(true);
    try {
      const all = [];
      let page = 1;
      let meta: StatementResponse | null = null;
      while (page <= MAX_PAGES) {
        const path = buildStatementPath(accountId, range, page, PAGE_SIZE);
        const resp = await api<StatementResponse>("GET", path);
        if (!meta) meta = resp;
        all.push(...resp.entries);
        if (resp.entries.length < PAGE_SIZE) break;
        page += 1;
      }
      const csv = entriesToCsv(all, {
        account_name: accountName,
        opening_balance: meta?.opening_balance,
        closing_balance: meta?.closing_balance,
        currency: meta?.currency,
      });
      const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
      triggerDownload(blob, csvFilename(accountName, range));
      setSuccess(`Statement exported (${all.length} entries).`);
      setOpened(false);
    } catch (err) {
      const msg =
        err instanceof ApiError
          ? `Statement download failed: ${err.message}`
          : `Statement download failed: ${(err as Error).message}`;
      setError(msg);
    } finally {
      setDownloading(false);
    }
  };

  return (
    <Popover
      opened={opened}
      onChange={setOpened}
      position="bottom-end"
      withArrow
      shadow="md"
      width={320}
    >
      <Popover.Target>
        <Button
          variant="default"
          size="sm"
          leftSection={<IconDownload size={16} />}
          onClick={() => setOpened((v) => !v)}
          aria-haspopup="dialog"
          aria-expanded={opened}
        >
          Download statement
        </Button>
      </Popover.Target>
      <Popover.Dropdown>
        <Stack gap="sm">
          <Text fw={600} size="sm">
            Download statement
          </Text>
          <TextInput
            type="date"
            label="From"
            value={range.from}
            onChange={(e) => setRange((r) => ({ ...r, from: e.currentTarget.value }))}
            data-testid="statement-from"
          />
          <TextInput
            type="date"
            label="To"
            value={range.to}
            onChange={(e) => setRange((r) => ({ ...r, to: e.currentTarget.value }))}
            data-testid="statement-to"
          />
          <Tooltip
            label="PDF export coming soon — choose CSV for now."
            disabled={format === "csv"}
            withArrow
          >
            <Select
              label="Format"
              value={format}
              onChange={(v) => setFormat((v as "csv" | "pdf") || "csv")}
              data={[
                { value: "csv", label: "CSV" },
                { value: "pdf", label: "PDF (coming soon)", disabled: true },
              ]}
              allowDeselect={false}
            />
          </Tooltip>
          {errorMessage && (
            <Text size="xs" c="red" role="alert">
              {errorMessage}
            </Text>
          )}
          <Group justify="flex-end" gap="xs">
            <Button variant="subtle" size="xs" onClick={() => setOpened(false)}>
              Cancel
            </Button>
            <Button
              size="xs"
              onClick={handleDownload}
              disabled={!canDownload}
              loading={downloading}
              data-testid="statement-submit"
            >
              Download
            </Button>
          </Group>
        </Stack>
      </Popover.Dropdown>
    </Popover>
  );
}
