/**
 * E2E test suite for the Next.js / Mantine dashboard (kinetic-core).
 *
 * Journeys covered:
 *   auth          — login, verify dashboard, logout, verify redirect
 *   customer      — create customer via /customers/create form
 *   account       — create two accounts for the test customer
 *   deposit       — deposit funds via /deposit form
 *   withdraw      — withdraw funds via /deposit (withdraw side)
 *   transfer      — internal transfer via /transfer/create
 *   compliance    — update KYC status via /compliance → KYC Management tab
 *   ledger        — load /reports/trial-balance and /reports/general-ledger
 *
 * Prerequisites:
 *   - Dashboard running at DASHBOARD_URL (default http://localhost:3000)
 *   - Backend API running at http://localhost:4000
 *   - A valid admin account at DASHBOARD_AUTH_EMAIL / DASHBOARD_AUTH_PASSWORD
 *
 * Usage:
 *   node test/e2e-journeys.js
 */

"use strict";

const { chromium } = require("playwright");

// ─── Configuration ─────────────────────────────────────────────────────────

const BASE_URL = process.env.DASHBOARD_URL || "http://localhost:3000";
const ADMIN_EMAIL =
  process.env.DASHBOARD_AUTH_EMAIL || "admin@example.com";
const ADMIN_PASSWORD =
  process.env.DASHBOARD_AUTH_PASSWORD || "secret-pass";

const DEFAULT_TIMEOUT = 20000;

// Unique suffix for test data so repeated runs don't conflict
const TS = Date.now();

// ─── Helpers ───────────────────────────────────────────────────────────────

function assert(cond, msg) {
  if (!cond) throw new Error(`Assertion failed: ${msg}`);
}

/**
 * Wait for the success notification banner containing the given text fragment.
 */
async function waitForSuccess(page, fragment, timeout = DEFAULT_TIMEOUT) {
  await page
    .locator('[data-testid="success-banner"]')
    .filter({ hasText: fragment })
    .waitFor({ state: "visible", timeout });
}

/**
 * Interact with a Mantine v7 Select / Combobox:
 *   1. Click the input identified by its visible label to open the dropdown.
 *   2. Click the matching option from the listbox.
 */
async function selectMantine(page, labelText, optionText) {
  await page.getByLabel(labelText).click();
  await page
    .getByRole("option", { name: optionText })
    .first()
    .click();
}

/**
 * Interact with a searchable Mantine Select by typing a search term first,
 * then clicking the first matching option.
 */
async function searchSelectMantine(page, labelText, searchTerm, timeout = DEFAULT_TIMEOUT) {
  await page.getByLabel(labelText).click();
  await page.getByLabel(labelText).fill(searchTerm);
  await page
    .getByRole("option")
    .first()
    .waitFor({ state: "visible", timeout });
  await page.getByRole("option").first().click();
}

/**
 * Navigate to the given path and wait for the network to settle.
 */
async function goto(page, path) {
  await page.goto(`${BASE_URL}${path}`);
  await page.waitForLoadState("networkidle");
}

/**
 * Log in with the configured admin credentials.
 * Resolves when the browser has landed on /dashboard.
 */
async function login(page) {
  await goto(page, "/login");
  await page
    .locator('[data-testid="login-form"]')
    .waitFor({ state: "visible", timeout: DEFAULT_TIMEOUT });

  await page.fill("#login-email", ADMIN_EMAIL);
  await page.fill("#login-password", ADMIN_PASSWORD);
  await page.click("#login-submit");

  await page.waitForURL(/\/dashboard/, { timeout: DEFAULT_TIMEOUT });
}

// ─── Individual journeys ───────────────────────────────────────────────────

/**
 * Auth journey:
 *   - Unauthenticated access to /dashboard redirects to /login.
 *   - Login lands on /dashboard.
 *   - Logout returns to /login.
 *   - Finishes with the page in an authenticated state.
 */
async function journeyAuth(page) {
  console.log("  [auth] unauthenticated redirect...");
  await page.goto(`${BASE_URL}/dashboard`);
  await page.waitForURL(/\/login/, { timeout: DEFAULT_TIMEOUT });

  console.log("  [auth] login...");
  await login(page);
  assert(page.url().includes("/dashboard"), "Expected /dashboard after login");

  console.log("  [auth] logout...");
  await page
    .locator('[data-testid="logout-button"]')
    .waitFor({ state: "visible", timeout: DEFAULT_TIMEOUT });
  await page.locator('[data-testid="logout-button"]').click();
  await page.waitForURL(/\/login/, { timeout: DEFAULT_TIMEOUT });

  console.log("  [auth] re-login for subsequent journeys...");
  await login(page);
}

