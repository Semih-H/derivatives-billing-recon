-- =====================================================================
-- 03_receivables.sql  (postgresql)
-- aging (q7), dso (q8), collection worklist (q9), cash validation (q10)
-- as-of date for all logic: 2026-11-10
-- =====================================================================

-- q7a: aging per open invoice
-- postgresql: subtracting two dates gives the number of days (no datediff)
create or replace view v_aging as
select
    invoice_id,
    clearer_code,
    billing_month,
    open_eur,
    due_date,
    date '2026-11-10' - due_date as days_past_due,
    case
        when date '2026-11-10' - due_date <= 0  then 'Not due'
        when date '2026-11-10' - due_date <= 30 then '1-30'
        when date '2026-11-10' - due_date <= 60 then '31-60'
        when date '2026-11-10' - due_date <= 90 then '61-90'
        else '90+'
    end as aging_bucket,
    case
        when date '2026-11-10' - due_date <= 0  then 0
        when date '2026-11-10' - due_date <= 30 then 1
        when date '2026-11-10' - due_date <= 60 then 2
        when date '2026-11-10' - due_date <= 90 then 3
        else 4
    end as bucket_order
from v_invoice_status
where open_eur > 0;

-- q7b: aging summary per clearer (one column per bucket)
select
    clearer_code,
    sum(case when aging_bucket = 'Not due' then open_eur else 0 end) as not_due,
    sum(case when aging_bucket = '1-30'    then open_eur else 0 end) as d1_30,
    sum(case when aging_bucket = '31-60'   then open_eur else 0 end) as d31_60,
    sum(case when aging_bucket = '61-90'   then open_eur else 0 end) as d61_90,
    sum(case when aging_bucket = '90+'     then open_eur else 0 end) as d90_plus,
    sum(open_eur) as total_open
from v_aging
group by clearer_code
order by total_open desc;


-- q8: days sales outstanding (dso) per clearer, as a view for power bi
-- billing period jul 1 – oct 31 2026 = 123 days
create or replace view v_dso as
select
    clearer_code,
    sum(amount_eur) as billed_eur,
    sum(open_eur)   as open_eur,
    round(sum(open_eur) / sum(amount_eur) * 123, 1) as dso_days
from v_invoice_status
group by clearer_code;

select * from v_dso order by dso_days desc;


-- q9: collection worklist — one row per overdue invoice, with next action
create or replace view v_collection_worklist as
with contacts as (
    -- how often and how recently we chased each invoice
    select invoice_id, count(*) as contact_count, max(contact_date) as last_contact_date
    from collection_log
    group by invoice_id
),
promises as (
    -- the latest payment date each clearer promised
    select invoice_id, max(promised_date) as latest_promised_date
    from collection_log
    where outcome = 'Promised'
    group by invoice_id
),
disputes as (
    -- invoices the clearer has disputed
    select distinct invoice_id
    from collection_log
    where outcome = 'Disputed'
),
unapplied as (
    -- cash received without an invoice reference (q6)
    select payment_id, clearer_code, amount_eur
    from payments
    where invoice_id is null
)
select
    a.invoice_id,
    a.clearer_code,
    c.clearer_name,
    a.open_eur,
    a.days_past_due,
    a.aging_bucket,
    ct.contact_count,
    ct.last_contact_date,
    pr.latest_promised_date,
    case
        when pr.latest_promised_date < date '2026-11-10' then 'YES'
        else 'NO'
    end as broken_promise,
    un.payment_id as matching_payment,
    case
        when un.payment_id is not null then 1
        when ds.invoice_id is not null then 2
        when pr.latest_promised_date < date '2026-11-10' then 3
        when pr.latest_promised_date >= date '2026-11-10' then 5
        else 4
    end as priority,
    case
        when un.payment_id is not null then 'Apply unreferenced payment, then close'
        when ds.invoice_id is not null then 'Resolve rate dispute with Sales / Client Management'
        when pr.latest_promised_date < date '2026-11-10' then 'Escalate: payment promise broken'
        when pr.latest_promised_date >= date '2026-11-10' then 'Wait: promise not yet due'
        else 'Call clearer'
    end as next_action
from v_aging as a
join clearers as c on c.clearer_code = a.clearer_code
left join contacts as ct on ct.invoice_id = a.invoice_id
left join promises as pr on pr.invoice_id = a.invoice_id
left join disputes as ds on ds.invoice_id = a.invoice_id
left join unapplied as un on un.clearer_code = a.clearer_code
                         and un.amount_eur = a.open_eur
where a.days_past_due > 0;

-- quick check
select invoice_id, clearer_code, open_eur, days_past_due, broken_promise, priority, next_action
from v_collection_worklist
order by priority, open_eur desc;


-- q10: validate cash-side findings against the answer key
with findings as (
    -- invoice payment problems (except the one explained by unapplied cash)
    select invoice_id as item_id, payment_status as issue_type
    from v_invoice_status
    where payment_status in ('SHORT_PAID', 'PAID_LATE', 'UNPAID_OVERDUE')
      and invoice_id not in (select invoice_id
                             from v_collection_worklist
                             where matching_payment is not null)
    union all
    -- invoice that has a matching unreferenced payment
    select invoice_id, 'UNAPPLIED_CASH_MATCH'
    from v_collection_worklist
    where matching_payment is not null
    union all
    -- the unreferenced payment itself
    select payment_id, 'UNAPPLIED_CASH'
    from payments
    where invoice_id is null
    union all
    -- broken payment promises
    select invoice_id, 'BROKEN_PROMISE'
    from v_collection_worklist
    where broken_promise = 'YES'
)
select
    (select count(*) from answer_key_cash) as planted_issues,

    (select count(*)
     from findings as f
     join answer_key_cash as k on k.item_id = f.item_id
                              and k.issue_type = f.issue_type) as correct,

    (select count(*)
     from answer_key_cash as k
     left join findings as f on f.item_id = k.item_id
                            and f.issue_type = k.issue_type
     where f.item_id is null) as missed,

    (select count(*)
     from findings as f
     left join answer_key_cash as k on k.item_id = f.item_id
                                   and k.issue_type = f.issue_type
     where k.item_id is null) as false_alarms;
