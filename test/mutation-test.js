#!/usr/bin/env node
'use strict';

/**
 * Mutation testing runner for financial calculation modules.
 *
 * For each mutation:
 *   1. Apply a semantic code change to a source file
 *   2. Run `rebar3 compile` — skips if the mutant is invalid Erlang
 *   3. Run the targeted CT suite — a failing test kills the mutant
 *   4. Restore the original source unconditionally
 *   5. Emit per-mutation status and a final kill-rate summary
 *
 * Environment variables:
 *   MUTATION_THRESHOLD   – minimum required kill rate (default: 0.70)
 *   MUTATION_STRICT      – set to "1" to exit 1 when threshold is not met
 */

const fs   = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');

// ─── Mutation definitions ─────────────────────────────────────────────────────
//
// Each entry describes one semantic mutation:
//   id       – short identifier used in the report
//   desc     – human-readable description of what changed
//   file     – path relative to ROOT
//   original – exact string to replace; must appear exactly once in the file
//   mutant   – replacement string (must produce syntactically valid Erlang)
//   suite    – CT suite name(s) expected to catch this mutation

const MUTATIONS = [

  // ── cb_interest.erl ─────────────────────────────────────────────────────

  {
    id:       'INT-01',
    desc:     'daily rate: div → * (multiply instead of divide by days/year)',
    file:     'apps/cb_interest/src/cb_interest.erl',
    original: '(AnnualRateBps * ?PPB_PER_BASIS_POINT) div ?DAYS_IN_YEAR.',
    mutant:   '(AnnualRateBps * ?PPB_PER_BASIS_POINT) * ?DAYS_IN_YEAR.',
    suite:    'cb_interest_SUITE',
  },
  {
    id:       'INT-02',
    desc:     'simple interest: off-by-one in numerator (add 1 before dividing)',
    file:     'apps/cb_interest/src/cb_interest.erl',
    original: '(Balance * DailyRatePpb * Days) div ?PPB_SCALE.',
    mutant:   '(Balance * DailyRatePpb * Days + 1) div ?PPB_SCALE.',
    suite:    'cb_interest_SUITE',
  },
  {
    id:       'INT-03',
    desc:     'compound interest: accumulate Balance − Interest instead of Balance + Interest',
    file:     'apps/cb_interest/src/cb_interest.erl',
    original: 'compound_over_periods(Balance + Interest,',
    mutant:   'compound_over_periods(Balance - Interest,',
    suite:    'cb_interest_SUITE',
  },
  {
    id:       'INT-04',
    desc:     'monthly compounding period: 30 days → 31 days',
    file:     'apps/cb_interest/src/cb_interest.erl',
    original: 'period_days(monthly) ->\n    30;',
    mutant:   'period_days(monthly) ->\n    31;',
    suite:    'cb_interest_SUITE',
  },
  {
    id:       'INT-05',
    desc:     'daily rate guard: AnnualRateBps >= 0 → > 0 (rejects zero-rate inputs)',
    file:     'apps/cb_interest/src/cb_interest.erl',
    original: 'is_integer(AnnualRateBps), AnnualRateBps >= 0 ->',
    mutant:   'is_integer(AnnualRateBps), AnnualRateBps > 0 ->',
    suite:    'cb_interest_SUITE',
  },

  // ── cb_loan_calculations.erl ─────────────────────────────────────────────

  {
    id:       'LOAN-01',
    desc:     'principal portion: remove max(0, …) floor guard',
    file:     'apps/cb_loans/src/cb_loan_calculations.erl',
    original: 'max(0, TotalPayment - InterestPortion).',
    mutant:   'TotalPayment - InterestPortion.',
    suite:    'cb_loans_SUITE',
  },
  {
    id:       'LOAN-02',
    desc:     'outstanding balance: remove max(0, …) floor guard',
    file:     'apps/cb_loans/src/cb_loan_calculations.erl',
    original: 'max(0, Principal - TotalPaid).',
    mutant:   'Principal - TotalPaid.',
    suite:    'cb_loans_SUITE',
  },
  {
    id:       'LOAN-03',
    desc:     'ceil_div: remove ceiling adjustment (becomes floor division)',
    file:     'apps/cb_loans/src/cb_loan_calculations.erl',
    original: '(Numerator + Denominator - 1) div Denominator.',
    mutant:   'Numerator div Denominator.',
    suite:    'cb_loans_SUITE',
  },
  {
    id:       'LOAN-04',
    desc:     'round_div: remove rounding offset (becomes truncating division)',
    file:     'apps/cb_loans/src/cb_loan_calculations.erl',
    original: '(Numerator + (Denominator div 2)) div Denominator.',
    mutant:   'Numerator div Denominator.',
    suite:    'cb_loans_SUITE',
  },
  {
    id:       'LOAN-05',
    desc:     'MONTHLY_RATE_DIVISOR: multiplication → addition (120 000 → 10 012)',
    file:     'apps/cb_loans/src/cb_loan_calculations.erl',
    original: '-define(MONTHLY_RATE_DIVISOR, ?MONTHS_PER_YEAR * ?BPS_FACTOR).',
    mutant:   '-define(MONTHLY_RATE_DIVISOR, ?MONTHS_PER_YEAR + ?BPS_FACTOR).',
    suite:    'cb_loans_SUITE',
  },

];

// ─── Configuration ────────────────────────────────────────────────────────────

