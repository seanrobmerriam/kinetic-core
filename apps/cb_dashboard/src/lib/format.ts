export function formatAmount(amount: number, currency: string): string {
  switch (currency) {
    case "JPY":
      return `¥${amount}`;
    case "USD":
      return `$${(amount / 100).toFixed(2)}`;
    case "EUR":
      return `€${(amount / 100).toFixed(2)}`;
    case "GBP":
      return `£${(amount / 100).toFixed(2)}`;
    case "CHF":
      return `CHF ${(amount / 100).toFixed(2)}`;
    default:
      return `${amount}`;
  }
}

export function parseAmount(amountStr: string): number {
  const trimmed = (amountStr ?? "").trim();
  if (trimmed === "") {
    throw new Error("Empty amount");
  }
  const num = Number(trimmed);
  if (!Number.isFinite(num)) {
    throw new Error(`Invalid amount: ${amountStr}`);
  }
  // Round to nearest cent (minor units)
  return Math.round(num * 100);
}

export function formatTimestamp(ts: number): string {
  if (!ts) return "—";
  const d = new Date(ts < 1e12 ? ts * 1000 : ts);
  return d.toLocaleString();
}

export function formatDate(ts: number): string {
  if (!ts) return "—";
  const d = new Date(ts < 1e12 ? ts * 1000 : ts);
  return d.toLocaleDateString();
}

export function formatNumber(n: number): string {
  return new Intl.NumberFormat().format(n);
}

export function truncateID(id: string): string {
  if (!id) return "";
  if (id.length <= 12) return id;
  return `${id.slice(0, 6)}…${id.slice(-4)}`;
}

export function capitalize(s: string): string {
  if (!s) return s;
  return s.charAt(0).toUpperCase() + s.slice(1);
}
