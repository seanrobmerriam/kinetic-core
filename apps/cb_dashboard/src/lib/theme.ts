"use client";

import { useSyncExternalStore } from "react";
import { useMantineColorScheme } from "@mantine/core";

function subscribe(callback: () => void): () => void {
  if (typeof window === "undefined") return () => {};
  const mq = window.matchMedia("(prefers-color-scheme: dark)");
  mq.addEventListener("change", callback);
  return () => mq.removeEventListener("change", callback);
}

function getSnapshot(): "light" | "dark" {
  if (typeof window === "undefined") return "light";
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

function getServerSnapshot(): "light" | "dark" {
  return "light";
}

export function useTheme(): { theme: "light" | "dark"; toggle: () => void } {
  const { colorScheme, setColorScheme } = useMantineColorScheme();
  const systemScheme = useSyncExternalStore(
    subscribe,
    getSnapshot,
    getServerSnapshot,
  );
  const resolved: "light" | "dark" =
    colorScheme === "auto" ? systemScheme : colorScheme;

  const toggle = () => {
    setColorScheme(resolved === "dark" ? "light" : "dark");
  };

  return { theme: resolved, toggle };
}
