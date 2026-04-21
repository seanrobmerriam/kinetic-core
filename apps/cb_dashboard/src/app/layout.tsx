import type { Metadata } from "next";
import { Manrope } from "next/font/google";
import { ColorSchemeScript, MantineProvider, mantineHtmlProps } from "@mantine/core";
import { Notifications } from "@mantine/notifications";
import "@mantine/core/styles.css";
import "@mantine/notifications/styles.css";
import { Providers } from "./providers";
import { theme } from "./theme";

const manrope = Manrope({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-sans-display",
  weight: ["400", "500", "600", "700", "800"],
});

export const metadata: Metadata = {
  title: "IronLedger Dashboard",
  description: "Core banking operations dashboard",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={manrope.variable} {...mantineHtmlProps}>
      <head>
        <ColorSchemeScript defaultColorScheme="auto" />
      </head>
      <body>
        <MantineProvider theme={theme} defaultColorScheme="auto">
          <Notifications position="top-right" />
          <Providers>{children}</Providers>
        </MantineProvider>
      </body>
    </html>
  );
}
