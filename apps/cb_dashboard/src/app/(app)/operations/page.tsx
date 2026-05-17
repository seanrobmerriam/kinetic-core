"use client";

import { useEffect, useState } from "react";
import {
  Box,
  Button,
  Card,
  Center,
  Group,
  Loader,
  SimpleGrid,
  Stack,
  Text,
  Title,
} from "@mantine/core";
import { IconRefresh } from "@/components/icons";
import { pollSLOSnapshot } from "@/lib/api/operations";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { SLOCard } from "@/components/SLOCard";
import { AlertsList } from "@/components/AlertItem";
import type { SLOSnapshot } from "@/lib/types/operations";

export default function OperationsPage() {
  const [snapshot, setSnapshot] = useState<SLOSnapshot | null>(null);
  const [loading, setLoading] = useState(true);
  const { setError } = useNotify();
  const { tick } = useRefresh();

  const fetchSnapshot = async () => {
    setLoading(true);
    try {
      const data = await pollSLOSnapshot();
      if (data) {
        setSnapshot(data);
      } else {
        setError("Unable to fetch operations snapshot");
      }
    } catch (error) {
      setError(error instanceof Error ? error.message : "Unknown error");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchSnapshot();
    const interval = setInterval(fetchSnapshot, 10000); // Refresh every 10 seconds
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    fetchSnapshot();
  }, [tick]);

  if (loading && !snapshot) {
    return (
      <Center style={{ height: "100vh" }}>
        <Loader />
      </Center>
    );
  }

  if (!snapshot) {
    return (
      <Box p="md">
        <Stack gap="md">
          <Title>Operations Dashboard</Title>
          <Card withBorder>
            <Text c="red">Unable to load operations data</Text>
            <Button onClick={fetchSnapshot} mt="md">
              Retry
            </Button>
          </Card>
        </Stack>
      </Box>
    );
  }

  const healthyCount = snapshot.objectives.filter((o) => o.status === "healthy").length;
  const breachedCount = snapshot.objectives.filter((o) => o.status === "breached").length;
  const dataCount = snapshot.objectives.filter((o) => o.status === "insufficient_data").length;

  const firingAlerts = snapshot.alerts.filter((a) => a.state === "firing");

  return (
    <Box p="md">
      <Stack gap="lg">
        <Group justify="space-between" align="flex-end">
          <div>
            <Title>Operations Dashboard</Title>
            <Text size="sm" c="dimmed">
              Real-time service health and SLO indicators
            </Text>
          </div>
          <Button
            leftSection={<IconRefresh size={16} />}
            onClick={fetchSnapshot}
            loading={loading}
            variant="light"
          >
            Refresh
          </Button>
        </Group>

        {/* Health Summary */}
        <SimpleGrid cols={{ base: 1, sm: 4 }} spacing="md">
          <Card withBorder radius="md" padding="md">
            <Stack gap="xs">
              <Text size="sm" fw={500} c="dimmed">
                Healthy Objectives
              </Text>
              <Text fw={700} size="xl">
                {healthyCount}/{snapshot.objectives.length}
              </Text>
            </Stack>
          </Card>
          <Card withBorder radius="md" padding="md">
            <Stack gap="xs">
              <Text size="sm" fw={500} c="dimmed">
                Breached
              </Text>
              <Text fw={700} size="xl" c={breachedCount > 0 ? "red" : "green"}>
                {breachedCount}
              </Text>
            </Stack>
          </Card>
          <Card withBorder radius="md" padding="md">
            <Stack gap="xs">
              <Text size="sm" fw={500} c="dimmed">
                Insufficient Data
              </Text>
              <Text fw={700} size="xl" c={dataCount > 0 ? "yellow" : "green"}>
                {dataCount}
              </Text>
            </Stack>
          </Card>
          <Card withBorder radius="md" padding="md">
            <Stack gap="xs">
              <Text size="sm" fw={500} c="dimmed">
                Active Alerts
              </Text>
              <Text fw={700} size="xl" c={firingAlerts.length > 0 ? "red" : "green"}>
                {firingAlerts.length}
              </Text>
            </Stack>
          </Card>
        </SimpleGrid>

        {/* Last Updated */}
        <Text size="xs" c="dimmed">
          Last updated: {new Date(snapshot.generated_at_ms).toLocaleTimeString()}
        </Text>

        {/* SLO Objectives */}
        <div>
          <Title order={2} size="h3" mb="md">
            Service Level Objectives
          </Title>
          <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
            {snapshot.objectives.map((objective) => (
              <SLOCard key={objective.id} objective={objective} />
            ))}
          </SimpleGrid>
        </div>

        {/* Alerts */}
        <div>
          <Title order={2} size="h3" mb="md">
            Alerts & Status
          </Title>
          <AlertsList alerts={snapshot.alerts} />
        </div>
      </Stack>
    </Box>
  );
}
