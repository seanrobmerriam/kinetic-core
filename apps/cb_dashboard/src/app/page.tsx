"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { Center, Loader, Stack, Text } from "@mantine/core";
import { useAuth } from "@/lib/auth";

export default function Home() {
  const router = useRouter();
  const { state } = useAuth();

  useEffect(() => {
    if (state.status === "authenticated") {
      router.replace("/dashboard");
    } else if (state.status === "unauthenticated") {
      router.replace("/login");
    }
  }, [state.status, router]);

  return (
    <Center mih="100vh">
      <Stack align="center" gap="sm" data-testid="loading">
        <Loader />
        <Text size="sm" c="dimmed">
          Loading…
        </Text>
      </Stack>
    </Center>
  );
}
