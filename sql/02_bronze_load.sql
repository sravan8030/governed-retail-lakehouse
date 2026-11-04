
create volume if not exists retail.bronze.landing;
COMMENT on volume retail.bronze.landing is 'Raw source files as received, before loading to Bronze tables';
describe volume retail.bronze.landing;

list '/Volumes/retail/bronze/landing'; 

select * 
from read_files('/Volumes/retail/bronze/landing/*.csv', format => 'csv', header => true, infercolumntypes=>false )
Limit 20;

--drop table if exists retail.bronze.transactions;

create table if not exists retail.bronze.transactions (
  invoice        STRING    COMMENT 'Invoice number as received; values starting with C are cancellations',
  stock_code     STRING    COMMENT 'Product code as received; some codes are non-product (e.g. postage)',
  description    STRING    COMMENT 'Product description as received',
  quantity       STRING    COMMENT 'Units on the invoice line as received; negative values are returns',
  invoice_date   STRING    COMMENT 'Invoice date and time as received',
  price          STRING    COMMENT 'Unit price as received',
  customer_id    STRING    COMMENT 'Customer identifier as received; may be blank; personal data',
  country        STRING    COMMENT 'Customer country as received',
  _source_file   STRING    COMMENT 'Landing file the row was loaded from',
  _loaded_at     TIMESTAMP COMMENT 'When the row was loaded into Bronze',
  _rescued_data STRING COMMENT 'Source values that did not fit the expected structure, kept as JSON; non-null = investigate'
) 
COMMENT 'Online Retail II transactions exactly as received, plus load metadata';


insert OVERWRITE retail.bronze.transactions 
SELECT
  CAST(Invoice AS STRING),
  CAST(StockCode AS STRING),
  CAST(Description AS STRING),
  CAST(Quantity AS STRING),
  CAST(InvoiceDate AS STRING),
  CAST(Price AS STRING),
  CAST(`Customer ID` AS STRING),
  CAST(Country AS STRING),
  _metadata.file_name,
  current_timestamp(),
  _rescued_data
FROM read_files('/Volumes/retail/bronze/landing/*.csv', format => 'csv', header => true);


describe table retail.bronze.transactions;


SELECT
  MAX(LENGTH(Invoice))       AS max_invoice,
  MAX(LENGTH(StockCode))     AS max_stock_code,
  MAX(LENGTH(Description))   AS max_description,
  MAX(LENGTH(Quantity))      AS max_quantity,
  MAX(LENGTH(InvoiceDate))  AS max_invoice_date,
  MAX(LENGTH(Price))         AS max_price,
  MAX(LENGTH(`Customer ID`)) AS max_customer_id,
  MAX(LENGTH(Country))       AS max_country
FROM read_files('/Volumes/retail/bronze/landing/*.csv', format => 'csv', header => true);

SELECT
  MIN(LENGTH(invoice))       AS min_invoice,     MAX(LENGTH(invoice))       AS max_invoice,
  MIN(LENGTH(stock_code))    AS min_stock_code,  MAX(LENGTH(stock_code))    AS max_stock_code,
  MAX(LENGTH(description))   AS max_description,
  MAX(LENGTH(quantity))      AS max_quantity,
  MAX(LENGTH(invoice_date))  AS max_invoice_date,
  MAX(LENGTH(price))         AS max_price,
  MIN(LENGTH(customer_id))   AS min_customer_id, MAX(LENGTH(customer_id))   AS max_customer_id,
  MAX(LENGTH(country))       AS max_country
FROM retail.bronze.transactions;

-- 1. Reconciliation: expect 525,461 and 541,910
SELECT _source_file, COUNT(*) AS rows
FROM retail.bronze.transactions
GROUP BY _source_file;

-- 2. Total: expect 1,067,371
SELECT COUNT(*) AS total_rows FROM retail.bronze.transactions;

-- 3. Structural DQ: expect 0
SELECT COUNT(*) AS rescued_rows
FROM retail.bronze.transactions
WHERE _rescued_data IS NOT NULL;
