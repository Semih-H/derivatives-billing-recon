-- 04_export_outputs.sql (run in psql)
-- writes the result views to output\ for power bi and the python notebook

\copy (select * from v_recon_breaks)        to 'C:/Users/semih/Documents/derivatives-billing-recon/output/recon_breaks.csv'        with (format csv, header true)
\copy (select * from v_invoice_status)      to 'C:/Users/semih/Documents/derivatives-billing-recon/output/invoice_status.csv'      with (format csv, header true)
\copy (select * from v_aging)               to 'C:/Users/semih/Documents/derivatives-billing-recon/output/aging.csv'               with (format csv, header true)
\copy (select * from v_collection_worklist) to 'C:/Users/semih/Documents/derivatives-billing-recon/output/collection_worklist.csv' with (format csv, header true)
\copy (select * from v_dso)                 to 'C:/Users/semih/Documents/derivatives-billing-recon/output/dso.csv'                 with (format csv, header true)