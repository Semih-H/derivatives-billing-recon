-- =====================================================================
-- 00_create_tables.sql  (postgresql)
-- run while connected to the billing_recon database
-- safe to re-run: drops views and tables first (cascade)
-- =====================================================================

drop table if exists answer_key_cash, answer_key_trades, collection_log, payments,
                     invoices, clearer_statement, internal_trades, rate_card, clearers cascade;

-- reference data -------------------------------------------------------

create table clearers (
    clearer_code        char(3)       primary key,
    clearer_name        varchar(100)  not null,
    payment_terms_days  integer       not null
);

create table rate_card (
    product_code           varchar(10)   primary key,
    product_name           varchar(50)   not null,
    exchange               varchar(10)   not null,
    instrument_type        varchar(10)   not null,
    asset_class            varchar(20)   not null,
    rate_per_contract_eur  numeric(8,2)  not null
);

-- trade data: our side vs the clearer's side ---------------------------

create table internal_trades (
    trade_id               varchar(20)    primary key,
    trade_date             date           not null,
    clearer_code           char(3)        not null,
    account                varchar(20)    not null,
    product_code           varchar(10)    not null,
    contracts              integer        not null,
    rate_per_contract_eur  numeric(8,2)   not null,
    fee_eur                numeric(12,2)  not null
);

create table clearer_statement (
    stmt_line_id           varchar(10)    primary key,
    trade_id               varchar(20)    not null,
    trade_date             date           not null,
    clearer_code           char(3)        not null,
    account                varchar(20)    not null,
    product_code           varchar(10)    not null,
    contracts              integer        not null,
    rate_per_contract_eur  numeric(8,2)   not null,
    fee_eur                numeric(12,2)  not null
);

create index idx_stmt_trade_id on clearer_statement (trade_id);

-- cash side --------------------------------------------------------------

create table invoices (
    invoice_id     varchar(20)    primary key,
    clearer_code   char(3)        not null,
    billing_month  char(7)        not null,   -- e.g. 2026-07
    trade_count    integer        not null,
    amount_eur     numeric(12,2)  not null,
    issue_date     date           not null,
    due_date       date           not null
);

create table payments (
    payment_id         varchar(10)    primary key,
    clearer_code       char(3)        not null,
    invoice_id         varchar(20)    null,       -- null = cash without invoice reference
    payment_reference  varchar(50)    not null,
    payment_date       date           not null,
    amount_eur         numeric(12,2)  not null
);

create table collection_log (
    log_id               varchar(10)    primary key,
    clearer_code         char(3)        not null,
    invoice_id           varchar(20)    not null,
    contact_date         date           not null,
    channel              varchar(10)    not null,
    contact_person       varchar(50)    not null,
    outcome              varchar(20)    not null,
    promised_date        date           null,     -- only when outcome = 'Promised'
    promised_amount_eur  numeric(12,2)  null,
    notes                varchar(255)   null
);

-- answer keys (used only to validate the sql) ----------------------------

create table answer_key_trades (
    trade_id    varchar(20)   primary key,
    break_type  varchar(30)   not null,
    detail      varchar(255)  null
);

create table answer_key_cash (
    item_id     varchar(20)   not null,
    issue_type  varchar(30)   not null,
    detail      varchar(255)  null,
    primary key (item_id, issue_type)
);
