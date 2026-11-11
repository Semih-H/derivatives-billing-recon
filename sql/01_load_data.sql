-- =====================================================================
-- 01_load_data.sql  (postgresql, run in psql / "SQL Shell (psql)")
--
-- \copy is a psql command: it reads the files from YOUR computer,
-- so no server file permissions are needed.
-- BEFORE RUNNING: replace C:/Users/YOURNAME with your real path.
-- In csv format, empty fields are loaded as null automatically.
-- =====================================================================

truncate clearers, rate_card, internal_trades, clearer_statement, invoices,
         payments, collection_log, answer_key_trades, answer_key_cash;

\copy clearers          from 'C:/Users/semih/Documents/derivatives-billing-recon/data/clearers.csv'          with (format csv, header true)
\copy rate_card         from 'C:/Users/semih/Documents/derivatives-billing-recon/data/rate_card.csv'         with (format csv, header true)
\copy internal_trades   from 'C:/Users/semih/Documents/derivatives-billing-recon/data/internal_trades.csv'   with (format csv, header true)
\copy clearer_statement from 'C:/Users/semih/Documents/derivatives-billing-recon/data/clearer_statement.csv' with (format csv, header true)
\copy invoices          from 'C:/Users/semih/Documents/derivatives-billing-recon/data/invoices.csv'          with (format csv, header true)
\copy payments          from 'C:/Users/semih/Documents/derivatives-billing-recon/data/payments.csv'          with (format csv, header true)
\copy collection_log    from 'C:/Users/semih/Documents/derivatives-billing-recon/data/collection_log.csv'    with (format csv, header true)
\copy answer_key_trades from 'C:/Users/semih/Documents/derivatives-billing-recon/data/answer_key_trades.csv' with (format csv, header true)
\copy answer_key_cash   from 'C:/Users/semih/Documents/derivatives-billing-recon/data/answer_key_cash.csv'   with (format csv, header true)

-- check: every row should say OK
select 'clearers' as tbl, count(*) as loaded, 5 as expected,
       case when count(*) = 5 then 'OK' else 'CHECK' end as status from clearers
union all select 'rate_card',         count(*), 9,    case when count(*) = 9    then 'OK' else 'CHECK' end from rate_card
union all select 'internal_trades',   count(*), 2000, case when count(*) = 2000 then 'OK' else 'CHECK' end from internal_trades
union all select 'clearer_statement', count(*), 1990, case when count(*) = 1990 then 'OK' else 'CHECK' end from clearer_statement
union all select 'invoices',          count(*), 20,   case when count(*) = 20   then 'OK' else 'CHECK' end from invoices
union all select 'payments',          count(*), 13,   case when count(*) = 13   then 'OK' else 'CHECK' end from payments
union all select 'collection_log',    count(*), 8,    case when count(*) = 8    then 'OK' else 'CHECK' end from collection_log
union all select 'answer_key_trades', count(*), 80,   case when count(*) = 80   then 'OK' else 'CHECK' end from answer_key_trades
union all select 'answer_key_cash',   count(*), 10,   case when count(*) = 10   then 'OK' else 'CHECK' end from answer_key_cash;
