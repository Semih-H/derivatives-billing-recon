-- =====================================================================
-- 01_load_data.sql  (postgresql, run in psql / "SQL Shell (psql)")
--
-- \copy is a psql command: it reads the files from YOUR computer,
-- so no server file permissions are needed.
-- BEFORE RUNNING: check that C:/Users/semih matches your real path.
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

-- check: one row of counts; compare with 5 / 9 / 2000 / 1990 / 20 / 13 / 8 / 80 / 10
select
    (select count(*) from clearers)          as clearers,
    (select count(*) from rate_card)         as rate_card,
    (select count(*) from internal_trades)   as internal_trades,
    (select count(*) from clearer_statement) as clearer_statement,
    (select count(*) from invoices)          as invoices,
    (select count(*) from payments)          as payments,
    (select count(*) from collection_log)    as collection_log,
    (select count(*) from answer_key_trades) as answer_key_trades,
    (select count(*) from answer_key_cash)   as answer_key_cash;
