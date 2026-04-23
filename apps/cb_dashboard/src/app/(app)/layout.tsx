"use client";

import { useEffect, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { AppShell, Center, Loader, Stack, Text } from "@mantine/core";
import { useAuth } from "@/lib/auth";
import { useNotify } from "@/lib/notify";
import { useRefresh } from "@/lib/refresh";
import { Sidebar } from "@/components/Sidebar";
import { Header } from "@/components/Header";
import { Alerts } from "@/components/Alerts";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const { state } = useAuth();
  const { clear } = useNotify();
  const { bump } = useRefresh();
  const lastPath = useRef<string | null>(null);
  const [activeTab, setActiveTab] = useState("banking");

  useEffect(() => {
    if (lastPath.current !== pathname) {
      lastPath.current = pathname;
      clear();
    }
  }, [pathname, clear]);

  useEffect(() => {
    if (state.status === "unauthenticated") {
      router.replace("/login");
    }
  }, [state.status, router]);

  if (state.status !== "authenticated") {
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

  return (
    <AppShell
      header={{ height: 95 }}
      navbar={{ width: 260, breakpoint: "sm" }}
      padding="lg"
    >
      <Header
        onRefresh={() => {
          bump();
          router.refresh();
        }}
        activeTab={activeTab}
        setActiveTab={setActiveTab}
      />
      <Sidebar activeTab={activeTab} />
      <AppShell.Main>
        <Alerts />
        {children}
      </AppShell.Main>
    </AppShell>
  );
}
