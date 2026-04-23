import {
  formatAmount,
  parseAmount,
  formatTimestamp,
  truncateID,
  capitalize,
} from "../format";

describe("formatAmount", () => {
  it("formats USD as dollars from minor units", () => {
    expect(formatAmount(12345, "USD")).toBe("$123.45");
  });

  it("formats EUR with euro sign", () => {
    expect(formatAmount(5000, "EUR")).toBe("€50.00");
  });

  it("formats JPY without decimal scaling (zero-decimal currency)", () => {
    expect(formatAmount(1000, "JPY")).toBe("¥1000");
  });

  it("returns raw amount for unknown currency", () => {
    expect(formatAmount(99, "XYZ")).toBe("99");
  });
});

describe("parseAmount", () => {
  it("converts decimal string to integer minor units", () => {
    expect(parseAmount("12.34")).toBe(1234);
  });

  it("rounds to nearest minor unit", () => {
    expect(parseAmount("0.005")).toBe(1);
  });

  it("throws on empty string", () => {
    expect(() => parseAmount("")).toThrow("Empty amount");
  });

  it("throws on non-numeric input", () => {
    expect(() => parseAmount("abc")).toThrow(/Invalid amount/);
  });
});

describe("formatTimestamp", () => {
  it("returns dash for falsy timestamps", () => {
    expect(formatTimestamp(0)).toBe("—");
  });

  it("treats values below 1e12 as seconds", () => {
    const seconds = 1700000000;
    expect(formatTimestamp(seconds)).toBe(
      new Date(seconds * 1000).toLocaleString(),
    );
  });
});

describe("truncateID", () => {
  it("returns short ids unchanged", () => {
    expect(truncateID("abc123")).toBe("abc123");
  });

  it("truncates long ids with ellipsis", () => {
    expect(truncateID("abcdef1234567890")).toBe("abcdef…7890");
  });

  it("returns empty string for empty input", () => {
    expect(truncateID("")).toBe("");
  });
});

describe("capitalize", () => {
  it("uppercases the first letter", () => {
    expect(capitalize("hello")).toBe("Hello");
  });

  it("returns empty string unchanged", () => {
    expect(capitalize("")).toBe("");
  });
});
