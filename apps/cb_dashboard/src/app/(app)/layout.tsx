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
  const { state, hasAnyPermission, hasPermission } = useAuth();
  const { clear } = useNotify();
  const { bump } = useRefresh();
  const lastPath = useRef<string | null>(null);
  const [activeTab, setActiveTab] = useState("banking");

  const canAccessAdmin = hasAnyPermission([
    "user.read",
    "user.write",
    "role.read",
    "role.write",
    "permission.read",
  ]);

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

  useEffect(() => {
    if (state.status !== "authenticated") return;

    const routeRequirements: Array<{ prefix: string; permission: string }> = [
      { prefix: "/users", permission: "user.read" },
      { prefix: "/roles", permission: "role.read" },
      { prefix: "/permissions", permission: "permission.read" },
    ];

    const matched = routeRequirements.find((entry) =>
      pathname === entry.prefix || pathname.startsWith(`${entry.prefix}/`),
    );

    if (matched && !hasPermission(matched.permission)) {
      router.replace("/dashboard");
    }
  }, [state.status, pathname, hasPermission, router]);

  useEffect(() => {
    const isAdminRoute =
      pathname === "/users" ||
      pathname.startsWith("/users/") ||
      pathname === "/roles" ||
      pathname.startsWith("/roles/") ||
      pathname === "/permissions" ||
      pathname.startsWith("/permissions/");

    if (isAdminRoute && canAccessAdmin) {
      setActiveTab("admin");
      return;
    }

    if (!canAccessAdmin) {
      setActiveTab("banking");
    }
  }, [pathname, canAccessAdmin]);

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
        canAccessAdmin={canAccessAdmin}
      />
      <Sidebar activeTab={activeTab} />
      <AppShell.Main>
        <Alerts />
        {children}
      </AppShell.Main>
    </AppShell>
  );
}
