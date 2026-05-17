"use client";

import { Badge, Group, Paper, Stack, Text } from "@mantine/core";
import {
  IconAlertTriangle,
  IconAlertOctagon,
  IconCheck,
  IconInfoCircle,
  type Icon,
} from "@/components/icons";
import type { SLOAlert } from "@/lib/types/operations";

interface AlertItemProps {
  alert: SLOAlert;
}

/**
 * Display a single alert with severity and state indicators.
 */
export function AlertItem({ alert }: AlertItemProps) {
  const severityConfig = {
    info: {
      color: "blue",
      icon: IconInfoCircle,
      label: "Info",
    },
    warning: {
      color: "yellow",
      icon: IconAlertTriangle,
      label: "Warning",
    },
    critical: {
      color: "red",
      icon: IconAlertOctagon,
      label: "Critical",
    },
  };

  const stateConfig = {
    firing: { label: "Firing", variant: "filled" as const },
    resolved: { label: "Resolved", variant: "light" as const },
    monitoring: { label: "Monitoring", variant: "light" as const },
  };

  const sConfig = severityConfig[alert.severity];
  const stConfig = stateConfig[alert.state];
  const Icon = sConfig.icon;

  return (
    <Paper withBorder p="md" radius="md">
      <Group justify="space-between" mb="sm">
        <Group gap="sm">
          <Icon size={20} color={sConfig.color} stroke={1.5} />
          <Badge color={sConfig.color} variant="light">
            {sConfig.label}
          </Badge>
          <Badge color="gray" variant={stConfig.variant}>
            {stConfig.label}
          </Badge>
        </Group>
      </Group>
      <Stack gap="xs">
        <Text fw={500} size="sm">
          {alert.objective}
        </Text>
        <Text size="sm" c="dimmed">
          {alert.message}
        </Text>
      </Stack>
    </Paper>
  );
}

interface AlertsListProps {
  alerts: SLOAlert[];
}

/**
 * Display all alerts grouped by state.
 */
export function AlertsList({ alerts }: AlertsListProps) {
  if (alerts.length === 0) {
    return (
      <Paper withBorder p="md" radius="md">
        <Group gap="sm">
          <IconCheck size={20} color="green" stroke={1.5} />
          <Text fw={500}>All systems operational</Text>
        </Group>
      </Paper>
    );
  }

  const firingAlerts = alerts.filter((a) => a.state === "firing");
  const resolvedAlerts = alerts.filter((a) => a.state === "resolved");
  const monitoringAlerts = alerts.filter((a) => a.state === "monitoring");

  return (
    <Stack gap="md">
      {firingAlerts.length > 0 && (
        <Stack gap="sm">
          <Text fw={600} size="sm" c="red">
            Active Alerts ({firingAlerts.length})
          </Text>
          {firingAlerts.map((alert) => (
            <AlertItem key={alert.alert_id} alert={alert} />
          ))}
        </Stack>
      )}
      {monitoringAlerts.length > 0 && (
        <Stack gap="sm">
          <Text fw={600} size="sm" c="gray">
            Monitoring ({monitoringAlerts.length})
          </Text>
          {monitoringAlerts.map((alert) => (
            <AlertItem key={alert.alert_id} alert={alert} />
          ))}
        </Stack>
      )}
      {resolvedAlerts.length > 0 && (
        <Stack gap="sm">
          <Text fw={600} size="sm" c="green">
            Resolved ({resolvedAlerts.length})
          </Text>
          {resolvedAlerts.map((alert) => (
            <AlertItem key={alert.alert_id} alert={alert} />
          ))}
        </Stack>
      )}
    </Stack>
  );
}
