# IronLedger Glossary

This glossary maps banking terminology to its precise meaning within IronLedger.
When in doubt, use the definition here — not a general banking textbook definition.

---

## A

**Account**  
A record owned by a Party that holds a balance in a single currency. An account has a
lifecycle: `active → frozen → active` (reversible) or `active → closed` (irreversible).
See `docs/domain-model.md §1.2`.

**Account ID (`account_id`)**  
A UUID binary that uniquely and permanently identifies an account. Assigned at creation.
Never recycled.

**Active (account status)**  
The normal operating state of an account. Debits and credits are permitted.

**Active (party status)**  
The normal operating state of a party. The party may own accounts and initiate transfers.

**Adjustment**  
A transaction type (`txn_type = adjustment`) used for manual balance corrections.
Out of scope for the prototype; reserved for future use.

**Amount**  
Always an integer in minor units. `100` = $1.00 USD. Never a float. See `ADR-003`.

---

## B

**Balance**  
The current integer value (minor units) on an `account` record. Updated atomically with
every transaction. Always `>= 0`. Not computed from ledger history at runtime.

**Booking / Posting**  
Used interchangeably in IronLedger. The moment a transaction's status moves to `posted`
and its ledger entries are written. The `posted_at` timestamp is set at this moment.

---

## C

**Closed (account/party status)**  
Terminal status. No further operations are permitted. An account must have a zero balance
before it can be closed. A party must have no active accounts before it can be closed.

**Credit**  
A ledger entry that increases an account's balance. In a transfer, the destination account
receives a credit entry.

**Currency**  
An ISO 4217 atom (`'USD'`, `'EUR'`, `'GBP'`, `'JPY'`, `'CHF'`). Stored as an atom in
Mnesia. Always uppercase. Cross-currency transfers are out of scope for the prototype.

---

## D

**Debit**  
A ledger entry that decreases an account's balance. In a transfer, the source account
receives a debit entry.

**Deposit**  
A transaction type (`txn_type = deposit`) that credits an account with no source account.
Represents money entering the system from an external source.

**Double-Entry**  
The accounting principle that every financial event produces two ledger entries of equal
value: one debit and one credit. The sum of all debits always equals the sum of all credits.
Enforced by IronLedger as an invariant. See `ADR-002`.

---

## E

**Entry / Ledger Entry**  
A single immutable record of a monetary movement on an account. Every entry has a type
(`debit` or `credit`), an amount (integer, minor units), and a parent `txn_id`.
Entries are never updated or deleted.

---

## F

**Failed (transaction status)**  
A transaction that was submitted but could not be posted (e.g. insufficient funds,
validation error). A failed transaction has no ledger entries. Terminal status.

**Freeze / Frozen**  
An account in `frozen` status cannot be debited or credited. The freeze is reversible
(unlike closure). Used to temporarily block activity on an account.

---

## I

**Idempotency Key**  
A client-supplied opaque binary that identifies a unique intended operation. Submitting
the same key twice returns the original result without re-executing the operation.
Required on all transaction submission endpoints. See `ADR-006`.

**ISO 4217**  
The international standard for currency codes. IronLedger uses three-letter uppercase
atoms: `'USD'`, `'EUR'`, `'GBP'`, `'JPY'`, `'CHF'`.

---

## L

**Ledger**  
The complete, immutable record of all financial events. Implemented as the `ledger_entry`
Mnesia table. Distinct from the account balance (which is a derived running total).

---

## M

**Minor Units**  
The smallest denomination of a currency. For USD/EUR/GBP/CHF: cents (1/100 of the base unit).
For JPY: the yen itself (no minor unit). All amounts in IronLedger are expressed in minor units.

---

## P

**Party**  
A legal or natural person who can own accounts. The top-level customer entity.
Not to be confused with "counterparty" (which is not a concept in the prototype).

**Party ID (`party_id`)**  
A UUID binary uniquely identifying a party. Assigned at creation. Never changes.

**Pending (transaction status)**  
A transaction that has been created but not yet posted. In the prototype, the
`pending → posted` transition happens synchronously within the same request.

**Posted (transaction status)**  
A transaction that has been committed: balances updated and ledger entries written.
A posted transaction is immutable (it can only be reversed, not edited).

---

## R

**Reversal**  
A new transaction (also type `transfer` or `adjustment`) that exactly undoes a posted
transaction by creating equal and opposite ledger entries. The original transaction status
moves to `reversed`. Both the original and reversal records remain in the ledger.

---

## S

**Settlement**  
The process of exchanging funds between financial institutions to finalise a transfer.
**Out of scope for the prototype.** IronLedger treats all accounts as being within the
same ledger; there is no inter-bank settlement concept.

**Source Account**  
The account that is debited in a transfer or withdrawal. `source_account_id` in the
transaction record.

**Suspended (party status)**  
A party that cannot initiate new transfers. Existing accounts remain active and can still
receive credits. The party can be unsuspended (returned to `active`).

---

## T

**Transaction**  
A complete, atomic financial event that moves money between accounts or into/out of the
system. Every transaction has a type, status, amount, currency, and idempotency key.
Parent of one or more ledger entry pairs.

**Transfer**  
A transaction type (`txn_type = transfer`) that moves money from one account to another
within IronLedger. Both accounts must be in the same currency.

---

## U

**UUID**  
Universally Unique Identifier. Used as primary keys for all entities. Stored as a binary
in Mnesia. Format: `<<"xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx">>`.

---

## W

**Withdrawal**  
A transaction type (`txn_type = withdrawal`) that debits an account with no destination
account. Represents money leaving the system to an external destination.

---

## Out of Scope Terms

The following terms appear in general banking literature but are **not implemented** in
the IronLedger prototype. If an agent encounters a requirement involving these, it must
flag it as out of scope rather than implementing a partial version.

| Term | Why out of scope |
|------|-----------------|
| Settlement | Inter-bank clearing not modelled |
| FX / Foreign exchange | Cross-currency transfers deferred |
| Interest | Interest calculation engine deferred |
| Fees | Fee schedule engine deferred |
| KYC / AML | Regulatory compliance deferred |
| Authentication | Auth layer deferred |
| Overdraft | Negative balances are forbidden |
| Hold / Reservation | Balance reservation not implemented |
| Scheduled payment | Recurring/future payments deferred |