import type { Metadata } from "next";
import { Manrope } from "next/font/google";
import { ColorSchemeScript, MantineProvider, mantineHtmlProps } from "@mantine/core";
import { Notifications } from "@mantine/notifications";
import "@mantine/core/styles.css";
import "@mantine/notifications/styles.css";
import "./rtl.css";
import { Providers } from "./providers";
import { theme } from "./theme";
import { getDir } from "../lib/locale";

const manrope = Manrope({
  subsets: ["latin", "latin-ext"],
  display: "swap",
  variable: "--font-sans-display",
  weight: ["400", "500", "600", "700", "800"],
});

export const metadata: Metadata = {
  title: "IronLedger Dashboard",
  description: "Core banking operations dashboard",
};

/**
 * Resolve the locale from the request context.
 * Falls back to "en-US" when the Accept-Language header is absent.
 */
function resolveLocale(): string {
  // In Next.js App Router, locale resolution happens server-side via
  // next-intl or middleware. For the MVP we use a static default; the
  // `dir` attribute is kept in the layout so RTL CSS takes effect.
  return process.env.DEFAULT_LOCALE ?? "en-US";
}

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const locale = resolveLocale();
  const dir = getDir(locale);

  return (
    <html lang={locale} dir={dir} className={manrope.variable} {...mantineHtmlProps}>
      <head>
        <ColorSchemeScript defaultColorScheme="auto" />
      </head>
      <body>
        <MantineProvider theme={theme} defaultColorScheme="auto">
          <Notifications position={dir === "rtl" ? "top-left" : "top-right"} />
          <Providers>{children}</Providers>
        </MantineProvider>
      </body>
    </html>
  );
}
