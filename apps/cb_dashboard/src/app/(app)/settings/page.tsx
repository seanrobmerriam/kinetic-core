"use client";

import { useEffect, useState } from "react";
import { Card, Code, Group, Stack, Text, Title } from "@mantine/core";
import { getApiBase } from "@/lib/api";

export default function SettingsPage() {
  const [endpoint, setEndpoint] = useState("");

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setEndpoint(getApiBase());
  }, []);

  return (
    <Stack gap="lg" maw={700}>
      <Title order={3}>Settings</Title>

      <Card withBorder shadow="sm" radius="md" padding="lg">
        <Stack gap="lg">
          <Group justify="space-between" align="flex-start">
            <div>
              <Title order={5}>API Endpoint</Title>
              <Text size="sm" c="dimmed">
                The backend API URL
              </Text>
            </div>
            <Code>{endpoint}</Code>
          </Group>
          <Group justify="space-between" align="flex-start">
            <div>
              <Title order={5}>Application Version</Title>
              <Text size="sm" c="dimmed">
                Current dashboard version
              </Text>
            </div>
            <Text>1.0.0</Text>
          </Group>
        </Stack>
      </Card>
    </Stack>
  );
}
