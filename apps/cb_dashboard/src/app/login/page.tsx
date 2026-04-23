"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Alert,
  Button,
  Center,
  Container,
  Loader,
  Paper,
  PasswordInput,
  Stack,
  Text,
  TextInput,
  ThemeIcon,
  Title,
  Group,
} from "@mantine/core";
import { IconAlertCircle, IconBuildingBank } from "@/components/icons";
import { useAuth } from "@/lib/auth";

export default function LoginPage() {
  const router = useRouter();
  const { state, login } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  useEffect(() => {
    if (state.status === "authenticated") {
      router.replace("/dashboard");
    }
  }, [state.status, router]);

  const submit = (e: FormEvent) => {
    e.preventDefault();
    void login(email, password);
  };

  const loading = state.status === "loading";

  return (
    <Center mih="100vh" px="md">
      <Container size={420} w="100%">
        <Stack align="center" gap="xs" mb="xl">
          <ThemeIcon
            size={56}
            radius="lg"
            variant="gradient"
            gradient={{ from: "indigo", to: "violet" }}
          >
            <IconBuildingBank size={32} />
          </ThemeIcon>
          <Title order={2} ta="center">
            IronLedger Dashboard
          </Title>
          <Text c="dimmed" ta="center" size="sm">
            Modern core banking operations with real-time visibility and
            controls.
          </Text>
        </Stack>

        <Paper
          withBorder
          shadow="sm"
          p="xl"
          radius="md"
          data-testid="login-form"
        >
          <form onSubmit={submit}>
            <Stack>
              {state.error && (
                <Alert
                  color="red"
                  icon={<IconAlertCircle size={18} />}
                  data-testid="error-banner"
                  variant="light"
                >
                  {state.error}
                </Alert>
              )}
              {loading && (
                <Group gap="sm" data-testid="loading">
                  <Loader size="sm" />
                  <Text size="sm" c="dimmed">
                    Signing in…
                  </Text>
                </Group>
              )}
              <TextInput
                id="login-email"
                label="Email"
                placeholder="admin@example.com"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.currentTarget.value)}
                required
              />
              <PasswordInput
                id="login-password"
                label="Password"
                value={password}
                onChange={(e) => setPassword(e.currentTarget.value)}
                required
              />
              <Button
                id="login-submit"
                type="submit"
                fullWidth
                disabled={loading}
                loading={loading}
              >
                Sign In
              </Button>
            </Stack>
          </form>
        </Paper>
      </Container>
    </Center>
  );
}
