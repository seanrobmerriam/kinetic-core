"use client";

import { Badge, Box, Group, Paper, Text, Tooltip } from "@mantine/core";
import {
  IconAlertTriangle,
  IconCheck,
  IconCircleFilled,
  IconExclamationMark,
  type Icon,
} from "@/components/icons";
import type { SLOObjective } from "@/lib/types/operations";

interface SLOCardProps {
  objective: SLOObjective;
}

/**
 * Display a single SLO objective with status and metrics.
 */
export function SLOCard({ objective }: SLOCardProps) {
  const statusConfig = {
    healthy: {
      color: "green",
      icon: IconCheck,
      label: "Healthy",
    },
    breached: {
      color: "red",
      icon: IconExclamationMark,
      label: "Breached",
    },
    insufficient_data: {
      color: "gray",
      icon: IconAlertTriangle,
      label: "Insufficient Data",
    },
  };

  const config = statusConfig[objective.status as keyof typeof statusConfig];
  const Icon = config.icon;

  const content = (() => {
    const value = objective.value;
    
    if (objective.sli === "availability" && value.availability_pct !== undefined) {
      return (
        <Box>
          <Group gap="xs" mb="xs">
            <Text fw={500}>{objective.description}</Text>
          </Group>
          <Group justify="space-between">
            <Box>
              <Text size="xs" c="dimmed">Availability</Text>
              <Text fw={700} size="lg">{value.availability_pct.toFixed(2)}%</Text>
            </Box>
            <Box>
              <Text size="xs" c="dimmed">Target</Text>
              <Text fw={700} size="lg">{objective.target_pct}%</Text>
            </Box>
            <Box>
              <Text size="xs" c="dimmed">Requests</Text>
              <Text fw={700} size="lg">{value.total_requests}</Text>
            </Box>
          </Group>
        </Box>
      );
    }

    if (objective.sli === "dependency_health" && value.dependency_status !== undefined) {
      const depConfig = {
        ok: { color: "green", label: "Healthy" },
        degraded: { color: "yellow", label: "Degraded" },
        unhealthy: { color: "red", label: "Unhealthy" },
      };
      const depCfg = depConfig[value.dependency_status];
      
      return (
        <Box>
          <Group gap="xs" mb="xs">
            <Text fw={500}>{objective.description}</Text>
          </Group>
          <Group justify="space-between">
            <Badge color={depCfg.color} variant="light">
              {depCfg.label}
            </Badge>
            <Box>
              <Text size="xs" c="dimmed">Max Latency</Text>
              <Text fw={700} size="lg">{value.max_latency_ms}ms</Text>
            </Box>
          </Group>
          {value.checks && value.checks.length > 0 && (
            <Box mt="xs">
              <Text size="xs" fw={500} mb="xs">Checks:</Text>
              {value.checks.map((check) => (
                <Group gap="xs" key={check.name} mb="xs">
                  <IconCircleFilled size={8} color={check.status === "ok" ? "green" : "red"} />
                  <Text size="xs">{check.name}: {check.status === "ok" ? "OK" : "FAILED"} ({check.latency_ms}ms)</Text>
                </Group>
              ))}
            </Box>
          )}
        </Box>
      );
    }

    return (
      <Text fw={500}>{objective.description}</Text>
    );
  })();

  return (
    <Paper withBorder p="md" radius="md">
      <Group justify="space-between" mb="sm">
        <Group gap="sm">
          <Icon size={20} color={config.color} stroke={1.5} />
          <Badge color={config.color} variant="light">
            {config.label}
          </Badge>
        </Group>
      </Group>
      {content}
    </Paper>
  );
}
