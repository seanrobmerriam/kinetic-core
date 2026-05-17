/**
 * Locale and RTL support utilities for the Kinetic Core dashboard (TASK-036).
 *
 * Provides:
 *  - RTL detection for supported locale codes
 *  - HTML `dir` attribute resolution
 *  - Locale-aware number and currency formatting (thin wrapper over Intl)
 *  - Direction-aware CSS class helpers for layout and documents
 */

/** Supported locale codes — must stay in sync with cb_locale.erl */
export const SUPPORTED_LOCALES = [
  "en-US",
  "en-GB",
  "en-AU",
  "de-DE",
  "fr-FR",
  "ja-JP",
  "zh-CN",
  "ar-SA",
  "ar-AE",
  "he-IL",
  "sg-SG",
] as const;

export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

/** Locales that use right-to-left text direction */
const RTL_LOCALES = new Set<string>(["ar-SA", "ar-AE", "he-IL"]);

/**
 * Returns true when the locale requires right-to-left layout.
 *
 * @example
 * isRTL("ar-SA") // true
 * isRTL("en-US") // false
 */
export function isRTL(locale: string): boolean {
  return RTL_LOCALES.has(locale);
}

/**
 * Returns the HTML `dir` attribute value for the given locale.
 *
 * Use this on the `<html>` element (or any element that should inherit
 * direction) to satisfy WCAG 1.3.4 (Orientation) and browser BiDi requirements.
 *
 * @example
 * const dir = getDir("ar-SA"); // "rtl"
 * <html lang="ar-SA" dir={dir}>
 */
export function getDir(locale: string): "ltr" | "rtl" {
  return isRTL(locale) ? "rtl" : "ltr";
}

/**
 * Returns CSS class names for direction-aware layout.
 *
 * Provides utility classes that can be spread onto container elements
 * to reverse flex/grid order and text alignment for RTL languages.
 *
 * @example
 * const cls = dirClasses("ar-SA");
 * <div className={cls.container}>…</div>
 */
export function dirClasses(locale: string): {
  container: string;
  text: string;
  flexRow: string;
} {
  const rtl = isRTL(locale);
  return {
    container: rtl ? "rtl-layout" : "ltr-layout",
    text: rtl ? "text-right" : "text-left",
    flexRow: rtl ? "flex-row-reverse" : "flex-row",
  };
}

/**
 * Format a monetary minor-unit amount using the browser's Intl API,
 * respecting the supplied locale.
 *
 * @param amountMinor - Integer amount in minor units (e.g. cents).
 * @param currencyCode - ISO 4217 code, e.g. "USD".
 * @param locale - IETF locale string, e.g. "en-US".
 *
 * @example
 * formatCurrency(123456, "USD", "en-US") // "$1,234.56"
 * formatCurrency(123456, "EUR", "de-DE") // "1.234,56 €"
 */
export function formatCurrency(
  amountMinor: number,
  currencyCode: string,
  locale: string
): string {
  const minorUnits = currencyCode === "JPY" ? 1 : 100;
  const major = amountMinor / minorUnits;
  try {
    return new Intl.NumberFormat(locale, {
      style: "currency",
      currency: currencyCode,
      minimumFractionDigits: currencyCode === "JPY" ? 0 : 2,
      maximumFractionDigits: currencyCode === "JPY" ? 0 : 2,
    }).format(major);
  } catch {
    // Graceful fallback for unknown currency codes
    return `${currencyCode} ${major.toFixed(2)}`;
  }
}

/**
 * Format a number with locale-appropriate thousands separators and
 * decimal marks.
 *
 * @example
 * formatNumber(1234567.89, "de-DE") // "1.234.567,89"
 * formatNumber(1234567.89, "en-US") // "1,234,567.89"
 */
export function formatNumber(value: number, locale: string): string {
  try {
    return new Intl.NumberFormat(locale).format(value);
  } catch {
    return String(value);
  }
}

/**
 * Format a Unix timestamp (ms) as a locale-aware date string.
 *
 * @example
 * formatDate(1720051200000, "en-US") // "July 4, 2024"
 * formatDate(1720051200000, "de-DE") // "4. Juli 2024"
 */
export function formatDate(
  timestampMs: number,
  locale: string,
  style: "long" | "short" | "numeric" = "long"
): string {
  try {
    const dateStyle = style === "numeric" ? undefined : style;
    const opts: Intl.DateTimeFormatOptions = dateStyle
      ? { dateStyle }
      : { year: "numeric", month: "2-digit", day: "2-digit" };
    return new Intl.DateTimeFormat(locale, opts).format(new Date(timestampMs));
  } catch {
    return new Date(timestampMs).toDateString();
  }
}

/**
 * Retrieve the active locale from the document or fall back to the browser
 * default.  Reads the `lang` attribute from `<html>` if available.
 *
 * Safe to call in both SSR and CSR contexts.
 */
export function getActiveLocale(): string {
  if (typeof document !== "undefined") {
    const lang = document.documentElement.lang;
    if (lang) return lang;
  }
  if (typeof navigator !== "undefined") {
    return navigator.language ?? "en-US";
  }
  return "en-US";
}
