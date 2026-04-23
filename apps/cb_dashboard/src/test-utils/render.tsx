import type { ReactElement, ReactNode } from "react";
import { render, type RenderOptions, type RenderResult } from "@testing-library/react";
import { MantineProvider } from "@mantine/core";
import { NotifyProvider } from "@/lib/notify";
import { RefreshProvider } from "@/lib/refresh";

function AppProviders({ children }: { children: ReactNode }) {
  return (
    <MantineProvider>
      <NotifyProvider>
        <RefreshProvider>{children}</RefreshProvider>
      </NotifyProvider>
    </MantineProvider>
  );
}

export function renderWithProviders(
  ui: ReactElement,
  options?: Omit<RenderOptions, "wrapper">,
): RenderResult {
  return render(ui, { wrapper: AppProviders, ...options });
}

export * from "@testing-library/react";
