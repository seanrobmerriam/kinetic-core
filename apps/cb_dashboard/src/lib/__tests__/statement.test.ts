import {
  buildStatementPath,
  csvFilename,
  defaultRange,
  entriesToCsv,
  validateRange,
  type StatementEntry,
} from "@/lib/statement";

describe("statement helpers", () => {
  describe("validateRange", () => {
    it("flags missing dates", () => {
      expect(validateRange({ from: "", to: "2024-01-01" })).toBe("missing-from");
      expect(validateRange({ from: "2024-01-01", to: "" })).toBe("missing-to");
    });

    it("flags from after to", () => {
      expect(validateRange({ from: "2024-02-10", to: "2024-02-01" })).toBe(
        "from-after-to",
      );
    });

    it("accepts a valid range with from == to", () => {
      expect(validateRange({ from: "2024-02-01", to: "2024-02-01" })).toBeNull();
    });
  });

  describe("defaultRange", () => {
    it("uses first-of-month through today", () => {
      const r = defaultRange(new Date(2024, 5, 17));
      expect(r.from).toBe("2024-06-01");
      expect(r.to).toBe("2024-06-17");
    });
  });

  describe("buildStatementPath", () => {
    it("encodes accountId and serialises date range as ms", () => {
      const path = buildStatementPath(
        "acc/with space",
        { from: "2024-01-01", to: "2024-01-02" },
        2,
        100,
      );
      expect(path.startsWith("/accounts/acc%2Fwith%20space/statement?")).toBe(true);
      const params = new URLSearchParams(path.split("?")[1]);
      expect(Number(params.get("from"))).toBe(
        new Date(2024, 0, 1, 0, 0, 0, 0).getTime(),
      );
      expect(Number(params.get("to"))).toBe(
        new Date(2024, 0, 2, 23, 59, 59, 999).getTime(),
      );
      expect(params.get("page")).toBe("2");
      expect(params.get("page_size")).toBe("100");
    });
  });

  describe("entriesToCsv", () => {
    const entry: StatementEntry = {
      entry_id: "e1",
      txn_id: "t1",
      account_id: "a1",
      entry_type: "credit",
      amount: 1234,
      currency: "USD",
      description: 'Pay, "rent"',
      posted_at: 1700000000000,
      running_balance: 1234,
    };

    it("emits a header row and serialises entries", () => {
      const csv = entriesToCsv([entry]);
      const lines = csv.trim().split("\r\n");
      expect(lines[0]).toBe(
        "Posted At,Entry ID,Transaction ID,Type,Amount,Currency,Running Balance,Description",
      );
      expect(lines[1]).toContain("e1,t1,credit,1234,USD,1234");
    });

    it("escapes commas and quotes per RFC4180", () => {
      const csv = entriesToCsv([entry]);
      expect(csv).toContain('"Pay, ""rent"""');
    });

    it("includes account metadata as comment lines", () => {
      const csv = entriesToCsv([entry], {
        account_name: "Checking",
        currency: "USD",
        opening_balance: 0,
        closing_balance: 1234,
      });
      expect(csv).toContain("# Account: Checking");
      expect(csv).toContain("# Currency: USD");
      expect(csv).toContain("# Opening Balance (minor units): 0");
      expect(csv).toContain("# Closing Balance (minor units): 1234");
    });
  });

  describe("csvFilename", () => {
    it("sanitises the account name", () => {
      const name = csvFilename("Bob's Checking!", {
        from: "2024-01-01",
        to: "2024-01-31",
      });
      expect(name).toBe("Bob_s_Checking_statement_2024-01-01_to_2024-01-31.csv");
    });

    it("falls back to a default when name is unusable", () => {
      const name = csvFilename("***", { from: "2024-01-01", to: "2024-01-31" });
      expect(name).toBe("account_statement_2024-01-01_to_2024-01-31.csv");
    });
  });
});
