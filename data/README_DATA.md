# Data pack — derivatives-billing-recon

Synthetic data for a broker that earns a fee per contract on exchange-traded
derivatives and bills the clearing banks (clearers) monthly.
All companies, people and figures are fictional. Generated with an AI-assisted
script (`data_generation/generate_data.py`).

**As-of date for all ageing and overdue logic: 2026-11-10**
Period: trades July–October 2026. Currency: EUR only.

## Tables

| File | Rows | Grain | What it represents |
|---|---|---|---|
| `clearers.csv` | 5 | one per clearer | Clearing banks we bill; 30-day payment terms |
| `rate_card.csv` | 9 | one per product | Agreed fee per contract (the "correct" rate) |
| `internal_trades.csv` | 2,000 | one per trade | Our own trade blotter — what we believe we executed and should bill |
| `clearer_statement.csv` | 1,990 | one per statement line | What the clearers report (like an Atlantis/clearer feed) |
| `invoices.csv` | 20 | clearer × month | Monthly invoices, billed from the internal blotter |
| `payments.csv` | 13 | one per cash receipt | Money received from clearers |
| `collection_log.csv` | 8 | one per contact | Calls/emails chasing overdue invoices, incl. payment promises |
| `answer_key_trades.csv` | 80 | one per planted break | **Don't open until your recon SQL is done** |
| `answer_key_cash.csv` | 10 | one per planted cash issue | **Don't open until your receivables SQL is done** |

## Keys and joins

- `internal_trades.trade_id` ↔ `clearer_statement.trade_id` (the reconciliation join)
- `*.product_code` → `rate_card.product_code`
- `*.clearer_code` → `clearers.clearer_code`
- `invoices.invoice_id` ↔ `payments.invoice_id` and `collection_log.invoice_id`
- Invoice = sum of `internal_trades.fee_eur` per clearer per `trade_date` month

## Columns worth knowing

- `fee_eur` = `contracts` × `rate_per_contract_eur`
- `account` — the client account at the clearer, format `HAL-ACC-01`
- `invoices.due_date` = `issue_date` + 30 days
- `payments.invoice_id` — **can be empty**: cash received without an invoice reference
- `collection_log.outcome` — `Promised`, `Disputed`, `No response`, `Says paid`
- `collection_log.promised_date` / `promised_amount_eur` — **empty** unless outcome is `Promised`

## What you should find (types only — details are in the answer keys)

Trade breaks: missing on the clearer side, missing on our side, quantity mismatch,
rate mismatch, reallocation (different account or different clearer).
Cash issues: short payments, late payment, unpaid overdue invoices, unapplied cash,
broken payment promises.
