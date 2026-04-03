const { chromium } = require("playwright");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function waitForVisible(page, selector, timeout = 15000) {
  await page.locator(selector).waitFor({ state: "visible", timeout });
}

async function waitForOption(page, selector, label, timeout = 15000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const labels = await page.locator(`${selector} option`).evaluateAll((options) =>
      options.map((option) => option.textContent || "")
    );
    if (labels.includes(label)) {
      return;
    }
    await page.waitForTimeout(200);
  }
  throw new Error(`Option "${label}" not found for ${selector}`);
}

async function waitForTableText(page, text, timeout = 15000) {
  await page.locator("table").filter({ hasText: text }).first().waitFor({
    state: "visible",
    timeout
  });
}

async function waitForSuccess(page, text, timeout = 15000) {
  await page.locator('[data-testid="success-banner"]').filter({ hasText: text }).waitFor({
    state: "visible",
    timeout
  });
  await page.waitForLoadState("networkidle");
}

async function clickNav(page, view) {
  await page.locator(`[data-testid="nav-${view}"]`).click();
  await page.waitForLoadState("networkidle");
}

async function login(page) {
  const email = process.env.DASHBOARD_AUTH_EMAIL || "admin@example.com";
  const password = process.env.DASHBOARD_AUTH_PASSWORD || "secret-pass";

  await waitForVisible(page, '[data-testid="login-form"]');
  await page.fill("#login-email", email);
  await page.fill("#login-password", password);
  await page.click("#login-submit");
  await waitForVisible(page, '[data-testid="nav-customers"]');
}

async function main() {
  const dashboardURL = process.env.DASHBOARD_URL || "http://127.0.0.1:8080";
  const dashboardAPIURL = process.env.DASHBOARD_API_URL || "";
  const suffix = Date.now();
  const customerName = `E2E Customer ${suffix}`;
  const customerEmail = `e2e-${suffix}@example.com`;
  const accountName = `E2E Checking ${suffix}`;
  const savingsProductName = `E2E Savings ${suffix}`;
  const loanProductName = `E2E Loan ${suffix}`;
  const repaymentAmount = "25.00";
  const consoleErrors = [];
  const pageErrors = [];

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();

  if (dashboardAPIURL) {
    await page.addInitScript((apiURL) => {
      const originalFetch = window.fetch.bind(window);
      window.fetch = (input, init) => {
        const url = typeof input === "string" ? input : input.url;
        const rewritten = url.replace(/http:\/\/127\.0\.0\.1:8081\/api\/v1/, apiURL);
        if (typeof input === "string") {
          return originalFetch(rewritten, init);
        }
        return originalFetch(new Request(rewritten, input), init);
      };
    }, dashboardAPIURL);
  }

  page.on("console", (msg) => {
    if (msg.type() === "error") {
      consoleErrors.push(msg.text());
    }
  });
  page.on("pageerror", (err) => {
    pageErrors.push(err.message);
  });

  try {
    await page.goto(dashboardURL, { waitUntil: "domcontentloaded" });
    await login(page);

    await clickNav(page, "customers");
    await page.fill("#customer-name", customerName);
    await page.fill("#customer-email", customerEmail);
    await page.click("#create-customer-button");
    await waitForSuccess(page, "Customer created");
    await waitForTableText(page, customerName);

    await clickNav(page, "accounts");
    await waitForOption(page, "#account-party-select", `${customerName} (${customerEmail})`);
    await page.selectOption("#account-party-select", { label: `${customerName} (${customerEmail})` });
    await page.fill("#account-name", accountName);
    await page.selectOption("#account-currency", "USD");
    await page.click("#create-account-button");
    await waitForSuccess(page, "Account created");
    await waitForTableText(page, accountName);

    await clickNav(page, "products");
    await page.fill("#savings-name", savingsProductName);
    await page.fill("#savings-description", "Playwright savings product");
    await page.fill("#savings-rate-bps", "450");
    await page.fill("#savings-minimum-balance", "100.00");
    await page.selectOption("#savings-currency", "USD");
    await page.selectOption("#savings-interest-type", "simple");
    await page.selectOption("#savings-compounding-period", "monthly");
    await page.click("#create-savings-product-button");
    await waitForSuccess(page, "Savings product created");
    await waitForTableText(page, savingsProductName);

    await page.fill("#loan-product-name", loanProductName);
    await page.fill("#loan-product-description", "Playwright loan product");
    await page.fill("#loan-product-min-amount", "100.00");
    await page.fill("#loan-product-max-amount", "5000.00");
    await page.fill("#loan-product-min-term", "6");
    await page.fill("#loan-product-max-term", "24");
    await page.fill("#loan-product-rate-bps", "1200");
    await page.selectOption("#loan-product-currency", "USD");
    await page.selectOption("#loan-product-interest-type", "flat");
    await page.click("#create-loan-product-button");
    await waitForSuccess(page, "Loan product created");
    await waitForTableText(page, loanProductName);

    await clickNav(page, "loans");
    await waitForOption(page, "#loan-party-select", `${customerName} (${customerEmail})`);
    await page.selectOption("#loan-party-select", { label: `${customerName} (${customerEmail})` });
    await waitForOption(page, "#loan-create-product", `${loanProductName} (USD)`);
    await waitForOption(page, "#loan-create-account", `${accountName} (USD)`);
    await page.selectOption("#loan-create-product", { label: `${loanProductName} (USD)` });
    await page.selectOption("#loan-create-account", { label: `${accountName} (USD)` });
    await page.fill("#loan-create-principal", "200.00");
    await page.fill("#loan-create-term", "12");
    await page.click("#create-loan-button");
    await waitForSuccess(page, "Loan created");
    await waitForTableText(page, loanProductName);

    const loanRow = page.locator("table.data-table tbody tr").filter({ hasText: loanProductName }).first();
    await loanRow.locator('button:has-text("Approve")').click();
    await waitForSuccess(page, "Loan approved");
    await page.locator("table.data-table tbody tr").filter({ hasText: loanProductName }).first().locator('button:has-text("Disburse")').click();
    await waitForSuccess(page, "Loan disbursed");

    const disbursedRow = page.locator("table.data-table tbody tr").filter({ hasText: loanProductName }).first();
    await disbursedRow.locator('button:has-text("View")').click();
    await waitForVisible(page, "#loan-repayment-amount");
    await page.fill("#loan-repayment-amount", repaymentAmount);
    await page.selectOption("#loan-repayment-type", "partial");
    await page.click("#record-loan-repayment-button");
    await waitForSuccess(page, "Repayment recorded");
    await waitForTableText(page, "$25.00");

    assert(pageErrors.length === 0, `Page errors: ${pageErrors.join("; ")}`);
    assert(consoleErrors.length === 0, `Console errors: ${consoleErrors.join("; ")}`);

    console.log("Dashboard E2E flow passed");
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err.stack || err.message);
  process.exit(1);
});