const THRESHOLD = parseFloat(process.env.MUTATION_THRESHOLD || '0.70');
const STRICT    = process.env.MUTATION_STRICT === '1';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function rebar3(args) {
  return spawnSync('rebar3', args, {
    cwd:      ROOT,
    stdio:    'pipe',
    shell:    true,
    timeout:  180_000,
    encoding: 'utf8',
  });
}

/**
 * Replace the unique occurrence of `original` in `filePath` with `mutant`.
 * Returns { ok: true, saved } on success, or { ok: false, reason } on ambiguity.
 */
function applyMutation(filePath, original, mutant) {
  const src    = fs.readFileSync(filePath, 'utf8');
  const count  = src.split(original).length - 1;
  if (count !== 1) {
    return { ok: false, reason: `${count} occurrences found (expected 1)` };
  }
  fs.writeFileSync(filePath, src.replace(original, mutant), 'utf8');
  return { ok: true, saved: src };
}

function restore(filePath, saved) {
  fs.writeFileSync(filePath, saved, 'utf8');
}

function pad(s, n)  { return String(s).padEnd(n); }

// ─── Per-mutation runner ──────────────────────────────────────────────────────

function runMutation(m) {
  const absFile = path.join(ROOT, m.file);
  const apply   = applyMutation(absFile, m.original, m.mutant);

  if (!apply.ok) {
    return { id: m.id, status: 'SKIP', detail: apply.reason };
  }

  let status = 'SURVIVED';
  let detail = '';

  try {
    const compile = rebar3(['compile']);
    if (compile.status !== 0) {
      status = 'COMPILE_ERROR';
      detail = (compile.stderr || '').trim().split('\n').slice(-2).join(' | ');
    } else {
      const suites = Array.isArray(m.suite) ? m.suite.join(',') : m.suite;
      const ct     = rebar3(['ct', '--suite', suites]);
      if (ct.status !== 0) {
        status = 'KILLED';
        const match = (ct.stdout || '').match(/(\d+) cases? failed/);
        detail = match ? `${match[1]} test(s) failed` : 'test failure detected';
      } else {
        detail = 'all CT tests passed — test gap';
      }
    }
  } finally {
    restore(absFile, apply.saved);
  }

  return { id: m.id, status, detail };
}

// ─── Main ─────────────────────────────────────────────────────────────────────

console.log('\n=== Mutation Testing Report ===');
console.log(`Targets  : cb_interest.erl, cb_loan_calculations.erl`);
console.log(`Mutations: ${MUTATIONS.length}`);
console.log(`Threshold: ${(THRESHOLD * 100).toFixed(0)}% kill rate\n`);

const results = [];
for (const m of MUTATIONS) {
  process.stdout.write(`  ${pad(m.id, 9)} ${m.desc.slice(0, 58).padEnd(58)} `);
  const r = runMutation(m);
  results.push(r);
  const icon = { KILLED: '✓', COMPILE_ERROR: '~', SKIP: '-', SURVIVED: '✗' }[r.status] || '?';
  console.log(`${icon} ${r.status}${r.detail ? ` (${r.detail})` : ''}`);
}

// ─── Summary ──────────────────────────────────────────────────────────────────

const killed   = results.filter(r => r.status === 'KILLED').length;
const survived = results.filter(r => r.status === 'SURVIVED').length;
const cerrors  = results.filter(r => r.status === 'COMPILE_ERROR').length;
const skipped  = results.filter(r => r.status === 'SKIP').length;
const eligible = results.length - skipped;
const killRate = eligible > 0 ? killed / eligible : 0;

const LINE = '─'.repeat(76);
console.log(`\n${LINE}`);
console.log(pad('ID', 10) + pad('STATUS', 16) + 'DETAIL');
console.log(LINE);
for (const r of results) {
  console.log(pad(r.id, 10) + pad(r.status, 16) + (r.detail || ''));
}
console.log(LINE);

console.log(`\nTotal mutations : ${results.length}`);
console.log(`Killed          : ${killed}`);
console.log(`Survived        : ${survived}`);
console.log(`Compile errors  : ${cerrors}`);
console.log(`Skipped         : ${skipped}`);
console.log(`Kill rate       : ${(killRate * 100).toFixed(1)}%  (threshold: ${(THRESHOLD * 100).toFixed(0)}%)`);

if (survived > 0) {
  console.log('\nSurviving mutations — test gaps to address:');
  for (const r of results.filter(r => r.status === 'SURVIVED')) {
    const m = MUTATIONS.find(x => x.id === r.id);
    console.log(`\n  ${r.id}: ${m.desc}`);
    console.log(`    file    : ${m.file}`);
    console.log(`    original: ${m.original.replace(/\n/g, '\\n')}`);
    console.log(`    mutant  : ${m.mutant.replace(/\n/g, '\\n')}`);
  }
}

if (STRICT && killRate < THRESHOLD) {
  console.error(`\n[FAIL] Kill rate ${(killRate * 100).toFixed(1)}% is below threshold ${(THRESHOLD * 100).toFixed(0)}%`);
  process.exit(1);
} else if (killRate < THRESHOLD) {
  console.warn(`\n[WARN] Kill rate ${(killRate * 100).toFixed(1)}% is below threshold ${(THRESHOLD * 100).toFixed(0)}%`);
} else {
  console.log(`\n[PASS] Kill rate ${(killRate * 100).toFixed(1)}% meets threshold`);
}
