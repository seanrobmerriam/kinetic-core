"use client";

import { createTheme, DEFAULT_THEME, mergeMantineTheme } from "@mantine/core";

const themeOverride = createTheme({
  primaryColor: "indigo",
  defaultRadius: "md",
  fontFamily:
    "var(--font-sans-display), -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
  headings: {
    fontFamily:
      "var(--font-sans-display), -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
    fontWeight: "600",
  },
  cursorType: "pointer",
});

export const theme = mergeMantineTheme(DEFAULT_THEME, themeOverride);