/**
 * Customer journey:
 *   - Navigate to /customers/create.
 *   - Fill and submit the customer form.
 *   - Verify success notification and redirect to /customers.
 *
 * Returns { customerName, customerEmail }.
 */
async function journeyCustomer(page) {
  const customerName = `E2E User ${TS}`;
  const customerEmail = `e2e_${TS}@example.com`;

  console.log(`  [customer] creating ${customerEmail}...`);
  await goto(page, "/customers/create");

  await page.fill("#customer-name", customerName);
  await page.fill("#customer-email", customerEmail);
  await page.getByRole("button", { name: "Create Customer" }).click();

  await waitForSuccess(page, "Customer created");
  await page.waitForURL(/\/customers/, { timeout: DEFAULT_TIMEOUT });

  return { customerName, customerEmail };
}

/**
 * Account journey:
 *   - Navigate to /accounts/create.
 *   - Select the test customer by searching for their email.
 *   - Fill account name and submit.
 *   - Capture the account_id from the redirect URL (/accounts/:id).
 *
 * Returns the account_id string.
 */
async function journeyAccount(page, customerEmail, nameSuffix = "") {
  const accountName = `E2E Account${nameSuffix} ${TS}`;

  console.log(`  [account] creating "${accountName}"...`);
  await goto(page, "/accounts/create");

  // Customer: searchable Mantine Select — type email to filter, pick first option
  await searchSelectMantine(page, "Customer", customerEmail);

  // Account Type defaults to Checking — leave it

  // Account Name: plain TextInput with label (no id)
  await page.getByLabel("Account Name").fill(accountName);

  // Currency defaults to USD — leave it

  await page.getByRole("button", { name: "Create Account" }).click();

  await page.waitForURL(/\/accounts\/[a-z0-9-]+$/, {
    timeout: DEFAULT_TIMEOUT,
  });

  const accountId = page.url().split("/accounts/")[1];
  assert(accountId && accountId.length > 0, "Account ID missing from redirect URL");

  console.log(`  [account] created ${accountId}`);
  return accountId;
}

/**
 * Deposit journey:
 *   - Navigate to /deposit.
 *   - Fill and submit the Deposit form.
 *   - Verify success notification.
 */
async function journeyDeposit(page, accountId) {
  console.log(`  [deposit] depositing to ${accountId}...`);
  await goto(page, "/deposit");

  await page.fill("#deposit-account", accountId);
  await page.fill("#deposit-amount", "1000.00");
  // Currency defaults to USD
  await page.fill("#deposit-desc", `E2E deposit ${TS}`);

  await page.getByRole("button", { name: "Deposit" }).click();
  await waitForSuccess(page, "Deposit successful");
}

/**
 * Withdrawal journey:
 *   - Navigate to /deposit (the page hosts both forms).
 *   - Fill and submit the Withdraw form.
 *   - Verify success notification.
 */
async function journeyWithdraw(page, accountId) {
  console.log(`  [withdraw] withdrawing from ${accountId}...`);
  await goto(page, "/deposit");

  await page.fill("#withdraw-account", accountId);
  await page.fill("#withdraw-amount", "10.00");
  // Currency defaults to USD
  await page.fill("#withdraw-desc", `E2E withdrawal ${TS}`);

  await page.getByRole("button", { name: "Withdraw" }).click();
  await waitForSuccess(page, "Withdrawal successful");
}

/**
 * Transfer journey:
 *   - Navigate to /transfer/create.
 *   - Select source and destination accounts by searching with their IDs.
 *   - Enter amount and submit.
 *   - Verify success notification and redirect to /transfer.
 */
async function journeyTransfer(page, sourceId, destId) {
  console.log(`  [transfer] ${sourceId} → ${destId}...`);
  await goto(page, "/transfer/create");

  // Source Account — searchable Select; search by the first 8 chars of the ID
  await searchSelectMantine(page, "Source Account", sourceId.slice(0, 8));

  // Destination Account — searchable Select (excludes source once source is set)
  await searchSelectMantine(page, "Destination Account", destId.slice(0, 8));

  // Amount — Mantine NumberInput (label: "Amount")
  await page.getByLabel("Amount").fill("5.00");

  // Currency defaults to USD

  await page.getByRole("button", { name: "Submit Transfer" }).click();

  await waitForSuccess(page, "Transfer initiated");
  await page.waitForURL(/\/transfer/, { timeout: DEFAULT_TIMEOUT });
}

/**
 * Compliance journey:
 *   - Navigate to /compliance.
 *   - Switch to the KYC Management tab.
 *   - Click "Update KYC" on the first customer in the table.
 *   - Set status to "Approved" and add review notes.
 *   - Submit and verify success notification.
 */
