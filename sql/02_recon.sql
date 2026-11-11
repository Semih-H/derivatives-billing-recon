-- =====================================================================
-- 02_recon.sql  (postgresql)
-- trade reconciliation (q1-q4) and cash reconciliation (q5-q6)
-- =====================================================================

-- q1: match overview
-- postgresql has full outer join, so one query replaces the three-part union
select
    case
        when s.trade_id is null then 'only_internal'
        when i.trade_id is null then 'only_clearer'
        else 'matched'
    end as match_status,
    count(*) as trades
from internal_trades as i
full outer join clearer_statement as s on s.trade_id = i.trade_id
group by match_status
order by trades desc;


-- q2: field-level comparison of matched trades
select
    i.trade_id,
    i.clearer_code          as clearer_internal,
    s.clearer_code          as clearer_statement,
    i.account               as account_internal,
    s.account               as account_statement,
    i.contracts             as contracts_internal,
    s.contracts             as contracts_statement,
    i.rate_per_contract_eur as rate_internal,
    s.rate_per_contract_eur as rate_statement,
    case
        when i.clearer_code <> s.clearer_code or i.account <> s.account then 'REALLOCATION'
        when i.contracts <> s.contracts then 'QTY_MISMATCH'
        when i.rate_per_contract_eur <> s.rate_per_contract_eur then 'RATE_MISMATCH'
    end as break_type,
    i.fee_eur - s.fee_eur   as fee_diff_eur
from internal_trades as i
join clearer_statement as s on s.trade_id = i.trade_id
where i.clearer_code <> s.clearer_code
   or i.account <> s.account
   or i.contracts <> s.contracts
   or i.rate_per_contract_eur <> s.rate_per_contract_eur
order by break_type, i.trade_id;


-- q3: one saved view with every trade break
create or replace view v_recon_breaks as

-- part a: matched trades with a field difference
select
    i.trade_id,
    i.trade_date,
    i.clearer_code,
    i.product_code,
    case
        when i.clearer_code <> s.clearer_code or i.account <> s.account then 'REALLOCATION'
        when i.contracts <> s.contracts then 'QTY_MISMATCH'
        else 'RATE_MISMATCH'
    end as break_type,
    case
        when i.clearer_code <> s.clearer_code or i.account <> s.account
            then concat(i.clearer_code, '/', i.account, ' -> ', s.clearer_code, '/', s.account)
        when i.contracts <> s.contracts
            then concat('contracts ', i.contracts, ' vs ', s.contracts)
        else concat('rate ', i.rate_per_contract_eur, ' vs ', s.rate_per_contract_eur)
    end as detail,
    i.fee_eur as fee_internal_eur,
    s.fee_eur as fee_statement_eur,
    i.fee_eur - s.fee_eur as fee_diff_eur
from internal_trades as i
join clearer_statement as s on s.trade_id = i.trade_id
where i.clearer_code <> s.clearer_code
   or i.account <> s.account
   or i.contracts <> s.contracts
   or i.rate_per_contract_eur <> s.rate_per_contract_eur

union all

-- part b: on our blotter, missing from the clearer statement
select
    i.trade_id,
    i.trade_date,
    i.clearer_code,
    i.product_code,
    'MISSING_IN_CLEARER',
    'not on clearer statement',
    i.fee_eur,
    null,
    i.fee_eur
from internal_trades as i
left join clearer_statement as s on s.trade_id = i.trade_id
where s.trade_id is null

union all

-- part c: on the clearer statement, missing from our blotter
select
    s.trade_id,
    s.trade_date,
    s.clearer_code,
    s.product_code,
    'MISSING_INTERNAL',
    'not on internal blotter',
    null,
    s.fee_eur,
    -s.fee_eur
from clearer_statement as s
left join internal_trades as i on i.trade_id = s.trade_id
where i.trade_id is null;

-- quick check: breaks per type
select break_type, count(*) as trades, sum(fee_diff_eur) as fee_diff_eur
from v_recon_breaks
group by break_type
order by trades desc;


-- q4: validate the reconciliation against the answer key
select
    (select count(*)
     from answer_key_trades) as planted_breaks,

    (select count(*)
     from v_recon_breaks as b
     join answer_key_trades as k on k.trade_id = b.trade_id
                                and k.break_type = b.break_type) as correct,

    (select count(*)
     from v_recon_breaks as b
     join answer_key_trades as k on k.trade_id = b.trade_id
                                and k.break_type <> b.break_type) as wrong_type,

    (select count(*)
     from answer_key_trades as k
     left join v_recon_breaks as b on b.trade_id = k.trade_id
     where b.trade_id is null) as missed,

    (select count(*)
     from v_recon_breaks as b
     left join answer_key_trades as k on k.trade_id = b.trade_id
     where k.trade_id is null) as false_alarms;


-- =====================================================================
-- cash reconciliation
-- =====================================================================

-- q5: invoice-level cash reconciliation (as-of date: 2026-11-10)
create or replace view v_invoice_status as
with paid as (
    -- step 1: total paid per invoice
    select
        invoice_id,
        sum(amount_eur)   as paid_eur,
        max(payment_date) as last_payment_date
    from payments
    where invoice_id is not null
    group by invoice_id
)
-- step 2: attach payments to every invoice and label it
select
    inv.invoice_id,
    inv.clearer_code,
    inv.billing_month,
    inv.amount_eur,
    pd.paid_eur,
    case
        when pd.paid_eur is null then inv.amount_eur
        else inv.amount_eur - pd.paid_eur
    end as open_eur,
    inv.due_date,
    pd.last_payment_date,
    case
        when pd.paid_eur is null and inv.due_date >= date '2026-11-10' then 'NOT_DUE'
        when pd.paid_eur is null then 'UNPAID_OVERDUE'
        when pd.paid_eur < inv.amount_eur then 'SHORT_PAID'
        when pd.last_payment_date > inv.due_date then 'PAID_LATE'
        else 'PAID'
    end as payment_status
from invoices as inv
left join paid as pd on pd.invoice_id = inv.invoice_id;

-- quick check
select payment_status, count(*) as invoices, sum(open_eur) as open_eur
from v_invoice_status
group by payment_status
order by open_eur desc;


-- q6: unapplied cash — suggest which open invoice each payment belongs to
select
    p.payment_id,
    p.clearer_code,
    p.payment_reference,
    p.payment_date,
    p.amount_eur,
    st.invoice_id     as suggested_invoice,
    st.payment_status as invoice_status
from payments as p
left join v_invoice_status as st
    on st.clearer_code = p.clearer_code
   and st.open_eur = p.amount_eur
where p.invoice_id is null;
