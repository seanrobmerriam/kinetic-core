"use client";

import { type ReactNode, useMemo, useState } from "react";
import {
  Box,
  Center,
  Group,
  Pagination,
  Stack,
  Table,
  Text,
  TextInput,
  UnstyledButton,
} from "@mantine/core";
import {
  IconChevronDown,
  IconChevronUp,
  IconSearch,
  IconSelector,
} from "@/components/icons";
import classes from "./SortableTable.module.css";

export interface ColumnDef<T> {
  key: string;
  label: string;
  /** Set to false to disable sorting on this column (e.g. Actions). Default: true */
  sortable?: boolean;
  /** Return a primitive used for sorting and searching. Omit for purely rendered columns. */
  getValue?: (row: T) => string | number;
  /** Custom cell renderer. Falls back to getValue if omitted. */
  render?: (row: T) => ReactNode;
  ta?: "left" | "right" | "center";
  ff?: string;
  fw?: number;
  c?: string;
}

function Th({
  children,
  sorted,
  reversed,
  onSort,
}: {
  children: ReactNode;
  sorted: boolean;
  reversed: boolean;
  onSort: () => void;
}) {
  const Icon = sorted
    ? reversed
      ? IconChevronUp
      : IconChevronDown
    : IconSelector;
  return (
    <Table.Th className={classes.th}>
      <UnstyledButton onClick={onSort} className={classes.control}>
        <Group justify="space-between" wrap="nowrap">
          <Text fw={500} fz="sm">
            {children}
          </Text>
          <Center className={classes.icon}>
            <Icon size={16} stroke={1.5} />
          </Center>
        </Group>
      </UnstyledButton>
    </Table.Th>
  );
}

export function SortableTable<T>({
  data,
  columns,
  rowKey,
  searchPlaceholder = "Search...",
  emptyMessage = "No items found",
  minWidth = 700,
  pageSize = 50,
  searchValue,
  onSearchChange,
}: {
  data: T[];
  columns: ColumnDef<T>[];
  rowKey: (row: T) => string;
  searchPlaceholder?: string;
  emptyMessage?: string;
  minWidth?: number;
  /** Rows per page. Pagination renders only when total filtered rows exceed this. Default: 50 */
  pageSize?: number;
  searchValue?: string;
  onSearchChange?: (v: string) => void;
}) {
  const isControlled = onSearchChange !== undefined;
  const [internalSearch, setInternalSearch] = useState("");
  const search = isControlled ? (searchValue ?? "") : internalSearch;
  const [sortBy, setSortBy] = useState<string | null>(null);
  const [reversed, setReversed] = useState(false);
  const [page, setPage] = useState(1);

  // Reset page to 1 when filters or sort change (setState-during-render pattern —
  // avoids the cascading-render lint error that useEffect-setState would trigger).
  const [prevFilterKey, setPrevFilterKey] = useState(
    () => `${search}|${sortBy}|${reversed}`,
  );
  const filterKey = `${search}|${sortBy}|${reversed}`;
  if (filterKey !== prevFilterKey) {
    setPrevFilterKey(filterKey);
    setPage(1);
  }

  const setSorting = (key: string) => {
    setReversed(sortBy === key ? !reversed : false);
    setSortBy(key);
  };

  const processed = useMemo(() => {
    let rows = [...data];

    if (search) {
      const q = search.toLowerCase();
      rows = rows.filter((row) =>
        columns.some(
          (col) =>
            col.getValue !== undefined &&
            String(col.getValue(row)).toLowerCase().includes(q),
        ),
      );
    }

    if (sortBy) {
      const col = columns.find((c) => c.key === sortBy);
      if (col?.getValue) {
        const fn = col.getValue;
        rows.sort((a, b) => {
          const av = fn(a);
          const bv = fn(b);
          const cmp =
            typeof av === "number" && typeof bv === "number"
              ? av - bv
              : String(av).localeCompare(String(bv));
          return reversed ? -cmp : cmp;
        });
      }
    }

    return rows;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data, search, sortBy, reversed]);

  const totalPages = Math.max(1, Math.ceil(processed.length / pageSize));
  const safePage = Math.min(page, totalPages);
  const pageSlice = processed.slice(
    (safePage - 1) * pageSize,
    safePage * pageSize,
  );
  const showPagination = processed.length > pageSize;

  return (
    <>
      {!isControlled && (
        <Box px="md" pt="md">
          <TextInput
            leftSection={<IconSearch size={16} stroke={1.5} />}
            placeholder={searchPlaceholder}
            value={internalSearch}
            onChange={(e) => setInternalSearch(e.currentTarget.value)}
            maw={400}
          />
        </Box>
      )}
      <Table.ScrollContainer minWidth={minWidth}>
        <Table verticalSpacing="sm" highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              {columns.map((col) =>
                col.sortable === false ? (
                  <Table.Th key={col.key} ta={col.ta}>
                    {col.label}
                  </Table.Th>
                ) : (
                  <Th
                    key={col.key}
                    sorted={sortBy === col.key}
                    reversed={reversed}
                    onSort={() => setSorting(col.key)}
                  >
                    {col.label}
                  </Th>
                ),
              )}
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {processed.length === 0 ? (
              <Table.Tr>
                <Table.Td
                  colSpan={columns.length}
                  ta="center"
                  py="xl"
                  c="dimmed"
                >
                  {emptyMessage}
                </Table.Td>
              </Table.Tr>
            ) : (
              pageSlice.map((row) => (
                <Table.Tr key={rowKey(row)}>
                  {columns.map((col) => (
                    <Table.Td
                      key={col.key}
                      ta={col.ta}
                      ff={col.ff}
                      fw={col.fw}
                      c={col.c}
                    >
                      {col.render
                        ? col.render(row)
                        : col.getValue !== undefined
                          ? col.getValue(row)
                          : null}
                    </Table.Td>
                  ))}
                </Table.Tr>
              ))
            )}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
      {showPagination && (
        <Stack align="center" pb="md">
          <Text size="xs" c="dimmed">
            {(safePage - 1) * pageSize + 1}–
            {Math.min(safePage * pageSize, processed.length)} of{" "}
            {processed.length}
          </Text>
          <Pagination
            total={totalPages}
            value={safePage}
            onChange={setPage}
            size="sm"
            withEdges
          />
        </Stack>
      )}
    </>
  );
}
