"use client";

import { Alert, Loader, Group, Text } from "@mantine/core";
import { IconAlertCircle, IconCheck } from "@tabler/icons-react";
import { useNotify } from "@/lib/notify";

export function Alerts() {
  const { error, success } = useNotify();
  return (
    <>
      {error && (
        <Alert
          mb="md"
          color="red"
          icon={<IconAlertCircle size={18} />}
          data-testid="error-banner"
          variant="light"
          radius="md"
        >
          {error}
        </Alert>
      )}
      {success && (
        <Alert
          mb="md"
          color="green"
          icon={<IconCheck size={18} />}
          data-testid="success-banner"
          variant="light"
          radius="md"
        >
          {success}
        </Alert>
      )}
    </>
  );
}

export function Loading({ label = "Loading..." }: { label?: string }) {
  return (
    <Group gap="sm" data-testid="loading">
      <Loader size="sm" />
      <Text size="sm" c="dimmed">
        {label}
      </Text>
    </Group>
  );
}
