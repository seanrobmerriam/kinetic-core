"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import {
  ActionIcon,
  AppShell,
  Avatar,
  Box,
  Group,
  Tabs,
  Text,
  Title,
  Tooltip,
} from "@mantine/core";
import {
  IconAt,
  IconLogout,
  IconMoon,
  IconRefresh,
  IconSun,
  IconUpload,
} from "@/components/icons";
import { useAuth } from "@/lib/auth";
import { useNotify } from "@/lib/notify";
import { useTheme } from "@/lib/theme";
import { api } from "@/lib/api";
import { capitalize } from "@/lib/format";

export function Header({
  onRefresh,
  activeTab,
  setActiveTab,
}: {
  onRefresh?: () => void;
  activeTab: string;
  setActiveTab: (tab: string) => void;
}) {
  const router = useRouter();
  const { state, logout, devToolsEnabled, setDevToolsEnabled } = useAuth();
  const { theme, toggle } = useTheme();
  const { setError, setSuccess } = useNotify();
  const [mockImporting, setMockImporting] = useState(false);

  useEffect(() => {
    if (state.status !== "authenticated") return;
    let cancelled = false;
    (async () => {
      try {
        const result = await api<{ enabled: boolean }>("GET", "/dev/mock-import");
        if (!cancelled) setDevToolsEnabled(Boolean(result?.enabled));
      } catch {
        if (!cancelled) setDevToolsEnabled(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [state.status, setDevToolsEnabled]);

  const importMock = async () => {
    if (mockImporting || !devToolsEnabled) return;
    setMockImporting(true);
    try {
      const resp = await api<{ summary: Record<string, number> }>(
        "POST",
        "/dev/mock-import",
        {},
      );
      const created = resp?.summary?.transactions_created ?? 0;
      const existing = resp?.summary?.transactions_existing ?? 0;
      setSuccess(
        `Mock data imported (transactions created: ${created}, existing: ${existing})`,
      );
      onRefresh?.();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setMockImporting(false);
    }
  };

  const refresh = () => {
    if (onRefresh) onRefresh();
    else router.refresh();
  };

  const userInitial =
    state.status === "authenticated" && state.user
      ? state.user.email.charAt(0).toUpperCase()
      : "?";

  return (
    <AppShell.Header style={{ display: "flex", flexDirection: "column" }}>
      <Group flex={1} px="lg" justify="space-between" wrap="nowrap">
        <div>
          <Title order={3} fw={600}>
            Kinetic Core
          </Title>
          <Text size="xs" c="dimmed" tt="uppercase" fw={600}>
            Banking Solution
          </Text>
        </div>

        <Group gap="xs" wrap="nowrap">
          {devToolsEnabled && (
            <Tooltip label="Import mock data">
              <ActionIcon
                variant="default"
                size="lg"
                data-testid="mock-import-button"
                onClick={importMock}
                disabled={mockImporting}
                loading={mockImporting}
              >
                <IconUpload size={18} />
              </ActionIcon>
            </Tooltip>
          )}

          <Tooltip label="Toggle theme">
            <ActionIcon
              variant="default"
              size="lg"
              data-testid="theme-toggle"
              onClick={toggle}
            >
              {theme === "dark" ? <IconSun size={18} /> : <IconMoon size={18} />}
            </ActionIcon>
          </Tooltip>

          <Tooltip label="Refresh">
            <ActionIcon variant="default" size="lg" onClick={refresh}>
              <IconRefresh size={18} />
            </ActionIcon>
          </Tooltip>

          <Tooltip label="Sign out">
            <ActionIcon
              variant="default"
              size="lg"
              data-testid="logout-button"
              onClick={() => void logout()}
            >
              <IconLogout size={18} />
            </ActionIcon>
          </Tooltip>

          {state.status === "authenticated" && state.user && (
            <Group
              gap="md"
              data-testid="current-user"
              wrap="nowrap"
              visibleFrom="sm"
              style={{
                borderLeft:
                  "1px solid light-dark(var(--mantine-color-gray-3), var(--mantine-color-dark-4))",
                paddingLeft: "var(--mantine-spacing-md)",
              }}
            >
              <Avatar
                color="indigo"
                radius="md"
                size={46}
                variant="gradient"
                gradient={{ from: "indigo", to: "violet" }}
              >
                {userInitial}
              </Avatar>
              <div>
                <Text size="sm" fw={600} lh={1.3}>
                  {state.user.email}
                </Text>
                <Group gap={4} align="center" wrap="nowrap" mt={2}>
                  <IconAt size={12} stroke={1.5} style={{ color: "var(--mantine-color-dimmed)" }} />
                  <Text size="xs" c="dimmed">
                    {capitalize(state.user.role)}
                  </Text>
                </Group>
              </div>
            </Group>
          )}
        </Group>
      </Group>

      {/* Banking / Admin tab strip at bottom of header */}
      <Box px="lg" pb={0}>
        <Tabs
          value={activeTab}
          onChange={(v) => setActiveTab(v ?? "banking")}
          variant="default"
        >
          <Tabs.List>
            <Tabs.Tab value="banking" fw={500}>
              Banking
            </Tabs.Tab>
            <Tabs.Tab value="admin" fw={500}>
              Admin
            </Tabs.Tab>
          </Tabs.List>
        </Tabs>
      </Box>
    </AppShell.Header>
  );
}