async function journeyCompliance(page) {
  console.log("  [compliance] KYC update...");
  await goto(page, "/compliance");

  // Switch to KYC Management tab via SegmentedControl label
  await page.getByText("KYC Management").click();
  await page.waitForLoadState("networkidle");

  // Click "Update KYC" on the first customer
  await page
    .getByRole("button", { name: "Update KYC" })
    .first()
    .waitFor({ state: "visible", timeout: DEFAULT_TIMEOUT });
  await page.getByRole("button", { name: "Update KYC" }).first().click();

  // Fill the KYC update form that appears
  await selectMantine(page, "KYC Status", "Approved");
  await page.getByLabel("Review Notes").fill(`E2E review ${TS}`);
  await page.getByRole("button", { name: "Save" }).click();

  await waitForSuccess(page, "KYC updated");
}

/**
 * Ledger journey:
 *   - Navigate to /reports/trial-balance, generate a USD report.
 *   - Navigate to /reports/general-ledger and verify the page loads without errors.
 */
async function journeyLedger(page) {
  console.log("  [ledger] trial balance...");
  await goto(page, "/reports/trial-balance");

  await selectMantine(page, "Currency", "USD");
  await page.getByRole("button", { name: "Generate Report" }).click();
  await page.waitForLoadState("networkidle");

  // Verify no error banner appeared
  const trialBalanceError = await page
    .locator('[data-testid="error-banner"]')
    .isVisible()
    .catch(() => false);
  assert(!trialBalanceError, "Trial balance page shows error banner");

  console.log("  [ledger] general ledger...");
  await goto(page, "/reports/general-ledger");

  const glError = await page
    .locator('[data-testid="error-banner"]')
    .isVisible()
    .catch(() => false);
  assert(!glError, "General ledger page shows error banner");
}

// ─── Runner ────────────────────────────────────────────────────────────────

async function main() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  const results = [];

  /**
   * Run a named journey function, catch any error, and record pass/fail.
   * The journey function receives `page` and must return a value or undefined.
   */
  async function run(name, fn) {
    process.stdout.write(`\n▶ ${name}\n`);
    try {
      const result = await fn(page);
      console.log(`✓ ${name} — PASS`);
      results.push({ name, status: "PASS" });
      return result;
    } catch (err) {
      console.error(`✗ ${name} — FAIL: ${err.message}`);
      results.push({ name, status: "FAIL", error: err.message });
      return undefined;
    }
  }

  function skip(name, reason) {
    console.log(`○ ${name} — SKIP (${reason})`);
    results.push({ name, status: "SKIP", reason });
  }

  try {
    // Auth must run first to establish authenticated state
    await run("auth", journeyAuth);

    // Customer creation
    const customerResult = await run("customer", journeyCustomer);
    const customerEmail = customerResult?.customerEmail;

    // Accounts (require a valid customer)
    let accountId1, accountId2;

    if (customerEmail) {
      accountId1 = await run("account_1", (p) =>
        journeyAccount(p, customerEmail, " Alpha")
      );
      accountId2 = await run("account_2", (p) =>
        journeyAccount(p, customerEmail, " Beta")
      );
    } else {
      skip("account_1", "customer creation failed");
      skip("account_2", "customer creation failed");
    }

    // Deposit / withdraw (require accountId1)
    if (accountId1) {
      await run("deposit", (p) => journeyDeposit(p, accountId1));
      await run("withdraw", (p) => journeyWithdraw(p, accountId1));
    } else {
      skip("deposit", "account_1 creation failed");
      skip("withdraw", "account_1 creation failed");
    }

    // Transfer (requires both accounts)
    if (accountId1 && accountId2) {
      await run("transfer", (p) => journeyTransfer(p, accountId1, accountId2));
    } else {
      skip("transfer", "one or both accounts not created");
    }

    // Compliance — independent of test accounts
    await run("compliance", journeyCompliance);

    // Ledger reports — independent of test accounts
    await run("ledger", journeyLedger);
  } finally {
    await browser.close();
  }

  // ── Summary ──────────────────────────────────────────────────────────────
  console.log("\n─────────────────────────────────────────────────");
  console.log(" E2E Journey Results");
  console.log("─────────────────────────────────────────────────");

  let passed = 0;
  let failed = 0;
  let skipped = 0;

  for (const r of results) {
    const icon = r.status === "PASS" ? "✓" : r.status === "SKIP" ? "○" : "✗";
    const detail =
      r.status === "FAIL" ? ` — ${r.error}` :
      r.status === "SKIP" ? ` (${r.reason})` :
      "";
    console.log(`  ${icon}  ${r.name}${detail}`);
    if (r.status === "PASS") passed++;
    else if (r.status === "FAIL") failed++;
    else skipped++;
  }

  console.log("─────────────────────────────────────────────────");
  console.log(`  Passed: ${passed}   Failed: ${failed}   Skipped: ${skipped}`);
  console.log("─────────────────────────────────────────────────\n");

  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
